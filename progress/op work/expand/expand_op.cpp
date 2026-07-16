/**
 * @file expand_op.cpp
 * @brief Expand 算子核心实现：STB/LDB 数据搬运版本。
 */

#include "expand_op.h"

#include <algorithm>
#include <cstring>
#include <stdexcept>

#include "../../app/fp16_utils.h"
#include "../common/lsu_v2_packer.h"
#include "../common/v421_iq_adapter.h"
#include "iq/modules/ds_iq.h"

namespace aiacc {
namespace op {

namespace {
constexpr uint32_t kUrWordBytes = 16;
constexpr uint32_t kUrBankAddrStride = 0x1000;
constexpr uint32_t kMaxUrWords = 256;
constexpr uint32_t kIqIdUrR0 = 14;
constexpr uint32_t kIqIdUrW0 = 18;
constexpr uint32_t kIqIdRtovr35 = 59;
constexpr uint8_t kRtovrOutWdata0 = 35;
constexpr uint8_t kRtovrInUrRdata0 = 30;

// v4.19 / release testbench layout: STB=24, LDB=26.
constexpr uint32_t kIqIdStb = 24;
constexpr uint32_t kIqIdLdb = 26;

void append_scalar(std::vector<uint8_t>& bin, float value, app::AppDataType dtype) {
    if (dtype == app::AppDataType::FLOAT16) {
        uint16_t bits = app::float32_to_float16(value);
        bin.push_back(bits & 0xFF);
        bin.push_back((bits >> 8) & 0xFF);
    } else {
        uint32_t bits;
        std::memcpy(&bits, &value, sizeof(float));
        bin.push_back(bits & 0xFF);
        bin.push_back((bits >> 8) & 0xFF);
        bin.push_back((bits >> 16) & 0xFF);
        bin.push_back((bits >> 24) & 0xFF);
    }
}

void write_tensor_data(std::vector<uint8_t>& bin, const app::AppTensorDesc& tensor) {
    for (float v : tensor.para_data_f32) {
        append_scalar(bin, v, tensor.para_dtype);
    }
}

uint64_t pack_lsu_header(uint16_t loops, uint8_t dly, uint16_t inc_bytes) {
    // Header layout from fields_iq_stb/ldb:
    // VLD(1), JUMP(1), EMBED(3), EMBED_END(6), LOOPS(10),
    // COND(7), DLY(3), INC(13), INC_EMBED(6) = 50 bits.
    uint64_t h = 0;
    h = (h << 1) | 1u;                         // VLD
    h = (h << 1) | 0u;                         // JUMP
    h = (h << 3) | 0u;                         // EMBED
    h = (h << 6) | 0u;                         // EMBED_END
    h = (h << 10) | (loops & 0x3FFu);          // LOOPS
    h = (h << 7) | 0u;                         // COND
    h = (h << 3) | (dly & 0x7u);               // DLY
    h = (h << 13) | (inc_bytes & 0x1FFFu);     // INC
    h = (h << 6) | 0u;                         // INC_EMBED
    return h;
}

void append_big_endian(std::vector<uint8_t>& out, unsigned __int128 value, int num_bytes) {
    for (int i = num_bytes - 1; i >= 0; --i) {
        out.push_back(static_cast<uint8_t>((value >> (i * 8)) & 0xFF));
    }
}

uint16_t make_ur_addr(uint8_t bank, uint16_t byte_addr) {
    return static_cast<uint16_t>((static_cast<uint16_t>(bank & 0x7u) * kUrBankAddrStride) +
                                 (byte_addr & 0x0FFFu));
}

std::vector<uint8_t> make_stb_instruction(uint32_t words, uint8_t bank, uint16_t byte_addr,
                                          uint8_t tid = 0) {
    const uint16_t loops = static_cast<uint16_t>((words > 0) ? words - 1 : 0);
    const uint64_t header = pack_lsu_header(loops, 0, kUrWordBytes);

    // STB code layout:
    // tid(2), smc_id_en(5), inst_id(4), line_stride(6),
    // line_byte_cnt(9), ur_rd_line_cnt(8), ur_addr(15), vld(1) = 50 bits.
    uint64_t code = 0;
    code = (code << 2) | (tid & 0x3u);               // tid: 00=bypass, 01=DS->LDB
    code = (code << 5) | 0x7u;                       // smc_id_en, same as LSU examples
    code = (code << 4) | 0u;                         // inst_id
    code = (code << 6) | 0u;                         // line_stride
    code = (code << 9) | (kUrWordBytes - 1);         // line_byte_cnt: 16B -> 0xf
    code = (code << 8) | 1u;                         // one UR line per issue
    code = (code << 15) | make_ur_addr(bank, byte_addr);
    code = (code << 1) | 1u;                         // vld

    unsigned __int128 inst = (static_cast<unsigned __int128>(header) << 50) | code;
    std::vector<uint8_t> bytes;
    append_big_endian(bytes, inst, 13);              // 100 bits -> 13 bytes
    return bytes;
}

std::vector<uint8_t> make_ldb_instruction(uint32_t words, uint8_t bank, uint16_t byte_addr) {
    const uint16_t loops = static_cast<uint16_t>((words > 0) ? words - 1 : 0);
    const uint64_t header = pack_lsu_header(loops, 0, kUrWordBytes);

    // LDB code layout:
    // smc_id_en(5), inst_id(4), post_fill(1), pre_fill(1), const(6),
    // line_stride(6), line_byte_cnt(9), ur_wd_line_cnt(8), ur_addr(15), vld(1) = 56 bits.
    uint64_t code = 0;
    code = (code << 5) | 0x7u;                       // smc_id_en
    code = (code << 4) | 0u;                         // inst_id
    code = (code << 1) | 0u;                         // post_fill
    code = (code << 1) | 0u;                         // pre_fill
    code = (code << 6) | 0u;                         // const
    code = (code << 6) | 0u;                         // line_stride
    code = (code << 9) | (kUrWordBytes - 1);         // line_byte_cnt: 16B -> 0xf
    code = (code << 8) | 1u;                         // one UR line per issue
    code = (code << 15) | make_ur_addr(bank, byte_addr);
    code = (code << 1) | 1u;                         // vld

    unsigned __int128 inst = (static_cast<unsigned __int128>(header) << 56) | code;
    std::vector<uint8_t> bytes;
    append_big_endian(bytes, inst, 14);              // 106 bits -> 14 bytes
    return bytes;
}

uint64_t pack_iq_header_41(uint8_t vld, uint8_t jump, uint16_t loops, uint8_t dly, uint8_t inc) {
    uint64_t header = 0;
    uint32_t pos = 0;
    header |= (0ull & 0x3Full) << pos; pos += 6;             // INC_EMBED
    header |= (static_cast<uint64_t>(inc) & 0xFull) << pos; pos += 4;
    header |= (static_cast<uint64_t>(dly) & 0x7ull) << pos; pos += 3;
    header |= (0ull & 0x7Full) << pos; pos += 7;             // COND
    header |= (static_cast<uint64_t>(loops) & 0x3FFull) << pos; pos += 10;
    header |= (0ull & 0x3Full) << pos; pos += 6;             // EMBED_END
    header |= (0ull & 0x7ull) << pos; pos += 3;              // EMBED
    header |= (static_cast<uint64_t>(jump) & 0x1ull) << pos; pos += 1;
    header |= (static_cast<uint64_t>(vld) & 0x1ull) << pos;
    return header;
}

std::vector<uint8_t> make_iq_instruction(uint32_t code_bits, uint64_t code,
                                         uint8_t vld = 1, uint8_t jump = 0,
                                         uint16_t loops = 0, uint8_t dly = 0,
                                         uint8_t inc = 0) {
    unsigned __int128 inst =
        (static_cast<unsigned __int128>(pack_iq_header_41(vld, jump, loops, dly, inc)) << code_bits) |
        static_cast<unsigned __int128>(code & ((code_bits >= 64) ? ~0ull : ((1ull << code_bits) - 1ull)));
    const int bytes = static_cast<int>((41 + code_bits + 7) / 8);
    std::vector<uint8_t> out;
    append_big_endian(out, inst, bytes);
    return out;
}

void append_scheduled_instruction(IqInstructionFile& file, int& last_cycle, uint32_t target_cycle,
                                  uint32_t code_bits, uint64_t code) {
    const uint32_t next_cycle = static_cast<uint32_t>(last_cycle + 1);
    if (target_cycle > next_cycle) {
        const uint32_t gap = target_cycle - next_cycle;
        auto idle = make_iq_instruction(code_bits, 0, 0, 0, static_cast<uint16_t>(gap - 1));
        file.para_data.insert(file.para_data.end(), idle.begin(), idle.end());
    }
    auto inst = make_iq_instruction(code_bits, code);
    file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
    last_cycle = static_cast<int>(target_cycle);
}

void append_terminal_instruction(IqInstructionFile& file, uint32_t code_bits) {
    auto inst = make_iq_instruction(code_bits, 0, 0, 1);
    file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
}

uint32_t make_ur_read_code(uint8_t bank, uint16_t word_addr, uint8_t smc_id_en = 0) {
    return 0x1u |
           ((static_cast<uint32_t>(bank) & 0x7u) << 1) |
           ((static_cast<uint32_t>(word_addr) & 0xFFu) << 4) |
           ((static_cast<uint32_t>(smc_id_en) & 0x1Fu) << 12);
}

uint64_t make_ur_write_code(uint8_t bank, uint16_t word_addr, uint8_t smc_id_en = 0, uint16_t wbe = 0xFFFF) {
    return 0x1ull |
           ((static_cast<uint64_t>(bank) & 0x7ull) << 1) |
           ((static_cast<uint64_t>(word_addr) & 0xFFull) << 4) |
           ((static_cast<uint64_t>(wbe) & 0xFFFFull) << 12) |
           ((static_cast<uint64_t>(smc_id_en) & 0x1Full) << 28);
}

uint64_t make_ds_lane_replicate_code(uint8_t dtype_bits, uint8_t in_beats_m1,
                                     uint8_t out_beats_m1, uint8_t inst_id = 0,
                                     uint8_t smc_id_en = 7) {
    // Sentinel: reshape + t_dim0/t_dim1 = 31.
    iq::DsCru cru{};
    cru.para_vld = true;
    cru.para_op_type = iq::DsOpType::RESHAPE;
    cru.para_data_type = static_cast<iq::DsDataType>(dtype_bits & 0x3u);
    cru.para_r_in_cnt = in_beats_m1;
    cru.para_r_out_cnt = out_beats_m1;
    cru.para_t_dim0_cnt = 31;
    cru.para_t_dim1_cnt = 31;
    cru.para_inst_id = inst_id & 0xFu;
    cru.para_smc_id_en = smc_id_en & 0x1Fu;
    uint32_t words[2] = {0, 0};
    iq::DsIq::pack_cru_ds(cru, words);
    return (static_cast<uint64_t>(words[1] & 0x7Fu) << 32) | words[0];
}

std::vector<uint8_t> make_ds_lane_replicate_instruction(uint8_t dtype_bits,
                                                        uint32_t input_words,
                                                        uint32_t output_words) {
    const uint8_t in_m1 = static_cast<uint8_t>(
        (input_words > 0 ? input_words - 1 : 0) & 0xFFu);
    const uint8_t out_m1 = static_cast<uint8_t>(
        (output_words > 0 ? output_words - 1 : 0) & 0xFFu);
    const uint64_t code = make_ds_lane_replicate_code(dtype_bits, in_m1, out_m1);
    return make_iq_instruction(39, code);
}

uint8_t make_rtovr_code(uint8_t select) {
    return static_cast<uint8_t>(((select & 0x3Fu) << 1) | 0x1u);
}

uint32_t flat_index(uint32_t n, uint32_t c, uint32_t h, uint32_t w,
                    uint32_t channels, uint32_t height, uint32_t width) {
    return ((n * channels + c) * height + h) * width + w;
}

std::vector<uint32_t> normalize_shape_to_nchw(const std::vector<uint32_t>& shape) {
    std::vector<uint32_t> normalized(4, 1);
    if (shape.empty()) return normalized;
    const size_t copy = std::min<size_t>(4, shape.size());
    const size_t src_start = shape.size() - copy;
    const size_t dst_start = 4 - copy;
    for (size_t i = 0; i < copy; ++i) {
        normalized[dst_start + i] = std::max<uint32_t>(1, shape[src_start + i]);
    }
    return normalized;
}

std::vector<uint32_t> normalize_i32_shape_to_nchw(const std::vector<int32_t>& shape) {
    std::vector<uint32_t> u;
    u.reserve(shape.size());
    for (int32_t v : shape) u.push_back(static_cast<uint32_t>(std::max<int32_t>(1, v)));
    return normalize_shape_to_nchw(u);
}

bool is_lane_broadcast_case(const ExpandOpParams& params) {
    auto dim_ok = [](uint32_t in_dim, uint32_t out_dim) {
        return in_dim == 1 || in_dim == out_dim;
    };
    return dim_ok(params.para_input_n, params.para_n) &&
           dim_ok(params.para_input_c, params.para_c) &&
           dim_ok(params.para_input_h, params.para_h) &&
           params.para_input_w == 1 &&
           params.para_w > 1;
}

bool build_native_word_mapping(const ExpandOpParams& params, std::vector<uint16_t>& mapping) {
    mapping.clear();
    const uint32_t elems_per_word = params.get_elems_per_word();
    auto dim_ok = [](uint32_t in_dim, uint32_t out_dim) {
        return in_dim == 1 || in_dim == out_dim;
    };
    if (!dim_ok(params.para_input_n, params.para_n) ||
        !dim_ok(params.para_input_c, params.para_c) ||
        !dim_ok(params.para_input_h, params.para_h) ||
        !dim_ok(params.para_input_w, params.para_w)) {
        return false;
    }
    const bool lane_broadcast = is_lane_broadcast_case(params);
    if (!lane_broadcast &&
        (params.para_input_w != elems_per_word || params.para_w != elems_per_word)) {
        return false;
    }
    const uint32_t output_elems = params.para_n * params.para_c * params.para_h * params.para_w;
    const uint32_t output_words = (output_elems + elems_per_word - 1) / elems_per_word;
    if (output_words > kMaxUrWords) return false;

    if (lane_broadcast) {
        for (uint32_t dst_word = 0; dst_word < output_words; ++dst_word) {
            const uint32_t elem = dst_word * elems_per_word;
            const uint32_t w = elem % params.para_w;
            const uint32_t tmp0 = elem / params.para_w;
            const uint32_t h = tmp0 % params.para_h;
            const uint32_t tmp1 = tmp0 / params.para_h;
            const uint32_t c = tmp1 % params.para_c;
            const uint32_t n = tmp1 / params.para_c;
            (void)w;
            const uint32_t src_n = (params.para_input_n == 1) ? 0 : n;
            const uint32_t src_c = (params.para_input_c == 1) ? 0 : c;
            const uint32_t src_h = (params.para_input_h == 1) ? 0 : h;
            const uint32_t src_scalar =
                ((src_n * params.para_input_c + src_c) * params.para_input_h + src_h);
            mapping.push_back(static_cast<uint16_t>(src_scalar));
        }
        return true;
    }

    for (uint32_t n = 0; n < params.para_n; ++n) {
        for (uint32_t c = 0; c < params.para_c; ++c) {
            for (uint32_t h = 0; h < params.para_h; ++h) {
                const uint32_t src_n = (params.para_input_n == 1) ? 0 : n;
                const uint32_t src_c = (params.para_input_c == 1) ? 0 : c;
                const uint32_t src_h = (params.para_input_h == 1) ? 0 : h;
                const uint32_t src_word = (src_n * params.para_input_c + src_c) * params.para_input_h + src_h;
                mapping.push_back(static_cast<uint16_t>(src_word));
            }
        }
    }
    return true;
}

void append_lsu_v2_files(std::vector<IqInstructionFile>& files,
                         uint32_t input_words,
                         uint32_t output_words,
                         const ExpandOpInstructions& insts) {
    const uint8_t smc_strb =
        static_cast<uint8_t>(std::max<uint8_t>(1, insts.para_lsu_v2_smc_count) - 1);
    if (input_words > 0) {
        IqInstructionFile file;
        file.para_iq_id = lsu_v2::kIqIdLdbV2;
        file.para_iq_name = "ldb_v2";
        file.para_width_bits = lsu_v2::kLdbBits;
        lsu_v2::LsuV2Params p;
        p.smc_strb = smc_strb;
        p.byte_strb = insts.para_lsu_v2_byte_strb;
        p.gr_base_addr = insts.para_lsu_v2_input_gr_base;
        p.smc_id = insts.para_lsu_v2_smc_id;
        p.ur_id = insts.para_lsu_v2_input_ur_id;
        p.ur_addr = static_cast<uint8_t>(insts.para_input_addr_bytes / kUrWordBytes);
        lsu_v2::append_ldb_v2_transfer(file.para_data, p, input_words);
        files.push_back(file);
    }
    if (output_words > 0) {
        IqInstructionFile file;
        file.para_iq_id = lsu_v2::kIqIdStbV2;
        file.para_iq_name = "stb_v2";
        file.para_width_bits = lsu_v2::kStbBits;
        lsu_v2::LsuV2Params p;
        p.smc_strb = smc_strb;
        p.byte_strb = insts.para_lsu_v2_byte_strb;
        p.gr_base_addr = insts.para_lsu_v2_output_gr_base;
        p.smc_id = insts.para_lsu_v2_smc_id;
        p.ur_id = insts.para_lsu_v2_output_ur_id;
        p.ur_addr = static_cast<uint8_t>(insts.para_output_addr_bytes / kUrWordBytes);
        lsu_v2::append_stb_v2_transfer(file.para_data, p, output_words);
        files.push_back(file);
    }
}

void append_ur_mapping_files(std::vector<IqInstructionFile>& files,
                             const std::vector<uint16_t>& src_words,
                             uint8_t input_bank,
                             uint8_t output_bank) {
    const uint32_t words = std::min<uint32_t>(static_cast<uint32_t>(src_words.size()), kMaxUrWords);
    {
        IqInstructionFile file;
        file.para_iq_id = kIqIdUrR0;
        file.para_iq_name = "ur_rdata_0";
        file.para_width_bits = 41 + 17;
        int last_cycle = -1;
        for (uint32_t dst_word = 0; dst_word < words; ++dst_word) {
            const uint16_t src_word = src_words[dst_word];
            const uint32_t cycle = dst_word * 8;
            const uint32_t code = make_ur_read_code(input_bank, src_word);
            append_scheduled_instruction(file, last_cycle, cycle, 17, code);
        }
        append_terminal_instruction(file, 17);
        files.push_back(file);
    }

    {
        IqInstructionFile file;
        file.para_iq_id = kIqIdRtovr35;
        file.para_iq_name = "rtovr-35";
        file.para_width_bits = 41 + 7;
        int last_cycle = -1;
        const uint8_t code = make_rtovr_code(kRtovrInUrRdata0);
        for (uint32_t dst_word = 0; dst_word < words; ++dst_word) {
            append_scheduled_instruction(file, last_cycle, dst_word * 8 + 5, 7, code);
        }
        append_terminal_instruction(file, 7);
        files.push_back(file);
    }

    {
        IqInstructionFile file;
        file.para_iq_id = kIqIdUrW0;
        file.para_iq_name = "ur_wdata_0";
        file.para_width_bits = 41 + 33;
        int last_cycle = -1;
        for (uint32_t dst_word = 0; dst_word < words; ++dst_word) {
            const uint32_t cycle = dst_word * 8 + 6;
            const uint64_t code = make_ur_write_code(output_bank, static_cast<uint16_t>(dst_word));
            append_scheduled_instruction(file, last_cycle, cycle, 33, code);
        }
        append_terminal_instruction(file, 33);
        files.push_back(file);
    }
}

void append_expanded_tensor_data(std::vector<uint8_t>& bin,
                                 const app::AppTensorDesc& input,
                                 uint32_t out_n, uint32_t out_c, uint32_t out_h, uint32_t out_w) {
    const auto shape = normalize_shape_to_nchw(input.para_shape);
    const uint32_t in_n = shape[0];
    const uint32_t in_c = shape[1];
    const uint32_t in_h = shape[2];
    const uint32_t in_w = shape[3];
    for (uint32_t n = 0; n < out_n; ++n) {
        for (uint32_t c = 0; c < out_c; ++c) {
            for (uint32_t h = 0; h < out_h; ++h) {
                for (uint32_t w = 0; w < out_w; ++w) {
                    const uint32_t src_n = (in_n == 1) ? 0 : n;
                    const uint32_t src_c = (in_c == 1) ? 0 : c;
                    const uint32_t src_h = (in_h == 1) ? 0 : h;
                    const uint32_t src_w = (in_w == 1) ? 0 : w;
                    const uint32_t idx = flat_index(src_n, src_c, src_h, src_w, in_c, in_h, in_w);
                    if (idx < input.para_data_f32.size()) {
                        append_scalar(bin, input.para_data_f32[idx], input.para_dtype);
                    }
                }
            }
        }
    }
}

} // namespace

ExpandOpInstructions ExpandOp::compile(const ExpandOpParams& para_params) {
    ExpandOpInstructions result;
    result.para_dtype = para_params.para_dtype;
    result.para_input_bank = para_params.para_input_bank;
    result.para_input_addr_bytes = para_params.para_input_addr_bytes;
    result.para_output_bank = para_params.para_output_bank;
    result.para_output_addr_bytes = para_params.para_output_addr_bytes;
    result.para_native_broadcast = para_params.para_native_broadcast;
    result.para_lane_broadcast = para_params.para_lane_broadcast;
    result.para_strict_lane_replicate = para_params.para_strict_lane_replicate;
    result.para_enable_lsu_v2 = para_params.para_enable_lsu_v2;
    result.para_lsu_v2_input_gr_base = para_params.para_lsu_v2_input_gr_base;
    result.para_lsu_v2_output_gr_base = para_params.para_lsu_v2_output_gr_base;
    result.para_lsu_v2_input_ur_id = para_params.para_lsu_v2_input_ur_id;
    result.para_lsu_v2_output_ur_id = para_params.para_lsu_v2_output_ur_id;
    result.para_lsu_v2_smc_id = para_params.para_lsu_v2_smc_id;
    result.para_lsu_v2_smc_count = para_params.para_lsu_v2_smc_count;
    result.para_lsu_v2_byte_strb = para_params.para_lsu_v2_byte_strb;

    const uint32_t total_elems = para_params.para_n * para_params.para_c *
                                 para_params.para_h * para_params.para_w;
    const uint32_t input_elems = para_params.para_input_n * para_params.para_input_c *
                                 para_params.para_input_h * para_params.para_input_w;
    const uint32_t elems_per_word = para_params.get_elems_per_word();
    result.para_total_steps = (total_elems + elems_per_word - 1) / elems_per_word;
    result.para_total_elements = total_elems;
    result.para_input_words = para_params.para_lane_broadcast
                                  ? input_elems
                                  : (input_elems + elems_per_word - 1) / elems_per_word;
    if (para_params.para_native_broadcast) {
        if (!build_native_word_mapping(para_params, result.para_native_src_words)) {
            throw std::runtime_error("Expand native broadcast supports word-aligned N/C/H or scalar W lane broadcast");
        }
        result.para_total_steps = static_cast<uint32_t>(result.para_native_src_words.size());
    }
    return result;
}

std::vector<IqInstructionFile> ExpandOpInstructions::get_iq_files() const {
    std::vector<IqInstructionFile> files;
    const uint32_t words = std::min(para_total_steps, kMaxUrWords);

    if (para_strict_lane_replicate) {
        // Native path: scalar UR word --STB(tid=01)--> DS lane-replicate --LDB--> UR out.
        const uint32_t in_words = std::max<uint32_t>(1, para_input_words);
        const uint32_t out_words = std::max<uint32_t>(1, words);
        const uint8_t dtype_bits =
            (para_dtype == ExpandDataType::FP16)
                ? static_cast<uint8_t>(iq::DsDataType::BIT16)
                : static_cast<uint8_t>(iq::DsDataType::BIT32);
        {
            IqInstructionFile file;
            file.para_iq_id = v421::kIqIdDs;
            file.para_iq_name = "ds";
            file.para_width_bits = v421::kBitsDs;
            auto inst = make_ds_lane_replicate_instruction(dtype_bits, in_words, out_words);
            file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
            auto term = make_iq_instruction(39, 0, 0, 1);
            file.para_data.insert(file.para_data.end(), term.begin(), term.end());
            files.push_back(file);
        }
        {
            IqInstructionFile file;
            file.para_iq_id = kIqIdStb;
            file.para_iq_name = "stb";
            file.para_width_bits = 100;
            // tid=01: STB -> DS engine -> LDB
            auto inst = make_stb_instruction(in_words, para_input_bank, para_input_addr_bytes, 1);
            file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
            files.push_back(file);
        }
        {
            IqInstructionFile file;
            file.para_iq_id = kIqIdLdb;
            file.para_iq_name = "ldb";
            file.para_width_bits = 106;
            auto inst = make_ldb_instruction(out_words, para_output_bank, para_output_addr_bytes);
            file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
            files.push_back(file);
        }
        return files;
    }

    if (para_native_broadcast) {
        if (para_enable_lsu_v2) {
            append_lsu_v2_files(files, para_input_words, para_total_steps, *this);
        }
        append_ur_mapping_files(files, para_native_src_words, para_input_bank, para_output_bank);
        return files;
    }

    if (para_enable_lsu_v2) {
        append_lsu_v2_files(files, para_input_words, para_total_steps, *this);
        std::vector<uint16_t> copy_words;
        copy_words.reserve(words);
        for (uint32_t i = 0; i < words; ++i) {
            copy_words.push_back(static_cast<uint16_t>(i));
        }
        append_ur_mapping_files(files, copy_words, para_input_bank, para_output_bank);
        return files;
    }

    {
        IqInstructionFile file;
        file.para_iq_id = kIqIdStb;
        file.para_iq_name = "stb";
        file.para_width_bits = 100;
        auto inst = make_stb_instruction(words, para_input_bank, para_input_addr_bytes);
        file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
        files.push_back(file);
    }

    {
        IqInstructionFile file;
        file.para_iq_id = kIqIdLdb;
        file.para_iq_name = "ldb";
        file.para_width_bits = 106;
        auto inst = make_ldb_instruction(words, para_output_bank, para_output_addr_bytes);
        file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
        files.push_back(file);
    }

    return files;
}

std::string ExpandOp::get_name() const {
    return "Expand";
}

OpInstructionsBase* ExpandOp::compile(const app::AppOperatorRequest& req) {
    ExpandOpParams params;
    params.para_n = req.para_dimensions.para_n;
    params.para_c = req.para_dimensions.para_c;
    params.para_h = req.para_dimensions.para_h;
    params.para_w = req.para_dimensions.para_w;

    if (!req.para_inputs.empty()) {
        const auto& input = req.para_inputs.begin()->second;
        params.para_dtype = (input.para_dtype == app::AppDataType::FLOAT16)
                                ? ExpandDataType::FP16
                                : ExpandDataType::FP32;
        const auto shape = normalize_shape_to_nchw(input.para_shape);
        params.para_input_n = shape[0];
        params.para_input_c = shape[1];
        params.para_input_h = shape[2];
        params.para_input_w = shape[3];
    }

    auto shape_it = req.para_parameters.find("input_shape");
    if (shape_it != req.para_parameters.end() && !shape_it->second.para_data_i32.empty()) {
        const auto shape = normalize_i32_shape_to_nchw(shape_it->second.para_data_i32);
        params.para_input_n = shape[0];
        params.para_input_c = shape[1];
        params.para_input_h = shape[2];
        params.para_input_w = shape[3];
    }

    auto get_i32_param = [&](const std::string& name, int def) {
        auto it = req.para_parameters.find(name);
        if (it != req.para_parameters.end() && !it->second.para_data_i32.empty()) {
            return it->second.para_data_i32[0];
        }
        return def;
    };
    params.para_enable_lsu_v2 = get_i32_param("enable_lsu_v2", 0) != 0;
    params.para_lsu_v2_input_gr_base =
        static_cast<uint64_t>(std::max(0, get_i32_param("lsu_v2_input_gr_base", 0)));
    params.para_lsu_v2_output_gr_base =
        static_cast<uint64_t>(std::max(0, get_i32_param("lsu_v2_output_gr_base", 0x1000)));
    params.para_lsu_v2_input_ur_id =
        static_cast<uint8_t>(std::max(0, get_i32_param("lsu_v2_input_ur_id", params.para_input_bank)) & 0x7);
    params.para_lsu_v2_output_ur_id =
        static_cast<uint8_t>(std::max(0, get_i32_param("lsu_v2_output_ur_id", params.para_output_bank)) & 0x7);
    params.para_lsu_v2_smc_id =
        static_cast<uint8_t>(std::max(0, get_i32_param("smc_id", 0)) & 0x1F);
    params.para_lsu_v2_smc_count =
        static_cast<uint8_t>(std::max(1, get_i32_param("smc_count", 1)) & 0x3F);
    params.para_lsu_v2_byte_strb =
        static_cast<uint8_t>(std::max(0, get_i32_param("lsu_v2_byte_strb", 0)) & 0xF);

    auto input_it = req.para_inputs.find("input_tensor");
    if (input_it != req.para_inputs.end()) {
        const auto shape = normalize_shape_to_nchw(input_it->second.para_shape);
        const bool lane_broadcast =
            shape[3] == 1 && params.para_w > 1 &&
            (shape[0] == 1 || shape[0] == params.para_n) &&
            (shape[1] == 1 || shape[1] == params.para_c) &&
            (shape[2] == 1 || shape[2] == params.para_h);
        params.para_native_broadcast =
            !lane_broadcast &&
            shape[0] == params.para_input_n &&
            shape[1] == params.para_input_c &&
            shape[2] == params.para_input_h &&
            shape[3] == params.para_input_w &&
            (params.para_input_n != params.para_n ||
             params.para_input_c != params.para_c ||
             params.para_input_h != params.para_h ||
             params.para_input_w != params.para_w);
        params.para_lane_broadcast = lane_broadcast;
        if (lane_broadcast && get_i32_param("strict_hardware_path", 0) != 0) {
            // Native DS LANE_REPLICATE: keep scalar input, emit IQ92 + STB(tid=01)+LDB.
            params.para_strict_lane_replicate = true;
            params.para_native_broadcast = false;
        }
    }

    auto* insts = new ExpandOpInstructions();
    *insts = compile(params);
    return insts;
}

bool ExpandOp::calculate_golden(const app::AppOperatorRequest& req,
                                std::vector<uint8_t>& golden_bin) {
    golden_bin.clear();
    auto it = req.para_inputs.find("input_tensor");
    if (it == req.para_inputs.end()) return false;
    {
        const auto shape = normalize_shape_to_nchw(it->second.para_shape);
        const bool materialized =
            shape[0] == req.para_dimensions.para_n &&
            shape[1] == req.para_dimensions.para_c &&
            shape[2] == req.para_dimensions.para_h &&
            shape[3] == req.para_dimensions.para_w;
        if (!materialized) {
            append_expanded_tensor_data(golden_bin, it->second,
                                        req.para_dimensions.para_n,
                                        req.para_dimensions.para_c,
                                        req.para_dimensions.para_h,
                                        req.para_dimensions.para_w);
            return !golden_bin.empty();
        }
    }
    write_tensor_data(golden_bin, it->second);
    return true;
}

void ExpandOp::fill_random_request(app::AppOperatorRequest& req,
                                   std::mt19937& rng,
                                   std::uniform_real_distribution<float>& data_dist,
                                   const std::string& dtype_str) {
    req.para_operator = "Expand";

    app::AppDataType target_type = (dtype_str == "fp16") ? app::AppDataType::FLOAT16
                                                         : app::AppDataType::FLOAT32;
    const uint32_t elems_per_word = (target_type == app::AppDataType::FLOAT16) ? 8 : 4;

    uint32_t out_n = std::max(1u, req.para_dimensions.para_n);
    uint32_t out_c = std::max(1u, req.para_dimensions.para_c);
    uint32_t out_h = std::max(1u, req.para_dimensions.para_h);
    uint32_t out_w = elems_per_word;
    if (req.para_parameters.find("llama_expand") != req.para_parameters.end()) {
        out_n = 1;
        out_c = 1;
        out_h = 1;
        out_w = 32;
    }

    while (out_n * out_c * out_h > kMaxUrWords) {
        if (out_n > 1) out_n--;
        else if (out_c > 1) out_c--;
        else if (out_h > 1) out_h--;
        else break;
    }

    req.para_dimensions.para_n = out_n;
    req.para_dimensions.para_c = out_c;
    req.para_dimensions.para_h = out_h;
    req.para_dimensions.para_w = out_w;

    std::bernoulli_distribution make_broadcast(0.45);
    uint32_t in_n = (out_n > 1 && make_broadcast(rng)) ? 1 : out_n;
    uint32_t in_c = (out_c > 1 && make_broadcast(rng)) ? 1 : out_c;
    uint32_t in_h = (out_h > 1 && make_broadcast(rng)) ? 1 : out_h;
    uint32_t in_w = (out_w == 32 && out_n == 1 && out_c == 1 && out_h == 1) ? 1 : out_w;
    if (in_n == out_n && in_c == out_c && in_h == out_h && in_w == out_w && out_n > 1) {
        in_n = 1;
    }

    const uint32_t input_elems = in_n * in_c * in_h * in_w;
    std::vector<float> source(input_elems);
    for (float& v : source) v = data_dist(rng);

    app::AppTensorDesc input_desc;
    input_desc.para_name = "input_tensor";
    input_desc.para_dtype = target_type;
    input_desc.para_shape = {in_n, in_c, in_h, in_w};
    input_desc.para_data_f32 = source;
    req.para_inputs["input_tensor"] = input_desc;

    app::AppTensorDesc shape_desc;
    shape_desc.para_name = "input_shape";
    shape_desc.para_dtype = app::AppDataType::INT32;
    shape_desc.para_shape = {4};
    shape_desc.para_data_i32 = {static_cast<int32_t>(in_n), static_cast<int32_t>(in_c),
                                static_cast<int32_t>(in_h), static_cast<int32_t>(in_w)};
    req.para_parameters["input_shape"] = shape_desc;
}

bool ExpandOp::generate_data(const app::AppOperatorRequest& req,
                             std::vector<uint8_t>& input_bin,
                             std::vector<uint8_t>& other_bin,
                             std::vector<uint8_t>& alpha_bin) {
    input_bin.clear();
    other_bin.clear();
    alpha_bin.clear();

    auto input_it = req.para_inputs.find("input_tensor");
    if (input_it != req.para_inputs.end()) {
        const auto out_shape = std::vector<uint32_t>{
            req.para_dimensions.para_n,
            req.para_dimensions.para_c,
            req.para_dimensions.para_h,
            req.para_dimensions.para_w};
        const auto in_shape = normalize_shape_to_nchw(input_it->second.para_shape);
        const bool lane_broadcast =
            in_shape[3] == 1 && out_shape[3] > 1 &&
            (in_shape[0] == 1 || in_shape[0] == out_shape[0]) &&
            (in_shape[1] == 1 || in_shape[1] == out_shape[1]) &&
            (in_shape[2] == 1 || in_shape[2] == out_shape[2]);
        const bool strict =
            [&]() {
                auto it = req.para_parameters.find("strict_hardware_path");
                return it != req.para_parameters.end() && !it->second.para_data_i32.empty() &&
                       it->second.para_data_i32[0] != 0;
            }();
        if (lane_broadcast && !strict) {
            append_expanded_tensor_data(input_bin, input_it->second,
                                        req.para_dimensions.para_n,
                                        req.para_dimensions.para_c,
                                        req.para_dimensions.para_h,
                                        req.para_dimensions.para_w);
        } else {
            write_tensor_data(input_bin, input_it->second);
        }
    }

    return true;
}

std::vector<uint8_t> ExpandOpInstructions::serialize() const {
    std::vector<uint8_t> result;
    auto iq_files = get_iq_files();
    for (const auto& file : iq_files)
        result.insert(result.end(), file.para_data.begin(), file.para_data.end());
    return result;
}

REGISTER_OP(ExpandOp);

} // namespace op
} // namespace aiacc

/**
 * @file mean_dim_op.cpp
 * @brief MeanDim 算子核心实现
 *
 * 功能：out[g] = mean(input[g*R .. g*R+R-1])
 *
 * 策略 (与 1smc/8smc 硬件测试一致):
 *   1. 数据预处理阶段 (软件侧):
 *      - 将 reduce_size 个输入 word 按组求和 → pre_sum
 *      - alpha = 1.0 / reduce_size
 *   2. 硬件流水线 (复用 add 算子流程):
 *      - bank0 = 全零 (input = 0)
 *      - bank1 = pre_sum (预求和数据, 作为 "other")
 *      - bank2 = alpha = 1/reduce_size (广播标量)
 *      - bank3 = output
 *      - 计算: out = 0 + alpha * pre_sum = mean(原始输入)
 *
 * 支持 8 SMC: 每个 SMC 独立处理完整的 mean_dim 任务。
 */
#include "mean_dim_op.h"
#include <iostream>
#include <iomanip>
#include <cstring>
#include <algorithm>
#include <stdexcept>
#include <map>
#include "../../iq/iq_id_defs.h"
#include "../../app/fp16_utils.h"
#include "ur_code_extractor.h"

#include "mean_dim_op_constants.h"
#include "mean_dim_op_bank_conflict.h"
#include "mean_dim_op_ur_inst.h"
#include "mean_dim_op_rtovr_inst.h"
#include "mean_dim_op_compute_inst.h"
#include "../common/lsu_v2_packer.h"
#include "../common/v421_iq_adapter.h"

namespace aiacc {
namespace op {

namespace {
using v421::kMaxDlyField;
using v421::emit_dummy_for_long_delay;
using v421::consume_startup_delay;
using v421::ScaleAddSteadyStateSchedule;

constexpr uint32_t kRtovrPorts   = 40;
constexpr uint32_t kRtovrBitsPerPort = 7;
constexpr uint32_t kRtovrTotalBits   = kRtovrPorts * kRtovrBitsPerPort;
constexpr uint32_t kRtovrMsbBitIndex = kRtovrTotalBits - 1;
constexpr uint32_t kUrWordBytes = 16;
constexpr uint32_t kUrBankAddrStride = 0x1000;
constexpr uint32_t kIqIdStb = v421::kIqIdStb;
constexpr uint32_t kIqIdLdb = v421::kIqIdLdb;

inline uint32_t align_dly_to_slot(uint32_t base_dly, uint8_t target_slot, uint8_t num_slots) {
    if (num_slots <= 1) return base_dly;
    uint32_t remainder = base_dly % num_slots;
    uint32_t offset = (static_cast<uint32_t>(target_slot) - remainder + num_slots) % num_slots;
    return base_dly + offset;
}

uint8_t extract_rtovr_port_code(const std::vector<uint32_t>& rtovr_words, uint8_t port) {
    if (rtovr_words.empty() || port >= kRtovrPorts) return 0;
    const uint32_t bit_lsb = 273u - static_cast<uint32_t>(port) * kRtovrBitsPerPort;
    const uint32_t word_idx = bit_lsb / 32u;
    const uint32_t bit_in_word = bit_lsb % 32u;
    if (word_idx >= rtovr_words.size()) return 0;
    uint32_t code = (rtovr_words[word_idx] >> bit_in_word) & 0x7Fu;
    if (bit_in_word > 25u && (word_idx + 1u) < rtovr_words.size()) {
        const uint32_t right_bits = 32u - bit_in_word;
        const uint32_t high_mask = (1u << (kRtovrBitsPerPort - right_bits)) - 1u;
        const uint32_t high_bits = rtovr_words[word_idx + 1u] & high_mask;
        code |= (high_bits << right_bits);
    }
    return static_cast<uint8_t>(code & 0x7Fu);
}

std::vector<uint8_t> extract_active_rtovr_ports(const std::vector<uint32_t>& rtovr_words) {
    std::vector<uint8_t> active_ports;
    if (rtovr_words.empty()) return active_ports;
    for (uint8_t port = 0; port < kRtovrPorts; ++port) {
        int msb = static_cast<int>(kRtovrMsbBitIndex) - static_cast<int>(kRtovrBitsPerPort) * port;
        int lsb = msb - 6;
        int word_idx = lsb / 32;
        int bit_in_word = lsb % 32;
        if (word_idx >= (int)rtovr_words.size()) break;
        bool valid = (rtovr_words[word_idx] >> bit_in_word) & 0x1;
        if (valid) active_ports.push_back(port);
    }
    return active_ports;
}

uint64_t pack_lsu_header(uint16_t loops, uint8_t dly, uint16_t inc_bytes) {
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

std::vector<uint8_t> make_stb_instruction(uint32_t words, uint8_t bank, uint16_t byte_addr) {
    const uint16_t loops = static_cast<uint16_t>((words > 0) ? words - 1 : 0);
    const uint64_t header = pack_lsu_header(loops, 0, kUrWordBytes);

    uint64_t code = 0;
    code = (code << 2) | 0u;                         // tid
    code = (code << 5) | 0x7u;                       // smc_id_en
    code = (code << 4) | 0u;                         // inst_id
    code = (code << 6) | 0u;                         // line_stride
    code = (code << 9) | (kUrWordBytes - 1);         // line_byte_cnt
    code = (code << 8) | 1u;                         // one UR line per issue
    code = (code << 15) | make_ur_addr(bank, byte_addr);
    code = (code << 1) | 1u;                         // vld

    unsigned __int128 inst = (static_cast<unsigned __int128>(header) << 50) | code;
    std::vector<uint8_t> bytes;
    append_big_endian(bytes, inst, 13);
    return bytes;
}

std::vector<uint8_t> make_ldb_instruction(uint32_t words, uint8_t bank, uint16_t byte_addr) {
    const uint16_t loops = static_cast<uint16_t>((words > 0) ? words - 1 : 0);
    const uint64_t header = pack_lsu_header(loops, 0, kUrWordBytes);

    uint64_t code = 0;
    code = (code << 5) | 0x7u;                       // smc_id_en
    code = (code << 4) | 0u;                         // inst_id
    code = (code << 1) | 0u;                         // post_fill
    code = (code << 1) | 0u;                         // pre_fill
    code = (code << 6) | 0u;                         // const
    code = (code << 6) | 0u;                         // line_stride
    code = (code << 9) | (kUrWordBytes - 1);         // line_byte_cnt
    code = (code << 8) | 1u;                         // one UR line per issue
    code = (code << 15) | make_ur_addr(bank, byte_addr);
    code = (code << 1) | 1u;                         // vld

    unsigned __int128 inst = (static_cast<unsigned __int128>(header) << 56) | code;
    std::vector<uint8_t> bytes;
    append_big_endian(bytes, inst, 14);
    return bytes;
}

int get_i32_param_from_req(const app::AppOperatorRequest& req, const std::string& key, int def) {
    auto it = req.para_parameters.find(key);
    if (it != req.para_parameters.end() && !it->second.para_data_i32.empty()) {
        return it->second.para_data_i32[0];
    }
    return def;
}

bool is_llama_dim_reduce_request(const app::AppOperatorRequest& req) {
    const int dim = get_i32_param_from_req(req, "dim", -1);
    const int keepdim = get_i32_param_from_req(req, "keepdim", 1);
    const int reduce_elems = get_i32_param_from_req(
        req, "reduce_elems", static_cast<int>(req.para_dimensions.para_w));
    return dim == -1 && keepdim != 0 &&
           reduce_elems > 0 &&
           static_cast<uint32_t>(reduce_elems) == req.para_dimensions.para_w &&
           req.para_dimensions.para_w > 16;
}

void emit_float_bytes(std::vector<uint8_t>& bin, float value, app::AppDataType dtype) {
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

std::vector<float> build_llama_mean_presum(const app::AppOperatorRequest& req,
                                           app::AppDataType& dtype,
                                           uint32_t& tokens,
                                           uint32_t& elems_per_word) {
    auto input_it = req.para_inputs.find("input_tensor");
    if (input_it == req.para_inputs.end()) return {};
    dtype = input_it->second.para_dtype;
    elems_per_word = (dtype == app::AppDataType::FLOAT16) ? 8 : 4;
    const uint32_t reduce_elems =
        static_cast<uint32_t>(get_i32_param_from_req(req, "reduce_elems",
                                                    static_cast<int>(req.para_dimensions.para_w)));
    tokens = req.para_dimensions.para_n * req.para_dimensions.para_c * req.para_dimensions.para_h;
    if (tokens == 0 || reduce_elems == 0) return {};
    std::vector<float> pre_sum(tokens * elems_per_word, 0.0f);
    const auto& data = input_it->second.para_data_f32;
    for (uint32_t t = 0; t < tokens; ++t) {
        double sum = 0.0;
        const uint32_t base = t * reduce_elems;
        for (uint32_t i = 0; i < reduce_elems && (base + i) < data.size(); ++i) {
            float v = data[base + i];
            if (dtype == app::AppDataType::FLOAT16) {
                v = app::float16_to_float32(app::float32_to_float16(v));
            }
            sum += static_cast<double>(v);
        }
        pre_sum[t * elems_per_word] = static_cast<float>(sum);
    }
    return pre_sum;
}

void append_lsu_v2_files(std::vector<IqInstructionFile>& files,
                         uint32_t input_words,
                         uint32_t output_words,
                         uint8_t input_ur_id,
                         uint8_t input_ur_addr,
                         uint8_t output_ur_id,
                         uint8_t output_ur_addr,
                         uint64_t input_gr_base,
                         uint64_t output_gr_base,
                         uint8_t smc_count,
                         uint8_t smc_id,
                         uint8_t byte_strb) {
    const uint8_t smc_strb = static_cast<uint8_t>(std::max<uint8_t>(1, smc_count) - 1);
    if (input_words > 0) {
        IqInstructionFile file;
        file.para_iq_id = lsu_v2::kIqIdLdbV2;
        file.para_iq_name = "ldb_v2";
        file.para_width_bits = lsu_v2::kLdbBits;
        lsu_v2::LsuV2Params p;
        p.smc_strb = smc_strb;
        p.byte_strb = byte_strb;
        p.gr_base_addr = input_gr_base;
        p.smc_id = smc_id;
        p.ur_id = input_ur_id;
        p.ur_addr = input_ur_addr;
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
        p.byte_strb = byte_strb;
        p.gr_base_addr = output_gr_base;
        p.smc_id = smc_id;
        p.ur_id = output_ur_id;
        p.ur_addr = output_ur_addr;
        lsu_v2::append_stb_v2_transfer(file.para_data, p, output_words);
        files.push_back(file);
    }
}
} // anonymous namespace

// ============================================================================
// 指令生成实现 (复用 add 算子数据流)
// ============================================================================

static void gen_ur_insts_impl(const MeanDimOpParams& params, MeanDimOpInstructions& result) {
    iq::UrCru ur_read_cru;
    ur_read_cru.para_vld = true;

    // 读端口 0: hardware_reduce 读取 raw input；兼容模式读取零输入。
    ur_read_cru.para_raddr[0].bank = params.para_input_bank;
    ur_read_cru.para_raddr[0].addr_word = params.para_input_addr;
    ur_read_cru.para_re[0] = true;

    // 读端口 1: legacy pre_sum 兼容模式使用 bank1；chunk 模式读 bank1 作 tile1。
    ur_read_cru.para_raddr[1].bank = 1;
    ur_read_cru.para_raddr[1].addr_word = 0;
    ur_read_cru.para_re[1] = params.para_pre_sum_compat || params.para_llama_chunk_reduce;

    // 读端口 2: alpha = 1/reduce_size，广播读取。
    ur_read_cru.para_raddr[2].bank = params.para_alpha_bank;
    ur_read_cru.para_raddr[2].addr_word = params.para_alpha_addr;
    ur_read_cru.para_re[2] = true;

    ur_read_cru.para_re[3] = false;
    ur_read_cru.para_we[0] = false;
    ur_read_cru.para_we[1] = false;
    ur_read_cru.para_we[2] = false;
    ur_read_cru.para_we[3] = false;
    result.para_ur_read_crus.push_back(ur_read_cru);

    // 写端口
    iq::UrCru ur_write_cru;
    ur_write_cru.para_vld = true;
    ur_write_cru.para_re[0] = false;
    ur_write_cru.para_re[1] = false;
    ur_write_cru.para_re[2] = false;
    ur_write_cru.para_re[3] = false;
    ur_write_cru.para_waddr[0].bank = params.para_output_bank;
    ur_write_cru.para_waddr[0].addr_word = params.para_output_addr;
    ur_write_cru.para_we[0] = true;
    ur_write_cru.para_wbe[0] = 0xFFFF;
    ur_write_cru.para_we[1] = false;
    ur_write_cru.para_we[2] = false;
    ur_write_cru.para_we[3] = false;
    result.para_ur_write_crus.push_back(ur_write_cru);
}

static void gen_float_compute_impl(const MeanDimOpParams& params, MeanDimOpInstructions& result) {
    if (params.para_llama_chunk_reduce) {
        // Native LLAMA path: FPADD word reduce → AddTree8to1 lane sum → ×(1/N).
        // Word-reduce RtoVR (stage1): UR0 → FPADD_S0, FPADD_D → FPADD_S1.
        {
            iq::RtoVrCru rtovr_cru;
            rtovr_cru.para_vld = true;
            for (int i = 0; i < 40; ++i) {
                rtovr_cru.para_out[i].para_valid = false;
                rtovr_cru.para_out[i].para_select = 0;
            }
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S0].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S0].para_select = MD_RTOVR_IN_UR_RDATA_0;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S1].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S1].para_select = MD_RTOVR_IN_DR_FPADD_D;
            uint32_t rtovr_words[10];
            iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
            result.para_rtovr_stage1.assign(rtovr_words, rtovr_words + 9);
        }
        // Lane-reduce RtoVR (stage2): FPADD_D → AddTree S0, ZERO → AddTree S1.
        {
            iq::RtoVrCru rtovr_cru;
            rtovr_cru.para_vld = true;
            for (int i = 0; i < 40; ++i) {
                rtovr_cru.para_out[i].para_valid = false;
                rtovr_cru.para_out[i].para_select = 0;
            }
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FP32ADDTREE8TO1_S0].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FP32ADDTREE8TO1_S0].para_select =
                MD_RTOVR_IN_DR_FPADD_D;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FP32ADDTREE8TO1_S1].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FP32ADDTREE8TO1_S1].para_select =
                MD_RTOVR_IN_ZERO;
            uint32_t rtovr_words[10];
            iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
            result.para_rtovr_stage2.assign(rtovr_words, rtovr_words + 9);
        }
        // Scale + writeback (stage3): alpha → FPMUL_S0, AddTree_D → FPMUL_S1, mul → UVR.
        {
            iq::RtoVrCru rtovr_cru;
            rtovr_cru.para_vld = true;
            for (int i = 0; i < 40; ++i) {
                rtovr_cru.para_out[i].para_valid = false;
                rtovr_cru.para_out[i].para_select = 0;
            }
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S0].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S0].para_select = MD_RTOVR_IN_UR_RDATA_2;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S1].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S1].para_select =
                MD_RTOVR_IN_DR_FP32ADDTREE8TO1_D;
            rtovr_cru.para_out[MD_RTOVR_OUT_UVR_WDATA_0].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_UVR_WDATA_0].para_select = MD_RTOVR_IN_DR_FPMUL_D;
            uint32_t rtovr_words[10];
            iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
            result.para_rtovr_stage3.assign(rtovr_words, rtovr_words + 9);
        }

        const bool is_32b = (params.para_dtype == MeanDimDataType::FP32);
        const uint8_t smc_en = 31;
        {
            iq::FpMulCru fpmul_cru;
            fpmul_cru.para_inst_valid = true;
            fpmul_cru.para_src_precision_is_32b = is_32b;
            fpmul_cru.para_dst_precision_is_32b = is_32b;
            fpmul_cru.para_smc_id_en = smc_en;
            result.para_fpmul_inst = iq::FpMulIq::pack_cru_fpmul(fpmul_cru);
        }
        {
            iq::FpAddCru fpadd_cru;
            fpadd_cru.para_inst_valid = true;
            fpadd_cru.para_mode_is_32b = is_32b;
            fpadd_cru.para_update_st = false;
            result.para_fpadd_inst = static_cast<uint16_t>(
                (iq::FpAddIq::pack_cru_fpadd(fpadd_cru) & 0x1Fu) | (static_cast<uint16_t>(smc_en) << 5));
        }
        {
            iq::Fp32AddTree8To1Cru tree;
            tree.para_inst_valid = true;
            tree.para_dst_reg_enc = 0; // lane0
            result.para_addtree8_inst = static_cast<uint16_t>(
                (iq::Fp32AddTree8To1Iq::pack_cru_fp32addtree8to1(tree) & 0x7u) |
                (static_cast<uint16_t>(smc_en) << 3));
        }
        return;
    }

    if (params.para_hardware_reduce) {
        // Hardware reduce topology:
        //   raw input(UR_RDATA_0) -> FPADD_S0
        //   FPADD_D feedback      -> FPADD_S1 (disabled on the first item of each group by scheduler)
        //   alpha(UR_RDATA_2)     -> FPMUL_S0
        //   FPADD_D final sum     -> FPMUL_S1
        {
            iq::RtoVrCru rtovr_cru;
            rtovr_cru.para_vld = true;
            for (int i = 0; i < 40; ++i) {
                rtovr_cru.para_out[i].para_valid = false;
                rtovr_cru.para_out[i].para_select = 0;
            }
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S0].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S0].para_select = MD_RTOVR_IN_UR_RDATA_0;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S1].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S1].para_select = MD_RTOVR_IN_DR_FPADD_D;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S0].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S0].para_select = 32; // UR_RDATA_2 (alpha)
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S1].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S1].para_select = MD_RTOVR_IN_DR_FPADD_D;
            uint32_t rtovr_words[10];
            iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
            result.para_rtovr_stage1.assign(rtovr_words, rtovr_words + 9);
        }

        {
            iq::RtoVrCru rtovr_cru;
            rtovr_cru.para_vld = true;
            for (int i = 0; i < 40; ++i) {
                rtovr_cru.para_out[i].para_valid = false;
                rtovr_cru.para_out[i].para_select = 0;
            }
            rtovr_cru.para_out[MD_RTOVR_OUT_UVR_WDATA_0].para_valid = true;
            rtovr_cru.para_out[MD_RTOVR_OUT_UVR_WDATA_0].para_select = MD_RTOVR_IN_DR_FPMUL_D;
            uint32_t rtovr_words[10];
            iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
            result.para_rtovr_stage3.assign(rtovr_words, rtovr_words + 9);
        }

        iq::FpMulCru fpmul_cru;
        fpmul_cru.para_inst_valid = true;
        const bool is_32b = (params.para_dtype == MeanDimDataType::FP32);
        fpmul_cru.para_src_precision_is_32b = is_32b;
        fpmul_cru.para_dst_precision_is_32b = is_32b;
        fpmul_cru.para_smc_id_en = static_cast<uint8_t>((params.para_smc_count > 0)
                                                            ? (params.para_smc_count - 1)
                                                            : 31);
        result.para_fpmul_inst = iq::FpMulIq::pack_cru_fpmul(fpmul_cru);

        iq::FpAddCru fpadd_cru;
        fpadd_cru.para_inst_valid = true;
        fpadd_cru.para_mode_is_32b = is_32b;
        fpadd_cru.para_update_st = true;
        const uint16_t fpadd_smc = static_cast<uint16_t>((params.para_smc_count > 0)
                                                             ? (params.para_smc_count - 1)
                                                             : 31);
        result.para_fpadd_inst = static_cast<uint16_t>(
            (iq::FpAddIq::pack_cru_fpadd(fpadd_cru) & 0x1Fu) | ((fpadd_smc & 0x1Fu) << 5));
    } else {
    // Stage1: alpha(UR_RDATA_2) → FPMUL_S0, other(UR_RDATA_1) → FPMUL_S1
    {
        iq::RtoVrCru rtovr_cru;
        rtovr_cru.para_vld = true;
        for (int i = 0; i < 40; ++i) {
            rtovr_cru.para_out[i].para_valid = false;
            rtovr_cru.para_out[i].para_select = 0;
        }
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S0].para_valid = true;
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S0].para_select = 32; // UR_RDATA_2 (alpha)
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S1].para_valid = true;
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S1].para_select = 31; // UR_RDATA_1 (other/pre_sum)
        uint32_t rtovr_words[10];
        iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
        result.para_rtovr_stage1.assign(rtovr_words, rtovr_words + 9);
    }

    // Stage2: input(UR_RDATA_0) → FPADD_S0, FPMUL_D → FPADD_S1
    {
        iq::RtoVrCru rtovr_cru;
        rtovr_cru.para_vld = true;
        for (int i = 0; i < 40; ++i) {
            rtovr_cru.para_out[i].para_valid = false;
            rtovr_cru.para_out[i].para_select = 0;
        }
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S0].para_valid = true;
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S0].para_select = 30; // UR_RDATA_0 (input=0)
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S1].para_valid = true;
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S1].para_select = MD_RTOVR_IN_DR_FPMUL_D;
        uint32_t rtovr_words[10];
        iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
        result.para_rtovr_stage2.assign(rtovr_words, rtovr_words + 9);
    }

    // Stage3: FPADD_D → UVR_WDATA_0
    {
        iq::RtoVrCru rtovr_cru;
        rtovr_cru.para_vld = true;
        for (int i = 0; i < 40; ++i) {
            rtovr_cru.para_out[i].para_valid = false;
            rtovr_cru.para_out[i].para_select = 0;
        }
        rtovr_cru.para_out[MD_RTOVR_OUT_UVR_WDATA_0].para_valid = true;
        rtovr_cru.para_out[MD_RTOVR_OUT_UVR_WDATA_0].para_select = MD_RTOVR_IN_DR_FPADD_D;
        uint32_t rtovr_words[10];
        iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
        result.para_rtovr_stage3.assign(rtovr_words, rtovr_words + 9);
    }

    // Optional cascade route: FPADD_D → DVR_SHIFTDN_S.
    // This exposes the local partial mean to the inter-SMC shift-down chain.
    if (params.para_enable_cascade) {
        iq::RtoVrCru rtovr_cru;
        rtovr_cru.para_vld = true;
        for (int i = 0; i < 40; ++i) {
            rtovr_cru.para_out[i].para_valid = false;
            rtovr_cru.para_out[i].para_select = 0;
        }
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_SHIFTDN_S].para_valid = true;
        rtovr_cru.para_out[MD_RTOVR_OUT_DVR_SHIFTDN_S].para_select = MD_RTOVR_IN_DR_FPADD_D;
        uint32_t rtovr_words[10];
        iq::RtoVrIq::pack_cru_rtovr_words(rtovr_cru, rtovr_words);
        result.para_rtovr_stage_shift.assign(rtovr_words, rtovr_words + 9);
    }

    // FPMUL
    {
        iq::FpMulCru fpmul_cru;
        fpmul_cru.para_inst_valid = true;
        bool is_32b = (params.para_dtype == MeanDimDataType::FP32);
        fpmul_cru.para_src_precision_is_32b = is_32b;
        fpmul_cru.para_dst_precision_is_32b = is_32b;
        fpmul_cru.para_smc_id_en = static_cast<uint8_t>((params.para_smc_count > 0)
                                                            ? (params.para_smc_count - 1)
                                                            : 31);
        result.para_fpmul_inst = iq::FpMulIq::pack_cru_fpmul(fpmul_cru);
    }
    // FPADD (pass-through: update_st=false, compute out = input + mul_result)
    {
        iq::FpAddCru fpadd_cru;
        fpadd_cru.para_inst_valid = true;
        fpadd_cru.para_mode_is_32b = (params.para_dtype == MeanDimDataType::FP32);
        fpadd_cru.para_update_st = false;
        const uint16_t fpadd_smc = static_cast<uint16_t>((params.para_smc_count > 0)
                                                             ? (params.para_smc_count - 1)
                                                             : 31);
        result.para_fpadd_inst = static_cast<uint16_t>(
            (iq::FpAddIq::pack_cru_fpadd(fpadd_cru) & 0x1Fu) | ((fpadd_smc & 0x1Fu) << 5));
    }
    }

    // Simulator shiftdn control keeps valid at bit13; RTL also sees bit0 as valid.
    const uint16_t smc_id_en = static_cast<uint16_t>((params.para_smc_count > 0)
                                                        ? (params.para_smc_count - 1)
                                                        : params.para_smc_id);
    result.para_shiftdn_inst = static_cast<uint16_t>((1u << 13) |
                                                     ((smc_id_en & 0x1Fu) << 2) |
                                                     0x1u);
}

MeanDimOpInstructions MeanDimOp::compile(const MeanDimOpParams& para_params) {
    MeanDimOpInstructions result;
    result.para_dtype = para_params.para_dtype;
    result.para_reduce_size = para_params.para_reduce_size;
    result.para_hardware_reduce = para_params.para_hardware_reduce;
    result.para_pre_sum_compat = para_params.para_pre_sum_compat;
    result.para_llama_chunk_reduce = para_params.para_llama_chunk_reduce;
    result.para_enable_lsu = para_params.para_enable_lsu;
    result.para_enable_lsu_v2 = para_params.para_enable_lsu_v2;
    result.para_enable_cascade = para_params.para_enable_cascade;
    result.para_smc_id = para_params.para_smc_id;
    result.para_smc_count = para_params.para_smc_count;
    result.para_lsu_source_bank =
        (para_params.para_hardware_reduce || para_params.para_llama_chunk_reduce)
            ? para_params.para_input_bank
            : 1;
    result.para_lsu_stage_bank = para_params.para_lsu_stage_bank;
    result.para_lsu_stage_addr_bytes = para_params.para_lsu_stage_addr_bytes;
    result.para_lsu_v2_input_gr_base = para_params.para_lsu_v2_input_gr_base;
    result.para_lsu_v2_output_gr_base = para_params.para_lsu_v2_output_gr_base;
    result.para_lsu_v2_input_ur_id = para_params.para_lsu_v2_input_ur_id;
    result.para_lsu_v2_output_ur_id = para_params.para_lsu_v2_output_ur_id;
    result.para_lsu_v2_byte_strb = para_params.para_lsu_v2_byte_strb;

    const uint32_t total_elems = para_params.para_n * para_params.para_c *
                                 para_params.para_h * para_params.para_w;
    const uint32_t elems_per_word = para_params.get_elems_per_word();
    const uint32_t total_input_words = (total_elems + elems_per_word - 1) / elems_per_word;
    const uint32_t reduce_words = std::max<uint32_t>(1, para_params.para_reduce_size);
    const uint32_t output_words = total_input_words / reduce_words;

    // hardware / chunk 处理 raw input words；pre_sum_compat 只处理预求和后的 output words。
    result.para_total_steps =
        (para_params.para_hardware_reduce || para_params.para_llama_chunk_reduce)
            ? total_input_words
            : output_words;
    if (para_params.para_llama_chunk_reduce) {
        // One scalar mean per token → one UR output word.
        result.para_output_words = 1;
        result.para_total_elements = elems_per_word;
    } else {
        result.para_total_elements = output_words * elems_per_word;
        result.para_output_words = output_words;
    }
    result.para_num_slots = 1;

    // 循环参数
    const uint32_t w_steps = para_params.para_w / elems_per_word / reduce_words;
    const uint32_t outer_loops = para_params.para_n * para_params.para_c * para_params.para_h;
    result.para_embed_loops = static_cast<uint16_t>(outer_loops);
    result.para_inner_loops = static_cast<uint16_t>(w_steps > 0 ? w_steps : 1);

    gen_ur_insts_impl(para_params, result);
    gen_float_compute_impl(para_params, result);

    return result;
}

// ============================================================================
// IQ 文件序列化 (复用 add 算子的序列化逻辑)
// ============================================================================

std::vector<IqInstructionFile> MeanDimOpInstructions::get_iq_files() const {
    std::vector<IqInstructionFile> files;

    constexpr uint32_t BITS_EMBED = 3, BITS_EMBED_END = 6, BITS_LOOPS = 10;
    constexpr uint32_t BITS_COND = 7, BITS_DLY = 3, BITS_INC = 4, BITS_INC_EMBED = 6;
    constexpr uint32_t MASK_EMBED = (1u << BITS_EMBED) - 1;
    constexpr uint32_t MASK_EMBED_END = (1u << BITS_EMBED_END) - 1;
    constexpr uint32_t MASK_LOOPS = (1u << BITS_LOOPS) - 1;
    constexpr uint32_t MASK_COND = (1u << BITS_COND) - 1;
    constexpr uint32_t MASK_DLY = (1u << BITS_DLY) - 1;
    constexpr uint32_t MASK_INC = (1u << BITS_INC) - 1;
    constexpr uint32_t MASK_INC_EMBED = (1u << BITS_INC_EMBED) - 1;

    auto serialize_header_bits = [](uint8_t vld, uint8_t jump, uint8_t embed, uint16_t loops,
                                    uint8_t cond, uint8_t dly, uint8_t inc,
                                    uint8_t embed_end_bits, uint8_t inc_embed_bits) -> uint64_t {
        uint64_t bits = 0;
        uint32_t pos = 0;
        uint8_t embed_end = (embed == 0) ? (embed_end_bits & MASK_EMBED_END) : 0u;
        uint8_t inc_embed = (embed == 0) ? (inc_embed_bits & MASK_INC_EMBED) : 0u;
        bits |= (uint64_t)(inc_embed & MASK_INC_EMBED) << pos; pos += BITS_INC_EMBED;
        bits |= (uint64_t)(inc & MASK_INC) << pos;             pos += BITS_INC;
        bits |= (uint64_t)(dly & MASK_DLY) << pos;             pos += BITS_DLY;
        bits |= (uint64_t)(cond & MASK_COND) << pos;           pos += BITS_COND;
        bits |= (uint64_t)(loops & MASK_LOOPS) << pos;         pos += BITS_LOOPS;
        bits |= (uint64_t)(embed_end & MASK_EMBED_END) << pos; pos += BITS_EMBED_END;
        bits |= (uint64_t)(embed & MASK_EMBED) << pos;         pos += BITS_EMBED;
        bits |= (uint64_t)(jump & 1u) << pos;                  pos += 1;
        bits |= (uint64_t)(vld & 1u) << pos;
        return bits;
    };

    auto serialize_header = [&](uint8_t vld, uint8_t jump, uint8_t embed, uint16_t loops,
                               uint8_t cond, uint8_t dly, uint8_t inc,
                               uint8_t embed_end_bits, uint8_t inc_embed_bits) -> std::vector<uint8_t> {
        uint64_t bits = serialize_header_bits(vld, jump, embed, loops, cond, dly, inc, embed_end_bits, inc_embed_bits);
        std::vector<uint8_t> bytes;
        for (int i = 5; i >= 0; --i)
            bytes.push_back(static_cast<uint8_t>((bits >> (i * 8)) & 0xFF));
        return bytes;
    };

    auto serialize_code = [](uint64_t code, uint16_t code_bits) -> std::vector<uint8_t> {
        std::vector<uint8_t> bytes;
        uint16_t num_bytes = (code_bits + 7) / 8;
        for (int i = num_bytes - 1; i >= 0; --i)
            bytes.push_back((code >> (i * 8)) & 0xFF);
        return bytes;
    };

    auto make_instruction = [&](uint8_t vld, uint8_t jump, uint8_t embed, uint16_t loops,
                                uint8_t cond, uint8_t dly, int8_t inc,
                                uint8_t embed_end_bits, uint8_t inc_embed_bits,
                                const std::vector<uint8_t>& code_bytes,
                                int code_bits = -1) -> std::vector<uint8_t> {
        if (code_bits > 0 && code_bits <= 23) {
            uint64_t h = serialize_header_bits(vld, jump, embed, loops, cond, dly, inc, embed_end_bits, inc_embed_bits);
            uint64_t c = 0;
            for (uint8_t b : code_bytes) c = (c << 8) | b;
            if (code_bits < 64) c &= ((1ULL << code_bits) - 1);
            uint64_t total = (h << code_bits) | c;
            int total_width = 41 + code_bits;
            int num_bytes = (total_width + 7) / 8;
            std::vector<uint8_t> ret;
            for (int i = num_bytes - 1; i >= 0; --i)
                ret.push_back(static_cast<uint8_t>((total >> (i * 8)) & 0xFF));
            return ret;
        } else {
            auto header = serialize_header(vld, jump, embed, loops, cond, dly, inc, embed_end_bits, inc_embed_bits);
            header.insert(header.end(), code_bytes.begin(), code_bytes.end());
            return header;
        }
    };

    if (para_llama_chunk_reduce) {
        // Native LLAMA mean: FPADD feedback accumulate needs period≈6 (pipeline).
        // Compact encoding: embed=1 outer loop + body [ops + nop padding] so EXE_ARRAY
        // spends one cycle per body slot (dly is cleared on replay). INSTQ_DEPTH=128.
        constexpr uint8_t kNoEmbed = ScaleAddSteadyStateSchedule::kNoEmbed;
        constexpr uint8_t smc_en = 31;
        constexpr uint16_t kUrRBits = 17;
        constexpr uint16_t kUrWBits = 33;
        constexpr uint16_t kFpmulBits = 8;
        constexpr uint16_t kFpaddBits = 10;
        constexpr uint16_t kAddTreeBits = 8;
        constexpr uint32_t kTileWords = MD_LLAMA_TILE_WORDS;
        constexpr uint32_t kSpacing = 6;     // hardware_reduce / FPADD pipe
        constexpr uint32_t kUrSlot = 0;      // body slot of UR read
        constexpr uint32_t kFpaddSlot = 2;   // UR→FPADD gap ≈2 (Sub-like)

        const uint32_t total_words = para_total_steps;
        if (total_words == 0 || (total_words % kTileWords) != 0) {
            throw std::runtime_error("llama_chunk_reduce requires total_words multiple of 256");
        }
        const uint32_t num_tiles = total_words / kTileWords;
        const uint32_t job_cycles = total_words * kSpacing;
        const uint32_t hold_cycles = job_cycles + 80;

        auto make_single_rtovr_code = [&](uint8_t port, uint8_t select) -> uint8_t {
            iq::RtoVrCru cru;
            cru.para_vld = true;
            for (int i = 0; i < 40; ++i) {
                cru.para_out[i].para_valid = false;
                cru.para_out[i].para_select = 0;
            }
            cru.para_out[port].para_valid = true;
            cru.para_out[port].para_select = select;
            uint32_t words[10];
            iq::RtoVrIq::pack_cru_rtovr_words(cru, words);
            return extract_rtovr_port_code(std::vector<uint32_t>(words, words + 9), port);
        };
        auto append_hold_code = [&](IqInstructionFile& file, uint16_t width_bits,
                                    const std::vector<uint8_t>& code_bytes, uint32_t beats) {
            uint32_t left = beats;
            while (left > 0) {
                const uint32_t chunk = std::min<uint32_t>(left, 1023);
                auto head =
                    make_instruction(1, 0, kNoEmbed, 0, 0, 0, 0, 0, 0, code_bytes, width_bits);
                file.para_data.insert(file.para_data.end(), head.begin(), head.end());
                if (chunk > 1) {
                    auto rest = make_instruction(
                        1, 0, 0u, static_cast<uint16_t>(chunk - 1), 0, 0, 0, 0, 0, code_bytes,
                        width_bits);
                    file.para_data.insert(file.para_data.end(), rest.begin(), rest.end());
                }
                left -= chunk;
            }
        };
        auto append_rtovr_static = [&](uint8_t port, uint8_t select) {
            IqInstructionFile file;
            file.para_iq_id = v421::rtovr_iq_id(port);
            file.para_iq_name = "rtovr-" + std::to_string(port);
            file.para_width_bits = 41 + 7;
            auto code_bytes = serialize_code(make_single_rtovr_code(port, select), 7);
            auto zero_code = serialize_code(0, 7);
            append_hold_code(file, 7, code_bytes, hold_cycles);
            auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0, 0, zero_code, 7);
            file.para_data.insert(file.para_data.end(), end.begin(), end.end());
            files.push_back(file);
        };
        // emit spaced embed body: ctrl embed=1 + body[spacing] with fire at fire_slot
        // UR address walk requires body fire's inc_embed bit0 so lev1 offset is applied.
        auto append_embed_spaced = [&](IqInstructionFile& file, uint16_t width_bits,
                                       uint32_t steps, uint8_t ctrl_inc, uint32_t fire_slot,
                                       const std::vector<uint8_t>& fire_code,
                                       bool fire_inc_embed) {
            auto zero_code = serialize_code(0, width_bits);
            auto ctrl = make_instruction(
                1, 0, /*embed*/1, static_cast<uint16_t>(steps - 1), 0, 0, ctrl_inc, 0, 0,
                zero_code, width_bits);
            file.para_data.insert(file.para_data.end(), ctrl.begin(), ctrl.end());
            for (uint32_t slot = 0; slot < kSpacing; ++slot) {
                const bool is_fire = (slot == fire_slot);
                const bool is_last = (slot + 1 == kSpacing);
                auto body = make_instruction(
                    1, 0, /*embed*/0, 0, 0, 0, 0,
                    /*embed_end*/is_last ? 1u : 0u,
                    /*inc_embed*/(is_fire && fire_inc_embed) ? 1u : 0u,
                    is_fire ? fire_code : zero_code, width_bits);
                file.para_data.insert(file.para_data.end(), body.begin(), body.end());
            }
        };

        append_rtovr_static(MD_RTOVR_OUT_DVR_FPADD_S0, MD_RTOVR_IN_UR_RDATA_0);
        {
            // First period: S1=0; then feedback for the rest of the job.
            IqInstructionFile file;
            file.para_iq_id = v421::rtovr_iq_id(MD_RTOVR_OUT_DVR_FPADD_S1);
            file.para_iq_name = "rtovr-" + std::to_string(MD_RTOVR_OUT_DVR_FPADD_S1);
            file.para_width_bits = 41 + 7;
            auto z = serialize_code(
                make_single_rtovr_code(MD_RTOVR_OUT_DVR_FPADD_S1, MD_RTOVR_IN_ZERO), 7);
            auto fb = serialize_code(
                make_single_rtovr_code(MD_RTOVR_OUT_DVR_FPADD_S1, MD_RTOVR_IN_DR_FPADD_D), 7);
            auto zero_code = serialize_code(0, 7);
            append_hold_code(file, 7, z, kSpacing);
            append_hold_code(file, 7, fb, hold_cycles - kSpacing);
            auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0, 0, zero_code, 7);
            file.para_data.insert(file.para_data.end(), end.begin(), end.end());
            files.push_back(file);
        }
        append_rtovr_static(MD_RTOVR_OUT_DVR_FP32ADDTREE8TO1_S0, MD_RTOVR_IN_DR_FPADD_D);
        append_rtovr_static(MD_RTOVR_OUT_DVR_FP32ADDTREE8TO1_S1, MD_RTOVR_IN_ZERO);
        append_rtovr_static(MD_RTOVR_OUT_DVR_FPMUL_S0, MD_RTOVR_IN_UR_RDATA_2);
        append_rtovr_static(MD_RTOVR_OUT_DVR_FPMUL_S1, MD_RTOVR_IN_DR_FP32ADDTREE8TO1_D);
        append_rtovr_static(MD_RTOVR_OUT_UVR_WDATA_0, MD_RTOVR_IN_DR_FPMUL_D);

        // UR-R0: one embed per bank. UR micro-addr is only 8 bits (one bank); INC cannot
        // cross banks — must restart with a new bank code for each 256-word tile.
        {
            IqInstructionFile file;
            file.para_iq_id = v421::kIqIdUrR0;
            file.para_iq_name = "ur-r0";
            file.para_width_bits = 41 + kUrRBits;
            auto zero_code = serialize_code(0, kUrRBits);
            for (uint32_t tile = 0; tile < num_tiles; ++tile) {
                iq::UrCru cru;
                cru.para_re[0] = true;
                cru.para_raddr[0].bank = MD_LLAMA_TILE_BANKS[tile];
                cru.para_raddr[0].addr_word = 0;
                auto fire_code = serialize_code(
                    mean_dim_detail::extract_ur_read_port_code(cru, 0, smc_en), kUrRBits);
                append_embed_spaced(
                    file, kUrRBits, kTileWords, /*ctrl_inc*/1, kUrSlot, fire_code,
                    /*fire_inc_embed*/true);
            }
            auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0, 0, zero_code, kUrRBits);
            file.para_data.insert(file.para_data.end(), end.begin(), end.end());
            files.push_back(file);
        }

        // UR-R2: alpha held past FPMUL.
        {
            IqInstructionFile file;
            file.para_iq_id = v421::kIqIdUrR2;
            file.para_iq_name = "ur-r2";
            file.para_width_bits = 41 + kUrRBits;
            auto code_bytes = serialize_code(
                mean_dim_detail::extract_ur_read_port_code(para_ur_read_crus[0], 2, smc_en),
                kUrRBits);
            auto zero_code = serialize_code(0, kUrRBits);
            append_hold_code(file, kUrRBits, code_bytes, hold_cycles);
            auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0, 0, zero_code, kUrRBits);
            file.para_data.insert(file.para_data.end(), end.begin(), end.end());
            files.push_back(file);
        }

        // FPADD: spaced once per word; aligned kFpaddSlot after UR within each period.
        {
            IqInstructionFile file;
            file.para_iq_id = v421::kIqIdFpadd;
            file.para_iq_name = "fpadd";
            file.para_width_bits = 41 + kFpaddBits;
            auto fire_code = serialize_code(para_fpadd_inst, kFpaddBits);
            auto zero_code = serialize_code(0, kFpaddBits);
            append_embed_spaced(
                file, kFpaddBits, total_words, /*ctrl_inc*/0, kFpaddSlot, fire_code,
                /*fire_inc_embed*/false);
            auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0, 0, zero_code, kFpaddBits);
            file.para_data.insert(file.para_data.end(), end.begin(), end.end());
            files.push_back(file);
        }

        // Post: wait job_cycles then AddTree → FPMUL → UR-W.
        auto append_post_wait_then_fire = [&](uint32_t iq_id, const char* name, uint16_t width_bits,
                                              uint64_t fire_code, int extra_drain7) {
            IqInstructionFile file;
            file.para_iq_id = iq_id;
            file.para_iq_name = name;
            file.para_width_bits = 41 + width_bits;
            auto zero_code = serialize_code(0, width_bits);
            auto fire_bytes = serialize_code(fire_code, width_bits);
            append_hold_code(file, width_bits, zero_code, job_cycles);
            for (int i = 0; i < 2 + extra_drain7; ++i) {
                auto drain =
                    make_instruction(1, 0, kNoEmbed, 0, 0, 7, 0, 0, 0, zero_code, width_bits);
                file.para_data.insert(file.para_data.end(), drain.begin(), drain.end());
            }
            auto fire =
                make_instruction(1, 0, kNoEmbed, 0, 0, 4, 0, 0, 0, fire_bytes, width_bits);
            file.para_data.insert(file.para_data.end(), fire.begin(), fire.end());
            auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0, 0, zero_code, width_bits);
            file.para_data.insert(file.para_data.end(), end.begin(), end.end());
            files.push_back(file);
        };
        append_post_wait_then_fire(
            v421::kIqIdFp32AddTree8to1, "fp32addtree8to1", kAddTreeBits, para_addtree8_inst, 0);
        append_post_wait_then_fire(
            v421::kIqIdFpmul, "fpmul", kFpmulBits, para_fpmul_inst & 0xFFu, 3);

        {
            IqInstructionFile file;
            file.para_iq_id = v421::kIqIdUrW0;
            file.para_iq_name = "ur-w0";
            file.para_width_bits = 41 + kUrWBits;
            auto serialize_ur_wdata_inst = [&](uint8_t vld, uint8_t jump, uint8_t embed,
                                               uint16_t loops, uint8_t cond, uint8_t dly,
                                               uint8_t inc, uint64_t code_33) {
                uint64_t header =
                    serialize_header_bits(vld, jump, embed, loops, cond, dly, inc, 0, 0);
                unsigned __int128 inst_74 =
                    (static_cast<unsigned __int128>(header) << kUrWBits) |
                    static_cast<unsigned __int128>(code_33 & ((1ull << kUrWBits) - 1ull));
                std::vector<uint8_t> bytes;
                for (int i = 9; i >= 0; --i)
                    bytes.push_back(static_cast<uint8_t>((inst_74 >> (i * 8)) & 0xFF));
                return bytes;
            };
            uint64_t code =
                mean_dim_detail::extract_ur_write_port_code(para_ur_write_crus[0], 0, smc_en);
            // Wait job_cycles via zero-code hold (pack into loops).
            {
                auto zero_bytes = serialize_code(0, kUrWBits);
                // Reuse make_instruction path for hold; width includes header via helper above.
                uint32_t left = job_cycles;
                while (left > 0) {
                    const uint32_t chunk = std::min<uint32_t>(left, 1023);
                    auto head = serialize_ur_wdata_inst(1, 0, kNoEmbed, 0, 0, 0, 0, 0);
                    file.para_data.insert(file.para_data.end(), head.begin(), head.end());
                    if (chunk > 1) {
                        auto rest = serialize_ur_wdata_inst(
                            1, 0, 0u, static_cast<uint16_t>(chunk - 1), 0, 0, 0, 0);
                        file.para_data.insert(file.para_data.end(), rest.begin(), rest.end());
                    }
                    left -= chunk;
                    (void)zero_bytes;
                }
            }
            for (int i = 0; i < 2 + 6; ++i) {
                auto drain = serialize_ur_wdata_inst(1, 0, kNoEmbed, 0, 0, 7, 0, 0);
                file.para_data.insert(file.para_data.end(), drain.begin(), drain.end());
            }
            auto fire = serialize_ur_wdata_inst(1, 0, kNoEmbed, 0, 0, 4, 0, code);
            file.para_data.insert(file.para_data.end(), fire.begin(), fire.end());
            auto end_inst = serialize_ur_wdata_inst(0, 1, 0, 0, 0, 0, 0, 0);
            file.para_data.insert(file.para_data.end(), end_inst.begin(), end_inst.end());
            files.push_back(file);
        }
        return files;
    }

    if (para_hardware_reduce) {
        constexpr uint32_t kFpaddSpacing = 6;
        constexpr uint32_t kFirstFpaddCycle = 5;
        constexpr uint32_t kReadToFpaddGap = 1;
        constexpr uint32_t kFpaddToFpmulGap = 6;
        constexpr uint32_t kFpmulToWriteGap = 6;
        constexpr uint32_t kGroupTailGap = 8;

        auto append_scheduled = [&](IqInstructionFile& file,
                                    int& last_cycle,
                                    uint32_t target_cycle,
                                    const std::vector<uint8_t>& code_bytes,
                                    uint16_t code_bits) {
            while (target_cycle > static_cast<uint32_t>(last_cycle + 8)) {
                auto zero_code = serialize_code(0, code_bits);
                auto dummy = make_instruction(1, 0, 0, 0, 0, kMaxDlyField, 0, 0, 0, zero_code, code_bits);
                file.para_data.insert(file.para_data.end(), dummy.begin(), dummy.end());
                last_cycle += 8;
            }
            uint8_t dly = static_cast<uint8_t>(target_cycle - static_cast<uint32_t>(last_cycle + 1));
            auto inst = make_instruction(1, 0, 0, 0, 0, dly, 0, 0, 0, code_bytes, code_bits);
            file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
            last_cycle = static_cast<int>(target_cycle);
        };

        auto append_end = [&](IqInstructionFile& file, int& last_cycle, uint16_t code_bits) {
            const uint32_t end_cycle = static_cast<uint32_t>(std::max(0, last_cycle)) + kGroupTailGap;
            auto zero_code = serialize_code(0, code_bits);
            append_scheduled(file, last_cycle, end_cycle, zero_code, code_bits);
            // Mark the terminal instruction as JUMP with zero code.
            if (!file.para_data.empty()) {
                std::vector<uint8_t> end_inst = make_instruction(1, 1, 0, 0, 0, 0, 0, 0, 0, zero_code, code_bits);
                file.para_data.insert(file.para_data.end(), end_inst.begin(), end_inst.end());
            }
        };

        const uint32_t total_input_words = para_total_steps;
        const uint32_t reduce_words = std::max<uint32_t>(1, para_reduce_size);
        const uint32_t output_words = para_output_words;
        const uint32_t group_stride = reduce_words * kFpaddSpacing + kFpaddToFpmulGap +
                                      kFpmulToWriteGap + kGroupTailGap;

        auto fpadd_cycle = [&](uint32_t group, uint32_t r) {
            return group * group_stride + kFirstFpaddCycle + r * kFpaddSpacing;
        };
        auto fpmul_cycle = [&](uint32_t group) {
            return fpadd_cycle(group, reduce_words - 1) + kFpaddToFpmulGap;
        };
        auto write_cycle = [&](uint32_t group) {
            return fpmul_cycle(group) + kFpmulToWriteGap;
        };

        // UR_RDATA_0: raw input words.
        {
            IqInstructionFile file;
            file.para_iq_id = 14;
            file.para_iq_name = "ur_rdata_0";
            file.para_width_bits = 41 + 12;
            int last_cycle = -1;
            for (uint32_t iw = 0; iw < total_input_words; ++iw) {
                iq::UrCru cru = para_ur_read_crus[0];
                cru.para_raddr[0].addr_word = static_cast<uint16_t>(iw);
                uint32_t code = mean_dim_detail::extract_ur_read_port_code(cru, 0);
                uint32_t group = iw / reduce_words;
                uint32_t r = iw % reduce_words;
                uint32_t cyc = fpadd_cycle(group, r) - kReadToFpaddGap;
                append_scheduled(file, last_cycle, cyc, serialize_code(code, 12), 12);
            }
            append_end(file, last_cycle, 12);
            files.push_back(file);
        }

        // UR_RDATA_2: alpha broadcast. One read is enough because the UR output is held.
        {
            IqInstructionFile file;
            file.para_iq_id = 16;
            file.para_iq_name = "ur_rdata_2";
            file.para_width_bits = 41 + 12;
            int last_cycle = -1;
            uint32_t code = mean_dim_detail::extract_ur_read_port_code(para_ur_read_crus[0], 2);
            append_scheduled(file, last_cycle, kFirstFpaddCycle - kReadToFpaddGap, serialize_code(code, 12), 12);
            append_end(file, last_cycle, 12);
            files.push_back(file);
        }

        auto emit_rtovr_port_file = [&](uint8_t port, const std::vector<std::pair<uint32_t, uint8_t>>& events) {
            IqInstructionFile file;
            file.para_iq_id = 24 + port; // Informational only; simulator uses the name.
            file.para_iq_name = "rtovr-" + std::to_string(port);
            file.para_width_bits = 41 + 7;
            int last_cycle = -1;
            for (auto [cyc, code] : events) {
                append_scheduled(file, last_cycle, cyc, serialize_code(code, 7), 7);
            }
            append_end(file, last_cycle, 7);
            files.push_back(file);
        };

        const uint8_t rtovr_fpadd_s0 = extract_rtovr_port_code(para_rtovr_stage1, MD_RTOVR_OUT_DVR_FPADD_S0);
        const uint8_t rtovr_fpadd_s1_feedback = extract_rtovr_port_code(para_rtovr_stage1, MD_RTOVR_OUT_DVR_FPADD_S1);
        const uint8_t rtovr_fpmul_s0 = extract_rtovr_port_code(para_rtovr_stage1, MD_RTOVR_OUT_DVR_FPMUL_S0);
        const uint8_t rtovr_fpmul_s1 = extract_rtovr_port_code(para_rtovr_stage1, MD_RTOVR_OUT_DVR_FPMUL_S1);
        const uint8_t rtovr_wdata0 = extract_rtovr_port_code(para_rtovr_stage3, MD_RTOVR_OUT_UVR_WDATA_0);
        auto make_single_rtovr_code = [&](uint8_t port, uint8_t select) -> uint8_t {
            iq::RtoVrCru cru;
            cru.para_vld = true;
            for (int i = 0; i < 40; ++i) {
                cru.para_out[i].para_valid = false;
                cru.para_out[i].para_select = 0;
            }
            cru.para_out[port].para_valid = true;
            cru.para_out[port].para_select = select;
            uint32_t words[10];
            iq::RtoVrIq::pack_cru_rtovr_words(cru, words);
            return extract_rtovr_port_code(std::vector<uint32_t>(words, words + 9), port);
        };
        const uint8_t rtovr_fpadd_s1_zero = make_single_rtovr_code(MD_RTOVR_OUT_DVR_FPADD_S1, 34);

        emit_rtovr_port_file(MD_RTOVR_OUT_DVR_FPADD_S0, {{0, rtovr_fpadd_s0}});
        emit_rtovr_port_file(MD_RTOVR_OUT_DVR_FPMUL_S0, {{0, rtovr_fpmul_s0}});
        emit_rtovr_port_file(MD_RTOVR_OUT_DVR_FPMUL_S1, {{0, rtovr_fpmul_s1}});
        emit_rtovr_port_file(MD_RTOVR_OUT_UVR_WDATA_0, {{0, rtovr_wdata0}});

        // FPADD_S1 must be zero on the first item of each group, then feedback.
        {
            std::vector<std::pair<uint32_t, uint8_t>> events;
            for (uint32_t group = 0; group < output_words; ++group) {
                events.push_back({group * group_stride, rtovr_fpadd_s1_zero});
                if (reduce_words > 1) {
                    events.push_back({fpadd_cycle(group, 1) - 1, rtovr_fpadd_s1_feedback});
                }
            }
            emit_rtovr_port_file(MD_RTOVR_OUT_DVR_FPADD_S1, events);
        }

        // FPADD: issue once per raw input word.
        {
            IqInstructionFile file;
            file.para_iq_id = 6;
            file.para_iq_name = "fpadd";
            file.para_width_bits = 41 + 5;
            int last_cycle = -1;
            auto code = serialize_code(para_fpadd_inst, 5);
            for (uint32_t iw = 0; iw < total_input_words; ++iw) {
                uint32_t group = iw / reduce_words;
                uint32_t r = iw % reduce_words;
                append_scheduled(file, last_cycle, fpadd_cycle(group, r), code, 5);
            }
            append_end(file, last_cycle, 5);
            files.push_back(file);
        }

        // FPMUL: only after each group has produced its final sum.
        {
            IqInstructionFile file;
            file.para_iq_id = 5;
            file.para_iq_name = "fpmul";
            file.para_width_bits = 41 + 3;
            int last_cycle = -1;
            auto code = serialize_code(para_fpmul_inst, 3);
            for (uint32_t group = 0; group < output_words; ++group) {
                append_scheduled(file, last_cycle, fpmul_cycle(group), code, 3);
            }
            append_end(file, last_cycle, 3);
            files.push_back(file);
        }

        // UR_WDATA_0: write one output word per reduce group.
        {
            IqInstructionFile file;
            file.para_iq_id = 18;
            file.para_iq_name = "ur_wdata_0";
            file.para_width_bits = 41 + 28;

            auto serialize_ur_wdata_inst = [&](uint8_t vld, uint8_t jump, uint8_t embed, uint16_t loops,
                                               uint8_t cond, uint8_t dly, uint8_t inc,
                                               uint8_t embed_end_bits, uint8_t inc_embed_bits,
                                               uint32_t code_28) -> std::vector<uint8_t> {
                uint64_t header = serialize_header_bits(vld, jump, embed, loops, cond, dly, inc, embed_end_bits, inc_embed_bits);
                unsigned __int128 inst_69 = (static_cast<unsigned __int128>(header) << 28) |
                                            static_cast<unsigned __int128>(code_28 & 0x0FFFFFFFu);
                std::vector<uint8_t> bytes;
                for (int i = 8; i >= 0; --i)
                    bytes.push_back(static_cast<uint8_t>((inst_69 >> (i * 8)) & 0xFF));
                return bytes;
            };

            auto append_urw = [&](int& last_cycle, uint32_t target_cycle, uint32_t code) {
                while (target_cycle > static_cast<uint32_t>(last_cycle + 8)) {
                    auto dummy = serialize_ur_wdata_inst(1, 0, 0, 0, 0, kMaxDlyField, 0, 0, 0, 0);
                    file.para_data.insert(file.para_data.end(), dummy.begin(), dummy.end());
                    last_cycle += 8;
                }
                uint8_t dly = static_cast<uint8_t>(target_cycle - static_cast<uint32_t>(last_cycle + 1));
                auto inst = serialize_ur_wdata_inst(1, 0, 0, 0, 0, dly, 0, 0, 0, code);
                file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
                last_cycle = static_cast<int>(target_cycle);
            };

            int last_cycle = -1;
            for (uint32_t group = 0; group < output_words; ++group) {
                iq::UrCru cru = para_ur_write_crus[0];
                cru.para_waddr[0].addr_word = static_cast<uint16_t>(group);
                uint32_t code = mean_dim_detail::extract_ur_write_port_code(cru, 0);
                append_urw(last_cycle, write_cycle(group), code);
            }
            uint32_t end_cycle = static_cast<uint32_t>(std::max(0, last_cycle)) + kGroupTailGap;
            while (end_cycle > static_cast<uint32_t>(last_cycle + 8)) {
                auto dummy = serialize_ur_wdata_inst(1, 0, 0, 0, 0, kMaxDlyField, 0, 0, 0, 0);
                file.para_data.insert(file.para_data.end(), dummy.begin(), dummy.end());
                last_cycle += 8;
            }
            auto end_inst = serialize_ur_wdata_inst(1, 1, 0, 0, 0,
                                                    static_cast<uint8_t>(end_cycle - static_cast<uint32_t>(last_cycle + 1)),
                                                    0, 0, 0, 0);
            file.para_data.insert(file.para_data.end(), end_inst.begin(), end_inst.end());
            files.push_back(file);
        }

        if (para_enable_lsu && para_total_steps > 0) {
            if (para_enable_lsu_v2) {
                append_lsu_v2_files(files,
                                    para_total_steps,
                                    para_output_words,
                                    para_lsu_v2_input_ur_id,
                                    0,
                                    para_lsu_v2_output_ur_id,
                                    0,
                                    para_lsu_v2_input_gr_base,
                                    para_lsu_v2_output_gr_base,
                                    para_smc_count,
                                    para_smc_id,
                                    para_lsu_v2_byte_strb);
                return files;
            }
            {
                IqInstructionFile file;
                file.para_iq_id = kIqIdStb;
                file.para_iq_name = "stb";
                file.para_width_bits = 100;
                auto inst = make_stb_instruction(para_total_steps,
                                                 para_lsu_source_bank,
                                                 para_lsu_source_addr_bytes);
                file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
                files.push_back(file);
            }
            {
                IqInstructionFile file;
                file.para_iq_id = kIqIdLdb;
                file.para_iq_name = "ldb";
                file.para_width_bits = 106;
                auto inst = make_ldb_instruction(para_total_steps,
                                                 para_lsu_stage_bank,
                                                 para_lsu_stage_addr_bytes);
                file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
                files.push_back(file);
            }
        }

        return files;
    }

    // pre_sum_compat: mirror Sub's IQ shape (out = 0 + alpha * pre_sum).
    // Critical: first beat uses embed=7 (bypass EXE_EMBED0); drain uses embed=0+loops.
    const ScaleAddSteadyStateSchedule schedule{};
    const uint8_t kNoEmbed = ScaleAddSteadyStateSchedule::kNoEmbed;
    const uint16_t loops_inner = (para_total_steps >= 1) ? (para_total_steps - 1) : 0;
    const uint16_t loops_drain = static_cast<uint16_t>(loops_inner + ScaleAddSteadyStateSchedule::kPipelineDrain);
    const uint8_t inc_inner = 1;
    const uint8_t smc_en = 31;
    constexpr uint16_t kUrRBits = 17;
    constexpr uint16_t kUrWBits = 33;
    constexpr uint16_t kFpmulBits = 8;
    constexpr uint16_t kFpaddBits = 10;

    auto advance_ur_read_code = [](uint32_t code, uint32_t delta_words) -> uint32_t {
        const uint32_t addr = ((code >> 4) + delta_words) & 0xFFu;
        return (code & ~(0xFFu << 4)) | (addr << 4);
    };
    auto advance_ur_write_code = [](uint64_t code, uint32_t delta_words) -> uint64_t {
        const uint64_t addr = ((code >> 4) + delta_words) & 0xFFull;
        return (code & ~(0xFFull << 4)) | (addr << 4);
    };

    auto append_ur_read = [&](uint32_t iq_id, const char* name, int port, uint32_t total_dly,
                              uint8_t inc_on_rest) {
        IqInstructionFile file;
        file.para_iq_id = iq_id;
        file.para_iq_name = name;
        file.para_width_bits = 41 + kUrRBits;
        uint32_t code = mean_dim_detail::extract_ur_read_port_code(para_ur_read_crus[0], port, smc_en);
        auto code_bytes = serialize_code(code, kUrRBits);
        auto zero_code = serialize_code(0, kUrRBits);
        const uint8_t dly = emit_dummy_for_long_delay(total_dly, [&]() {
            auto nop = make_instruction(1, 0, kNoEmbed, 0, 0, kMaxDlyField, 0, 0, 0, zero_code, kUrRBits);
            file.para_data.insert(file.para_data.end(), nop.begin(), nop.end());
        });
        auto first = make_instruction(1, 0, kNoEmbed, 0, 0, dly, 0, 0u, 0u, code_bytes, kUrRBits);
        file.para_data.insert(file.para_data.end(), first.begin(), first.end());
        if (loops_drain > 0) {
            auto rest = make_instruction(
                1, 0, 0u, static_cast<uint16_t>(loops_drain - 1), 0, 0, inc_on_rest, 0u, 0u,
                serialize_code(advance_ur_read_code(code, 1), kUrRBits), kUrRBits);
            file.para_data.insert(file.para_data.end(), rest.begin(), rest.end());
        }
        auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0u, 0u, zero_code, kUrRBits);
        file.para_data.insert(file.para_data.end(), end.begin(), end.end());
        files.push_back(file);
    };

    // UR-R0: zero input (bank0); UR-R1: pre_sum; UR-R2: alpha broadcast (no INC)
    append_ur_read(v421::kIqIdUrR0, "ur-r0", 0, schedule.ur_r0, inc_inner);
    append_ur_read(v421::kIqIdUrR1, "ur-r1", 1, schedule.ur_r1, inc_inner);
    append_ur_read(v421::kIqIdUrR2, "ur-r2", 2, schedule.ur_r2, 0);

    auto append_rtovr_inst = [&](uint8_t port, uint8_t select, uint32_t total_dly) {
        IqInstructionFile file;
        file.para_iq_id = v421::rtovr_iq_id(port);
        file.para_iq_name = "rtovr-" + std::to_string(port);
        file.para_width_bits = 41 + 7;
        const uint8_t port_code = static_cast<uint8_t>(((select & 0x3Fu) << 1) | 1u);
        auto code_bytes = serialize_code(port_code, 7);
        auto zero_code = serialize_code(0, 7);
        if (port == MD_RTOVR_OUT_UVR_WDATA_0) {
            consume_startup_delay(
                total_dly,
                [&]() {
                    auto nop = make_instruction(1, 0, kNoEmbed, 0, 0, kMaxDlyField, 0, 0, 0, zero_code, 7);
                    file.para_data.insert(file.para_data.end(), nop.begin(), nop.end());
                },
                [&](uint8_t precise_dly) {
                    auto precise_nop =
                        make_instruction(1, 0, kNoEmbed, 0, 0, precise_dly, 0, 0, 0, zero_code, 7);
                    file.para_data.insert(file.para_data.end(), precise_nop.begin(), precise_nop.end());
                });
            auto first = make_instruction(1, 0, kNoEmbed, 0, 0, 0, 0, 0u, 0u, code_bytes, 7);
            file.para_data.insert(file.para_data.end(), first.begin(), first.end());
        } else {
            const uint8_t dly = emit_dummy_for_long_delay(total_dly, [&]() {
                auto nop = make_instruction(1, 0, kNoEmbed, 0, 0, kMaxDlyField, 0, 0, 0, zero_code, 7);
                file.para_data.insert(file.para_data.end(), nop.begin(), nop.end());
            });
            auto first = make_instruction(1, 0, kNoEmbed, 0, 0, dly, 0, 0u, 0u, code_bytes, 7);
            file.para_data.insert(file.para_data.end(), first.begin(), first.end());
        }
        if (loops_drain > 0) {
            auto rest = make_instruction(
                1, 0, 0u, static_cast<uint16_t>(loops_drain - 1), 0, 0, 0, 0u, 0u, code_bytes, 7);
            file.para_data.insert(file.para_data.end(), rest.begin(), rest.end());
        }
        auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0u, 0u, zero_code, 7);
        file.para_data.insert(file.para_data.end(), end.begin(), end.end());
        files.push_back(file);
    };

    // alpha(R2) * pre_sum(R1) → FPMUL; zero(R0) + FPMUL_D → FPADD → writeback
    append_rtovr_inst(MD_RTOVR_OUT_DVR_FPMUL_S0, 32, schedule.rtovr_fpmul_s0); // UR_RDATA_2
    append_rtovr_inst(MD_RTOVR_OUT_DVR_FPMUL_S1, 31, schedule.rtovr_fpmul_s1); // UR_RDATA_1
    append_rtovr_inst(MD_RTOVR_OUT_DVR_FPADD_S0, 30, schedule.rtovr_fpadd_s0); // UR_RDATA_0
    append_rtovr_inst(MD_RTOVR_OUT_DVR_FPADD_S1, MD_RTOVR_IN_DR_FPMUL_D, schedule.rtovr_fpadd_s1);
    append_rtovr_inst(MD_RTOVR_OUT_UVR_WDATA_0, MD_RTOVR_IN_DR_FPADD_D, schedule.rtovr_uwr0);

    auto append_fp_iq = [&](uint32_t iq_id, const char* name, uint16_t width_bits,
                            uint64_t code, uint32_t total_dly) {
        IqInstructionFile file;
        file.para_iq_id = iq_id;
        file.para_iq_name = name;
        file.para_width_bits = 41 + width_bits;
        auto code_bytes = serialize_code(code, width_bits);
        auto zero_code = serialize_code(0, width_bits);
        const uint8_t dly = emit_dummy_for_long_delay(total_dly, [&]() {
            auto nop = make_instruction(1, 0, kNoEmbed, 0, 0, kMaxDlyField, 0, 0, 0, zero_code, width_bits);
            file.para_data.insert(file.para_data.end(), nop.begin(), nop.end());
        });
        auto first = make_instruction(1, 0, kNoEmbed, 0, 0, dly, 0, 0u, 0u, code_bytes, width_bits);
        file.para_data.insert(file.para_data.end(), first.begin(), first.end());
        if (loops_drain > 0) {
            auto rest = make_instruction(
                1, 0, 0u, static_cast<uint16_t>(loops_drain - 1), 0, 0, 0, 0u, 0u, code_bytes, width_bits);
            file.para_data.insert(file.para_data.end(), rest.begin(), rest.end());
        }
        auto end = make_instruction(0, 1, 0, 0, 0, 0, 0, 0u, 0u, zero_code, width_bits);
        file.para_data.insert(file.para_data.end(), end.begin(), end.end());
        files.push_back(file);
    };

    append_fp_iq(
        v421::kIqIdFpmul, "fpmul", kFpmulBits,
        (static_cast<uint64_t>(para_fpmul_inst) & 0x7u) | (static_cast<uint64_t>(smc_en) << 3),
        schedule.fpmul);
    append_fp_iq(
        v421::kIqIdFpadd, "fpadd", kFpaddBits,
        (static_cast<uint64_t>(para_fpadd_inst) & 0x1Fu) | (static_cast<uint64_t>(smc_en) << 5),
        schedule.fpadd);

    {
        IqInstructionFile file;
        file.para_iq_id = v421::kIqIdUrW0;
        file.para_iq_name = "ur-w0";
        file.para_width_bits = 41 + kUrWBits;
        auto serialize_ur_wdata_inst = [&](uint8_t vld, uint8_t jump, uint8_t embed, uint16_t loops,
                                           uint8_t cond, uint8_t dly, uint8_t inc,
                                           uint8_t embed_end_bits, uint8_t inc_embed_bits,
                                           uint64_t code_33) -> std::vector<uint8_t> {
            uint64_t header = serialize_header_bits(vld, jump, embed, loops, cond, dly, inc,
                                                    embed_end_bits, inc_embed_bits);
            unsigned __int128 inst_74 =
                (static_cast<unsigned __int128>(header) << kUrWBits) |
                static_cast<unsigned __int128>(code_33 & ((1ull << kUrWBits) - 1ull));
            std::vector<uint8_t> bytes;
            for (int i = 9; i >= 0; --i)
                bytes.push_back(static_cast<uint8_t>((inst_74 >> (i * 8)) & 0xFF));
            return bytes;
        };
        uint64_t code = mean_dim_detail::extract_ur_write_port_code(para_ur_write_crus[0], 0, smc_en);
        uint32_t total_dly = schedule.ur_w0;
        consume_startup_delay(
            total_dly,
            [&]() {
                auto dummy =
                    serialize_ur_wdata_inst(1, 0, kNoEmbed, 0, 0, kMaxDlyField, 0, 0, 0, 0);
                file.para_data.insert(file.para_data.end(), dummy.begin(), dummy.end());
            },
            [&](uint8_t precise_dly) {
                auto precise_dummy =
                    serialize_ur_wdata_inst(1, 0, kNoEmbed, 0, 0, precise_dly, 0, 0, 0, 0);
                file.para_data.insert(file.para_data.end(), precise_dummy.begin(), precise_dummy.end());
            });
        auto first = serialize_ur_wdata_inst(1, 0, kNoEmbed, 0, 0, 0, 0, 0u, 0u, code);
        file.para_data.insert(file.para_data.end(), first.begin(), first.end());
        if (loops_inner > 0) {
            auto rest = serialize_ur_wdata_inst(
                1, 0, 0u, static_cast<uint16_t>(loops_inner - 1), 0, 0, inc_inner, 0u, 0u,
                advance_ur_write_code(code, 1));
            file.para_data.insert(file.para_data.end(), rest.begin(), rest.end());
        }
        auto end_inst = serialize_ur_wdata_inst(0, 1, 0, 0, 0, 0, 0, 0u, 0u, 0);
        file.para_data.insert(file.para_data.end(), end_inst.begin(), end_inst.end());
        files.push_back(file);
    }

    // LSU side-channel: copy pre_sum (bank1) into a staging bank. This keeps the
    // existing compute path intact while exercising the Load/Store path for each
    // partial word used by MeanDim.
    if (para_enable_lsu && para_total_steps > 0) {
        if (para_enable_lsu_v2) {
            append_lsu_v2_files(files,
                                para_total_steps,
                                para_output_words,
                                para_lsu_v2_input_ur_id,
                                0,
                                para_lsu_v2_output_ur_id,
                                0,
                                para_lsu_v2_input_gr_base,
                                para_lsu_v2_output_gr_base,
                                para_smc_count,
                                para_smc_id,
                                para_lsu_v2_byte_strb);
            return files;
        }
        {
            IqInstructionFile file;
            file.para_iq_id = kIqIdStb;
            file.para_iq_name = "stb";
            file.para_width_bits = 100;
            auto inst = make_stb_instruction(para_total_steps,
                                             para_lsu_source_bank,
                                             para_lsu_source_addr_bytes);
            file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
            files.push_back(file);
        }
        {
            IqInstructionFile file;
            file.para_iq_id = kIqIdLdb;
            file.para_iq_name = "ldb";
            file.para_width_bits = 106;
            auto inst = make_ldb_instruction(para_total_steps,
                                             para_lsu_stage_bank,
                                             para_lsu_stage_addr_bytes);
            file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());
            files.push_back(file);
        }
    }

    // Cascade side-channel: route FPADD_D into SHIFTDN so an 8-SMC RTL case can
    // observe and chain each SMC's partial result.
    if (para_enable_cascade && !para_rtovr_stage_shift.empty()) {
        auto active_ports = extract_active_rtovr_ports(para_rtovr_stage_shift);
        for (uint8_t port : active_ports) {
            IqInstructionFile file;
            file.para_iq_id = 27;
            file.para_iq_name = "rtovr-" + std::to_string(port);
            file.para_width_bits = 41 + 7;
            const uint8_t port_code = extract_rtovr_port_code(para_rtovr_stage_shift, port);
            auto code_bytes = serialize_code(port_code, 7);

            uint32_t route_total_dly = 8;
            while (route_total_dly > 7) {
                auto zero_code_tmp = serialize_code(0, 7);
                auto dummy = make_instruction(1, 0, 0, 0, 0, 7, 0, 0, 0, zero_code_tmp, 7);
                file.para_data.insert(file.para_data.end(), dummy.begin(), dummy.end());
                route_total_dly -= 8;
            }
            const uint8_t route_dly = static_cast<uint8_t>(route_total_dly);

            auto inst = make_instruction(1, 0, 0u, loops_drain, 0, route_dly, 0, 0u, 0u, code_bytes, 7);
            file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());

            auto zero_code = serialize_code(0, 7);
            auto end_inst = make_instruction(1, 1, 0, 0, 0, route_dly, 0, 0u, 0u, zero_code, 7);
            file.para_data.insert(file.para_data.end(), end_inst.begin(), end_inst.end());
            files.push_back(file);
        }

        {
            IqInstructionFile file;
            file.para_iq_id = 13;
            file.para_iq_name = "shiftdn";
            file.para_width_bits = 41 + 14;
            auto code_bytes = serialize_code(para_shiftdn_inst, 14);
            const uint8_t shift_dly = 2;

            auto inst = make_instruction(1, 0, 0u, loops_drain, 0, shift_dly, 0, 0u, 0u, code_bytes, 14);
            file.para_data.insert(file.para_data.end(), inst.begin(), inst.end());

            auto zero_code = serialize_code(0, 14);
            auto end_inst = make_instruction(1, 1, 0, 0, 0, shift_dly, 0, 0u, 0u, zero_code, 14);
            file.para_data.insert(file.para_data.end(), end_inst.begin(), end_inst.end());
            files.push_back(file);
        }
    }

    return files;
}

// ============================================================================
// OpBase 接口
// ============================================================================

std::string MeanDimOp::get_name() const {
    return "MeanDim";
}

OpInstructionsBase* MeanDimOp::compile(const app::AppOperatorRequest& req) {
    MeanDimOpParams params;
    params.para_n = req.para_dimensions.para_n;
    params.para_c = req.para_dimensions.para_c;
    params.para_h = req.para_dimensions.para_h;
    params.para_w = req.para_dimensions.para_w;

    auto it = req.para_parameters.find("reduce_size");
    if (it != req.para_parameters.end() && !it->second.para_data_i32.empty()) {
        params.para_reduce_size = static_cast<uint32_t>(it->second.para_data_i32[0]);
    } else {
        params.para_reduce_size = 4;
    }
    params.para_dim = get_i32_param_from_req(req, "dim", -1);
    params.para_keepdim = get_i32_param_from_req(req, "keepdim", 1) != 0;
    params.para_reduce_elems = static_cast<uint32_t>(
        std::max(0, get_i32_param_from_req(req, "reduce_elems",
                                           static_cast<int>(req.para_dimensions.para_w))));
    params.para_llama_dim_reduce = is_llama_dim_reduce_request(req);

    if (!req.para_inputs.empty()) {
        const auto& first_input = req.para_inputs.begin()->second;
        switch (first_input.para_dtype) {
            case app::AppDataType::FLOAT32: params.para_dtype = MeanDimDataType::FP32; break;
            case app::AppDataType::FLOAT16: params.para_dtype = MeanDimDataType::FP16; break;
            default: params.para_dtype = MeanDimDataType::FP32; break;
        }
    }

    auto get_i32_param = [&](const std::string& key, int def) -> int {
        auto pit = req.para_parameters.find(key);
        if (pit != req.para_parameters.end() && !pit->second.para_data_i32.empty()) {
            return pit->second.para_data_i32[0];
        }
        return def;
    };
    params.para_enable_lsu = get_i32_param("enable_lsu", 0) != 0;
    params.para_enable_lsu_v2 = get_i32_param("enable_lsu_v2", 0) != 0;
    if (params.para_enable_lsu_v2) {
        params.para_enable_lsu = true;
    }
    params.para_enable_cascade = get_i32_param("enable_cascade", 0) != 0;
    params.para_pre_sum_compat = get_i32_param("pre_sum_compat", 0) != 0;
    params.para_hardware_reduce = !params.para_pre_sum_compat &&
                                  (get_i32_param("hardware_reduce", 1) != 0);
    if (params.para_llama_dim_reduce) {
        const bool strict_hardware_path = get_i32_param("strict_hardware_path", 0) != 0;
        const bool llama_chunk_reduce = get_i32_param("llama_chunk_reduce", 0) != 0;
        const uint32_t elems_per_word = params.get_elems_per_word();
        params.para_reduce_size = std::max<uint32_t>(1, params.para_reduce_elems / elems_per_word);
        if (strict_hardware_path || llama_chunk_reduce) {
            if (params.para_dtype != MeanDimDataType::FP32) {
                throw std::runtime_error("MeanDim llama_chunk_reduce currently supports FP32 only");
            }
            if (params.para_reduce_size == 0 ||
                (params.para_reduce_size % MD_LLAMA_TILE_WORDS) != 0) {
                throw std::runtime_error(
                    "MeanDim llama_chunk_reduce requires reduce_size (words) multiple of 256");
            }
            params.para_llama_chunk_reduce = true;
            params.para_pre_sum_compat = false;
            params.para_hardware_reduce = false;
        } else {
            params.para_pre_sum_compat = true;
            params.para_hardware_reduce = false;
            params.para_llama_chunk_reduce = false;
        }
    }
    params.para_smc_id = static_cast<uint8_t>(std::max(0, get_i32_param("smc_id", 0)) & 0x1F);
    params.para_smc_count = static_cast<uint8_t>(std::max(1, get_i32_param("smc_count", 8)) & 0x1F);
    params.para_lsu_stage_bank = static_cast<uint8_t>(std::max(0, get_i32_param("lsu_stage_bank", 4)) & 0x7);
    params.para_lsu_v2_input_gr_base = static_cast<uint64_t>(std::max(0, get_i32_param("lsu_v2_input_gr_base", 0)));
    params.para_lsu_v2_output_gr_base = static_cast<uint64_t>(std::max(0, get_i32_param("lsu_v2_output_gr_base", 0x1000)));
    params.para_lsu_v2_input_ur_id = static_cast<uint8_t>(std::max(0, get_i32_param("lsu_v2_input_ur_id", params.para_input_bank)) & 0x7);
    params.para_lsu_v2_output_ur_id = static_cast<uint8_t>(std::max(0, get_i32_param("lsu_v2_output_ur_id", params.para_output_bank)) & 0x7);
    params.para_lsu_v2_byte_strb = static_cast<uint8_t>(std::max(0, get_i32_param("lsu_v2_byte_strb", 0)) & 0xF);

    if (params.para_hardware_reduce) {
        const bool supported_reduce =
            params.para_reduce_size == 2 || params.para_reduce_size == 4 ||
            params.para_reduce_size == 8 || params.para_reduce_size == 16;
        if (!supported_reduce) {
            throw std::runtime_error("MeanDim hardware_reduce supports reduce_size 2/4/8/16 in this version");
        }
    }

    MeanDimOpInstructions* insts = new MeanDimOpInstructions();
    *insts = compile(params);
    return insts;
}

bool MeanDimOp::calculate_golden(const app::AppOperatorRequest& req,
                                 std::vector<uint8_t>& golden_bin) {
    golden_bin.clear();

    const auto& inputs = req.para_inputs;
    app::AppDataType dtype = app::AppDataType::FLOAT32;
    auto get_i32_param = [&](const std::string& key, int def) -> int {
        auto pit = req.para_parameters.find(key);
        if (pit != req.para_parameters.end() && !pit->second.para_data_i32.empty()) {
            return pit->second.para_data_i32[0];
        }
        return def;
    };
    const bool pre_sum_compat = get_i32_param("pre_sum_compat", 0) != 0;
    const bool hardware_reduce = !pre_sum_compat && (get_i32_param("hardware_reduce", 1) != 0);

    auto emit_float = [&](float out) {
        if (dtype == app::AppDataType::FLOAT32) {
            uint32_t bits; memcpy(&bits, &out, sizeof(float));
            golden_bin.push_back(bits & 0xFF);
            golden_bin.push_back((bits >> 8) & 0xFF);
            golden_bin.push_back((bits >> 16) & 0xFF);
            golden_bin.push_back((bits >> 24) & 0xFF);
        } else {
            uint16_t bits = app::float32_to_float16(out);
            golden_bin.push_back(bits & 0xFF);
            golden_bin.push_back((bits >> 8) & 0xFF);
        }
    };

    if (is_llama_dim_reduce_request(req)) {
        uint32_t tokens = 0;
        uint32_t elems_per_word = 4;
        std::vector<float> pre_sum = build_llama_mean_presum(req, dtype, tokens, elems_per_word);
        const uint32_t reduce_elems =
            static_cast<uint32_t>(get_i32_param("reduce_elems", req.para_dimensions.para_w));
        if (pre_sum.empty() || reduce_elems == 0) return false;
        for (uint32_t t = 0; t < tokens; ++t) {
            const float mean = pre_sum[t * elems_per_word] / static_cast<float>(reduce_elems);
            emit_float(mean);
            for (uint32_t lane = 1; lane < elems_per_word; ++lane) {
                emit_float(0.0f);
            }
        }
        return true;
    }

    // alpha
    std::vector<float> alpha_f32;
    auto alpha_it = req.para_parameters.find("alpha");
    if (alpha_it != req.para_parameters.end()) {
        alpha_f32 = alpha_it->second.para_data_f32;
    }

    if (hardware_reduce) {
        std::vector<float> input_f32;
        auto input_it = inputs.find("input_tensor");
        if (input_it != inputs.end()) {
            dtype = input_it->second.para_dtype;
            input_f32 = input_it->second.para_data_f32;
        }
        const uint32_t elems_per_word = (dtype == app::AppDataType::FLOAT16) ? 8 : 4;
        const uint32_t reduce_words = std::max(1, get_i32_param("reduce_size", 4));
        const uint32_t total_words = static_cast<uint32_t>(input_f32.size()) / elems_per_word;
        const uint32_t output_words = total_words / reduce_words;
        const float alpha = !alpha_f32.empty() ? alpha_f32[0] : (1.0f / static_cast<float>(reduce_words));

        for (uint32_t ow = 0; ow < output_words; ++ow) {
            for (uint32_t lane = 0; lane < elems_per_word; ++lane) {
                float sum = 0.0f;
                for (uint32_t r = 0; r < reduce_words; ++r) {
                    uint32_t idx = (ow * reduce_words + r) * elems_per_word + lane;
                    float v = input_f32[idx];
                    if (dtype == app::AppDataType::FLOAT16) {
                        v = app::float16_to_float32(app::float32_to_float16(v));
                    }
                    sum += v;
                    if (dtype == app::AppDataType::FLOAT16) {
                        sum = app::float16_to_float32(app::float32_to_float16(sum));
                    }
                }
                float out = sum * alpha;
                if (dtype == app::AppDataType::FLOAT16) {
                    out = app::float16_to_float32(app::float32_to_float16(out));
                }
                emit_float(out);
            }
        }
        return true;
    }

    // Legacy pre_sum compatibility path: out = alpha * pre_sum.
    std::vector<float> other_f32;
    auto other_it = inputs.find("other_tensor");
    if (other_it != inputs.end()) {
        dtype = other_it->second.para_dtype;
        other_f32 = other_it->second.para_data_f32;
    }
    const uint32_t w = req.para_dimensions.para_w;
    size_t n = other_f32.size();

    for (size_t i = 0; i < n; ++i) {
        float a = (!alpha_f32.empty() && w > 0) ? alpha_f32[i % w] : 1.0f;
        float out;

        if (dtype == app::AppDataType::FLOAT16) {
            double a_fp16 = static_cast<double>(app::float16_to_float32(app::float32_to_float16(a)));
            double other_fp16 = static_cast<double>(app::float16_to_float32(app::float32_to_float16(other_f32[i])));
            double mul_d = a_fp16 * other_fp16;
            double mul_fp16 = static_cast<double>(app::float16_to_float32(app::float32_to_float16(static_cast<float>(mul_d))));
            out = static_cast<float>(app::float16_to_float32(app::float32_to_float16(static_cast<float>(mul_fp16))));
        } else {
            out = a * other_f32[i];
        }

        emit_float(out);
    }

    return true;
}

void MeanDimOp::fill_random_request(app::AppOperatorRequest& req,
                                    std::mt19937& rng,
                                    std::uniform_real_distribution<float>& data_dist,
                                    const std::string& dtype_str) {
    req.para_operator = "MeanDim";

    app::AppDataType target_type = app::AppDataType::FLOAT32;
    if (dtype_str == "fp16") target_type = app::AppDataType::FLOAT16;

    uint32_t elems_per_word = (target_type == app::AppDataType::FLOAT16) ? 8 : 4;

    uint32_t total_elems = req.para_dimensions.para_n * req.para_dimensions.para_c *
                           req.para_dimensions.para_h * req.para_dimensions.para_w;
    uint32_t total_words = total_elems / elems_per_word;
    if (total_words < 4) {
        req.para_dimensions.para_w = 4 * elems_per_word;
        total_elems = req.para_dimensions.para_n * req.para_dimensions.para_c *
                      req.para_dimensions.para_h * req.para_dimensions.para_w;
        total_words = total_elems / elems_per_word;
    }

    auto get_existing_i32 = [&](const std::string& key, int def) -> int {
        auto it = req.para_parameters.find(key);
        if (it != req.para_parameters.end() && !it->second.para_data_i32.empty()) {
            return it->second.para_data_i32[0];
        }
        return def;
    };
    const bool pre_sum_compat = get_existing_i32("pre_sum_compat", 0) != 0;
    const bool hardware_reduce = !pre_sum_compat && (get_existing_i32("hardware_reduce", 1) != 0);

    int requested_reduce_size = get_existing_i32("reduce_size", 0);
    uint32_t reduce_size = 0;
    if (requested_reduce_size > 0) {
        reduce_size = static_cast<uint32_t>(requested_reduce_size);
        while (total_words % reduce_size != 0 || total_words / reduce_size < 1) {
            req.para_dimensions.para_w += elems_per_word;
            total_elems = req.para_dimensions.para_n * req.para_dimensions.para_c *
                          req.para_dimensions.para_h * req.para_dimensions.para_w;
            total_words = total_elems / elems_per_word;
        }
    } else {
        // Find valid product-grade reduce sizes, then pick one randomly.
        std::vector<uint32_t> valid_rs;
        for (uint32_t rs : {2u, 4u, 8u, 16u}) {
            if (total_words % rs == 0 && total_words / rs >= 1)
                valid_rs.push_back(rs);
        }
        if (valid_rs.empty()) {
            // Fallback: force total_words to be even by incrementing W
            while (total_words % 2 != 0) {
                req.para_dimensions.para_w += elems_per_word;
                total_elems = req.para_dimensions.para_n * req.para_dimensions.para_c *
                              req.para_dimensions.para_h * req.para_dimensions.para_w;
                total_words = total_elems / elems_per_word;
            }
            valid_rs.push_back(2);
        }
        std::uniform_int_distribution<size_t> idx_dist(0, valid_rs.size() - 1);
        reduce_size = valid_rs[idx_dist(rng)];
    }

    uint32_t output_words = total_words / reduce_size;
    uint32_t output_elems = output_words * elems_per_word;

    // 生成原始输入数据
    std::vector<float> raw_input(total_elems);
    for (uint32_t i = 0; i < total_elems; ++i) {
        raw_input[i] = data_dist(rng);
    }

    // 预求和: 每 reduce_size 个 word (每个 word 有 elems_per_word 个元素)
    std::vector<float> pre_sum(output_elems, 0.0f);
    for (uint32_t ow = 0; ow < output_words; ++ow) {
        for (uint32_t r = 0; r < reduce_size; ++r) {
            uint32_t iw = ow * reduce_size + r;
            for (uint32_t e = 0; e < elems_per_word; ++e) {
                pre_sum[ow * elems_per_word + e] += raw_input[iw * elems_per_word + e];
            }
        }
    }

    if (pre_sum_compat) {
        // Legacy bringup path: reshape to pre_sum size because hardware only
        // sees one word per output.
        req.para_dimensions.para_n = 1;
        req.para_dimensions.para_c = 1;
        req.para_dimensions.para_h = output_words;
        req.para_dimensions.para_w = elems_per_word;
    }

    // input_tensor: hardware_reduce uses raw input; legacy path uses zero input.
    app::AppTensorDesc input_desc;
    input_desc.para_name = "input_tensor";
    input_desc.para_dtype = target_type;
    input_desc.para_shape = {req.para_dimensions.para_n, req.para_dimensions.para_c,
                             req.para_dimensions.para_h, req.para_dimensions.para_w};
    if (hardware_reduce) {
        input_desc.para_data_f32 = raw_input;
    } else {
        for (uint32_t i = 0; i < output_elems; ++i) {
            input_desc.para_data_f32.push_back(0.0f);
        }
    }
    req.para_inputs["input_tensor"] = input_desc;

    if (pre_sum_compat) {
        // other_tensor: pre_sum 数据 (bank1)
        app::AppTensorDesc other_desc;
        other_desc.para_name = "other_tensor";
        other_desc.para_dtype = target_type;
        other_desc.para_shape = input_desc.para_shape;
        other_desc.para_data_f32 = pre_sum;
        req.para_inputs["other_tensor"] = other_desc;
    } else {
        req.para_inputs.erase("other_tensor");
    }

    // alpha: 1/reduce_size (广播, 长度=W)
    float alpha_val = 1.0f / static_cast<float>(reduce_size);
    app::AppTensorDesc alpha_desc;
    alpha_desc.para_name = "alpha";
    alpha_desc.para_dtype = target_type;
    alpha_desc.para_shape = {req.para_dimensions.para_w};
    for (uint32_t i = 0; i < req.para_dimensions.para_w; ++i) {
        alpha_desc.para_data_f32.push_back(alpha_val);
    }
    req.para_parameters["alpha"] = alpha_desc;

    app::AppTensorDesc rs_desc;
    rs_desc.para_name = "reduce_size";
    rs_desc.para_dtype = app::AppDataType::INT32;
    rs_desc.para_shape = {1};
    rs_desc.para_data_i32.push_back(pre_sum_compat ? 1 : static_cast<int32_t>(reduce_size));
    req.para_parameters["reduce_size"] = rs_desc;

    app::AppTensorDesc hw_desc;
    hw_desc.para_name = "hardware_reduce";
    hw_desc.para_dtype = app::AppDataType::INT32;
    hw_desc.para_shape = {1};
    hw_desc.para_data_i32.push_back(hardware_reduce ? 1 : 0);
    req.para_parameters["hardware_reduce"] = hw_desc;
}

bool MeanDimOp::generate_data(const app::AppOperatorRequest& req,
                              std::vector<uint8_t>& input_bin,
                              std::vector<uint8_t>& other_bin,
                              std::vector<uint8_t>& alpha_bin) {
    input_bin.clear();
    other_bin.clear();
    alpha_bin.clear();

    auto write_tensor_data = [](std::vector<uint8_t>& bin, const app::AppTensorDesc& tensor) {
        if (tensor.para_dtype == app::AppDataType::FLOAT32) {
            for (float v : tensor.para_data_f32) {
                uint32_t bits; memcpy(&bits, &v, sizeof(float));
                bin.push_back(bits & 0xFF);
                bin.push_back((bits >> 8) & 0xFF);
                bin.push_back((bits >> 16) & 0xFF);
                bin.push_back((bits >> 24) & 0xFF);
            }
        } else if (tensor.para_dtype == app::AppDataType::FLOAT16) {
            for (float v : tensor.para_data_f32) {
                uint16_t bits = app::float32_to_float16(v);
                bin.push_back(bits & 0xFF);
                bin.push_back((bits >> 8) & 0xFF);
            }
        }
    };

    if (is_llama_dim_reduce_request(req)) {
        const bool strict_hardware_path =
            get_i32_param_from_req(req, "strict_hardware_path", 0) != 0;
        const bool llama_chunk_reduce =
            get_i32_param_from_req(req, "llama_chunk_reduce", 0) != 0;
        auto input_it = req.para_inputs.find("input_tensor");
        if (input_it == req.para_inputs.end()) return false;
        const app::AppDataType dtype = input_it->second.para_dtype;
        const uint32_t elems_per_word = (dtype == app::AppDataType::FLOAT16) ? 8 : 4;
        const uint32_t reduce_elems =
            static_cast<uint32_t>(get_i32_param_from_req(req, "reduce_elems",
                                                        static_cast<int>(req.para_dimensions.para_w)));
        const float alpha = 1.0f / static_cast<float>(std::max<uint32_t>(1, reduce_elems));

        if (strict_hardware_path || llama_chunk_reduce) {
            // Native path: raw input stays full-size; no software pre_sum in other.bin.
            write_tensor_data(input_bin, input_it->second);
            for (uint32_t lane = 0; lane < elems_per_word; ++lane) {
                emit_float_bytes(alpha_bin, alpha, dtype);
            }
            return true;
        }

        app::AppDataType presum_dtype = dtype;
        uint32_t tokens = 0;
        uint32_t epw = elems_per_word;
        std::vector<float> pre_sum = build_llama_mean_presum(req, presum_dtype, tokens, epw);
        if (pre_sum.empty()) return false;
        for (uint32_t i = 0; i < tokens * elems_per_word; ++i) {
            emit_float_bytes(input_bin, 0.0f, dtype);
        }
        for (float v : pre_sum) {
            emit_float_bytes(other_bin, v, dtype);
        }
        for (uint32_t lane = 0; lane < elems_per_word; ++lane) {
            emit_float_bytes(alpha_bin, alpha, dtype);
        }
        return true;
    }

    if (req.para_inputs.find("input_tensor") != req.para_inputs.end())
        write_tensor_data(input_bin, req.para_inputs.at("input_tensor"));
    if (req.para_inputs.find("other_tensor") != req.para_inputs.end())
        write_tensor_data(other_bin, req.para_inputs.at("other_tensor"));

    const auto& params = req.para_parameters;
    if (params.find("alpha") != params.end())
        write_tensor_data(alpha_bin, params.at("alpha"));

    return true;
}

std::vector<uint8_t> MeanDimOpInstructions::serialize() const {
    std::vector<uint8_t> result;
    auto iq_files = get_iq_files();
    for (const auto& file : iq_files)
        result.insert(result.end(), file.para_data.begin(), file.para_data.end());
    return result;
}

REGISTER_OP(MeanDimOp);

} // namespace op
} // namespace aiacc

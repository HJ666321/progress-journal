#ifndef FHJ_OP_AXI_LSU_PACKER_H
#define FHJ_OP_AXI_LSU_PACKER_H

/**
 * @file axi_lsu_packer.h
 * @brief v4.21 LDB/LDBAXI + STB/STBAXI packing (matches SMI_IQ lsu_emit LSB-first header).
 *
 * Hardware data path:
 *   HBM --LDBAXI--> DS --LDB--> UR --STB--> DS --STBAXI--> HBM
 * Paired instructions share inst_id. Avoid brst=0 (1-beat) for LDBAXI when possible.
 */

#include <cstdint>
#include <vector>

#include "v421_iq_adapter.h"
#include "iq/modules/ldb_iq.h"
#include "iq/modules/stb_iq.h"

namespace aiacc {
namespace op {
namespace axi_lsu {

namespace detail {

inline uint64_t serialize_header_bits_lsb(bool vld, bool jump, uint8_t embed, uint16_t loops,
                                          uint8_t cond, uint8_t dly, uint16_t inc,
                                          uint8_t embed_end, uint8_t inc_embed) {
    uint64_t bits = 0;
    uint32_t pos = 0;
    bits |= (static_cast<uint64_t>(inc_embed) & 0x3Fu) << pos; pos += 6;
    bits |= (static_cast<uint64_t>(inc) & 0x1FFFu) << pos; pos += 13;
    bits |= (static_cast<uint64_t>(dly) & 0x7u) << pos; pos += 3;
    bits |= (static_cast<uint64_t>(cond) & 0x7Fu) << pos; pos += 7;
    bits |= (static_cast<uint64_t>(loops) & 0x3FFu) << pos; pos += 10;
    bits |= (static_cast<uint64_t>(embed_end) & 0x3Fu) << pos; pos += 6;
    bits |= (static_cast<uint64_t>(embed) & 0x7u) << pos; pos += 3;
    bits |= (jump ? 1ull : 0ull) << pos; pos += 1;
    bits |= (vld ? 1ull : 0ull) << pos;
    return bits;
}

inline std::vector<uint8_t> serialize_code_lsb_first(const uint32_t* words, uint32_t code_bits) {
    const uint32_t num_bytes = (code_bits + 7u) / 8u;
    std::vector<uint8_t> bytes(num_bytes, 0);
    for (uint32_t i = 0; i < num_bytes; ++i) {
        const uint32_t wi = i / 4;
        const uint32_t bi = i % 4;
        bytes[num_bytes - 1u - i] = static_cast<uint8_t>((words[wi] >> (bi * 8u)) & 0xFFu);
    }
    return bytes;
}

inline std::vector<uint8_t> make_instruction(bool vld, uint16_t loops, uint8_t cond,
                                             uint8_t dly, uint16_t inc,
                                             const std::vector<uint8_t>& code_bytes,
                                             uint32_t code_bits) {
    constexpr uint32_t kHdrBits = 50;
    const uint64_t header_bits =
        serialize_header_bits_lsb(vld, false, 0, loops, cond, dly, inc, 0, 0);
    const uint32_t total_bits = kHdrBits + code_bits;
    const uint32_t total_bytes = (total_bits + 7u) / 8u;
    std::vector<uint8_t> result(total_bytes, 0);

    const uint32_t code_start = total_bytes - static_cast<uint32_t>(code_bytes.size());
    for (uint32_t i = 0; i < code_bytes.size(); ++i) {
        result[code_start + i] = code_bytes[i];
    }
    for (uint32_t bit = 0; bit < kHdrBits; ++bit) {
        if (((header_bits >> bit) & 1u) == 0) continue;
        const uint32_t global_bit = code_bits + bit;
        const uint32_t byte_from_lsb = global_bit / 8u;
        const uint32_t bit_in_byte = global_bit % 8u;
        const uint32_t idx = total_bytes - 1u - byte_from_lsb;
        result[idx] = static_cast<uint8_t>(result[idx] | (1u << bit_in_byte));
    }
    return result;
}

} // namespace detail

// cond indexes inst_rdy_in[]; use IQ_ID_LDB so store waits until UR is filled.
constexpr uint8_t kCondWaitLdb = 26;  // IQ_ID_LDB

struct AxiLoadXfer {
    uint64_t gr_base_addr{0};
    uint64_t gr_intlv_addr{0};
    uint8_t brst{0};              // beats-1; prefer >=1
    uint16_t ur_addr{0};          // bank*0x1000 + byte_offset
    uint8_t ur_wr_line_cnt{1};    // lines to write into UR
    uint8_t inst_id{0};
    uint8_t smc_id_en{0};
    uint8_t tid{0};               // LDBAXI DS route; 0=bypass to LDB
    uint16_t ldb_inc{0x0010};
    uint16_t ldbaxi_inc{0x0100};  // bulk AXI burst address step (16 lines)
};

struct AxiStoreXfer {
    uint64_t gr_base_addr{0};
    uint64_t gr_intlv_addr{0};
    uint8_t brst{0};
    uint16_t ur_addr{0};
    uint8_t ur_rd_line_cnt{1};
    uint8_t inst_id{0};
    uint8_t smc_id_en{0};
    uint8_t tid{2};               // STB tid=2 (b10) toward STBAXI
    uint8_t cond{kCondWaitLdb};   // wait for LDB rdy before reading UR
    uint8_t dly{7};
    uint16_t stb_inc{0x0010};
    uint16_t stbaxi_inc{0x0100};
};

inline std::vector<uint8_t> pack_ldbaxi(const AxiLoadXfer& p) {
    iq::LdbAxiCru cru{};
    cru.para_vld = true;
    cru.para_first_byte_strb = 0;
    cru.para_last_byte_strb = 0;
    cru.para_brst = p.brst;
    cru.para_gr_base_addr = p.gr_base_addr;
    cru.para_gr_intlv_addr = p.gr_intlv_addr ? p.gr_intlv_addr : p.gr_base_addr;
    cru.para_inst_id = p.inst_id & 0xFu;
    cru.para_smc_id_en = p.smc_id_en & 0x1Fu;
    cru.para_tid = static_cast<iq::LdbAxiTid>(p.tid & 0x3u);
    uint32_t words[4] = {0, 0, 0, 0};
    iq::LdbIq::pack_cru_ldbaxi(cru, words);
    return detail::make_instruction(true, 0, 0, 0, p.ldbaxi_inc,
                                    detail::serialize_code_lsb_first(words, 104), 104);
}

inline std::vector<uint8_t> pack_ldb(const AxiLoadXfer& p) {
    iq::LdbCru cru{};
    cru.para_vld = true;
    cru.para_ur_addr = p.ur_addr & 0x7FFFu;
    cru.para_ur_wr_line_cnt = p.ur_wr_line_cnt;
    cru.para_line_byte_cnt = 0x0F;
    cru.para_line_stride = 1;
    cru.para_inst_id = p.inst_id & 0xFu;
    cru.para_smc_id_en = p.smc_id_en & 0x1Fu;
    uint32_t words[2] = {0, 0};
    iq::LdbIq::pack_cru_ldb(cru, words);
    return detail::make_instruction(true, 0, 0, 0, p.ldb_inc,
                                    detail::serialize_code_lsb_first(words, 56), 56);
}

inline std::vector<uint8_t> pack_stb(const AxiStoreXfer& p) {
    iq::StbCru cru{};
    cru.para_vld = true;
    cru.para_ur_addr = p.ur_addr & 0x7FFFu;
    cru.para_ur_rd_line_cnt = p.ur_rd_line_cnt;
    cru.para_line_byte_cnt = 0x0F;
    cru.para_line_stride = 1;
    cru.para_inst_id = p.inst_id & 0xFu;
    cru.para_smc_id_en = p.smc_id_en & 0x1Fu;
    cru.para_tid = static_cast<iq::StbTid>(p.tid & 0x3u);
    uint32_t words[2] = {0, 0};
    iq::StbIq::pack_cru_stb(cru, words);
    return detail::make_instruction(true, 0, p.cond, p.dly, p.stb_inc,
                                    detail::serialize_code_lsb_first(words, 50), 50);
}

inline std::vector<uint8_t> pack_stbaxi(const AxiStoreXfer& p) {
    iq::StbAxiCru cru{};
    cru.para_vld = true;
    cru.para_first_byte_strb = 0;
    cru.para_last_byte_strb = 0;
    cru.para_brst = p.brst;
    cru.para_gr_base_addr = p.gr_base_addr;
    cru.para_gr_intlv_addr = p.gr_intlv_addr ? p.gr_intlv_addr : p.gr_base_addr;
    cru.para_inst_id = p.inst_id & 0xFu;
    cru.para_smc_id_en = p.smc_id_en & 0x1Fu;
    uint32_t words[4] = {0, 0, 0, 0};
    iq::StbIq::pack_cru_stbaxi(cru, words);
    return detail::make_instruction(true, 0, p.cond, p.dly, p.stbaxi_inc,
                                    detail::serialize_code_lsb_first(words, 102), 102);
}

} // namespace axi_lsu
} // namespace op
} // namespace aiacc

#endif // FHJ_OP_AXI_LSU_PACKER_H

#ifndef AIACC_OP_COMMON_LSU_V2_PACKER_H
#define AIACC_OP_COMMON_LSU_V2_PACKER_H

#include <algorithm>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace aiacc {
namespace op {
namespace lsu_v2 {

constexpr uint32_t kIqIdStbV2 = 86;
constexpr uint32_t kIqIdLdbV2 = 87;
constexpr uint32_t kStbBits = 71;
constexpr uint32_t kLdbBits = 128;
constexpr uint32_t kUrWordBytes = 16;

struct LsuV2Params {
    uint8_t smc_strb{0};        // Number of SMCs minus one.
    uint8_t byte_strb{0};       // 0 means all 16 bytes.
    uint32_t burst_words{1};    // Number of 128-bit beats/UR words.
    uint64_t gr_base_addr{0};   // 40-bit GR/HBM base address.
    uint8_t smc_id{0};
    uint8_t ur_id{0};
    uint8_t ur_addr{0};         // UR word address in v2 RTL.
};

inline void append_big_endian(std::vector<uint8_t>& out, unsigned __int128 value, int num_bytes) {
    for (int i = num_bytes - 1; i >= 0; --i) {
        out.push_back(static_cast<uint8_t>((value >> (i * 8)) & 0xFF));
    }
}

inline uint8_t encode_stb_burst(uint32_t burst_words) {
    switch (burst_words) {
        case 1: return 0;
        case 2: return 1;
        case 4: return 2;
        case 8: return 3;
        default:
            throw std::runtime_error("STB v2 burst must be one of 1/2/4/8 words");
    }
}

inline void validate_common(const LsuV2Params& p) {
    if (p.smc_strb > 63) throw std::runtime_error("LSU v2 smc_strb exceeds 6 bits");
    if (p.byte_strb > 15) throw std::runtime_error("LSU v2 byte_strb exceeds 4 bits");
    if (p.gr_base_addr >= (1ull << 40)) throw std::runtime_error("LSU v2 gr_base_addr exceeds 40 bits");
    if (p.smc_id > 31) throw std::runtime_error("LSU v2 smc_id exceeds 5 bits");
    if (p.ur_id > 7) throw std::runtime_error("LSU v2 ur_id exceeds 3 bits");
}

inline std::vector<uint8_t> pack_stb_v2(const LsuV2Params& p) {
    validate_common(p);
    const uint8_t brst_code = encode_stb_burst(p.burst_words);

    unsigned __int128 inst = 0;
    inst |= static_cast<unsigned __int128>(1) << 70;                         // vld
    inst |= static_cast<unsigned __int128>(p.smc_strb & 0x3F) << 64;
    inst |= static_cast<unsigned __int128>(p.byte_strb & 0xF) << 60;
    inst |= static_cast<unsigned __int128>(brst_code & 0x3) << 56;
    inst |= static_cast<unsigned __int128>(p.gr_base_addr & ((1ull << 40) - 1)) << 16;
    inst |= static_cast<unsigned __int128>(p.smc_id & 0x1F) << 11;
    inst |= static_cast<unsigned __int128>(p.ur_id & 0x7) << 8;
    inst |= static_cast<unsigned __int128>(p.ur_addr);

    std::vector<uint8_t> out;
    append_big_endian(out, inst, 9);
    return out;
}

inline std::vector<uint8_t> pack_ldb_v2(const LsuV2Params& p) {
    validate_common(p);
    if (p.burst_words == 0 || p.burst_words > 31) {
        throw std::runtime_error("LDB v2 burst_words must be in 1..31 for current brst_w=5 RTL");
    }

    unsigned __int128 inst = 0;
    inst |= static_cast<unsigned __int128>(1) << 127;                        // vld
    inst |= static_cast<unsigned __int128>(p.smc_strb & 0x3F) << 121;
    inst |= static_cast<unsigned __int128>(p.byte_strb & 0xF) << 117;
    inst |= static_cast<unsigned __int128>(p.burst_words & 0xFFFF) << 101;
    inst |= static_cast<unsigned __int128>(p.gr_base_addr & ((1ull << 40) - 1)) << 61;
    inst |= static_cast<unsigned __int128>(p.smc_id & 0x1F) << 56;
    inst |= static_cast<unsigned __int128>(p.ur_id & 0x7) << 53;
    inst |= static_cast<unsigned __int128>(p.ur_addr) << 45;

    std::vector<uint8_t> out;
    append_big_endian(out, inst, 16);
    return out;
}

inline void append_stb_v2_transfer(std::vector<uint8_t>& out, LsuV2Params p, uint32_t total_words) {
    uint32_t word_offset = 0;
    while (word_offset < total_words) {
        uint32_t remaining = total_words - word_offset;
        uint32_t chunk = (remaining >= 8) ? 8 : (remaining >= 4) ? 4 : (remaining >= 2) ? 2 : 1;
        if (static_cast<uint32_t>(p.ur_addr) + word_offset > 0xFF) {
            throw std::runtime_error("STB v2 ur_addr exceeds 8 bits after chunking");
        }
        p.burst_words = chunk;
        p.gr_base_addr += static_cast<uint64_t>(word_offset) * kUrWordBytes;
        p.ur_addr = static_cast<uint8_t>(p.ur_addr + word_offset);
        auto inst = pack_stb_v2(p);
        out.insert(out.end(), inst.begin(), inst.end());
        p.gr_base_addr -= static_cast<uint64_t>(word_offset) * kUrWordBytes;
        p.ur_addr = static_cast<uint8_t>(p.ur_addr - word_offset);
        word_offset += chunk;
    }
}

inline void append_ldb_v2_transfer(std::vector<uint8_t>& out, LsuV2Params p, uint32_t total_words) {
    uint32_t word_offset = 0;
    while (word_offset < total_words) {
        uint32_t chunk = std::min<uint32_t>(31, total_words - word_offset);
        if (static_cast<uint32_t>(p.ur_addr) + word_offset > 0xFF) {
            throw std::runtime_error("LDB v2 ur_addr exceeds 8 bits after chunking");
        }
        p.burst_words = chunk;
        p.gr_base_addr += static_cast<uint64_t>(word_offset) * kUrWordBytes;
        p.ur_addr = static_cast<uint8_t>(p.ur_addr + word_offset);
        auto inst = pack_ldb_v2(p);
        out.insert(out.end(), inst.begin(), inst.end());
        p.gr_base_addr -= static_cast<uint64_t>(word_offset) * kUrWordBytes;
        p.ur_addr = static_cast<uint8_t>(p.ur_addr - word_offset);
        word_offset += chunk;
    }
}

} // namespace lsu_v2
} // namespace op
} // namespace aiacc

#endif // AIACC_OP_COMMON_LSU_V2_PACKER_H

#ifndef MEAN_DIM_UR_CODE_EXTRACTOR_H
#define MEAN_DIM_UR_CODE_EXTRACTOR_H

/**
 * @file ur_code_extractor.h
 * @brief MeanDim 算子 UR 指令 CODE 字段提取
 *
 * 复用 add 算子的提取逻辑（位布局相同）。
 */

#include <cstdint>
#include <stdexcept>
#include "../../iq/modules/ur_iq.h"

namespace aiacc {
namespace op {

namespace mean_dim_detail {

inline uint32_t extract_ur_read_port_code(const iq::UrCru& cru,
                                          int port,
                                          uint8_t smc_id_en = 0) {
    if (port < 0 || port >= 4)
        throw std::out_of_range("extract_ur_read_port_code: port must be in [0, 3]");
    const uint32_t bank = cru.para_raddr[port].bank & 0x7u;
    const uint32_t addr = cru.para_raddr[port].addr_word & 0xFFu;
    const uint32_t re   = cru.para_re[port] ? 1u : 0u;
    return (static_cast<uint32_t>(smc_id_en & 0x1Fu) << 12) |
           (addr << 4) |
           (bank << 1) |
           re;
}

inline uint64_t extract_ur_write_port_code(const iq::UrCru& cru,
                                           int port,
                                           uint8_t smc_id_en = 0) {
    if (port < 0 || port >= 4)
        throw std::out_of_range("extract_ur_write_port_code: port must be in [0, 3]");
    const uint64_t bank = cru.para_waddr[port].bank & 0x7u;
    const uint64_t addr = cru.para_waddr[port].addr_word & 0xFFu;
    const uint64_t we   = cru.para_we[port] ? 1u : 0u;
    const uint64_t wbe  = cru.para_wbe[port] & 0xFFFFu;
    return (static_cast<uint64_t>(smc_id_en & 0x1Fu) << 28) |
           (wbe << 12) |
           (addr << 4) |
           (bank << 1) |
           we;
}

} // namespace mean_dim_detail

inline uint32_t md_extract_ur_read_port0_code(const iq::UrCru& cru) {
    return mean_dim_detail::extract_ur_read_port_code(cru, 0);
}
inline uint32_t md_extract_ur_read_port1_code(const iq::UrCru& cru) {
    return mean_dim_detail::extract_ur_read_port_code(cru, 1);
}
inline uint32_t md_extract_ur_write_port0_code(const iq::UrCru& cru) {
    return mean_dim_detail::extract_ur_write_port_code(cru, 0);
}

} // namespace op
} // namespace aiacc

#endif // MEAN_DIM_UR_CODE_EXTRACTOR_H

#ifndef MEAN_DIM_OP_BANK_CONFLICT_H
#define MEAN_DIM_OP_BANK_CONFLICT_H

/**
 * @file mean_dim_op_bank_conflict.h
 * @brief MeanDim 算子 Bank 冲突解决模块
 *
 * MeanDim 使用 3 个端口: r0(input), r1(alpha), w0(output)
 */

#include <cstdint>
#include <vector>
#include "mean_dim_op.h"

namespace aiacc {
namespace op {

uint8_t md_compute_slot_allocation(const MeanDimOpParams& params,
                                   std::vector<MeanDimOpInstructions::SlotAccess>& slot_accesses,
                                   uint8_t port_slots[3]);

} // namespace op
} // namespace aiacc

#endif // MEAN_DIM_OP_BANK_CONFLICT_H

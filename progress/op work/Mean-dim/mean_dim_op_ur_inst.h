#ifndef MEAN_DIM_OP_UR_INST_H
#define MEAN_DIM_OP_UR_INST_H

/**
 * @file mean_dim_op_ur_inst.h
 * @brief MeanDim 算子 UR 微指令生成模块
 *
 * 读端口:
 *   port 0: input (顺序读取所有输入 word)
 *   port 1: alpha = 1/reduce_size (广播标量)
 * 写端口:
 *   port 0: output (每 reduce_size 步写一次)
 */

#include <cstdint>
#include "../../iq/modules/ur_iq.h"
#include "mean_dim_op.h"

namespace aiacc {
namespace op {

void md_gen_ur_read_inst(const MeanDimOpParams& para_params,
                         uint32_t para_step,
                         iq::UrCru& para_cru);

void md_gen_ur_write_inst(const MeanDimOpParams& para_params,
                          uint32_t para_step,
                          iq::UrCru& para_cru);

} // namespace op
} // namespace aiacc

#endif // MEAN_DIM_OP_UR_INST_H

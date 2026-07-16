#ifndef MEAN_DIM_OP_COMPUTE_INST_H
#define MEAN_DIM_OP_COMPUTE_INST_H

/**
 * @file mean_dim_op_compute_inst.h
 * @brief MeanDim 算子计算单元微指令生成
 *
 * FPMUL: input * alpha (标量乘法)
 * FPADD: 累加模式 (update_st=true)
 */

#include "../../iq/modules/fpmul_iq.h"
#include "../../iq/modules/fpadd_iq.h"
#include "mean_dim_op.h"

namespace aiacc {
namespace op {

void md_gen_fpmul_inst(const MeanDimOpParams& para_params, iq::FpMulCru& para_cru);
void md_gen_fpadd_inst(const MeanDimOpParams& para_params, iq::FpAddCru& para_cru);

} // namespace op
} // namespace aiacc

#endif // MEAN_DIM_OP_COMPUTE_INST_H

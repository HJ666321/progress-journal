#ifndef MEAN_DIM_OP_RTOVR_INST_H
#define MEAN_DIM_OP_RTOVR_INST_H

/**
 * @file mean_dim_op_rtovr_inst.h
 * @brief MeanDim 算子 RtoVR 路由微指令生成
 *
 * 路由拓扑:
 *   Stage1: alpha(UR_RDATA_1) → FPMUL_S0, input(UR_RDATA_0) → FPMUL_S1
 *   Stage2: FPMUL_D → FPADD_S0
 *   Stage3: FPADD_D → UVR_WDATA_0
 */

#include "../../iq/modules/rtovr_iq.h"
#include "mean_dim_op_constants.h"

namespace aiacc {
namespace op {

void md_gen_rtovr_to_fpmul(iq::RtoVrCru& para_cru);
void md_gen_rtovr_fpmul_to_fpadd(iq::RtoVrCru& para_cru);
void md_gen_rtovr_fpadd_to_ur(iq::RtoVrCru& para_cru);

} // namespace op
} // namespace aiacc

#endif // MEAN_DIM_OP_RTOVR_INST_H

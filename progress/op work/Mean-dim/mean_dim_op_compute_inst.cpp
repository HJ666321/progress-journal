#include "mean_dim_op_compute_inst.h"
#include "mean_dim_op.h"

namespace aiacc {
namespace op {

void md_gen_fpmul_inst(const MeanDimOpParams& para_params, iq::FpMulCru& para_cru) {
    para_cru.para_inst_valid = true;
    bool is_32b = (para_params.para_dtype == MeanDimDataType::FP32);
    para_cru.para_src_precision_is_32b = is_32b;
    para_cru.para_dst_precision_is_32b = is_32b;
}

void md_gen_fpadd_inst(const MeanDimOpParams& para_params, iq::FpAddCru& para_cru) {
    para_cru.para_inst_valid = true;
    para_cru.para_mode_is_32b = (para_params.para_dtype == MeanDimDataType::FP32);
    // update_st = true: 使用累加器模式累积 reduce_size 个乘积
    para_cru.para_update_st = true;
}

} // namespace op
} // namespace aiacc

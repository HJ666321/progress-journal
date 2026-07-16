#include "mean_dim_op_rtovr_inst.h"
#include "mean_dim_op_constants.h"

namespace aiacc {
namespace op {

void md_gen_rtovr_to_fpmul(iq::RtoVrCru& para_cru) {
    para_cru.para_vld = true;
    for (int i = 0; i < 40; ++i) {
        para_cru.para_out[i].para_valid = false;
        para_cru.para_out[i].para_select = 0;
    }

    // alpha(UR_RDATA_1) → FPMUL_S0
    para_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S0].para_valid = true;
    para_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S0].para_select = MD_RTOVR_IN_UR_RDATA_1;

    // input(UR_RDATA_0) → FPMUL_S1
    para_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S1].para_valid = true;
    para_cru.para_out[MD_RTOVR_OUT_DVR_FPMUL_S1].para_select = MD_RTOVR_IN_UR_RDATA_0;
}

void md_gen_rtovr_fpmul_to_fpadd(iq::RtoVrCru& para_cru) {
    para_cru.para_vld = true;
    for (int i = 0; i < 40; ++i) {
        para_cru.para_out[i].para_valid = false;
        para_cru.para_out[i].para_select = 0;
    }

    // FPMUL_D → FPADD_S0
    para_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S0].para_valid = true;
    para_cru.para_out[MD_RTOVR_OUT_DVR_FPADD_S0].para_select = MD_RTOVR_IN_DR_FPMUL_D;
}

void md_gen_rtovr_fpadd_to_ur(iq::RtoVrCru& para_cru) {
    para_cru.para_vld = true;
    for (int i = 0; i < 40; ++i) {
        para_cru.para_out[i].para_valid = false;
        para_cru.para_out[i].para_select = 0;
    }

    // FPADD_D → UVR_WDATA_0
    para_cru.para_out[MD_RTOVR_OUT_UVR_WDATA_0].para_valid = true;
    para_cru.para_out[MD_RTOVR_OUT_UVR_WDATA_0].para_select = MD_RTOVR_IN_DR_FPADD_D;
}

} // namespace op
} // namespace aiacc

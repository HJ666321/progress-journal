#include "mean_dim_op_ur_inst.h"
#include "mean_dim_op.h"

namespace aiacc {
namespace op {

void md_gen_ur_read_inst(const MeanDimOpParams& para_params,
                         uint32_t para_step,
                         iq::UrCru& para_cru) {
    para_cru.para_vld = true;

    // 读端口 0: input (顺序读取)
    para_cru.para_raddr[0].bank = para_params.para_input_bank;
    para_cru.para_raddr[0].addr_word = para_params.para_input_addr + para_step;
    para_cru.para_re[0] = true;

    // 读端口 1: alpha (广播，始终同一地址)
    para_cru.para_raddr[1].bank = para_params.para_alpha_bank;
    para_cru.para_raddr[1].addr_word = para_params.para_alpha_addr;
    para_cru.para_re[1] = true;

    para_cru.para_re[2] = false;
    para_cru.para_re[3] = false;

    para_cru.para_we[0] = false;
    para_cru.para_we[1] = false;
    para_cru.para_we[2] = false;
    para_cru.para_we[3] = false;
}

void md_gen_ur_write_inst(const MeanDimOpParams& para_params,
                          uint32_t para_step,
                          iq::UrCru& para_cru) {
    para_cru.para_vld = true;

    para_cru.para_re[0] = false;
    para_cru.para_re[1] = false;
    para_cru.para_re[2] = false;
    para_cru.para_re[3] = false;

    para_cru.para_waddr[0].bank = para_params.para_output_bank;
    para_cru.para_waddr[0].addr_word = para_params.para_output_addr + para_step;
    para_cru.para_we[0] = true;
    para_cru.para_wbe[0] = 0xFFFF;

    para_cru.para_we[1] = false;
    para_cru.para_we[2] = false;
    para_cru.para_we[3] = false;
}

} // namespace op
} // namespace aiacc

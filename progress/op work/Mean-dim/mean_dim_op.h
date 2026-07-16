#ifndef MEAN_DIM_OP_H
#define MEAN_DIM_OP_H

/**
 * @file mean_dim_op.h
 * @brief MeanDim 算子：out[i] = mean(input[i*R .. i*R+R-1])
 *
 * 沿最后一维连续 reduce 取均值。产品级硬件流水线：
 *   1. UR 顺序读 raw input
 *   2. RtoVR: input → FPADD_S0, FPADD_D feedback → FPADD_S1
 *   3. FPADD 逐 word 归约得到 sum
 *   4. RtoVR: sum → FPMUL_S1, alpha (=1/reduce_size) → FPMUL_S0
 *   5. RtoVR: FPMUL_D → UVR_WDATA_0
 *   6. UR 写 output
 *
 * 支持 8 SMC: 每个 SMC 处理完整的独立 mean_dim 任务。
 */

#include <cstdint>
#include <vector>
#include <string>
#include <random>

#include "../../hal/aiacc_smi_iq.h"
#include "../../iq/modules/ur_iq.h"
#include "../../iq/modules/rtovr_iq.h"
#include "../../iq/modules/fpmul_iq.h"
#include "../../iq/modules/fpadd_iq.h"
#include "../../iq/modules/fp32addtree8to1_iq.h"
#include "../common/op_instructions_base.h"
#include "../common/op_base.h"
#include "../common/op_registry.h"
#include "../../app/app_json_parser.h"

namespace aiacc {
namespace op {

enum class MeanDimDataType : uint8_t {
    FP32 = 0,
    FP16 = 1
};

struct MeanDimOpParams {
    uint32_t para_n{1};
    uint32_t para_c{1};
    uint32_t para_h{1};
    uint32_t para_w{4};

    uint32_t para_reduce_size{4};
    uint32_t para_reduce_elems{0};
    int32_t para_dim{-1};
    bool para_keepdim{true};
    bool para_llama_dim_reduce{false};

    MeanDimDataType para_dtype{MeanDimDataType::FP32};

    // UR 存储布局
    uint8_t para_input_bank{0};
    uint8_t para_input_addr{0};

    uint8_t para_alpha_bank{2};
    uint8_t para_alpha_addr{0};

    uint8_t para_output_bank{3};
    uint8_t para_output_addr{0};

    bool para_enable_lsu{false};
    bool para_enable_lsu_v2{false};
    bool para_enable_cascade{false};
    bool para_hardware_reduce{true};
    bool para_pre_sum_compat{false};
    bool para_llama_chunk_reduce{false}; // native 4096: FPADD tiles + AddTree8to1 lane sum
    uint8_t para_smc_id{0};
    uint8_t para_smc_count{8};
    uint8_t para_lsu_stage_bank{4};
    uint16_t para_lsu_stage_addr_bytes{0};
    uint64_t para_lsu_v2_input_gr_base{0};
    uint64_t para_lsu_v2_output_gr_base{0x1000};
    uint8_t para_lsu_v2_input_ur_id{0};
    uint8_t para_lsu_v2_output_ur_id{3};
    uint8_t para_lsu_v2_byte_strb{0};

    uint32_t get_elems_per_word() const {
        return (para_dtype == MeanDimDataType::FP32) ? 4 : 8;
    }
};

struct MeanDimOpInstructions : public OpInstructionsBase {
    std::vector<iq::UrCru> para_ur_read_crus;
    std::vector<iq::UrCru> para_ur_write_crus;

    std::vector<uint32_t> para_rtovr_stage1; // input,alpha → FPMUL
    std::vector<uint32_t> para_rtovr_stage2; // FPMUL_D → FPADD
    std::vector<uint32_t> para_rtovr_stage3; // FPADD_D → UVR_WDATA
    std::vector<uint32_t> para_rtovr_stage_shift; // FPADD_D → SHIFTDN

    uint16_t para_fpmul_inst{0};
    uint16_t para_fpadd_inst{0};
    uint16_t para_addtree8_inst{0};
    uint16_t para_shiftdn_inst{0};

    MeanDimDataType para_dtype{MeanDimDataType::FP32};

    uint32_t para_total_steps{0};      // 总输入 word 数
    uint32_t para_total_elements{0};
    uint32_t para_output_words{0};     // 输出 word 数
    uint32_t para_reduce_size{4};      // 每组 reduce 的 word 数
    bool para_hardware_reduce{true};
    bool para_pre_sum_compat{false};
    bool para_llama_chunk_reduce{false};

    uint16_t para_embed_loops{0};      // 外层循环 (输出 word 数)
    uint16_t para_inner_loops{0};      // 内层循环 (reduce_size)

    bool para_enable_lsu{false};
    bool para_enable_lsu_v2{false};
    bool para_enable_cascade{false};
    uint8_t para_smc_id{0};
    uint8_t para_smc_count{8};
    uint8_t para_lsu_source_bank{1};
    uint16_t para_lsu_source_addr_bytes{0};
    uint8_t para_lsu_stage_bank{4};
    uint16_t para_lsu_stage_addr_bytes{0};
    uint64_t para_lsu_v2_input_gr_base{0};
    uint64_t para_lsu_v2_output_gr_base{0x1000};
    uint8_t para_lsu_v2_input_ur_id{0};
    uint8_t para_lsu_v2_output_ur_id{3};
    uint8_t para_lsu_v2_byte_strb{0};

    uint8_t para_num_slots{1};
    struct SlotAccess {
        uint8_t input_slot{0xFF};
        uint8_t alpha_slot{0xFF};
        uint8_t output_slot{0xFF};
        bool has_compute{false};
    };
    std::vector<SlotAccess> para_slot_accesses;
    uint8_t para_port_slots[3] = {0, 0, 0}; // [r0=input, r1=alpha, w0=output]

    std::vector<IqInstructionFile> get_iq_files() const override;
    std::string get_operator_name() const override { return "MeanDim"; }
    uint32_t get_total_steps() const override { return para_total_steps; }
    uint32_t get_total_elements() const override { return para_total_elements; }
    std::vector<uint8_t> serialize() const override;
};

class MeanDimOp : public OpBase {
public:
    MeanDimOp() = default;
    ~MeanDimOp() = default;

    std::string get_name() const override;
    OpInstructionsBase* compile(const app::AppOperatorRequest& req) override;
    bool calculate_golden(const app::AppOperatorRequest& req,
                         std::vector<uint8_t>& golden_bin) override;
    bool generate_data(const app::AppOperatorRequest& req,
                      std::vector<uint8_t>& input_bin,
                      std::vector<uint8_t>& other_bin,
                      std::vector<uint8_t>& alpha_bin) override;
    void fill_random_request(app::AppOperatorRequest& req,
                             std::mt19937& rng,
                             std::uniform_real_distribution<float>& data_dist,
                             const std::string& dtype_str) override;

    MeanDimOpInstructions compile(const MeanDimOpParams& para_params);
};

} // namespace op
} // namespace aiacc

#endif // MEAN_DIM_OP_H

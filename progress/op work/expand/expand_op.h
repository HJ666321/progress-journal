#ifndef EXPAND_OP_H
#define EXPAND_OP_H

/**
 * @file expand_op.h
 * @brief Expand 算子：基于指令集架构中的 STB/LDB 数据搬运模块实现。
 *
 * expand 属于 Shape / Broadcast 类算子。当前实现把广播寻址在 TVGen 阶段完成，
 * 得到连续的 expanded tensor 后，硬件侧只做数据搬运：
 *
 *   UR bank0 (expanded input) --STB--> LSU buffer --LDB--> UR bank3 (output)
 *
 * STB/LDB 的 CRU 编码参考 v4.19 LSU 测例字段：
 * - STB: 50-bit header + 50-bit code = 100 bits
 * - LDB: 50-bit header + 56-bit code = 106 bits
 *
 * 这版不再复用 FPMUL/FPADD/add 数据通路，属于纯 LDB/STB 搬运实现。
 */

#include <cstdint>
#include <random>
#include <string>
#include <vector>

#include "../../app/app_json_parser.h"
#include "../common/op_base.h"
#include "../common/op_instructions_base.h"
#include "../common/op_registry.h"

namespace aiacc {
namespace op {

enum class ExpandDataType : uint8_t {
    FP32 = 0,
    FP16 = 1
};

struct ExpandOpParams {
    uint32_t para_n{1};
    uint32_t para_c{1};
    uint32_t para_h{1};
    uint32_t para_w{4};

    uint32_t para_input_n{1};
    uint32_t para_input_c{1};
    uint32_t para_input_h{1};
    uint32_t para_input_w{4};

    ExpandDataType para_dtype{ExpandDataType::FP32};
    bool para_native_broadcast{false};
    bool para_lane_broadcast{false};
    bool para_strict_lane_replicate{false};
    bool para_enable_lsu_v2{false};

    uint8_t para_input_bank{0};
    uint16_t para_input_addr_bytes{0};
    uint8_t para_output_bank{3};
    uint16_t para_output_addr_bytes{0};
    uint64_t para_lsu_v2_input_gr_base{0};
    uint64_t para_lsu_v2_output_gr_base{0x1000};
    uint8_t para_lsu_v2_input_ur_id{0};
    uint8_t para_lsu_v2_output_ur_id{3};
    uint8_t para_lsu_v2_smc_id{0};
    uint8_t para_lsu_v2_smc_count{1};
    uint8_t para_lsu_v2_byte_strb{0};

    uint32_t get_elems_per_word() const {
        return (para_dtype == ExpandDataType::FP32) ? 4 : 8;
    }
};

struct ExpandOpInstructions : public OpInstructionsBase {
    ExpandDataType para_dtype{ExpandDataType::FP32};
    uint32_t para_total_steps{0};
    uint32_t para_total_elements{0};
    uint32_t para_input_words{0};
    bool para_native_broadcast{false};
    bool para_lane_broadcast{false};
    bool para_strict_lane_replicate{false};
    bool para_enable_lsu_v2{false};
    uint8_t para_input_bank{0};
    uint16_t para_input_addr_bytes{0};
    uint8_t para_output_bank{3};
    uint16_t para_output_addr_bytes{0};
    uint64_t para_lsu_v2_input_gr_base{0};
    uint64_t para_lsu_v2_output_gr_base{0x1000};
    uint8_t para_lsu_v2_input_ur_id{0};
    uint8_t para_lsu_v2_output_ur_id{3};
    uint8_t para_lsu_v2_smc_id{0};
    uint8_t para_lsu_v2_smc_count{1};
    uint8_t para_lsu_v2_byte_strb{0};
    std::vector<uint16_t> para_native_src_words;

    std::vector<IqInstructionFile> get_iq_files() const override;
    std::string get_operator_name() const override { return "Expand"; }
    uint32_t get_total_steps() const override { return para_total_steps; }
    uint32_t get_total_elements() const override { return para_total_elements; }
    std::vector<uint8_t> serialize() const override;
};

class ExpandOp : public OpBase {
public:
    ExpandOp() = default;
    ~ExpandOp() = default;

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

    ExpandOpInstructions compile(const ExpandOpParams& para_params);
};

} // namespace op
} // namespace aiacc

#endif // EXPAND_OP_H

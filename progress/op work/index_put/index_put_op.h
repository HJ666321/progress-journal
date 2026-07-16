#ifndef INDEX_PUT_OP_H
#define INDEX_PUT_OP_H

/**
 * @file index_put_op.h
 * @brief IndexPut 算子：flat word index 的索引赋值。
 *
 * 第一版支持 flat word index，indices 中每个元素表示 128-bit UR word 地址。
 * TVGen 根据 accumulate=false/true 预处理重复 index 和累加语义，硬件侧只做
 * 非连续写回：
 *
 *   UR bank1 (canonical values) --STB--> LSU buffer --LDB--> UR bank3[index]
 *
 * UR bank3 初始内容由 TVGen 写成 input/base tensor，因此未更新位置保持原值。
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

enum class IndexPutDataType : uint8_t {
    FP32 = 0,
    FP16 = 1
};

struct IndexPutOpParams {
    uint32_t para_n{1};
    uint32_t para_c{1};
    uint32_t para_h{1};
    uint32_t para_w{4};
    uint32_t para_num_updates{0};
    bool para_accumulate{false};

    IndexPutDataType para_dtype{IndexPutDataType::FP32};

    uint8_t para_value_bank{1};
    uint16_t para_value_addr_bytes{0};
    uint8_t para_output_bank{3};
    uint16_t para_output_addr_bytes{0};
    std::vector<uint32_t> para_indices;
    std::vector<int64_t> para_slot_mapping;

    bool para_cache_flash_mode{false};
    uint32_t para_token_count{0};
    uint32_t para_block_size{16};
    uint32_t para_num_heads{32};
    uint32_t para_head_size{128};
    uint32_t para_cache_words{0};
    uint32_t para_cache_kind{0}; // 0=K, 1=V, 2=K+V

    bool para_enable_lsu_v2{false};
    uint64_t para_lsu_v2_input_gr_base{0};
    uint64_t para_lsu_v2_values_gr_base{0x1000};
    uint64_t para_lsu_v2_output_gr_base{0};
    uint8_t para_lsu_v2_smc_id{0};
    uint8_t para_lsu_v2_smc_count{1};
    uint8_t para_lsu_v2_byte_strb{0};

    uint32_t get_elems_per_word() const {
        return (para_dtype == IndexPutDataType::FP32) ? 4 : 8;
    }
};

struct IndexPutOpInstructions : public OpInstructionsBase {
    IndexPutDataType para_dtype{IndexPutDataType::FP32};
    uint32_t para_total_steps{0};
    uint32_t para_total_elements{0};
    uint32_t para_num_updates{0};
    bool para_accumulate{false};
    uint8_t para_value_bank{1};
    uint16_t para_value_addr_bytes{0};
    uint8_t para_output_bank{3};
    uint16_t para_output_addr_bytes{0};
    std::vector<uint32_t> para_indices;
    std::vector<int64_t> para_slot_mapping;

    bool para_cache_flash_mode{false};
    uint32_t para_token_count{0};
    uint32_t para_block_size{16};
    uint32_t para_num_heads{32};
    uint32_t para_head_size{128};
    uint32_t para_cache_words{0};
    uint32_t para_cache_kind{0};

    bool para_enable_lsu_v2{false};
    uint64_t para_lsu_v2_input_gr_base{0};
    uint64_t para_lsu_v2_values_gr_base{0x1000};
    uint64_t para_lsu_v2_output_gr_base{0};
    uint8_t para_lsu_v2_smc_id{0};
    uint8_t para_lsu_v2_smc_count{1};
    uint8_t para_lsu_v2_byte_strb{0};

    std::vector<IqInstructionFile> get_iq_files() const override;
    std::string get_operator_name() const override { return "IndexPut"; }
    uint32_t get_total_steps() const override { return para_total_steps; }
    uint32_t get_total_elements() const override { return para_total_elements; }
    std::vector<uint8_t> serialize() const override;
};

class IndexPutOp : public OpBase {
public:
    IndexPutOp() = default;
    ~IndexPutOp() = default;

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

    IndexPutOpInstructions compile(const IndexPutOpParams& para_params);
};

} // namespace op
} // namespace aiacc

#endif // INDEX_PUT_OP_H

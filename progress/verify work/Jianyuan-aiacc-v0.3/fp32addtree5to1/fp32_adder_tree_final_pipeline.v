//=========================================================================
// Project   : FP32 Adder Tree (Pipelined Version)
// File      : fp32_adder_tree_final_pipeline.v
// Module    : fp32_adder_tree_final_pipeline
// Author    : sunny
// Email     : 
// Created   : 2025-01-XX
// Modified  : 2025-01-XX
// Version   : 3.0 (Pipelined for 100MHz)
//=========================================================================
// Description:
// - Top-level 8-input FP32 adder tree with 5-stage pipeline
// - Pipeline stages:
//   Stage 0: Data reorganization + Unpack
//   Stage 1: Special value detection + Mantissa alignment
//   Stage 2: Sign separation + Wallace tree accumulation
//   Stage 3: Sign combination + Normalization/Rounding
//   Stage 4: Packing + Output
// - Verilog-2001 compliant
// - Designed for 100MHz operation
//
// IO Ports:
// - Inputs : clk, rst_n, cru_fp32addtree5to1
//            dvr_fp32addtree5to1_s0, dvr_fp32addtree5to1_s1, dvr_fp32addtree5to1_s2, dvr_fp32addtree5to1_s3,
//            dvr_fp32addtree5to1_s4, dvr_fp32addtree5to1_s5, dvr_fp32addtree5to1_s6, dvr_fp32addtree5to1_s7
// - Outputs: dr_fp32addtree5to1_d0, dr_fp32addtree5to1_d1
//
// Dependencies:
// - `../define/fp32_defines.vh`
// - fp32_unpacker, fp32_aligner, wallace_tree_5_inputs, fp32_normalizer_rounder, fp32_packer
//
//=========================================================================
`include "fp32_defines.vh"

module fp32_adder_tree_final_pipeline #(
    parameter SMC_ID = 0,
    parameter IEEE_754 = 1
)(
    input  wire        clk,
    input  wire        rst_n,               
    input  wire        cru_fp32addtree5to1,
    
    // SMC Identification
    input  wire [4:0]  i_smc_id,
    
    // IEEE-754 Rounding Mode Control (NEW)
    input  wire [2:0]  i_rounding_mode,  // 000=RNE, 001=RTZ, 010=RDN, 011=RUP, 100=RMM
    
    // 8组128-bit源寄存器
    input  wire [127:0] dvr_fp32addtree5to1_s0,
    input  wire [127:0] dvr_fp32addtree5to1_s1,
    input  wire [127:0] dvr_fp32addtree5to1_s2,
    input  wire [127:0] dvr_fp32addtree5to1_s3,
    input  wire [127:0] dvr_fp32addtree5to1_s4,
    input  wire [127:0] dvr_fp32addtree5to1_s5,
    input  wire [127:0] dvr_fp32addtree5to1_s6,
    input  wire [127:0] dvr_fp32addtree5to1_s7,

    // 2组128-bit目的寄存器
    output wire [127:0] dr_fp32addtree5to1_d0,
    output wire [127:0] dr_fp32addtree5to1_d1,
    
    // IEEE-754 Exception Flags Output (NEW) - per adder
    // [4:0] = {Inexact, Underflow, Overflow, DivByZero, Invalid}
    output wire [7:0] [4:0] o_exception_flags
);

    // --------------------------------------------------------------------
    // 参数与局部常量
    // --------------------------------------------------------------------
    localparam NUM      = 8;
    localparam NUM_INPUTS = 5;

    localparam SUM_IN_WIDTH  = `ALIGNED_MANT_WIDTH + 1;          
    localparam WALLACE_WIDTH = `ALIGNED_MANT_WIDTH + $clog2(NUM_INPUTS) - 1;
    localparam SUM_OUT_WIDTH = WALLACE_WIDTH + 1;
    genvar i, j, k;

    // ====================================================================
    // 流水线控制信号
    // ====================================================================
    reg [4:0] valid_pipe;
    reg [2:0] rounding_mode_pipe [0:4];  // Pipeline rounding mode

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 5'd0;
            rounding_mode_pipe[0] <= `RM_RNE;
            rounding_mode_pipe[1] <= `RM_RNE;
            rounding_mode_pipe[2] <= `RM_RNE;
            rounding_mode_pipe[3] <= `RM_RNE;
            rounding_mode_pipe[4] <= `RM_RNE;
        end else begin
            valid_pipe <= {valid_pipe[3:0], cru_fp32addtree5to1};
            rounding_mode_pipe[0] <= i_rounding_mode;
            rounding_mode_pipe[1] <= rounding_mode_pipe[0];
            rounding_mode_pipe[2] <= rounding_mode_pipe[1];
            rounding_mode_pipe[3] <= rounding_mode_pipe[2];
            rounding_mode_pipe[4] <= rounding_mode_pipe[3];
        end
    end

    // ====================================================================
    // Stage 0: 数据重组 + 拆包
    // ====================================================================
    wire [`FP32_WIDTH-1:0] fp_new [0:NUM-1][0:3];
    wire [`FP32_WIDTH-1:0] old_fp32 [0:NUM-1];
    wire [`FP32_WIDTH-1:0] full_fp_in [0:NUM-1][0:NUM_INPUTS-1];
    wire [`FP32_WIDTH-1:0] add_result [0:NUM-1];
    wire [4:0] exception_flags [0:NUM-1];  // Exception flags per adder
    
    reg [`FP32_WIDTH-1:0] add_result_stage4 [0:NUM-1];

    generate
        for (i = 0; i < NUM; i = i + 1) begin : gen_stage0
            // 新输入解包
            for (k = 0; k < 4; k = k + 1) begin : gen_unpack_bits
                assign fp_new[i][k] = {
                    dvr_fp32addtree5to1_s7[(4*i + k) * 4 +: 4], 
                    dvr_fp32addtree5to1_s6[(4*i + k) * 4 +: 4],
                    dvr_fp32addtree5to1_s5[(4*i + k) * 4 +: 4], 
                    dvr_fp32addtree5to1_s4[(4*i + k) * 4 +: 4],
                    dvr_fp32addtree5to1_s3[(4*i + k) * 4 +: 4], 
                    dvr_fp32addtree5to1_s2[(4*i + k) * 4 +: 4],
                    dvr_fp32addtree5to1_s1[(4*i + k) * 4 +: 4], 
                    dvr_fp32addtree5to1_s0[(4*i + k) * 4 +: 4]
                };
            end

            assign old_fp32[i] = add_result_stage4[i];

            for (j = 0; j < 4; j = j + 1) begin : gen_new_inputs
                assign full_fp_in[i][j] = fp_new[i][j];
            end
            assign full_fp_in[i][4] = old_fp32[i];
            
            // 拆包
            wire [`FP32_EXP_WIDTH-1:0] temp_exponent [0:NUM_INPUTS-1];
            wire [`FP32_MANT_WIDTH-1:0] temp_mantissa [0:NUM_INPUTS-1];
            wire [NUM_INPUTS-1:0] signs, is_zeros, is_infs, is_nans;
            wire [NUM_INPUTS*`FP32_EXP_WIDTH-1:0] exponents_flat;
            wire [NUM_INPUTS*`FP32_MANT_WIDTH-1:0] mantissas_flat;

            for (j = 0; j < NUM_INPUTS; j = j + 1) begin : unpack_gen
                fp32_unpacker # (.IEEE_754(IEEE_754)) unpacker_inst (
                    .fp_in(full_fp_in[i][j]), 
                    .sign(signs[j]), 
                    .exponent(temp_exponent[j]),
                    .mantissa(temp_mantissa[j]), 
                    .is_zero(is_zeros[j]),
                    .is_inf(is_infs[j]), 
                    .is_nan(is_nans[j])
                );
                assign exponents_flat[j*`FP32_EXP_WIDTH +: `FP32_EXP_WIDTH] = temp_exponent[j];
                assign mantissas_flat[j*`FP32_MANT_WIDTH +: `FP32_MANT_WIDTH] = temp_mantissa[j];
            end

            // Stage 0 组合逻辑
            wire [NUM_INPUTS*`FP32_EXP_WIDTH-1:0] exponents_flat_s0;
            wire [NUM_INPUTS*`FP32_MANT_WIDTH-1:0] mantissas_flat_s0;
            wire [NUM_INPUTS-1:0] signs_s0, is_zeros_s0, is_infs_s0, is_nans_s0;

            assign exponents_flat_s0 = exponents_flat;
            assign mantissas_flat_s0 = mantissas_flat;
            assign signs_s0 = signs;
            assign is_zeros_s0 = is_zeros;
            assign is_infs_s0 = is_infs;
            assign is_nans_s0 = is_nans;

            // ====================================================================
            // Stage 1: 特殊值检测 + 尾数对齐
            // ====================================================================
            // 特殊值处理与异常检测
            wire any_nan_in = |is_nans_s0;
            wire [NUM_INPUTS-1:0] is_pos_inf = is_infs_s0 & ~signs_s0;
            wire [NUM_INPUTS-1:0] is_neg_inf = is_infs_s0 & signs_s0;
            wire any_pos_inf = |is_pos_inf;
            wire any_neg_inf = |is_neg_inf;
            
            // Invalid operation: NaN input or (+Inf) + (-Inf)
            wire invalid_operation = any_nan_in || (any_pos_inf && any_neg_inf);
            
            wire result_is_nan_condition = invalid_operation;
            wire result_is_inf_condition = !result_is_nan_condition && (any_pos_inf ^ any_neg_inf);
            wire result_inf_sign = any_neg_inf;
            wire any_valid_positive = |(~is_nans_s0 & ~is_infs_s0 & ~signs_s0);
            wire no_positive_contribution_present = ~any_valid_positive;

            // 尾数对齐
            wire [`FP32_EXP_WIDTH-1:0] max_exponent;
            wire [NUM_INPUTS*`ALIGNED_MANT_WIDTH-1:0] aligned_mantissas_flat;
            wire [NUM_INPUTS-1:0] effective_signs;
            fp32_aligner #(.NUM_INPUTS(NUM_INPUTS)) aligner_inst (
                .signs(signs_s0), 
                .exponents_flat(exponents_flat_s0), 
                .mantissas_flat(mantissas_flat_s0),
                .is_zeros(is_zeros_s0), 
                .is_infs(is_infs_s0), 
                .is_nans(is_nans_s0),
                .max_exponent(max_exponent), 
                .aligned_mantissas_flat(aligned_mantissas_flat),
                .effective_signs(effective_signs)
            );

            // Stage 1 寄存器
            reg [`FP32_EXP_WIDTH-1:0] max_exponent_s1;
            reg [NUM_INPUTS*`ALIGNED_MANT_WIDTH-1:0] aligned_mantissas_flat_s1;
            reg [NUM_INPUTS-1:0] effective_signs_s1;
            reg result_is_nan_condition_s1, result_is_inf_condition_s1;
            reg result_inf_sign_s1, no_positive_contribution_present_s1;
            reg invalid_operation_s1;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    max_exponent_s1 <= {`FP32_EXP_WIDTH{1'b0}};
                    aligned_mantissas_flat_s1 <= {(NUM_INPUTS*`ALIGNED_MANT_WIDTH){1'b0}};
                    effective_signs_s1 <= {NUM_INPUTS{1'b0}};
                    result_is_nan_condition_s1 <= 1'b0;
                    result_is_inf_condition_s1 <= 1'b0;
                    result_inf_sign_s1 <= 1'b0;
                    no_positive_contribution_present_s1 <= 1'b0;
                    invalid_operation_s1 <= 1'b0;
                end else if (cru_fp32addtree5to1) begin
                    max_exponent_s1 <= max_exponent;
                    aligned_mantissas_flat_s1 <= aligned_mantissas_flat;
                    effective_signs_s1 <= effective_signs;
                    result_is_nan_condition_s1 <= result_is_nan_condition;
                    result_is_inf_condition_s1 <= result_is_inf_condition;
                    result_inf_sign_s1 <= result_inf_sign;
                    no_positive_contribution_present_s1 <= no_positive_contribution_present;
                    invalid_operation_s1 <= invalid_operation;
                end
            end

            // ====================================================================
            // Stage 2: 正负分离 + 华莱士树累加
            // ====================================================================
            wire [NUM_INPUTS*`ALIGNED_MANT_WIDTH-1:0] pos_mants_flat;
            wire [NUM_INPUTS*`ALIGNED_MANT_WIDTH-1:0] neg_mants_flat;
            for (j = 0; j < NUM_INPUTS; j = j + 1) begin : pos_neg_group
                wire [`ALIGNED_MANT_WIDTH-1:0] this_aligned_mantissa;
                assign this_aligned_mantissa = aligned_mantissas_flat_s1[j*`ALIGNED_MANT_WIDTH +: `ALIGNED_MANT_WIDTH];
                assign pos_mants_flat[j*`ALIGNED_MANT_WIDTH +: `ALIGNED_MANT_WIDTH] = 
                    (effective_signs_s1[j] == 1'b0) ? this_aligned_mantissa : {`ALIGNED_MANT_WIDTH{1'b0}};
                assign neg_mants_flat[j*`ALIGNED_MANT_WIDTH +: `ALIGNED_MANT_WIDTH] = 
                    (effective_signs_s1[j] == 1'b1) ? this_aligned_mantissa : {`ALIGNED_MANT_WIDTH{1'b0}};
            end

            // Wallace Tree累加
            wire [WALLACE_WIDTH:0] pos_sum;
            wire [WALLACE_WIDTH:0] neg_sum;
            wallace_tree_5_inputs #(
                .NUM_INPUTS(NUM_INPUTS),
                .WIDTH(WALLACE_WIDTH),
                .IN_WIDTH(`ALIGNED_MANT_WIDTH)
            ) wallace_pos (
                .data_in(pos_mants_flat),
                .final_result(pos_sum)
            );
            wallace_tree_5_inputs #(
                .NUM_INPUTS(NUM_INPUTS),
                .WIDTH(WALLACE_WIDTH),
                .IN_WIDTH(`ALIGNED_MANT_WIDTH)
            ) wallace_neg (
                .data_in(neg_mants_flat),
                .final_result(neg_sum)
            );

            // Stage 2 寄存器
            reg [WALLACE_WIDTH:0] pos_sum_s2, neg_sum_s2;
            reg [`FP32_EXP_WIDTH-1:0] max_exponent_s2;
            reg result_is_nan_condition_s2, result_is_inf_condition_s2;
            reg result_inf_sign_s2, no_positive_contribution_present_s2;
            reg invalid_operation_s2;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    pos_sum_s2 <= {(WALLACE_WIDTH+1){1'b0}};
                    neg_sum_s2 <= {(WALLACE_WIDTH+1){1'b0}};
                    max_exponent_s2 <= {`FP32_EXP_WIDTH{1'b0}};
                    result_is_nan_condition_s2 <= 1'b0;
                    result_is_inf_condition_s2 <= 1'b0;
                    result_inf_sign_s2 <= 1'b0;
                    no_positive_contribution_present_s2 <= 1'b0;
                    invalid_operation_s2 <= 1'b0;
                end else if (valid_pipe[0]) begin
                    pos_sum_s2 <= pos_sum;
                    neg_sum_s2 <= neg_sum;
                    max_exponent_s2 <= max_exponent_s1;
                    result_is_nan_condition_s2 <= result_is_nan_condition_s1;
                    result_is_inf_condition_s2 <= result_is_inf_condition_s1;
                    result_inf_sign_s2 <= result_inf_sign_s1;
                    no_positive_contribution_present_s2 <= no_positive_contribution_present_s1;
                    invalid_operation_s2 <= invalid_operation_s1;
                end
            end

            // ====================================================================
            // Stage 3: 正负合成 + 规格化舍入
            // ====================================================================
            wire signed [SUM_OUT_WIDTH:0] wallace_final_signed = 
                $signed({1'b0,pos_sum_s2}) - $signed({1'b0,neg_sum_s2});
            wire [SUM_OUT_WIDTH-1:0] abs_wallace_result = (wallace_final_signed < 0)
                                            ? -wallace_final_signed[SUM_OUT_WIDTH-1:0]
                                            :  wallace_final_signed[SUM_OUT_WIDTH-1:0];
            wire [SUM_OUT_WIDTH-1:0] result_mant_raw = abs_wallace_result;
            wire result_sign = (wallace_final_signed == 0) ? 
                               no_positive_contribution_present_s2 : (wallace_final_signed < 0);

            // 规格化 + 舍入（带舍入模式）
            wire [`FP32_WIDTH-1:0] normalized_fp_out;
            wire norm_overflow, norm_underflow, norm_zero_out, norm_inexact;
            
            fp32_normalizer_rounder #(.IN_WIDTH(SUM_OUT_WIDTH)) normalizer_inst (
                .clk(clk),
                .rst_n(rst_n),
                .mant_raw(result_mant_raw),
                .exp_in(max_exponent_s2),
                .sign_in(result_sign),
                .rounding_mode(rounding_mode_pipe[2]),  // Use pipelined rounding mode
                .fp_out(normalized_fp_out),
                .overflow(norm_overflow),
                .underflow(norm_underflow),
                .zero_out(norm_zero_out),
                .inexact(norm_inexact)
            );

            // Stage 3 寄存器
            wire [`FP32_WIDTH-1:0] normalized_fp_out_s3;
            wire norm_overflow_s3, norm_underflow_s3, norm_zero_out_s3, norm_inexact_s3;
            reg result_is_nan_condition_s3, result_is_inf_condition_s3;
            reg result_inf_sign_s3, result_sign_s3;
            reg invalid_operation_s3;

            assign normalized_fp_out_s3 = normalized_fp_out;
            assign norm_overflow_s3 = norm_overflow;
            assign norm_underflow_s3 = norm_underflow;
            assign norm_zero_out_s3 = norm_zero_out;
            assign norm_inexact_s3 = norm_inexact;
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    result_is_nan_condition_s3 <= 1'b0;
                    result_is_inf_condition_s3 <= 1'b0;
                    result_inf_sign_s3 <= 1'b0;
                    result_sign_s3 <= 1'b0;
                    invalid_operation_s3 <= 1'b0;
                end else if (valid_pipe[1]) begin
                    result_is_nan_condition_s3 <= result_is_nan_condition_s2;
                    result_is_inf_condition_s3 <= result_is_inf_condition_s2;
                    result_inf_sign_s3 <= result_inf_sign_s2;
                    result_sign_s3 <= result_sign;
                    invalid_operation_s3 <= invalid_operation_s2;
                end
            end

            // ====================================================================
            // Stage 4: 打包 + 异常标志生成
            // ====================================================================
            wire packer_sign = normalized_fp_out_s3[`FP32_WIDTH-1];
            wire [`FP32_EXP_WIDTH-1:0] packer_exp  = normalized_fp_out_s3[`FP32_WIDTH-2 : `FP32_MANT_WIDTH];
            wire [`FP32_MANT_WIDTH-1:0] packer_mant = normalized_fp_out_s3[`FP32_MANT_WIDTH-1 : 0];

            wire is_special_case = result_is_nan_condition_s3 || result_is_inf_condition_s3 || 
                                   norm_overflow_s3 || norm_underflow_s3;
            wire is_zero_out = !is_special_case && norm_zero_out_s3;

            wire final_sign_for_packer = (result_is_inf_condition_s3 || norm_overflow_s3) ?
                                           (result_is_inf_condition_s3 ? result_inf_sign_s3 : result_sign_s3) :
                                           (is_zero_out ? result_sign_s3 : packer_sign);

            wire [`FP32_WIDTH-1:0] add_result_wire;
            fp32_packer # (.IEEE_754(IEEE_754)) packer_inst (
                .final_sign(final_sign_for_packer),
                .final_exponent(packer_exp),
                .final_mantissa(packer_mant),
                .result_is_zero(is_zero_out),
                .result_is_inf(result_is_inf_condition_s3 || norm_overflow_s3),
                .result_is_nan(result_is_nan_condition_s3),
                .fp_out(add_result_wire)
            );

            // Exception Flags Generation
            wire [4:0] exception_flags_wire;
            assign exception_flags_wire[`EXC_INVALID]   = invalid_operation_s3;
            assign exception_flags_wire[`EXC_DIV_ZERO]  = 1'b0;  // N/A for adder
            assign exception_flags_wire[`EXC_OVERFLOW]  = norm_overflow_s3 && !result_is_nan_condition_s3;
            assign exception_flags_wire[`EXC_UNDERFLOW] = norm_underflow_s3 && !result_is_nan_condition_s3;
            assign exception_flags_wire[`EXC_INEXACT]   = norm_inexact_s3 && !result_is_nan_condition_s3 && !is_zero_out;

            // Stage 4 寄存器
            reg [`FP32_WIDTH-1:0] add_result_reg;
            reg [4:0] exception_flags_reg;
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    add_result_reg <= {`FP32_WIDTH{1'b0}};
                    exception_flags_reg <= 5'b0;
                end else if (valid_pipe[2]) begin
                    add_result_reg <= add_result_wire;
                    exception_flags_reg <= exception_flags_wire;
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    add_result_stage4[i] <= {`FP32_WIDTH{1'b0}};
                end else if (valid_pipe[2]) begin
                    add_result_stage4[i] <= add_result_wire;
                end
            end

            assign add_result[i] = add_result_reg;
            assign exception_flags[i] = exception_flags_reg;
        end
    endgenerate

    // ====================================================================
    // 输出组合逻辑
    // ====================================================================
    genvar out_idx;
    generate
        for (out_idx = 0; out_idx < 8; out_idx = out_idx + 1) begin : gen_output_loop
            assign dr_fp32addtree5to1_d0[out_idx*16 +: 16] = add_result[out_idx][15:0];
            assign dr_fp32addtree5to1_d1[out_idx*16 +: 16] = add_result[out_idx][31:16];
            assign o_exception_flags[out_idx] = exception_flags[out_idx];
        end
    endgenerate

endmodule


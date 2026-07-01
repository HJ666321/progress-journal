/*****************************************************************************
** Project  :  AIACC NPU                                                     **
******************************************************************************
**                                      **                                  **
** File name:  fp32_adder_pipeline.v    **             [Company]            **
** Designer :  [designer_name]         **  [Division]                      **
**                                      **                                  **
******************************************************************************
******************************************************************************
**                                                                          **
** Module Description:                                                      **
**                                                                          **
** FP32 floating-point adder with 4-stage pipeline for 100MHz operation.   **
** Supports denormal numbers, NaN, Inf, and all IEEE 754 FP32 operations. **
**                                                                          **
** Pipeline Stages:                                                        **
**   Stage 0: Decode + Alignment (Field extraction, special value detection,**
**            NaN/Inf handling, mantissa preparation, exponent alignment)  **
**   Stage 1: Computation (Mantissa addition/subtraction, double denormal)   **
**   Stage 2: Normalization (Leading zero count, exponent adjustment,       **
**            mantissa shift)                                               **
**   Stage 3: Rounding + Output (Rounding logic, overflow/underflow,       **
**            final output selection)                                       **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
** Hierarchy:                                                               **
**                                                                          **
** fp32_adder_pipeline                                                     **
**   - leading_zero_counter_fp32                                            **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
**   Revision        Date            By               Reason                **
** ------------   ------------   ------------      ------------             **
**     1.0                                           Creation               **
**                                                                          **
******************************************************************************
****************************************************************************** 
** This file has been provided pursuant to a License Agreement containing   **
** restrictions on its use. This data contains valuable trade secrets       **
** and proprietary information of [Company] and is protected                **
*****************************************************************************/
// $Revision: 1.0 $

`timescale 1ns/1ps

// Include rounding mode and exception flag definitions
`include "fp32_defines.vh"

//=========================================================================
// Sub-module: FP32 Leading Zero Counter (31-bit sum_mant_raw signal)
//=========================================================================
module leading_zero_counter_fp32 #(
    parameter DATA_WIDTH   = 31,  // Adapt to FP32 sum_mant_raw[30:0] (31 bits total)
    parameter COUNT_WIDTH  = 5    // 31-bit data max 31 leading zeros, 5 bits sufficient (0~31)
)(
    input  [DATA_WIDTH-1:0] i_data_in,       // Input: FP32 mantissa addition result sum_mant_raw[30:0]
    output [COUNT_WIDTH-1:0] o_leading_zeros // Output: leading zero count (0~31)
);

    // Array chain structure: avoid multiple assignments to same signal in loop
    reg [COUNT_WIDTH-1:0] r_count_chain [0:DATA_WIDTH];  // Count chain: store leading zero count for each bit
    reg r_found_chain [0:DATA_WIDTH];                    // Flag chain: mark if first 1 found
    
    integer i;  // Loop variable

    always @(*) begin
        // Initialization: when all bits are 0, leading zero count = data width (31)
        r_count_chain[DATA_WIDTH] = DATA_WIDTH[COUNT_WIDTH-1:0];  // 31[4:0] = 5'b11111
        r_found_chain[DATA_WIDTH] = 1'b0;                         // Initially no 1 found

        // Traverse from MSB (i_data_in[30]) to LSB (i_data_in[0])
        for (i = DATA_WIDTH-1; i >= 0; i = i-1) begin
            // Mark: current bit or higher bits already found 1
            r_found_chain[i] = r_found_chain[i+1] | i_data_in[i];
            
            // If current bit is first 1 (no 1 found before and current bit is 1), count = distance from current to MSB
            if (i_data_in[i] && !r_found_chain[i+1]) begin
                r_count_chain[i] = (DATA_WIDTH - 1) - i;  // MSB index=30, distance=30-i
            end else begin
                // Otherwise, inherit count from higher bits
                r_count_chain[i] = r_count_chain[i+1];
            end
        end
    end

    // Final output: count at LSB position (leading zero count for entire data)
    assign o_leading_zeros = r_count_chain[0];

endmodule

//=========================================================================
// Main Module: FP32 Floating Point Adder (4-stage pipeline)
//=========================================================================
module fp32_adder_pipeline #(
    parameter IEEE_754 = 1    // IEEE 754 mode
)(
    // Clock and Reset
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_valid,
    input  wire [2:0]  i_rounding_mode,  // Rounding mode: 000=RNE, 001=RTZ, 010=RDN, 011=RUP, 100=RMM
    // Input Operands
    input  wire [31:0] i_a,   // 32-bit floating point input A
    input  wire [31:0] i_b,   // 32-bit floating point input B
    
    // Output Result
    output reg  [31:0] o_sum,  // 32-bit floating point addition result
    output reg  [4:0]  o_exception_flags  // Exception flags: [0]=Invalid, [1]=DivZero, [2]=Overflow, [3]=Underflow, [4]=Inexact
);

    //=========================================================================
    // Global Parameters
    //=========================================================================
    parameter FP32_BIAS      = 8'd127;  // FP32 exponent bias
    parameter MIN_NORM_EXP   = -126;    // Minimum normalized exponent

    //=========================================================================
    // Stage 0: Decode + Alignment (Combinational Logic)
    //=========================================================================
    generate
        if (IEEE_754 == 1) begin : gen_ieee754
    // Field Extraction
    wire w_a_sign_s0 = i_a[31];
    wire w_b_sign_s0 = i_b[31];
    wire [7:0] w_a_exp_s0 = i_a[30:23];
    wire [7:0] w_b_exp_s0 = i_b[30:23];
    wire [22:0] w_a_frac_s0 = i_a[22:0];
    wire [22:0] w_b_frac_s0 = i_b[22:0];

    // Special Value Detection
    wire w_a_nan_s0 = (w_a_exp_s0 == 8'b11111111) && (w_a_frac_s0 != 23'b00000000000000000000000);
    wire w_b_nan_s0 = (w_b_exp_s0 == 8'b11111111) && (w_b_frac_s0 != 23'b00000000000000000000000);
    wire w_a_inf_s0 = (w_a_exp_s0 == 8'b11111111) && (w_a_frac_s0 == 23'b00000000000000000000000);
    wire w_b_inf_s0 = (w_b_exp_s0 == 8'b11111111) && (w_b_frac_s0 == 23'b00000000000000000000000);
    wire w_a_zero_s0 = (w_a_exp_s0 == 8'b0) && (w_a_frac_s0 == 23'b0);
    wire w_b_zero_s0 = (w_b_exp_s0 == 8'b0) && (w_b_frac_s0 == 23'b0);
    wire w_a_denorm_s0 = (w_a_exp_s0 == 8'b0) && (w_a_frac_s0 != 23'b0);
    wire w_b_denorm_s0 = (w_b_exp_s0 == 8'b0) && (w_b_frac_s0 != 23'b0);
    wire w_both_denorm_s0 = w_a_denorm_s0 && w_b_denorm_s0;

    // NaN/Inf Handling
    wire w_a_is_snan_s0 = w_a_nan_s0 && (w_a_frac_s0[22] == 1'b0);
    wire w_b_is_snan_s0 = w_b_nan_s0 && (w_b_frac_s0[22] == 1'b0);
    wire [21:0] w_a_nan_payload_raw_s0 = w_a_frac_s0[21:0];
    wire [21:0] w_b_nan_payload_raw_s0 = w_b_frac_s0[21:0];
    wire [21:0] w_a_nan_payload_s0 = (w_a_nan_payload_raw_s0 == 22'b0) ? 22'b1 : w_a_nan_payload_raw_s0;
    wire [21:0] w_b_nan_payload_s0 = (w_b_nan_payload_raw_s0 == 22'b0) ? 22'b1 : w_b_nan_payload_raw_s0;
    wire w_has_snan_s0 = w_a_is_snan_s0 || w_b_is_snan_s0;
    wire w_is_double_inf_s0 = w_a_inf_s0 && w_b_inf_s0;
    wire w_is_opposite_inf_s0 = w_is_double_inf_s0 && (w_a_sign_s0 != w_b_sign_s0);
    wire w_is_nan_s0 = w_a_nan_s0 || w_b_nan_s0 || w_is_opposite_inf_s0;
    wire w_nan_type_bit_s0 = w_has_snan_s0 ? 1'b0 : 1'b1;
    wire [21:0] w_nan_payload_s0 = w_a_nan_s0 ? w_a_nan_payload_s0 : w_b_nan_payload_s0;
    wire w_nan_sign_s0 = (w_a_inf_s0 && w_b_inf_s0 && w_a_sign_s0 != w_b_sign_s0) ? w_a_sign_s0 :
                         (w_a_nan_s0 ? w_a_sign_s0 : w_b_sign_s0);
    // wire [31:0] w_nan_result_s0 = {w_nan_sign_s0, 8'b11111111, w_nan_type_bit_s0, w_nan_payload_s0};
    wire [31:0] w_nan_result_s0 = {1'b0, 8'b11111111, {23{1'b1}}};
    wire w_is_inf_s0 = (w_a_inf_s0 || w_b_inf_s0) && !w_is_nan_s0;
    wire w_inf_sign_s0 = (w_a_inf_s0 && w_b_inf_s0) ? w_a_sign_s0 : (w_a_inf_s0 ? w_a_sign_s0 : w_b_sign_s0);
    wire [31:0] w_inf_result_s0 = {w_inf_sign_s0, 8'b11111111, 23'b0};

    // Mantissa Preparation
    wire [29:0] w_a_mant_s0 = w_a_denorm_s0 ? {1'b0, w_a_frac_s0, 6'b0} : {1'b1, w_a_frac_s0, 6'b0};
    wire [29:0] w_b_mant_s0 = w_b_denorm_s0 ? {1'b0, w_b_frac_s0, 6'b0} : {1'b1, w_b_frac_s0, 6'b0};
    wire [7:0] w_a_exp_actual_s0 = w_a_denorm_s0 ? 8'd1 : w_a_exp_s0;
    wire [7:0] w_b_exp_actual_s0 = w_b_denorm_s0 ? 8'd1 : w_b_exp_s0;

    // Exponent Alignment
    wire [7:0] w_exp_diff_s0 = (w_a_exp_actual_s0 > w_b_exp_actual_s0) ? 
                               (w_a_exp_actual_s0 - w_b_exp_actual_s0) : 
                               (w_b_exp_actual_s0 - w_a_exp_actual_s0);
    wire w_a_larger_exp_s0 = (w_a_exp_actual_s0 >= w_b_exp_actual_s0);
    wire [7:0] w_max_exp_s0 = w_a_larger_exp_s0 ? w_a_exp_actual_s0 : w_b_exp_actual_s0;
    wire [4:0] w_actual_shift_s0 = (w_exp_diff_s0 > 30) ? 5'd30 : w_exp_diff_s0[4:0];
    
    wire [29:0] w_a_mant_shifted_s0 = w_a_larger_exp_s0 ? w_a_mant_s0 : (w_a_mant_s0 >> w_actual_shift_s0);
    wire [29:0] w_b_mant_shifted_s0 = w_a_larger_exp_s0 ? (w_b_mant_s0 >> w_actual_shift_s0) : w_b_mant_s0;
    wire [29:0] w_sticky_mask_a_s0 = (w_actual_shift_s0 == 0) ? 30'b0 : ((1 << w_actual_shift_s0) - 1);
    wire [29:0] w_sticky_mask_b_s0 = (w_actual_shift_s0 == 0) ? 30'b0 : ((1 << w_actual_shift_s0) - 1);
    wire w_sticky_a_s0 = w_a_larger_exp_s0 ? 1'b0 : (|(w_a_mant_s0 & w_sticky_mask_a_s0));
    wire w_sticky_b_s0 = w_a_larger_exp_s0 ? (|(w_b_mant_s0 & w_sticky_mask_b_s0)) : 1'b0;
    wire [29:0] w_a_mant_aligned_s0 = w_a_mant_shifted_s0 | {29'b0, w_sticky_a_s0};
    wire [29:0] w_b_mant_aligned_s0 = w_b_mant_shifted_s0 | {29'b0, w_sticky_b_s0};

    // Swap logic for Stage 1
    wire w_swap_s0 = (w_a_exp_actual_s0 < w_b_exp_actual_s0) || 
                     ((w_a_exp_actual_s0 == w_b_exp_actual_s0) && (w_a_frac_s0 < w_b_frac_s0));
    wire [29:0] w_large_mant_s0 = w_swap_s0 ? w_b_mant_aligned_s0 : w_a_mant_aligned_s0;
    wire [29:0] w_small_mant_s0 = w_swap_s0 ? w_a_mant_aligned_s0 : w_b_mant_aligned_s0;
    wire w_large_sign_s0 = w_swap_s0 ? w_b_sign_s0 : w_a_sign_s0;
    wire w_small_sign_s0 = w_swap_s0 ? w_a_sign_s0 : w_b_sign_s0;
    wire w_operation_sub_s0 = (w_large_sign_s0 != w_small_sign_s0);

    // Double denormal calculation (for Stage 1)
    wire [29:0] w_a_mant_denorm_s0 = {1'b0, w_a_frac_s0, 6'b0};
    wire [29:0] w_b_mant_denorm_s0 = {1'b0, w_b_frac_s0, 6'b0};
    wire w_same_sign_denorm_s0 = (w_a_sign_s0 == w_b_sign_s0);
    wire w_a_larger_mant_denorm_s0 = (w_a_mant_denorm_s0 >= w_b_mant_denorm_s0);

    //=========================================================================
    // Stage 0 Registers
    //=========================================================================
    reg        r_a_sign_s1;
    reg        r_b_sign_s1;
    reg [29:0] r_large_mant_s1;
    reg [29:0] r_small_mant_s1;
    reg        r_large_sign_s1;
    reg        r_small_sign_s1;
    reg        r_operation_sub_s1;
    reg [7:0]  r_max_exp_s1;
    reg        r_is_nan_s1;
    reg        r_is_inf_s1;
    reg        r_a_zero_s1;
    reg        r_b_zero_s1;
    reg        r_both_denorm_s1;
    reg [31:0] r_nan_result_s1;
    reg [31:0] r_inf_result_s1;
    reg [31:0] r_i_a_s1;
    reg [31:0] r_i_b_s1;
    
    // Double denormal signals
    reg [29:0] r_a_mant_denorm_s1;
    reg [29:0] r_b_mant_denorm_s1;
    reg        r_same_sign_denorm_s1;
    reg        r_a_larger_mant_denorm_s1;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_a_sign_s1 <= 1'b0;
            r_b_sign_s1 <= 1'b0;
            r_large_mant_s1 <= 30'd0;
            r_small_mant_s1 <= 30'd0;
            r_large_sign_s1 <= 1'b0;
            r_small_sign_s1 <= 1'b0;
            r_operation_sub_s1 <= 1'b0;
            r_max_exp_s1 <= 8'd0;
            r_is_nan_s1 <= 1'b0;
            r_is_inf_s1 <= 1'b0;
            r_a_zero_s1 <= 1'b0;
            r_b_zero_s1 <= 1'b0;
            r_both_denorm_s1 <= 1'b0;
            r_nan_result_s1 <= 32'd0;
            r_inf_result_s1 <= 32'd0;
            r_i_a_s1 <= 32'd0;
            r_i_b_s1 <= 32'd0;
            r_a_mant_denorm_s1 <= 30'd0;
            r_b_mant_denorm_s1 <= 30'd0;
            r_same_sign_denorm_s1 <= 1'b0;
            r_a_larger_mant_denorm_s1 <= 1'b0;
        end else if (i_valid) begin
            r_a_sign_s1 <= w_a_sign_s0;
            r_b_sign_s1 <= w_b_sign_s0;
            r_large_mant_s1 <= w_large_mant_s0;
            r_small_mant_s1 <= w_small_mant_s0;
            r_large_sign_s1 <= w_large_sign_s0;
            r_small_sign_s1 <= w_small_sign_s0;
            r_operation_sub_s1 <= w_operation_sub_s0;
            r_max_exp_s1 <= w_max_exp_s0;
            r_is_nan_s1 <= w_is_nan_s0;
            r_is_inf_s1 <= w_is_inf_s0;
            r_a_zero_s1 <= w_a_zero_s0;
            r_b_zero_s1 <= w_b_zero_s0;
            r_both_denorm_s1 <= w_both_denorm_s0;
            r_nan_result_s1 <= w_nan_result_s0;
            r_inf_result_s1 <= w_inf_result_s0;
            r_i_a_s1 <= i_a;
            r_i_b_s1 <= i_b;
            r_a_mant_denorm_s1 <= w_a_mant_denorm_s0;
            r_b_mant_denorm_s1 <= w_b_mant_denorm_s0;
            r_same_sign_denorm_s1 <= w_same_sign_denorm_s0;
            r_a_larger_mant_denorm_s1 <= w_a_larger_mant_denorm_s0;
        end
    end

    //=========================================================================
    // Stage 1: Computation (Combinational Logic)
    //=========================================================================
    
    // Mantissa Addition/Subtraction
    wire [30:0] w_sum_mant_raw_s1;
    wire w_result_sign_s1;
    
    assign w_sum_mant_raw_s1 = r_operation_sub_s1 ?
        ((r_large_mant_s1 >= r_small_mant_s1) ? 
         ({1'b0, r_large_mant_s1} - {1'b0, r_small_mant_s1}) : 
         ({1'b0, r_small_mant_s1} - {1'b0, r_large_mant_s1})) :
        ({1'b0, r_large_mant_s1} + {1'b0, r_small_mant_s1});
        
    assign w_result_sign_s1 = r_operation_sub_s1 ? 
        ((r_large_mant_s1 >= r_small_mant_s1) ? r_large_sign_s1 : r_small_sign_s1) : 
        r_large_sign_s1;

    // Double denormal add/sub
    wire [29:0] w_mant_result_denorm_s1 = r_both_denorm_s1 ? (
        r_same_sign_denorm_s1 ? (r_a_mant_denorm_s1 + r_b_mant_denorm_s1) :
        (r_a_larger_mant_denorm_s1 ? (r_a_mant_denorm_s1 - r_b_mant_denorm_s1) : 
                                     (r_b_mant_denorm_s1 - r_a_mant_denorm_s1))
    ) : 30'd0;
    
    wire w_mant_zero_denorm_s1 = (w_mant_result_denorm_s1 == 30'd0);
    wire [23:0] w_frac_final_denorm_s1 = r_both_denorm_s1 ? (
        w_mant_zero_denorm_s1 ? 23'd0 : (w_mant_result_denorm_s1 >> 6)
    ) : 23'd0;
    wire [22:0] w_rounded_mant_denorm_s1 = w_frac_final_denorm_s1[22:0];
    wire w_sign_denorm_s1 = r_both_denorm_s1 ? (
        w_mant_zero_denorm_s1 ? 1'b0 : 
        (r_same_sign_denorm_s1 ? r_a_sign_s1 : 
         (r_a_larger_mant_denorm_s1 ? r_a_sign_s1 : r_b_sign_s1))
    ) : 1'b0;

    //=========================================================================
    // Stage 1 Registers
    //=========================================================================
    reg [30:0] r_sum_mant_raw_s2;
    reg        r_result_sign_s2;
    reg [7:0]  r_max_exp_s2;
    reg        r_is_nan_s2;
    reg        r_is_inf_s2;
    reg        r_a_zero_s2;
    reg        r_b_zero_s2;
    reg        r_both_denorm_s2;
    reg [31:0] r_nan_result_s2;
    reg [31:0] r_inf_result_s2;
    reg [31:0] r_i_a_s2;
    reg [31:0] r_i_b_s2;
    reg [22:0] r_rounded_mant_denorm_s2;
    reg        r_sign_denorm_s2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_sum_mant_raw_s2 <= 31'd0;
            r_result_sign_s2 <= 1'b0;
            r_max_exp_s2 <= 8'd0;
            r_is_nan_s2 <= 1'b0;
            r_is_inf_s2 <= 1'b0;
            r_a_zero_s2 <= 1'b0;
            r_b_zero_s2 <= 1'b0;
            r_both_denorm_s2 <= 1'b0;
            r_nan_result_s2 <= 32'd0;
            r_inf_result_s2 <= 32'd0;
            r_i_a_s2 <= 32'd0;
            r_i_b_s2 <= 32'd0;
            r_rounded_mant_denorm_s2 <= 23'd0;
            r_sign_denorm_s2 <= 1'b0;
        end else begin
            r_sum_mant_raw_s2 <= w_sum_mant_raw_s1;
            r_result_sign_s2 <= w_result_sign_s1;
            r_max_exp_s2 <= r_max_exp_s1;
            r_is_nan_s2 <= r_is_nan_s1;
            r_is_inf_s2 <= r_is_inf_s1;
            r_a_zero_s2 <= r_a_zero_s1;
            r_b_zero_s2 <= r_b_zero_s1;
            r_both_denorm_s2 <= r_both_denorm_s1;
            r_nan_result_s2 <= r_nan_result_s1;
            r_inf_result_s2 <= r_inf_result_s1;
            r_i_a_s2 <= r_i_a_s1;
            r_i_b_s2 <= r_i_b_s1;
            r_rounded_mant_denorm_s2 <= w_rounded_mant_denorm_s1;
            r_sign_denorm_s2 <= w_sign_denorm_s1;
        end
    end

    //=========================================================================
    // Stage 2: Normalization (Combinational Logic)
    //=========================================================================
    
    // Leading Zero Counter
    wire [4:0] w_lz_count_s2;
    leading_zero_counter_fp32 u_leading_zero_counter(
        .i_data_in      (r_sum_mant_raw_s2),
        .o_leading_zeros(w_lz_count_s2)
    );

    // Calculate leading_one and normalization
    wire [4:0] w_leading_one_s2 = (w_lz_count_s2 == 5'd31) ? 5'd0 : (5'd30 - w_lz_count_s2);
    wire [8:0] w_temp_exp_ext_s2 = {1'b0, r_max_exp_s2} + {1'b0, w_leading_one_s2} - 9'd29;
    wire w_temp_exp_pos_s2 = !w_temp_exp_ext_s2[8];
    wire w_temp_exp_ge1_s2 = w_temp_exp_pos_s2 && (w_temp_exp_ext_s2[7:0] >= 8'b1);
    wire w_exp_underflow_s2 = !w_temp_exp_pos_s2 || (w_temp_exp_ext_s2[7:0] == 8'b0);
    
    wire [8:0] w_temp_exp_signed_s2 = w_temp_exp_ext_s2;
    wire [4:0] w_denorm_shift_right_s2 = w_exp_underflow_s2 ? (2 - $signed(w_temp_exp_signed_s2)) : 5'd0;
    wire [4:0] w_shift_amount_left_s2 = 30 - w_leading_one_s2;
    wire [30:0] w_shifted_sum_temp_s2 = r_sum_mant_raw_s2 << w_shift_amount_left_s2;
    wire [30:0] w_shifted_sum_denorm_s2 = w_shifted_sum_temp_s2 >> w_denorm_shift_right_s2;
    wire [4:0] w_shift_amount_s2 = w_exp_underflow_s2 ? 5'd0 : (30 - w_leading_one_s2);
    wire [30:0] w_shifted_sum_s2 = w_exp_underflow_s2 ? w_shifted_sum_denorm_s2 : (r_sum_mant_raw_s2 << w_shift_amount_s2);
    
    wire [29:0] w_normalized_mant_s2 = w_shifted_sum_s2[29:0];
    wire [7:0]  w_normalized_exp_s2 = w_exp_underflow_s2 ? 8'b0 : w_temp_exp_ext_s2[7:0];
    wire [2:0]  w_round_bits_s2 = {w_normalized_mant_s2[6], w_normalized_mant_s2[5], |w_normalized_mant_s2[4:0]};

    //=========================================================================
    // Stage 2 Registers
    //=========================================================================
    reg [29:0] r_normalized_mant_s3;
    reg [7:0]  r_normalized_exp_s3;
    reg [2:0]  r_round_bits_s3;
    reg        r_exp_underflow_s3;
    reg        r_result_sign_s3;
    reg        r_is_nan_s3;
    reg        r_is_inf_s3;
    reg        r_a_zero_s3;
    reg        r_b_zero_s3;
    reg        r_both_denorm_s3;
    reg [31:0] r_nan_result_s3;
    reg [31:0] r_inf_result_s3;
    reg [31:0] r_i_a_s3;
    reg [31:0] r_i_b_s3;
    reg [22:0] r_rounded_mant_denorm_s3;
    reg        r_sign_denorm_s3;
    reg [8:0]  r_temp_exp_ext_s3;
    reg        r_temp_exp_ge1_s3;
    reg [30:0] r_sum_mant_raw_s3;
    reg [2:0]  r_rounding_mode_s3;  // Pipeline rounding mode

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_normalized_mant_s3 <= 30'd0;
            r_normalized_exp_s3 <= 8'd0;
            r_round_bits_s3 <= 3'd0;
            r_exp_underflow_s3 <= 1'b0;
            r_result_sign_s3 <= 1'b0;
            r_is_nan_s3 <= 1'b0;
            r_is_inf_s3 <= 1'b0;
            r_a_zero_s3 <= 1'b0;
            r_b_zero_s3 <= 1'b0;
            r_both_denorm_s3 <= 1'b0;
            r_nan_result_s3 <= 32'd0;
            r_inf_result_s3 <= 32'd0;
            r_i_a_s3 <= 32'd0;
            r_i_b_s3 <= 32'd0;
            r_rounded_mant_denorm_s3 <= 23'd0;
            r_sign_denorm_s3 <= 1'b0;
            r_temp_exp_ext_s3 <= 9'd0;
            r_temp_exp_ge1_s3 <= 1'b0;
            r_sum_mant_raw_s3 <= 31'd0;
            r_rounding_mode_s3 <= `RM_RNE;
        end else begin
            r_normalized_mant_s3 <= w_normalized_mant_s2;
            r_normalized_exp_s3 <= w_normalized_exp_s2;
            r_round_bits_s3 <= w_round_bits_s2;
            r_exp_underflow_s3 <= w_exp_underflow_s2;
            r_result_sign_s3 <= r_result_sign_s2;
            r_is_nan_s3 <= r_is_nan_s2;
            r_is_inf_s3 <= r_is_inf_s2;
            r_a_zero_s3 <= r_a_zero_s2;
            r_b_zero_s3 <= r_b_zero_s2;
            r_both_denorm_s3 <= r_both_denorm_s2;
            r_nan_result_s3 <= r_nan_result_s2;
            r_inf_result_s3 <= r_inf_result_s2;
            r_i_a_s3 <= r_i_a_s2;
            r_i_b_s3 <= r_i_b_s2;
            r_rounded_mant_denorm_s3 <= r_rounded_mant_denorm_s2;
            r_sign_denorm_s3 <= r_sign_denorm_s2;
            r_temp_exp_ext_s3 <= w_temp_exp_ext_s2;
            r_temp_exp_ge1_s3 <= w_temp_exp_ge1_s2;
            r_sum_mant_raw_s3 <= r_sum_mant_raw_s2;
            r_rounding_mode_s3 <= i_rounding_mode;  // Pass rounding mode to Stage 3
        end
    end

    //=========================================================================
    // Stage 3: Rounding + Output (Combinational Logic)
    //=========================================================================
    
    // Rounding Logic - Support all 5 rounding modes
    wire w_guard_s3 = r_round_bits_s3[2];
    wire w_round_bit_s3 = r_round_bits_s3[1];
    wire w_sticky_bit_s3 = r_round_bits_s3[0];
    wire w_lsb_s3 = r_exp_underflow_s3 ? r_normalized_mant_s3[5] : r_normalized_mant_s3[7];
    wire w_extended_sticky_s3 = w_sticky_bit_s3 || r_normalized_mant_s3[5];
    wire w_has_discarded_bits_s3 = w_guard_s3 | w_round_bit_s3 | w_sticky_bit_s3;
    
    reg w_round_up_s3;
    always @(*) begin
        case (r_rounding_mode_s3)
            `RM_RNE: begin  // Round to Nearest, ties to Even
                w_round_up_s3 = (w_guard_s3 && w_round_bit_s3) || 
                                (w_guard_s3 && w_extended_sticky_s3) || 
                                (w_guard_s3 && !w_round_bit_s3 && !w_extended_sticky_s3 && w_lsb_s3);
            end
            `RM_RTZ: begin  // Round Towards Zero
                w_round_up_s3 = 1'b0;  // Always round down (towards zero)
            end
            `RM_RDN: begin  // Round Down (towards -∞)
                w_round_up_s3 = r_result_sign_s3 && w_has_discarded_bits_s3;  // Negative with discarded bits -> round up (towards -∞)
            end
            `RM_RUP: begin  // Round Up (towards +∞)
                w_round_up_s3 = ~r_result_sign_s3 && w_has_discarded_bits_s3;  // Positive with discarded bits -> round up (towards +∞)
            end
            `RM_RMM: begin  // Round to Nearest, ties to Max magnitude
                w_round_up_s3 = w_guard_s3;  // G=1 -> round up
            end
            default: begin  // Default to RNE
                w_round_up_s3 = (w_guard_s3 && w_round_bit_s3) || 
                                (w_guard_s3 && w_extended_sticky_s3) || 
                                (w_guard_s3 && !w_round_bit_s3 && !w_extended_sticky_s3 && w_lsb_s3);
            end
        endcase
    end
    
    wire [23:0] w_rounded_mant_s3 = r_exp_underflow_s3 ?
        {1'b0, r_normalized_mant_s3[28:6]} + (w_round_up_s3 ? 24'd1 : 24'd0) :
        {1'b0, r_normalized_mant_s3[29:7]} + (w_round_up_s3 ? 24'd1 : 24'd0);
    wire w_round_carry_s3 = w_rounded_mant_s3[23];

    // Overflow/Underflow Handling - Based on rounding mode
    wire [7:0] w_exp_max = 8'd255;
    wire [7:0] w_exp_max_finite = 8'd254;
    wire [22:0] w_mant_max = {23{1'b1}};
    
    reg [7:0] w_final_exp_val_s3;
    reg [22:0] w_final_frac_s3;
    reg w_overflow_s3;
    reg w_underflow_s3;
    
    // Overflow output based on rounding mode
    reg [7:0] w_exp_out_overflow_s3;
    reg [22:0] w_mant_out_overflow_s3;
    
    // Underflow output based on rounding mode (RDN/RUP need special handling)
    reg [22:0] w_mant_out_underflow_s3;
    
    always @(*) begin
        if (w_round_carry_s3) begin
            w_final_exp_val_s3 = r_normalized_exp_s3 + 8'd1;
            w_final_frac_s3 = w_rounded_mant_s3[22:0];
        end else begin
            w_final_exp_val_s3 = r_normalized_exp_s3;
            w_final_frac_s3 = w_rounded_mant_s3[22:0];
        end
        
        // Overflow detection and output selection
        // Note: Overflow occurs when exp > max_finite (not >=), as exp == 254 is still a valid finite number
        case (r_rounding_mode_s3)
            `RM_RNE, `RM_RMM: begin
                w_overflow_s3 = (w_final_exp_val_s3 > w_exp_max_finite);  // exp > 254 -> overflow to Inf
                w_exp_out_overflow_s3 = w_exp_max;  // ±Inf
                w_mant_out_overflow_s3 = 23'b0;
            end
            `RM_RTZ: begin
                w_overflow_s3 = (w_final_exp_val_s3 > w_exp_max_finite);  // exp > 254 -> overflow to Max
                w_exp_out_overflow_s3 = w_exp_max_finite;  // ±Max
                w_mant_out_overflow_s3 = w_mant_max;
            end
            `RM_RDN: begin
                w_overflow_s3 = r_result_sign_s3 ? (w_final_exp_val_s3 > w_exp_max_finite) : (w_final_exp_val_s3 > w_exp_max_finite);
                // Negative: exp > 254 -> -∞, Positive: exp > 254 -> +Max
                w_exp_out_overflow_s3 = r_result_sign_s3 ? w_exp_max : w_exp_max_finite;  // -∞ or +Max
                w_mant_out_overflow_s3 = r_result_sign_s3 ? 23'b0 : w_mant_max;
            end
            `RM_RUP: begin
                w_overflow_s3 = r_result_sign_s3 ? (w_final_exp_val_s3 > w_exp_max_finite) : (w_final_exp_val_s3 > w_exp_max_finite);
                // Negative: exp > 254 -> -Max, Positive: exp > 254 -> +∞
                w_exp_out_overflow_s3 = r_result_sign_s3 ? w_exp_max_finite : w_exp_max;  // -Max or +∞
                w_mant_out_overflow_s3 = r_result_sign_s3 ? w_mant_max : 23'b0;
            end
            default: begin
                w_overflow_s3 = (w_final_exp_val_s3 > w_exp_max_finite);  // exp > 254 -> overflow to Inf
                w_exp_out_overflow_s3 = w_exp_max;  // Default to ±Inf
                w_mant_out_overflow_s3 = 23'b0;
            end
        endcase
        
        // Underflow detection and output selection
        w_underflow_s3 = (r_normalized_exp_s3 == 8'b0) && (w_rounded_mant_s3[22:0] != 23'b0);
        
        // Underflow output based on rounding mode (RDN/RUP need special handling)
        case (r_rounding_mode_s3)
            `RM_RDN: begin
                // Round Down: 负数下溢→最小负非规格化数(0x80000001), 正数下溢→+0.0
                w_mant_out_underflow_s3 = r_result_sign_s3 ? 23'b1 : 23'b0;
            end
            `RM_RUP: begin
                // Round Up: 负数下溢→-0.0, 正数下溢→最小正非规格化数(0x00000001)
                w_mant_out_underflow_s3 = r_result_sign_s3 ? 23'b0 : 23'b1;
            end
            default: begin
                // RNE, RTZ, RMM: 下溢时输出零
                w_mant_out_underflow_s3 = 23'b0;
            end
        endcase
    end

    // Exception flags generation
    wire w_invalid_operation_s3 = r_is_nan_s3;  // NaN input or Inf-Inf
    wire w_has_discarded_bits_s3 = w_guard_s3 | w_round_bit_s3 | w_sticky_bit_s3;
    wire w_inexact_flag_s3 = w_has_discarded_bits_s3 && !r_is_nan_s3 && 
                             !((r_a_zero_s3 && r_b_zero_s3) || (r_sum_mant_raw_s3 == 31'd0));
    
    wire [4:0] w_exception_flags_wire;
    assign w_exception_flags_wire[`EXC_INVALID]   = w_invalid_operation_s3;
    assign w_exception_flags_wire[`EXC_DIV_ZERO]  = 1'b0;  // N/A for adder
    assign w_exception_flags_wire[`EXC_OVERFLOW]  = w_overflow_s3 && !r_is_nan_s3;
    assign w_exception_flags_wire[`EXC_UNDERFLOW] = w_underflow_s3 && !r_is_nan_s3 && !r_exp_underflow_s3;
    assign w_exception_flags_wire[`EXC_INEXACT]   = w_inexact_flag_s3;

    // Final Output Selection
    always @(*) begin
        case (1'b1)
            // 1. Highest priority: NaN scenario
            r_is_nan_s3: begin
                o_sum <= r_nan_result_s3;
            end
            
            // 2. Second priority: Infinity/overflow scenario
            r_is_inf_s3: begin
                o_sum <= r_inf_result_s3;
            end
            w_overflow_s3: begin
                // Overflow output based on rounding mode
                o_sum <= {r_result_sign_s3, w_exp_out_overflow_s3, w_mant_out_overflow_s3};
            end
            
            // 3. Single zero scenario
            r_a_zero_s3 && !r_b_zero_s3: o_sum <= r_i_b_s3;
            !r_a_zero_s3 && r_b_zero_s3: o_sum <= r_i_a_s3;
            
            // 4. Double zero scenario
            r_a_zero_s3 && r_b_zero_s3: o_sum <= {r_result_sign_s3, 31'b0};
            
            // 5. Double denormal scenario
            r_both_denorm_s3: o_sum <= r_temp_exp_ge1_s3 ? 
                {r_sign_denorm_s3, r_temp_exp_ext_s3[7:0], w_rounded_mant_s3[22:0]} : 
                {r_sign_denorm_s3, 8'b0, r_rounded_mant_denorm_s3};
            
            // 6. Operation result zero scenario
            r_sum_mant_raw_s3 == 31'd0: o_sum <= {r_result_sign_s3, 31'b0};
            
            // 7. Underflow scenario - Based on rounding mode
            w_underflow_s3 || r_exp_underflow_s3: begin
                if (w_underflow_s3 && !r_exp_underflow_s3) begin
                    // Underflow: use rounding mode specific output
                    o_sum <= {r_result_sign_s3, 8'b0, w_mant_out_underflow_s3};
                end else begin
                    // Exponent underflow: output denormal
                    o_sum <= {r_result_sign_s3, 8'b0, w_rounded_mant_s3[22:0]};
                end
            end
            
            // 8. Default scenario: normal normalized operation
            default: o_sum <= {r_result_sign_s3, w_final_exp_val_s3, w_final_frac_s3};
        endcase
    end
    
    // Exception flags output
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_exception_flags <= 5'b0;
        end else begin
            o_exception_flags <= w_exception_flags_wire;
        end
    end
        end else begin : gen_non_ieee754
            // Non-IEEE 754 mode


    //=========================================================================
    // Stage 0: Decode + Alignment (Combinational Logic)
    //=========================================================================
    
    // Field Extraction
    wire w_a_sign_s0 = i_a[31];
    wire w_b_sign_s0 = i_b[31];
    wire [7:0] w_a_exp_s0 = i_a[30:23];
    wire [7:0] w_b_exp_s0 = i_b[30:23];
    wire [22:0] w_a_frac_s0 = i_a[22:0];
    wire [22:0] w_b_frac_s0 = i_b[22:0];

    // Special Value Detection
    wire w_a_nan_s0 = (w_a_exp_s0 == 8'b11111111) && (w_a_frac_s0 != 23'b00000000000000000000000);
    wire w_b_nan_s0 = (w_b_exp_s0 == 8'b11111111) && (w_b_frac_s0 != 23'b00000000000000000000000);
    wire w_a_inf_s0 = (w_a_exp_s0 == 8'b11111111) && (w_a_frac_s0 == 23'b00000000000000000000000);
    wire w_b_inf_s0 = (w_b_exp_s0 == 8'b11111111) && (w_b_frac_s0 == 23'b00000000000000000000000);
    wire w_a_zero_s0 = (w_a_exp_s0 == 8'b0) && (w_a_frac_s0 == 23'b0);
    wire w_b_zero_s0 = (w_b_exp_s0 == 8'b0) && (w_b_frac_s0 == 23'b0);
    wire w_a_denorm_s0 = (w_a_exp_s0 == 8'b0) && (w_a_frac_s0 != 23'b0);
    wire w_b_denorm_s0 = (w_b_exp_s0 == 8'b0) && (w_b_frac_s0 != 23'b0);
    wire w_both_denorm_s0 = 1'b0; // No longer needed since denorm treated as zero
    // Treat denorm as zero
    wire w_a_effective_zero_s0 = w_a_zero_s0 || w_a_denorm_s0;
    wire w_b_effective_zero_s0 = w_b_zero_s0 || w_b_denorm_s0;

    // NaN/Inf Handling
    wire w_a_is_snan_s0 = w_a_nan_s0 && (w_a_frac_s0[22] == 1'b0);
    wire w_b_is_snan_s0 = w_b_nan_s0 && (w_b_frac_s0[22] == 1'b0);
    wire [21:0] w_a_nan_payload_raw_s0 = w_a_frac_s0[21:0];
    wire [21:0] w_b_nan_payload_raw_s0 = w_b_frac_s0[21:0];
    wire [21:0] w_a_nan_payload_s0 = (w_a_nan_payload_raw_s0 == 22'b0) ? 22'b1 : w_a_nan_payload_raw_s0;
    wire [21:0] w_b_nan_payload_s0 = (w_b_nan_payload_raw_s0 == 22'b0) ? 22'b1 : w_b_nan_payload_raw_s0;
    wire w_has_snan_s0 = w_a_is_snan_s0 || w_b_is_snan_s0;
    wire w_is_double_inf_s0 = w_a_inf_s0 && w_b_inf_s0;
    wire w_is_opposite_inf_s0 = w_is_double_inf_s0 && (w_a_sign_s0 != w_b_sign_s0);
    wire w_is_nan_s0 = w_a_nan_s0 || w_b_nan_s0 || w_is_opposite_inf_s0;
    wire w_nan_type_bit_s0 = w_has_snan_s0 ? 1'b0 : 1'b1;
    wire [21:0] w_nan_payload_s0 = w_a_nan_s0 ? w_a_nan_payload_s0 : w_b_nan_payload_s0;
    wire w_nan_sign_s0 = (w_a_inf_s0 && w_b_inf_s0 && w_a_sign_s0 != w_b_sign_s0) ? w_a_sign_s0 :
                         (w_a_nan_s0 ? w_a_sign_s0 : w_b_sign_s0);
    wire [31:0] w_nan_result_s0 = {w_nan_sign_s0, 8'b11111111, w_nan_type_bit_s0, w_nan_payload_s0};
    wire w_is_inf_s0 = (w_a_inf_s0 || w_b_inf_s0) && !w_is_nan_s0;
    wire w_inf_sign_s0 = (w_a_inf_s0 && w_b_inf_s0) ? w_a_sign_s0 : (w_a_inf_s0 ? w_a_sign_s0 : w_b_sign_s0);
    wire [31:0] w_inf_result_s0 = {w_inf_sign_s0, 8'b11111111, 23'b0};

    // Mantissa Preparation - treat denorm as zero
    wire [29:0] w_a_mant_s0 = w_a_effective_zero_s0 ? 30'b0 : {1'b1, w_a_frac_s0, 6'b0};
    wire [29:0] w_b_mant_s0 = w_b_effective_zero_s0 ? 30'b0 : {1'b1, w_b_frac_s0, 6'b0};
    wire [7:0] w_a_exp_actual_s0 = w_a_effective_zero_s0 ? 8'd0 : w_a_exp_s0;
    wire [7:0] w_b_exp_actual_s0 = w_b_effective_zero_s0 ? 8'd0 : w_b_exp_s0;

    // Exponent Alignment
    wire [7:0] w_exp_diff_s0 = (w_a_exp_actual_s0 > w_b_exp_actual_s0) ? 
                               (w_a_exp_actual_s0 - w_b_exp_actual_s0) : 
                               (w_b_exp_actual_s0 - w_a_exp_actual_s0);
    wire w_a_larger_exp_s0 = (w_a_exp_actual_s0 >= w_b_exp_actual_s0);
    wire [7:0] w_max_exp_s0 = w_a_larger_exp_s0 ? w_a_exp_actual_s0 : w_b_exp_actual_s0;
    wire [4:0] w_actual_shift_s0 = (w_exp_diff_s0 > 30) ? 5'd30 : w_exp_diff_s0[4:0];
    
    wire [29:0] w_a_mant_shifted_s0 = w_a_larger_exp_s0 ? w_a_mant_s0 : (w_a_mant_s0 >> w_actual_shift_s0);
    wire [29:0] w_b_mant_shifted_s0 = w_a_larger_exp_s0 ? (w_b_mant_s0 >> w_actual_shift_s0) : w_b_mant_s0;
    wire [29:0] w_sticky_mask_a_s0 = (w_actual_shift_s0 == 0) ? 30'b0 : ((1 << w_actual_shift_s0) - 1);
    wire [29:0] w_sticky_mask_b_s0 = (w_actual_shift_s0 == 0) ? 30'b0 : ((1 << w_actual_shift_s0) - 1);
    wire w_sticky_a_s0 = w_a_larger_exp_s0 ? 1'b0 : (|(w_a_mant_s0 & w_sticky_mask_a_s0));
    wire w_sticky_b_s0 = w_a_larger_exp_s0 ? (|(w_b_mant_s0 & w_sticky_mask_b_s0)) : 1'b0;
    wire [29:0] w_a_mant_aligned_s0 = w_a_mant_shifted_s0 | {29'b0, w_sticky_a_s0};
    wire [29:0] w_b_mant_aligned_s0 = w_b_mant_shifted_s0 | {29'b0, w_sticky_b_s0};

    // Swap logic for Stage 1
    wire w_swap_s0 = (w_a_exp_actual_s0 < w_b_exp_actual_s0) || 
                     ((w_a_exp_actual_s0 == w_b_exp_actual_s0) && (w_a_frac_s0 < w_b_frac_s0));
    wire [29:0] w_large_mant_s0 = w_swap_s0 ? w_b_mant_aligned_s0 : w_a_mant_aligned_s0;
    wire [29:0] w_small_mant_s0 = w_swap_s0 ? w_a_mant_aligned_s0 : w_b_mant_aligned_s0;
    wire w_large_sign_s0 = w_swap_s0 ? w_b_sign_s0 : w_a_sign_s0;
    wire w_small_sign_s0 = w_swap_s0 ? w_a_sign_s0 : w_b_sign_s0;
    wire w_operation_sub_s0 = (w_large_sign_s0 != w_small_sign_s0);

    // Double denormal calculation removed - denorm treated as zero

    //=========================================================================
    // Stage 0 Registers
    //=========================================================================
    reg        r_a_sign_s1;
    reg        r_b_sign_s1;
    reg [29:0] r_large_mant_s1;
    reg [29:0] r_small_mant_s1;
    reg        r_large_sign_s1;
    reg        r_small_sign_s1;
    reg        r_operation_sub_s1;
    reg [7:0]  r_max_exp_s1;
    reg        r_is_nan_s1;
    reg        r_is_inf_s1;
    reg        r_a_zero_s1;
    reg        r_b_zero_s1;
    // r_both_denorm_s1 removed
    reg [31:0] r_nan_result_s1;
    reg [31:0] r_inf_result_s1;
    reg [31:0] r_i_a_s1;
    reg [31:0] r_i_b_s1;
    
    // Double denormal signals removed (denorm treated as zero)

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_a_sign_s1 <= 1'b0;
            r_b_sign_s1 <= 1'b0;
            r_large_mant_s1 <= 30'd0;
            r_small_mant_s1 <= 30'd0;
            r_large_sign_s1 <= 1'b0;
            r_small_sign_s1 <= 1'b0;
            r_operation_sub_s1 <= 1'b0;
            r_max_exp_s1 <= 8'd0;
            r_is_nan_s1 <= 1'b0;
            r_is_inf_s1 <= 1'b0;
            r_a_zero_s1 <= 1'b0;
            r_b_zero_s1 <= 1'b0;
            // r_both_denorm_s1 removed
            r_nan_result_s1 <= 32'd0;
            r_inf_result_s1 <= 32'd0;
            r_i_a_s1 <= 32'd0;
            r_i_b_s1 <= 32'd0;
            // Denorm signals removed
        end else if (i_valid) begin
            r_a_sign_s1 <= w_a_sign_s0;
            r_b_sign_s1 <= w_b_sign_s0;
            r_large_mant_s1 <= w_large_mant_s0;
            r_small_mant_s1 <= w_small_mant_s0;
            r_large_sign_s1 <= w_large_sign_s0;
            r_small_sign_s1 <= w_small_sign_s0;
            r_operation_sub_s1 <= w_operation_sub_s0;
            r_max_exp_s1 <= w_max_exp_s0;
            r_is_nan_s1 <= w_is_nan_s0;
            r_is_inf_s1 <= w_is_inf_s0;
            r_a_zero_s1 <= w_a_effective_zero_s0;
            r_b_zero_s1 <= w_b_effective_zero_s0;
            // r_both_denorm_s1 removed // No longer needed
            r_nan_result_s1 <= w_nan_result_s0;
            r_inf_result_s1 <= w_inf_result_s0;
            r_i_a_s1 <= i_a;
            r_i_b_s1 <= i_b;
            // Denorm signals removed - treated as zero
        end
    end

    //=========================================================================
    // Stage 1: Computation (Combinational Logic)
    //=========================================================================
    
    // Mantissa Addition/Subtraction
    wire [30:0] w_sum_mant_raw_s1;
    wire w_result_sign_s1;
    
    assign w_sum_mant_raw_s1 = r_operation_sub_s1 ?
        ((r_large_mant_s1 >= r_small_mant_s1) ? 
         ({1'b0, r_large_mant_s1} - {1'b0, r_small_mant_s1}) : 
         ({1'b0, r_small_mant_s1} - {1'b0, r_large_mant_s1})) :
        ({1'b0, r_large_mant_s1} + {1'b0, r_small_mant_s1});
        
    assign w_result_sign_s1 = r_operation_sub_s1 ? 
        ((r_large_mant_s1 >= r_small_mant_s1) ? r_large_sign_s1 : r_small_sign_s1) : 
        r_large_sign_s1;

    // Double denormal calculation removed - denorm treated as zero
    // Denorm signals removed

    //=========================================================================
    // Stage 1 Registers
    //=========================================================================
    reg [30:0] r_sum_mant_raw_s2;
    reg        r_result_sign_s2;
    reg [7:0]  r_max_exp_s2;
    reg        r_is_nan_s2;
    reg        r_is_inf_s2;
    reg        r_a_zero_s2;
    reg        r_b_zero_s2;
    // r_both_denorm_s2 removed
    reg [31:0] r_nan_result_s2;
    reg [31:0] r_inf_result_s2;
    reg [31:0] r_i_a_s2;
    reg [31:0] r_i_b_s2;
    // Denorm signals removed

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_sum_mant_raw_s2 <= 31'd0;
            r_result_sign_s2 <= 1'b0;
            r_max_exp_s2 <= 8'd0;
            r_is_nan_s2 <= 1'b0;
            r_is_inf_s2 <= 1'b0;
            r_a_zero_s2 <= 1'b0;
            r_b_zero_s2 <= 1'b0;
            // r_both_denorm_s2 removed
            r_nan_result_s2 <= 32'd0;
            r_inf_result_s2 <= 32'd0;
            r_i_a_s2 <= 32'd0;
            r_i_b_s2 <= 32'd0;
            // Denorm signals removed
        end else begin
            r_sum_mant_raw_s2 <= w_sum_mant_raw_s1;
            r_result_sign_s2 <= w_result_sign_s1;
            r_max_exp_s2 <= r_max_exp_s1;
            r_is_nan_s2 <= r_is_nan_s1;
            r_is_inf_s2 <= r_is_inf_s1;
            r_a_zero_s2 <= r_a_zero_s1;
            r_b_zero_s2 <= r_b_zero_s1;
            // r_both_denorm_s2 removed (denorm treated as zero in non-IEEE mode)
            r_nan_result_s2 <= r_nan_result_s1;
            r_inf_result_s2 <= r_inf_result_s1;
            r_i_a_s2 <= r_i_a_s1;
            r_i_b_s2 <= r_i_b_s1;
            // Denorm signals removed
        end
    end

    //=========================================================================
    // Stage 2: Normalization (Combinational Logic)
    //=========================================================================
    
    // Leading Zero Counter
    wire [4:0] w_lz_count_s2;
    leading_zero_counter_fp32 u_leading_zero_counter(
        .i_data_in      (r_sum_mant_raw_s2),
        .o_leading_zeros(w_lz_count_s2)
    );

    // Calculate leading_one and normalization
    wire [4:0] w_leading_one_s2 = (w_lz_count_s2 == 5'd31) ? 5'd0 : (5'd30 - w_lz_count_s2);
    wire [8:0] w_temp_exp_ext_s2 = {1'b0, r_max_exp_s2} + {1'b0, w_leading_one_s2} - 9'd29;
    wire w_temp_exp_pos_s2 = !w_temp_exp_ext_s2[8];
    wire w_temp_exp_ge1_s2 = w_temp_exp_pos_s2 && (w_temp_exp_ext_s2[7:0] >= 8'b1);
    wire w_exp_underflow_s2 = !w_temp_exp_pos_s2 || (w_temp_exp_ext_s2[7:0] == 8'b0);
    
    wire [8:0] w_temp_exp_signed_s2 = w_temp_exp_ext_s2;
    wire [4:0] w_denorm_shift_right_s2 = w_exp_underflow_s2 ? (2 - $signed(w_temp_exp_signed_s2)) : 5'd0;
    wire [4:0] w_shift_amount_left_s2 = 30 - w_leading_one_s2;
    wire [30:0] w_shifted_sum_temp_s2 = r_sum_mant_raw_s2 << w_shift_amount_left_s2;
    wire [30:0] w_shifted_sum_denorm_s2 = w_shifted_sum_temp_s2 >> w_denorm_shift_right_s2;
    wire [4:0] w_shift_amount_s2 = w_exp_underflow_s2 ? 5'd0 : (30 - w_leading_one_s2);
    wire [30:0] w_shifted_sum_s2 = w_exp_underflow_s2 ? w_shifted_sum_denorm_s2 : (r_sum_mant_raw_s2 << w_shift_amount_s2);
    
    wire [29:0] w_normalized_mant_s2 = w_shifted_sum_s2[29:0];
    wire [7:0]  w_normalized_exp_s2 = w_exp_underflow_s2 ? 8'b0 : w_temp_exp_ext_s2[7:0];
    wire [2:0]  w_round_bits_s2 = {w_normalized_mant_s2[6], w_normalized_mant_s2[5], |w_normalized_mant_s2[4:0]};

    //=========================================================================
    // Stage 2 Registers
    //=========================================================================
    reg [29:0] r_normalized_mant_s3;
    reg [7:0]  r_normalized_exp_s3;
    reg [2:0]  r_round_bits_s3;
    reg        r_exp_underflow_s3;
    reg        r_result_sign_s3;
    reg        r_is_nan_s3;
    reg        r_is_inf_s3;
    reg        r_a_zero_s3;
    reg        r_b_zero_s3;
    // r_both_denorm_s3 removed
    reg [31:0] r_nan_result_s3;
    reg [31:0] r_inf_result_s3;
    reg [31:0] r_i_a_s3;
    reg [31:0] r_i_b_s3;
    // Denorm-related signals removed since denorm treated as zero
    reg [30:0] r_sum_mant_raw_s3;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_normalized_mant_s3 <= 30'd0;
            r_normalized_exp_s3 <= 8'd0;
            r_round_bits_s3 <= 3'd0;
            r_exp_underflow_s3 <= 1'b0;
            r_result_sign_s3 <= 1'b0;
            r_is_nan_s3 <= 1'b0;
            r_is_inf_s3 <= 1'b0;
            r_a_zero_s3 <= 1'b0;
            r_b_zero_s3 <= 1'b0;
            // r_both_denorm_s3 removed
            r_nan_result_s3 <= 32'd0;
            r_inf_result_s3 <= 32'd0;
            r_i_a_s3 <= 32'd0;
            r_i_b_s3 <= 32'd0;
            // Denorm signals removed
            r_sum_mant_raw_s3 <= 31'd0;
        end else begin
            r_normalized_mant_s3 <= w_normalized_mant_s2;
            r_normalized_exp_s3 <= w_normalized_exp_s2;
            r_round_bits_s3 <= w_round_bits_s2;
            r_exp_underflow_s3 <= w_exp_underflow_s2;
            r_result_sign_s3 <= r_result_sign_s2;
            r_is_nan_s3 <= r_is_nan_s2;
            r_is_inf_s3 <= r_is_inf_s2;
            r_a_zero_s3 <= r_a_zero_s2;
            r_b_zero_s3 <= r_b_zero_s2;
            // r_both_denorm_s3 removed
            r_nan_result_s3 <= r_nan_result_s2;
            r_inf_result_s3 <= r_inf_result_s2;
            r_i_a_s3 <= r_i_a_s2;
            r_i_b_s3 <= r_i_b_s2;
            // Denorm signals removed
            r_sum_mant_raw_s3 <= r_sum_mant_raw_s2;
        end
    end

    //=========================================================================
    // Stage 3: Rounding + Output (Combinational Logic)
    //=========================================================================
    
    // Rounding Logic
    wire w_guard_s3 = r_round_bits_s3[2];
    wire w_round_bit_s3 = r_round_bits_s3[1];
    wire w_sticky_bit_s3 = r_round_bits_s3[0];
    wire w_lsb_s3 = r_exp_underflow_s3 ? r_normalized_mant_s3[5] : r_normalized_mant_s3[7];
    wire w_extended_sticky_s3 = w_sticky_bit_s3 || r_normalized_mant_s3[5];
    wire w_round_up_s3 = (w_guard_s3 && w_round_bit_s3) || 
                         (w_guard_s3 && w_extended_sticky_s3) || 
                         (w_guard_s3 && !w_round_bit_s3 && !w_extended_sticky_s3 && w_lsb_s3);
    
    wire [23:0] w_rounded_mant_s3 = r_exp_underflow_s3 ?
        {1'b0, r_normalized_mant_s3[28:6]} + (w_round_up_s3 ? 24'd1 : 24'd0) :
        {1'b0, r_normalized_mant_s3[29:7]} + (w_round_up_s3 ? 24'd1 : 24'd0);
    wire w_round_carry_s3 = w_rounded_mant_s3[23];

    // Overflow/Underflow Handling
    wire [7:0] w_final_exp_val_s3 = w_round_carry_s3 ? (r_normalized_exp_s3 + 8'd1) : r_normalized_exp_s3;
    wire [22:0] w_final_frac_s3 = (w_final_exp_val_s3 == 8'b0) ? 23'b0 : w_rounded_mant_s3[22:0];
    wire w_overflow_s3 = (w_final_exp_val_s3 >= 8'b11111111);
    wire w_underflow_s3 = (r_normalized_exp_s3 == 8'b0) && (w_rounded_mant_s3[22:0] != 23'b0);

    // Final Output Selection
    always @(*) begin
        case (1'b1)
            // 1. Highest priority: NaN scenario
            r_is_nan_s3: o_sum <= r_nan_result_s3;
            
            // 2. Second priority: Infinity/overflow scenario
            r_is_inf_s3 || w_overflow_s3: o_sum <= r_inf_result_s3;
            
            // 3. Single zero scenario
            r_a_zero_s3 && !r_b_zero_s3: o_sum <= r_i_b_s3;
            !r_a_zero_s3 && r_b_zero_s3: o_sum <= r_i_a_s3;
            
            // 4. Double zero scenario
            r_a_zero_s3 && r_b_zero_s3: o_sum <= {r_result_sign_s3, 31'b0};
            
            // 5. Double denormal scenario removed (denorm treated as zero)
            
            // 6. Operation result zero scenario
            r_sum_mant_raw_s3 == 31'd0: o_sum <= {r_result_sign_s3, 31'b0};
            
            // 7. Underflow scenario
            w_underflow_s3 || r_exp_underflow_s3: o_sum <= {r_result_sign_s3, 8'b0, 23'd0};
            
            // 8. Default scenario: normal normalized operation
            default: o_sum <= {r_result_sign_s3, w_final_exp_val_s3, w_final_frac_s3};
        endcase
    end
        end
    endgenerate


endmodule


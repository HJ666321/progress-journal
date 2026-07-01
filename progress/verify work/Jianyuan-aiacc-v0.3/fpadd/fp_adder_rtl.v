/*****************************************************************************
** Project  :  AIACC NPU                                                     **
******************************************************************************
**                                      **                                  **
** File name:  fp_adder_rtl.v           **             [Company]            **
** Designer :  [designer_name]           **  [Division]                      **
**                                      **                                  **
******************************************************************************
******************************************************************************
**                                                                          **
** Module Description:                                                      **
**                                                                          **
** Floating-point comparison modules for FP16 and FP32.                    **
** Implements combinational logic for comparing two floating-point numbers.**
** Returns 3-bit result: 001(a<b), 010(a==b), 100(a>b)                     **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
** Hierarchy:                                                               **
**                                                                          **
** fp_adder_rtl                                                             **
**   - cmp_fp16                                                             **
**   - cmp_fp32                                                             **
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
// Module: cmp_fp16
// Description: FP16 floating-point comparison module (combinational logic)
// Inputs:  a[15:0], b[15:0] - Two FP16 numbers to compare
// Outputs: result[2:0] - 3-bit comparison result: 001(a<b), 010(a==b), 100(a>b)
//=========================================================================

module fp_adder #(
    parameter PARAM_DR_FPADD_CNT = 4,  // Adder count: 32bit→4, 16bit→8
    parameter SMC_ID = 0,    // SMC ID for this module
    parameter IEEE_754 = 1    // IEEE 754 mode
)(
    // Clock and Reset
    input  wire        i_clk,
    input  wire        i_rst_n,
    
    // SMC Identification (5bit, AIACC architecture v0.2.7)
    input  wire [4:0]  i_smc_id,
    
    // Source Operands
    input  wire [127:0] i_dvr_fpadd_s0,  // Source operand 0
    input  wire [127:0] i_dvr_fpadd_s1,  // Source operand 1
    
    // Control Interface
    input  wire [4:0]  i_cru_fpadd,      // 5bit micro-instruction: [0]=inst_valid, [1]=src_prec, [2]=dest_prec, [3]=update_status, [4]=add_sub(0=add, 1=sub)
    input  wire [2:0]  i_rounding_mode,  // Rounding mode: 000=RNE, 001=RTZ, 010=RDN, 011=RUP, 100=RMM
    
    // Output Interface  
    output wire  [127:0] o_dr_fpadd_d,    // Addition/Subtraction result output
    output reg  [127:0] o_dr_fpadd_st,   // Status register output
    output wire  [4:0]  o_exception_flags [0:(2*PARAM_DR_FPADD_CNT)-1],  // Exception flags per lane: [0]=Invalid, [1]=DivZero, [2]=Overflow, [3]=Underflow, [4]=Inexact
    
    // CRU-FPADD Output (5bit register, AIACC architecture v0.2.7)
    output wire  [4:0]  o_cru_fpadd_o
);

    wire w_inst_valid  = i_cru_fpadd[0];
    wire w_src_prec    = i_cru_fpadd[1]; 
    wire w_dest_prec   = i_cru_fpadd[2];
    wire w_update_status = i_cru_fpadd[3];
    wire w_add_sub     = i_cru_fpadd[4];  // 0=addition, 1=subtraction
    wire w_same_flag   = (w_dest_prec == w_src_prec) ? 1'b1 : 1'b0;
    wire w_inst_trigger = w_inst_valid && w_same_flag;
    reg [4:0] valid_pipe;  // 5级流水线valid信号
    reg [4:0] w_src_prec_pipe;
    reg [4:0] w_dest_prec_pipe;
    reg [4:0] w_update_status_pipe;
    reg [4:0] w_add_sub_pipe;  // Pipeline add_sub signal
    reg [2:0] rounding_mode_pipe [0:3];  // Pipeline rounding mode (4 stages)
    integer j;  // Loop variable for status register update
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            valid_pipe <= 5'd0;
            w_src_prec_pipe <= 5'b0;
            w_dest_prec_pipe <= 5'b0;
            w_update_status_pipe <= 5'b0;
            w_add_sub_pipe <= 5'b0;
            rounding_mode_pipe[0] <= `RM_RNE;
            rounding_mode_pipe[1] <= `RM_RNE;
            rounding_mode_pipe[2] <= `RM_RNE;
            rounding_mode_pipe[3] <= `RM_RNE;
        end else begin
            valid_pipe <= {valid_pipe[3:0], w_inst_valid};
            w_src_prec_pipe <= {w_src_prec_pipe[3:0], w_src_prec};
            w_dest_prec_pipe <= {w_dest_prec_pipe[3:0], w_dest_prec};
            w_update_status_pipe <= {w_update_status_pipe[3:0], w_update_status};
            w_add_sub_pipe <= {w_add_sub_pipe[3:0], w_add_sub};
            rounding_mode_pipe[0] <= i_rounding_mode;
            rounding_mode_pipe[1] <= rounding_mode_pipe[0];
            rounding_mode_pipe[2] <= rounding_mode_pipe[1];
            rounding_mode_pipe[3] <= rounding_mode_pipe[2];
        end
    end
    //=========================================================================
    // Subword Splitting and Subtraction Handling
    //=========================================================================
    wire [15:0] w_src0_16 [0:(2*PARAM_DR_FPADD_CNT)-1];
    wire [15:0] w_src1_16 [0:(2*PARAM_DR_FPADD_CNT)-1];
    wire [15:0] w_src1_16_processed [0:(2*PARAM_DR_FPADD_CNT)-1];  // Processed src1 for subtraction
    wire [31:0] w_src0_32 [0:PARAM_DR_FPADD_CNT-1];
    wire [31:0] w_src1_32 [0:PARAM_DR_FPADD_CNT-1];
    wire [31:0] w_src1_32_processed [0:PARAM_DR_FPADD_CNT-1];  // Processed src1 for subtraction

    //=========================================================================
    // Addition Results
    //=========================================================================
    wire [15:0] w_fp16_sum [0:(2*PARAM_DR_FPADD_CNT)-1];
    wire [31:0] w_fp32_sum [0:PARAM_DR_FPADD_CNT-1];
    wire [2:0] w_cmp_fp16_result [0:(2*PARAM_DR_FPADD_CNT)-1];
    wire [2:0] w_cmp_fp32_result [0:PARAM_DR_FPADD_CNT-1];
    wire [4:0] w_exception_flags_fp16 [0:(2*PARAM_DR_FPADD_CNT)-1];
    wire [4:0] w_exception_flags_fp32 [0:PARAM_DR_FPADD_CNT-1];
    

    genvar i;  
    generate
        // 16-bit Splitting
        for (i = 0; i < (2*PARAM_DR_FPADD_CNT); i = i + 1) begin : split_16
            assign w_src0_16[i] = i_dvr_fpadd_s0[16*i +: 16];
            assign w_src1_16[i] = i_dvr_fpadd_s1[16*i +: 16];
            // For subtraction: flip sign bit of src1 (bit[15])
            // This converts a - b to a + (-b), and the underlying adder handles sign comparison
            assign w_src1_16_processed[i] = w_add_sub ? {~w_src1_16[i][15], w_src1_16[i][14:0]} : w_src1_16[i];
        end

        // 32-bit Splitting  
        for (i = 0; i < PARAM_DR_FPADD_CNT; i = i + 1) begin : split_32
            assign w_src0_32[i] = i_dvr_fpadd_s0[32*i +: 32];
            assign w_src1_32[i] = i_dvr_fpadd_s1[32*i +: 32];
            // For subtraction: flip sign bit of src1 (bit[31])
            // This converts a - b to a + (-b), and the underlying adder handles sign comparison
            assign w_src1_32_processed[i] = w_add_sub ? {~w_src1_32[i][31], w_src1_32[i][30:0]} : w_src1_32[i];
        end

        // FP32 Adder Instances
        for (i = 0; i < PARAM_DR_FPADD_CNT; i = i + 1) begin : gen_fp32
            fp32_adder_pipeline # (.IEEE_754(IEEE_754)) u_fp32 (
                .i_clk (i_clk),
                .i_rst_n (i_rst_n),
                .i_valid (w_inst_trigger),
                .i_rounding_mode(i_rounding_mode),  // Pass rounding mode
                .i_a   (w_src0_32[i]),
                .i_b   (w_src1_32_processed[i]),  // Use processed src1 (sign flipped for subtraction)
                .o_sum (w_fp32_sum[i]),
                .o_exception_flags(w_exception_flags_fp32[i])
            );

            cmp_fp32 u_fp32_comparator (
                .a (w_src0_32[i]),
                .b (w_src1_32[i]),
                .cmp_fp32_result (w_cmp_fp32_result[i])
            );
        end

        // FP16 Adder Instances
        for (i = 0; i < (2*PARAM_DR_FPADD_CNT); i = i + 1) begin : gen_fp16
            fp16_adder_pipeline u_fp16 (
                .i_clk (i_clk),
                .i_rst_n (i_rst_n),
                .i_valid (w_inst_trigger),
                .i_rounding_mode(i_rounding_mode),  // Pass rounding mode
                .i_a   (w_src0_16[i]),
                .i_b   (w_src1_16_processed[i]),  // Use processed src1 (sign flipped for subtraction)
                .o_sum (w_fp16_sum[i]),
                .o_exception_flags(w_exception_flags_fp16[i])
            );
            
            fp16_comparator u_fp16_comparator (
                .a (w_src0_16[i]),
                .b (w_src1_16[i]),
                .cmp_fp16_result (w_cmp_fp16_result[i])
            );
        end
    endgenerate
    
    reg [127:0] o_result;
    reg [23:0] w_cmp_fp16_result_reg;
    reg [11:0] w_cmp_fp32_result_reg;
    reg [23:0] w_cmp_fp16_result_reg_r1;
    reg [11:0] w_cmp_fp32_result_reg_r1;
    reg [23:0] w_cmp_fp16_result_reg_r2;
    reg [11:0] w_cmp_fp32_result_reg_r2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            w_cmp_fp16_result_reg <= 128'b0;
            w_cmp_fp32_result_reg <= 128'b0;
        end else if (w_inst_trigger) begin
            w_cmp_fp16_result_reg <= {w_cmp_fp16_result[7],w_cmp_fp16_result[6],w_cmp_fp16_result[5],w_cmp_fp16_result[4],w_cmp_fp16_result[3],w_cmp_fp16_result[2],w_cmp_fp16_result[1],w_cmp_fp16_result[0]};
            w_cmp_fp32_result_reg <= {w_cmp_fp32_result[3],w_cmp_fp32_result[2],w_cmp_fp32_result[1],w_cmp_fp32_result[0]};
        end
    end
    
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_dr_fpadd_st <= 128'b0;
        end 
        else if (valid_pipe[2] && w_update_status_pipe[2]) begin
            if (~w_dest_prec_pipe[2]) begin
                for (j = 0; j < 8; j = j + 1) begin
                    o_dr_fpadd_st[16*j +: 3] <= w_cmp_fp16_result_reg_r2[3*j +: 3];
                end
            end else begin
                for (j = 0; j < 4; j = j + 1) begin
                    o_dr_fpadd_st[32*j +: 3] <= w_cmp_fp32_result_reg_r2[3*j +: 3];
                end
            end
        end
        else begin
            o_dr_fpadd_st <= o_dr_fpadd_st;
        end
    end

    always @(posedge i_clk or negedge i_rst_n)           
        begin                                        
            if(!i_rst_n) begin                          
                w_cmp_fp16_result_reg_r1 <= 24'b0;
                w_cmp_fp32_result_reg_r1 <= 12'b0; 
                w_cmp_fp16_result_reg_r2 <= 24'b0;
                w_cmp_fp32_result_reg_r2 <= 12'b0;
            end
            else begin
                w_cmp_fp16_result_reg_r1 <= w_cmp_fp16_result_reg;
                w_cmp_fp32_result_reg_r1 <= w_cmp_fp32_result_reg;
                w_cmp_fp16_result_reg_r2 <= w_cmp_fp16_result_reg_r1;
                w_cmp_fp32_result_reg_r2 <= w_cmp_fp32_result_reg_r1;
            end
        end                                          

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_result <= 128'd0;
        end 
        else if (valid_pipe[2]) begin
            if (w_dest_prec_pipe[2] ^ w_src_prec_pipe[2]) begin
                o_result <= 128'd0;
            end
            else if (w_dest_prec_pipe[2]) begin
                o_result <= {
                    w_fp32_sum[3],  // 127:96 bits (4th 32-bit subword)
                    w_fp32_sum[2],  // 95:64 bits (3rd 32-bit subword)  
                    w_fp32_sum[1],  // 63:32 bits (2nd 32-bit subword)
                    w_fp32_sum[0]   // 31:0 bits (1st 32-bit subword)
                };
            end
            else if (~w_dest_prec_pipe[2]) begin
                o_result <= {
                    w_fp16_sum[7], w_fp16_sum[6], w_fp16_sum[5], w_fp16_sum[4],
                    w_fp16_sum[3], w_fp16_sum[2], w_fp16_sum[1], w_fp16_sum[0]
                };
            end
        end
        else begin
            o_result <= o_result;
        end
    end

    assign o_dr_fpadd_d = o_result;
    assign o_cru_fpadd_o = {w_add_sub_pipe[3], valid_pipe[3], w_dest_prec_pipe[3], w_src_prec_pipe[3], w_update_status_pipe[3]};
    
    // Exception flags selection based on precision
    genvar k;
    generate
        for (k = 0; k < (2*PARAM_DR_FPADD_CNT); k = k + 1) begin : gen_exception_flags
            assign o_exception_flags[k] = 
                (w_dest_prec_pipe[3] && w_src_prec_pipe[3]) ? 
                    (k < PARAM_DR_FPADD_CNT ? w_exception_flags_fp32[k] : 5'b0) :  // FP32 mode: use FP32 flags for first 4 lanes
                    (~w_dest_prec_pipe[3] && ~w_src_prec_pipe[3]) ? 
                        w_exception_flags_fp16[k] :  // FP16 mode: use FP16 flags for all 8 lanes
                        5'b0;  // Unknown state
        end
    endgenerate
endmodule

module fp16_comparator (
    // Inputs
    input  [15:0] a,
    input  [15:0] b,
    // Outputs
    output [2:0]  cmp_fp16_result
);

    // Internal signals
    wire        a_s, b_s;
    wire [4:0]  a_e, b_e;
    wire [9:0]  a_f, b_f;
    wire        a_is_zero, b_is_zero;
    wire        a_is_inf, b_is_inf;
    wire        a_is_nan, b_is_nan;
    
    // Extract sign, exponent, and fraction
    assign a_s = a[15];
    assign a_e = a[14:10];
    assign a_f = a[9:0];
    
    assign b_s = b[15];
    assign b_e = b[14:10];
    assign b_f = b[9:0];
    
    // Check for zero (+0 or -0)
    assign a_is_zero = (a == 16'h0000) || (a == 16'h8000);
    assign b_is_zero = (b == 16'h0000) || (b == 16'h8000);
    // Check for Inf (exp=0x1F, frac=0)
    assign a_is_inf = (a_e == 5'b11111) && (a_f == 10'b0000000000);
    assign b_is_inf = (b_e == 5'b11111) && (b_f == 10'b0000000000);
    // Check for NaN (exp=0x1F, frac!=0)
    assign a_is_nan = (a_e == 5'b11111) && (a_f != 10'b0000000000);
    assign b_is_nan = (b_e == 5'b11111) && (b_f != 10'b0000000000);
    
    // ====================================================================
    // Parallel comparison logic - all comparisons computed in parallel
    // ====================================================================
    
    // Priority flags (computed in parallel)
    wire has_nan = a_is_nan || b_is_nan;
    wire both_zero = a_is_zero && b_is_zero;  // FP16 rule: both zero -> >/< false, == only when same sign
    wire has_inf = a_is_inf || b_is_inf;
    wire both_inf = a_is_inf && b_is_inf;
    wire diff_sign = (a_s != b_s);
    wire exp_equal = (a_e == b_e);
    wire exp_a_gt_b = (a_e > b_e);
    wire frac_equal = (a_f == b_f);
    wire frac_a_gt_b = (a_f > b_f);
    
    // Parallel computation of comparison results for each priority level
    // Level 1: NaN result (highest priority) - rule: A<B true, A>B false, A==B bit equal
    wire result_nan_eq = (a == b);
    wire result_nan_gt = 1'b0;
    wire result_nan_lt = 1'b1;
    
    // Level 2: Both zero - rule: A>B false, A<B false, A==B true only when same sign
    wire result_bothzero_eq = (a_s == b_s);
    wire result_bothzero_gt = 1'b0;
    wire result_bothzero_lt = 1'b0;
    
    // Level 3: Inf result
    wire result_inf_eq = both_inf && (a_s == b_s);
    wire result_inf_gt = (a_is_inf && !b_is_inf && !a_s) ||  // a is +Inf
                         (b_is_inf && !a_is_inf && b_s) ||   // b is -Inf
                         (both_inf && (a_s == 1'b0) && (b_s == 1'b1));  // +Inf > -Inf
    wire result_inf_lt = (a_is_inf && !b_is_inf && a_s) ||   // a is -Inf
                         (b_is_inf && !a_is_inf && !b_s) ||  // b is +Inf
                         (both_inf && (a_s == 1'b1) && (b_s == 1'b0));  // -Inf < +Inf
    
    // Level 4: Different sign result
    wire result_sign_eq = 1'b0;
    wire result_sign_gt = !a_s;  // positive > negative
    wire result_sign_lt = a_s;   // negative < positive
    
    // Level 5: Exponent comparison result (same sign)
    wire result_exp_eq = 1'b0;
    wire result_exp_gt = exp_a_gt_b ? (!a_s) : a_s;  // positive: larger exp > smaller; negative: larger exp < smaller
    wire result_exp_lt = exp_a_gt_b ? a_s : (!a_s);
    
    // Level 6: Fraction comparison result (same sign and exponent)
    wire result_frac_eq = frac_equal;
    wire result_frac_gt = frac_a_gt_b ? (!a_s) : a_s;  // positive: larger frac > smaller; negative: larger frac < smaller
    wire result_frac_lt = frac_a_gt_b ? a_s : (!a_s);
    
    // Priority encoder: NaN > BothZero > Inf > Sign > Exp > Frac (per fp_compare_rules FP16)
    wire a_eq_b = has_nan ? result_nan_eq :
                  both_zero ? result_bothzero_eq :
                  has_inf ? result_inf_eq :
                  diff_sign ? result_sign_eq :
                  !exp_equal ? result_exp_eq :
                  result_frac_eq;
    
    wire a_gt_b = has_nan ? result_nan_gt :
                  both_zero ? result_bothzero_gt :
                  has_inf ? result_inf_gt :
                  diff_sign ? result_sign_gt :
                  !exp_equal ? result_exp_gt :
                  result_frac_gt;
    
    wire a_lt_b = has_nan ? result_nan_lt :
                  both_zero ? result_bothzero_lt :
                  has_inf ? result_inf_lt :
                  diff_sign ? result_sign_lt :
                  !exp_equal ? result_exp_lt :
                  result_frac_lt;
    
    // Output encoding: 001(a<b), 010(a==b), 100(a>b)
    assign cmp_fp16_result = a_lt_b ? 3'b001 : (a_eq_b ? 3'b010 : 3'b100);

endmodule

//=========================================================================
// Module: cmp_fp32
// Description: FP32 floating-point comparison module (combinational logic)
// Inputs:  a[31:0], b[31:0] - Two FP32 numbers to compare
// Outputs: result[2:0] - 3-bit comparison result: 001(a<b), 010(a==b), 100(a>b)
//=========================================================================
module cmp_fp32 (
    // Inputs
    input  [31:0] a,
    input  [31:0] b,
    // Outputs
    output [2:0]  cmp_fp32_result
);

    // Internal signals
    wire        a_s, b_s;
    wire [7:0]  a_e, b_e;
    wire [22:0] a_f, b_f;
    wire        a_is_zero, b_is_zero;
    wire        a_is_inf, b_is_inf;
    wire        a_is_nan, b_is_nan;
    
    // Extract sign, exponent, and fraction
    assign a_s = a[31];
    assign a_e = a[30:23];
    assign a_f = a[22:0];
    
    assign b_s = b[31];
    assign b_e = b[30:23];
    assign b_f = b[22:0];
    
    // Check for zero (+0 or -0)
    assign a_is_zero = (a == 32'h00000000) || (a == 32'h80000000);
    assign b_is_zero = (b == 32'h00000000) || (b == 32'h80000000);
    // Check for Inf (exp=0xFF, frac=0)
    assign a_is_inf = (a_e == 8'hFF) && (a_f == 23'b00000000000000000000000);
    assign b_is_inf = (b_e == 8'hFF) && (b_f == 23'b00000000000000000000000);
    // Check for NaN (exp=0xFF, frac!=0)
    assign a_is_nan = (a_e == 8'hFF) && (a_f != 23'b00000000000000000000000);
    assign b_is_nan = (b_e == 8'hFF) && (b_f != 23'b00000000000000000000000);
    // FP32/BF16: denorm = exp 0, frac != 0; rule: treat as 0, A>B/A<B false, A==B bit equal
    wire a_is_denorm = (a_e == 8'h00) && (a_f != 23'b00000000000000000000000);
    wire b_is_denorm = (b_e == 8'h00) && (b_f != 23'b00000000000000000000000);
    
    // ====================================================================
    // Parallel comparison logic - all comparisons computed in parallel
    // ====================================================================
    
    // Priority flags (computed in parallel)
    wire has_nan = a_is_nan || b_is_nan;
    wire both_zero = a_is_zero && b_is_zero;  // FP32 rule: both zero -> >/< false, == only when same sign
    wire has_denorm = a_is_denorm || b_is_denorm;  // FP32 rule: denorm treated as 0, >/< false, == bit equal
    wire has_inf = a_is_inf || b_is_inf;
    wire both_inf = a_is_inf && b_is_inf;
    wire diff_sign = (a_s != b_s);
    wire exp_equal = (a_e == b_e);
    wire exp_a_gt_b = (a_e > b_e);
    wire frac_equal = (a_f == b_f);
    wire frac_a_gt_b = (a_f > b_f);
    
    // Parallel computation of comparison results for each priority level
    // Level 1: NaN result (highest priority) - rule: A<B true, A>B false, A==B bit equal
    wire result_nan_eq = (a == b);
    wire result_nan_gt = 1'b0;
    wire result_nan_lt = 1'b1;
    
    // Level 2: Both zero - rule: A>B false, A<B false, A==B true only when same sign
    wire result_bothzero_eq = (a_s == b_s);
    wire result_bothzero_gt = 1'b0;
    wire result_bothzero_lt = 1'b0;
    
    // Level 3: Denorm (FP32 only) - rule: treat as 0, A>B false, A<B false, A==B bit equal
    wire result_denorm_eq = (a == b);
    wire result_denorm_gt = 1'b0;
    wire result_denorm_lt = 1'b0;
    
    // Level 4: Inf result
    wire result_inf_eq = both_inf && (a_s == b_s);
    wire result_inf_gt = (a_is_inf && !b_is_inf && !a_s) ||  // a is +Inf
                         (b_is_inf && !a_is_inf && b_s) ||   // b is -Inf
                         (both_inf && (a_s == 1'b0) && (b_s == 1'b1));  // +Inf > -Inf
    wire result_inf_lt = (a_is_inf && !b_is_inf && a_s) ||   // a is -Inf
                         (b_is_inf && !a_is_inf && !b_s) ||  // b is +Inf
                         (both_inf && (a_s == 1'b1) && (b_s == 1'b0));  // -Inf < +Inf
    
    // Level 5: Different sign result
    wire result_sign_eq = 1'b0;
    wire result_sign_gt = !a_s;  // positive > negative
    wire result_sign_lt = a_s;   // negative < positive
    
    // Level 6: Exponent comparison result (same sign)
    wire result_exp_eq = 1'b0;
    wire result_exp_gt = exp_a_gt_b ? (!a_s) : a_s;  // positive: larger exp > smaller; negative: larger exp < smaller
    wire result_exp_lt = exp_a_gt_b ? a_s : (!a_s);
    
    // Level 7: Fraction comparison result (same sign and exponent)
    wire result_frac_eq = frac_equal;
    wire result_frac_gt = frac_a_gt_b ? (!a_s) : a_s;  // positive: larger frac > smaller; negative: larger frac < smaller
    wire result_frac_lt = frac_a_gt_b ? a_s : (!a_s);
    
    // Priority encoder: NaN > BothZero > Denorm > Inf > Sign > Exp > Frac (per fp_compare_rules FP32/BF16)
    wire a_eq_b = has_nan ? result_nan_eq :
                  both_zero ? result_bothzero_eq :
                  has_denorm ? result_denorm_eq :
                  has_inf ? result_inf_eq :
                  diff_sign ? result_sign_eq :
                  !exp_equal ? result_exp_eq :
                  result_frac_eq;
    
    wire a_gt_b = has_nan ? result_nan_gt :
                  both_zero ? result_bothzero_gt :
                  has_denorm ? result_denorm_gt :
                  has_inf ? result_inf_gt :
                  diff_sign ? result_sign_gt :
                  !exp_equal ? result_exp_gt :
                  result_frac_gt;
    
    wire a_lt_b = has_nan ? result_nan_lt :
                  both_zero ? result_bothzero_lt :
                  has_denorm ? result_denorm_lt :
                  has_inf ? result_inf_lt :
                  diff_sign ? result_sign_lt :
                  !exp_equal ? result_exp_lt :
                  result_frac_lt;
    
    // Output encoding: 001(a<b), 010(a==b), 100(a>b)
    assign cmp_fp32_result = a_lt_b ? 3'b001 : (a_eq_b ? 3'b010 : 3'b100);

endmodule


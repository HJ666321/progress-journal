/*****************************************************************************
** Project  :  AIACC NPU                                                     **
******************************************************************************
**                                      **                                  **
** File name:  SMC.sv                     **             AIACC Team          **
** Designer :  AIACC RTL Generator      **  NPU Design Division            **
**                                      **                                  **
******************************************************************************
******************************************************************************
**                                                                          **
** Module Description:                                                      **
**                                                                          **
** SMC (Stream Multiprocessor Compute Unit) Top Module                    **
**                                                                          **
** This module integrates all compute units in the SMC:                    **
**   - fp16mul: FP16 multiplication unit                                  **
**   - fp32addtree5to1: FP32 5-to-1 adder tree                            **
**   - fp32addtree8to1: FP32 8-to-1 adder tree                            **
**   - fpadd: Floating-point addition/subtraction                          **
**   - fpmul: Floating-point multiplication                                **
**   - fpto_int: Floating-point to integer conversion                     **
**   - fptofp: Floating-point to floating-point conversion                **
**   - int_to_int: Integer to integer conversion                          **
**   - inttofp: Integer to floating-point conversion                      **
**   - logical: Logical operations                                        **
**   - shift_up: Shift up operation                                       **
**   - shift_down: Shift down operation                                   **
**   - user_register: User register module (UR)                            **
**   - IPR: Input Pipeline Register (VIN0, VIN1)                         **
**   - OPR: Output Pipeline Register (VOUT0)                             **
**   - RtoVR: Register to Vector Register routing module                  **
**                                                                          **
** All modules are connected through the RtoVR crossbar switch.           **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
** Hierarchy:                                                               **
**                                                                          **
** SMC (top)                                                                **
**   |-- RtoVR (routing crossbar)                                          **
**   |-- fp16mul                                                            **
**   |-- fp32addtree5to1                                                   **
**   |-- fp32addtree8to1                                                   **
**   |-- fpadd                                                              **
**   |-- fpmul                                                              **
**   |-- fpto_int                                                           **
**   |-- fptofp                                                             **
**   |-- int_to_int                                                         **
**   |-- inttofp                                                            **
**   |-- logical                                                            **
**   |-- shift_up                                                           **
**   |-- shift_down                                                         **
**   |-- user_register                                                      **
**   |-- IPR (VIN0)                                                        **
**   |-- IPR (VIN1)                                                        **
**   |-- OPR (VOUT0)                                                       **
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
** and proprietary information of AIACC and is protected                    **
*****************************************************************************/
// $Revision: 1.0 $

`timescale 1ns/1ps

module SMC #(
    /*************************************************** PARAMETER DECLARATIONS ***************************************************/
    parameter SMC_ID = 0,                // SMC ID for this module
    parameter IEEE_754 = 0                // IEEE 754 mode
) (
    /*AUTOARG*/
    
    /******************************************************** INPUTS **************************************************************/
    // Global Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // SMC Identification
    input  wire [4:0]  i_smc_id,
    
    // Rounding Mode Control
    input  wire [2:0]  i_rounding_mode,  // 000=RNE, 001=RTZ, 010=RDN, 011=RUP, 100=RMM
    
    // CRU (Command Register Upstream) - Control signals for each unit
    input  wire [12:0]  cru_intadd,               // INTADD control (13-bit: bit 12 is sub_en)
    input  wire [2:0]   cru_fp16mul,              // FP16 multiplication control
    input  wire [1:0]   cru_fp16mul_s0123,        // FP16mul S0-S3 control
    input  wire [3:0]   cru_fp16mul_s4567,        // FP16mul S4-S7 control
    input  wire         cru_fp32addtree5to1,      // FP32 5-to-1 adder tree control
    input  wire [2:0]   cru_fp32addtree8to1,      // FP32 8-to-1 adder tree control
    input  wire [4:0]   cru_fpadd,                // FP addition/subtraction control (5bit: valid,src_prec,dest_prec,update_status,add_sub)
    input  wire [2:0]   cru_fpmul,                // FP multiplication control
    input  wire [4:0]   cru_fptoint,               // FP to INT control
    input  wire [4:0]   cru_fptofp,               // FP to FP control
    input  wire [6:0]   cru_inttoint,             // INT to INT control
    input  wire [5:0]   cru_inttofp,              // INT to FP control
    input  wire [5:0]   cru_logic,                // Logical operations control
    input  wire [1:0]   cru_int8tofp16,           // INT8toFP16 control
    input  wire [134:0] cru_shiftup,              // Shift up control
    input  wire [133:0] crd_shiftdn,             // Shift down control (downstream)
    input  wire [279:0] cru_rtovr,                // RtoVR routing control (40 outputs × 7 bits = 280 bits)
    input  wire [160:0] cru_ur,                   // User register control (161-bit)
    input  wire         cru_vin0,                 // VIN0 control
    input  wire         cru_vin1,                 // VIN1 control
    input  wire         cru_vout0,                // VOUT0 control
    
    /******************************************************** OUTPUTS *************************************************************/
    // Control Outputs
    output wire [133:0] crd_shiftdn_out,          // SHIFTDN downstream control output
    
    // CRU Outputs (Command Register Upstream Output)
    // Only modules that actually modify or pass through CRU signals have outputs
    output wire [4:0]   cru_fpadd_o,              // FPADD CRU output (5bit, from fp_adder module)
    output wire [2:0]   cru_fpmul_o,              // FPMUL CRU output (from fpmul module)
    output wire [6:0]   cru_inttoint_o,           // INTtoINT CRU output (from int_to_int_array module)
    output wire [5:0]   cru_inttofp_o,            // INTtoFP CRU output (from inttofp module)
    output wire [5:0]   cru_logic_o,             // LOGICAL CRU output (from logical module)
    output wire [12:0]  cru_intadd_o,             // INTADD CRU output (from intadd module, 13-bit)
    output wire [134:0] cru_shiftup_o,            // SHIFTUP CRU output (from shift_up module)
    output wire [279:0] cru_rtovr_o,              // RtoVR CRU output (from RtoVR module, 40 outputs × 7 bits = 280 bits)
    output wire [160:0] cru_ur_o,                 // User register CRU output (from user_register module)
    output wire         cru_vin0_o,               // VIN0 CRU output (from IPR module)
    output wire         cru_vin1_o,               // VIN1 CRU output (from IPR module)
    output wire         cru_vout0_o               // VOUT0 CRU output (from OPR module)
);

/*************************************************** WIRE DECLARATIONS ********************************************************/
// Internal wires for connecting modules to RtoVR
// RtoVR inputs (64 inputs from DR outputs)
wire [127:0] dr_fpmul_d_w;
wire [127:0] dr_fpadd_d_w;
wire [127:0] dr_fpadd_st_w;
wire [127:0] dr_fptofp_d_w;
wire [127:0] dr_inttoint_d_w;
wire [127:0] dr_fptoint_d_w;
wire [127:0] dr_inttofp_d_w;
wire [127:0] dr_logic_d_w;
wire [127:0] dr_shiftup_d_w;
wire [127:0] dr_fp16mul_d0_w;
wire [127:0] dr_fp16mul_d1_w;
wire [127:0] dr_fp16mul_d2_w;
wire [127:0] dr_fp16mul_d3_w;
wire [127:0] dr_fp16mul_d4_w;
wire [127:0] dr_fp16mul_d5_w;
wire [127:0] dr_fp16mul_d6_w;
wire [127:0] dr_fp16mul_d7_w;
wire [127:0] dr_fp32addtree5to1_d0_w;
wire [127:0] dr_fp32addtree5to1_d1_w;
wire [127:0] dr_fp32addtree8to1_d_w;

// RtoVR outputs (40 outputs to DVR inputs)
wire [127:0] dvr_intadd_s0_w;
wire [127:0] dvr_intadd_s1_w;
wire [127:0] dvr_intadd_s2_w;
wire [127:0] dvr_fpmul_s0_w;
wire [127:0] dvr_fpmul_s1_w;
wire [127:0] dvr_fpadd_s0_w;
wire [127:0] dvr_fpadd_s1_w;
wire [127:0] dvr_fptofp_s_w;
wire [127:0] dvr_inttoint_s_w;
wire [127:0] dvr_fptoint_s_w;
wire [127:0] dvr_inttofp_s_w;
wire [127:0] dvr_logic_s0_w;
wire [127:0] dvr_logic_s1_w;
wire [127:0] dvr_logic_st_w;
wire [127:0] dvr_int8tofp16_s0_w;
wire [127:0] dvr_int8tofp16_s1_w;
wire [127:0] dvr_fp16mul_s0_w;
wire [127:0] dvr_fp16mul_s1_w;
wire [127:0] dvr_fp16mul_s2_w;
wire [127:0] dvr_fp16mul_s3_w;
wire [127:0] dvr_fp16mul_s4567_w;
wire [127:0] dvr_fp32addtree5to1_s0_w;
wire [127:0] dvr_fp32addtree5to1_s1_w;
wire [127:0] dvr_fp32addtree5to1_s2_w;
wire [127:0] dvr_fp32addtree5to1_s3_w;
wire [127:0] dvr_fp32addtree5to1_s4_w;
wire [127:0] dvr_fp32addtree5to1_s5_w;
wire [127:0] dvr_fp32addtree5to1_s6_w;
wire [127:0] dvr_fp32addtree5to1_s7_w;
wire [127:0] dvr_fp32addtree8to1_s0_w;
wire [127:0] dvr_fp32addtree8to1_s1_w;
wire [127:0] dvr_vin0_s_w;          // Reserved (Output 14)
wire [127:0] dvr_vin1_s_w;          // Reserved (Output 15)
wire [127:0] dvr_vout0_s_w;         // Reserved (Output 16)
wire [127:0] dvr_shiftdn_s_w;
wire [127:0] uvr_wdata_0_w;
wire [127:0] uvr_wdata_1_w;
wire [127:0] uvr_wdata_2_w;
wire [127:0] uvr_wdata_3_w;
wire [127:0] reserved_out_39_w;     // Reserved (Output 39)

// IPR/OPR module outputs (connected to RtoVR inputs)
wire [127:0] dr_vin0_d_w;      // From IPR (VIN0)
wire [127:0] dr_vin1_d_w;      // From IPR (VIN1)
wire [127:0] dr_vout0_d_w;     // From OPR (VOUT0)

// Exception flags (optional, for monitoring)
wire [4:0] exception_flags_fp16mul [31:0];
wire [7:0] [4:0] exception_flags_fp32addtree5to1;
wire [4:0] exception_flags_fpadd [0:7];  // fp_adder: PARAM_DR_FPADD_CNT=4, so 2*4-1=7
wire [4:0] exception_flags_fpmul [3:0];  // fpmul: 4 lanes

// Internal wires for intadd and int8tofp16 modules
wire [127:0] dr_intadd_d0_internal;
wire [127:0] dr_intadd_d1_internal;
wire [127:0] dr_intadd_st_internal;
wire [127:0] dr_int8tofp16_d0_internal;
wire [127:0] dr_int8tofp16_d1_internal;
wire [127:0] dr_int8tofp16_d2_internal;
wire [127:0] dr_int8tofp16_d3_internal;

// Internal wires for user_register module
wire [127:0] ur_rdata_0_w;
wire [127:0] ur_rdata_1_w;
wire [127:0] ur_rdata_2_w;
wire [127:0] ur_rdata_3_w;

/*************************************************** MODULE INSTANTIATIONS ****************************************************/

// ========================================================================
// RtoVR: Register to Vector Register Routing Crossbar
// ========================================================================


RtoVR #(
    .SMC_ID(SMC_ID)
) u_rtovr (
    // Clock and Reset
    .clk                (clk),
    .rst_n              (rst_n),
    .rtovr_smc_id       (i_smc_id),
    
    // CRU
    .cru_rtovr          (cru_rtovr),
    .cru_rtovr_o        (cru_rtovr_o),
    
    // 64 Inputs (from DR outputs)
    .dr_intadd_d0       (dr_intadd_d0_internal),
    .dr_intadd_d1       (dr_intadd_d1_internal),
    .dr_intadd_st       (dr_intadd_st_internal),
    .dr_fpmul_d         (dr_fpmul_d_w),
    .dr_fpadd_d         (dr_fpadd_d_w),
    .dr_fpadd_st        (dr_fpadd_st_w),
    .dr_fptofp_d        (dr_fptofp_d_w),
    .dr_inttoint_d      (dr_inttoint_d_w),
    .dr_fptoint_d       (dr_fptoint_d_w),
    .dr_inttofp_d       (dr_inttofp_d_w),
    .dr_logic_d         (dr_logic_d_w),
    .dr_vin0_d          (dr_vin0_d_w),
    .dr_vin1_d          (dr_vin1_d_w),
    .dr_vout0_d         (dr_vout0_d_w),
    .dr_int8tofp16_d0   (dr_int8tofp16_d0_internal),
    .dr_int8tofp16_d1   (dr_int8tofp16_d1_internal),
    .dr_int8tofp16_d2   (dr_int8tofp16_d2_internal),
    .dr_int8tofp16_d3   (dr_int8tofp16_d3_internal),
    .dr_fp16mul_d0      (dr_fp16mul_d0_w),
    .dr_fp16mul_d1      (dr_fp16mul_d1_w),
    .dr_fp16mul_d2      (dr_fp16mul_d2_w),
    .dr_fp16mul_d3      (dr_fp16mul_d3_w),
    .dr_fp16mul_d4      (dr_fp16mul_d4_w),
    .dr_fp16mul_d5      (dr_fp16mul_d5_w),
    .dr_fp16mul_d6      (dr_fp16mul_d6_w),
    .dr_fp16mul_d7      (dr_fp16mul_d7_w),
    .dr_fp32addtree5to1_d0 (dr_fp32addtree5to1_d0_w),
    .dr_fp32addtree5to1_d1 (dr_fp32addtree5to1_d1_w),
    .dr_fp32addtree8to1_d (dr_fp32addtree8to1_d_w),
    .dr_shiftup_d       (dr_shiftup_d_w),
    .ur_rdata_0         (ur_rdata_0_w),
    .ur_rdata_1         (ur_rdata_1_w),
    .ur_rdata_2         (ur_rdata_2_w),
    .ur_rdata_3         (ur_rdata_3_w),
    
    // 40 Outputs (to DVR inputs)
    .dvr_intadd_s0      (dvr_intadd_s0_w),
    .dvr_intadd_s1      (dvr_intadd_s1_w),
    .dvr_intadd_s2      (dvr_intadd_s2_w),
    .dvr_fpmul_s0       (dvr_fpmul_s0_w),
    .dvr_fpmul_s1       (dvr_fpmul_s1_w),
    .dvr_fpadd_s0       (dvr_fpadd_s0_w),
    .dvr_fpadd_s1       (dvr_fpadd_s1_w),
    .dvr_fptofp_s       (dvr_fptofp_s_w),
    .dvr_inttoint_s     (dvr_inttoint_s_w),
    .dvr_fptoint_s      (dvr_fptoint_s_w),
    .dvr_inttofp_s      (dvr_inttofp_s_w),
    .dvr_logic_s0       (dvr_logic_s0_w),
    .dvr_logic_s1       (dvr_logic_s1_w),
    .dvr_logic_st        (dvr_logic_st_w),
    .dvr_vin0_s          (dvr_vin0_s_w),          // Reserved (Output 14)
    .dvr_vin1_s          (dvr_vin1_s_w),          // Reserved (Output 15)
    .dvr_vout0_s         (dvr_vout0_s_w),         // Reserved (Output 16)
    .dvr_int8tofp16_s0   (dvr_int8tofp16_s0_w),
    .dvr_int8tofp16_s1   (dvr_int8tofp16_s1_w),
    .dvr_fp16mul_s0     (dvr_fp16mul_s0_w),
    .dvr_fp16mul_s1     (dvr_fp16mul_s1_w),
    .dvr_fp16mul_s2     (dvr_fp16mul_s2_w),
    .dvr_fp16mul_s3     (dvr_fp16mul_s3_w),
    .dvr_fp16mul_s4567  (dvr_fp16mul_s4567_w),
    .dvr_fp32addtree5to1_s0 (dvr_fp32addtree5to1_s0_w),
    .dvr_fp32addtree5to1_s1 (dvr_fp32addtree5to1_s1_w),
    .dvr_fp32addtree5to1_s2 (dvr_fp32addtree5to1_s2_w),
    .dvr_fp32addtree5to1_s3 (dvr_fp32addtree5to1_s3_w),
    .dvr_fp32addtree5to1_s4 (dvr_fp32addtree5to1_s4_w),
    .dvr_fp32addtree5to1_s5 (dvr_fp32addtree5to1_s5_w),
    .dvr_fp32addtree5to1_s6 (dvr_fp32addtree5to1_s6_w),
    .dvr_fp32addtree5to1_s7 (dvr_fp32addtree5to1_s7_w),
    .dvr_fp32addtree8to1_s0 (dvr_fp32addtree8to1_s0_w),
    .dvr_fp32addtree8to1_s1 (dvr_fp32addtree8to1_s1_w),
    .dvr_shiftdn_s      (dvr_shiftdn_s_w),
    .uvr_wdata_0        (uvr_wdata_0_w),
    .uvr_wdata_1        (uvr_wdata_1_w),
    .uvr_wdata_2        (uvr_wdata_2_w),
    .uvr_wdata_3        (uvr_wdata_3_w),
    .reserved_out_39    (reserved_out_39_w)      // Reserved (Output 39)
);

// ========================================================================
// fp16mul: FP16 Multiplication Unit
// ========================================================================
fp16mul #(
    .SMC_ID(SMC_ID),
    .IEEE_754(IEEE_754)
) u_fp16mul (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .i_smc_id               (i_smc_id),
    .dvr_fp16mul_s0         (dvr_fp16mul_s0_w),
    .dvr_fp16mul_s1         (dvr_fp16mul_s1_w),
    .dvr_fp16mul_s2         (dvr_fp16mul_s2_w),
    .dvr_fp16mul_s3         (dvr_fp16mul_s3_w),
    .dvr_fp16mul_s4567      (dvr_fp16mul_s4567_w),
    .cru_fp16mul_s0123      (cru_fp16mul_s0123),
    .cru_fp16mul_s4567      (cru_fp16mul_s4567),
    .cru_fp16mul            (cru_fp16mul),
    .i_rounding_mode        (i_rounding_mode),
    .dr_fp16mul_d0          (dr_fp16mul_d0_w),
    .dr_fp16mul_d1          (dr_fp16mul_d1_w),
    .dr_fp16mul_d2          (dr_fp16mul_d2_w),
    .dr_fp16mul_d3          (dr_fp16mul_d3_w),
    .dr_fp16mul_d4          (dr_fp16mul_d4_w),
    .dr_fp16mul_d5          (dr_fp16mul_d5_w),
    .dr_fp16mul_d6          (dr_fp16mul_d6_w),
    .dr_fp16mul_d7          (dr_fp16mul_d7_w),
    .o_exception_flags      (exception_flags_fp16mul)
);

// ========================================================================
// fp32addtree5to1: FP32 5-to-1 Adder Tree
// ========================================================================
fp32_adder_tree_final_pipeline_5to1 #(
    .SMC_ID(SMC_ID),
    .IEEE_754(IEEE_754)
) u_fp32addtree5to1 (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .i_smc_id               (i_smc_id),
    .cru_fp32addtree5to1    (cru_fp32addtree5to1),
    .i_rounding_mode        (i_rounding_mode),
    .dvr_fp32addtree5to1_s0 (dvr_fp32addtree5to1_s0_w),
    .dvr_fp32addtree5to1_s1 (dvr_fp32addtree5to1_s1_w),
    .dvr_fp32addtree5to1_s2 (dvr_fp32addtree5to1_s2_w),
    .dvr_fp32addtree5to1_s3 (dvr_fp32addtree5to1_s3_w),
    .dvr_fp32addtree5to1_s4 (dvr_fp32addtree5to1_s4_w),
    .dvr_fp32addtree5to1_s5 (dvr_fp32addtree5to1_s5_w),
    .dvr_fp32addtree5to1_s6 (dvr_fp32addtree5to1_s6_w),
    .dvr_fp32addtree5to1_s7 (dvr_fp32addtree5to1_s7_w),
    .dr_fp32addtree5to1_d0  (dr_fp32addtree5to1_d0_w),
    .dr_fp32addtree5to1_d1  (dr_fp32addtree5to1_d1_w),
    .o_exception_flags      (exception_flags_fp32addtree5to1)
);

// ========================================================================
// fp32addtree8to1: FP32 8-to-1 Adder Tree
// ========================================================================
fp32_adder_tree_8_inputs_8to1 #(
    .SMC_ID(SMC_ID),
    .IEEE_754(IEEE_754)
) u_fp32addtree8to1 (
    .i_clk                  (clk),
    .i_rst_n                (rst_n),
    .i_smc_id               (i_smc_id),
    .i_dvr_fp32addtree8to1_s0 (dvr_fp32addtree8to1_s0_w),
    .i_dvr_fp32addtree8to1_s1 (dvr_fp32addtree8to1_s1_w),
    .i_cru_fp32addtree8to1  (cru_fp32addtree8to1),
    .i_rounding_mode        (i_rounding_mode),
    .o_dr_fp32addtree8to1_d (dr_fp32addtree8to1_d_w),
    .o_exception_flags      ()  // Exception flags (optional)
);

// ========================================================================
// fpadd: Floating-Point Addition/Subtraction
// ========================================================================
fp_adder #(
    .SMC_ID(SMC_ID),
    .IEEE_754(IEEE_754)
) u_fpadd (
    .i_clk                  (clk),
    .i_rst_n                (rst_n),
    .i_smc_id               (i_smc_id),
    .i_dvr_fpadd_s0         (dvr_fpadd_s0_w),
    .i_dvr_fpadd_s1         (dvr_fpadd_s1_w),
    .i_cru_fpadd            (cru_fpadd),
    .i_rounding_mode        (i_rounding_mode),
    .o_dr_fpadd_d           (dr_fpadd_d_w),
    .o_dr_fpadd_st          (dr_fpadd_st_w),
    .o_exception_flags      (exception_flags_fpadd),
    .o_cru_fpadd_o          (cru_fpadd_o)
);

// ========================================================================
// fpmul: Floating-Point Multiplication
// ========================================================================
fpmul #(
    .SMC_ID(SMC_ID),
    .IEEE_754(IEEE_754)
) u_fpmul (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dvr_fpmul_s0           (dvr_fpmul_s0_w),
    .dvr_fpmul_s1           (dvr_fpmul_s1_w),
    .cru_fpmul              (cru_fpmul),
    .i_rounding_mode        (i_rounding_mode),
    .cru_fpmul_o            (cru_fpmul_o),
    .dr_fpmul_d             (dr_fpmul_d_w),
    .o_exception_flags      (exception_flags_fpmul)
);

// ========================================================================
// fpto_int: Floating-Point to Integer Conversion
// ========================================================================
fpto_int_array #(
    .SMC_ID(SMC_ID)
) u_fpto_int (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dvr_fptoint_s_in       (dvr_fptoint_s_w),
    .cru_fptoint_in         (cru_fptoint),
    .dr_fptoint_d_out       (dr_fptoint_d_w)
);

// ========================================================================
// fptofp: Floating-Point to Floating-Point Conversion
// ========================================================================
fptofp_array #(
    .SMC_ID(SMC_ID)
) u_fptofp (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dvr_fptofp_s           (dvr_fptofp_s_w),
    .cru_fptofp             (cru_fptofp),
    .dr_fptofp_d            (dr_fptofp_d_w),
    .smc_id                 (i_smc_id)
);

// ========================================================================
// int_to_int: Integer to Integer Conversion
// ========================================================================
int_to_int_array #(
    .SMC_ID(SMC_ID)
) u_int_to_int (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dvr_inttoint_s_in      (dvr_inttoint_s_w),
    .cru_inttoint_in        (cru_inttoint),
    .dr_inttoint_d_out      (dr_inttoint_d_w),
    .cru_inttoint_out       (cru_inttoint_o),
    .smc_id_in              (i_smc_id)
);

// ========================================================================
// inttofp: Integer to Floating-Point Conversion
// ========================================================================
inttofp #(
    .SMC_ID(SMC_ID)
) u_inttofp (
    .i_clk                  (clk),
    .i_rst_n                (rst_n),
    .i_smc_id               (i_smc_id),
    .i_dvr_inttofp_s        (dvr_inttofp_s_w),
    .i_cru_inttofp          (cru_inttofp),
    .o_dr_inttofp_d         (dr_inttofp_d_w),
    .o_cru_inttofp_o        (cru_inttofp_o)
);

// ========================================================================
// intadd: Integer Addition (if exists in cells directory)
// ========================================================================
intadd u_intadd (
    .clk                 (clk),
    .rst_n               (rst_n),
    .i_smc_id            (i_smc_id),
    .src_reg0            (dvr_intadd_s0_w),
    .src_reg1            (dvr_intadd_s1_w),
    .src_reg2            (dvr_intadd_s2_w),
    .cru_intadd          (cru_intadd),
    .dst_reg0            (dr_intadd_d0_internal),
    .dst_reg1            (dr_intadd_d1_internal),
    .st                  (dr_intadd_st_internal),
    .o_cru_intadd        (cru_intadd_o)
);

// ========================================================================
// int8tofp16: INT8 to FP16 Conversion
// ========================================================================
int8_to_fp16_array u_int8tofp16 (
    .clk                 (clk),
    .rst_n               (rst_n),
    .dvr_int8tofp16_s0   (dvr_int8tofp16_s0_w),
    .dvr_int8tofp16_s1   (dvr_int8tofp16_s1_w),
    .cru_int8tofp16      (cru_int8tofp16),
    .dr_int8tofp16_d0    (dr_int8tofp16_d0_internal),
    .dr_int8tofp16_d1    (dr_int8tofp16_d1_internal),
    .dr_int8tofp16_d2    (dr_int8tofp16_d2_internal),
    .dr_int8tofp16_d3    (dr_int8tofp16_d3_internal)
);

// ========================================================================
// logical: Logical Operations
// ========================================================================
logical #(
    .SMC_ID(SMC_ID)
) u_logical (
    .i_clk                  (clk),
    .i_rst_n                (rst_n),
    .i_smc_id               (i_smc_id),
    .i_cru_logic            (cru_logic),
    .i_dvr_logic_s0         (dvr_logic_s0_w),
    .i_dvr_logic_s1         (dvr_logic_s1_w),
    .i_dvr_logic_st         (dvr_logic_st_w),
    .o_dr_logic_d           (dr_logic_d_w),
    .o_cru_logic_o          (cru_logic_o)
);

// ========================================================================
// shift_up: Shift Up Operation
// ========================================================================
shift_up #(
    .SMC_ID(SMC_ID)
) u_shift_up (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .cru_shiftup_in         (cru_shiftup),
    .dr_shiftup_out         (dr_shiftup_d_w),
    .cru_shiftup_out        (cru_shiftup_o)
);

// ========================================================================
// shift_down: Shift Down Operation
// ========================================================================
shift_down #(
    .SMC_ID(SMC_ID)
) u_shift_down (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .crd_shiftdn_in         (crd_shiftdn),
    .dvr_shiftdn_in         (dvr_shiftdn_s_w),
    .crd_shiftdn_out        (crd_shiftdn_out)
);

// ========================================================================
// user_register: User Register Module (UR)
// ========================================================================
user_register #(
    .SMC_ID                     (SMC_ID),
    .PARAM_UR_BYTE_CNT          (5'd16),
    .PARAM_UR_WR_PORT_CNT       (3'd4),
    .PARAM_UR_RD_PORT_CNT       (3'd4),
    .PARAM_UR_BANK_BIT_NUM      (2'd2),
    .PARAM_UR_BANK_ADDR_BIT_NUM (4'd8),
    .PARAM_UR_WRI_PIPE_CNT      (1'd0),
    .PARAM_UR_RDI_PIPE_CNT      (1'd0),
    .PARAM_UR_RDO_PIPE_CNT      (1'd0)
) u_user_register (
    .i_clk                      (clk),
    .i_rst_n                    (rst_n),
    .i_smc_id                   (i_smc_id),
    .i_cru_ur                   (cru_ur),
    .i_uvr_wdata_0              (uvr_wdata_0_w),
    .i_uvr_wdata_1              (uvr_wdata_1_w),
    .i_uvr_wdata_2              (uvr_wdata_2_w),
    .i_uvr_wdata_3              (uvr_wdata_3_w),
    .o_ur_rdata_0               (ur_rdata_0_w),
    .o_ur_rdata_1               (ur_rdata_1_w),
    .o_ur_rdata_2               (ur_rdata_2_w),
    .o_ur_rdata_3               (ur_rdata_3_w),
    .o_cru_ur                   (cru_ur_o)
);

// ========================================================================
// IPR: Input Pipeline Register - VIN0
// ========================================================================
IPR #(
    .SMC_ID(SMC_ID)
) u_ipr_vin0 (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .i_smc_id                   (i_smc_id),
    .cru_vin0                   (cru_vin0),
    .dvr_vin0_s                 (dvr_vin0_s_w),      // From RtoVR output
    .dr_vin0_d                  (dr_vin0_d_w),       // To RtoVR input
    .cru_vin0_o                 (cru_vin0_o)
);

// ========================================================================
// IPR: Input Pipeline Register - VIN1
// ========================================================================
IPR #(
    .SMC_ID(SMC_ID)
) u_ipr_vin1 (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .i_smc_id                   (i_smc_id),
    .cru_vin0                   (cru_vin1),          // Note: IPR module uses cru_vin0 port name
    .dvr_vin0_s                 (dvr_vin1_s_w),      // From RtoVR output
    .dr_vin0_d                  (dr_vin1_d_w),       // To RtoVR input
    .cru_vin0_o                 (cru_vin1_o)
);

// ========================================================================
// OPR: Output Pipeline Register - VOUT0
// ========================================================================
OPR #(
    .SMC_ID(SMC_ID)
) u_opr_vout0 (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .i_smc_id                   (i_smc_id),
    .cru_vout0                  (cru_vout0),
    .dvr_vout0_s                (dvr_vout0_s_w),     // From RtoVR output
    .dr_vout0_d                 (dr_vout0_d_w),      // To RtoVR input
    .cru_vout0_o                (cru_vout0_o)
);

/*************************************************** OUTPUT ASSIGNMENTS ******************************************************/
// CRU outputs are directly connected from module instances
// No assignments needed - outputs are directly wired from modules

endmodule

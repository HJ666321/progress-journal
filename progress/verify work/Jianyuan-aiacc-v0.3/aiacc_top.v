/*****************************************************************************
** Project  :  AIACC NPU                                                     **
******************************************************************************
**                                      **                                  **
** File name:  aiacc_top.v                 **             AIACC Team          **
** Designer :  AIACC RTL Generator      **  NPU Design Division            **
**                                      **                                  **
******************************************************************************
******************************************************************************
**                                                                          **
** Module Description:                                                      **
**                                                                          **
** AIACC NPU Top Module                                                    **
**                                                                          **
** This module integrates:                                                 **
**   - SMC: Stream Multiprocessor Compute Unit                             **
**   - smi_iq: 64 Instruction Queue instances (ID 0-63)                    **
**                                                                          **
** SMI-IQ ID Mapping:                                                       **
**   0: INTADD, 1: INT8toFP16, 2: FP16MUL, 3: FP32ADDTREE5TO1              **
**   4: FP32ADDTREE8TO1, 5: FPMUL, 6: FPADD, 7: FPtoFP                     **
**   8: INTtoINT, 9: FPtoINT, 10: INTtoFP, 11: LOGIC                       **
**   12: SHIFTUP, 13: SHIFTDN, 14-17: UR-RDATA-0~3, 18-21: UR-WDATA-0~3   **
**   22: STB, 23: LDB, 24-63: RtoVR (40 instances, out_idx 0-39)           **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
** Hierarchy:                                                               **
**                                                                          **
** aiacc_top (top)                                                          **
**   |-- SMC                                                                **
**   |-- smi_iq x 64                                                        **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
**   Revision        Date            By               Reason                **
** ------------   ------------   ------------      ------------             **
**     1.0                                           Creation               **
**                                                                          **
*****************************************************************************/
`timescale 1ns/1ps

// ==========================================================================
// SMI-IQ ID Definitions
// ==========================================================================
`define IQ_ID_INTADD           0
`define IQ_ID_INT8toFP16       1
`define IQ_ID_FP16MUL          2
`define IQ_ID_FP32ADDTREE5TO1  3
`define IQ_ID_FP32ADDTREE8TO1  4
`define IQ_ID_FPMUL            5
`define IQ_ID_FPADD            6
`define IQ_ID_FPtoFP           7
`define IQ_ID_INTtoINT         8
`define IQ_ID_FPtoINT          9
`define IQ_ID_INTtoFP          10
`define IQ_ID_LOGIC            11
`define IQ_ID_SHIFTUP          12
`define IQ_ID_SHIFTDN          13
`define IQ_ID_UR_RDATA_0       14
`define IQ_ID_UR_RDATA_1       15
`define IQ_ID_UR_RDATA_2       16
`define IQ_ID_UR_RDATA_3       17
`define IQ_ID_UR_WDATA_0       18
`define IQ_ID_UR_WDATA_1       19
`define IQ_ID_UR_WDATA_2       20
`define IQ_ID_UR_WDATA_3       21
`define IQ_ID_STB              22
`define IQ_ID_LDB              23
`define IQ_ID_RTOVR_BASE       24
// RtoVR IDs: 24-63 (40 instances, out_idx 0-39)

// Total SMI-IQ count
`define SMI_IQ_CNT             64

// ==========================================================================
// DLY_INST_WIDTH Definitions (= BIT_CODE)
// Unique values only, shared by IQs with same width
// ==========================================================================
`define DLY_WIDTH_1            1    // FP32ADDTREE5TO1
`define DLY_WIDTH_2            2    // INT8toFP16
`define DLY_WIDTH_3            3    // FP32ADDTREE8TO1, FPMUL
`define DLY_WIDTH_5            5    // FPADD, FPtoFP, FPtoINT
`define DLY_WIDTH_6            6    // INTtoFP, LOGIC
`define DLY_WIDTH_7            7    // INTtoINT, RtoVR
`define DLY_WIDTH_9            9    // FP16MUL
`define DLY_WIDTH_12           12   // UR-RDATA
`define DLY_WIDTH_13           13   // INTADD (13-bit: bit 12 is sub_en)
`define DLY_WIDTH_28           28   // UR-WDATA
`define DLY_WIDTH_71           71   // STB, LDB
`define DLY_WIDTH_134          134  // SHIFTDN
`define DLY_WIDTH_135          135  // SHIFTUP

// Maximum DLY_INST_WIDTH (for array declaration)
`define DLY_WIDTH_MAX          135

// ==========================================================================
// smi_iq Write Data Width (WR_DATA_xxx_W = bit width)
// ==========================================================================
`define WR_DATA_INTADD_W           54   // ID 0
`define WR_DATA_INT8toFP16_W       43   // ID 1
`define WR_DATA_FP16MUL_W          50   // ID 2
`define WR_DATA_FP32ADDTREE5TO1_W  42   // ID 3
`define WR_DATA_FP32ADDTREE8TO1_W  44   // ID 4
`define WR_DATA_FPMUL_W            44   // ID 5
`define WR_DATA_FPADD_W            46   // ID 6
`define WR_DATA_FPtoFP_W           46   // ID 7
`define WR_DATA_INTtoINT_W         48   // ID 8
`define WR_DATA_FPtoINT_W          46   // ID 9
`define WR_DATA_INTtoFP_W          47   // ID 10
`define WR_DATA_LOGIC_W            47   // ID 11
`define WR_DATA_SHIFTUP_W          176  // ID 12
`define WR_DATA_SHIFTDN_W          175  // ID 13
`define WR_DATA_UR_RDATA_W         53   // ID 14-17
`define WR_DATA_UR_WDATA_W          69   // ID 18-21
`define WR_DATA_STB_W              112  // ID 22
`define WR_DATA_LDB_W              112  // ID 23
`define WR_DATA_RTOVR_W            48   // ID 24-63

module aiacc_top #(
    /*************************************************** PARAMETER DECLARATIONS ***************************************************/
    parameter SMC_ID = 0,                // SMC ID
    parameter IEEE_754 = 0,               // IEEE 754 mode
    parameter SUB_IQ_NUM = 4,             // Sub IQ number
    parameter SMI_IQ_AMOUNT = 64          // Total IQ amount (64 IQs)
) (
    /******************************************************** INPUTS **************************************************************/
    // Global Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // SMC Identification
    input  wire [4:0]  i_smc_id,
    
    // Rounding Mode Control
    input  wire [2:0]  i_rounding_mode,  // 000=RNE, 001=RTZ, 010=RDN, 011=RUP, 100=RMM
    
    // ========== smi_iq Write Instruction Interface (per IQ, different widths) ==========
    // ID 0: INTADD
    input  wire [`WR_DATA_INTADD_W-1:0]           wri_data_intadd,
    // ID 1: INT8toFP16
    input  wire [`WR_DATA_INT8toFP16_W-1:0]      wri_data_int8tofp16,
    // ID 2: FP16MUL
    input  wire [`WR_DATA_FP16MUL_W-1:0]         wri_data_fp16mul,
    // ID 3: FP32ADDTREE5TO1
    input  wire [`WR_DATA_FP32ADDTREE5TO1_W-1:0] wri_data_fp32addtree5to1,
    // ID 4: FP32ADDTREE8TO1
    input  wire [`WR_DATA_FP32ADDTREE8TO1_W-1:0] wri_data_fp32addtree8to1,
    // ID 5: FPMUL
    input  wire [`WR_DATA_FPMUL_W-1:0]           wri_data_fpmul,
    // ID 6: FPADD
    input  wire [`WR_DATA_FPADD_W-1:0]           wri_data_fpadd,
    // ID 7: FPtoFP
    input  wire [`WR_DATA_FPtoFP_W-1:0]          wri_data_fptofp,
    // ID 8: INTtoINT
    input  wire [`WR_DATA_INTtoINT_W-1:0]        wri_data_inttoint,
    // ID 9: FPtoINT
    input  wire [`WR_DATA_FPtoINT_W-1:0]         wri_data_fptoint,
    // ID 10: INTtoFP
    input  wire [`WR_DATA_INTtoFP_W-1:0]         wri_data_inttofp,
    // ID 11: LOGIC
    input  wire [`WR_DATA_LOGIC_W-1:0]           wri_data_logic,
    // ID 12: SHIFTUP
    input  wire [`WR_DATA_SHIFTUP_W-1:0]         wri_data_shiftup,
    // ID 13: SHIFTDN
    input  wire [`WR_DATA_SHIFTDN_W-1:0]         wri_data_shiftdn,
    // ID 14-17: UR-RDATA
    input  wire [`WR_DATA_UR_RDATA_W-1:0]        wri_data_ur_rdata [3:0],
    // ID 18-21: UR-WDATA
    input  wire [`WR_DATA_UR_WDATA_W-1:0]        wri_data_ur_wdata [3:0],
    // ID 22: STB
    input  wire [`WR_DATA_STB_W-1:0]             wri_data_stb,
    // ID 23: LDB
    input  wire [`WR_DATA_LDB_W-1:0]             wri_data_ldb,
    // ID 24-63: RtoVR
    input  wire [`WR_DATA_RTOVR_W-1:0]           wri_data_rtovr [39:0],
    
    // ========== smi_iq Write Control (per IQ arrays) ==========
    input  wire [SMI_IQ_AMOUNT-1:0] wri_vld,
    input  wire [SMI_IQ_AMOUNT-1:0] wri_start,
    input  wire [SMI_IQ_AMOUNT-1:0] wri_end,
    input  wire [1:0]               wri_iqsid [SMI_IQ_AMOUNT-1:0],
    
    // ========== smi_iq Read Control (per IQ arrays) ==========
    input  wire [SMI_IQ_AMOUNT-1:0] rdi_start,
    input  wire [1:0]               rdi_iqsid [SMI_IQ_AMOUNT-1:0],
    output wire [SMI_IQ_AMOUNT-1:0] rdi_done,
    output wire [1:0]               rdi_iqeid [SMI_IQ_AMOUNT-1:0],
    
    /******************************************************** OUTPUTS *************************************************************/
    // SMC CRU Outputs
    output wire [133:0] crd_shiftdn_out,
    output wire [4:0]   cru_fpadd_o,
    output wire [2:0]   cru_fpmul_o,
    output wire [6:0]   cru_inttoint_o,
    output wire [5:0]   cru_inttofp_o,
    output wire [5:0]   cru_logic_o,
    output wire [12:0]  cru_intadd_o,
    output wire [134:0] cru_shiftup_o,
    output wire [279:0] cru_rtovr_o,
    output wire [160:0] cru_ur_o,
    output wire         cru_vin0_o,
    output wire         cru_vin1_o,
    output wire         cru_vout0_o

);

/*************************************************** WIRE DECLARATIONS ********************************************************/
// Instruction outputs from smi_iq instances (individual signals for each IQ)

// ---------- ID 0-13: Compute Units (individual signals) ----------
wire [`DLY_WIDTH_13-1:0]  w_inst_intadd;           // ID 0: INTADD
wire                      w_inst_valid_intadd;
wire [5:0]                w_inst_id_intadd;
wire                      w_inst_keep_intadd;
wire                      w_inst_rdy_intadd;

wire [`DLY_WIDTH_2-1:0]   w_inst_int8tofp16;       // ID 1: INT8toFP16
wire                      w_inst_valid_int8tofp16;
wire [5:0]                w_inst_id_int8tofp16;
wire                      w_inst_keep_int8tofp16;
wire                      w_inst_rdy_int8tofp16;

wire [`DLY_WIDTH_9-1:0]   w_inst_fp16mul;          // ID 2: FP16MUL
wire                      w_inst_valid_fp16mul;
wire [5:0]                w_inst_id_fp16mul;
wire                      w_inst_keep_fp16mul;
wire                      w_inst_rdy_fp16mul;

wire [`DLY_WIDTH_1-1:0]   w_inst_fp32addtree5to1;  // ID 3: FP32ADDTREE5TO1
wire                      w_inst_valid_fp32addtree5to1;
wire [5:0]                w_inst_id_fp32addtree5to1;
wire                      w_inst_keep_fp32addtree5to1;
wire                      w_inst_rdy_fp32addtree5to1;

wire [`DLY_WIDTH_3-1:0]   w_inst_fp32addtree8to1;  // ID 4: FP32ADDTREE8TO1
wire                      w_inst_valid_fp32addtree8to1;
wire [5:0]                w_inst_id_fp32addtree8to1;
wire                      w_inst_keep_fp32addtree8to1;
wire                      w_inst_rdy_fp32addtree8to1;

wire [`DLY_WIDTH_3-1:0]   w_inst_fpmul;            // ID 5: FPMUL
wire                      w_inst_valid_fpmul;
wire [5:0]                w_inst_id_fpmul;
wire                      w_inst_keep_fpmul;
wire                      w_inst_rdy_fpmul;

wire [`DLY_WIDTH_5-1:0]   w_inst_fpadd;            // ID 6: FPADD
wire                      w_inst_valid_fpadd;
wire [5:0]                w_inst_id_fpadd;
wire                      w_inst_keep_fpadd;
wire                      w_inst_rdy_fpadd;

wire [`DLY_WIDTH_5-1:0]   w_inst_fptofp;           // ID 7: FPtoFP
wire                      w_inst_valid_fptofp;
wire [5:0]                w_inst_id_fptofp;
wire                      w_inst_keep_fptofp;
wire                      w_inst_rdy_fptofp;

wire [`DLY_WIDTH_7-1:0]   w_inst_inttoint;         // ID 8: INTtoINT
wire                      w_inst_valid_inttoint;
wire [5:0]                w_inst_id_inttoint;
wire                      w_inst_keep_inttoint;
wire                      w_inst_rdy_inttoint;

wire [`DLY_WIDTH_5-1:0]   w_inst_fptoint;          // ID 9: FPtoINT
wire                      w_inst_valid_fptoint;
wire [5:0]                w_inst_id_fptoint;
wire                      w_inst_keep_fptoint;
wire                      w_inst_rdy_fptoint;

wire [`DLY_WIDTH_6-1:0]   w_inst_inttofp;          // ID 10: INTtoFP
wire                      w_inst_valid_inttofp;
wire [5:0]                w_inst_id_inttofp;
wire                      w_inst_keep_inttofp;
wire                      w_inst_rdy_inttofp;

wire [`DLY_WIDTH_6-1:0]   w_inst_logic;            // ID 11: LOGIC
wire                      w_inst_valid_logic;
wire [5:0]                w_inst_id_logic;
wire                      w_inst_keep_logic;
wire                      w_inst_rdy_logic;

wire [`DLY_WIDTH_135-1:0] w_inst_shiftup;          // ID 12: SHIFTUP
wire                      w_inst_valid_shiftup;
wire [5:0]                w_inst_id_shiftup;
wire                      w_inst_keep_shiftup;
wire                      w_inst_rdy_shiftup;

wire [`DLY_WIDTH_134-1:0] w_inst_shiftdn;          // ID 13: SHIFTDN
wire                      w_inst_valid_shiftdn;
wire [5:0]                w_inst_id_shiftdn;
wire                      w_inst_keep_shiftdn;
wire                      w_inst_rdy_shiftdn;

// ---------- ID 14-17: UR-RDATA (array for loop instantiation) ----------
wire [`DLY_WIDTH_12-1:0]  w_inst_ur_rdata [3:0];
wire [3:0]                w_inst_valid_ur_rdata;
wire [5:0]                w_inst_id_ur_rdata [3:0];
wire [3:0]                w_inst_keep_ur_rdata;
wire [3:0]                w_inst_rdy_ur_rdata;

// ---------- ID 18-21: UR-WDATA (array for loop instantiation) ----------
wire [`DLY_WIDTH_28-1:0]  w_inst_ur_wdata [3:0];
wire [3:0]                w_inst_valid_ur_wdata;
wire [5:0]                w_inst_id_ur_wdata [3:0];
wire [3:0]                w_inst_keep_ur_wdata;
wire [3:0]                w_inst_rdy_ur_wdata;

// ---------- ID 22-23: STB/LDB (individual signals) ----------
wire [`DLY_WIDTH_71-1:0]  w_inst_stb;              // ID 22: STB
wire                      w_inst_valid_stb;
wire [5:0]                w_inst_id_stb;
wire                      w_inst_keep_stb;
wire                      w_inst_rdy_stb;

wire [`DLY_WIDTH_71-1:0]  w_inst_ldb;              // ID 23: LDB
wire                      w_inst_valid_ldb;
wire [5:0]                w_inst_id_ldb;
wire                      w_inst_keep_ldb;
wire                      w_inst_rdy_ldb;

// ---------- ID 24-63: RtoVR (array for loop instantiation) ----------
wire [`DLY_WIDTH_7-1:0]   w_inst_rtovr [39:0];
wire [39:0]               w_inst_valid_rtovr;
wire [5:0]                w_inst_id_rtovr [39:0];
wire [39:0]               w_inst_keep_rtovr;
wire [39:0]               w_inst_rdy_rtovr;

// Combined inst_rdy for inst_rdy_in (OR of all ready signals)
wire [SMI_IQ_AMOUNT-1:0]  w_inst_rdy_all;

// CRU control signals (width = DLY_INST_WIDTH for each IQ)
wire [`DLY_WIDTH_13-1:0]  w_cru_intadd;           // ID 0:  DLY_WIDTH = 13 (13-bit: bit 12 is sub_en)
wire [`DLY_WIDTH_2-1:0]   w_cru_int8tofp16;       // ID 1:  DLY_WIDTH = 2
wire [`DLY_WIDTH_9-1:0]   w_cru_fp16mul_full;     // ID 2:  DLY_WIDTH = 9 (split below)
wire [2:0]                w_cru_fp16mul;          //        - [2:0]
wire [1:0]                w_cru_fp16mul_s0123;    //        - [4:3]
wire [3:0]                w_cru_fp16mul_s4567;    //        - [8:5]
wire [`DLY_WIDTH_1-1:0]   w_cru_fp32addtree5to1;  // ID 3:  DLY_WIDTH = 1
wire [`DLY_WIDTH_3-1:0]   w_cru_fp32addtree8to1;  // ID 4:  DLY_WIDTH = 3
wire [`DLY_WIDTH_3-1:0]   w_cru_fpmul;            // ID 5:  DLY_WIDTH = 3
wire [`DLY_WIDTH_5-1:0]   w_cru_fpadd;            // ID 6: FPADD, DLY_WIDTH = 5
wire [`DLY_WIDTH_5-1:0]   w_cru_fptofp;           // ID 7:  DLY_WIDTH = 5
wire [`DLY_WIDTH_7-1:0]   w_cru_inttoint;         // ID 8:  DLY_WIDTH = 7
wire [`DLY_WIDTH_5-1:0]   w_cru_fptoint;          // ID 9:  DLY_WIDTH = 5
wire [`DLY_WIDTH_6-1:0]   w_cru_inttofp;          // ID 10: DLY_WIDTH = 6
wire [`DLY_WIDTH_6-1:0]   w_cru_logic;            // ID 11: DLY_WIDTH = 6
wire [`DLY_WIDTH_135-1:0] w_cru_shiftup;          // ID 12: DLY_WIDTH = 135
wire [`DLY_WIDTH_134-1:0] w_crd_shiftdn;          // ID 13: DLY_WIDTH = 134
wire [`DLY_WIDTH_12-1:0]  w_cru_ur_rdata [3:0];   // ID 14-17: DLY_WIDTH = 12 each
wire [`DLY_WIDTH_28-1:0]  w_cru_ur_wdata [3:0];   // ID 18-21: DLY_WIDTH = 28 each
wire [`DLY_WIDTH_71-1:0]  w_cru_stb;              // ID 22: DLY_WIDTH = 71
wire [`DLY_WIDTH_71-1:0]  w_cru_ldb;              // ID 23: DLY_WIDTH = 71
wire [`DLY_WIDTH_7-1:0]   w_cru_rtovr_inst [39:0];// ID 24-63: DLY_WIDTH = 7 each
reg  [279:0]              w_cru_rtovr;            // Concatenated RtoVR
wire [159:0]              w_cru_ur;               // Concatenated UR
wire                      w_cru_vin0;
wire                      w_cru_vin1;
wire                      w_cru_vout0;

// ==========================================================================
// Debug Signals: Individual w_cru_rtovr_inst channels with channel ID suffix
// ==========================================================================
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_0;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_1;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_2;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_3;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_4;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_5;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_6;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_7;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_8;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_9;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_10;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_11;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_12;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_13;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_14;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_15;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_16;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_17;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_18;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_19;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_20;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_21;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_22;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_23;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_24;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_25;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_26;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_27;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_28;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_29;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_30;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_31;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_32;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_33;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_34;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_35;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_36;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_37;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_38;
wire [`DLY_WIDTH_7-1:0] dbg_cru_rtovr_inst_39;

// ==========================================================================
// CRU Signal Assignment (using individual inst signals)
// ==========================================================================

// INTADD (ID 0): DLY_WIDTH = 12
assign w_cru_intadd = w_inst_valid_intadd ? w_inst_intadd : {`DLY_WIDTH_13{1'b0}};

// INT8toFP16 (ID 1): DLY_WIDTH = 2
assign w_cru_int8tofp16 = w_inst_valid_int8tofp16 ? w_inst_int8tofp16 : {`DLY_WIDTH_2{1'b0}};

// FP16MUL (ID 2): DLY_WIDTH = 9, split into 3 parts
assign w_cru_fp16mul_full  = w_inst_valid_fp16mul ? w_inst_fp16mul : {`DLY_WIDTH_9{1'b0}};
assign w_cru_fp16mul       = w_cru_fp16mul_full[2:0];
assign w_cru_fp16mul_s0123 = w_cru_fp16mul_full[4:3];
assign w_cru_fp16mul_s4567 = w_cru_fp16mul_full[8:5];

// FP32ADDTREE5TO1 (ID 3): DLY_WIDTH = 1
assign w_cru_fp32addtree5to1 = w_inst_valid_fp32addtree5to1 ? w_inst_fp32addtree5to1 : {`DLY_WIDTH_1{1'b0}};

// FP32ADDTREE8TO1 (ID 4): DLY_WIDTH = 3
assign w_cru_fp32addtree8to1 = w_inst_valid_fp32addtree8to1 ? w_inst_fp32addtree8to1 : {`DLY_WIDTH_3{1'b0}};

// FPMUL (ID 5): DLY_WIDTH = 3
assign w_cru_fpmul = w_inst_valid_fpmul ? w_inst_fpmul : {`DLY_WIDTH_3{1'b0}};

// FPADD (ID 6): DLY_WIDTH = 5 (5bit CRU)
assign w_cru_fpadd = w_inst_valid_fpadd ? w_inst_fpadd : {`DLY_WIDTH_5{1'b0}};

// FPtoFP (ID 7): DLY_WIDTH = 5
assign w_cru_fptofp = w_inst_valid_fptofp ? w_inst_fptofp : {`DLY_WIDTH_5{1'b0}};

// INTtoINT (ID 8): DLY_WIDTH = 7
assign w_cru_inttoint = w_inst_valid_inttoint ? w_inst_inttoint : {`DLY_WIDTH_7{1'b0}};

// FPtoINT (ID 9): DLY_WIDTH = 5
assign w_cru_fptoint = w_inst_valid_fptoint ? w_inst_fptoint : {`DLY_WIDTH_5{1'b0}};

// INTtoFP (ID 10): DLY_WIDTH = 6
assign w_cru_inttofp = w_inst_valid_inttofp ? w_inst_inttofp : {`DLY_WIDTH_6{1'b0}};

// LOGIC (ID 11): DLY_WIDTH = 6
assign w_cru_logic = w_inst_valid_logic ? w_inst_logic : {`DLY_WIDTH_6{1'b0}};

// SHIFTUP (ID 12): DLY_WIDTH = 135
assign w_cru_shiftup = w_inst_valid_shiftup ? w_inst_shiftup : {`DLY_WIDTH_135{1'b0}};

// SHIFTDN (ID 13): DLY_WIDTH = 134
assign w_crd_shiftdn = w_inst_valid_shiftdn ? w_inst_shiftdn : {`DLY_WIDTH_134{1'b0}};

// UR-RDATA (ID 14-17): DLY_WIDTH = 12 each
assign w_cru_ur_rdata[0] = w_inst_valid_ur_rdata[0] ? w_inst_ur_rdata[0] : {`DLY_WIDTH_12{1'b0}};
assign w_cru_ur_rdata[1] = w_inst_valid_ur_rdata[1] ? w_inst_ur_rdata[1] : {`DLY_WIDTH_12{1'b0}};
assign w_cru_ur_rdata[2] = w_inst_valid_ur_rdata[2] ? w_inst_ur_rdata[2] : {`DLY_WIDTH_12{1'b0}};
assign w_cru_ur_rdata[3] = w_inst_valid_ur_rdata[3] ? w_inst_ur_rdata[3] : {`DLY_WIDTH_12{1'b0}};

// UR-WDATA (ID 18-21): DLY_WIDTH = 28 each
assign w_cru_ur_wdata[0] = w_inst_valid_ur_wdata[0] ? w_inst_ur_wdata[0] : {`DLY_WIDTH_28{1'b0}};
assign w_cru_ur_wdata[1] = w_inst_valid_ur_wdata[1] ? w_inst_ur_wdata[1] : {`DLY_WIDTH_28{1'b0}};
assign w_cru_ur_wdata[2] = w_inst_valid_ur_wdata[2] ? w_inst_ur_wdata[2] : {`DLY_WIDTH_28{1'b0}};
assign w_cru_ur_wdata[3] = w_inst_valid_ur_wdata[3] ? w_inst_ur_wdata[3] : {`DLY_WIDTH_28{1'b0}};

// STB (ID 22): DLY_WIDTH = 71
assign w_cru_stb = w_inst_valid_stb ? w_inst_stb : {`DLY_WIDTH_71{1'b0}};

// LDB (ID 23): DLY_WIDTH = 71
assign w_cru_ldb = w_inst_valid_ldb ? w_inst_ldb : {`DLY_WIDTH_71{1'b0}};

// RtoVR (ID 24-63): DLY_WIDTH = 7 each
genvar rtovr_idx;
generate
    for (rtovr_idx = 0; rtovr_idx < 40; rtovr_idx = rtovr_idx + 1) begin : gen_rtovr_assign
        assign w_cru_rtovr_inst[rtovr_idx] = w_inst_valid_rtovr[rtovr_idx] ? w_inst_rtovr[rtovr_idx] : {`DLY_WIDTH_7{1'b0}};
        
        // Debug signal assignment: Connect each channel to individual debug signal with channel ID suffix
        case (rtovr_idx)
            0:  assign dbg_cru_rtovr_inst_0 = w_cru_rtovr_inst[rtovr_idx];
            1:  assign dbg_cru_rtovr_inst_1 = w_cru_rtovr_inst[rtovr_idx];
            2:  assign dbg_cru_rtovr_inst_2 = w_cru_rtovr_inst[rtovr_idx];
            3:  assign dbg_cru_rtovr_inst_3 = w_cru_rtovr_inst[rtovr_idx];
            4:  assign dbg_cru_rtovr_inst_4 = w_cru_rtovr_inst[rtovr_idx];
            5:  assign dbg_cru_rtovr_inst_5 = w_cru_rtovr_inst[rtovr_idx];
            6:  assign dbg_cru_rtovr_inst_6 = w_cru_rtovr_inst[rtovr_idx];
            7:  assign dbg_cru_rtovr_inst_7 = w_cru_rtovr_inst[rtovr_idx];
            8:  assign dbg_cru_rtovr_inst_8 = w_cru_rtovr_inst[rtovr_idx];
            9:  assign dbg_cru_rtovr_inst_9 = w_cru_rtovr_inst[rtovr_idx];
            10: assign dbg_cru_rtovr_inst_10 = w_cru_rtovr_inst[rtovr_idx];
            11: assign dbg_cru_rtovr_inst_11 = w_cru_rtovr_inst[rtovr_idx];
            12: assign dbg_cru_rtovr_inst_12 = w_cru_rtovr_inst[rtovr_idx];
            13: assign dbg_cru_rtovr_inst_13 = w_cru_rtovr_inst[rtovr_idx];
            14: assign dbg_cru_rtovr_inst_14 = w_cru_rtovr_inst[rtovr_idx];
            15: assign dbg_cru_rtovr_inst_15 = w_cru_rtovr_inst[rtovr_idx];
            16: assign dbg_cru_rtovr_inst_16 = w_cru_rtovr_inst[rtovr_idx];
            17: assign dbg_cru_rtovr_inst_17 = w_cru_rtovr_inst[rtovr_idx];
            18: assign dbg_cru_rtovr_inst_18 = w_cru_rtovr_inst[rtovr_idx];
            19: assign dbg_cru_rtovr_inst_19 = w_cru_rtovr_inst[rtovr_idx];
            20: assign dbg_cru_rtovr_inst_20 = w_cru_rtovr_inst[rtovr_idx];
            21: assign dbg_cru_rtovr_inst_21 = w_cru_rtovr_inst[rtovr_idx];
            22: assign dbg_cru_rtovr_inst_22 = w_cru_rtovr_inst[rtovr_idx];
            23: assign dbg_cru_rtovr_inst_23 = w_cru_rtovr_inst[rtovr_idx];
            24: assign dbg_cru_rtovr_inst_24 = w_cru_rtovr_inst[rtovr_idx];
            25: assign dbg_cru_rtovr_inst_25 = w_cru_rtovr_inst[rtovr_idx];
            26: assign dbg_cru_rtovr_inst_26 = w_cru_rtovr_inst[rtovr_idx];
            27: assign dbg_cru_rtovr_inst_27 = w_cru_rtovr_inst[rtovr_idx];
            28: assign dbg_cru_rtovr_inst_28 = w_cru_rtovr_inst[rtovr_idx];
            29: assign dbg_cru_rtovr_inst_29 = w_cru_rtovr_inst[rtovr_idx];
            30: assign dbg_cru_rtovr_inst_30 = w_cru_rtovr_inst[rtovr_idx];
            31: assign dbg_cru_rtovr_inst_31 = w_cru_rtovr_inst[rtovr_idx];
            32: assign dbg_cru_rtovr_inst_32 = w_cru_rtovr_inst[rtovr_idx];
            33: assign dbg_cru_rtovr_inst_33 = w_cru_rtovr_inst[rtovr_idx];
            34: assign dbg_cru_rtovr_inst_34 = w_cru_rtovr_inst[rtovr_idx];
            35: assign dbg_cru_rtovr_inst_35 = w_cru_rtovr_inst[rtovr_idx];
            36: assign dbg_cru_rtovr_inst_36 = w_cru_rtovr_inst[rtovr_idx];
            37: assign dbg_cru_rtovr_inst_37 = w_cru_rtovr_inst[rtovr_idx];
            38: assign dbg_cru_rtovr_inst_38 = w_cru_rtovr_inst[rtovr_idx];
            39: assign dbg_cru_rtovr_inst_39 = w_cru_rtovr_inst[rtovr_idx];
            default: ; // No assignment for invalid rtovr_idx
        endcase
    end
endgenerate

// ==========================================================================
// UR CRU Signal Assignment (ID 14-21)
// w_cru_ur[159:0] is concatenated from 8 UR smi_iq outputs:
//   - UR-RDATA-x (ID 14-17): DLY_WIDTH_12 = 12 bits each
//   - UR-WDATA-x (ID 18-21): DLY_WIDTH_28 = 28 bits each
// Concatenation order (MSB to LSB):
//   {ur_rdata_3, ur_rdata_2, ur_rdata_1, ur_rdata_0,
//    ur_wdata_3, ur_wdata_2, ur_wdata_1, ur_wdata_0}
// Total: 4*12 + 4*28 = 48 + 112 = 160 bits
// ==========================================================================
assign w_cru_ur = {w_cru_ur_rdata[3], w_cru_ur_rdata[2], w_cru_ur_rdata[1], w_cru_ur_rdata[0],
                   w_cru_ur_wdata[3], w_cru_ur_wdata[2], w_cru_ur_wdata[1], w_cru_ur_wdata[0]};

// ==========================================================================
// RtoVR CRU Signal Assignment (ID 24-63 -> out_idx 0-39)
// w_cru_rtovr[279:0] = {out_39[6:0], out_38[6:0], ..., out_1[6:0], out_0[6:0]}
// out_idx k corresponds to IQ ID (24+k), each DLY_WIDTH_7 = 7-bit
// Mapping matches mapping_table.txt
// ==========================================================================
integer rtovr_concat_idx;
always @(*) begin
    w_cru_rtovr = 280'b0;
    for (rtovr_concat_idx = 0; rtovr_concat_idx < 40; rtovr_concat_idx = rtovr_concat_idx + 1) begin
        w_cru_rtovr[rtovr_concat_idx*`DLY_WIDTH_7 +: `DLY_WIDTH_7] = w_cru_rtovr_inst[rtovr_concat_idx];
    end
end

// Unused CRU signals
assign w_cru_vin0 = 1'b0;
assign w_cru_vin1 = 1'b0;
assign w_cru_vout0 = 1'b0;

// ==========================================================================
// Combined inst_rdy for inst_rdy_in (all IQ ready signals)
// ==========================================================================
assign w_inst_rdy_all = {
    w_inst_rdy_rtovr,                                         // [63:24] - RtoVR (40 bits)
    w_inst_rdy_ldb,                                           // [23]    - LDB
    w_inst_rdy_stb,                                           // [22]    - STB
    w_inst_rdy_ur_wdata,                                      // [21:18] - UR-WDATA (4 bits)
    w_inst_rdy_ur_rdata,                                      // [17:14] - UR-RDATA (4 bits)
    w_inst_rdy_shiftdn,                                       // [13]    - SHIFTDN
    w_inst_rdy_shiftup,                                       // [12]    - SHIFTUP
    w_inst_rdy_logic,                                         // [11]    - LOGIC
    w_inst_rdy_inttofp,                                       // [10]    - INTtoFP
    w_inst_rdy_fptoint,                                       // [9]     - FPtoINT
    w_inst_rdy_inttoint,                                      // [8]     - INTtoINT
    w_inst_rdy_fptofp,                                        // [7]     - FPtoFP
    w_inst_rdy_fpadd,                                         // [6]     - FPADD
    w_inst_rdy_fpmul,                                         // [5]     - FPMUL
    w_inst_rdy_fp32addtree8to1,                               // [4]     - FP32ADDTREE8TO1
    w_inst_rdy_fp32addtree5to1,                               // [3]     - FP32ADDTREE5TO1
    w_inst_rdy_fp16mul,                                       // [2]     - FP16MUL
    w_inst_rdy_int8tofp16,                                    // [1]     - INT8toFP16
    w_inst_rdy_intadd                                         // [0]     - INTADD
};

/*************************************************** MODULE INSTANTIATIONS ****************************************************/

// ==========================================================================
// smi_iq: 64 Instruction Queue Modules (IDs 0-63)
// - ID 0-13:  Compute units (individual instantiation)
// - ID 14-17: UR-RDATA (loop instantiation)
// - ID 18-21: UR-WDATA (loop instantiation)
// - ID 22-23: STB/LDB (individual instantiation)
// - ID 24-63: RtoVR (loop instantiation)
// All interface signals are now per-IQ arrays
// ==========================================================================

// --------------------------------------------------------------------------
// ID 0: INTADD - Integer Addition/Subtraction, WR_INST_WIDTH=53
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_INTADD), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_intadd (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_intadd), .inst_keep(w_inst_keep_intadd),
    .inst_valid(w_inst_valid_intadd), .inst_id(w_inst_id_intadd),
    .inst_rdy(w_inst_rdy_intadd), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_INTADD]), .rdi_iqsid(rdi_iqsid[`IQ_ID_INTADD]),
    .rdi_done(rdi_done[`IQ_ID_INTADD]), .rdi_iqeid(rdi_iqeid[`IQ_ID_INTADD]),
    .wri_data(wri_data_intadd), .wri_vld(wri_vld[`IQ_ID_INTADD]),
    .wri_start(wri_start[`IQ_ID_INTADD]), .wri_end(wri_end[`IQ_ID_INTADD]), .wri_iqsid(wri_iqsid[`IQ_ID_INTADD])
);

// --------------------------------------------------------------------------
// ID 1: INT8toFP16 - INT8 to FP16 Conversion, WR_INST_WIDTH=43
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_INT8toFP16), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_int8tofp16 (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_int8tofp16), .inst_keep(w_inst_keep_int8tofp16),
    .inst_valid(w_inst_valid_int8tofp16), .inst_id(w_inst_id_int8tofp16),
    .inst_rdy(w_inst_rdy_int8tofp16), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_INT8toFP16]), .rdi_iqsid(rdi_iqsid[`IQ_ID_INT8toFP16]),
    .rdi_done(rdi_done[`IQ_ID_INT8toFP16]), .rdi_iqeid(rdi_iqeid[`IQ_ID_INT8toFP16]),
    .wri_data(wri_data_int8tofp16), .wri_vld(wri_vld[`IQ_ID_INT8toFP16]),
    .wri_start(wri_start[`IQ_ID_INT8toFP16]), .wri_end(wri_end[`IQ_ID_INT8toFP16]), .wri_iqsid(wri_iqsid[`IQ_ID_INT8toFP16])
);

// --------------------------------------------------------------------------
// ID 2: FP16MUL - FP16 Multiplication, WR_INST_WIDTH=50
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_FP16MUL), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_fp16mul (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_fp16mul), .inst_keep(w_inst_keep_fp16mul),
    .inst_valid(w_inst_valid_fp16mul), .inst_id(w_inst_id_fp16mul),
    .inst_rdy(w_inst_rdy_fp16mul), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_FP16MUL]), .rdi_iqsid(rdi_iqsid[`IQ_ID_FP16MUL]),
    .rdi_done(rdi_done[`IQ_ID_FP16MUL]), .rdi_iqeid(rdi_iqeid[`IQ_ID_FP16MUL]),
    .wri_data(wri_data_fp16mul), .wri_vld(wri_vld[`IQ_ID_FP16MUL]),
    .wri_start(wri_start[`IQ_ID_FP16MUL]), .wri_end(wri_end[`IQ_ID_FP16MUL]), .wri_iqsid(wri_iqsid[`IQ_ID_FP16MUL])
);

// --------------------------------------------------------------------------
// ID 3: FP32ADDTREE5TO1 - FP32 5-to-1 Addition Tree, WR_INST_WIDTH=42
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_FP32ADDTREE5TO1), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_fp32addtree5to1 (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_fp32addtree5to1), .inst_keep(w_inst_keep_fp32addtree5to1),
    .inst_valid(w_inst_valid_fp32addtree5to1), .inst_id(w_inst_id_fp32addtree5to1),
    .inst_rdy(w_inst_rdy_fp32addtree5to1), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_FP32ADDTREE5TO1]), .rdi_iqsid(rdi_iqsid[`IQ_ID_FP32ADDTREE5TO1]),
    .rdi_done(rdi_done[`IQ_ID_FP32ADDTREE5TO1]), .rdi_iqeid(rdi_iqeid[`IQ_ID_FP32ADDTREE5TO1]),
    .wri_data(wri_data_fp32addtree5to1), .wri_vld(wri_vld[`IQ_ID_FP32ADDTREE5TO1]),
    .wri_start(wri_start[`IQ_ID_FP32ADDTREE5TO1]), .wri_end(wri_end[`IQ_ID_FP32ADDTREE5TO1]), .wri_iqsid(wri_iqsid[`IQ_ID_FP32ADDTREE5TO1])
);

// --------------------------------------------------------------------------
// ID 4: FP32ADDTREE8TO1 - FP32 8-to-1 Addition Tree, WR_INST_WIDTH=44
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_FP32ADDTREE8TO1), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_fp32addtree8to1 (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_fp32addtree8to1), .inst_keep(w_inst_keep_fp32addtree8to1),
    .inst_valid(w_inst_valid_fp32addtree8to1), .inst_id(w_inst_id_fp32addtree8to1),
    .inst_rdy(w_inst_rdy_fp32addtree8to1), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_FP32ADDTREE8TO1]), .rdi_iqsid(rdi_iqsid[`IQ_ID_FP32ADDTREE8TO1]),
    .rdi_done(rdi_done[`IQ_ID_FP32ADDTREE8TO1]), .rdi_iqeid(rdi_iqeid[`IQ_ID_FP32ADDTREE8TO1]),
    .wri_data(wri_data_fp32addtree8to1), .wri_vld(wri_vld[`IQ_ID_FP32ADDTREE8TO1]),
    .wri_start(wri_start[`IQ_ID_FP32ADDTREE8TO1]), .wri_end(wri_end[`IQ_ID_FP32ADDTREE8TO1]), .wri_iqsid(wri_iqsid[`IQ_ID_FP32ADDTREE8TO1])
);

// --------------------------------------------------------------------------
// ID 5: FPMUL - FP32 Multiplication, WR_INST_WIDTH=44
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_FPMUL), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_fpmul (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_fpmul), .inst_keep(w_inst_keep_fpmul),
    .inst_valid(w_inst_valid_fpmul), .inst_id(w_inst_id_fpmul),
    .inst_rdy(w_inst_rdy_fpmul), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_FPMUL]), .rdi_iqsid(rdi_iqsid[`IQ_ID_FPMUL]),
    .rdi_done(rdi_done[`IQ_ID_FPMUL]), .rdi_iqeid(rdi_iqeid[`IQ_ID_FPMUL]),
    .wri_data(wri_data_fpmul), .wri_vld(wri_vld[`IQ_ID_FPMUL]),
    .wri_start(wri_start[`IQ_ID_FPMUL]), .wri_end(wri_end[`IQ_ID_FPMUL]), .wri_iqsid(wri_iqsid[`IQ_ID_FPMUL])
);

// --------------------------------------------------------------------------
// ID 6: FPADD - FP32 Addition/Subtraction, WR_INST_WIDTH=46
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_FPADD), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_fpadd (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_fpadd), .inst_keep(w_inst_keep_fpadd),
    .inst_valid(w_inst_valid_fpadd), .inst_id(w_inst_id_fpadd),
    .inst_rdy(w_inst_rdy_fpadd), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_FPADD]), .rdi_iqsid(rdi_iqsid[`IQ_ID_FPADD]),
    .rdi_done(rdi_done[`IQ_ID_FPADD]), .rdi_iqeid(rdi_iqeid[`IQ_ID_FPADD]),
    .wri_data(wri_data_fpadd), .wri_vld(wri_vld[`IQ_ID_FPADD]),
    .wri_start(wri_start[`IQ_ID_FPADD]), .wri_end(wri_end[`IQ_ID_FPADD]), .wri_iqsid(wri_iqsid[`IQ_ID_FPADD])
);

// --------------------------------------------------------------------------
// ID 7: FPtoFP - FP Format Conversion, WR_INST_WIDTH=46
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_FPtoFP), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_fptofp (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_fptofp), .inst_keep(w_inst_keep_fptofp),
    .inst_valid(w_inst_valid_fptofp), .inst_id(w_inst_id_fptofp),
    .inst_rdy(w_inst_rdy_fptofp), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_FPtoFP]), .rdi_iqsid(rdi_iqsid[`IQ_ID_FPtoFP]),
    .rdi_done(rdi_done[`IQ_ID_FPtoFP]), .rdi_iqeid(rdi_iqeid[`IQ_ID_FPtoFP]),
    .wri_data(wri_data_fptofp), .wri_vld(wri_vld[`IQ_ID_FPtoFP]),
    .wri_start(wri_start[`IQ_ID_FPtoFP]), .wri_end(wri_end[`IQ_ID_FPtoFP]), .wri_iqsid(wri_iqsid[`IQ_ID_FPtoFP])
);

// --------------------------------------------------------------------------
// ID 8: INTtoINT - Integer Format Conversion, WR_INST_WIDTH=48
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_INTtoINT), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_inttoint (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_inttoint), .inst_keep(w_inst_keep_inttoint),
    .inst_valid(w_inst_valid_inttoint), .inst_id(w_inst_id_inttoint),
    .inst_rdy(w_inst_rdy_inttoint), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_INTtoINT]), .rdi_iqsid(rdi_iqsid[`IQ_ID_INTtoINT]),
    .rdi_done(rdi_done[`IQ_ID_INTtoINT]), .rdi_iqeid(rdi_iqeid[`IQ_ID_INTtoINT]),
    .wri_data(wri_data_inttoint), .wri_vld(wri_vld[`IQ_ID_INTtoINT]),
    .wri_start(wri_start[`IQ_ID_INTtoINT]), .wri_end(wri_end[`IQ_ID_INTtoINT]), .wri_iqsid(wri_iqsid[`IQ_ID_INTtoINT])
);

// --------------------------------------------------------------------------
// ID 9: FPtoINT - FP to Integer Conversion, WR_INST_WIDTH=46
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_FPtoINT), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_fptoint (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_fptoint), .inst_keep(w_inst_keep_fptoint),
    .inst_valid(w_inst_valid_fptoint), .inst_id(w_inst_id_fptoint),
    .inst_rdy(w_inst_rdy_fptoint), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_FPtoINT]), .rdi_iqsid(rdi_iqsid[`IQ_ID_FPtoINT]),
    .rdi_done(rdi_done[`IQ_ID_FPtoINT]), .rdi_iqeid(rdi_iqeid[`IQ_ID_FPtoINT]),
    .wri_data(wri_data_fptoint), .wri_vld(wri_vld[`IQ_ID_FPtoINT]),
    .wri_start(wri_start[`IQ_ID_FPtoINT]), .wri_end(wri_end[`IQ_ID_FPtoINT]), .wri_iqsid(wri_iqsid[`IQ_ID_FPtoINT])
);

// --------------------------------------------------------------------------
// ID 10: INTtoFP - Integer to FP Conversion, WR_INST_WIDTH=47
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_INTtoFP), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_inttofp (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_inttofp), .inst_keep(w_inst_keep_inttofp),
    .inst_valid(w_inst_valid_inttofp), .inst_id(w_inst_id_inttofp),
    .inst_rdy(w_inst_rdy_inttofp), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_INTtoFP]), .rdi_iqsid(rdi_iqsid[`IQ_ID_INTtoFP]),
    .rdi_done(rdi_done[`IQ_ID_INTtoFP]), .rdi_iqeid(rdi_iqeid[`IQ_ID_INTtoFP]),
    .wri_data(wri_data_inttofp), .wri_vld(wri_vld[`IQ_ID_INTtoFP]),
    .wri_start(wri_start[`IQ_ID_INTtoFP]), .wri_end(wri_end[`IQ_ID_INTtoFP]), .wri_iqsid(wri_iqsid[`IQ_ID_INTtoFP])
);

// --------------------------------------------------------------------------
// ID 11: LOGIC - Logical Operations, WR_INST_WIDTH=47
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_LOGIC), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_logic (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_logic), .inst_keep(w_inst_keep_logic),
    .inst_valid(w_inst_valid_logic), .inst_id(w_inst_id_logic),
    .inst_rdy(w_inst_rdy_logic), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_LOGIC]), .rdi_iqsid(rdi_iqsid[`IQ_ID_LOGIC]),
    .rdi_done(rdi_done[`IQ_ID_LOGIC]), .rdi_iqeid(rdi_iqeid[`IQ_ID_LOGIC]),
    .wri_data(wri_data_logic), .wri_vld(wri_vld[`IQ_ID_LOGIC]),
    .wri_start(wri_start[`IQ_ID_LOGIC]), .wri_end(wri_end[`IQ_ID_LOGIC]), .wri_iqsid(wri_iqsid[`IQ_ID_LOGIC])
);

// --------------------------------------------------------------------------
// ID 12: SHIFTUP - Shift Up Operation, WR_INST_WIDTH=176
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_SHIFTUP), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_shiftup (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_shiftup), .inst_keep(w_inst_keep_shiftup),
    .inst_valid(w_inst_valid_shiftup), .inst_id(w_inst_id_shiftup),
    .inst_rdy(w_inst_rdy_shiftup), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_SHIFTUP]), .rdi_iqsid(rdi_iqsid[`IQ_ID_SHIFTUP]),
    .rdi_done(rdi_done[`IQ_ID_SHIFTUP]), .rdi_iqeid(rdi_iqeid[`IQ_ID_SHIFTUP]),
    .wri_data(wri_data_shiftup), .wri_vld(wri_vld[`IQ_ID_SHIFTUP]),
    .wri_start(wri_start[`IQ_ID_SHIFTUP]), .wri_end(wri_end[`IQ_ID_SHIFTUP]), .wri_iqsid(wri_iqsid[`IQ_ID_SHIFTUP])
);

// --------------------------------------------------------------------------
// ID 13: SHIFTDN - Shift Down Operation, WR_INST_WIDTH=175
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_SHIFTDN), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_shiftdn (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_shiftdn), .inst_keep(w_inst_keep_shiftdn),
    .inst_valid(w_inst_valid_shiftdn), .inst_id(w_inst_id_shiftdn),
    .inst_rdy(w_inst_rdy_shiftdn), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_SHIFTDN]), .rdi_iqsid(rdi_iqsid[`IQ_ID_SHIFTDN]),
    .rdi_done(rdi_done[`IQ_ID_SHIFTDN]), .rdi_iqeid(rdi_iqeid[`IQ_ID_SHIFTDN]),
    .wri_data(wri_data_shiftdn), .wri_vld(wri_vld[`IQ_ID_SHIFTDN]),
    .wri_start(wri_start[`IQ_ID_SHIFTDN]), .wri_end(wri_end[`IQ_ID_SHIFTDN]), .wri_iqsid(wri_iqsid[`IQ_ID_SHIFTDN])
);

// --------------------------------------------------------------------------
// ID 14-17: UR-RDATA - User Register Read Data (4 instances, loop), WR_INST_WIDTH=53
// --------------------------------------------------------------------------
genvar ur_rdata_idx;
generate
    for (ur_rdata_idx = 0; ur_rdata_idx < 4; ur_rdata_idx = ur_rdata_idx + 1) begin : gen_smi_iq_ur_rdata
        smi_iq #(.PARA_IQ_ID(`IQ_ID_UR_RDATA_0 + ur_rdata_idx), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_ur_rdata (
            .clk(clk), .rst_n(rst_n),
            .inst(w_inst_ur_rdata[ur_rdata_idx]), .inst_keep(w_inst_keep_ur_rdata[ur_rdata_idx]),
            .inst_valid(w_inst_valid_ur_rdata[ur_rdata_idx]), .inst_id(w_inst_id_ur_rdata[ur_rdata_idx]),
            .inst_rdy(w_inst_rdy_ur_rdata[ur_rdata_idx]), .inst_rdy_in(w_inst_rdy_all),
            .rdi_start(rdi_start[`IQ_ID_UR_RDATA_0 + ur_rdata_idx]), .rdi_iqsid(rdi_iqsid[`IQ_ID_UR_RDATA_0 + ur_rdata_idx]),
            .rdi_done(rdi_done[`IQ_ID_UR_RDATA_0 + ur_rdata_idx]), .rdi_iqeid(rdi_iqeid[`IQ_ID_UR_RDATA_0 + ur_rdata_idx]),
            .wri_data(wri_data_ur_rdata[ur_rdata_idx]), .wri_vld(wri_vld[`IQ_ID_UR_RDATA_0 + ur_rdata_idx]),
            .wri_start(wri_start[`IQ_ID_UR_RDATA_0 + ur_rdata_idx]), .wri_end(wri_end[`IQ_ID_UR_RDATA_0 + ur_rdata_idx]), .wri_iqsid(wri_iqsid[`IQ_ID_UR_RDATA_0 + ur_rdata_idx])
        );
    end
endgenerate

// --------------------------------------------------------------------------
// ID 18-21: UR-WDATA - User Register Write Data (4 instances, loop), WR_INST_WIDTH=69
// --------------------------------------------------------------------------
genvar ur_wdata_idx;
generate
    for (ur_wdata_idx = 0; ur_wdata_idx < 4; ur_wdata_idx = ur_wdata_idx + 1) begin : gen_smi_iq_ur_wdata
        smi_iq #(.PARA_IQ_ID(`IQ_ID_UR_WDATA_0 + ur_wdata_idx), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_ur_wdata (
            .clk(clk), .rst_n(rst_n),
            .inst(w_inst_ur_wdata[ur_wdata_idx]), .inst_keep(w_inst_keep_ur_wdata[ur_wdata_idx]),
            .inst_valid(w_inst_valid_ur_wdata[ur_wdata_idx]), .inst_id(w_inst_id_ur_wdata[ur_wdata_idx]),
            .inst_rdy(w_inst_rdy_ur_wdata[ur_wdata_idx]), .inst_rdy_in(w_inst_rdy_all),
            .rdi_start(rdi_start[`IQ_ID_UR_WDATA_0 + ur_wdata_idx]), .rdi_iqsid(rdi_iqsid[`IQ_ID_UR_WDATA_0 + ur_wdata_idx]),
            .rdi_done(rdi_done[`IQ_ID_UR_WDATA_0 + ur_wdata_idx]), .rdi_iqeid(rdi_iqeid[`IQ_ID_UR_WDATA_0 + ur_wdata_idx]),
            .wri_data(wri_data_ur_wdata[ur_wdata_idx]), .wri_vld(wri_vld[`IQ_ID_UR_WDATA_0 + ur_wdata_idx]),
            .wri_start(wri_start[`IQ_ID_UR_WDATA_0 + ur_wdata_idx]), .wri_end(wri_end[`IQ_ID_UR_WDATA_0 + ur_wdata_idx]), .wri_iqsid(wri_iqsid[`IQ_ID_UR_WDATA_0 + ur_wdata_idx])
        );
    end
endgenerate

// --------------------------------------------------------------------------
// ID 22: STB - Store Buffer, WR_INST_WIDTH=112
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_STB), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_stb (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_stb), .inst_keep(w_inst_keep_stb),
    .inst_valid(w_inst_valid_stb), .inst_id(w_inst_id_stb),
    .inst_rdy(w_inst_rdy_stb), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_STB]), .rdi_iqsid(rdi_iqsid[`IQ_ID_STB]),
    .rdi_done(rdi_done[`IQ_ID_STB]), .rdi_iqeid(rdi_iqeid[`IQ_ID_STB]),
    .wri_data(wri_data_stb), .wri_vld(wri_vld[`IQ_ID_STB]),
    .wri_start(wri_start[`IQ_ID_STB]), .wri_end(wri_end[`IQ_ID_STB]), .wri_iqsid(wri_iqsid[`IQ_ID_STB])
);

// --------------------------------------------------------------------------
// ID 23: LDB - Load Buffer, WR_INST_WIDTH=112
// --------------------------------------------------------------------------
smi_iq #(.PARA_IQ_ID(`IQ_ID_LDB), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_ldb (
    .clk(clk), .rst_n(rst_n),
    .inst(w_inst_ldb), .inst_keep(w_inst_keep_ldb),
    .inst_valid(w_inst_valid_ldb), .inst_id(w_inst_id_ldb),
    .inst_rdy(w_inst_rdy_ldb), .inst_rdy_in(w_inst_rdy_all),
    .rdi_start(rdi_start[`IQ_ID_LDB]), .rdi_iqsid(rdi_iqsid[`IQ_ID_LDB]),
    .rdi_done(rdi_done[`IQ_ID_LDB]), .rdi_iqeid(rdi_iqeid[`IQ_ID_LDB]),
    .wri_data(wri_data_ldb), .wri_vld(wri_vld[`IQ_ID_LDB]),
    .wri_start(wri_start[`IQ_ID_LDB]), .wri_end(wri_end[`IQ_ID_LDB]), .wri_iqsid(wri_iqsid[`IQ_ID_LDB])
);

// --------------------------------------------------------------------------
// ID 24-63: RtoVR - Register to Vector Register Routing (40 instances, loop), WR_INST_WIDTH=48
// --------------------------------------------------------------------------
genvar rtovr_inst_idx;
generate
    for (rtovr_inst_idx = 0; rtovr_inst_idx < 40; rtovr_inst_idx = rtovr_inst_idx + 1) begin : gen_smi_iq_rtovr
        smi_iq #(.PARA_IQ_ID(`IQ_ID_RTOVR_BASE + rtovr_inst_idx), .SMI_IQ_AMOUNT(SMI_IQ_AMOUNT), .EN_COND(0)) u_smi_iq_rtovr (
            .clk(clk), .rst_n(rst_n),
            .inst(w_inst_rtovr[rtovr_inst_idx]), .inst_keep(w_inst_keep_rtovr[rtovr_inst_idx]),
            .inst_valid(w_inst_valid_rtovr[rtovr_inst_idx]), .inst_id(w_inst_id_rtovr[rtovr_inst_idx]),
            .inst_rdy(w_inst_rdy_rtovr[rtovr_inst_idx]), .inst_rdy_in(w_inst_rdy_all),
            .rdi_start(rdi_start[`IQ_ID_RTOVR_BASE + rtovr_inst_idx]), .rdi_iqsid(rdi_iqsid[`IQ_ID_RTOVR_BASE + rtovr_inst_idx]),
            .rdi_done(rdi_done[`IQ_ID_RTOVR_BASE + rtovr_inst_idx]), .rdi_iqeid(rdi_iqeid[`IQ_ID_RTOVR_BASE + rtovr_inst_idx]),
            .wri_data(wri_data_rtovr[rtovr_inst_idx]), .wri_vld(wri_vld[`IQ_ID_RTOVR_BASE + rtovr_inst_idx]),
            .wri_start(wri_start[`IQ_ID_RTOVR_BASE + rtovr_inst_idx]), .wri_end(wri_end[`IQ_ID_RTOVR_BASE + rtovr_inst_idx]), .wri_iqsid(wri_iqsid[`IQ_ID_RTOVR_BASE + rtovr_inst_idx])
        );
    end
endgenerate

// ==========================================================================
// SMC: Stream Multiprocessor Compute Unit
// ==========================================================================
SMC #(
    .SMC_ID              (SMC_ID),
    .IEEE_754            (IEEE_754)
) u_smc (
    .clk                 (clk),
    .rst_n               (rst_n),
    .i_smc_id            (i_smc_id),
    .i_rounding_mode     (i_rounding_mode),
    .cru_intadd          (w_cru_intadd),
    .cru_fp16mul         (w_cru_fp16mul),
    .cru_fp16mul_s0123   (w_cru_fp16mul_s0123),
    .cru_fp16mul_s4567   (w_cru_fp16mul_s4567),
    .cru_fp32addtree5to1 (w_cru_fp32addtree5to1),
    .cru_fp32addtree8to1 (w_cru_fp32addtree8to1),
    .cru_fpadd           (w_cru_fpadd),
    .cru_fpmul           (w_cru_fpmul),
    .cru_fptoint         (w_cru_fptoint),
    .cru_fptofp          (w_cru_fptofp),
    .cru_inttoint        (w_cru_inttoint),
    .cru_inttofp         (w_cru_inttofp),
    .cru_logic           (w_cru_logic),
    .cru_int8tofp16      (w_cru_int8tofp16),
    .cru_shiftup         (w_cru_shiftup),
    .crd_shiftdn         (w_crd_shiftdn),
    .cru_rtovr           (w_cru_rtovr),
    .cru_ur              (w_cru_ur),
    .cru_vin0            (w_cru_vin0),
    .cru_vin1            (w_cru_vin1),
    .cru_vout0           (w_cru_vout0),
    .crd_shiftdn_out     (crd_shiftdn_out),
    .cru_fpadd_o         (cru_fpadd_o),
    .cru_fpmul_o         (cru_fpmul_o),
    .cru_inttoint_o      (cru_inttoint_o),
    .cru_inttofp_o       (cru_inttofp_o),
    .cru_logic_o         (cru_logic_o),
    .cru_intadd_o        (cru_intadd_o),
    .cru_shiftup_o       (cru_shiftup_o),
    .cru_rtovr_o         (cru_rtovr_o),
    .cru_ur_o            (cru_ur_o),
    .cru_vin0_o          (cru_vin0_o),
    .cru_vin1_o          (cru_vin1_o),
    .cru_vout0_o         (cru_vout0_o)
);

endmodule

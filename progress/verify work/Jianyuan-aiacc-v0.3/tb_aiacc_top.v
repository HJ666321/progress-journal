/*****************************************************************************
** Project  :  AIACC NPU                                                     **
******************************************************************************
**                                      **                                  **
** File name:  tb_aiacc_top.v               **             AIACC Team          **
** Designer :  AIACC RTL Generator      **  NPU Design Division            **
**                                      **                                  **
******************************************************************************
******************************************************************************
**                                                                          **
** Module Description:                                                      **
**                                                                          **
** Testbench for aiacc_top module                                          **
**                                                                          **
** This testbench tests the integration of SMC and smi_iq modules.          **
** It uses INTADD instruction queue (ID = 0) and tests INTADD              **
** functionality with fixed input data values.                             **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
**   Revision        Date            By               Reason                **
** ------------   ------------   ------------      ------------             **
**     1.0                                           Creation               **
**     2.0                                           Update for new DUT     **
**                                                                          **
*****************************************************************************/
`timescale 1ns/1ps

// ==========================================================================
// SMI-IQ ID Definitions (copied from aiacc_top.v)
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
// Memory data path: load from test_atomic_ops/<MEM_DATA_SUBFOLDER>/<DATA_LIST_FILE>
// ==========================================================================
`ifndef MEM_DATA_BASE
`define MEM_DATA_BASE "/datahdd/qinglongv200/xuedong/AIACC/Hongjun-main/aiacc/cells/A_Integration/test_atomic_ops"
`endif
`ifndef MEM_DATA_SUBFOLDER
`define MEM_DATA_SUBFOLDER "fpadd"
`endif
`ifndef DATA_LIST_FILE
`define DATA_LIST_FILE "data_list.txt"
`endif

// ==========================================================================
// DLY_INST_WIDTH Definitions (= BIT_CODE)
// ==========================================================================
`define DLY_WIDTH_1            1    // FP32ADDTREE5TO1
`define DLY_WIDTH_2            2    // INT8toFP16
`define DLY_WIDTH_3            3    // FP32ADDTREE8TO1, FPMUL
`define DLY_WIDTH_4            4    // FPADD
`define DLY_WIDTH_5            5    // FPtoFP, FPtoINT
`define DLY_WIDTH_6            6    // INTtoFP, LOGIC
`define DLY_WIDTH_7            7    // INTtoINT, RtoVR
`define DLY_WIDTH_9            9    // FP16MUL
`define DLY_WIDTH_12           12   // UR-RDATA
`define DLY_WIDTH_13           13   // INTADD (13-bit: bit 12 is sub_en)
`define DLY_WIDTH_28           28   // UR-WDATA
`define DLY_WIDTH_71           71   // STB, LDB
`define DLY_WIDTH_134          134  // SHIFTDN
`define DLY_WIDTH_135          135  // SHIFTUP
`define DLY_WIDTH_MAX          135  // Maximum

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

// Instruction memory width for wide IQs (others use 64-bit)
// SHIFTUP/SHIFTDN: WR_DATA 176/175 -> mem 256-bit; STB/LDB: WR_DATA 112 -> mem 128-bit
`define INST_MEM_SHIFTUP_W         256  // ID 12: SHIFTUP inst mem width
`define INST_MEM_SHIFTDN_W         256  // ID 13: SHIFTDN inst mem width
`define INST_MEM_STB_W             128  // ID 22: STB inst mem width
`define INST_MEM_LDB_W             128  // ID 23: LDB inst mem width

module tb_aiacc_top;

// ==========================================================================
// Parameters
// ==========================================================================
parameter CLK_PERIOD = 10;  // 10ns = 100MHz
parameter SMC_ID = 5'd0;
parameter SMI_IQ_AMOUNT = `SMI_IQ_CNT;  // Use macro definition

// ==========================================================================
// Clock and Reset
// ==========================================================================
reg clk;
reg rst_n;

// ==========================================================================
// DUT Signals
// ==========================================================================
// SMC Identification
reg  [4:0]  i_smc_id;
reg  [2:0]  i_rounding_mode;

// smi_iq Write Instruction Data (per IQ, different widths)
reg  [`WR_DATA_INTADD_W-1:0]           wri_data_intadd;
reg  [`WR_DATA_INT8toFP16_W-1:0]      wri_data_int8tofp16;
reg  [`WR_DATA_FP16MUL_W-1:0]         wri_data_fp16mul;
reg  [`WR_DATA_FP32ADDTREE5TO1_W-1:0] wri_data_fp32addtree5to1;
reg  [`WR_DATA_FP32ADDTREE8TO1_W-1:0] wri_data_fp32addtree8to1;
reg  [`WR_DATA_FPMUL_W-1:0]           wri_data_fpmul;
reg  [`WR_DATA_FPADD_W-1:0]           wri_data_fpadd;
reg  [`WR_DATA_FPtoFP_W-1:0]          wri_data_fptofp;
reg  [`WR_DATA_INTtoINT_W-1:0]        wri_data_inttoint;
reg  [`WR_DATA_FPtoINT_W-1:0]         wri_data_fptoint;
reg  [`WR_DATA_INTtoFP_W-1:0]        wri_data_inttofp;
reg  [`WR_DATA_LOGIC_W-1:0]          wri_data_logic;
reg  [`WR_DATA_SHIFTUP_W-1:0]         wri_data_shiftup;
reg  [`WR_DATA_SHIFTDN_W-1:0]         wri_data_shiftdn;
reg  [`WR_DATA_UR_RDATA_W-1:0]        wri_data_ur_rdata [3:0];   // ID 14-17
reg  [`WR_DATA_UR_WDATA_W-1:0]        wri_data_ur_wdata [3:0];   // ID 18-21
reg  [`WR_DATA_STB_W-1:0]             wri_data_stb;
reg  [`WR_DATA_LDB_W-1:0]             wri_data_ldb;
reg  [`WR_DATA_RTOVR_W-1:0]           wri_data_rtovr [39:0];

// smi_iq Write Control (per IQ arrays)
reg  [SMI_IQ_AMOUNT-1:0] wri_vld;
reg  [SMI_IQ_AMOUNT-1:0] wri_start;
reg  [SMI_IQ_AMOUNT-1:0] wri_end;
reg  [1:0]               wri_iqsid [SMI_IQ_AMOUNT-1:0];

// smi_iq Read Control (per IQ arrays)
reg  [SMI_IQ_AMOUNT-1:0] rdi_start;
reg  [1:0]               rdi_iqsid [SMI_IQ_AMOUNT-1:0];
wire [SMI_IQ_AMOUNT-1:0] rdi_done;
wire [1:0]               rdi_iqeid [SMI_IQ_AMOUNT-1:0];

// ==========================================================================
// Instruction Memory for each IQ (64-bit default; SHIFTUP/SHIFTDN 256-bit, STB/LDB 128-bit)
// ==========================================================================
// ID 0-13: Compute Units (64-bit)
reg  [63:0] inst_mem_intadd          [0:31];  // ID 0: INTADD
reg  [63:0] inst_mem_int8tofp16      [0:31];  // ID 1: INT8toFP16
reg  [63:0] inst_mem_fp16mul         [0:31];  // ID 2: FP16MUL
reg  [63:0] inst_mem_fp32addtree5to1 [0:31];  // ID 3: FP32ADDTREE5TO1
reg  [63:0] inst_mem_fp32addtree8to1 [0:31];  // ID 4: FP32ADDTREE8TO1
reg  [63:0] inst_mem_fpmul           [0:31];  // ID 5: FPMUL
reg  [63:0] inst_mem_fpadd           [0:31];  // ID 6: FPADD
reg  [63:0] inst_mem_fptofp          [0:31];  // ID 7: FPtoFP
reg  [63:0] inst_mem_inttoint        [0:31];  // ID 8: INTtoINT
reg  [63:0] inst_mem_fptoint         [0:31];  // ID 9: FPtoINT
reg  [63:0] inst_mem_inttofp         [0:31];  // ID 10: INTtoFP
reg  [63:0] inst_mem_logic           [0:31];  // ID 11: LOGIC
reg  [`INST_MEM_SHIFTUP_W-1:0] inst_mem_shiftup [0:31];  // ID 12: SHIFTUP, 256-bit
reg  [`INST_MEM_SHIFTDN_W-1:0] inst_mem_shiftdn [0:31];  // ID 13: SHIFTDN, 256-bit

// ID 14-17: UR-RDATA
reg  [63:0] inst_mem_ur_rdata_0      [0:31];  // ID 14: UR-RDATA-0
reg  [63:0] inst_mem_ur_rdata_1      [0:31];  // ID 15: UR-RDATA-1
reg  [63:0] inst_mem_ur_rdata_2      [0:31];  // ID 16: UR-RDATA-2
reg  [63:0] inst_mem_ur_rdata_3      [0:31];  // ID 17: UR-RDATA-3

// ID 18-21: UR-WDATA
reg  [68:0] inst_mem_ur_wdata_0      [0:31];  // ID 18: UR-WDATA-0, 69 bits
reg  [68:0] inst_mem_ur_wdata_1      [0:31];  // ID 19: UR-WDATA-1, 69 bits
reg  [68:0] inst_mem_ur_wdata_2      [0:31];  // ID 20: UR-WDATA-2, 69 bits
reg  [68:0] inst_mem_ur_wdata_3      [0:31];  // ID 21: UR-WDATA-3, 69 bits

// ID 22-23: STB, LDB (128-bit)
reg  [`INST_MEM_STB_W-1:0] inst_mem_stb [0:31];  // ID 22: STB
reg  [`INST_MEM_LDB_W-1:0] inst_mem_ldb [0:31];  // ID 23: LDB

// ID 24-63: RtoVR (40 instances)
reg  [63:0] inst_mem_rtovr [0:39]    [0:31];  // ID 24-63: RtoVR-0 to RtoVR-39
reg  [63:0] temp_rtovr_mem [0:31];  // Temporary 1D array for loading hex files into 2D array

// Instruction count for each IQ
integer inst_count_intadd, inst_count_int8tofp16, inst_count_fp16mul;
integer inst_count_fp32addtree5to1, inst_count_fp32addtree8to1;
integer inst_count_fpmul, inst_count_fpadd, inst_count_fptofp;
integer inst_count_inttoint, inst_count_fptoint, inst_count_inttofp;
integer inst_count_logic, inst_count_shiftup, inst_count_shiftdn;
integer inst_count_ur_rdata [0:3];
integer inst_count_ur_wdata [0:3];
integer inst_count_stb, inst_count_ldb;
integer inst_count_rtovr [0:39];

integer inst_idx;    // Current instruction index
integer iq_idx;      // IQ index for loops

// SMC CRU Outputs
wire [133:0] crd_shiftdn_out;
wire [4:0]   cru_fpadd_o;
wire [2:0]   cru_fpmul_o;
wire [6:0]   cru_inttoint_o;
wire [5:0]   cru_inttofp_o;
wire [5:0]   cru_logic_o;
wire [12:0]  cru_intadd_o;
wire [134:0] cru_shiftup_o;
wire [279:0] cru_rtovr_o;
wire [160:0] cru_ur_o;
wire         cru_vin0_o;
wire         cru_vin1_o;
wire         cru_vout0_o;

// Test data variables removed (no longer needed for INTADD testing)

// ==========================================================================
// DUT Instantiation
// ==========================================================================
aiacc_top #(
    .SMC_ID              (SMC_ID),
    .IEEE_754            (0),
    .SUB_IQ_NUM          (4),
    .SMI_IQ_AMOUNT       (SMI_IQ_AMOUNT)
) dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .i_smc_id            (i_smc_id),
    .i_rounding_mode     (i_rounding_mode),
    
    // smi_iq Write Instruction Data (per IQ, different widths)
    .wri_data_intadd     (wri_data_intadd),
    .wri_data_int8tofp16 (wri_data_int8tofp16),
    .wri_data_fp16mul    (wri_data_fp16mul),
    .wri_data_fp32addtree5to1 (wri_data_fp32addtree5to1),
    .wri_data_fp32addtree8to1 (wri_data_fp32addtree8to1),
    .wri_data_fpmul      (wri_data_fpmul),
    .wri_data_fpadd      (wri_data_fpadd),
    .wri_data_fptofp     (wri_data_fptofp),
    .wri_data_inttoint   (wri_data_inttoint),
    .wri_data_fptoint    (wri_data_fptoint),
    .wri_data_inttofp    (wri_data_inttofp),
    .wri_data_logic      (wri_data_logic),
    .wri_data_shiftup    (wri_data_shiftup),
    .wri_data_shiftdn    (wri_data_shiftdn),
    .wri_data_ur_rdata   (wri_data_ur_rdata),
    .wri_data_ur_wdata   (wri_data_ur_wdata),
    .wri_data_stb        (wri_data_stb),
    .wri_data_ldb        (wri_data_ldb),
    .wri_data_rtovr      (wri_data_rtovr),
    
    // Write control (per IQ arrays)
    .wri_vld             (wri_vld),
    .wri_start           (wri_start),
    .wri_end             (wri_end),
    .wri_iqsid           (wri_iqsid),
    
    // Read control (per IQ arrays)
    .rdi_start           (rdi_start),
    .rdi_iqsid           (rdi_iqsid),
    .rdi_done            (rdi_done),
    .rdi_iqeid           (rdi_iqeid),
    
    // CRU Outputs
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

// ==========================================================================
// Clock Generation
// ==========================================================================
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// INTADD input data forcing removed (no longer needed)

// ==========================================================================
// Initialize wri_iqsid and rdi_iqsid arrays
// ==========================================================================
integer init_idx;
initial begin
    for (init_idx = 0; init_idx < SMI_IQ_AMOUNT; init_idx = init_idx + 1) begin
        wri_iqsid[init_idx] = 2'b00;
        rdi_iqsid[init_idx] = 2'b00;
    end
end

// ==========================================================================
// Test Sequence
// ==========================================================================
initial begin
    // Runtime parameters (read from plusarg, used throughout this initial block)
    string runtime_subfolder, runtime_data_list_file;
    string ur_dump_file0, ur_dump_file1, ur_dump_file2, ur_dump_file3, ur_dump_file4, ur_dump_file5, ur_dump_file6, ur_dump_file7;
    integer plusarg_ok;
    
    // 从 plusarg 读取运行时参数（覆盖编译时的宏定义）
    plusarg_ok = $value$plusargs("MEM_DATA_SUBFOLDER=%s", runtime_subfolder);
    if (plusarg_ok) begin
        $display("  [plusarg] MEM_DATA_SUBFOLDER = %s", runtime_subfolder);
    end else begin
        runtime_subfolder = `MEM_DATA_SUBFOLDER;
    end
    
    plusarg_ok = $value$plusargs("DATA_LIST_FILE=%s", runtime_data_list_file);
    if (plusarg_ok) begin
        $display("  [plusarg] DATA_LIST_FILE = %s", runtime_data_list_file);
    end else begin
        runtime_data_list_file = `DATA_LIST_FILE;
    end
    
    $display("==================================================");
    $display("Starting AIACC Top Testbench");
    $display("  - Loading instructions to all smi_iq (except UR)");
    $display("  - SMI_IQ_AMOUNT = %0d", SMI_IQ_AMOUNT);
    $display("==================================================");
    
    // Test data initialization removed (no longer needed)
    
    // Initialize signals
    rst_n = 0;
    i_smc_id = SMC_ID;
    i_rounding_mode = 3'b000;  // RNE
    
    // smi_iq Write Interface (all IQs) - Initialize all wri_data to 0
    wri_data_intadd = {`WR_DATA_INTADD_W{1'b0}};
    wri_data_int8tofp16 = {`WR_DATA_INT8toFP16_W{1'b0}};
    wri_data_fp16mul = {`WR_DATA_FP16MUL_W{1'b0}};
    wri_data_fp32addtree5to1 = {`WR_DATA_FP32ADDTREE5TO1_W{1'b0}};
    wri_data_fp32addtree8to1 = {`WR_DATA_FP32ADDTREE8TO1_W{1'b0}};
    wri_data_fpmul = {`WR_DATA_FPMUL_W{1'b0}};
    wri_data_fpadd = {`WR_DATA_FPADD_W{1'b0}};
    wri_data_fptofp = {`WR_DATA_FPtoFP_W{1'b0}};
    wri_data_inttoint = {`WR_DATA_INTtoINT_W{1'b0}};
    wri_data_fptoint = {`WR_DATA_FPtoINT_W{1'b0}};
    wri_data_inttofp = {`WR_DATA_INTtoFP_W{1'b0}};
    wri_data_logic = {`WR_DATA_LOGIC_W{1'b0}};
    wri_data_shiftup = {`WR_DATA_SHIFTUP_W{1'b0}};
    wri_data_shiftdn = {`WR_DATA_SHIFTDN_W{1'b0}};
    for (integer ur_idx = 0; ur_idx < 4; ur_idx = ur_idx + 1) begin
        wri_data_ur_rdata[ur_idx] = {`WR_DATA_UR_RDATA_W{1'b0}};
        wri_data_ur_wdata[ur_idx] = {`WR_DATA_UR_WDATA_W{1'b0}};
    end
    wri_data_stb = {`WR_DATA_STB_W{1'b0}};
    wri_data_ldb = {`WR_DATA_LDB_W{1'b0}};
    for (integer rtovr_idx = 0; rtovr_idx < 40; rtovr_idx = rtovr_idx + 1) begin
        wri_data_rtovr[rtovr_idx] = {`WR_DATA_RTOVR_W{1'b0}};
    end
    wri_vld = {SMI_IQ_AMOUNT{1'b0}};
    wri_start = {SMI_IQ_AMOUNT{1'b0}};
    wri_end = {SMI_IQ_AMOUNT{1'b0}};
    
    // smi_iq Read Control (all IQs)
    rdi_start = {SMI_IQ_AMOUNT{1'b0}};
    
    // ==========================================================================
    // Load Instructions and UR Bank from data_list file (test_atomic_ops/<MEM_DATA_SUBFOLDER>/<DATA_LIST_FILE>)
    // Format: mem_name absolute_path (one per line)；路径由 data_list 内容给出，可指向子目录如 smc_0 下的 hex
    // ==========================================================================
    begin
        integer fd_list;
        integer sp_pos, parse_i, trim_start, trim_end, rtovr_idx_parsed;
        string  list_path, line_str, mem_name_str, path_str;
        
        // 构建 data_list 文件路径；其中每行的 path 为绝对路径，tb 直接按 path 加载，无需再拼 smc_0
        list_path = $sformatf("%s/%s/%s", `MEM_DATA_BASE, runtime_subfolder, runtime_data_list_file);
        $display("\n--- Loading from data_list file (%s/%s/%s) ---", `MEM_DATA_BASE, runtime_subfolder, runtime_data_list_file);
        // Initialize all instruction memories and counts to zero
        inst_count_intadd = 0; inst_count_int8tofp16 = 0; inst_count_fp16mul = 0;
        inst_count_fp32addtree5to1 = 0; inst_count_fp32addtree8to1 = 0;
        inst_count_fpmul = 0; inst_count_fpadd = 0; inst_count_fptofp = 0;
        inst_count_inttoint = 0; inst_count_fptoint = 0; inst_count_inttofp = 0;
        inst_count_logic = 0; inst_count_shiftup = 0; inst_count_shiftdn = 0;
        for (iq_idx = 0; iq_idx < 4; iq_idx = iq_idx + 1) begin
            inst_count_ur_rdata[iq_idx] = 0;
            inst_count_ur_wdata[iq_idx] = 0;
        end
        inst_count_stb = 0; inst_count_ldb = 0;
        for (inst_idx = 0; inst_idx < 40; inst_idx = inst_idx + 1) inst_count_rtovr[inst_idx] = 0;
        for (inst_idx = 0; inst_idx < 32; inst_idx = inst_idx + 1) begin
            inst_mem_intadd[inst_idx] = 64'd0; inst_mem_int8tofp16[inst_idx] = 64'd0;
            inst_mem_fp16mul[inst_idx] = 64'd0; inst_mem_fp32addtree5to1[inst_idx] = 64'd0;
            inst_mem_fp32addtree8to1[inst_idx] = 64'd0; inst_mem_fpmul[inst_idx] = 64'd0;
            inst_mem_fpadd[inst_idx] = 64'd0; inst_mem_fptofp[inst_idx] = 64'd0;
            inst_mem_inttoint[inst_idx] = 64'd0; inst_mem_fptoint[inst_idx] = 64'd0;
            inst_mem_inttofp[inst_idx] = 64'd0; inst_mem_logic[inst_idx] = 64'd0;
            inst_mem_shiftup[inst_idx] = {`INST_MEM_SHIFTUP_W{1'b0}}; inst_mem_shiftdn[inst_idx] = {`INST_MEM_SHIFTDN_W{1'b0}};
            inst_mem_ur_rdata_0[inst_idx] = 64'd0; inst_mem_ur_rdata_1[inst_idx] = 64'd0;
            inst_mem_ur_rdata_2[inst_idx] = 64'd0; inst_mem_ur_rdata_3[inst_idx] = 64'd0;
            inst_mem_ur_wdata_0[inst_idx] = 69'd0; inst_mem_ur_wdata_1[inst_idx] = 69'd0;
            inst_mem_ur_wdata_2[inst_idx] = 69'd0; inst_mem_ur_wdata_3[inst_idx] = 69'd0;
            inst_mem_stb[inst_idx] = {`INST_MEM_STB_W{1'b0}}; inst_mem_ldb[inst_idx] = {`INST_MEM_LDB_W{1'b0}};
        end
        for (inst_idx = 0; inst_idx < 40; inst_idx = inst_idx + 1)
            for (iq_idx = 0; iq_idx < 32; iq_idx = iq_idx + 1)
                inst_mem_rtovr[inst_idx][iq_idx] = 64'd0;

        fd_list = $fopen(list_path, "r");
        if (fd_list == 0) begin
            $display("  ERROR: Cannot open data list: %s", list_path);
        end else begin
            while (!$feof(fd_list)) begin
                line_str = "";
                if ($fgets(line_str, fd_list) == 0) continue;
                if (line_str.len() == 0) continue;
                // Find first space to split mem_name and path
                sp_pos = -1;
                for (parse_i = 0; parse_i < line_str.len(); parse_i = parse_i + 1)
                    if (line_str.getc(parse_i) == 32) begin sp_pos = parse_i; parse_i = line_str.len(); end
                if (sp_pos <= 0) continue;
                mem_name_str = line_str.substr(0, sp_pos - 1);
                path_str = line_str.substr(sp_pos + 1, line_str.len() - 1);
                // Trim path: leading spaces
                trim_start = 0;
                for (parse_i = 0; parse_i < path_str.len(); parse_i = parse_i + 1)
                    if (path_str.getc(parse_i) != 32 && path_str.getc(parse_i) != 10 && path_str.getc(parse_i) != 13)
                        begin trim_start = parse_i; parse_i = path_str.len(); end
                trim_end = path_str.len() - 1;
                for (parse_i = path_str.len() - 1; parse_i >= 0; parse_i = parse_i - 1)
                    if (path_str.getc(parse_i) != 32 && path_str.getc(parse_i) != 10 && path_str.getc(parse_i) != 13)
                        begin trim_end = parse_i; parse_i = -1; end
                if (trim_start <= trim_end)
                    path_str = path_str.substr(trim_start, trim_end);

                // Dispatch by mem_name_str (each load prints one line)
                if (mem_name_str == "inst_mem_intadd") begin
                    $readmemh(path_str, inst_mem_intadd);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_int8tofp16") begin
                    $readmemh(path_str, inst_mem_int8tofp16);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_fp16mul") begin
                    $readmemh(path_str, inst_mem_fp16mul);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_fp32addtree5to1") begin
                    $readmemh(path_str, inst_mem_fp32addtree5to1);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_fp32addtree8to1") begin
                    $readmemh(path_str, inst_mem_fp32addtree8to1);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_fpmul") begin
                    $readmemh(path_str, inst_mem_fpmul);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_fpadd") begin
                    $readmemh(path_str, inst_mem_fpadd);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_fptofp") begin
                    $readmemh(path_str, inst_mem_fptofp);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_inttoint") begin
                    $readmemh(path_str, inst_mem_inttoint);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_fptoint") begin
                    $readmemh(path_str, inst_mem_fptoint);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_inttofp") begin
                    $readmemh(path_str, inst_mem_inttofp);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_logic") begin
                    $readmemh(path_str, inst_mem_logic);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_shiftup") begin
                    $readmemh(path_str, inst_mem_shiftup);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_shiftdn") begin
                    $readmemh(path_str, inst_mem_shiftdn);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ur_rdata_0") begin
                    $readmemh(path_str, inst_mem_ur_rdata_0);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ur_rdata_1") begin
                    $readmemh(path_str, inst_mem_ur_rdata_1);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ur_rdata_2") begin
                    $readmemh(path_str, inst_mem_ur_rdata_2);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ur_rdata_3") begin
                    $readmemh(path_str, inst_mem_ur_rdata_3);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ur_wdata_0") begin
                    $readmemh(path_str, inst_mem_ur_wdata_0);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ur_wdata_1") begin
                    $readmemh(path_str, inst_mem_ur_wdata_1);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ur_wdata_2") begin
                    $readmemh(path_str, inst_mem_ur_wdata_2);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ur_wdata_3") begin
                    $readmemh(path_str, inst_mem_ur_wdata_3);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_stb") begin
                    $readmemh(path_str, inst_mem_stb);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "inst_mem_ldb") begin
                    $readmemh(path_str, inst_mem_ldb);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "dut.u_smc.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array") begin
                    $readmemh(path_str, dut.u_smc.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "dut.u_smc.u_user_register.bram_bank_inst[1].u_bank_sram.memory_array") begin
                    $readmemh(path_str, dut.u_smc.u_user_register.bram_bank_inst[1].u_bank_sram.memory_array);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "dut.u_smc.u_user_register.bram_bank_inst[2].u_bank_sram.memory_array") begin
                    $readmemh(path_str, dut.u_smc.u_user_register.bram_bank_inst[2].u_bank_sram.memory_array);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "dut.u_smc.u_user_register.bram_bank_inst[3].u_bank_sram.memory_array") begin
                    $readmemh(path_str, dut.u_smc.u_user_register.bram_bank_inst[3].u_bank_sram.memory_array);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "dut.u_smc.u_user_register.bram_bank_inst[4].u_bank_sram.memory_array") begin
                    $readmemh(path_str, dut.u_smc.u_user_register.bram_bank_inst[4].u_bank_sram.memory_array);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "dut.u_smc.u_user_register.bram_bank_inst[5].u_bank_sram.memory_array") begin
                    $readmemh(path_str, dut.u_smc.u_user_register.bram_bank_inst[5].u_bank_sram.memory_array);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "dut.u_smc.u_user_register.bram_bank_inst[6].u_bank_sram.memory_array") begin
                    $readmemh(path_str, dut.u_smc.u_user_register.bram_bank_inst[6].u_bank_sram.memory_array);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str == "dut.u_smc.u_user_register.bram_bank_inst[7].u_bank_sram.memory_array") begin
                    $readmemh(path_str, dut.u_smc.u_user_register.bram_bank_inst[7].u_bank_sram.memory_array);
                    $display("  [data_list] %s <- %s", mem_name_str, path_str);
                end else if (mem_name_str.len() >= 17 && mem_name_str.substr(0, 14) == "inst_mem_rtovr[") begin
                    // 最后匹配：前缀 inst_mem_rtovr[，数字在 15..len-2
                    rtovr_idx_parsed = 0;
                    for (parse_i = 15; parse_i <= mem_name_str.len() - 2; parse_i = parse_i + 1)
                        rtovr_idx_parsed = rtovr_idx_parsed * 10 + (mem_name_str.getc(parse_i) - 48);
                    if (rtovr_idx_parsed >= 0 && rtovr_idx_parsed <= 39) begin
                        // 先清零 temp_rtovr_mem，否则 $readmemh 只写入文件行数，未写到的 [N..31] 为 x，复制后会被误计为有效指令
                        for (inst_idx = 0; inst_idx < 32; inst_idx = inst_idx + 1)
                            temp_rtovr_mem[inst_idx] = 64'd0;
                        $readmemh(path_str, temp_rtovr_mem);
                        for (inst_idx = 0; inst_idx < 32; inst_idx = inst_idx + 1)
                            inst_mem_rtovr[rtovr_idx_parsed][inst_idx] = temp_rtovr_mem[inst_idx];
                        $display("  [data_list] %s <- %s", mem_name_str, path_str);
                    end
                end else
                    $display("  [data_list] Unknown mem_name: %s", mem_name_str);
            end
            $fclose(fd_list);
        end

        // Recompute inst_count_* for all IQs
        for (inst_idx = 0; inst_idx < 32; inst_idx = inst_idx + 1) begin
            if (inst_mem_intadd[inst_idx] != 'd0) inst_count_intadd = inst_count_intadd + 1;
            if (inst_mem_int8tofp16[inst_idx] != 'd0) inst_count_int8tofp16 = inst_count_int8tofp16 + 1;
            if (inst_mem_fp16mul[inst_idx] != 'd0) inst_count_fp16mul = inst_count_fp16mul + 1;
            if (inst_mem_fp32addtree5to1[inst_idx] != 'd0) inst_count_fp32addtree5to1 = inst_count_fp32addtree5to1 + 1;
            if (inst_mem_fp32addtree8to1[inst_idx] != 'd0) inst_count_fp32addtree8to1 = inst_count_fp32addtree8to1 + 1;
            if (inst_mem_fpmul[inst_idx] != 'd0) inst_count_fpmul = inst_count_fpmul + 1;
            if (inst_mem_fpadd[inst_idx] != 'd0) inst_count_fpadd = inst_count_fpadd + 1;
            if (inst_mem_fptofp[inst_idx] != 'd0) inst_count_fptofp = inst_count_fptofp + 1;
            if (inst_mem_inttoint[inst_idx] != 'd0) inst_count_inttoint = inst_count_inttoint + 1;
            if (inst_mem_fptoint[inst_idx] != 'd0) inst_count_fptoint = inst_count_fptoint + 1;
            if (inst_mem_inttofp[inst_idx] != 'd0) inst_count_inttofp = inst_count_inttofp + 1;
            if (inst_mem_logic[inst_idx] != 'd0) inst_count_logic = inst_count_logic + 1;
            if (inst_mem_shiftup[inst_idx] != 'd0) inst_count_shiftup = inst_count_shiftup + 1;
            if (inst_mem_shiftdn[inst_idx] != 'd0) inst_count_shiftdn = inst_count_shiftdn + 1;
            if (inst_mem_ur_rdata_0[inst_idx] != 'd0) inst_count_ur_rdata[0] = inst_count_ur_rdata[0] + 1;
            if (inst_mem_ur_rdata_1[inst_idx] != 'd0) inst_count_ur_rdata[1] = inst_count_ur_rdata[1] + 1;
            if (inst_mem_ur_rdata_2[inst_idx] != 'd0) inst_count_ur_rdata[2] = inst_count_ur_rdata[2] + 1;
            if (inst_mem_ur_rdata_3[inst_idx] != 'd0) inst_count_ur_rdata[3] = inst_count_ur_rdata[3] + 1;
            if (inst_mem_ur_wdata_0[inst_idx] != 'd0) inst_count_ur_wdata[0] = inst_count_ur_wdata[0] + 1;
            if (inst_mem_ur_wdata_1[inst_idx] != 'd0) inst_count_ur_wdata[1] = inst_count_ur_wdata[1] + 1;
            if (inst_mem_ur_wdata_2[inst_idx] != 'd0) inst_count_ur_wdata[2] = inst_count_ur_wdata[2] + 1;
            if (inst_mem_ur_wdata_3[inst_idx] != 'd0) inst_count_ur_wdata[3] = inst_count_ur_wdata[3] + 1;
            if (inst_mem_stb[inst_idx] != 'd0) inst_count_stb = inst_count_stb + 1;
            if (inst_mem_ldb[inst_idx] != 'd0) inst_count_ldb = inst_count_ldb + 1;
        end
        for (inst_idx = 0; inst_idx < 40; inst_idx = inst_idx + 1)
            for (iq_idx = 0; iq_idx < 32; iq_idx = iq_idx + 1)
                if (inst_mem_rtovr[inst_idx][iq_idx] != 'd0)
                    inst_count_rtovr[inst_idx] = inst_count_rtovr[inst_idx] + 1;

        $display("  ID 0-13:  inst counts: intadd=%0d fpadd=%0d fpmul=%0d ...", inst_count_intadd, inst_count_fpadd, inst_count_fpmul);
        $display("  ID 14-17 UR-RDATA: %0d,%0d,%0d,%0d; ID 18-21 UR-WDATA: %0d,%0d,%0d,%0d",
                 inst_count_ur_rdata[0], inst_count_ur_rdata[1], inst_count_ur_rdata[2], inst_count_ur_rdata[3],
                 inst_count_ur_wdata[0], inst_count_ur_wdata[1], inst_count_ur_wdata[2], inst_count_ur_wdata[3]);
    end
    
    // Reset sequence
    #(CLK_PERIOD * 10);
    rst_n = 1;
    #(CLK_PERIOD * 5);
    
    // ==========================================================================
    // Write Instructions to All smi_iq (except UR)
    // UR instructions are loaded directly to memory, not via interface
    // ==========================================================================
    $display("\n--- Step 1: Write Instructions to All smi_iq (except UR) ---");
    
    // ID 0: INTADD
    if (inst_count_intadd > 0) begin
        $display("\n  Writing to INTADD (SMI-IQ ID 0): %0d instructions", inst_count_intadd);
        for (inst_idx = 0; inst_idx < inst_count_intadd; inst_idx = inst_idx + 1) begin
            @(negedge clk);
            #1;
            
            wri_vld[`IQ_ID_INTADD] = 1'b1;
            wri_data_intadd = inst_mem_intadd[inst_idx][`WR_DATA_INTADD_W-1:0];
            wri_iqsid[`IQ_ID_INTADD] = 2'b00;
            
            if (inst_idx == inst_count_intadd - 1) begin
                if (inst_idx == 0) begin
                    wri_start[`IQ_ID_INTADD] = 1'b1;
                    wri_end[`IQ_ID_INTADD] = 1'b1;
                end else begin
                    wri_start[`IQ_ID_INTADD] = 1'b0;
                    wri_end[`IQ_ID_INTADD] = 1'b1;
                end
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_INTADD] = 1'b1;
                wri_end[`IQ_ID_INTADD] = 1'b0;
            end else begin
                wri_start[`IQ_ID_INTADD] = 1'b0;
                wri_end[`IQ_ID_INTADD] = 1'b0;
            end
            
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        #1;
        wri_vld[`IQ_ID_INTADD] = 1'b0;
        wri_start[`IQ_ID_INTADD] = 1'b0;
        wri_end[`IQ_ID_INTADD] = 1'b0;
        @(posedge clk);
    end
    
    // ID 1: INT8toFP16 (WR_INST_WIDTH=43)
    if (inst_count_int8tofp16 > 0) begin
        $display("\n  Writing to INT8toFP16 (SMI-IQ ID 1): %0d instructions", inst_count_int8tofp16);
        for (inst_idx = 0; inst_idx < inst_count_int8tofp16; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_INT8toFP16] = 1'b1;
            wri_data_int8tofp16 = inst_mem_int8tofp16[inst_idx][`WR_DATA_INT8toFP16_W-1:0];
            wri_iqsid[`IQ_ID_INT8toFP16] = 2'b00;
            if (inst_idx == inst_count_int8tofp16 - 1) begin
                wri_start[`IQ_ID_INT8toFP16] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_INT8toFP16] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_INT8toFP16] = 1'b1; wri_end[`IQ_ID_INT8toFP16] = 1'b0;
            end else begin
                wri_start[`IQ_ID_INT8toFP16] = 1'b0; wri_end[`IQ_ID_INT8toFP16] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_INT8toFP16] = 1'b0; wri_start[`IQ_ID_INT8toFP16] = 1'b0; wri_end[`IQ_ID_INT8toFP16] = 1'b0;
        @(posedge clk);
    end
    
    // ID 2: FP16MUL (WR_INST_WIDTH=50)
    if (inst_count_fp16mul > 0) begin
        $display("\n  Writing to FP16MUL (SMI-IQ ID 2): %0d instructions", inst_count_fp16mul);
        for (inst_idx = 0; inst_idx < inst_count_fp16mul; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_FP16MUL] = 1'b1;
            wri_data_fp16mul = inst_mem_fp16mul[inst_idx][`WR_DATA_FP16MUL_W-1:0];
            wri_iqsid[`IQ_ID_FP16MUL] = 2'b00;
            if (inst_idx == inst_count_fp16mul - 1) begin
                wri_start[`IQ_ID_FP16MUL] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_FP16MUL] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_FP16MUL] = 1'b1; wri_end[`IQ_ID_FP16MUL] = 1'b0;
            end else begin
                wri_start[`IQ_ID_FP16MUL] = 1'b0; wri_end[`IQ_ID_FP16MUL] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_FP16MUL] = 1'b0; wri_start[`IQ_ID_FP16MUL] = 1'b0; wri_end[`IQ_ID_FP16MUL] = 1'b0;
        @(posedge clk);
    end
    
    // ID 3: FP32ADDTREE5TO1 (WR_INST_WIDTH=42)
    if (inst_count_fp32addtree5to1 > 0) begin
        $display("\n  Writing to FP32ADDTREE5TO1 (SMI-IQ ID 3): %0d instructions", inst_count_fp32addtree5to1);
        for (inst_idx = 0; inst_idx < inst_count_fp32addtree5to1; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_FP32ADDTREE5TO1] = 1'b1;
            wri_data_fp32addtree5to1 = inst_mem_fp32addtree5to1[inst_idx][`WR_DATA_FP32ADDTREE5TO1_W-1:0];
            wri_iqsid[`IQ_ID_FP32ADDTREE5TO1] = 2'b00;
            if (inst_idx == inst_count_fp32addtree5to1 - 1) begin
                wri_start[`IQ_ID_FP32ADDTREE5TO1] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_FP32ADDTREE5TO1] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_FP32ADDTREE5TO1] = 1'b1; wri_end[`IQ_ID_FP32ADDTREE5TO1] = 1'b0;
            end else begin
                wri_start[`IQ_ID_FP32ADDTREE5TO1] = 1'b0; wri_end[`IQ_ID_FP32ADDTREE5TO1] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_FP32ADDTREE5TO1] = 1'b0; wri_start[`IQ_ID_FP32ADDTREE5TO1] = 1'b0; wri_end[`IQ_ID_FP32ADDTREE5TO1] = 1'b0;
        @(posedge clk);
    end
    
    // ID 4: FP32ADDTREE8TO1 (WR_INST_WIDTH=44)
    if (inst_count_fp32addtree8to1 > 0) begin
        $display("\n  Writing to FP32ADDTREE8TO1 (SMI-IQ ID 4): %0d instructions", inst_count_fp32addtree8to1);
        for (inst_idx = 0; inst_idx < inst_count_fp32addtree8to1; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_FP32ADDTREE8TO1] = 1'b1;
            wri_data_fp32addtree8to1 = inst_mem_fp32addtree8to1[inst_idx][`WR_DATA_FP32ADDTREE8TO1_W-1:0];
            wri_iqsid[`IQ_ID_FP32ADDTREE8TO1] = 2'b00;
            if (inst_idx == inst_count_fp32addtree8to1 - 1) begin
                wri_start[`IQ_ID_FP32ADDTREE8TO1] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_FP32ADDTREE8TO1] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_FP32ADDTREE8TO1] = 1'b1; wri_end[`IQ_ID_FP32ADDTREE8TO1] = 1'b0;
            end else begin
                wri_start[`IQ_ID_FP32ADDTREE8TO1] = 1'b0; wri_end[`IQ_ID_FP32ADDTREE8TO1] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_FP32ADDTREE8TO1] = 1'b0; wri_start[`IQ_ID_FP32ADDTREE8TO1] = 1'b0; wri_end[`IQ_ID_FP32ADDTREE8TO1] = 1'b0;
        @(posedge clk);
    end
    
    // ID 5: FPMUL
    if (inst_count_fpmul > 0) begin
        $display("\n  Writing to FPMUL (ID 5): %0d instructions", inst_count_fpmul);
        for (inst_idx = 0; inst_idx < inst_count_fpmul; inst_idx = inst_idx + 1) begin
            // Wait for clock falling edge before setting signals to ensure setup time
            @(negedge clk);
            #1;
            
            wri_vld[`IQ_ID_FPMUL] = 1'b1;
            wri_data_fpmul = inst_mem_fpmul[inst_idx][`WR_DATA_FPMUL_W-1:0];
            wri_iqsid[`IQ_ID_FPMUL] = 2'b00;
            
            // Check if this is the last instruction first (handles single instruction case)
            if (inst_idx == inst_count_fpmul - 1) begin
                // Last instruction (or only instruction)
                if (inst_idx == 0) begin
                    // Single instruction: both start and end
                    wri_start[`IQ_ID_FPMUL] = 1'b1;
                    wri_end[`IQ_ID_FPMUL] = 1'b1;
                end else begin
                    // Last of multiple instructions
                    wri_start[`IQ_ID_FPMUL] = 1'b0;
                    wri_end[`IQ_ID_FPMUL] = 1'b1;
                end
            end else if (inst_idx == 0) begin
                // First instruction (but not the last)
                wri_start[`IQ_ID_FPMUL] = 1'b1;
                wri_end[`IQ_ID_FPMUL] = 1'b0;
            end else begin
                // Middle instruction
                wri_start[`IQ_ID_FPMUL] = 1'b0;
                wri_end[`IQ_ID_FPMUL] = 1'b0;
            end
            
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        #1;
        wri_vld[`IQ_ID_FPMUL] = 1'b0;
        wri_start[`IQ_ID_FPMUL] = 1'b0;
        wri_end[`IQ_ID_FPMUL] = 1'b0;
        @(posedge clk);
    end
    
    // ID 6: FPADD
    if (inst_count_fpadd > 0) begin
        $display("\n  Writing to FPADD (ID 6): %0d instructions", inst_count_fpadd);
        for (inst_idx = 0; inst_idx < inst_count_fpadd; inst_idx = inst_idx + 1) begin
            // Wait for clock falling edge before setting signals to ensure setup time
            @(negedge clk);
            #1;
            
            wri_vld[`IQ_ID_FPADD] = 1'b1;
            wri_data_fpadd = inst_mem_fpadd[inst_idx][`WR_DATA_FPADD_W-1:0];
            wri_iqsid[`IQ_ID_FPADD] = 2'b00;
            
            // Check if this is the last instruction first (handles single instruction case)
            if (inst_idx == inst_count_fpadd - 1) begin
                // Last instruction (or only instruction)
                if (inst_idx == 0) begin
                    // Single instruction: both start and end
                    wri_start[`IQ_ID_FPADD] = 1'b1;
                    wri_end[`IQ_ID_FPADD] = 1'b1;
                end else begin
                    // Last of multiple instructions
                    wri_start[`IQ_ID_FPADD] = 1'b0;
                    wri_end[`IQ_ID_FPADD] = 1'b1;
                end
            end else if (inst_idx == 0) begin
                // First instruction (but not the last)
                wri_start[`IQ_ID_FPADD] = 1'b1;
                wri_end[`IQ_ID_FPADD] = 1'b0;
            end else begin
                // Middle instruction
                wri_start[`IQ_ID_FPADD] = 1'b0;
                wri_end[`IQ_ID_FPADD] = 1'b0;
            end
            
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        #1;
        wri_vld[`IQ_ID_FPADD] = 1'b0;
        wri_start[`IQ_ID_FPADD] = 1'b0;
        wri_end[`IQ_ID_FPADD] = 1'b0;
        @(posedge clk);
    end
    
    // ID 7: FPtoFP (WR_INST_WIDTH=46)
    if (inst_count_fptofp > 0) begin
        $display("\n  Writing to FPtoFP (SMI-IQ ID 7): %0d instructions", inst_count_fptofp);
        for (inst_idx = 0; inst_idx < inst_count_fptofp; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_FPtoFP] = 1'b1;
            wri_data_fptofp = inst_mem_fptofp[inst_idx][`WR_DATA_FPtoFP_W-1:0];
            wri_iqsid[`IQ_ID_FPtoFP] = 2'b00;
            if (inst_idx == inst_count_fptofp - 1) begin
                wri_start[`IQ_ID_FPtoFP] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_FPtoFP] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_FPtoFP] = 1'b1; wri_end[`IQ_ID_FPtoFP] = 1'b0;
            end else begin
                wri_start[`IQ_ID_FPtoFP] = 1'b0; wri_end[`IQ_ID_FPtoFP] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_FPtoFP] = 1'b0; wri_start[`IQ_ID_FPtoFP] = 1'b0; wri_end[`IQ_ID_FPtoFP] = 1'b0;
        @(posedge clk);
    end
    
    // ID 8: INTtoINT (WR_INST_WIDTH=48)
    if (inst_count_inttoint > 0) begin
        $display("\n  Writing to INTtoINT (SMI-IQ ID 8): %0d instructions", inst_count_inttoint);
        for (inst_idx = 0; inst_idx < inst_count_inttoint; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_INTtoINT] = 1'b1;
            wri_data_inttoint = inst_mem_inttoint[inst_idx][`WR_DATA_INTtoINT_W-1:0];
            wri_iqsid[`IQ_ID_INTtoINT] = 2'b00;
            if (inst_idx == inst_count_inttoint - 1) begin
                wri_start[`IQ_ID_INTtoINT] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_INTtoINT] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_INTtoINT] = 1'b1; wri_end[`IQ_ID_INTtoINT] = 1'b0;
            end else begin
                wri_start[`IQ_ID_INTtoINT] = 1'b0; wri_end[`IQ_ID_INTtoINT] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_INTtoINT] = 1'b0; wri_start[`IQ_ID_INTtoINT] = 1'b0; wri_end[`IQ_ID_INTtoINT] = 1'b0;
        @(posedge clk);
    end
    
    // ID 9: FPtoINT (WR_INST_WIDTH=46)
    if (inst_count_fptoint > 0) begin
        $display("\n  Writing to FPtoINT (SMI-IQ ID 9): %0d instructions", inst_count_fptoint);
        for (inst_idx = 0; inst_idx < inst_count_fptoint; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_FPtoINT] = 1'b1;
            wri_data_fptoint = inst_mem_fptoint[inst_idx][`WR_DATA_FPtoINT_W-1:0];
            wri_iqsid[`IQ_ID_FPtoINT] = 2'b00;
            if (inst_idx == inst_count_fptoint - 1) begin
                wri_start[`IQ_ID_FPtoINT] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_FPtoINT] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_FPtoINT] = 1'b1; wri_end[`IQ_ID_FPtoINT] = 1'b0;
            end else begin
                wri_start[`IQ_ID_FPtoINT] = 1'b0; wri_end[`IQ_ID_FPtoINT] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_FPtoINT] = 1'b0; wri_start[`IQ_ID_FPtoINT] = 1'b0; wri_end[`IQ_ID_FPtoINT] = 1'b0;
        @(posedge clk);
    end
    
    // ID 10: INTtoFP (WR_INST_WIDTH=47)
    if (inst_count_inttofp > 0) begin
        $display("\n  Writing to INTtoFP (SMI-IQ ID 10): %0d instructions", inst_count_inttofp);
        for (inst_idx = 0; inst_idx < inst_count_inttofp; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_INTtoFP] = 1'b1;
            wri_data_inttofp = inst_mem_inttofp[inst_idx][`WR_DATA_INTtoFP_W-1:0];
            wri_iqsid[`IQ_ID_INTtoFP] = 2'b00;
            if (inst_idx == inst_count_inttofp - 1) begin
                wri_start[`IQ_ID_INTtoFP] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_INTtoFP] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_INTtoFP] = 1'b1; wri_end[`IQ_ID_INTtoFP] = 1'b0;
            end else begin
                wri_start[`IQ_ID_INTtoFP] = 1'b0; wri_end[`IQ_ID_INTtoFP] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_INTtoFP] = 1'b0; wri_start[`IQ_ID_INTtoFP] = 1'b0; wri_end[`IQ_ID_INTtoFP] = 1'b0;
        @(posedge clk);
    end
    
    // ID 11: LOGIC (WR_INST_WIDTH=47)
    if (inst_count_logic > 0) begin
        $display("\n  Writing to LOGIC (SMI-IQ ID 11): %0d instructions", inst_count_logic);
        for (inst_idx = 0; inst_idx < inst_count_logic; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_LOGIC] = 1'b1;
            wri_data_logic = inst_mem_logic[inst_idx][`WR_DATA_LOGIC_W-1:0];
            wri_iqsid[`IQ_ID_LOGIC] = 2'b00;
            if (inst_idx == inst_count_logic - 1) begin
                wri_start[`IQ_ID_LOGIC] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_LOGIC] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_LOGIC] = 1'b1; wri_end[`IQ_ID_LOGIC] = 1'b0;
            end else begin
                wri_start[`IQ_ID_LOGIC] = 1'b0; wri_end[`IQ_ID_LOGIC] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_LOGIC] = 1'b0; wri_start[`IQ_ID_LOGIC] = 1'b0; wri_end[`IQ_ID_LOGIC] = 1'b0;
        @(posedge clk);
    end
    
    // ID 12: SHIFTUP (WR_INST_WIDTH=176, inst_mem 64b -> zero-pad to 176)
    if (inst_count_shiftup > 0) begin
        $display("\n  Writing to SHIFTUP (SMI-IQ ID 12): %0d instructions", inst_count_shiftup);
        for (inst_idx = 0; inst_idx < inst_count_shiftup; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_SHIFTUP] = 1'b1;
            wri_data_shiftup = inst_mem_shiftup[inst_idx][`WR_DATA_SHIFTUP_W-1:0];
            wri_iqsid[`IQ_ID_SHIFTUP] = 2'b00;
            if (inst_idx == inst_count_shiftup - 1) begin
                wri_start[`IQ_ID_SHIFTUP] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_SHIFTUP] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_SHIFTUP] = 1'b1; wri_end[`IQ_ID_SHIFTUP] = 1'b0;
            end else begin
                wri_start[`IQ_ID_SHIFTUP] = 1'b0; wri_end[`IQ_ID_SHIFTUP] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_SHIFTUP] = 1'b0; wri_start[`IQ_ID_SHIFTUP] = 1'b0; wri_end[`IQ_ID_SHIFTUP] = 1'b0;
        @(posedge clk);
    end
    
    // ID 13: SHIFTDN (WR_INST_WIDTH=175, inst_mem 64b -> zero-pad to 175)
    if (inst_count_shiftdn > 0) begin
        $display("\n  Writing to SHIFTDN (SMI-IQ ID 13): %0d instructions", inst_count_shiftdn);
        for (inst_idx = 0; inst_idx < inst_count_shiftdn; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_SHIFTDN] = 1'b1;
            wri_data_shiftdn = inst_mem_shiftdn[inst_idx][`WR_DATA_SHIFTDN_W-1:0];
            wri_iqsid[`IQ_ID_SHIFTDN] = 2'b00;
            if (inst_idx == inst_count_shiftdn - 1) begin
                wri_start[`IQ_ID_SHIFTDN] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_SHIFTDN] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_SHIFTDN] = 1'b1; wri_end[`IQ_ID_SHIFTDN] = 1'b0;
            end else begin
                wri_start[`IQ_ID_SHIFTDN] = 1'b0; wri_end[`IQ_ID_SHIFTDN] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_SHIFTDN] = 1'b0; wri_start[`IQ_ID_SHIFTDN] = 1'b0; wri_end[`IQ_ID_SHIFTDN] = 1'b0;
        @(posedge clk);
    end
    
    // RtoVR instances: 文件后缀编号 N 对应 instance index N
    // SMI-IQ ID = IQ_ID_RTOVR_BASE (24) + instance_index
    // 遍历 0..39 的所有 instance，根据 inst_count_rtovr[N] 判断是否需要写入
    begin
        integer rtovr_idx;
        integer rtovr_smi_iq_id;
        
        for (rtovr_idx = 0; rtovr_idx < 40; rtovr_idx = rtovr_idx + 1) begin
            rtovr_smi_iq_id = `IQ_ID_RTOVR_BASE + rtovr_idx;  // Calculate SMI-IQ ID from instance index
            
            if (inst_count_rtovr[rtovr_idx] > 0) begin
                $display("\n  Writing to RtoVR-%0d (SMI-IQ ID %0d): %0d instructions", 
                         rtovr_idx, rtovr_smi_iq_id, inst_count_rtovr[rtovr_idx]);
                for (inst_idx = 0; inst_idx < inst_count_rtovr[rtovr_idx]; inst_idx = inst_idx + 1) begin
                    // Wait for clock falling edge before setting signals to ensure setup time
                    @(negedge clk);
                    #1;
                    
                    // Set data first, then control signals
                    wri_data_rtovr[rtovr_idx] = inst_mem_rtovr[rtovr_idx][inst_idx][`WR_DATA_RTOVR_W-1:0];
                    wri_iqsid[rtovr_smi_iq_id] = 2'b00;
                    
                    // Check if this is the last instruction first (handles single instruction case)
                    if (inst_idx == inst_count_rtovr[rtovr_idx] - 1) begin
                        // Last instruction (or only instruction)
                        if (inst_idx == 0) begin
                            // Single instruction: both start and end
                            wri_start[rtovr_smi_iq_id] = 1'b1;
                            wri_end[rtovr_smi_iq_id] = 1'b1;
                        end else begin
                            // Last of multiple instructions
                            wri_start[rtovr_smi_iq_id] = 1'b0;
                            wri_end[rtovr_smi_iq_id] = 1'b1;
                        end
                    end else if (inst_idx == 0) begin
                        // First instruction (but not the last)
                        wri_start[rtovr_smi_iq_id] = 1'b1;
                        wri_end[rtovr_smi_iq_id] = 1'b0;
                    end else begin
                        // Middle instruction
                        wri_start[rtovr_smi_iq_id] = 1'b0;
                        wri_end[rtovr_smi_iq_id] = 1'b0;
                    end
                    
                    // Set valid signal last, then wait for clock
                    wri_vld[rtovr_smi_iq_id] = 1'b1;
                    
                    // Debug: display what we're writing (after setting signals)
                    $display("    [RtoVR-%0d] Inst %0d/%0d: SMI-IQ ID=%0d, wri_vld=%b, wri_data=%h, wri_start=%b, wri_end=%b", 
                             rtovr_idx, inst_idx+1, inst_count_rtovr[rtovr_idx],
                             rtovr_smi_iq_id, wri_vld[rtovr_smi_iq_id],
                             wri_data_rtovr[rtovr_idx],
                             wri_start[rtovr_smi_iq_id], wri_end[rtovr_smi_iq_id]);
                    
                    @(posedge clk);
                    #1;
                end
                @(negedge clk);
                #1;
                wri_vld[rtovr_smi_iq_id] = 1'b0;
                wri_start[rtovr_smi_iq_id] = 1'b0;
                wri_end[rtovr_smi_iq_id] = 1'b0;
                @(posedge clk);
            end
        end
    end
    
    // ID 14-17: UR-RDATA - Load from phase4_bank_constrained
    // ID 14: UR-RDATA-0 (iq_ur-r0.hex exists)
    if (inst_count_ur_rdata[0] > 0) begin
        $display("\n  Writing to UR-RDATA-0 (ID 14): %0d instructions", inst_count_ur_rdata[0]);
        for (inst_idx = 0; inst_idx < inst_count_ur_rdata[0]; inst_idx = inst_idx + 1) begin
            // Wait for clock falling edge before setting signals to ensure setup time
            @(negedge clk);
            #1;
            
            wri_vld[`IQ_ID_UR_RDATA_0] = 1'b1;
            wri_data_ur_rdata[0] = inst_mem_ur_rdata_0[inst_idx][`WR_DATA_UR_RDATA_W-1:0];
            wri_iqsid[`IQ_ID_UR_RDATA_0] = 2'b00;
            
            // Check if this is the last instruction first (handles single instruction case)
            if (inst_idx == inst_count_ur_rdata[0] - 1) begin
                // Last instruction (or only instruction)
                if (inst_idx == 0) begin
                    // Single instruction: both start and end
                    wri_start[`IQ_ID_UR_RDATA_0] = 1'b1;
                    wri_end[`IQ_ID_UR_RDATA_0] = 1'b1;
                end else begin
                    // Last of multiple instructions
                    wri_start[`IQ_ID_UR_RDATA_0] = 1'b0;
                    wri_end[`IQ_ID_UR_RDATA_0] = 1'b1;
                end
            end else if (inst_idx == 0) begin
                // First instruction (but not the last)
                wri_start[`IQ_ID_UR_RDATA_0] = 1'b1;
                wri_end[`IQ_ID_UR_RDATA_0] = 1'b0;
            end else begin
                // Middle instruction
                wri_start[`IQ_ID_UR_RDATA_0] = 1'b0;
                wri_end[`IQ_ID_UR_RDATA_0] = 1'b0;
            end
            
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        #1;
        wri_vld[`IQ_ID_UR_RDATA_0] = 1'b0;
        wri_start[`IQ_ID_UR_RDATA_0] = 1'b0;
        wri_end[`IQ_ID_UR_RDATA_0] = 1'b0;
        @(posedge clk);
    end
    
    // ID 15: UR-RDATA-1 (iq_ur-r1.hex exists)
    if (inst_count_ur_rdata[1] > 0) begin
        $display("\n  Writing to UR-RDATA-1 (ID 15): %0d instructions", inst_count_ur_rdata[1]);
        for (inst_idx = 0; inst_idx < inst_count_ur_rdata[1]; inst_idx = inst_idx + 1) begin
            // Wait for clock falling edge before setting signals to ensure setup time
            @(negedge clk);
            #1;
            
            wri_vld[`IQ_ID_UR_RDATA_1] = 1'b1;
            wri_data_ur_rdata[1] = inst_mem_ur_rdata_1[inst_idx][`WR_DATA_UR_RDATA_W-1:0];
            wri_iqsid[`IQ_ID_UR_RDATA_1] = 2'b00;
            
            // Check if this is the last instruction first (handles single instruction case)
            if (inst_idx == inst_count_ur_rdata[1] - 1) begin
                // Last instruction (or only instruction)
                if (inst_idx == 0) begin
                    // Single instruction: both start and end
                    wri_start[`IQ_ID_UR_RDATA_1] = 1'b1;
                    wri_end[`IQ_ID_UR_RDATA_1] = 1'b1;
                end else begin
                    // Last of multiple instructions
                    wri_start[`IQ_ID_UR_RDATA_1] = 1'b0;
                    wri_end[`IQ_ID_UR_RDATA_1] = 1'b1;
                end
            end else if (inst_idx == 0) begin
                // First instruction (but not the last)
                wri_start[`IQ_ID_UR_RDATA_1] = 1'b1;
                wri_end[`IQ_ID_UR_RDATA_1] = 1'b0;
            end else begin
                // Middle instruction
                wri_start[`IQ_ID_UR_RDATA_1] = 1'b0;
                wri_end[`IQ_ID_UR_RDATA_1] = 1'b0;
            end
            
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        #1;
        wri_vld[`IQ_ID_UR_RDATA_1] = 1'b0;
        wri_start[`IQ_ID_UR_RDATA_1] = 1'b0;
        wri_end[`IQ_ID_UR_RDATA_1] = 1'b0;
        @(posedge clk);
    end
    
    // ID 16: UR-RDATA-2 (iq_ur-r2.hex exists)
    if (inst_count_ur_rdata[2] > 0) begin
        $display("\n  Writing to UR-RDATA-2 (ID 16): %0d instructions", inst_count_ur_rdata[2]);
        for (inst_idx = 0; inst_idx < inst_count_ur_rdata[2]; inst_idx = inst_idx + 1) begin
            // Wait for clock falling edge before setting signals to ensure setup time
            @(negedge clk);
            #1;
            
            wri_vld[`IQ_ID_UR_RDATA_2] = 1'b1;
            wri_data_ur_rdata[2] = inst_mem_ur_rdata_2[inst_idx][`WR_DATA_UR_RDATA_W-1:0];
            wri_iqsid[`IQ_ID_UR_RDATA_2] = 2'b00;
            
            // Check if this is the last instruction first (handles single instruction case)
            if (inst_idx == inst_count_ur_rdata[2] - 1) begin
                // Last instruction (or only instruction)
                if (inst_idx == 0) begin
                    // Single instruction: both start and end
                    wri_start[`IQ_ID_UR_RDATA_2] = 1'b1;
                    wri_end[`IQ_ID_UR_RDATA_2] = 1'b1;
                end else begin
                    // Last of multiple instructions
                    wri_start[`IQ_ID_UR_RDATA_2] = 1'b0;
                    wri_end[`IQ_ID_UR_RDATA_2] = 1'b1;
                end
            end else if (inst_idx == 0) begin
                // First instruction (but not the last)
                wri_start[`IQ_ID_UR_RDATA_2] = 1'b1;
                wri_end[`IQ_ID_UR_RDATA_2] = 1'b0;
            end else begin
                // Middle instruction
                wri_start[`IQ_ID_UR_RDATA_2] = 1'b0;
                wri_end[`IQ_ID_UR_RDATA_2] = 1'b0;
            end
            
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        #1;
        wri_vld[`IQ_ID_UR_RDATA_2] = 1'b0;
        wri_start[`IQ_ID_UR_RDATA_2] = 1'b0;
        wri_end[`IQ_ID_UR_RDATA_2] = 1'b0;
        @(posedge clk);
    end
    
    // ID 17: UR-RDATA-3
    if (inst_count_ur_rdata[3] > 0) begin
        $display("\n  Writing to UR-RDATA-3 (ID 17): %0d instructions", inst_count_ur_rdata[3]);
        for (inst_idx = 0; inst_idx < inst_count_ur_rdata[3]; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_UR_RDATA_3] = 1'b1;
            wri_data_ur_rdata[3] = inst_mem_ur_rdata_3[inst_idx][`WR_DATA_UR_RDATA_W-1:0];
            wri_iqsid[`IQ_ID_UR_RDATA_3] = 2'b00;
            if (inst_idx == inst_count_ur_rdata[3] - 1) begin
                wri_start[`IQ_ID_UR_RDATA_3] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_UR_RDATA_3] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_UR_RDATA_3] = 1'b1; wri_end[`IQ_ID_UR_RDATA_3] = 1'b0;
            end else begin
                wri_start[`IQ_ID_UR_RDATA_3] = 1'b0; wri_end[`IQ_ID_UR_RDATA_3] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_UR_RDATA_3] = 1'b0; wri_start[`IQ_ID_UR_RDATA_3] = 1'b0; wri_end[`IQ_ID_UR_RDATA_3] = 1'b0;
        @(posedge clk);
    end
    
    // ID 18: UR-WDATA-0 (iq_ur-w0.hex exists)
    if (inst_count_ur_wdata[0] > 0) begin
        $display("\n  Writing to UR-WDATA-0 (ID 18): %0d instructions", inst_count_ur_wdata[0]);
        for (inst_idx = 0; inst_idx < inst_count_ur_wdata[0]; inst_idx = inst_idx + 1) begin
            // Wait for clock falling edge before setting signals to ensure setup time
            @(negedge clk);
            #1;
            
            wri_vld[`IQ_ID_UR_WDATA_0] = 1'b1;
            wri_data_ur_wdata[0] = inst_mem_ur_wdata_0[inst_idx][`WR_DATA_UR_WDATA_W-1:0];
            wri_iqsid[`IQ_ID_UR_WDATA_0] = 2'b00;
            
            // Check if this is the last instruction first (handles single instruction case)
            if (inst_idx == inst_count_ur_wdata[0] - 1) begin
                // Last instruction (or only instruction)
                if (inst_idx == 0) begin
                    // Single instruction: both start and end
                    wri_start[`IQ_ID_UR_WDATA_0] = 1'b1;
                    wri_end[`IQ_ID_UR_WDATA_0] = 1'b1;
                end else begin
                    // Last of multiple instructions
                    wri_start[`IQ_ID_UR_WDATA_0] = 1'b0;
                    wri_end[`IQ_ID_UR_WDATA_0] = 1'b1;
                end
            end else if (inst_idx == 0) begin
                // First instruction (but not the last)
                wri_start[`IQ_ID_UR_WDATA_0] = 1'b1;
                wri_end[`IQ_ID_UR_WDATA_0] = 1'b0;
            end else begin
                // Middle instruction
                wri_start[`IQ_ID_UR_WDATA_0] = 1'b0;
                wri_end[`IQ_ID_UR_WDATA_0] = 1'b0;
            end
            
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        #1;
        wri_vld[`IQ_ID_UR_WDATA_0] = 1'b0;
        wri_start[`IQ_ID_UR_WDATA_0] = 1'b0;
        wri_end[`IQ_ID_UR_WDATA_0] = 1'b0;
        @(posedge clk);
    end
    
    // ID 19: UR-WDATA-1
    if (inst_count_ur_wdata[1] > 0) begin
        $display("\n  Writing to UR-WDATA-1 (ID 19): %0d instructions", inst_count_ur_wdata[1]);
        for (inst_idx = 0; inst_idx < inst_count_ur_wdata[1]; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_UR_WDATA_1] = 1'b1;
            wri_data_ur_wdata[1] = inst_mem_ur_wdata_1[inst_idx][`WR_DATA_UR_WDATA_W-1:0];
            wri_iqsid[`IQ_ID_UR_WDATA_1] = 2'b00;
            if (inst_idx == inst_count_ur_wdata[1] - 1) begin
                wri_start[`IQ_ID_UR_WDATA_1] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_UR_WDATA_1] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_UR_WDATA_1] = 1'b1; wri_end[`IQ_ID_UR_WDATA_1] = 1'b0;
            end else begin
                wri_start[`IQ_ID_UR_WDATA_1] = 1'b0; wri_end[`IQ_ID_UR_WDATA_1] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_UR_WDATA_1] = 1'b0; wri_start[`IQ_ID_UR_WDATA_1] = 1'b0; wri_end[`IQ_ID_UR_WDATA_1] = 1'b0;
        @(posedge clk);
    end
    
    // ID 20: UR-WDATA-2
    if (inst_count_ur_wdata[2] > 0) begin
        $display("\n  Writing to UR-WDATA-2 (ID 20): %0d instructions", inst_count_ur_wdata[2]);
        for (inst_idx = 0; inst_idx < inst_count_ur_wdata[2]; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_UR_WDATA_2] = 1'b1;
            wri_data_ur_wdata[2] = inst_mem_ur_wdata_2[inst_idx][`WR_DATA_UR_WDATA_W-1:0];
            wri_iqsid[`IQ_ID_UR_WDATA_2] = 2'b00;
            if (inst_idx == inst_count_ur_wdata[2] - 1) begin
                wri_start[`IQ_ID_UR_WDATA_2] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_UR_WDATA_2] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_UR_WDATA_2] = 1'b1; wri_end[`IQ_ID_UR_WDATA_2] = 1'b0;
            end else begin
                wri_start[`IQ_ID_UR_WDATA_2] = 1'b0; wri_end[`IQ_ID_UR_WDATA_2] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_UR_WDATA_2] = 1'b0; wri_start[`IQ_ID_UR_WDATA_2] = 1'b0; wri_end[`IQ_ID_UR_WDATA_2] = 1'b0;
        @(posedge clk);
    end
    
    // ID 21: UR-WDATA-3
    if (inst_count_ur_wdata[3] > 0) begin
        $display("\n  Writing to UR-WDATA-3 (ID 21): %0d instructions", inst_count_ur_wdata[3]);
        for (inst_idx = 0; inst_idx < inst_count_ur_wdata[3]; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_UR_WDATA_3] = 1'b1;
            wri_data_ur_wdata[3] = inst_mem_ur_wdata_3[inst_idx][`WR_DATA_UR_WDATA_W-1:0];
            wri_iqsid[`IQ_ID_UR_WDATA_3] = 2'b00;
            if (inst_idx == inst_count_ur_wdata[3] - 1) begin
                wri_start[`IQ_ID_UR_WDATA_3] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_UR_WDATA_3] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_UR_WDATA_3] = 1'b1; wri_end[`IQ_ID_UR_WDATA_3] = 1'b0;
            end else begin
                wri_start[`IQ_ID_UR_WDATA_3] = 1'b0; wri_end[`IQ_ID_UR_WDATA_3] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_UR_WDATA_3] = 1'b0; wri_start[`IQ_ID_UR_WDATA_3] = 1'b0; wri_end[`IQ_ID_UR_WDATA_3] = 1'b0;
        @(posedge clk);
    end
    
    // ID 22: STB (WR_INST_WIDTH=112, inst_mem 64b -> zero-pad to 112)
    if (inst_count_stb > 0) begin
        $display("\n  Writing to STB (SMI-IQ ID 22): %0d instructions", inst_count_stb);
        for (inst_idx = 0; inst_idx < inst_count_stb; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_STB] = 1'b1;
            wri_data_stb = inst_mem_stb[inst_idx][`WR_DATA_STB_W-1:0];
            wri_iqsid[`IQ_ID_STB] = 2'b00;
            if (inst_idx == inst_count_stb - 1) begin
                wri_start[`IQ_ID_STB] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_STB] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_STB] = 1'b1; wri_end[`IQ_ID_STB] = 1'b0;
            end else begin
                wri_start[`IQ_ID_STB] = 1'b0; wri_end[`IQ_ID_STB] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_STB] = 1'b0; wri_start[`IQ_ID_STB] = 1'b0; wri_end[`IQ_ID_STB] = 1'b0;
        @(posedge clk);
    end
    
    // ID 23: LDB (WR_INST_WIDTH=112, inst_mem 64b -> zero-pad to 112)
    if (inst_count_ldb > 0) begin
        $display("\n  Writing to LDB (SMI-IQ ID 23): %0d instructions", inst_count_ldb);
        for (inst_idx = 0; inst_idx < inst_count_ldb; inst_idx = inst_idx + 1) begin
            @(negedge clk); #1;
            wri_vld[`IQ_ID_LDB] = 1'b1;
            wri_data_ldb = inst_mem_ldb[inst_idx][`WR_DATA_LDB_W-1:0];
            wri_iqsid[`IQ_ID_LDB] = 2'b00;
            if (inst_idx == inst_count_ldb - 1) begin
                wri_start[`IQ_ID_LDB] = (inst_idx == 0) ? 1'b1 : 1'b0;
                wri_end[`IQ_ID_LDB] = 1'b1;
            end else if (inst_idx == 0) begin
                wri_start[`IQ_ID_LDB] = 1'b1; wri_end[`IQ_ID_LDB] = 1'b0;
            end else begin
                wri_start[`IQ_ID_LDB] = 1'b0; wri_end[`IQ_ID_LDB] = 1'b0;
            end
            @(posedge clk); #1;
        end
        @(negedge clk); #1;
        wri_vld[`IQ_ID_LDB] = 1'b0; wri_start[`IQ_ID_LDB] = 1'b0; wri_end[`IQ_ID_LDB] = 1'b0;
        @(posedge clk);
    end
    
    #(CLK_PERIOD * 10);
    $display("\n--- All instructions written to smi_iq (including UR) ---");
    
    // ==========================================================================
    // Step 2: Start reading from all written smi_iq
    // Set rdi_start high for 1 cycle for each IQ that has instructions
    // ==========================================================================
    $display("\n--- Step 2: Start Reading from All Written smi_iq ---");
    
    // 说明：为满足“所有涉及到的 smi_iq 的 rdi_start 在同一时刻拉高，之后再拉低”
    // 这里将所有需要启动读的 IQ 的 rdi_start 在同一个 negedge+delay 置 1，
    // 保持 1 个周期后，在下一次 negedge+delay 同时清 0。
    @(negedge clk);
    #1;
    // ID 0: INTADD
    if (inst_count_intadd > 0) begin
        $display("  Starting read from INTADD (ID 0)");
        rdi_iqsid[`IQ_ID_INTADD] = 2'b00;
        rdi_start[`IQ_ID_INTADD] = 1'b1;
    end
    // ID 1: INT8toFP16
    if (inst_count_int8tofp16 > 0) begin
        $display("  Starting read from INT8toFP16 (ID 1)");
        rdi_iqsid[`IQ_ID_INT8toFP16] = 2'b00;
        rdi_start[`IQ_ID_INT8toFP16] = 1'b1;
    end
    // ID 2: FP16MUL
    if (inst_count_fp16mul > 0) begin
        $display("  Starting read from FP16MUL (ID 2)");
        rdi_iqsid[`IQ_ID_FP16MUL] = 2'b00;
        rdi_start[`IQ_ID_FP16MUL] = 1'b1;
    end
    // ID 3: FP32ADDTREE5TO1
    if (inst_count_fp32addtree5to1 > 0) begin
        $display("  Starting read from FP32ADDTREE5TO1 (ID 3)");
        rdi_iqsid[`IQ_ID_FP32ADDTREE5TO1] = 2'b00;
        rdi_start[`IQ_ID_FP32ADDTREE5TO1] = 1'b1;
    end
    // ID 4: FP32ADDTREE8TO1
    if (inst_count_fp32addtree8to1 > 0) begin
        $display("  Starting read from FP32ADDTREE8TO1 (ID 4)");
        rdi_iqsid[`IQ_ID_FP32ADDTREE8TO1] = 2'b00;
        rdi_start[`IQ_ID_FP32ADDTREE8TO1] = 1'b1;
    end
    // ID 5: FPMUL
    if (inst_count_fpmul > 0) begin
        $display("  Starting read from FPMUL (ID 5)");
        rdi_iqsid[`IQ_ID_FPMUL] = 2'b00;
        rdi_start[`IQ_ID_FPMUL] = 1'b1;
    end
    // ID 6: FPADD
    if (inst_count_fpadd > 0) begin
        $display("  Starting read from FPADD (ID 6)");
        rdi_iqsid[`IQ_ID_FPADD] = 2'b00;
        rdi_start[`IQ_ID_FPADD] = 1'b1;
    end
    // ID 7: FPtoFP
    if (inst_count_fptofp > 0) begin
        $display("  Starting read from FPtoFP (ID 7)");
        rdi_iqsid[`IQ_ID_FPtoFP] = 2'b00;
        rdi_start[`IQ_ID_FPtoFP] = 1'b1;
    end
    // ID 8: INTtoINT
    if (inst_count_inttoint > 0) begin
        $display("  Starting read from INTtoINT (ID 8)");
        rdi_iqsid[`IQ_ID_INTtoINT] = 2'b00;
        rdi_start[`IQ_ID_INTtoINT] = 1'b1;
    end
    // ID 9: FPtoINT
    if (inst_count_fptoint > 0) begin
        $display("  Starting read from FPtoINT (ID 9)");
        rdi_iqsid[`IQ_ID_FPtoINT] = 2'b00;
        rdi_start[`IQ_ID_FPtoINT] = 1'b1;
    end
    // ID 10: INTtoFP
    if (inst_count_inttofp > 0) begin
        $display("  Starting read from INTtoFP (ID 10)");
        rdi_iqsid[`IQ_ID_INTtoFP] = 2'b00;
        rdi_start[`IQ_ID_INTtoFP] = 1'b1;
    end
    // ID 11: LOGIC
    if (inst_count_logic > 0) begin
        $display("  Starting read from LOGIC (ID 11)");
        rdi_iqsid[`IQ_ID_LOGIC] = 2'b00;
        rdi_start[`IQ_ID_LOGIC] = 1'b1;
    end
    // ID 12: SHIFTUP
    if (inst_count_shiftup > 0) begin
        $display("  Starting read from SHIFTUP (ID 12)");
        rdi_iqsid[`IQ_ID_SHIFTUP] = 2'b00;
        rdi_start[`IQ_ID_SHIFTUP] = 1'b1;
    end
    // ID 13: SHIFTDN
    if (inst_count_shiftdn > 0) begin
        $display("  Starting read from SHIFTDN (ID 13)");
        rdi_iqsid[`IQ_ID_SHIFTDN] = 2'b00;
        rdi_start[`IQ_ID_SHIFTDN] = 1'b1;
    end
    // RtoVR instances: Start reading from all loaded instances
    // 根据 inst_count_rtovr[N] 是否大于 0，决定是否对该 instance 发起读
    begin
        integer rtovr_idx;
        integer rtovr_smi_iq_id;
        
        for (rtovr_idx = 0; rtovr_idx < 40; rtovr_idx = rtovr_idx + 1) begin
            rtovr_smi_iq_id = `IQ_ID_RTOVR_BASE + rtovr_idx;
            
            if (inst_count_rtovr[rtovr_idx] > 0) begin
                $display("  Starting read from RtoVR-%0d (SMI-IQ ID %0d)", 
                         rtovr_idx, rtovr_smi_iq_id);
                rdi_iqsid[rtovr_smi_iq_id] = 2'b00;
                rdi_start[rtovr_smi_iq_id] = 1'b1;
            end
        end
    end
    // ID 14: UR-RDATA-0
    if (inst_count_ur_rdata[0] > 0) begin
        $display("  Starting read from UR-RDATA-0 (ID 14)");
        rdi_iqsid[`IQ_ID_UR_RDATA_0] = 2'b00;
        rdi_start[`IQ_ID_UR_RDATA_0] = 1'b1;
    end
    // ID 15: UR-RDATA-1
    if (inst_count_ur_rdata[1] > 0) begin
        $display("  Starting read from UR-RDATA-1 (ID 15)");
        rdi_iqsid[`IQ_ID_UR_RDATA_1] = 2'b00;
        rdi_start[`IQ_ID_UR_RDATA_1] = 1'b1;
    end
    // ID 16: UR-RDATA-2
    if (inst_count_ur_rdata[2] > 0) begin
        $display("  Starting read from UR-RDATA-2 (ID 16)");
        rdi_iqsid[`IQ_ID_UR_RDATA_2] = 2'b00;
        rdi_start[`IQ_ID_UR_RDATA_2] = 1'b1;
    end
    // ID 17: UR-RDATA-3
    if (inst_count_ur_rdata[3] > 0) begin
        $display("  Starting read from UR-RDATA-3 (ID 17)");
        rdi_iqsid[`IQ_ID_UR_RDATA_3] = 2'b00;
        rdi_start[`IQ_ID_UR_RDATA_3] = 1'b1;
    end
    // ID 18: UR-WDATA-0
    if (inst_count_ur_wdata[0] > 0) begin
        $display("  Starting read from UR-WDATA-0 (ID 18)");
        rdi_iqsid[`IQ_ID_UR_WDATA_0] = 2'b00;
        rdi_start[`IQ_ID_UR_WDATA_0] = 1'b1;
    end
    // ID 19: UR-WDATA-1
    if (inst_count_ur_wdata[1] > 0) begin
        $display("  Starting read from UR-WDATA-1 (ID 19)");
        rdi_iqsid[`IQ_ID_UR_WDATA_1] = 2'b00;
        rdi_start[`IQ_ID_UR_WDATA_1] = 1'b1;
    end
    // ID 20: UR-WDATA-2
    if (inst_count_ur_wdata[2] > 0) begin
        $display("  Starting read from UR-WDATA-2 (ID 20)");
        rdi_iqsid[`IQ_ID_UR_WDATA_2] = 2'b00;
        rdi_start[`IQ_ID_UR_WDATA_2] = 1'b1;
    end
    // ID 21: UR-WDATA-3
    if (inst_count_ur_wdata[3] > 0) begin
        $display("  Starting read from UR-WDATA-3 (ID 21)");
        rdi_iqsid[`IQ_ID_UR_WDATA_3] = 2'b00;
        rdi_start[`IQ_ID_UR_WDATA_3] = 1'b1;
    end
    // ID 22: STB
    if (inst_count_stb > 0) begin
        $display("  Starting read from STB (ID 22)");
        rdi_iqsid[`IQ_ID_STB] = 2'b00;
        rdi_start[`IQ_ID_STB] = 1'b1;
    end
    // ID 23: LDB
    if (inst_count_ldb > 0) begin
        $display("  Starting read from LDB (ID 23)");
        rdi_iqsid[`IQ_ID_LDB] = 2'b00;
        rdi_start[`IQ_ID_LDB] = 1'b1;
    end
    @(posedge clk);
    #1;

    @(negedge clk);
    #1;
    // 同时拉低所有启动过的 rdi_start
    if (inst_count_intadd > 0)           rdi_start[`IQ_ID_INTADD] = 1'b0;
    if (inst_count_int8tofp16 > 0)       rdi_start[`IQ_ID_INT8toFP16] = 1'b0;
    if (inst_count_fp16mul > 0)          rdi_start[`IQ_ID_FP16MUL] = 1'b0;
    if (inst_count_fp32addtree5to1 > 0) rdi_start[`IQ_ID_FP32ADDTREE5TO1] = 1'b0;
    if (inst_count_fp32addtree8to1 > 0) rdi_start[`IQ_ID_FP32ADDTREE8TO1] = 1'b0;
    if (inst_count_fpmul > 0)            rdi_start[`IQ_ID_FPMUL] = 1'b0;
    if (inst_count_fpadd > 0)            rdi_start[`IQ_ID_FPADD] = 1'b0;
    if (inst_count_fptofp > 0)           rdi_start[`IQ_ID_FPtoFP] = 1'b0;
    if (inst_count_inttoint > 0)         rdi_start[`IQ_ID_INTtoINT] = 1'b0;
    if (inst_count_fptoint > 0)          rdi_start[`IQ_ID_FPtoINT] = 1'b0;
    if (inst_count_inttofp > 0)         rdi_start[`IQ_ID_INTtoFP] = 1'b0;
    if (inst_count_logic > 0)            rdi_start[`IQ_ID_LOGIC] = 1'b0;
    if (inst_count_shiftup > 0)          rdi_start[`IQ_ID_SHIFTUP] = 1'b0;
    if (inst_count_shiftdn > 0)          rdi_start[`IQ_ID_SHIFTDN] = 1'b0;
    begin
        integer rtovr_idx;
        integer rtovr_smi_iq_id;
        
        for (rtovr_idx = 0; rtovr_idx < 40; rtovr_idx = rtovr_idx + 1) begin
            rtovr_smi_iq_id = `IQ_ID_RTOVR_BASE + rtovr_idx;
            if (inst_count_rtovr[rtovr_idx] > 0) begin
                rdi_start[rtovr_smi_iq_id] = 1'b0;
            end
        end
    end
    if (inst_count_ur_rdata[0] > 0) rdi_start[`IQ_ID_UR_RDATA_0] = 1'b0;
    if (inst_count_ur_rdata[1] > 0) rdi_start[`IQ_ID_UR_RDATA_1] = 1'b0;
    if (inst_count_ur_rdata[2] > 0) rdi_start[`IQ_ID_UR_RDATA_2] = 1'b0;
    if (inst_count_ur_rdata[3] > 0) rdi_start[`IQ_ID_UR_RDATA_3] = 1'b0;
    if (inst_count_ur_wdata[0] > 0) rdi_start[`IQ_ID_UR_WDATA_0] = 1'b0;
    if (inst_count_ur_wdata[1] > 0) rdi_start[`IQ_ID_UR_WDATA_1] = 1'b0;
    if (inst_count_ur_wdata[2] > 0) rdi_start[`IQ_ID_UR_WDATA_2] = 1'b0;
    if (inst_count_ur_wdata[3] > 0) rdi_start[`IQ_ID_UR_WDATA_3] = 1'b0;
    if (inst_count_stb > 0)         rdi_start[`IQ_ID_STB] = 1'b0;
    if (inst_count_ldb > 0)         rdi_start[`IQ_ID_LDB] = 1'b0;
    @(posedge clk);
    #1;
    
    $display("\n--- All read starts issued ---");
    
    #(CLK_PERIOD * 100);
    
    $display("\n==================================================");
    $display("Test Complete");
    $display("==================================================");

    // ==========================================================================
    // Dump DUT User Register: all 8 banks, full memory_array, to .hex files.
    // Format matches test_atomic_ops/fp16mul/bank0_x.hex: one line per 128-bit word,
    // 32 hex chars per line, no prefix. X/Z written as 0.
    // Filename format: ur_result_<case_name>_bank0.hex (统一格式，适用于单 case 和多 case 模式)
    // ==========================================================================
    begin
        integer f0, f1, f2, f3, f4, f5, f6, f7, addr;
        reg [127:0] v;
        string ur_dump_filename_base, ur_dump_path_base;
        integer slash_pos, i;
        string case_name_from_path;
        
        // 从 runtime_subfolder 提取 case 名（最后一个 "/" 之后的部分）
        // 如果 runtime_subfolder 包含 "/"，提取最后一部分；否则使用整个字符串
        case_name_from_path = runtime_subfolder;
        slash_pos = -1;
        for (i = 0; i < runtime_subfolder.len(); i = i + 1) begin
            if (runtime_subfolder.getc(i) == "/") begin
                slash_pos = i;
            end
        end
        if (slash_pos >= 0 && slash_pos < runtime_subfolder.len() - 1) begin
            // 提取最后一个 "/" 之后的部分
            case_name_from_path = runtime_subfolder.substr(slash_pos + 1, runtime_subfolder.len() - 1);
        end
        
        // 构建 UR dump 文件名：ur_result_<case_name>_bank0.hex
        // 单 case 和多 case 模式统一使用此格式
        if (case_name_from_path.len() > 0) begin
            ur_dump_filename_base = $sformatf("ur_result_%s", case_name_from_path);
        end else begin
            ur_dump_filename_base = "ur_result";
        end
        
        // 构建完整路径：test_atomic_ops/<runtime_subfolder>/ur_result_<case_name>_bank0.hex
        // 注意：文件写入到 case 目录下（与 data_list 同一目录）
        ur_dump_path_base = $sformatf("%s/%s", `MEM_DATA_BASE, runtime_subfolder);
        ur_dump_file0 = $sformatf("%s/%s_bank0.hex", ur_dump_path_base, ur_dump_filename_base);
        ur_dump_file1 = $sformatf("%s/%s_bank1.hex", ur_dump_path_base, ur_dump_filename_base);
        ur_dump_file2 = $sformatf("%s/%s_bank2.hex", ur_dump_path_base, ur_dump_filename_base);
        ur_dump_file3 = $sformatf("%s/%s_bank3.hex", ur_dump_path_base, ur_dump_filename_base);
        ur_dump_file4 = $sformatf("%s/%s_bank4.hex", ur_dump_path_base, ur_dump_filename_base);
        ur_dump_file5 = $sformatf("%s/%s_bank5.hex", ur_dump_path_base, ur_dump_filename_base);
        ur_dump_file6 = $sformatf("%s/%s_bank6.hex", ur_dump_path_base, ur_dump_filename_base);
        ur_dump_file7 = $sformatf("%s/%s_bank7.hex", ur_dump_path_base, ur_dump_filename_base);
        
        $display("  UR dump 路径: %s", ur_dump_path_base);
        
        f0 = $fopen(ur_dump_file0, "w");
        f1 = $fopen(ur_dump_file1, "w");
        f2 = $fopen(ur_dump_file2, "w");
        f3 = $fopen(ur_dump_file3, "w");
        f4 = $fopen(ur_dump_file4, "w");
        f5 = $fopen(ur_dump_file5, "w");
        f6 = $fopen(ur_dump_file6, "w");
        f7 = $fopen(ur_dump_file7, "w");
        for (addr = 0; addr < 256; addr = addr + 1) begin
            v = dut.u_smc.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array[addr];
            $fwrite(f0, "%032h\n", $isunknown(v) ? 128'b0 : v);
            v = dut.u_smc.u_user_register.bram_bank_inst[1].u_bank_sram.memory_array[addr];
            $fwrite(f1, "%032h\n", $isunknown(v) ? 128'b0 : v);
            v = dut.u_smc.u_user_register.bram_bank_inst[2].u_bank_sram.memory_array[addr];
            $fwrite(f2, "%032h\n", $isunknown(v) ? 128'b0 : v);
            v = dut.u_smc.u_user_register.bram_bank_inst[3].u_bank_sram.memory_array[addr];
            $fwrite(f3, "%032h\n", $isunknown(v) ? 128'b0 : v);
            v = dut.u_smc.u_user_register.bram_bank_inst[4].u_bank_sram.memory_array[addr];
            $fwrite(f4, "%032h\n", $isunknown(v) ? 128'b0 : v);
            v = dut.u_smc.u_user_register.bram_bank_inst[5].u_bank_sram.memory_array[addr];
            $fwrite(f5, "%032h\n", $isunknown(v) ? 128'b0 : v);
            v = dut.u_smc.u_user_register.bram_bank_inst[6].u_bank_sram.memory_array[addr];
            $fwrite(f6, "%032h\n", $isunknown(v) ? 128'b0 : v);
            v = dut.u_smc.u_user_register.bram_bank_inst[7].u_bank_sram.memory_array[addr];
            $fwrite(f7, "%032h\n", $isunknown(v) ? 128'b0 : v);
        end
        $fclose(f0);
        $fclose(f1);
        $fclose(f2);
        $fclose(f3);
        $fclose(f4);
        $fclose(f5);
        $fclose(f6);
        $fclose(f7);
    end

    $display("\n==================================================");
    $display("Files Dumped to:");
    $display("  %s", ur_dump_file0);
    $display("  %s", ur_dump_file1);
    $display("  %s", ur_dump_file2);
    $display("  %s", ur_dump_file3);
    $display("  %s", ur_dump_file4);
    $display("  %s", ur_dump_file5);
    $display("  %s", ur_dump_file6);
    $display("  %s", ur_dump_file7);
    $display("==================================================");

    $finish;
end

// ==========================================================================
// Monitor
// ==========================================================================
initial begin
    $monitor("Time=%0t: cru_intadd_o=%h, inst_valid=%b", 
             $time, cru_intadd_o, cru_intadd_o[0]);
end

endmodule

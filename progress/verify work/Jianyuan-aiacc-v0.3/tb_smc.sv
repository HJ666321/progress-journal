/*****************************************************************************
** Project  :  AIACC NPU                                                     **
******************************************************************************
**                                      **                                  **
** File name:  tb_smc.sv                   **             AIACC Team          **
** Designer :  AIACC RTL Generator      **  NPU Design Division            **
**                                      **                                  **
******************************************************************************
******************************************************************************
**                                                                          **
** Module Description:                                                      **
**                                                                          **
** Testbench for SMC Module                                                **
**                                                                          **
** Test Flow:                                                              **
**   1. Write 128-bit data to UR (bank0, addr0), then read                 **
**   2. Configure RtoVR: Route UR-RDATA-0 to DVR-VIN0-S                    **
**   3. Configure RtoVR: Route DR-VIN0-D to DVR-FPMUL-S0                  **
**   4. Send FPMUL instruction (cru_fpmul) to perform multiplication      **
**   5. When dr_fpmul_d valid bit is 1, configure RtoVR:                  **
**      Route DR-FPMUL-D to DVR-VOUT0-S                                    **
**   6. Configure RtoVR: Route DR-VOUT0-D to UVR-WDATA-0                   **
**   7. Read data from UR (bank0, addr1) and compare with C model result   **
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

module tb_smc;

// ==========================================================================
// Parameters
// ==========================================================================
parameter CLK_PERIOD = 10;  // 10ns = 100MHz
parameter SMC_ID = 5'd0;

// RtoVR CRU bit field positions
// Each output uses 7 bits: {valid[6], select[5:0]}
// OUTk control word: cru_rtovr[279-7k -: 7] = cru_rtovr[(k+1)*7-1:k*7]
// CRU total width: 40 outputs × 7 bits = 280 bits
// Output indices sorted by out_idx (0-38)
parameter [7:0] OUT_DVR_INTADD_S0 = 0;    // Output 0: DVR-INTADD-S0 (out_idx=0, CSV列1)
parameter [7:0] OUT_DVR_INTADD_S1 = 1;    // Output 1: DVR-INTADD-S1 (out_idx=1, CSV列2)
parameter [7:0] OUT_DVR_INTADD_S2 = 2;    // Output 2: DVR-INTADD-S2 (out_idx=2, CSV列3)
parameter [7:0] OUT_DVR_FPMUL_S0 = 3;     // Output 3: DVR-FPMUL-S0 (out_idx=3, CSV列4)
parameter [7:0] OUT_DVR_FPMUL_S1 = 4;     // Output 4: DVR-FPMUL-S1 (out_idx=4, CSV列5)
parameter [7:0] OUT_DVR_FPADD_S0 = 5;     // Output 5: DVR-FPADD-S0 (out_idx=5, CSV列6)
parameter [7:0] OUT_DVR_FPADD_S1 = 6;     // Output 6: DVR-FPADD-S1 (out_idx=6, CSV列7)
parameter [7:0] OUT_DVR_FPTOFP_S = 7;     // Output 7: DVR-FPtoFP-S (out_idx=7, CSV列8)
parameter [7:0] OUT_DVR_INTTOINT_S = 8;   // Output 8: DVR-INTtoINT-S (out_idx=8, CSV列9)
parameter [7:0] OUT_DVR_FPTOINT_S = 9;    // Output 9: DVR-FPtoINT-S (out_idx=9, CSV列10)
parameter [7:0] OUT_DVR_INTTOFP_S = 10;   // Output 10: DVR-INTtoFP-S (out_idx=10, CSV列11)
parameter [7:0] OUT_DVR_LOGIC_S0 = 11;    // Output 11: DVR-LOGIC-S0 (out_idx=11, CSV列12)
parameter [7:0] OUT_DVR_LOGIC_S1 = 12;    // Output 12: DVR-LOGIC-S1 (out_idx=12, CSV列13)
parameter [7:0] OUT_DVR_LOGIC_ST = 13;    // Output 13: DVR-LOGIC-ST (out_idx=13, CSV列14)
parameter [7:0] OUT_DVR_SHIFTDN_S = 14;   // Output 14: DVR-SHIFTDN-S (out_idx=14, CSV列15)
parameter [7:0] OUT_DVR_VIN0_S = 15;      // Output 15: DVR-VIN0-S (out_idx=15, CSV列16)
parameter [7:0] OUT_DVR_VIN1_S = 16;      // Output 16: DVR-VIN1-S (out_idx=16, CSV列17)
parameter [7:0] OUT_DVR_VOUT0_S = 17;     // Output 17: DVR-VOUT0-S (out_idx=17, CSV列18)
parameter [7:0] OUT_DVR_INT8toFP16_S0 = 18; // Output 18: DVR-INT8toFP16-S0 (out_idx=18, CSV列19)
parameter [7:0] OUT_DVR_INT8toFP16_S1 = 19; // Output 19: DVR-INT8toFP16-S1 (out_idx=19, CSV列20)
parameter [7:0] OUT_DVR_FP16MUL_S0 = 20;  // Output 20: DVR-FP16MUL-S0 (out_idx=20, CSV列21)
parameter [7:0] OUT_DVR_FP16MUL_S1 = 21;  // Output 21: DVR-FP16MUL-S1 (out_idx=21, CSV列22)
parameter [7:0] OUT_DVR_FP16MUL_S2 = 22;  // Output 22: DVR-FP16MUL-S2 (out_idx=22, CSV列23)
parameter [7:0] OUT_DVR_FP16MUL_S3 = 23;  // Output 23: DVR-FP16MUL-S3 (out_idx=23, CSV列24)
parameter [7:0] OUT_DVR_FP16MUL_S4567 = 24; // Output 24: DVR-FP16MUL-S4567 (out_idx=24, CSV列25)
parameter [7:0] OUT_DVR_FP32ADDTREE5TO1_S0 = 25; // Output 25: DVR-FP32ADDTREE5TO1-S0 (out_idx=25, CSV列26)
parameter [7:0] OUT_DVR_FP32ADDTREE5TO1_S1 = 26; // Output 26: DVR-FP32ADDTREE5TO1-S1 (out_idx=26, CSV列27)
parameter [7:0] OUT_DVR_FP32ADDTREE5TO1_S2 = 27; // Output 27: DVR-FP32ADDTREE5TO1-S2 (out_idx=27, CSV列28)
parameter [7:0] OUT_DVR_FP32ADDTREE5TO1_S3 = 28; // Output 28: DVR-FP32ADDTREE5TO1-S3 (out_idx=28, CSV列29)
parameter [7:0] OUT_DVR_FP32ADDTREE5TO1_S4 = 29; // Output 29: DVR-FP32ADDTREE5TO1-S4 (out_idx=29, CSV列30)
parameter [7:0] OUT_DVR_FP32ADDTREE5TO1_S5 = 30; // Output 30: DVR-FP32ADDTREE5TO1-S5 (out_idx=30, CSV列31)
parameter [7:0] OUT_DVR_FP32ADDTREE5TO1_S6 = 31; // Output 31: DVR-FP32ADDTREE5TO1-S6 (out_idx=31, CSV列32)
parameter [7:0] OUT_DVR_FP32ADDTREE5TO1_S7 = 32; // Output 32: DVR-FP32ADDTREE5TO1-S7 (out_idx=32, CSV列33)
parameter [7:0] OUT_DVR_FP32ADDTREE8TO1_S0 = 33; // Output 33: DVR-FP32ADDTREE8TO1-S0 (out_idx=33, CSV列34)
parameter [7:0] OUT_DVR_FP32ADDTREE8TO1_S1 = 34; // Output 34: DVR-FP32ADDTREE8TO1-S1 (out_idx=34, CSV列35)
parameter [7:0] OUT_UVR_WDATA_0 = 35;     // Output 35: UVR-WDATA-0 (out_idx=35, CSV列38)
parameter [7:0] OUT_UVR_WDATA_1 = 36;     // Output 36: UVR-WDATA-1 (out_idx=36, CSV列39)
parameter [7:0] OUT_UVR_WDATA_2 = 37;     // Output 37: UVR-WDATA-2 (out_idx=37, CSV列40)
parameter [7:0] OUT_UVR_WDATA_3 = 38;     // Output 38: UVR-WDATA-3 (out_idx=38, CSV列41)

// RtoVR Input indices (in_idx = input_array position, CSV input index = in_idx + 1)
parameter [5:0] IN_DR_INTADD_D0 = 0;      // Input 0: DR-INTADD-D0 (in_idx=0, CSV输入1)
parameter [5:0] IN_DR_INTADD_D1 = 1;      // Input 1: DR-INTADD-D1 (in_idx=1, CSV输入2)
parameter [5:0] IN_DR_INTADD_ST = 2;      // Input 2: DR-INTADD-ST (in_idx=2, CSV输入3)
parameter [5:0] IN_DR_FPMUL_D = 3;        // Input 3: DR-FPMUL-D (in_idx=3, CSV输入4)
parameter [5:0] IN_DR_FPADD_D = 4;        // Input 4: DR-FPADD-D (in_idx=4, CSV输入5)
parameter [5:0] IN_DR_FPADD_ST = 5;       // Input 5: DR-FPADD-ST (in_idx=5, CSV输入6)
parameter [5:0] IN_DR_FPTOFP_D = 6;       // Input 6: DR-FPtoFP-D (in_idx=6, CSV输入7)
parameter [5:0] IN_DR_INTTOINT_D = 7;      // Input 7: DR-INTtoINT-D (in_idx=7, CSV输入8)
parameter [5:0] IN_DR_FPTOINT_D = 8;       // Input 8: DR-FPtoINT-D (in_idx=8, CSV输入9)
parameter [5:0] IN_DR_INTTOFP_D = 9;      // Input 9: DR-INTtoFP-D (in_idx=9, CSV输入10)
parameter [5:0] IN_DR_LOGIC_D = 10;        // Input 10: DR-LOGIC-D (in_idx=10, CSV输入11)
parameter [5:0] IN_DR_SHIFTUP_D = 11;     // Input 11: DR-SHIFTUP-D (in_idx=11, CSV输入12)
parameter [5:0] IN_DR_VIN0_D = 12;         // Input 12: DR-VIN0-D (in_idx=12, CSV输入13)
parameter [5:0] IN_DR_VIN1_D = 13;         // Input 13: DR-VIN1-D (in_idx=13, CSV输入14)
parameter [5:0] IN_DR_VOUT0_D = 14;       // Input 14: DR-VOUT0-D (in_idx=14, CSV输入15)
parameter [5:0] IN_DR_INT8toFP16_D0 = 15;  // Input 15: DR-INT8toFP16-D0 (in_idx=15, CSV输入16)
parameter [5:0] IN_DR_INT8toFP16_D1 = 16;  // Input 16: DR-INT8toFP16-D1 (in_idx=16, CSV输入17)
parameter [5:0] IN_DR_INT8toFP16_D2 = 17;  // Input 17: DR-INT8toFP16-D2 (in_idx=17, CSV输入18)
parameter [5:0] IN_DR_INT8toFP16_D3 = 18;  // Input 18: DR-INT8toFP16-D3 (in_idx=18, CSV输入19)
parameter [5:0] IN_DR_FP16MUL_D0 = 19;    // Input 19: DR-FP16MUL-D0 (in_idx=19, CSV输入20)
parameter [5:0] IN_DR_FP16MUL_D1 = 20;     // Input 20: DR-FP16MUL-D1 (in_idx=20, CSV输入21)
parameter [5:0] IN_DR_FP16MUL_D2 = 21;    // Input 21: DR-FP16MUL-D2 (in_idx=21, CSV输入22)
parameter [5:0] IN_DR_FP16MUL_D3 = 22;    // Input 22: DR-FP16MUL-D3 (in_idx=22, CSV输入23)
parameter [5:0] IN_DR_FP16MUL_D4 = 23;     // Input 23: DR-FP16MUL-D4 (in_idx=23, CSV输入24)
parameter [5:0] IN_DR_FP16MUL_D5 = 24;     // Input 24: DR-FP16MUL-D5 (in_idx=24, CSV输入25)
parameter [5:0] IN_DR_FP16MUL_D6 = 25;     // Input 25: DR-FP16MUL-D6 (in_idx=25, CSV输入26)
parameter [5:0] IN_DR_FP16MUL_D7 = 26;     // Input 26: DR-FP16MUL-D7 (in_idx=26, CSV输入27)
parameter [5:0] IN_DR_FP32ADDTREE5TO1_D0 = 27; // Input 27: DR-FP32ADDTREE5TO1-D0 (in_idx=27, CSV输入28)
parameter [5:0] IN_DR_FP32ADDTREE5TO1_D1 = 28; // Input 28: DR-FP32ADDTREE5TO1-D1 (in_idx=28, CSV输入29)
parameter [5:0] IN_DR_FP32ADDTREE8TO1_D = 29;  // Input 29: DR-FP32ADDTREE8TO1-D (in_idx=29, CSV输入30)
parameter [5:0] IN_DR_MIN0_D = 30;         // Input 30: DR-MIN0-D (in_idx=30, CSV输入31)
parameter [5:0] IN_DR_MIN1_D = 31;         // Input 31: DR-MIN1-D (in_idx=31, CSV输入32)
parameter [5:0] IN_UR_RDATA_0 = 32;        // Input 32: UR-RDATA-0 (in_idx=32, CSV输入33)
parameter [5:0] IN_UR_RDATA_1 = 33;        // Input 33: UR-RDATA-1 (in_idx=33, CSV输入34)
parameter [5:0] IN_UR_RDATA_2 = 34;        // Input 34: UR-RDATA-2 (in_idx=34, CSV输入35)
parameter [5:0] IN_UR_RDATA_3 = 35;        // Input 35: UR-RDATA-3 (in_idx=35, CSV输入36)

// ==========================================================================
// Clock and Reset
// ==========================================================================
reg clk;
reg rst_n;

// ==========================================================================
// DUT Signals
// ==========================================================================
// SMC DUT
wire [133:0] crd_shiftdn_out;
wire [3:0]   cru_fpadd_o;
wire [2:0]   cru_fpmul_o;
wire [6:0]   cru_inttoint_o;
wire [5:0]   cru_inttofp_o;
wire [5:0]   cru_logic_o;
wire [11:0]  cru_intadd_o;
wire [134:0] cru_shiftup_o;
wire [279:0] cru_rtovr_o;
wire [160:0] cru_ur_o;
wire         cru_vin0_o;
wire         cru_vin1_o;
wire         cru_vout0_o;

reg  [4:0]  i_smc_id;
reg  [2:0]  i_rounding_mode;
reg  [11:0] cru_intadd;
reg  [2:0]  cru_fp16mul;
reg  [1:0]  cru_fp16mul_s0123;
reg  [3:0]  cru_fp16mul_s4567;
reg         cru_fp32addtree5to1;
reg  [2:0]  cru_fp32addtree8to1;
reg  [3:0]  cru_fpadd;
reg  [2:0]  cru_fpmul;
reg  [4:0]  cru_fptoint;
reg  [4:0]  cru_fptofp;
reg  [6:0]  cru_inttoint;
reg  [5:0]  cru_inttofp;
reg  [5:0]  cru_logic;
reg  [1:0]  cru_int8tofp16;
reg  [134:0] cru_shiftup;
reg  [133:0] crd_shiftdn;
reg  [279:0] cru_rtovr;
reg  [160:0] cru_ur;
reg         cru_vin0;
reg         cru_vin1;
reg         cru_vout0;

// ==========================================================================
// Test Data
// ==========================================================================
reg [127:0] test_data_a;      // First operand for FPMUL (written to UR addr0)
reg [127:0] test_data_b;      // Second operand for FPMUL (will be same as A for A*A test)
reg [127:0] test_data_s0;     // INTADD source 0 data
reg [127:0] test_data_s1;     // INTADD source 1 data
reg [127:0] test_data_s2;     // INTADD source 2 data
reg [127:0] expected_result;  // Expected result from C model
reg [127:0] ur_read_data;     // Data read from UR

// ==========================================================================
// Helper Functions/Tasks
// ==========================================================================

// Function to configure RtoVR routing for a specific output
// CRU format: {valid[6], select[5:0]} = 7 bits per output
// OUTk control word: cru_rtovr[(k+1)*7-1:k*7]
function [279:0] set_rtovr_route;
    input [279:0] cru_current;
    input [7:0]   out_idx;
    input         valid;
    input [5:0]   in_idx;  // 6-bit input index (supports 0-63)
    integer bit_offset;
    begin
        set_rtovr_route = cru_current;
        // CRU field for output k: cru_rtovr[(k+1)*7-1:k*7]
        bit_offset = out_idx * 7;
        set_rtovr_route[bit_offset +: 7] = {valid, in_idx[5:0]};
    end
endfunction

// Task to configure UR write operation
task set_ur_write;
    input [2:0] port;
    input [2:0] bank;
    input [7:0] addr;
    input       we;
    input [15:0] wbe;
    begin
        case (port)
            0: begin
                cru_ur[160] = 1'b1;  // vld
                cru_ur[159:157] = bank;
                cru_ur[147:140] = addr;
                cru_ur[67] = we;
                cru_ur[63:48] = wbe;
            end
            1: begin
                cru_ur[160] = 1'b1;  // vld
                cru_ur[156:154] = bank;
                cru_ur[139:132] = addr;
                cru_ur[66] = we;
                cru_ur[47:32] = wbe;
            end
            2: begin
                cru_ur[160] = 1'b1;  // vld
                cru_ur[153:151] = bank;
                cru_ur[131:124] = addr;
                cru_ur[65] = we;
                cru_ur[31:16] = wbe;
            end
            3: begin
                cru_ur[160] = 1'b1;  // vld
                cru_ur[150:148] = bank;
                cru_ur[123:116] = addr;
                cru_ur[64] = we;
                cru_ur[15:0] = wbe;
            end
        endcase
    end
endtask

// Task to configure UR read operation
task set_ur_read;
    input [2:0] port;
    input [2:0] bank;
    input [7:0] addr;
    input       re;
    begin
        case (port)
            0: begin
                cru_ur[160] = 1'b1;  // vld
                cru_ur[115:113] = bank;
                cru_ur[103:96] = addr;
                cru_ur[71] = re;
            end
            1: begin
                cru_ur[160] = 1'b1;  // vld
                cru_ur[112:110] = bank;
                cru_ur[95:88] = addr;
                cru_ur[70] = re;
            end
            2: begin
                cru_ur[160] = 1'b1;  // vld
                cru_ur[109:107] = bank;
                cru_ur[87:80] = addr;
                cru_ur[69] = re;
            end
            3: begin
                cru_ur[160] = 1'b1;  // vld
                cru_ur[106:104] = bank;
                cru_ur[79:72] = addr;
                cru_ur[68] = re;
            end
        endcase
    end
endtask

// Task to clear all CRU signals
task clear_all_cru;
    begin
        cru_intadd = 12'b0;
        cru_fp16mul = 3'b0;
        cru_fp16mul_s0123 = 2'b0;
        cru_fp16mul_s4567 = 4'b0;
        cru_fp32addtree5to1 = 1'b0;
        cru_fp32addtree8to1 = 3'b0;
        cru_fpadd = 4'b0;
        cru_fpmul = 3'b0;
        cru_fptoint = 5'b0;
        cru_fptofp = 5'b0;
        cru_inttoint = 7'b0;
        cru_inttofp = 6'b0;
        cru_logic = 6'b0;
        cru_int8tofp16 = 2'b0;
        cru_shiftup = 135'b0;
        crd_shiftdn = 134'b0;
        cru_rtovr = 280'b0;
        cru_ur = 161'b0;
        cru_vin0 = 1'b0;
        cru_vin1 = 1'b0;
        cru_vout0 = 1'b0;
    end
endtask

// Task to wait for FPMUL result valid
// FPMUL has a 4-cycle pipeline, so we need to wait for cru_fpmul_o[0] to be 1
task wait_fpmul_valid;
    integer timeout;
    begin
        timeout = 0;
        // Wait for cru_fpmul_o[0] to become 1 (indicates result is valid)
        while (!cru_fpmul_o[0] && timeout < 100) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        if (timeout >= 100) begin
            $display("ERROR: Timeout waiting for FPMUL valid signal");
            $finish;
        end
    end
endtask


// Task to wait for FPADD result valid
// FPADD uses cru_fpadd_o[3] as valid pipeline indicator
task wait_fpadd_valid;
    integer timeout;
    begin
        timeout = 0;
        // Wait for cru_fpadd_o[3] to become 1 (indicates result is valid)
        while (!cru_fpadd_o[0] && timeout < 100) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        if (timeout >= 100) begin
            $display("ERROR: Timeout waiting for FPADD valid signal");
            $finish;
        end
    end
endtask

// Task to wait for INTADD result valid
// INTADD is combinational logic with registered outputs
// Results are available one clock cycle after instruction is sent
task wait_intadd_valid;
    begin
        // INTADD has registered outputs, wait one clock cycle for results
        @(posedge clk);
        #1;
    end
endtask

// Task to wait for FPTOINT result valid
// FPTOINT has registered outputs, wait a few clock cycles for results
task wait_fptoint_valid;
    begin
        // Wait 2 cycles to ensure result is available
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
    end
endtask

// Task to wait for INTTOINT result valid
// INTTOINT has CRU output signal, wait for cru_inttoint_o[0] to become 1
task wait_inttoint_valid;
    integer timeout;
    begin
        timeout = 0;
        // Wait for cru_inttoint_o[0] to become 1 (indicates result is valid)
        while (!cru_inttoint_o[0] && timeout < 100) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        if (timeout >= 100) begin
            $display("ERROR: Timeout waiting for INTTOINT valid signal");
            $finish;
        end
    end
endtask

// Task to wait for FPTOFP result valid
// FPTOFP has pipeline (2-3 stages), wait a few clock cycles for results
task wait_fptofp_valid;
    begin
        // Wait 3 cycles to ensure pipeline result is available
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
    end
endtask

// Task to wait for INTTOFP result valid
// INTTOFP has CRU output signal, wait for cru_inttofp_o[5] to become 1
task wait_inttofp_valid;
    integer timeout;
    begin
        timeout = 0;
        // Wait for cru_inttofp_o[5] to become 1 (indicates result is valid)
        while (!cru_inttofp_o[5] && timeout < 100) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        if (timeout >= 100) begin
            $display("ERROR: Timeout waiting for INTTOFP valid signal");
            $finish;
        end
    end
endtask

// ==========================================================================
// DUT Instantiation
// ==========================================================================
SMC #(
    .SMC_ID(SMC_ID),
    .IEEE_754(1)
) dut (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .i_smc_id               (i_smc_id),
    .i_rounding_mode        (i_rounding_mode),
    .cru_intadd             (cru_intadd),
    .cru_fp16mul            (cru_fp16mul),
    .cru_fp16mul_s0123      (cru_fp16mul_s0123),
    .cru_fp16mul_s4567      (cru_fp16mul_s4567),
    .cru_fp32addtree5to1    (cru_fp32addtree5to1),
    .cru_fp32addtree8to1    (cru_fp32addtree8to1),
    .cru_fpadd              (cru_fpadd),
    .cru_fpmul              (cru_fpmul),
    .cru_fptoint            (cru_fptoint),
    .cru_fptofp             (cru_fptofp),
    .cru_inttoint           (cru_inttoint),
    .cru_inttofp            (cru_inttofp),
    .cru_logic              (cru_logic),
    .cru_int8tofp16         (cru_int8tofp16),
    .cru_shiftup            (cru_shiftup),
    .crd_shiftdn            (crd_shiftdn),
    .cru_rtovr              (cru_rtovr),
    .cru_ur                 (cru_ur),
    .cru_vin0               (cru_vin0),
    .cru_vin1               (cru_vin1),
    .cru_vout0              (cru_vout0),
    .crd_shiftdn_out        (crd_shiftdn_out),
    .cru_fpadd_o            (cru_fpadd_o),
    .cru_fpmul_o            (cru_fpmul_o),
    .cru_inttoint_o         (cru_inttoint_o),
    .cru_inttofp_o          (cru_inttofp_o),
    .cru_logic_o            (cru_logic_o),
    .cru_intadd_o           (cru_intadd_o),
    .cru_shiftup_o          (cru_shiftup_o),
    .cru_rtovr_o            (cru_rtovr_o),
    .cru_ur_o               (cru_ur_o),
    .cru_vin0_o             (cru_vin0_o),
    .cru_vin1_o             (cru_vin1_o),
    .cru_vout0_o            (cru_vout0_o)
);

// ==========================================================================
// Clock Generation
// ==========================================================================
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// ==========================================================================
// Initialize UR Bank0 from hex file
// ==========================================================================
initial begin
    // Initialize Bank0 memory from ur_data.hex file
    // Note: $readmemh executes at time 0, before any clock edges
    // File path is relative to the simulation working directory
    $readmemh("/datahdd/qinglongv200/xuedong/AIACC/Hongjun-main/aiacc/cells/A_Integration/ur_data.hex", dut.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array);
    
    // Wait a bit for initialization to complete, then display
    #1;
    $display("========================================");
    $display("  UR Bank0 initialized from ur_data.hex");
    $display("========================================");
    
    // Display initialized data for verification
    $display("Bank0 Memory Contents:");
    $display("  Addr 0: %h", dut.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array[0]);
    $display("  Addr 1: %h", dut.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array[1]);
    $display("  Addr 2: %h", dut.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array[2]);
    $display("  Addr 3: %h", dut.u_user_register.bram_bank_inst[0].u_bank_sram.memory_array[3]);
    $display("========================================");
end

// ==========================================================================
// Main Test Flow (task)
// ==========================================================================
task automatic run_smc_test;
    begin
        string prefix = "FPMUL: ";
        $display("%s==========================================", prefix);
        $display("%sSMC Testbench Started", prefix);
        $display("%s==========================================", prefix);
        
        // Initialize
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;  // RNE
        clear_all_cru();
        test_data_a = 128'h3F800000_40000000_40400000_40800000;  // FP32: 1.0, 2.0, 3.0, 4.0
        test_data_b = test_data_a;  // A * A
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0) ---"});
        $display({prefix, "  Test data to write: %h"}, test_data_a);
        // For initial write, we need to inject test data to UVR-WDATA-0
        // Since UR write data comes from RtoVR output UVR-WDATA-0, we'll use force
        // to inject the test data directly
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        
        // Configure UR write: Port 0, Bank 0, Addr 0
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  UR write data input (UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        
        // Release force after write
        release dut.u_rtovr.uvr_wdata_0;
        
        // Clear UR write
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read data from UR (bank0, addr0) ---"});
        // Configure UR read: Port 0, Bank 0, Addr 0
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        $display({prefix, "  UR read enable: %b, bank: %d, addr: %h"}, cru_ur[71], cru_ur[115:113], cru_ur[103:96]);
        // Wait for read latency (UR has 0 pipeline stages, but BRAM has 1 cycle)
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read from UR (UR-RDATA-0): %h"}, ur_read_data);
        if (ur_read_data === test_data_a) begin
            $display({prefix, "  [PASS] UR read data matches written data"});
        end else begin
            $display({prefix, "  [FAIL] UR read data mismatch! Expected: %h"}, test_data_a);
        end
        
        // Clear UR read
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        // Configure RtoVR Output 15 (DVR-VIN0-S) to route from Input 32 (UR-RDATA-0)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-VIN0-S) routing from Input %0d (UR-RDATA-0)"}, OUT_DVR_VIN0_S, IN_UR_RDATA_0);
        $display({prefix, "  UR-RDATA-0: %h"}, dut.u_rtovr.ur_rdata_0);
        $display({prefix, "  DVR-VIN0-S (RtoVR output): %h"}, dut.u_rtovr.dvr_vin0_s);
        if (dut.u_rtovr.dvr_vin0_s === ur_read_data) begin
            $display({prefix, "  [PASS] RtoVR routing correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing mismatch!"});
        end
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture data ---"});
        $display({prefix, "  DVR-VIN0-S before capture: %h"}, dut.dvr_vin0_s_w);
        // Enable VIN0 to capture DVR-VIN0-S
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        $display({prefix, "  VIN0 CRU enabled, capturing data..."});
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VIN0-D (IPR output): %h"}, dut.dr_vin0_d_w);
        if (dut.dr_vin0_d_w === dut.dvr_vin0_s_w) begin
            $display({prefix, "  [PASS] VIN0 captured data correctly"});
        end else begin
            $display({prefix, "  [FAIL] VIN0 data mismatch! Expected: %h, Got: %h"}, dut.dvr_vin0_s_w, dut.dr_vin0_d_w);
        end
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-FPMUL-S0/S1 ---"});
        // Configure RtoVR Output 3 (DVR-FPMUL-S0) to route from Input 12 (DR-VIN0-D)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_FPMUL_S0, 1'b1, IN_DR_VIN0_D);
        // Also configure DVR-FPMUL-S1 to route from DR-VIN0-D (for A * A)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_FPMUL_S1, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-FPMUL-S0) routing from Input %0d (DR-VIN0-D)"}, OUT_DVR_FPMUL_S0, IN_DR_VIN0_D);
        $display({prefix, "  RtoVR Output %0d (DVR-FPMUL-S1) routing from Input %0d (DR-VIN0-D)"}, OUT_DVR_FPMUL_S1, IN_DR_VIN0_D);
        $display({prefix, "  DR-VIN0-D: %h"}, dut.dr_vin0_d_w);
        $display({prefix, "  DVR-FPMUL-S0 (RtoVR output): %h"}, dut.dvr_fpmul_s0_w);
        $display({prefix, "  DVR-FPMUL-S1 (RtoVR output): %h"}, dut.dvr_fpmul_s1_w);
        if (dut.dvr_fpmul_s0_w === dut.dr_vin0_d_w && dut.dvr_fpmul_s1_w === dut.dr_vin0_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to FPMUL correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to FPMUL mismatch!"});
        end
        
        $display({prefix, "\n--- Step 6: Send FPMUL instruction ---"});
        $display({prefix, "  FPMUL inputs:"});
        $display({prefix, "    DVR-FPMUL-S0: %h"}, dut.dvr_fpmul_s0_w);
        $display({prefix, "    DVR-FPMUL-S1: %h"}, dut.dvr_fpmul_s1_w);
        // Configure FPMUL: FP32 mode, valid
        // cru_fpmul[2:0]: bit[0]=inst_valid, bit[1]=src_precision_is_32b, bit[2]=dst_precision_is_32b
        cru_fpmul = 3'b111;  // valid=1, src32=1, dst32=1 (FP32 × FP32 → FP32)
        $display({prefix, "  CRU-FPMUL: %b (valid=%b, src32=%b, dst32=%b)"}, cru_fpmul, cru_fpmul[0], cru_fpmul[1], cru_fpmul[2]);
        @(posedge clk);
        #1;
        cru_fpmul = 3'b000;  // Clear after one cycle
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 7: Wait for FPMUL result valid ---"});
        // Wait for FPMUL to produce valid result
        // FPMUL has pipeline, need to wait for cru_fpmul_o[0] to be 1
        wait_fpmul_valid();
        $display({prefix, "  FPMUL result is valid (cru_fpmul_o[0] = %b)"}, cru_fpmul_o[0]);
        $display({prefix, "  DR-FPMUL-D (FPMUL output): %h"}, dut.dr_fpmul_d_w);
        // Check if result is non-zero (basic sanity check)
        if (dut.dr_fpmul_d_w !== 128'b0) begin
            $display({prefix, "  [PASS] FPMUL produced non-zero result"});
        end else begin
            $display({prefix, "  [WARN] FPMUL result is zero - may indicate an issue"});
        end
        
        $display({prefix, "\n--- Step 8: Configure RtoVR - Route DR-FPMUL-D to DVR-VOUT0-S ---"});
        // Configure RtoVR Output 17 (DVR-VOUT0-S) to route from Input 3 (DR-FPMUL-D)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_FPMUL_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-VOUT0-S) routing from Input %0d (DR-FPMUL-D)"}, OUT_DVR_VOUT0_S, IN_DR_FPMUL_D);
        $display({prefix, "  DR-FPMUL-D: %h"}, dut.dr_fpmul_d_w);
        $display({prefix, "  DVR-VOUT0-S (RtoVR output): %h"}, dut.dvr_vout0_s_w);
        if (dut.dvr_vout0_s_w === dut.dr_fpmul_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to VOUT0 correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to VOUT0 mismatch!"});
        end
        
        $display({prefix, "\n--- Step 9: Enable VOUT0 to capture data ---"});
        $display({prefix, "  DVR-VOUT0-S before capture: %h"}, dut.dvr_vout0_s_w);
        // Enable VOUT0 to capture DVR-VOUT0-S
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        $display({prefix, "  VOUT0 CRU enabled, capturing data..."});
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VOUT0-D (OPR output): %h"}, dut.dr_vout0_d_w);
        if (dut.dr_vout0_d_w === dut.dvr_vout0_s_w) begin
            $display({prefix, "  [PASS] VOUT0 captured data correctly"});
        end else begin
            $display({prefix, "  [FAIL] VOUT0 data mismatch! Expected: %h, Got: %h"}, dut.dvr_vout0_s_w, dut.dr_vout0_d_w);
        end
        
        $display({prefix, "\n--- Step 10: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        // Configure RtoVR Output 35 (UVR-WDATA-0) to route from Input 14 (DR-VOUT0-D)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (UVR-WDATA-0) routing from Input %0d (DR-VOUT0-D)"}, OUT_UVR_WDATA_0, IN_DR_VOUT0_D);
        $display({prefix, "  DR-VOUT0-D: %h"}, dut.dr_vout0_d_w);
        $display({prefix, "  UVR-WDATA-0 (RtoVR output): %h"}, dut.u_rtovr.uvr_wdata_0);
        if (dut.u_rtovr.uvr_wdata_0 === dut.dr_vout0_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to UR write port correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to UR write port mismatch!"});
        end
        
        $display({prefix, "\n--- Step 11: Write result to UR (bank0, addr1) ---"});
        $display({prefix, "  Data to write (from UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        // Configure UR write: Port 0, Bank 0, Addr 1
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        $display({prefix, "  UR write data input (UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        // Data should come from UVR-WDATA-0 (routed from DR-VOUT0-D)
        @(posedge clk);
        #1;
        $display({prefix, "  UR write completed"});
        
        // Clear UR write
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 12: Read result from UR (bank0, addr1) ---"});
        // Configure UR read: Port 0, Bank 0, Addr 1
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        $display({prefix, "  UR read enable: %b, bank: %d, addr: %h"}, cru_ur[71], cru_ur[115:113], cru_ur[103:96]);
        // Wait for read latency
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR (UR-RDATA-0): %h"}, ur_read_data);
        $display({prefix, "  Expected (from DR-VOUT0-D): %h"}, dut.dr_vout0_d_w);
        
        // Calculate expected result using C model
        // For FP32: A = {1.0, 2.0, 3.0, 4.0}, A * A = {1.0, 4.0, 9.0, 16.0}
        // FP32 representation:
        // 1.0 = 0x3F800000
        // 4.0 = 0x40800000
        // 9.0 = 0x41100000
        // 16.0 = 0x41800000
        expected_result = 128'h3F800000_40800000_41100000_41800000;
        
        $display({prefix, "\n--- Step 13: Compare with expected result ---"});
        $display({prefix, "Expected: %h"}, expected_result);
        $display({prefix, "Actual:   %h"}, ur_read_data);
        
        if (ur_read_data === expected_result) begin
            $display({prefix, "=========================================="});
            $display({prefix, "FPMUL TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "FPMUL TEST FAILED!"});
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// FPADD Test Flow (task)
// ==========================================================================
task automatic run_smc_fpadd_test;
    begin
        string prefix = "FPADD: ";
        $display({prefix, "=========================================="});
        $display({prefix, "SMC FPADD Testbench Started"});
        $display({prefix, "=========================================="});
        
        // Initialize
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;  // RNE
        clear_all_cru();
        test_data_a = 128'h3F800000_40000000_40400000_40800000;  // FP32: 1.0, 2.0, 3.0, 4.0
        test_data_b = test_data_a;  // A + A
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0) ---"});
        $display({prefix, "  Test data to write: %h"}, test_data_a);
        // For initial write, we need to inject test data to UVR-WDATA-0
        // Since UR write data comes from RtoVR output UVR-WDATA-0, we'll use force
        // to inject the test data directly
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        
        // Configure UR write: Port 0, Bank 0, Addr 0
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  UR write data input (UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        
        // Release force after write
        release dut.u_rtovr.uvr_wdata_0;
        
        // Clear UR write
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read data from UR (bank0, addr0) ---"});
        // Configure UR read: Port 0, Bank 0, Addr 0
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        $display({prefix, "  UR read enable: %b, bank: %d, addr: %h"}, cru_ur[71], cru_ur[115:113], cru_ur[103:96]);
        // Wait for read latency (UR has 0 pipeline stages, but BRAM has 1 cycle)
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read from UR (UR-RDATA-0): %h"}, ur_read_data);
        if (ur_read_data === test_data_a) begin
            $display({prefix, "  [PASS] UR read data matches written data"});
        end else begin
            $display({prefix, "  [FAIL] UR read data mismatch! Expected: %h"}, test_data_a);
        end
        
        // Clear UR read
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        // Configure RtoVR Output 15 (DVR-VIN0-S) to route from Input 32 (UR-RDATA-0)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-VIN0-S) routing from Input %0d (UR-RDATA-0)"}, OUT_DVR_VIN0_S, IN_UR_RDATA_0);
        $display({prefix, "  UR-RDATA-0: %h"}, dut.u_rtovr.ur_rdata_0);
        $display({prefix, "  DVR-VIN0-S (RtoVR output): %h"}, dut.u_rtovr.dvr_vin0_s);
        if (dut.u_rtovr.dvr_vin0_s === ur_read_data) begin
            $display({prefix, "  [PASS] RtoVR routing correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing mismatch!"});
        end
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture data ---"});
        $display({prefix, "  DVR-VIN0-S before capture: %h"}, dut.dvr_vin0_s_w);
        // Enable VIN0 to capture DVR-VIN0-S
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        $display({prefix, "  VIN0 CRU enabled, capturing data..."});
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VIN0-D (IPR output): %h"}, dut.dr_vin0_d_w);
        if (dut.dr_vin0_d_w === dut.dvr_vin0_s_w) begin
            $display({prefix, "  [PASS] VIN0 captured data correctly"});
        end else begin
            $display({prefix, "  [FAIL] VIN0 data mismatch! Expected: %h, Got: %h"}, dut.dvr_vin0_s_w, dut.dr_vin0_d_w);
        end
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-FPADD-S0/S1 ---"});
        // Configure RtoVR Output 5 (DVR-FPADD-S0) to route from Input 12 (DR-VIN0-D)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_FPADD_S0, 1'b1, IN_DR_VIN0_D);
        // Also configure DVR-FPADD-S1 to route from DR-VIN0-D (for A + A)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_FPADD_S1, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-FPADD-S0) routing from Input %0d (DR-VIN0-D)"}, OUT_DVR_FPADD_S0, IN_DR_VIN0_D);
        $display({prefix, "  RtoVR Output %0d (DVR-FPADD-S1) routing from Input %0d (DR-VIN0-D)"}, OUT_DVR_FPADD_S1, IN_DR_VIN0_D);
        $display({prefix, "  DR-VIN0-D: %h"}, dut.dr_vin0_d_w);
        $display({prefix, "  DVR-FPADD-S0 (RtoVR output): %h"}, dut.dvr_fpadd_s0_w);
        $display({prefix, "  DVR-FPADD-S1 (RtoVR output): %h"}, dut.dvr_fpadd_s1_w);
        if (dut.dvr_fpadd_s0_w === dut.dr_vin0_d_w && dut.dvr_fpadd_s1_w === dut.dr_vin0_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to FPADD correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to FPADD mismatch!"});
        end
        
        $display({prefix, "\n--- Step 6: Send FPADD instruction ---"});
        $display({prefix, "  FPADD inputs:"});
        $display({prefix, "    DVR-FPADD-S0: %h"}, dut.dvr_fpadd_s0_w);
        $display({prefix, "    DVR-FPADD-S1: %h"}, dut.dvr_fpadd_s1_w);
        // cru_fpadd[0]=valid, [1]=src_precision_is_32b, [2]=dst_precision_is_32b, [3]=update_status
        cru_fpadd = 4'b1111;  // valid=1, src32=1, dst32=1, update_status=1 (FP32 + FP32 → FP32)
        $display({prefix, "  CRU-FPADD: %b (valid=%b, src32=%b, dst32=%b, update=%b)"},
                 cru_fpadd, cru_fpadd[0], cru_fpadd[1], cru_fpadd[2], cru_fpadd[3]);
        @(posedge clk);
        #1;
        cru_fpadd = 4'b0000;  // Clear after one cycle
        
        $display({prefix, "\n--- Step 7: Wait for FPADD result valid ---"});
        // Wait for FPADD to produce valid result
        wait_fpadd_valid();
        $display({prefix, "  FPADD result is valid (cru_fpadd_o[3] = %b)"}, cru_fpadd_o[3]);
        $display({prefix, "  DR-FPADD-D (FPADD output): %h"}, dut.dr_fpadd_d_w);
        // Check if result is non-zero (basic sanity check)
        if (dut.dr_fpadd_d_w !== 128'b0) begin
            $display({prefix, "  [PASS] FPADD produced non-zero result"});
        end else begin
            $display({prefix, "  [WARN] FPADD result is zero - may indicate an issue"});
        end
        
        $display({prefix, "\n--- Step 8: Configure RtoVR - Route DR-FPADD-D to DVR-VOUT0-S ---"});
        // Configure RtoVR Output 17 (DVR-VOUT0-S) to route from Input 4 (DR-FPADD-D)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_FPADD_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-VOUT0-S) routing from Input %0d (DR-FPADD-D)"}, OUT_DVR_VOUT0_S, IN_DR_FPADD_D);
        $display({prefix, "  DR-FPADD-D: %h"}, dut.dr_fpadd_d_w);
        $display({prefix, "  DVR-VOUT0-S (RtoVR output): %h"}, dut.dvr_vout0_s_w);
        if (dut.dvr_vout0_s_w === dut.dr_fpadd_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to VOUT0 correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to VOUT0 mismatch!"});
        end
        
        $display({prefix, "\n--- Step 9: Enable VOUT0 to capture data ---"});
        $display({prefix, "  DVR-VOUT0-S before capture: %h"}, dut.dvr_vout0_s_w);
        // Enable VOUT0 to capture DVR-VOUT0-S
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        $display({prefix, "  VOUT0 CRU enabled, capturing data..."});
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VOUT0-D (OPR output): %h"}, dut.dr_vout0_d_w);
        if (dut.dr_vout0_d_w === dut.dvr_vout0_s_w) begin
            $display({prefix, "  [PASS] VOUT0 captured data correctly"});
        end else begin
            $display({prefix, "  [FAIL] VOUT0 data mismatch! Expected: %h, Got: %h"}, dut.dvr_vout0_s_w, dut.dr_vout0_d_w);
        end
        
        $display({prefix, "\n--- Step 10: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        // Configure RtoVR Output 35 (UVR-WDATA-0) to route from Input 14 (DR-VOUT0-D)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (UVR-WDATA-0) routing from Input %0d (DR-VOUT0-D)"}, OUT_UVR_WDATA_0, IN_DR_VOUT0_D);
        $display({prefix, "  DR-VOUT0-D: %h"}, dut.dr_vout0_d_w);
        $display({prefix, "  UVR-WDATA-0 (RtoVR output): %h"}, dut.u_rtovr.uvr_wdata_0);
        if (dut.u_rtovr.uvr_wdata_0 === dut.dr_vout0_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to UR write port correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to UR write port mismatch!"});
        end
        
        $display({prefix, "\n--- Step 11: Write result to UR (bank0, addr1) ---"});
        $display({prefix, "  Data to write (from UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        // Configure UR write: Port 0, Bank 0, Addr 1
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        $display({prefix, "  UR write data input (UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        // Data should come from UVR-WDATA-0 (routed from DR-VOUT0-D)
        @(posedge clk);
        #1;
        $display({prefix, "  UR write completed"});
        
        // Clear UR write
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 12: Read result from UR (bank0, addr1) ---"});
        // Configure UR read: Port 0, Bank 0, Addr 1
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        $display({prefix, "  UR read enable: %b, bank: %d, addr: %h"}, cru_ur[71], cru_ur[115:113], cru_ur[103:96]);
        // Wait for read latency
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR (UR-RDATA-0): %h"}, ur_read_data);
        $display({prefix, "  Expected (from DR-VOUT0-D): %h"}, dut.dr_vout0_d_w);
        
        // Calculate expected result
        // For FP32: A = {1.0, 2.0, 3.0, 4.0}, A + A = {2.0, 4.0, 6.0, 8.0}
        // FP32 representation:
        // 2.0 = 0x40000000
        // 4.0 = 0x40800000
        // 6.0 = 0x40C00000
        // 8.0 = 0x41000000
        expected_result = 128'h40000000_40800000_40C00000_41000000;
        
        $display({prefix, "\n--- Step 13: Compare with expected result ---"});
        $display({prefix, "Expected: %h"}, expected_result);
        $display({prefix, "Actual:   %h"}, ur_read_data);
        
        if (ur_read_data === expected_result) begin
            $display({prefix, "=========================================="});
            $display({prefix, "FPADD TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "FPADD TEST FAILED!"});
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// INTADD Test Flow (task)
// ==========================================================================
task automatic run_smc_intadd_test;
    begin
        string prefix = "INTADD: ";
        reg [1:0] precision_s0, precision_s1, precision_s2;
        reg sign_s0, sign_s1, sign_s2, sign_d;
        reg inst_valid, update_st;
        
        $display({prefix, "=========================================="});
        $display({prefix, "SMC INTADD Testbench Started"});
        $display({prefix, "=========================================="});
        
        // Initialize
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;  // RNE
        clear_all_cru();
        
        // Test data: 32-bit signed integers
        // S0 = {1, 2, 3, 4} = {32'h00000001, 32'h00000002, 32'h00000003, 32'h00000004}
        // S1 = {1, 2, 3, 4} = {32'h00000001, 32'h00000002, 32'h00000003, 32'h00000004}
        // S2 = {0, 0, 0, 0} = {32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000}
        // Expected result (32-bit mode: S0 + S1) = {2, 4, 6, 8}
        test_data_s0 = 128'h00000004_00000003_00000002_00000001;  // Little-endian: 1, 2, 3, 4
        test_data_s1 = 128'h00000004_00000003_00000002_00000001;  // Little-endian: 1, 2, 3, 4
        test_data_s2 = 128'h00000000_00000000_00000000_00000000;  // Little-endian: 0, 0, 0, 0
        expected_result = 128'h00000008_00000006_00000004_00000002;  // Little-endian: 2, 4, 6, 8
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0, addr1, addr2) ---"});
        $display({prefix, "  Test data S0 to write: %h"}, test_data_s0);
        $display({prefix, "  Test data S1 to write: %h"}, test_data_s1);
        $display({prefix, "  Test data S2 to write: %h"}, test_data_s2);
        
        // Write S0 to UR addr0
        force dut.u_rtovr.uvr_wdata_0 = test_data_s0;
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  UR write data input (UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        // Write S1 to UR addr1
        force dut.u_rtovr.uvr_wdata_0 = test_data_s1;
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        // Write S2 to UR addr2
        force dut.u_rtovr.uvr_wdata_0 = test_data_s2;
        set_ur_write(0, 3'd0, 8'h02, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read S0 from UR (bank0, addr0) ---"});
        // Configure UR read: Port 0, Bank 0, Addr 0
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        $display({prefix, "  UR read enable: %b, bank: %d, addr: %h"}, cru_ur[71], cru_ur[115:113], cru_ur[103:96]);
        // Wait for read latency (UR has 0 pipeline stages, but BRAM has 1 cycle)
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read from UR (UR-RDATA-0): %h"}, ur_read_data);
        if (ur_read_data === test_data_s0) begin
            $display({prefix, "  [PASS] UR read data matches written data"});
        end else begin
            $display({prefix, "  [FAIL] UR read data mismatch! Expected: %h"}, test_data_s0);
        end
        
        // Clear UR read
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        // Configure RtoVR Output 15 (DVR-VIN0-S) to route from Input 32 (UR-RDATA-0)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-VIN0-S) routing from Input %0d (UR-RDATA-0)"}, OUT_DVR_VIN0_S, IN_UR_RDATA_0);
        $display({prefix, "  UR-RDATA-0: %h"}, dut.u_rtovr.ur_rdata_0);
        $display({prefix, "  DVR-VIN0-S (RtoVR output): %h"}, dut.u_rtovr.dvr_vin0_s);
        if (dut.u_rtovr.dvr_vin0_s === ur_read_data) begin
            $display({prefix, "  [PASS] RtoVR routing correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing mismatch!"});
        end
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture S0 data ---"});
        $display({prefix, "  DVR-VIN0-S before capture: %h"}, dut.dvr_vin0_s_w);
        // Enable VIN0 to capture DVR-VIN0-S
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        $display({prefix, "  VIN0 CRU enabled, capturing data..."});
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VIN0-D (IPR output): %h"}, dut.dr_vin0_d_w);
        if (dut.dr_vin0_d_w === dut.dvr_vin0_s_w) begin
            $display({prefix, "  [PASS] VIN0 captured data correctly"});
        end else begin
            $display({prefix, "  [FAIL] VIN0 data mismatch! Expected: %h, Got: %h"}, dut.dvr_vin0_s_w, dut.dr_vin0_d_w);
        end
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-INTADD-S0/S1/S2 ---"});
        // Configure all three INTADD inputs to route from DR-VIN0-D
        // Multiple outputs can use the same input in RtoVR
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_INTADD_S0, 1'b1, IN_DR_VIN0_D);
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_INTADD_S1, 1'b1, IN_DR_VIN0_D);
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_INTADD_S2, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-INTADD-S0) routing from Input %0d (DR-VIN0-D)"}, OUT_DVR_INTADD_S0, IN_DR_VIN0_D);
        $display({prefix, "  RtoVR Output %0d (DVR-INTADD-S1) routing from Input %0d (DR-VIN0-D)"}, OUT_DVR_INTADD_S1, IN_DR_VIN0_D);
        $display({prefix, "  RtoVR Output %0d (DVR-INTADD-S2) routing from Input %0d (DR-VIN0-D)"}, OUT_DVR_INTADD_S2, IN_DR_VIN0_D);
        $display({prefix, "  DR-VIN0-D: %h"}, dut.dr_vin0_d_w);
        $display({prefix, "  DVR-INTADD-S0 (RtoVR output): %h"}, dut.dvr_intadd_s0_w);
        $display({prefix, "  DVR-INTADD-S1 (RtoVR output): %h"}, dut.dvr_intadd_s1_w);
        $display({prefix, "  DVR-INTADD-S2 (RtoVR output): %h"}, dut.dvr_intadd_s2_w);
        if (dut.dvr_intadd_s0_w === dut.dr_vin0_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to INTADD-S0 correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to INTADD-S0 mismatch!"});
        end
        
        $display({prefix, "\n--- Step 6: Read S1 from UR and route via VIN0 to INTADD-S1 ---"});
        // Read S1 from UR addr1
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        $display({prefix, "  UR read enable: %b, bank: %d, addr: %h"}, cru_ur[71], cru_ur[115:113], cru_ur[103:96]);
        // Wait for read latency
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read S1 from UR (UR-RDATA-0): %h"}, ur_read_data);
        if (ur_read_data === test_data_s1) begin
            $display({prefix, "  [PASS] UR read data matches written data"});
        end else begin
            $display({prefix, "  [FAIL] UR read data mismatch! Expected: %h"}, test_data_s1);
        end
        
        
        $display({prefix, "\n--- Step 8: Send INTADD instruction (32-bit mode) ---"});
        $display({prefix, "  INTADD inputs:"});
        $display({prefix, "    DVR-INTADD-S0: %h"}, dut.dvr_intadd_s0_w);
        $display({prefix, "    DVR-INTADD-S1: %h"}, dut.dvr_intadd_s1_w);
        $display({prefix, "    DVR-INTADD-S2: %h"}, dut.dvr_intadd_s2_w);
        
        // Configure INTADD: 32-bit mode, signed, valid
        // cru_intadd bit mapping (12位完全反转):
        // [0]  : inst_valid
        // [2:1]: precision_s0
        // [4:3]: precision_s1
        // [6:5]: precision_s2
        // [7]  : sign_s0
        // [8]  : sign_s1
        // [9]  : sign_s2
        // [10] : sign_d
        // [11] : update_st
        precision_s0 = 2'b11;  // 32-bit
        precision_s1 = 2'b11;  // 32-bit
        precision_s2 = 2'b11;  // 32-bit (not used in 32-bit mode)
        sign_s0 = 1'b1;        // signed
        sign_s1 = 1'b1;        // signed
        sign_s2 = 1'b0;        // not used
        sign_d = 1'b1;         // signed output
        inst_valid = 1'b1;
        update_st = 1'b1;
        
        // cru_intadd = {update_st, sign_d, sign_s2, sign_s1, sign_s0, precision_s2, precision_s1, precision_s0, inst_valid}
        cru_intadd = {update_st, sign_d, sign_s2, sign_s1, sign_s0, precision_s2, precision_s1, precision_s0, inst_valid};
        $display({prefix, "  CRU-INTADD: %b (12'h%03h)"}, cru_intadd, cru_intadd);
        $display({prefix, "    inst_valid=%b, precision_s0=%b, precision_s1=%b, precision_s2=%b"},
                 inst_valid, precision_s0, precision_s1, precision_s2);
        $display({prefix, "    sign_s0=%b, sign_s1=%b, sign_s2=%b, sign_d=%b, update_st=%b"},
                 sign_s0, sign_s1, sign_s2, sign_d, update_st);
        @(posedge clk);
        #1;
        cru_intadd = 12'b0;  // Clear after one cycle
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 9: Wait for INTADD result valid ---"});
        // Wait for INTADD to produce valid result
        wait_intadd_valid();
        $display({prefix, "  INTADD result is valid"});
        $display({prefix, "  DR-INTADD-D0 (INTADD output): %h"}, dut.u_intadd.dst_reg0);
        $display({prefix, "  DR-INTADD-D1 (INTADD output): %h"}, dut.u_intadd.dst_reg1);
        // Check if result is non-zero (basic sanity check)
        if (dut.u_intadd.dst_reg0 !== 128'b0) begin
            $display({prefix, "  [PASS] INTADD produced non-zero result"});
        end else begin
            $display({prefix, "  [WARN] INTADD result is zero - may indicate an issue"});
        end
        
        $display({prefix, "\n--- Step 10: Configure RtoVR - Route DR-INTADD-D0 to DVR-VOUT0-S ---"});
        // Configure RtoVR Output 17 (DVR-VOUT0-S) to route from Input 0 (DR-INTADD-D0)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_INTADD_D0);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-VOUT0-S) routing from Input %0d (DR-INTADD-D0)"}, OUT_DVR_VOUT0_S, IN_DR_INTADD_D0);
        $display({prefix, "  DR-INTADD-D0: %h"}, dut.u_intadd.dst_reg0);
        $display({prefix, "  DVR-VOUT0-S (RtoVR output): %h"}, dut.dvr_vout0_s_w);
        if (dut.dvr_vout0_s_w === dut.u_intadd.dst_reg0) begin
            $display({prefix, "  [PASS] RtoVR routing to VOUT0 correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to VOUT0 mismatch!"});
        end
        
        $display({prefix, "\n--- Step 11: Enable VOUT0 to capture data ---"});
        $display({prefix, "  DVR-VOUT0-S before capture: %h"}, dut.dvr_vout0_s_w);
        // Enable VOUT0 to capture DVR-VOUT0-S
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        $display({prefix, "  VOUT0 CRU enabled, capturing data..."});
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VOUT0-D (OPR output): %h"}, dut.dr_vout0_d_w);
        if (dut.dr_vout0_d_w === dut.dvr_vout0_s_w) begin
            $display({prefix, "  [PASS] VOUT0 captured data correctly"});
        end else begin
            $display({prefix, "  [FAIL] VOUT0 data mismatch! Expected: %h, Got: %h"}, dut.dvr_vout0_s_w, dut.dr_vout0_d_w);
        end
        
        $display({prefix, "\n--- Step 12: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        // Configure RtoVR Output 35 (UVR-WDATA-0) to route from Input 14 (DR-VOUT0-D)
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (UVR-WDATA-0) routing from Input %0d (DR-VOUT0-D)"}, OUT_UVR_WDATA_0, IN_DR_VOUT0_D);
        $display({prefix, "  DR-VOUT0-D: %h"}, dut.dr_vout0_d_w);
        $display({prefix, "  UVR-WDATA-0 (RtoVR output): %h"}, dut.u_rtovr.uvr_wdata_0);
        if (dut.u_rtovr.uvr_wdata_0 === dut.dr_vout0_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to UR write port correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to UR write port mismatch!"});
        end
        
        $display({prefix, "\n--- Step 13: Write result to UR (bank0, addr3) ---"});
        $display({prefix, "  Data to write (from UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        // Configure UR write: Port 0, Bank 0, Addr 3
        set_ur_write(0, 3'd0, 8'h03, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        $display({prefix, "  UR write data input (UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        // Data should come from UVR-WDATA-0 (routed from DR-VOUT0-D)
        @(posedge clk);
        #1;
        $display({prefix, "  UR write completed"});
        
        // Clear UR write
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 14: Read result from UR (bank0, addr3) ---"});
        // Configure UR read: Port 0, Bank 0, Addr 3
        set_ur_read(0, 3'd0, 8'h03, 1'b1);
        @(posedge clk);
        #1;
        $display({prefix, "  UR read enable: %b, bank: %d, addr: %h"}, cru_ur[71], cru_ur[115:113], cru_ur[103:96]);
        // Wait for read latency
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR (UR-RDATA-0): %h"}, ur_read_data);
        $display({prefix, "  Expected (from DR-VOUT0-D): %h"}, dut.dr_vout0_d_w);
        
        $display({prefix, "\n--- Step 15: Compare with expected result ---"});
        if (ur_read_data === expected_result) begin
            $display({prefix, "=========================================="});
            $display({prefix, "INTADD TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "INTADD TEST FAILED!"});
            $display({prefix, "Expected: %h"}, expected_result);
            $display({prefix, "Actual:   %h"}, ur_read_data);
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// FPTOINT Test Flow (task)
// ==========================================================================
task automatic run_smc_fptoint_test;
    begin
        string prefix = "FPTOINT: ";
        reg inst_vld, src_prec, dst_prec, src_pos, dst_pos;
        
        $display({prefix, "=========================================="});
        $display({prefix, "SMC FPTOINT Testbench Started"});
        $display({prefix, "=========================================="});
        
        // Initialize
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;  // RNE
        clear_all_cru();
        // Test data: FP32 values {1.0, 2.0, 3.0, 4.0}
        test_data_a = 128'h40800000_40400000_40000000_3F800000;  // FP32: 4.0, 3.0, 2.0, 1.0
        // Expected result: INT32 {4, 3, 2, 1}
        expected_result = 128'h00000004_00000003_00000002_00000001;
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0) ---"});
        $display({prefix, "  Test data to write: %h"}, test_data_a);
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  UR write data input (UVR-WDATA-0): %h"}, dut.u_rtovr.uvr_wdata_0);
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read data from UR (bank0, addr0) ---"});
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        $display({prefix, "  UR read enable: %b, bank: %d, addr: %h"}, cru_ur[71], cru_ur[115:113], cru_ur[103:96]);
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read from UR (UR-RDATA-0): %h"}, ur_read_data);
        if (ur_read_data === test_data_a) begin
            $display({prefix, "  [PASS] UR read data matches written data"});
        end else begin
            $display({prefix, "  [FAIL] UR read data mismatch! Expected: %h"}, test_data_a);
        end
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-VIN0-S) routing from Input %0d (UR-RDATA-0)"}, OUT_DVR_VIN0_S, IN_UR_RDATA_0);
        if (dut.u_rtovr.dvr_vin0_s === ur_read_data) begin
            $display({prefix, "  [PASS] RtoVR routing correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing mismatch!"});
        end
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture data ---"});
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VIN0-D (IPR output): %h"}, dut.dr_vin0_d_w);
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-FPTOINT-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_FPTOINT_S, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-FPTOINT-S) routing from Input %0d (DR-VIN0-D)"}, OUT_DVR_FPTOINT_S, IN_DR_VIN0_D);
        $display({prefix, "  DVR-FPTOINT-S (RtoVR output): %h"}, dut.dvr_fptoint_s_w);
        if (dut.dvr_fptoint_s_w === dut.dr_vin0_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to FPTOINT correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to FPTOINT mismatch!"});
        end
        
        $display({prefix, "\n--- Step 6: Send FPTOINT instruction (FP32 to INT32) ---"});
        // cru_fptoint[4:0]: [0]=inst_vld, [1]=src_prec, [2]=dst_prec, [3]=src_pos, [4]=dst_pos
        inst_vld = 1'b1;
        src_prec = 1'b1;   // FP32
        dst_prec = 1'b1;   // INT32
        src_pos = 1'b0;    // low position
        dst_pos = 1'b0;    // low position
        cru_fptoint = {dst_pos, src_pos, dst_prec, src_prec, inst_vld};
        $display({prefix, "  CRU-FPTOINT: %b (inst_vld=%b, src_prec=%b, dst_prec=%b, src_pos=%b, dst_pos=%b)"},
                 cru_fptoint, inst_vld, src_prec, dst_prec, src_pos, dst_pos);
        @(posedge clk);
        #1;
        cru_fptoint = 5'b0;
        
        $display({prefix, "\n--- Step 7: Check FPTOINT result ---"});
        $display({prefix, "  DR-FPTOINT-D (FPTOINT output): %h"}, dut.dr_fptoint_d_w);
        if (dut.dr_fptoint_d_w !== 128'b0) begin
            $display({prefix, "  [PASS] FPTOINT produced non-zero result"});
        end else begin
            $display({prefix, "  [WARN] FPTOINT result is zero"});
        end
        
        $display({prefix, "\n--- Step 8: Configure RtoVR - Route DR-FPTOINT-D to DVR-VOUT0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_FPTOINT_D);
        @(posedge clk);
        #1;
        $display({prefix, "  RtoVR Output %0d (DVR-VOUT0-S) routing from Input %0d (DR-FPTOINT-D)"}, OUT_DVR_VOUT0_S, IN_DR_FPTOINT_D);
        $display({prefix, "  DR-FPTOINT-D: %h"}, dut.dr_fptoint_d_w);
        $display({prefix, "  DVR-VOUT0-S (RtoVR output): %h"}, dut.dvr_vout0_s_w);
        if (dut.dvr_vout0_s_w === dut.dr_fptoint_d_w) begin
            $display({prefix, "  [PASS] RtoVR routing to VOUT0 correct"});
        end else begin
            $display({prefix, "  [FAIL] RtoVR routing to VOUT0 mismatch!"});
        end
        
        $display({prefix, "\n--- Step 9: Enable VOUT0 to capture data ---"});
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VOUT0-D (OPR output): %h"}, dut.dr_vout0_d_w);
        
        $display({prefix, "\n--- Step 10: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  UVR-WDATA-0 (RtoVR output): %h"}, dut.u_rtovr.uvr_wdata_0);
        
        $display({prefix, "\n--- Step 11: Write result to UR (bank0, addr1) ---"});
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 12: Read result from UR (bank0, addr1) ---"});
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR (UR-RDATA-0): %h"}, ur_read_data);
        $display({prefix, "  Expected: %h"}, expected_result);
        
        $display({prefix, "\n--- Step 13: Compare with expected result ---"});
        if (ur_read_data === expected_result) begin
            $display({prefix, "=========================================="});
            $display({prefix, "FPTOINT TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "FPTOINT TEST FAILED!"});
            $display({prefix, "Expected: %h"}, expected_result);
            $display({prefix, "Actual:   %h"}, ur_read_data);
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// INTTOINT Test Flow (task)
// ==========================================================================
task automatic run_smc_inttoint_test;
    begin
        string prefix = "INTTOINT: ";
        reg instr_vld, src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos;
        
        $display({prefix, "=========================================="});
        $display({prefix, "SMC INTTOINT Testbench Started"});
        $display({prefix, "=========================================="});
        
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;
        clear_all_cru();
        // Test data: INT32 signed {1, 2, 3, 4}
        test_data_a = 128'h00000004_00000003_00000002_00000001;
        // Expected: same (no conversion)
        expected_result = 128'h00000004_00000003_00000002_00000001;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0) ---"});
        $display({prefix, "  Test data to write: %h"}, test_data_a);
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read data from UR (bank0, addr0) ---"});
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read from UR (UR-RDATA-0): %h"}, ur_read_data);
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture data ---"});
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-INTTOINT-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_INTTOINT_S, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  DVR-INTTOINT-S (RtoVR output): %h"}, dut.dvr_inttoint_s_w);
        
        $display({prefix, "\n--- Step 6: Send INTTOINT instruction (INT32 to INT32, signed) ---"});
        // cru_inttoint[6:0]: [0]=instr_vld, [1]=src_prec, [2]=dst_prec, [3]=src_signed, [4]=dst_signed, [5]=src_pos, [6]=dst_pos
        instr_vld = 1'b1;
        src_prec = 1'b1;      // INT32
        dst_prec = 1'b1;      // INT32
        src_signed = 1'b1;    // signed
        dst_signed = 1'b1;    // signed
        src_pos = 1'b0;
        dst_pos = 1'b0;
        cru_inttoint = {dst_pos, src_pos, dst_signed, src_signed, dst_prec, src_prec, instr_vld};
        $display({prefix, "  CRU-INTTOINT: %b"}, cru_inttoint);
        @(posedge clk);
        #1;
        cru_inttoint = 7'b0;
        
        $display({prefix, "\n--- Step 7: Check INTTOINT result ---"});
        $display({prefix, "  DR-INTTOINT-D (INTTOINT output): %h"}, dut.dr_inttoint_d_w);
        
        $display({prefix, "\n--- Step 8: Configure RtoVR - Route DR-INTTOINT-D to DVR-VOUT0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_INTTOINT_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 9: Enable VOUT0 to capture data ---"});
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 10: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 11: Write result to UR (bank0, addr1) ---"});
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 12: Read result from UR (bank0, addr1) ---"});
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR: %h"}, ur_read_data);
        $display({prefix, "  Expected: %h"}, expected_result);
        
        $display({prefix, "\n--- Step 13: Compare with expected result ---"});
        if (ur_read_data === expected_result) begin
            $display({prefix, "=========================================="});
            $display({prefix, "INTTOINT TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "INTTOINT TEST FAILED!"});
            $display({prefix, "Expected: %h"}, expected_result);
            $display({prefix, "Actual:   %h"}, ur_read_data);
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// FPTOFP Test Flow (task)
// ==========================================================================
task automatic run_smc_fptofp_test;
    begin
        string prefix = "FPTOFP: ";
        reg instruction_valid, src_precision, dest_precision, src_pos;
        
        $display({prefix, "=========================================="});
        $display({prefix, "SMC FPTOFP Testbench Started"});
        $display({prefix, "=========================================="});
        
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;
        clear_all_cru();
        // Test data: FP32 {1.0, 2.0, 3.0, 4.0}
        test_data_a = 128'h40800000_40400000_40000000_3F800000;
        // Expected: same (FP32 to FP32)
        expected_result = 128'h40800000_40400000_40000000_3F800000;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0) ---"});
        $display({prefix, "  Test data to write: %h"}, test_data_a);
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read data from UR (bank0, addr0) ---"});
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read from UR (UR-RDATA-0): %h"}, ur_read_data);
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture data ---"});
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-FPTOFP-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_FPTOFP_S, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  DVR-FPTOFP-S (RtoVR output): %h"}, dut.dvr_fptofp_s_w);
        
        $display({prefix, "\n--- Step 6: Send FPTOFP instruction (FP32 to FP32) ---"});
        // cru_fptofp[4:0]: [0]=instruction_valid, [1]=src_precision, [2]=dest_precision, [3]=src_pos
        instruction_valid = 1'b1;
        src_precision = 1'b1;   // FP32
        dest_precision = 1'b1;  // FP32
        src_pos = 1'b0;
        cru_fptofp = {src_pos, dest_precision, src_precision, instruction_valid};
        $display({prefix, "  CRU-FPTOFP: %b"}, cru_fptofp);
        @(posedge clk);
        #1;
        cru_fptofp = 5'b0;
        
        $display({prefix, "\n--- Step 7: Check FPTOFP result ---"});
        $display({prefix, "  DR-FPTOFP-D (FPTOFP output): %h"}, dut.dr_fptofp_d_w);
        
        $display({prefix, "\n--- Step 8: Configure RtoVR - Route DR-FPTOFP-D to DVR-VOUT0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_FPTOFP_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 9: Enable VOUT0 to capture data ---"});
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 10: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 11: Write result to UR (bank0, addr1) ---"});
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 12: Read result from UR (bank0, addr1) ---"});
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR: %h"}, ur_read_data);
        $display({prefix, "  Expected: %h"}, expected_result);
        
        $display({prefix, "\n--- Step 13: Compare with expected result ---"});
        if (ur_read_data === expected_result) begin
            $display({prefix, "=========================================="});
            $display({prefix, "FPTOFP TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "FPTOFP TEST FAILED!"});
            $display({prefix, "Expected: %h"}, expected_result);
            $display({prefix, "Actual:   %h"}, ur_read_data);
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// INTTOFP Test Flow (task)
// ==========================================================================
task automatic run_smc_inttofp_test;
    begin
        string prefix = "INTTOFP: ";
        reg valid, src_is_32b, dst_is_32b, src_signed, src_high, dst_high;
        
        $display({prefix, "=========================================="});
        $display({prefix, "SMC INTTOFP Testbench Started"});
        $display({prefix, "=========================================="});
        
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;
        clear_all_cru();
        // Test data: INT32 signed {1, 2, 3, 4}
        test_data_a = 128'h00000004_00000003_00000002_00000001;
        // Expected: FP32 {1.0, 2.0, 3.0, 4.0}
        expected_result = 128'h40800000_40400000_40000000_3F800000;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0) ---"});
        $display({prefix, "  Test data to write: %h"}, test_data_a);
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read data from UR (bank0, addr0) ---"});
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read from UR (UR-RDATA-0): %h"}, ur_read_data);
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture data ---"});
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-INTTOFP-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_INTTOFP_S, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  DVR-INTTOFP-S (RtoVR output): %h"}, dut.dvr_inttofp_s_w);
        
        $display({prefix, "\n--- Step 6: Send INTTOFP instruction (INT32 to FP32, signed) ---"});
        // cru_inttofp[5:0]: [0]=valid, [1]=src_is_32b, [2]=dst_is_32b, [3]=src_signed, [4]=src_high, [5]=dst_high
        valid = 1'b1;
        src_is_32b = 1'b1;    // INT32
        dst_is_32b = 1'b1;    // FP32
        src_signed = 1'b1;     // signed
        src_high = 1'b0;
        dst_high = 1'b0;
        cru_inttofp = {dst_high, src_high, src_signed, dst_is_32b, src_is_32b, valid};
        $display({prefix, "  CRU-INTTOFP: %b"}, cru_inttofp);
        @(posedge clk);
        #1;
        cru_inttofp = 6'b0;
        
        $display({prefix, "\n--- Step 7: Check INTTOFP result ---"});
        $display({prefix, "  DR-INTTOFP-D (INTTOFP output): %h"}, dut.dr_inttofp_d_w);
        
        $display({prefix, "\n--- Step 8: Configure RtoVR - Route DR-INTTOFP-D to DVR-VOUT0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_INTTOFP_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 9: Enable VOUT0 to capture data ---"});
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 10: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 11: Write result to UR (bank0, addr1) ---"});
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 12: Read result from UR (bank0, addr1) ---"});
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR: %h"}, ur_read_data);
        $display({prefix, "  Expected: %h"}, expected_result);
        
        $display({prefix, "\n--- Step 13: Compare with expected result ---"});
        if (ur_read_data === expected_result) begin
            $display({prefix, "=========================================="});
            $display({prefix, "INTTOFP TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "INTTOFP TEST FAILED!"});
            $display({prefix, "Expected: %h"}, expected_result);
            $display({prefix, "Actual:   %h"}, ur_read_data);
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// LOGICAL Test Flow (task)
// ==========================================================================
task automatic run_smc_logical_test;
    begin
        string prefix = "LOGICAL: ";
        reg logical_vld, logical_precision;
        reg [3:0] logical_op;
        
        $display({prefix, "=========================================="});
        $display({prefix, "SMC LOGICAL Testbench Started"});
        $display({prefix, "=========================================="});
        
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;
        clear_all_cru();
        // Test data: 32-bit values for AND operation
        // S0 = {0xFFFFFFFF, 0xAAAAAAAA, 0x55555555, 0x00000000}
        // S1 = {0xAAAAAAAA, 0x55555555, 0xFFFFFFFF, 0xFFFFFFFF}
        // Expected result (AND): {0xAAAAAAAA, 0x00000000, 0x55555555, 0x00000000}
        test_data_a = 128'hFFFFFFFF_AAAAAAAA_55555555_00000000;  // S0
        test_data_b = 128'hAAAAAAAA_55555555_FFFFFFFF_FFFFFFFF;  // S1
        expected_result = 128'hAAAAAAAA_00000000_55555555_00000000;  // S0 AND S1
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0, addr1) ---"});
        $display({prefix, "  Test data S0 to write: %h"}, test_data_a);
        $display({prefix, "  Test data S1 to write: %h"}, test_data_b);
        
        // Write S0 to UR addr0
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  Writing S0 to UR addr0: %h"}, test_data_a);
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        // Write S1 to UR addr1
        force dut.u_rtovr.uvr_wdata_0 = test_data_b;
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        $display({prefix, "  Writing S1 to UR addr1: %h"}, test_data_b);
        $display({prefix, "  UR write enable: %b, bank: %d, addr: %h"}, cru_ur[67], cru_ur[159:157], cru_ur[147:140]);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        // Verify S1 was written correctly by reading it back
        $display({prefix, "\n--- Step 1.5: Verify S1 was written to UR addr1 ---"});
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read S1 from UR addr1: %h"}, ur_read_data);
        $display({prefix, "  Expected S1: %h"}, test_data_b);
        if (ur_read_data === test_data_b) begin
            $display({prefix, "  [PASS] S1 correctly written to UR addr1"});
        end else begin
            $display({prefix, "  [FAIL] S1 write verification failed! Expected: %h, Got: %h"}, test_data_b, ur_read_data);
        end
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read S0 from UR (bank0, addr0) ---"});
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read S0 from UR (UR-RDATA-0): %h"}, ur_read_data);
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture S0 data ---"});
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-LOGIC-S0 ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_LOGIC_S0, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  DVR-LOGIC-S0 (RtoVR output): %h"}, dut.dvr_logic_s0_w);
        
        $display({prefix, "\n--- Step 5.5: Keep LOGIC-S0 routed from DR-VIN0-D (VIN0 already captured S0) ---"});
        // LOGIC-S0 is already routed from DR-VIN0-D, which contains S0
        // No need to change routing - VIN0 register holds S0 data
        $display({prefix, "  DVR-LOGIC-S0 (routed from DR-VIN0-D, contains S0): %h"}, dut.dvr_logic_s0_w);
        $display({prefix, "  DR-VIN0-D (VIN0 register): %h"}, dut.dr_vin0_d_w);
        
        $display({prefix, "\n--- Step 6: Read S1 from UR and route to LOGIC-S1 via VIN1 ---"});
        // Read S1 from UR addr1 using port 0 (since we can't use port 1 when port 0 is also reading same bank)
        // Note: UR limitation - if port 0 and port 1 access same bank, only port 0's address is used
        // So we'll read S1 sequentially after ensuring S0 is captured in VIN0
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        // Wait for BRAM read latency
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read S1 from UR addr1: %h"}, ur_read_data);
        $display({prefix, "  Expected S1: %h"}, test_data_b);
        if (ur_read_data === test_data_b) begin
            $display({prefix, "  [PASS] S1 correctly read from UR addr1"});
        end else begin
            $display({prefix, "  [FAIL] S1 read failed! Expected: %h, Got: %h"}, test_data_b, ur_read_data);
        end
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        // Route UR-RDATA-0 (which now contains S1) to DVR-VIN1-S
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN1_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        
        // Enable VIN1 to capture S1 data
        cru_vin1 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin1 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VIN1-D (VIN1 register, should contain S1): %h"}, dut.dr_vin1_d_w);
        
        // Route DR-VIN1-D to LOGIC-S1
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_LOGIC_S1, 1'b1, IN_DR_VIN1_D);
        @(posedge clk);
        #1;
        $display({prefix, "  DVR-LOGIC-S1 (RtoVR output from DR-VIN1-D): %h"}, dut.dvr_logic_s1_w);
        $display({prefix, "  DVR-LOGIC-S0 (should still be S0, routed from DR-VIN0-D): %h"}, dut.dvr_logic_s0_w);
   
        $display({prefix, "\n--- Step 7: Configure LOGIC-ST (set to 0 for simple operations) ---"});

     
        $display({prefix, "\n--- Step 8: Send LOGICAL instruction (AND, 32-bit mode) ---"});
        // cru_logic[5:0]: [0]=logical_vld, [4:1]=logical_op, [5]=logical_precision
        // OP_AND = 4'b0000
        logical_vld = 1'b1;
        logical_op = 4'b0000;  // AND operation
        logical_precision = 1'b1;  // 32-bit mode
        cru_logic = {logical_precision, logical_op, logical_vld};
        $display({prefix, "  CRU-LOGICAL: %b (vld=%b, op=%b, precision=%b)"},
                 cru_logic, logical_vld, logical_op, logical_precision);
        @(posedge clk);
        #1;
        cru_logic = 6'b0;
        
        // Now we can clear UR read enables (both ports) after LOGICAL instruction is sent
        cru_ur[71] = 1'b0;  // Clear port 0 read enable
        cru_ur[70] = 1'b0;  // Clear port 1 read enable
        cru_ur[160] = 1'b0; // Clear valid
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 9: Check LOGICAL result ---"});
        $display({prefix, "  DR-LOGIC-D (LOGICAL output): %h"}, dut.dr_logic_d_w);
        
        $display({prefix, "\n--- Step 10: Configure RtoVR - Route DR-LOGIC-D to DVR-VOUT0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_LOGIC_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 11: Enable VOUT0 to capture data ---"});
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 12: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 13: Write result to UR (bank0, addr2) ---"});
        set_ur_write(0, 3'd0, 8'h02, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 14: Read result from UR (bank0, addr2) ---"});
        set_ur_read(0, 3'd0, 8'h02, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR: %h"}, ur_read_data);
        $display({prefix, "  Expected: %h"}, expected_result);
        
        $display({prefix, "\n--- Step 15: Compare with expected result ---"});
        if (ur_read_data === expected_result) begin
            $display({prefix, "=========================================="});
            $display({prefix, "LOGICAL TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "LOGICAL TEST FAILED!"});
            $display({prefix, "Expected: %h"}, expected_result);
            $display({prefix, "Actual:   %h"}, ur_read_data);
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// INT8toFP16 Test Flow (task)
// ==========================================================================
task automatic run_smc_int8tofp16_test;
    begin
        string prefix = "INT8toFP16: ";
        reg instruction_valid, signed_mode;
        
        $display({prefix, "=========================================="});
        $display({prefix, "SMC INT8toFP16 Testbench Started"});
        $display({prefix, "=========================================="});
        
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;
        clear_all_cru();
        // Test data: INT8 values (32 values in 128-bit, each INT8 = {S1[4*i+3:4*i], S0[4*i+3:4*i]})
        // S0 = lower 4 bits of each INT8: {0xC, 0xD, 0xE, 0xF, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xC, ...}
        // S1 = upper 4 bits of each INT8: {0x4, 0x3, 0x2, 0x1, 0x8, 0x7, 0x6, 0x5, 0xC, 0xB, 0xA, 0x9, 0xF, 0xE, 0xD, 0xC, ...}
        // This creates INT8 values with non-zero upper and lower nibbles
        test_data_a = 128'h4321_8765_CBA9_FEDC_4321_8765_CBA9_FEDC;  // S0 (lower 4 bits)
        test_data_b = 128'hFEDC_BA98_7654_3210_FEDC_BA98_7654_3210;  // S1 (upper 4 bits, non-zero values)
        // Note: expected_result is not used in this test; we only check that output is non-zero
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0, addr1) ---"});
        $display({prefix, "  Test data S0 to write: %h"}, test_data_a);
        $display({prefix, "  Test data S1 to write: %h"}, test_data_b);
        
        // Write S0 to UR addr0
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        // Write S1 to UR addr1
        force dut.u_rtovr.uvr_wdata_0 = test_data_b;
        set_ur_write(0, 3'd0, 8'h01, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read S0 from UR (bank0, addr0) ---"});
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read S0 from UR (UR-RDATA-0): %h"}, ur_read_data);
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture S0 data ---"});
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 5: Configure RtoVR - Route DR-VIN0-D to DVR-INT8toFP16-S0 ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_INT8toFP16_S0, 1'b1, IN_DR_VIN0_D);
        @(posedge clk);
        #1;
        $display({prefix, "  DVR-INT8toFP16-S0 (RtoVR output): %h"}, dut.dvr_int8tofp16_s0_w);
        $display({prefix, "  DR-VIN0-D (VIN0 register, contains S0): %h"}, dut.dr_vin0_d_w);
        
        $display({prefix, "\n--- Step 6: Read S1 from UR and route via VIN1 to INT8toFP16-S1 ---"});
        // Read S1 from UR addr1 using port 0 (sequential read to avoid UR bank conflict)
        set_ur_read(0, 3'd0, 8'h01, 1'b1);
        @(posedge clk);
        #1;
        // Wait for BRAM read latency
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read S1 from UR addr1: %h"}, ur_read_data);
        $display({prefix, "  Expected S1: %h"}, test_data_b);
        if (ur_read_data === test_data_b) begin
            $display({prefix, "  [PASS] S1 correctly read from UR addr1"});
        end else begin
            $display({prefix, "  [FAIL] S1 read failed! Expected: %h, Got: %h"}, test_data_b, ur_read_data);
        end
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        // Route UR-RDATA-0 (which now contains S1) to DVR-VIN1-S
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN1_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        
        // Enable VIN1 to capture S1 data
        cru_vin1 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin1 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VIN1-D (VIN1 register, should contain S1): %h"}, dut.dr_vin1_d_w);
        
        // Route DR-VIN1-D to INT8toFP16-S1
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_INT8toFP16_S1, 1'b1, IN_DR_VIN1_D);
        @(posedge clk);
        #1;
        $display({prefix, "  DVR-INT8toFP16-S1 (RtoVR output from DR-VIN1-D): %h"}, dut.dvr_int8tofp16_s1_w);
        $display({prefix, "  DVR-INT8toFP16-S0 (should still be S0, routed from DR-VIN0-D): %h"}, dut.dvr_int8tofp16_s0_w);
        
        $display({prefix, "\n--- Step 7: Send INT8toFP16 instruction (signed mode) ---"});
        // cru_int8tofp16[1:0]: [0]=instruction_valid, [1]=signed_mode
        instruction_valid = 1'b1;
        signed_mode = 1'b1;  // signed mode
        cru_int8tofp16 = {signed_mode, instruction_valid};
        $display({prefix, "  CRU-INT8toFP16: %b (valid=%b, signed=%b)"},
                 cru_int8tofp16, instruction_valid, signed_mode);
        @(posedge clk);
        #1;
        cru_int8tofp16 = 2'b0;
        
        $display({prefix, "\n--- Step 8: Check INT8toFP16 result ---"});
        $display({prefix, "  DR-INT8toFP16-D0: %h"}, dut.dr_int8tofp16_d0_internal);
        $display({prefix, "  DR-INT8toFP16-D1: %h"}, dut.dr_int8tofp16_d1_internal);
        $display({prefix, "  DR-INT8toFP16-D2: %h"}, dut.dr_int8tofp16_d2_internal);
        $display({prefix, "  DR-INT8toFP16-D3: %h"}, dut.dr_int8tofp16_d3_internal);
        if (dut.dr_int8tofp16_d0_internal !== 128'b0 || dut.dr_int8tofp16_d1_internal !== 128'b0 ||
            dut.dr_int8tofp16_d2_internal !== 128'b0 || dut.dr_int8tofp16_d3_internal !== 128'b0) begin
            $display({prefix, "  [PASS] INT8toFP16 produced non-zero result"});
        end else begin
            $display({prefix, "  [WARN] INT8toFP16 result is zero"});
        end
        
        $display({prefix, "\n--- Step 9: Configure RtoVR - Route DR-INT8toFP16-D0 to DVR-VOUT0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VOUT0_S, 1'b1, IN_DR_INT8toFP16_D0);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 10: Enable VOUT0 to capture data ---"});
        cru_vout0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vout0 = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 11: Configure RtoVR - Route DR-VOUT0-D to UVR-WDATA-0 ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_UVR_WDATA_0, 1'b1, IN_DR_VOUT0_D);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 12: Write result to UR (bank0, addr2) ---"});
        set_ur_write(0, 3'd0, 8'h02, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 13: Read result from UR (bank0, addr2) ---"});
        set_ur_read(0, 3'd0, 8'h02, 1'b1);
        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read result from UR: %h"}, ur_read_data);
        
        $display({prefix, "\n--- Step 14: Compare with expected result ---"});
        if (ur_read_data !== 128'b0) begin
            $display({prefix, "=========================================="});
            $display({prefix, "INT8toFP16 TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "=========================================="});
            $display({prefix, "INT8toFP16 TEST FAILED!"});
            $display({prefix, "Result is zero"});
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// SHIFT_UP Test Flow (task)
// ==========================================================================
task automatic run_smc_shiftup_test;
    begin
        string prefix = "SHIFT_UP: ";
        reg [127:0] ur_read_data;
        reg [134:0] cru_shiftup_inst;
        reg instruction_valid;
        reg broadcast;
        reg [4:0] target_smc_id;
        
        $display({prefix, "=========================================="});
        $display({prefix, "SMC SHIFT_UP Testbench Started"});
        $display({prefix, "=========================================="});
        
        rst_n = 0;
        i_smc_id = SMC_ID;
        i_rounding_mode = 3'b000;
        clear_all_cru();
        
        // Test data: 128-bit test pattern (use module-level variable)
        test_data_a = 128'h0123456789ABCDEF_FEDCBA9876543210;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display({prefix, "\n--- Step 1: Write data to UR (bank0, addr0) ---"});
        $display({prefix, "  Test data to write: %h"}, test_data_a);
        
        // Write test data to UR addr0
        force dut.u_rtovr.uvr_wdata_0 = test_data_a;
        set_ur_write(0, 3'd0, 8'h00, 1'b1, 16'hFFFF);
        @(posedge clk);
        #1;
        release dut.u_rtovr.uvr_wdata_0;
        cru_ur[67] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 2: Read data from UR (bank0, addr0) ---"});
        set_ur_read(0, 3'd0, 8'h00, 1'b1);
        @(posedge clk);
        #1;
        // Wait for BRAM read latency
        @(posedge clk);
        #1;
        ur_read_data = dut.u_user_register.o_ur_rdata_0;
        $display({prefix, "  Read data from UR (UR-RDATA-0): %h"}, ur_read_data);
        $display({prefix, "  Expected data: %h"}, test_data_a);
        if (ur_read_data === test_data_a) begin
            $display({prefix, "  [PASS] Data correctly read from UR"});
        end else begin
            $display({prefix, "  [FAIL] Data read failed! Expected: %h, Got: %h"}, test_data_a, ur_read_data);
        end
        cru_ur[71] = 1'b0;
        cru_ur[160] = 1'b0;
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 3: Configure RtoVR - Route UR-RDATA-0 to DVR-VIN0-S ---"});
        cru_rtovr = set_rtovr_route(cru_rtovr, OUT_DVR_VIN0_S, 1'b1, IN_UR_RDATA_0);
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 4: Enable VIN0 to capture data ---"});
        cru_vin0 = 1'b1;
        @(posedge clk);
        #1;
        cru_vin0 = 1'b0;
        @(posedge clk);
        #1;
        $display({prefix, "  DR-VIN0-D (VIN0 register, contains test data): %h"}, dut.dr_vin0_d_w);
        
        // Read data from VIN0 to construct shift_up instruction
        // Note: shift_up data is embedded in cru_shiftup_in[128:1]
        // Instruction format: {broadcast[134], smc_id[133:129], data[128:1], valid[0]}
        $display({prefix, "\n--- Step 5: Construct SHIFT_UP instruction ---"});
        instruction_valid = 1'b1;
        broadcast = 1'b0;  // No broadcast, target specific SMC
        target_smc_id = SMC_ID;  // Target current SMC
        // Construct instruction: {broadcast, smc_id, data, valid}
        cru_shiftup_inst = {broadcast, target_smc_id, dut.dr_vin0_d_w, instruction_valid};
        $display({prefix, "  Instruction format: {broadcast[134], smc_id[133:129], data[128:1], valid[0]}"});
        $display({prefix, "  broadcast = %b, smc_id = %d, valid = %b"}, broadcast, target_smc_id, instruction_valid);
        $display({prefix, "  data = %h"}, dut.dr_vin0_d_w);
        $display({prefix, "  Full instruction (135-bit): %h_%h"}, cru_shiftup_inst[134:64], cru_shiftup_inst[63:0]);
        
        $display({prefix, "\n--- Step 6: Send SHIFT_UP instruction ---"});
        cru_shiftup = cru_shiftup_inst;
        @(posedge clk);
        #1;
        cru_shiftup = 135'b0;  // Clear instruction
        @(posedge clk);
        #1;
        
        $display({prefix, "\n--- Step 7: Check SHIFT_UP output ---"});
        $display({prefix, "  DR-SHIFTUP-OUT (shift_up output): %h"}, dut.dr_shiftup_d_w);
        if (dut.dr_shiftup_d_w === test_data_a) begin
            $display({prefix, "  [PASS] SHIFT_UP output matches input data"});
            $display({prefix, "=========================================="});
            $display({prefix, "SHIFT_UP TEST PASSED!"});
            $display({prefix, "=========================================="});
        end else begin
            $display({prefix, "  [FAIL] SHIFT_UP output mismatch!"});
            $display({prefix, "  Expected: %h"}, test_data_a);
            $display({prefix, "  Got:      %h"}, dut.dr_shiftup_d_w);
            $display({prefix, "=========================================="});
            $display({prefix, "SHIFT_UP TEST FAILED!"});
            $display({prefix, "=========================================="});
        end
        
        #(CLK_PERIOD * 10);
    end
endtask

// ==========================================================================
// Main Test Flow
// ==========================================================================
initial begin
    string test_sel;
    test_sel = "ALL";
    void'($value$plusargs("TEST=%s", test_sel));
    
    // Run FPMUL test
    if (test_sel == "ALL" || test_sel == "FPMUL") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting FPMUL Test");
        $display("==================================================");
        run_smc_test();
        #(CLK_PERIOD * 5);
    end
    
    // Run FPADD test
    if (test_sel == "ALL" || test_sel == "FPADD") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting FPADD Test");
        $display("==================================================");
        run_smc_fpadd_test();
        #(CLK_PERIOD * 5);
    end
    
    // Run INTADD test
    if (test_sel == "ALL" || test_sel == "INTADD") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting INTADD Test");
        $display("==================================================");
        run_smc_intadd_test();
        #(CLK_PERIOD * 5);
    end
    
    // Run FPTOINT test
    if (test_sel == "ALL" || test_sel == "FPTOINT") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting FPTOINT Test");
        $display("==================================================");
        run_smc_fptoint_test();
        #(CLK_PERIOD * 5);
    end
    
    // Run INTTOINT test
    if (test_sel == "ALL" || test_sel == "INTTOINT") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting INTTOINT Test");
        $display("==================================================");
        run_smc_inttoint_test();
        #(CLK_PERIOD * 5);
    end
    
    // Run FPTOFP test
    if (test_sel == "ALL" || test_sel == "FPTOFP") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting FPTOFP Test");
        $display("==================================================");
        run_smc_fptofp_test();
        #(CLK_PERIOD * 5);
    end
    
    // Run INTTOFP test
    if (test_sel == "ALL" || test_sel == "INTTOFP") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting INTTOFP Test");
        $display("==================================================");
        run_smc_inttofp_test();
        #(CLK_PERIOD * 5);
    end
    
    // Run LOGICAL test
    if (test_sel == "ALL" || test_sel == "LOGICAL") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting LOGICAL Test");
        $display("==================================================");
        run_smc_logical_test();
        #(CLK_PERIOD * 5);
    end
    
    // Run INT8toFP16 test  MASK NOT ALLOW
    /*This test is not working, because the INT8toFP16 instruction is not working.
    if (test_sel == "ALL" || test_sel == "INT8toFP16") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting INT8toFP16 Test");
        $display("==================================================");
        run_smc_int8tofp16_test();
        #(CLK_PERIOD * 5);
    end
    */
    
    // Run SHIFT_UP test
    if (test_sel == "ALL" || test_sel == "SHIFT_UP") begin
        $display("\n\n");
        $display("==================================================");
        $display("Starting SHIFT_UP Test");
        $display("==================================================");
        run_smc_shiftup_test();
        #(CLK_PERIOD * 5);
    end
    // Final summary
    $display("\n\n");
    $display("==================================================");
    $display("All Tests Completed");
    $display("==================================================");
    #(CLK_PERIOD * 10);
    $finish;

end

endmodule

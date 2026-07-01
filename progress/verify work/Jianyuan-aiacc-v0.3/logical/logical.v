//=========================================================================//
// Logical Unit for AIACC Architecture v0.2.7
// Supports 16 logical operations, 32-bit/16-bit precision modes, 
// 4/8 channel parallel processing
// Temporary adjustment: SMC-ID=31 is treated as invalid (restore after testing)
//
// Features:
// - Supports 16 logical operations: AND, OR, XOR, NOT, etc.
// - Supports 32-bit (4 channels) and 16-bit (8 channels) precision modes
// - Supports STATUS-based selection operations
// - Supports shift and rotate operations
// - Supports find-first-one/zero operations
//=========================================================================//

`timescale 1ns/1ps

module logical #(
    parameter SMC_ID = 0                // SMC ID for this module
)(
    // Clock and reset
    input wire i_clk,           // Clock (1-bit)
    input wire i_rst_n,         // Active-low reset (1-bit)
    
    // Control signals
    input wire [4:0] i_smc_id,  // SMC-ID 5-bit (compliant with AIACC v0.2.7)
    input wire [5:0] i_cru_logic, // CRU control signal
    
    // Data inputs
    input wire [127:0] i_dvr_logic_s0,  // Input data 0 (128-bit)
    input wire [127:0] i_dvr_logic_s1,  // Input data 1 (128-bit)
    input wire [127:0] i_dvr_logic_st,  // STATUS input (contains GT/EQ/LS flags, 128-bit)
    
    // Data outputs
    output reg [127:0] o_dr_logic_d,    // Operation result output (128-bit, registered)
    output reg [5:0] o_cru_logic_o      // CRU cascade output (6-bit)
);

//=========================================================================//
// Parameter Definitions
//=========================================================================//

// 16 logical operation opcodes (compliant with AIACC v0.2.7 5.3.12 LOGICAL)
parameter [3:0]
    OP_AND                 = 4'b0000,  // Bitwise AND
    OP_OR                  = 4'b0001,  // Bitwise OR
    OP_XOR                 = 4'b0010,  // Bitwise XOR
    OP_NOT                 = 4'b0011,  // Bitwise NOT (uses s0 only)
    OP_COPY                = 4'b0100,  // Copy s0 to output
    OP_SELECT_GREAT        = 4'b0101,  // Select s0 if GT=1, else s1
    OP_SELECT_EQUAL        = 4'b0110,  // Select s0 if EQ=1, else s1
    OP_SELECT_LESS         = 4'b0111,  // Select s0 if LS=1, else s1
    OP_LOGIC_LEFT_SHIFT    = 4'b1000,  // Logical left shift (s0 << shift amount from s1)
    OP_ARITH_LEFT_SHIFT    = 4'b1001,  // Arithmetic left shift (sign-extended)
    OP_ROTATE_LEFT_SHIFT   = 4'b1010,  // Rotate left (shift amount from s1)
    OP_LOGIC_RIGHT_SHIFT   = 4'b1011,  // Logical right shift (s0 >> shift amount from s1)
    OP_ARITH_RIGHT_SHIFT   = 4'b1100,  // Arithmetic right shift (sign-extended)
    OP_ROTATE_RIGHT_SHIFT  = 4'b1101,  // Rotate right (shift amount from s1)
    OP_GET_FIRST_ONE       = 4'b1110,  // Find first '1' position in (s0|s1)
    OP_GET_FIRST_ZERO      = 4'b1111;  // Find first '0' position in ~(s0&s1)

//=========================================================================//
// Internal Signal Definitions
//=========================================================================//

// CRU control signal decoding (compliant with AIACC v0.2.7 5.3.12 LOGICAL micro-instruction)
wire [3:0] w_logical_op_i;        // Operation code (4-bit)
wire w_logical_vld_i;             // Instruction valid signal (1: valid)
wire w_logical_precision_i;       // Data precision (1: 32-bit, 0: 16-bit)

// 32-bit channel splitting (4 parallel channels, compliant with AIACC v0.2.7)
wire [31:0] w_src0_32 [0:3];      // s0 split into 4x 32-bit channels
wire [31:0] w_src1_32 [0:3];      // s1 split into 4x 32-bit channels
wire [2:0] w_st_32 [0:3];         // st split into 4x 32-bit channels (low 3 bits: GT[2], EQ[1], LS[0])
reg [31:0] r_dst_32 [0:3];        // 32-bit channel operation results

// 16-bit channel splitting (8 parallel channels, compliant with AIACC v0.2.7)
wire [15:0] w_src0_16 [0:7];      // s0 split into 8x 16-bit channels
wire [15:0] w_src1_16 [0:7];      // s1 split into 8x 16-bit channels
wire [2:0] w_st_16 [0:7];         // st split into 8x 16-bit channels (low 3 bits: GT[2], EQ[1], LS[0])
reg [15:0] r_dst_16 [0:7];        // 16-bit channel operation results

// Loop variables
integer i;     // Generate loop variable
integer ch;    // Channel loop variable
integer k;     // Concatenation loop variable

// Temporary variables for find-first-one/zero operations (declared at module level)
reg [31:0] temp32 [0:3];
reg [4:0] pos32 [0:3];
reg found32 [0:3];
reg [15:0] temp16 [0:7];
reg [3:0] pos16 [0:7];
reg found16 [0:7];

// Temporary variables for rotate operations
reg [4:0] shift_temp32 [0:3];
reg [3:0] shift_temp16 [0:7];

// Shift amount registers
reg [4:0] r_shift32 [0:3];  // Per-channel 32-bit shift amount
reg [3:0] r_shift16 [0:7];  // Per-channel 16-bit shift amount

//=========================================================================//
// CRU Control Signal Decoding
//=========================================================================//

assign w_logical_op_i = i_cru_logic[4:1];    // Operation code (4-bit)
assign w_logical_vld_i = i_cru_logic[0];     // Instruction valid (1: valid)
assign w_logical_precision_i = i_cru_logic[5]; // Data precision (1: 32-bit, 0: 16-bit)

//=========================================================================//
// Channel Splitting Logic (compliant with AIACC v0.2.7 data path)
//=========================================================================//

genvar gv_i;
generate
    // 32-bit channel splitting: each channel takes 32-bit data, st takes low 3 bits
    for (gv_i = 0; gv_i < 4; gv_i = gv_i + 1) begin : gen_32
        assign w_src0_32[gv_i] = i_dvr_logic_s0[32*gv_i +: 32];  // 32-bit block i of s0
        assign w_src1_32[gv_i] = i_dvr_logic_s1[32*gv_i +: 32];  // 32-bit block i of s1
        assign w_st_32[gv_i] = i_dvr_logic_st[32*gv_i +: 3];     // Low 3 bits of 32-bit block i of st
    end
    
    // 16-bit channel splitting: each channel takes 16-bit data, st takes low 3 bits
    for (gv_i = 0; gv_i < 8; gv_i = gv_i + 1) begin : gen_16
        assign w_src0_16[gv_i] = i_dvr_logic_s0[16*gv_i +: 16];  // 16-bit block i of s0
        assign w_src1_16[gv_i] = i_dvr_logic_s1[16*gv_i +: 16];  // 16-bit block i of s1
        assign w_st_16[gv_i] = i_dvr_logic_st[16*gv_i +: 3];     // Low 3 bits of 16-bit block i of st
    end
endgenerate

//=========================================================================//
// Parallel Operation Logic (combinational, compliant with AIACC v0.2.8 5.3.12)
//=========================================================================//

always @(*) begin
    // Initialize all results to zero to avoid latches
    for (ch = 0; ch < 4; ch = ch + 1) begin
        r_dst_32[ch] = 32'b0;
    end
    for (ch = 0; ch < 8; ch = ch + 1) begin
        r_dst_16[ch] = 16'b0;
    end
    
    if (w_logical_precision_i) begin  // 32-bit precision: 4 channels parallel operation
        for (ch = 0; ch < 4; ch = ch + 1) begin
            // Default assignment to avoid latches
            r_dst_32[ch] = 32'b0;
            
            // Shift amount assignment
            r_shift32[ch] = w_src1_32[ch][4:0];  // 32-bit shift amount
            
            case (w_logical_op_i)
                OP_AND: r_dst_32[ch] = w_src0_32[ch] & w_src1_32[ch];
                OP_OR:  r_dst_32[ch] = w_src0_32[ch] | w_src1_32[ch];
                OP_XOR: r_dst_32[ch] = w_src0_32[ch] ^ w_src1_32[ch];
                OP_NOT: r_dst_32[ch] = ~w_src0_32[ch];
                OP_COPY: r_dst_32[ch] = w_src0_32[ch];
                
                OP_SELECT_GREAT: r_dst_32[ch] = w_st_32[ch][2] ? w_src0_32[ch] : w_src1_32[ch];
                OP_SELECT_EQUAL: r_dst_32[ch] = w_st_32[ch][1] ? w_src0_32[ch] : w_src1_32[ch];
                OP_SELECT_LESS:  r_dst_32[ch] = w_st_32[ch][0] ? w_src0_32[ch] : w_src1_32[ch];
                
                OP_LOGIC_LEFT_SHIFT:  r_dst_32[ch] = w_src0_32[ch] << r_shift32[ch];
                OP_LOGIC_RIGHT_SHIFT: r_dst_32[ch] = w_src0_32[ch] >> r_shift32[ch];
                
                OP_ARITH_LEFT_SHIFT:  r_dst_32[ch] = $signed(w_src0_32[ch]) <<< r_shift32[ch];
                OP_ARITH_RIGHT_SHIFT: r_dst_32[ch] = $signed(w_src0_32[ch]) >>> r_shift32[ch];
                
                OP_ROTATE_LEFT_SHIFT: begin
                    shift_temp32[ch] = w_src1_32[ch][4:0] % 32;
                    r_dst_32[ch] = (w_src0_32[ch] << shift_temp32[ch]) | 
                                   (w_src0_32[ch] >> (32 - shift_temp32[ch]));
                end
                
                OP_ROTATE_RIGHT_SHIFT: begin
                    shift_temp32[ch] = w_src1_32[ch][4:0] % 32;
                    r_dst_32[ch] = (w_src0_32[ch] >> shift_temp32[ch]) | 
                                   (w_src0_32[ch] << (32 - shift_temp32[ch]));
                end
                
                OP_GET_FIRST_ONE: begin
                    temp32[ch] = w_src0_32[ch] | w_src1_32[ch];
                    pos32[ch] = 5'd0;
                    found32[ch] = 1'b0;
                    
                    // Search for first '1' from LSB to MSB
                    begin : find_first_one_32
                        integer idx;
                        for (idx = 0; idx < 32; idx = idx + 1) begin
                            if (temp32[ch][idx] && !found32[ch]) begin
                                pos32[ch] = idx;
                                found32[ch] = 1'b1;
                            end
                        end
                    end
                    
                    r_dst_32[ch] = found32[ch] ? {27'b0, pos32[ch]} : 32'b0;
                end
                
                OP_GET_FIRST_ZERO: begin
                    // Find first '0' position in (s0&s1): directly search for first '0'
                    temp32[ch] = w_src0_32[ch] & w_src1_32[ch];
                    pos32[ch] = 5'd0;
                    found32[ch] = 1'b0;
                    
                    // Search for first '0' from LSB to MSB
                    begin : find_first_zero_32
                        integer idx;
                        for (idx = 0; idx < 32; idx = idx + 1) begin
                            if (!temp32[ch][idx] && !found32[ch]) begin
                                pos32[ch] = idx;
                                found32[ch] = 1'b1;
                            end
                        end
                    end
                    
                    r_dst_32[ch] = found32[ch] ? {27'b0, pos32[ch]} : 32'b0;
                end
                
                default: r_dst_32[ch] = 32'b0;
            endcase
        end
    end else begin  // 16-bit precision: 8 channels parallel operation
        for (ch = 0; ch < 8; ch = ch + 1) begin
            // Default assignment to avoid latches
            r_dst_16[ch] = 16'b0;
            
            // Shift amount assignment
            r_shift16[ch] = w_src1_16[ch][3:0];  // 16-bit shift amount
            
            case (w_logical_op_i)
                OP_AND: r_dst_16[ch] = w_src0_16[ch] & w_src1_16[ch];
                OP_OR:  r_dst_16[ch] = w_src0_16[ch] | w_src1_16[ch];
                OP_XOR: r_dst_16[ch] = w_src0_16[ch] ^ w_src1_16[ch];
                OP_NOT: r_dst_16[ch] = ~w_src0_16[ch];
                OP_COPY: r_dst_16[ch] = w_src0_16[ch];
                
                OP_SELECT_GREAT: r_dst_16[ch] = w_st_16[ch][2] ? w_src0_16[ch] : w_src1_16[ch];
                OP_SELECT_EQUAL: r_dst_16[ch] = w_st_16[ch][1] ? w_src0_16[ch] : w_src1_16[ch];
                OP_SELECT_LESS:  r_dst_16[ch] = w_st_16[ch][0] ? w_src0_16[ch] : w_src1_16[ch];
                
                OP_LOGIC_LEFT_SHIFT:  r_dst_16[ch] = w_src0_16[ch] << r_shift16[ch];
                OP_LOGIC_RIGHT_SHIFT: r_dst_16[ch] = w_src0_16[ch] >> r_shift16[ch];
                
                OP_ARITH_LEFT_SHIFT:  r_dst_16[ch] = $signed(w_src0_16[ch]) <<< r_shift16[ch];
                OP_ARITH_RIGHT_SHIFT: r_dst_16[ch] = $signed(w_src0_16[ch]) >>> r_shift16[ch];
                
                OP_ROTATE_LEFT_SHIFT: begin
                    shift_temp16[ch] = w_src1_16[ch][3:0] % 16;
                    r_dst_16[ch] = (w_src0_16[ch] << shift_temp16[ch]) | 
                                   (w_src0_16[ch] >> (16 - shift_temp16[ch]));
                end
                
                OP_ROTATE_RIGHT_SHIFT: begin
                    shift_temp16[ch] = w_src1_16[ch][3:0] % 16;
                    r_dst_16[ch] = (w_src0_16[ch] >> shift_temp16[ch]) | 
                                   (w_src0_16[ch] << (16 - shift_temp16[ch]));
                end
                
                OP_GET_FIRST_ONE: begin
                    temp16[ch] = w_src0_16[ch] | w_src1_16[ch];
                    pos16[ch] = 4'd0;
                    found16[ch] = 1'b0;
                    
                    begin : find_first_one_16
                        integer idx;
                        for (idx = 0; idx < 16; idx = idx + 1) begin
                            if (temp16[ch][idx] && !found16[ch]) begin
                                pos16[ch] = idx;
                                found16[ch] = 1'b1;
                            end
                        end
                    end
                    
                    r_dst_16[ch] = found16[ch] ? {12'b0, pos16[ch]} : 16'b0;
                end
                
                OP_GET_FIRST_ZERO: begin
                    // Find first '0' position in (s0&s1): directly search for first '0'
                    temp16[ch] = w_src0_16[ch] & w_src1_16[ch];
                    pos16[ch] = 4'd0;
                    found16[ch] = 1'b0;
                    
                    // Search for first '0' from LSB to MSB
                    begin : find_first_zero_16
                        integer idx;
                        for (idx = 0; idx < 16; idx = idx + 1) begin
                            if (!temp16[ch][idx] && !found16[ch]) begin
                                pos16[ch] = idx;
                                found16[ch] = 1'b1;
                            end
                        end
                    end
                    
                    r_dst_16[ch] = found16[ch] ? {12'b0, pos16[ch]} : 16'b0;
                end
                
                default: r_dst_16[ch] = 16'b0;
            endcase
        end
    end
end

//=========================================================================//
// Result Concatenation + CRU Cascade (compliant with AIACC v0.2.7 5.3.12)
//=========================================================================//

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        // Reset: clear results and CRU output (compliant with AIACC v0.2.7 reset requirements)
        o_dr_logic_d <= 128'b0;
        o_cru_logic_o <= 6'b0;
    end else begin
        // CRU output: transparent for valid IDs, zero for invalid ID (SMC-ID=31)
        if (i_smc_id <= 5'd31) begin
            o_cru_logic_o <= i_cru_logic;
        end
        
        // Data path: update results only when instruction is valid (compliant with "data-control separation")
        if (w_logical_vld_i) begin
            if (w_logical_precision_i) begin  // 32-bit precision: concatenate 4 channels to 128-bit
                for (k = 0; k < 4; k = k + 1) begin
                    o_dr_logic_d[32*k +: 32] <= r_dst_32[k];
                end
            end else begin  // 16-bit precision: concatenate 8 channels to 128-bit
                for (k = 0; k < 8; k = k + 1) begin
                    o_dr_logic_d[16*k +: 16] <= r_dst_16[k];
                end
            end
        end
    end
end

endmodule
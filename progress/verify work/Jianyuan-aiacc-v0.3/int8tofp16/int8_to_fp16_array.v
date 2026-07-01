//----------------------------------------------------------------------------
// Filename: int8_to_fp16_array.v
// Author: xiaoke
// Date: 2025-10-23
// Version: 1.0
// Description: INT8 to FP16 conversion array module (32-lane parallel)
//              Top-level module with pipeline registers
//----------------------------------------------------------------------------

`timescale 1ns/1ps

module int8_to_fp16_array (
    input wire clk,                  // Clock input
    input wire rst_n,                // Active low reset
    
    // Input data registers (32 lanes, 8-bit each, split into S0 and S1)
    input wire [127:0] dvr_int8tofp16_s0, // Source register 0 (32 groups x 4-bit)
    input wire [127:0] dvr_int8tofp16_s1, // Source register 1 (32 groups x 4-bit)
    
    // Control instruction register
    input wire [1:0] cru_int8tofp16,     // Control instruction register
    
    // Output data registers (32 lanes, 16-bit each, split into D0-D3)
    output wire [127:0] dr_int8tofp16_d0, // Destination register 0 (32 groups x 4-bit)
    output wire [127:0] dr_int8tofp16_d1, // Destination register 1 (32 groups x 4-bit)
    output wire [127:0] dr_int8tofp16_d2, // Destination register 2 (32 groups x 4-bit)
    output wire [127:0] dr_int8tofp16_d3  // Destination register 3 (32 groups x 4-bit)
);

    // Design parameters
    parameter PARAM_DR_INT8TOFP16_CNT = 32;  // Number of INT8toFP16 units
    
    // Pipeline registers
    reg [127:0] dvr_s0_r, dvr_s1_r;  // Input data registers
    reg [1:0]   cru_r;                // Control register
    reg [127:0] dr_d0_r, dr_d1_r, dr_d2_r, dr_d3_r;  // Output data registers
    
    // Control signal decoding
    wire instruction_valid = cru_r[0];
    wire signed_mode = cru_r[1];
    
    // Input data segmentation (32 INT8 values)
    wire [7:0] int8_input [0:PARAM_DR_INT8TOFP16_CNT-1];
    genvar i;
    generate
        for (i = 0; i < PARAM_DR_INT8TOFP16_CNT; i = i + 1) begin : gen_input
            assign int8_input[i] = {dvr_s1_r[4*i+3:4*i], dvr_s0_r[4*i+3:4*i]};
        end
    endgenerate
    
    // Output FP16 values (32 conversions)
    wire [15:0] fp16_output [0:PARAM_DR_INT8TOFP16_CNT-1];
    
    // Instantiate 32 conversion units
    generate
        for (i = 0; i < PARAM_DR_INT8TOFP16_CNT; i = i + 1) begin : gen_conv
            int8_to_fp16 u_conv (
                .int8_in(int8_input[i]),
                .signed_mode(signed_mode),
                .fp16_out(fp16_output[i])
            );
        end
    endgenerate
    
    // Pipeline register update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all pipeline registers
            dvr_s0_r <= 128'b0;
            dvr_s1_r <= 128'b0;
            cru_r <= 2'b0;
            dr_d0_r <= 128'b0;
            dr_d1_r <= 128'b0;
            dr_d2_r <= 128'b0;
            dr_d3_r <= 128'b0;
        end else begin
            // Input pipeline stage
            dvr_s0_r <= dvr_int8tofp16_s0;
            dvr_s1_r <= dvr_int8tofp16_s1;
            cru_r <= cru_int8tofp16;
            
            // Output pipeline stage (update only when instruction is valid)
            if (instruction_valid) begin
                // Collect 32 FP16 outputs and distribute to 4 output registers
                // Use generate block for parallel assignment
                dr_d0_r <= {fp16_output[31][3:0], fp16_output[30][3:0], fp16_output[29][3:0], fp16_output[28][3:0],
                           fp16_output[27][3:0], fp16_output[26][3:0], fp16_output[25][3:0], fp16_output[24][3:0],
                           fp16_output[23][3:0], fp16_output[22][3:0], fp16_output[21][3:0], fp16_output[20][3:0],
                           fp16_output[19][3:0], fp16_output[18][3:0], fp16_output[17][3:0], fp16_output[16][3:0],
                           fp16_output[15][3:0], fp16_output[14][3:0], fp16_output[13][3:0], fp16_output[12][3:0],
                           fp16_output[11][3:0], fp16_output[10][3:0], fp16_output[9][3:0], fp16_output[8][3:0],
                           fp16_output[7][3:0], fp16_output[6][3:0], fp16_output[5][3:0], fp16_output[4][3:0],
                           fp16_output[3][3:0], fp16_output[2][3:0], fp16_output[1][3:0], fp16_output[0][3:0]};
                
                dr_d1_r <= {fp16_output[31][7:4], fp16_output[30][7:4], fp16_output[29][7:4], fp16_output[28][7:4],
                           fp16_output[27][7:4], fp16_output[26][7:4], fp16_output[25][7:4], fp16_output[24][7:4],
                           fp16_output[23][7:4], fp16_output[22][7:4], fp16_output[21][7:4], fp16_output[20][7:4],
                           fp16_output[19][7:4], fp16_output[18][7:4], fp16_output[17][7:4], fp16_output[16][7:4],
                           fp16_output[15][7:4], fp16_output[14][7:4], fp16_output[13][7:4], fp16_output[12][7:4],
                           fp16_output[11][7:4], fp16_output[10][7:4], fp16_output[9][7:4], fp16_output[8][7:4],
                           fp16_output[7][7:4], fp16_output[6][7:4], fp16_output[5][7:4], fp16_output[4][7:4],
                           fp16_output[3][7:4], fp16_output[2][7:4], fp16_output[1][7:4], fp16_output[0][7:4]};
                
                dr_d2_r <= {fp16_output[31][11:8], fp16_output[30][11:8], fp16_output[29][11:8], fp16_output[28][11:8],
                           fp16_output[27][11:8], fp16_output[26][11:8], fp16_output[25][11:8], fp16_output[24][11:8],
                           fp16_output[23][11:8], fp16_output[22][11:8], fp16_output[21][11:8], fp16_output[20][11:8],
                           fp16_output[19][11:8], fp16_output[18][11:8], fp16_output[17][11:8], fp16_output[16][11:8],
                           fp16_output[15][11:8], fp16_output[14][11:8], fp16_output[13][11:8], fp16_output[12][11:8],
                           fp16_output[11][11:8], fp16_output[10][11:8], fp16_output[9][11:8], fp16_output[8][11:8],
                           fp16_output[7][11:8], fp16_output[6][11:8], fp16_output[5][11:8], fp16_output[4][11:8],
                           fp16_output[3][11:8], fp16_output[2][11:8], fp16_output[1][11:8], fp16_output[0][11:8]};
                
                dr_d3_r <= {fp16_output[31][15:12], fp16_output[30][15:12], fp16_output[29][15:12], fp16_output[28][15:12],
                           fp16_output[27][15:12], fp16_output[26][15:12], fp16_output[25][15:12], fp16_output[24][15:12],
                           fp16_output[23][15:12], fp16_output[22][15:12], fp16_output[21][15:12], fp16_output[20][15:12],
                           fp16_output[19][15:12], fp16_output[18][15:12], fp16_output[17][15:12], fp16_output[16][15:12],
                           fp16_output[15][15:12], fp16_output[14][15:12], fp16_output[13][15:12], fp16_output[12][15:12],
                           fp16_output[11][15:12], fp16_output[10][15:12], fp16_output[9][15:12], fp16_output[8][15:12],
                           fp16_output[7][15:12], fp16_output[6][15:12], fp16_output[5][15:12], fp16_output[4][15:12],
                           fp16_output[3][15:12], fp16_output[2][15:12], fp16_output[1][15:12], fp16_output[0][15:12]};
            end
        end
    end
    
    // Output assignment
    assign dr_int8tofp16_d0 = dr_d0_r;
    assign dr_int8tofp16_d1 = dr_d1_r;
    assign dr_int8tofp16_d2 = dr_d2_r;
    assign dr_int8tofp16_d3 = dr_d3_r;

endmodule

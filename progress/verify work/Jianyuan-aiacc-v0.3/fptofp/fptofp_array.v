//----------------------------------------------------------------------------
// Filename: fptofp_array.v
// Author: xiaoke
// Date: 2025-10-24
// Version: 1.0
// Description: FPtoFP conversion array module
//              Supports 4 parallel FP32 or 8 parallel FP16 conversions
//----------------------------------------------------------------------------

module fptofp_array #(
    parameter SMC_ID = 0                // SMC ID for this module
)(
    input wire clk,                  // Clock input
    input wire rst_n,                // Active low reset
    
    // Input data register (128-bit)
    input wire [127:0] dvr_fptofp_s, // Source data register
    
    // Control instruction register (5-bit micro-instruction)
    input wire [4:0] cru_fptofp,     // Control instruction register
    
    // Output data register (128-bit)
    output wire [127:0] dr_fptofp_d, // Destination data register
    
    // System ID
    input wire [4:0] smc_id          // SMC ID encoding
);

    // Design parameters
    parameter PARAM_DR_FPTOFP_CNT = 4;  // Number of FPtoFP units
    
    wire [127:0] dvr_s_r;
    wire [4:0]  cru_r;
    // Pipeline registers
    // reg [127:0] dvr_s_r;         // Input data register (Stage 1)
    // reg [4:0]  cru_r;            // Control register (Stage 1)
    reg [127:0] output_data_r;   // Intermediate output register (Stage 2)
    reg [4:0]  cru_r2;            // Control register for output stage (Stage 2)
    reg [127:0] dr_d_r;          // Output data register (Stage 3)
    
    // Control signal decoding (use cru_r for pipeline stage 1)
    wire instruction_valid = cru_r[0];
    wire src_precision = cru_r[1];      // 0: 16-bit, 1: 32-bit
    wire dest_precision = cru_r[2];     // 0: 16-bit, 1: 32-bit
    wire src_pos = cru_r[3];            // 0: low, 1: high
    wire dest_pos = cru_r[4];            // 0: low, 1: high 
    // Mode decoding (based on cru_r, which is updated in Stage 1)
    wire mode_fp32_to_fp32 = instruction_valid && (src_precision && dest_precision);
    wire mode_fp16_to_fp16 = instruction_valid && (!src_precision && !dest_precision);
    wire mode_fp16_to_fp32 = instruction_valid && (!src_precision && dest_precision);
    wire mode_fp32_to_fp16 = instruction_valid && (src_precision && !dest_precision);
    
    // Input data segmentation
    wire [31:0] fp32_input [0:3];  // 4 FP32 inputs
    wire [15:0] fp16_input [0:7];  // 8 FP16 inputs
    
    // Internal signals for different conversion units
    wire [31:0] fp32_to_fp32_out [0:3];
    wire [15:0] fp16_to_fp16_out [0:7];
    wire [31:0] fp16_to_fp32_out [0:3];
    wire [15:0] fp32_to_fp16_out [0:7];
    
    // Final output signals
    wire [31:0] fp32_output [0:3]; // 4 FP32 outputs
    wire [15:0] fp16_output [0:7]; // 8 FP16 outputs
    
    // Input data segmentation
    assign fp32_input[0] = dvr_s_r[31:0];
    assign fp32_input[1] = dvr_s_r[63:32];
    assign fp32_input[2] = dvr_s_r[95:64];
    assign fp32_input[3] = dvr_s_r[127:96];
    
    assign fp16_input[0] = dvr_s_r[15:0];
    assign fp16_input[1] = dvr_s_r[31:16];
    assign fp16_input[2] = dvr_s_r[47:32];
    assign fp16_input[3] = dvr_s_r[63:48];
    assign fp16_input[4] = dvr_s_r[79:64];
    assign fp16_input[5] = dvr_s_r[95:80];
    assign fp16_input[6] = dvr_s_r[111:96];
    assign fp16_input[7] = dvr_s_r[127:112];
    
    // Instantiate conversion units based on mode
    generate
        genvar i;
        
        // FP32 to FP32 conversion (4 units)
        for (i = 0; i < 4; i = i + 1) begin : gen_fp32_to_fp32
            fp32_to_fp32 u_fp32_to_fp32 (
                .fp32_in(fp32_input[i]),
                .fp32_out(fp32_to_fp32_out[i])
            );
        end
        
        // FP16 to FP16 conversion (8 units)
        for (i = 0; i < 8; i = i + 1) begin : gen_fp16_to_fp16
            fp16_to_fp16 u_fp16_to_fp16 (
                .fp16_in(fp16_input[i]),
                .fp16_out(fp16_to_fp16_out[i])
            );
        end
        
        // FP16 to FP32 conversion (4 units)
        for (i = 0; i < 4; i = i + 1) begin : gen_fp16_to_fp32
            wire [15:0] src_fp16[3:0];
            assign src_fp16[i] = src_pos ? fp16_input[2*i+1] :  fp16_input[2*i] ;
            
            fp16_to_fp32 u_fp16_to_fp32 (
                .fp16_in(src_fp16[i]),
                .fp32_out(fp16_to_fp32_out[i])
            );
        end
        
        // FP32 to FP16 conversion (4 units)
        for (i = 0; i < 4; i = i + 1) begin : gen_fp32_to_fp16
            fp32_to_fp16 u_fp32_to_fp16 (
                .fp32_in(fp32_input[i]),
                .fp16_out(fp32_to_fp16_out[2*i])
            );
            
            // Duplicate output to both positions
            assign fp32_to_fp16_out[2*i+1] = fp32_to_fp16_out[2*i];
        end
    endgenerate
    
    // Output signal selection based on mode (improved with default values)
    assign fp32_output[0] = mode_fp32_to_fp32 ? fp32_to_fp32_out[0] : 
                            mode_fp16_to_fp32 ? fp16_to_fp32_out[0] : 32'b0;
    assign fp32_output[1] = mode_fp32_to_fp32 ? fp32_to_fp32_out[1] : 
                            mode_fp16_to_fp32 ? fp16_to_fp32_out[1] : 32'b0;
    assign fp32_output[2] = mode_fp32_to_fp32 ? fp32_to_fp32_out[2] : 
                            mode_fp16_to_fp32 ? fp16_to_fp32_out[2] : 32'b0;
    assign fp32_output[3] = mode_fp32_to_fp32 ? fp32_to_fp32_out[3] : 
                            mode_fp16_to_fp32 ? fp16_to_fp32_out[3] : 32'b0;
    
    assign fp16_output[0] = mode_fp16_to_fp16 ? fp16_to_fp16_out[0] : 
                             mode_fp32_to_fp16 ? fp32_to_fp16_out[0] : 16'b0;
    assign fp16_output[1] = mode_fp16_to_fp16 ? fp16_to_fp16_out[1] : 
                             mode_fp32_to_fp16 ? fp32_to_fp16_out[1] : 16'b0;
    assign fp16_output[2] = mode_fp16_to_fp16 ? fp16_to_fp16_out[2] : 
                             mode_fp32_to_fp16 ? fp32_to_fp16_out[2] : 16'b0;
    assign fp16_output[3] = mode_fp16_to_fp16 ? fp16_to_fp16_out[3] : 
                             mode_fp32_to_fp16 ? fp32_to_fp16_out[3] : 16'b0;
    assign fp16_output[4] = mode_fp16_to_fp16 ? fp16_to_fp16_out[4] : 
                             mode_fp32_to_fp16 ? fp32_to_fp16_out[4] : 16'b0;
    assign fp16_output[5] = mode_fp16_to_fp16 ? fp16_to_fp16_out[5] : 
                             mode_fp32_to_fp16 ? fp32_to_fp16_out[5] : 16'b0;
    assign fp16_output[6] = mode_fp16_to_fp16 ? fp16_to_fp16_out[6] : 
                             mode_fp32_to_fp16 ? fp32_to_fp16_out[6] : 16'b0;
    assign fp16_output[7] = mode_fp16_to_fp16 ? fp16_to_fp16_out[7] : 
                             mode_fp32_to_fp16 ? fp32_to_fp16_out[7] : 16'b0;
    
    

    assign dvr_s_r = dvr_fptofp_s;
    assign cru_r = cru_fptofp;
    // Pipeline register update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all pipeline registers
            // dvr_s_r <= 128'b0;
            // cru_r <= 5'b0;
            output_data_r <= 128'b0;
            cru_r2 <= 5'b0;
            dr_d_r <= 128'b0;
        end else begin
            // Stage 1: Input pipeline stage
            // dvr_s_r <= dvr_fptofp_s;
            // cru_r <= cru_fptofp;
            
            // Stage 2: Intermediate pipeline stage
            // Store computed output and control signal
            if (instruction_valid) begin
                cru_r2 <= cru_r;
                if (mode_fp32_to_fp32) begin
                    output_data_r <= { fp32_output[3], fp32_output[2], fp32_output[1], fp32_output[0] };
                end else if (mode_fp16_to_fp16) begin
                    output_data_r <= {
                        fp16_output[7], fp16_output[6], fp16_output[5], fp16_output[4],
                        fp16_output[3], fp16_output[2], fp16_output[1], fp16_output[0]
                    };
                end else if (mode_fp16_to_fp32) begin
                    output_data_r <= { fp32_output[3], fp32_output[2], fp32_output[1], fp32_output[0] };
                end else if (mode_fp32_to_fp16) begin
                    if (dest_pos) begin
                    output_data_r <= {
                            fp16_output[7], output_data_r[111:96], fp16_output[5], output_data_r[79:64],
                            fp16_output[3], output_data_r[47:32], fp16_output[1], output_data_r[15:0]
                        };
                    end else begin
                        output_data_r <= {
                            output_data_r[127:112], fp16_output[6], output_data_r[95:80], fp16_output[4],
                            output_data_r[63:48], fp16_output[2], output_data_r[31:16], fp16_output[0]
                        };
                    end
                end else begin
                    output_data_r <= output_data_r;
                end
            end else begin
                output_data_r <= output_data_r;
                cru_r2 <= 5'b0;
            end
        end
    end
    
    // Output assignment
    assign dr_fptofp_d = output_data_r;

endmodule

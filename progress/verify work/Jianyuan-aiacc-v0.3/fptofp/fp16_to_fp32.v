//----------------------------------------------------------------------------
// Filename: fp16_to_fp32.v
// Author: xiaoke
// Date: 2025-10-24
// Version: 2.0
// Description: FP16 to FP32 conversion unit (IEEE 754 Compliant)
//              - Handles Denormals -> Normalized conversion
//              - Handles Inf/NaN/Zero correctly
//----------------------------------------------------------------------------

module fp16_to_fp32 (
    input  wire [15:0] fp16_in,
    output wire [31:0] fp32_out
);

    // 1. Extract FP16 fields
    wire        sign_16 = fp16_in[15];
    wire [4:0]  exp_16  = fp16_in[14:10];
    wire [9:0]  mant_16 = fp16_in[9:0];
    
    // 2. Classify Input
    wire is_zero_16   = (exp_16 == 5'd0)  && (mant_16 == 10'd0);
    wire is_denorm_16 = (exp_16 == 5'd0)  && (mant_16 != 10'd0);
    wire is_inf_16    = (exp_16 == 5'd31) && (mant_16 == 10'd0);
    wire is_nan_16    = (exp_16 == 5'd31) && (mant_16 != 10'd0);
    
    // 3. Shift Amount Calculation for Denormals
    // Directly determines shift amount (lz_count + 1) to normalize mantissa
    reg [3:0] shift_amt;
    always @(*) begin
        casez (mant_16)
            10'b1????????? : shift_amt = 4'd1;
            10'b01???????? : shift_amt = 4'd2;
            10'b001??????? : shift_amt = 4'd3;
            10'b0001?????? : shift_amt = 4'd4;
            10'b00001????? : shift_amt = 4'd5;
            10'b000001???? : shift_amt = 4'd6;
            10'b0000001??? : shift_amt = 4'd7;
            10'b00000001?? : shift_amt = 4'd8;
            10'b000000001? : shift_amt = 4'd9;
            10'b0000000001 : shift_amt = 4'd10;
            default        : shift_amt = 4'd0; 
        endcase
    end

    // 4. Calculate Normalized Values for Denormal Input
    // Shift left to normalize (use 11-bit to avoid overflow then drop hidden 1)
    wire [10:0] mant_denorm_shift = {1'b0, mant_16} << shift_amt;
    wire [9:0]  mant_norm_from_denorm = mant_denorm_shift[9:0];
    
    // Calculate new exponent for denormal input:
    // FP16 Denorm Exp = -14. 
    // Effective Exp = -14 - shift_amt.
    // Biased FP32 Exp = (-14 - shift_amt) + 127 = 113 - shift_amt.
    wire [7:0] exp_norm_from_denorm = 8'd113 - {4'd0, shift_amt};

    // 5. Calculate Values for Normal Input
    // FP16 Bias = 15, FP32 Bias = 127. Diff = 112.
    wire [7:0] exp_norm_from_norm = {3'd0, exp_16} + 8'd112;
    wire [9:0] mant_norm_from_norm = mant_16;

    // 6. Select Final Results
    reg [7:0]  exp_32;
    reg [22:0] mant_32;

    always @(*) begin
        if (is_zero_16) begin
            exp_32  = 8'd0;
            mant_32 = 23'd0;
        end else if (is_inf_16) begin
            exp_32  = 8'd255;
            mant_32 = 23'd0;
        end else if (is_nan_16) begin
            exp_32  = 8'd255;
            mant_32 = {1'b1, 22'd0}; // Standard qNaN (MSB 1)
        end else if (is_denorm_16) begin
            exp_32  = exp_norm_from_denorm;
            mant_32 = {mant_norm_from_denorm, 13'd0};
        end else begin // Normalized
            exp_32  = exp_norm_from_norm;
            mant_32 = {mant_norm_from_norm, 13'd0};
        end
    end

    // 7. Output Assembly
    // Sign bit is passed through
    assign fp32_out = {sign_16, exp_32, mant_32};

endmodule

//----------------------------------------------------------------------------
// Filename: fp32_to_fp16.v
// Author: xiaoke
// Date: 2025-10-24
// Version: 2.0
// Description: FP32 to FP16 conversion unit (IEEE 754 Compliant)
//              - Round-to-Nearest-Even (RNE)
//              - Handles Denormals correctly
//              - Handles Overflow/Underflow/NaN/Inf
//----------------------------------------------------------------------------

module fp32_to_fp16 (
    input  wire [31:0] fp32_in,
    output wire [15:0] fp16_out
);

    // 1. Extract FP32 fields
    wire        sign_32 = fp32_in[31];
    wire [7:0]  exp_32  = fp32_in[30:23];
    wire [22:0] mant_32 = fp32_in[22:0];
    
    // 2. Add hidden bit
    wire [23:0] mant_32_hidden = (exp_32 == 0) ? {1'b0, mant_32} : {1'b1, mant_32};

    // 3. Special Value Detection
    wire is_zero_32 = (exp_32 == 0) && (mant_32 == 0);
    wire is_inf_32  = (exp_32 == 255) && (mant_32 == 0);
    wire is_nan_32  = (exp_32 == 255) && (mant_32 != 0);
    
    // 4. Exponent Calculation
    // FP32 bias = 127, FP16 bias = 15
    // Target exp = exp_32 - 127 + 15 = exp_32 - 112
    wire signed [9:0] exp_unbiased = {2'b0, exp_32} - 10'sd112;

    // 5. Shift Logic for Denormals
    // For FP16, min normalized exp is 1 (value -14).
    // If exp_unbiased < 1, we need to shift right to make it denormal.
    // Shift amount = 1 - exp_unbiased.
    // Max shift: exp_32=0 (-112) -> shift = 113. 24 bits -> need ample width.
    
    wire [4:0] shift_amt;
    wire       is_denorm_path;
    
    // Logic to determine shift amount
    // If exp_unbiased < 1 (<= 0), it's potentially a denormal in FP16 or underflow.
    // We treat everything < 1 as denormal path to shift mantissa.
    assign is_denorm_path = (exp_unbiased < 1);
    
    // Clamp shift amount to prevent excessive logic. 
    // Mantissa is 24 bits. Shift > 24 + 2(GRS) = 26 will flush to zero/sticky.
    // Let's allow up to 31.
    wire signed [9:0] raw_shift = 10'sd1 - exp_unbiased;
    assign shift_amt = (raw_shift > 31) ? 5'd31 : raw_shift[4:0];

    // 6. Mantissa Alignment & GRS Extraction
    // We need 10 bits for FP16 mantissa.
    // Source: 24 bits (1.23).
    // Target format: 10 bits.
    // We keep extra bits for rounding: G, R, S.
    
    // Shifted mantissa for denormals
    // Use 50 bits to capture shifted out bits for Sticky
    wire [54:0] mant_shifted_full = {mant_32_hidden, 31'd0} >> shift_amt;
    
    // Select mantissa based on path
    // Normal path: exp >= 1. Mantissa is mant_32_hidden.
    // Denormal path: shifted mantissa.
    
    // We focus on the bits relevant for rounding.
    // FP16 mantissa is 10 bits.
    // For normalized: input is 1.xxxx... (24 bits). We need top 11 bits (1 + 10).
    // Actually output format doesn't store hidden bit. 
    // Let's work with 13 bits: 1 (hidden) + 10 (mant) + G + R + S.
    
    reg [10:0] mant_aligned; // 1.xxxxxx... (11 bits)
    reg        guard;
    reg        round;
    reg        sticky;
    
    always @(*) begin
        if (is_denorm_path) begin
            // 对极大右移（超出有效位数）直接置0，sticky=1 表示有截断
            if (raw_shift > 10'sd34) begin // 24位尾数 + 10位保护/舍入位
                mant_aligned = 11'd0;
                guard        = 1'b0;
                round        = 1'b0;
                sticky       = |mant_32_hidden;
            end else begin
                // 正常右移并提取 GRS
                mant_aligned = mant_shifted_full[54:44]; // Includes integer bit + 10 frac
                guard        = mant_shifted_full[43];
                round        = mant_shifted_full[42];
                sticky       = |mant_shifted_full[41:0];
            end
        end else begin
            // Normalized: 1.mmmmmmmmmm...
            // Input: mant_32_hidden [23:0]
            // We need [23:13]. [23] is 1. [22:13] are 10 bits.
            mant_aligned = mant_32_hidden[23:13];
            guard        = mant_32_hidden[12];
            round        = mant_32_hidden[11];
            sticky       = |mant_32_hidden[10:0];
        end
    end

    // 7. Rounding (Round to Nearest Even)
    // Round up if:
    // 1. Guard = 1 AND (Round = 1 OR Sticky = 1) -> > 0.5
    // 2. Guard = 1 AND (Round = 0 AND Sticky = 0) AND LSB = 1 -> == 0.5 (Tie to even)
    wire lsb = mant_aligned[0];
    wire round_up = guard && (round || sticky || lsb);
    
    // Apply rounding
    wire [11:0] mant_rounded = mant_aligned + round_up;
    
    // 8. Handle Exponent & Overflow after Rounding
    // If rounding caused overflow (e.g. 1.1111... -> 10.000...), exp needs to inc.
    wire mant_overflow = mant_rounded[11]; // Bit 11 is 1 means 10.xxx (carry out of 1.xxx)
    
    // Effective exponent logic
    // If mant overflowed, exp + 1
    wire signed [9:0] effective_exp = exp_unbiased + mant_overflow;

    reg [4:0] final_exp;
    reg [9:0] final_mant;
    
    always @(*) begin
        if (is_zero_32) begin
            final_exp  = 5'd0;
            final_mant = 10'd0;
        end else if (is_inf_32) begin
            final_exp  = 5'd31;
            final_mant = 10'd0;
        end else if (is_nan_32) begin
            final_exp  = 5'd31;
            // Preserve payload if possible, or set default qNaN
            final_mant = (mant_32[22:13] == 0) ? {1'b1, 9'd0} : mant_32[22:13];
        end else begin
            // Normal / Denormal Logic
            if (is_denorm_path) begin
                // If denormal rounded up to normal (e.g. 0.1111 -> 1.0000)
                if (mant_rounded[10]) begin // Integer bit became 1
                    final_exp  = 5'd1;
                    final_mant = 10'd0; // 1.0000...
                end else begin
                    final_exp  = 5'd0;
                    final_mant = mant_rounded[9:0];
                end
            end else begin
                // Normalized path
                // Base exp is exp_unbiased.
                // Check for overflow (exp > 30)
                // Note: exp_unbiased is signed.
                
                if (effective_exp >= 10'sd31) begin
                    // Overflow to Inf
                    final_exp  = 5'd31;
                    final_mant = 10'd0; 
                end else begin
                    final_exp  = effective_exp[4:0];
                    final_mant = mant_overflow ? mant_rounded[10:1] : mant_rounded[9:0];
                end
            end
        end
    end

    // 9. Output Assembly
    assign fp16_out = {sign_32, final_exp, final_mant};

endmodule

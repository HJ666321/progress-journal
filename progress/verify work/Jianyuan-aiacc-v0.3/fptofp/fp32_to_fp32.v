//----------------------------------------------------------------------------
// Filename: fp32_to_fp32.v
// Author: xiaoke
// Date: 2025-10-24
// Version: 1.0
// Description: FP32 to FP32 conversion unit (pass-through)
//              Direct pass-through for same precision conversion
//----------------------------------------------------------------------------

module fp32_to_fp32 (
    input  wire [31:0] fp32_in,
    output wire [31:0] fp32_out
);

    // Direct pass-through
    assign fp32_out = fp32_in;

endmodule

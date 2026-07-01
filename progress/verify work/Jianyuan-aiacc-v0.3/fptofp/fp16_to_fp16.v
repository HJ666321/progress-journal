//----------------------------------------------------------------------------
// Filename: fp16_to_fp16.v
// Author: xiaoke
// Date: 2025-10-24
// Version: 1.0
// Description: FP16 to FP16 conversion unit (pass-through)
//              Direct pass-through for same precision conversion
//----------------------------------------------------------------------------

module fp16_to_fp16 (
    input  wire [15:0] fp16_in,
    output wire [15:0] fp16_out
);

    // Direct pass-through
    assign fp16_out = fp16_in;

endmodule

//=========================================================================
// Project   : FP32 Adder Tree
// File      : full_adder.v
// Module    : full_adder
// Author    : sunny
// Email     : 
// Created   : 2025-06-23
// Modified  : 2025-11-06
// Version   : v1.1
//=========================================================================
// Description:
// - 1-bit full adder used inside Wallace tree
// - Verilog-2001 compliant; i_/o_ naming already in place
//=========================================================================
module full_adder (
    input wire i_a,
    input wire i_b,
    input wire i_cin,
    output wire o_sum,
    output wire o_cout
);
    assign o_sum = i_a ^ i_b ^ i_cin;
    assign o_cout = (i_a & i_b) | (i_a & i_cin) | (i_b & i_cin);
endmodule
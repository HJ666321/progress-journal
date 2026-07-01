`timescale 1ns / 1ps

module add32_comb (
    input  [31:0]  src0,
    input  [31:0]  src1,
    input          sign_s0,
    input          sign_s1,
    input          i_sign_d,
    input          sub_en,      // 减法使能：1=减法，0=加法
    output [31:0]  dst,
    output [31:0]  st
);

    // wire               is_signed;
    wire [33:0]        s0_ext;
    wire [33:0]        s1_ext;
    wire signed [33:0] s0_signed;
    wire signed [33:0] s1_signed;
    wire signed [33:0] sum_signed_real;
    wire [31:0]        sum_lo;
    wire [31:0]        result;

    wire               gt;
    wire               ls;
    wire               eq;

    // assign is_signed = sign_s0 | sign_s1 | i_sign_d;

    // 约定：无符号数按 0～2^32−1 参与运算（零扩展后 34 位有符号解释仍为该值）
    // 符号/无符号扩展（组合）
    assign s0_ext = sign_s0 ? {{2{src0[31]}}, src0} : {2'b00, src0};
    assign s1_ext = sign_s1 ? {{2{src1[31]}}, src1} : {2'b00, src1};

    // 有符号求和/求差，用于溢出判定；低 32 位为基础结果
    assign s0_signed        = sign_s0 ? $signed(s0_ext) : s0_ext;
    assign s1_signed        = sign_s1 ? $signed(s1_ext) : s1_ext;
    // 根据 sub_en 选择加法或减法
    assign sum_signed_real  = sub_en ? (s0_signed - s1_signed) : (s0_signed + s1_signed);
    assign sum_lo           = sum_signed_real[31:0];

    // 溢出/饱和处理（只在任一输入被视为有符号时生效）
    // 源寄存器和目的寄存器有一个位有符号数时就将其转化为是有符号数
    // assign result = 
    //     (i_sign_d  && (sum_signed_real[32] == 1'b1) && (sum_signed_real[31] == 1'b0)) ? 32'h80000000 :
    //     (i_sign_d  && (sum_signed_real[32] == 1'b0) && (sum_signed_real[31] == 1'b1)) ? 32'h7FFFFFFF :
    //     (!i_sign_d && (sum_signed_real[32] == 1'b1)) ? 32'hFFFFFFFF :
    //     sum_lo;


    // 处理溢出或下溢（34 位和：33:32=01 正溢出，11/10 负，00 非溢出正）
    // 无符号目的：01→饱和 0xFFFFFFFF，11 或 10→饱和 0
    // 有符号目的：001 或 01→饱和 0x7FFFFFFF，110 或 10→饱和 0x80000000
    assign result = (!i_sign_d && (sum_signed_real[33:32] == 2'b01)) ? 32'hffffffff :
                    (!i_sign_d && (sum_signed_real[33:32] == 2'b11)) ? 32'h00000000 :
                    (!i_sign_d && (sum_signed_real[33:32] == 2'b10)) ? 32'h00000000 :
                    (i_sign_d && (sum_signed_real[33:31] == 3'b110)) ? 32'h80000000 :
                    (i_sign_d && (sum_signed_real[33:32] == 2'b10)) ? 32'h80000000 :
                    (i_sign_d && ((sum_signed_real[33:31] == 3'b001) || (sum_signed_real[33:32] == 2'b01))) ? 32'h7fffffff :
                    sum_lo;
            
    assign dst = result;

    // 比较逻辑：使用与加减法相同的 34 位扩展与解释（按 sign_s0/sign_s1），保证有符号/无符号混合时与计算一致
    assign gt = s0_signed > s1_signed;
    assign ls = s0_signed < s1_signed;
    assign eq = s0_signed == s1_signed;

    assign st = {{29{1'b0}}, gt, eq, ls};

endmodule

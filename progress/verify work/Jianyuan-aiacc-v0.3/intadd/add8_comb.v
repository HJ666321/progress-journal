`timescale 1ns / 1ps

module add8_comb (
    input  [3:0] src0,
    input  [3:0] src1,
    input  [3:0] src2,
    // input          sign_s0,
    input          sign_s1,
    input          sign_s2,
    input          i_sign_d,
    input          sub_en,      // 减法使能：1=减法，0=加法
    output [3:0] dst0,
    output [3:0] dst1
);
    // wire       is_signed;
    wire [7:0] concat_val;
    wire [9:0] s2_ext;
    wire [9:0] concat_val_ext;
    wire signed [9:0] s2_val;
    wire signed [9:0] add_val;
    wire signed [9:0] sum_signed_real;
    wire signed [7:0] sum_signed;
    wire [7:0] sum_clipped;

    // assign is_signed = sign_s1 | sign_s2 | i_sign_d;

    // 将u1和u0连接成8位值
    assign concat_val = {src1, src0};

    assign s2_ext = sign_s2 ? {{6{src2[3]}}, src2} : {6'b000000, src2};
    assign concat_val_ext = sign_s1 ? {{2{concat_val[7]}}, concat_val} : {2'b00, concat_val};

    assign s2_val = sign_s2 ? $signed(s2_ext) : s2_ext;
    assign add_val = sign_s1 ? $signed(concat_val_ext) : concat_val_ext;

    // 根据 sub_en 选择加法或减法
    wire signed [9:0] result_signed_real;
    assign result_signed_real = sub_en ? (s2_val - add_val) : (s2_val + add_val);
    assign sum_signed = result_signed_real[7:0];

    // 处理溢出或下溢（加法和减法使用相同的饱和逻辑）
    assign sum_clipped = (!i_sign_d && (result_signed_real[9:8] == 2'b01)) ? 8'hff :
                         (!i_sign_d && (result_signed_real[9:8] == 2'b11)) ? 8'h00 :
                         (!i_sign_d && (result_signed_real[9:8] == 2'b10)) ? 8'h00 :
                         (i_sign_d && (result_signed_real[9:7] == 3'b110)) ? 8'h80 :
                         (i_sign_d && (result_signed_real[9:8] == 2'b10)) ? 8'h80 :
                         (i_sign_d && ((result_signed_real[9:7] == 3'b001) || (result_signed_real[9:8] == 2'b01))) ? 8'h7f :
                         sum_signed;
    // assign sum_clipped = 
    //         (i_sign_d && (sum_signed_real[8] == 1'b1) && (sum_signed_real[7] == 1'b0)) ? 8'h80 :
    //         (i_sign_d && (sum_signed_real[8] == 1'b0) && (sum_signed_real[7] == 1'b1)) ? 8'h7F :
    //         (!i_sign_d && (sum_signed_real[8] == 1'b1)) ? 8'hFF :
    //         sum_signed;

    // 输出低4位和高4位
    assign dst0 = sum_clipped[3:0];
    assign dst1 = sum_clipped[7:4];

endmodule
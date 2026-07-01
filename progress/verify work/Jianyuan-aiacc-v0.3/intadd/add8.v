`timescale 1ns / 1ps

module add8 (
    // input          clk,
    // input          rst_n,
    input  [127:0] src0,
    input  [127:0] src1,
    input  [127:0] src2,
    input          sign_s0,
    input          sign_s1,
    input          sign_s2,
    input          i_sign_d,
    input          sub_en,      // 减法使能：1=减法，0=加法
    output [127:0] dst0,
    output [127:0] dst1
);

    genvar i;
    generate
        for(i=0; i<32; i++) begin
            add8_comb u_add8_comb(
                .src0        (src0[i*4 +: 4]),
                .src1        (src1[i*4 +: 4]),
                .src2        (src2[i*4 +: 4]),
                // .sign_s0     (sign_s0),
                .sign_s1     (sign_s1),
                .sign_s2     (sign_s2),
                .i_sign_d    (i_sign_d),
                .sub_en      (sub_en),
                .dst0        (dst0[i*4 +: 4]),
                .dst1        (dst1[i*4 +: 4])
            );
        end
    endgenerate

/*
    // 精确匹配C接口函数的实现，使用16位有符号整数模拟C代码行为
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_add8
            // 提取4位值
            wire [3:0] u0 = src0[i*4 +: 4];
            wire [3:0] u1 = src1[i*4 +: 4];
            wire [3:0] u2 = src2[i*4 +: 4];
  

            // 将u2和u1连接成8位值
            wire [7:0] concat_val = {u2, u1};

            // 符号扩展src0到8位
            wire [7:0] s0_signed = (u0[3] == 1'b1) ? {4'b1111, u0} : {4'b0000, u0};

            // 为s0_val创建16位有符号值 - 精确模拟C代码的(int16_t)(int8_t)转换
            wire signed [15:0] s0_val = sign_s0 ? $signed({{8{s0_signed[7]}}, s0_signed}) : {12'b000000000000, u0};

            // 为add_val创建16位有符号值 - 精确模拟C代码的(int16_t)(int8_t)转换
            wire signed [15:0] add_val = sign_s2 ? $signed({{8{concat_val[7]}}, concat_val}) : {8'b00000000, concat_val};

            // 计算有符号和，使用16位精度
            wire signed [15:0] sum_signed = s0_val + add_val;

            // 处理溢出或下溢 - 完全匹配C代码的条件判断
            wire [7:0] sum_clipped = 
                ((s0_val > 0) && (add_val > 0) && (sum_signed < 0)) ? 8'hFF :
                ((s0_val < 0) && (add_val < 0) && (sum_signed < -128)) ? 8'hFF :
                sum_signed[7:0];

            // 输出低4位和高4位
            assign dst0[i*4 +: 4] = sum_clipped[3:0];
            assign dst1[i*4 +: 4] = sum_clipped[7:4];
        end
    endgenerate */
    

endmodule

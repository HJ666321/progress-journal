//=========================================================================//
// Project  : int2fp16
// File     : int2fp16.v
// Module   : int2fp16
// Author   : cypher
// Modified : 2025-12-4  
// Version  : 0.28
//=========================================================================//
// Description:
// 16位整数转FP16浮点数转换模块
//
// Features:
// - 支持有符号和无符号整数转换
// - 前导零计数实现归一化
// - IEEE 754 FP16格式输出
//
//=========================================================================//

module int2fp16 (
    input  wire [15:0] i_in,
    input  wire        i_is_signed,
    output reg  [15:0] o_out
);

    //=========================================================================
    // Internal Signals
    //=========================================================================
    reg         r_sign;
    reg  [15:0] r_absv;
    reg  [3:0]  r_lzc;
    reg  [4:0]  r_exp;
    reg  [9:0]  r_mant;
    reg  [15:0] r_tmp;
    reg  [14:0] r_tmp_norm;
    reg  [10:0] r_man_ext;
    reg         r_guard;
    reg         r_sticky;
    reg         r_round_up;

    // 前导零计算的链式结构
    reg  [4:0] r_lzc_chain [0:16];
    reg        r_found_chain [0:16];

    integer i;

    //=========================================================================
    // Conversion Logic
    //=========================================================================
    always @(*) begin
        r_sign = i_is_signed & i_in[15];
        // 使用补码运算计算绝对值，避免溢出
        r_absv = r_sign ? (~i_in + 16'd1) : i_in;

        if (r_absv == 16'd0) begin
            o_out = 16'd0;
        end else begin
            // 初始化链式结构
            r_lzc_chain[16] = 5'd16;
            r_found_chain[16] = 1'b0;

            // 从高位到低位遍历
            for (i = 15; i >= 0; i = i - 1) begin
                r_found_chain[i] = r_found_chain[i+1] | r_absv[i];
                if (r_absv[i] && !r_found_chain[i+1]) begin
                    // 找到第一个1，计算前导零数量
                    r_lzc_chain[i] = 5'd15 - i;
                end else begin
                    // 继承上一级的计数
                    r_lzc_chain[i] = r_lzc_chain[i+1];
                end
            end

            r_lzc = r_lzc_chain[0][3:0];
            r_exp = 5'd15 + 15 - r_lzc;

            // 归一化后左移
            r_tmp = r_absv << r_lzc;
            r_tmp_norm = r_tmp[14:0];

            // 尾数扩展
            r_man_ext = {1'b0, r_tmp_norm[14:5]};
            r_guard   = r_tmp_norm[4];
            r_sticky  = |r_tmp_norm[3:0];
            r_round_up = r_guard & (r_sticky | r_man_ext[0]);

            // 处理舍入和进位
            if (r_round_up) begin
                r_man_ext = r_man_ext + 11'd1;
                if (r_man_ext[10]) begin
                    r_mant = 10'd0;
                    r_exp  = r_exp + 5'd1;
                end else begin
                    r_mant = r_man_ext[9:0];
                end
            end else begin
                r_mant = r_man_ext[9:0];
            end

            o_out = {r_sign, r_exp, r_mant};
        end
    end

endmodule
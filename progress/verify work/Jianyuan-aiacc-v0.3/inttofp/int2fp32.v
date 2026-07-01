//=========================================================================//
// Project  : int2fp32
// File     : int2fp32.v
// Module   : int2fp32
// Author   : cypher
// Modified : 2025-12-4  
// Version  : 0.28
//=========================================================================//
// Description:
// 32位整数转FP32浮点数转换模块
//
// Features:
// - 支持有符号和无符号整数转换
// - 前导零计数实现归一化
// - IEEE 754 FP32格式输出
//
//=========================================================================//

module int2fp32 (
    input  wire [31:0] i_in,
    input  wire        i_is_signed,
    output reg  [31:0] o_out
);

    //=========================================================================
    // Internal Signals
    //=========================================================================
    reg         r_sign;
    reg  [31:0] r_absv;
    reg  [4:0]  r_lzc;
    reg  [7:0]  r_exp;
    reg  [22:0] r_mant;
    reg  [31:0] r_tmp;
    reg  [30:0] r_tmp_norm;
    reg  [23:0] r_man_ext;
    reg         r_guard;
    reg         r_sticky;
    reg         r_round_up;

    // 前导零计算的链式结构
    reg  [5:0] r_lzc_chain [0:32];
    reg        r_found_chain [0:32];

    integer i;

    //=========================================================================
    // Conversion Logic
    //=========================================================================
    always @(*) begin
        r_sign = i_is_signed & i_in[31];
        // 使用补码运算计算绝对值，避免溢出
        r_absv = r_sign ? (~i_in + 32'd1) : i_in;

        if (r_absv == 32'd0) begin
            o_out = 32'd0;
        end else begin
            // 初始化链式结构
            r_lzc_chain[32] = 6'd32;
            r_found_chain[32] = 1'b0;

            // 从高位到低位遍历
            for (i = 31; i >= 0; i = i - 1) begin
                r_found_chain[i] = r_found_chain[i+1] | r_absv[i];
                if (r_absv[i] && !r_found_chain[i+1]) begin
                    // 找到第一个1，计算前导零数量
                    r_lzc_chain[i] = 6'd31 - i;
                end else begin
                    // 继承上一级的计数
                    r_lzc_chain[i] = r_lzc_chain[i+1];
                end
            end

            r_lzc = r_lzc_chain[0][4:0];
            r_exp = 8'd127 + 31 - r_lzc;

            // 尾数处理
            r_tmp = r_absv << r_lzc;
            r_tmp_norm = r_tmp[30:0];
            r_man_ext = {1'b0, r_tmp_norm[30:8]};
            r_guard   = r_tmp_norm[7];
            r_sticky  = |r_tmp_norm[6:0];
            r_round_up = r_guard & (r_sticky | r_man_ext[0]);

            // 处理舍入和进位
            if (r_round_up) begin
                r_man_ext = r_man_ext + 24'd1;
                if (r_man_ext[23]) begin
                    r_mant = 23'd0;
                    r_exp  = r_exp + 8'd1;
                end else begin
                    r_mant = r_man_ext[22:0];
                end
            end else begin
                r_mant = r_man_ext[22:0];
            end

            // IEEE 754 溢出检测：指数超出范围时输出Inf
            if (r_exp > 8'd254) begin
                // 正无穷大：符号位 + 指数全1 + 尾数全0
                o_out = {r_sign, 8'hFF, 23'd0};
            end else begin
                o_out = {r_sign, r_exp, r_mant};
            end
        end
    end

endmodule
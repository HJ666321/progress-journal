//=========================================================================//
// Project  : int32tofp16
// File     : int32tofp16.v
// Module   : int32tofp16
// Author   : cypher
// Modified : 2025-12-25
// Version  : 0.10
//=========================================================================//
// Description:
// 32位整数转FP16浮点数转换模块
//
// Features:
// - 支持有符号和无符号32位整数转换
// - 前导零计数实现归一化
// - IEEE 754 FP16格式输出
// - 处理32位整数的完整范围
//
//=========================================================================//

module int32tofp16 (
    input  wire [31:0] i_in,
    input  wire        i_is_signed,
    output reg  [15:0] o_out
);

    //=========================================================================
    // Internal Signals
    //=========================================================================
    reg         r_sign;
    reg  [31:0] r_absv;
    reg  [4:0]  r_lzc;        // 32位需要5位LZC计数器
    reg  [4:0]  r_exp;
    reg  [31:0] r_mant;
    reg  [9:0]  r_mant_final;
    reg  [10:0] r_man_ext;      // 11位扩展尾数（10位尾数+1位舍入位）
    reg         r_guard;         // Guard位
    reg         r_sticky;        // Sticky位
    reg         r_round_up;      // 舍入增量

    //=========================================================================
    // 符号位和绝对值计算
    //=========================================================================
    always @(*) begin
        if (i_is_signed) begin
            r_sign = i_in[31];
            r_absv = r_sign ? (~i_in + 1'b1) : i_in;
        end else begin
            r_sign = 1'b0;
            r_absv = i_in;
        end
    end

    //=========================================================================
    // 前导零计数器 (Leading Zero Counter)
    //=========================================================================
    always @(*) begin
        if (r_absv[31]) r_lzc = 0;
        else if (r_absv[30]) r_lzc = 1;
        else if (r_absv[29]) r_lzc = 2;
        else if (r_absv[28]) r_lzc = 3;
        else if (r_absv[27]) r_lzc = 4;
        else if (r_absv[26]) r_lzc = 5;
        else if (r_absv[25]) r_lzc = 6;
        else if (r_absv[24]) r_lzc = 7;
        else if (r_absv[23]) r_lzc = 8;
        else if (r_absv[22]) r_lzc = 9;
        else if (r_absv[21]) r_lzc = 10;
        else if (r_absv[20]) r_lzc = 11;
        else if (r_absv[19]) r_lzc = 12;
        else if (r_absv[18]) r_lzc = 13;
        else if (r_absv[17]) r_lzc = 14;
        else if (r_absv[16]) r_lzc = 15;
        else if (r_absv[15]) r_lzc = 16;
        else if (r_absv[14]) r_lzc = 17;
        else if (r_absv[13]) r_lzc = 18;
        else if (r_absv[12]) r_lzc = 19;
        else if (r_absv[11]) r_lzc = 20;
        else if (r_absv[10]) r_lzc = 21;
        else if (r_absv[9])  r_lzc = 22;
        else if (r_absv[8])  r_lzc = 23;
        else if (r_absv[7])  r_lzc = 24;
        else if (r_absv[6])  r_lzc = 25;
        else if (r_absv[5])  r_lzc = 26;
        else if (r_absv[4])  r_lzc = 27;
        else if (r_absv[3])  r_lzc = 28;
        else if (r_absv[2])  r_lzc = 29;
        else if (r_absv[1])  r_lzc = 30;
        else if (r_absv[0])  r_lzc = 31;
        else r_lzc = 32;  // 零值
    end

    //=========================================================================
    // 指数和尾数计算
    //=========================================================================
    always @(*) begin
        // 零值特殊处理
        if (r_absv == 32'd0) begin
            r_exp = 5'd0;
            r_mant_final = 10'd0;
        end else if (r_lzc < 5'd16) begin
            // 溢出检测：当LZC < 16时，r_exp = 15 + (31 - LZC) > 30
            // 由于r_exp是5位寄存器，46会被截断，所以需要在计算前检测
            // 当LZC < 16时，直接标记为溢出，后续输出Inf
            r_exp = 5'h1F;  // 设置为最大值，用于后续输出Inf
            r_mant_final = 10'd0;
        end else begin
            // 正常计算流程：LZC >= 16，r_exp <= 30
            // 指数计算: FP16偏置15, 32位数最高位在bit31
            // exp = 15 + (31 - lzc)
            r_exp = 5'd15 + (5'd31 - r_lzc);

            // 归一化: 左移消除前导零
            r_mant = r_absv << r_lzc;

            // 检查归一化结果（最高位应该是1）
            if (!r_mant[31]) begin
                // 这不应该发生，因为已经归一化了
                r_exp = 5'd0;
                r_mant_final = 10'd0;
            end else begin
                // 尾数扩展：提取bit30到bit21（10位）作为基础尾数
                r_man_ext = {1'b0, r_mant[30:21]};
                
                // Guard/Round/Sticky位提取（IEEE 754舍入）
                r_guard  = r_mant[20];           // Guard位：bit20
                r_sticky = |r_mant[19:0];        // Sticky位：bit19到bit0的OR
                
                // Round-to-Nearest-Even舍入判断
                // round_up = G & (R | S | LSB)
                r_round_up = r_guard & (r_sticky | r_man_ext[0]);
                
                // 执行舍入
                if (r_round_up) begin
                    r_man_ext = r_man_ext + 11'd1;
                    // 检查舍入是否导致尾数溢出
                    if (r_man_ext[10]) begin
                        // 尾数溢出：尾数清零，指数+1
                        r_mant_final = 10'd0;
                        r_exp = r_exp + 5'd1;
                        // 检查舍入后的指数是否溢出
                        if (r_exp > 5'd30) begin
                            r_exp = 5'h1F;  // 溢出，标记为Inf
                        end
                    end else begin
                        r_mant_final = r_man_ext[9:0];
                    end
                end else begin
                    r_mant_final = r_man_ext[9:0];
                end
            end
        end
    end

    //=========================================================================
    // 输出组合（包含溢出检测）
    //=========================================================================
    always @(*) begin
        // IEEE 754 溢出检测：FP16指数最大值为30（对应值65504）
        // 当指数 >= 31 (即r_exp == 5'h1F) 时，输出正/负无穷大
        if (r_exp >= 5'd31) begin
            // FP16无穷大：符号位 + 指数全1(31) + 尾数全0
            o_out = {r_sign, 5'h1F, 10'd0};
        end else begin
            o_out = {r_sign, r_exp, r_mant_final};
        end
    end

endmodule

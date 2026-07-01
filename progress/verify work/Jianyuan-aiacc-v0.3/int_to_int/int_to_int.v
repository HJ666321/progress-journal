//----------------------------------------------------------------------------
// Filename: int_to_int.v
// Author: [Oliver]
// Date: 2025-8-28
// Version: 1.0
// Description: INT to INT conversion module (Synthesizable, Combinational)
//----------------------------------------------------------------------------
`timescale 1ns / 1ps
module int_to_int
(
    input wire instr_vld,              // 指令有效信号
    input wire src_prec,               // 源寄存器精度：0=16bit，1=32bit
    input wire dst_prec,               // 目的寄存器精度：0=16bit，1=32bit
    input wire src_signed,             // 源数据符号位：0=无符号，1=有符号
    input wire dst_signed,             // 目的数据符号位：0=无符号，1=有符号
    input wire src_pos,           // 源数据位置：0=低位，1=高位（仅在非全精度时有效）
    input wire dst_pos,           // 目的数据位置：0=低位，1=高位（仅在非全精度时有效）
    input wire [31:0] in_reg,          // 输入寄存器（整数）

    output wire [31:0] out_reg,        // 输出寄存器（整数）
    output wire result_vld             // 结果有效信号
);

// 内部信号
wire [15:0] src_data_16;            // 提取的16位源数据
wire [31:0] src_data_32;            // 提取的32位源数据
reg  [31:0] dst_data;               // 最终输出数据

// 转换中间结果
reg  [15:0] dst_data_32to16;        // 32位到16位转换结果
reg  [31:0] dst_data_32to32;        // 32位到32位转换结果
reg  [31:0] dst_data_16to32;        // 16位到32位转换结果
reg  [15:0] dst_data_16to16_low;    // 16位到16位转换结果(低位)
reg  [15:0] dst_data_16to16_high;   // 16位到16位转换结果(高位)
wire [31:0] dst_data_32to16_out;    // 32位到16位输出结果(移位处理后)

// 16位到16位转换的临时变量
reg  [15:0] in_low;                 // 低16位输入数据
reg  [15:0] in_high;                // 高16位输入数据

// 提取源数据
assign src_data_16 = src_pos ? in_reg[31:16] : in_reg[15:0];
assign src_data_32 = in_reg;

    // 1. 32-bit -> 32-bit 转换逻辑
    always @(*) begin
        // 默认直通
        dst_data_32to32 = src_data_32;
        
        if (src_signed) begin
            // Signed -> Signed: 直通
            // Signed -> Unsigned: 负数转0
            if (!dst_signed && src_data_32[31]) begin
                dst_data_32to32 = 32'd0;
            end
        end else begin
            // Unsigned -> Signed: 大数饱和到 0x7FFFFFFF
            if (dst_signed && src_data_32[31]) begin
                dst_data_32to32 = 32'h7FFFFFFF;
            end
            // Unsigned -> Unsigned: 直通
        end
    end

    // 2. 32-bit -> 16-bit 转换逻辑 (带饱和)
    always @(*) begin
        dst_data_32to16 = src_data_32[15:0]; // 默认截断
        
        if (src_signed) begin
            if (dst_signed) begin
                // S32 -> S16: 检查范围 -32768 ~ 32767
                // 32位有符号数超出16位有符号范围：
                // 正数 > 32767 (0x7FFF) 或 负数 < -32768 (0xFFFF8000)
                // 简易判断：高17位 (31:15) 必须全为0（正数）或全为1（负数）才不溢出
                // 即: src_data_32[31:15] == 17'h00000 (正不溢出) 或 src_data_32[31:15] == 17'h1FFFF (负不溢出)
                // 等价于: src_data_32[31:15] 全0或全1 -> {17{src_data_32[15]}} == src_data_32[31:15]
                if ($signed(src_data_32) > $signed(32'sd32767))
                    dst_data_32to16 = 16'h7FFF;
                else if ($signed(src_data_32) < $signed(-32'sd32768))
                    dst_data_32to16 = 16'h8000;
            end else begin
                // S32 -> U16: 检查范围 0 ~ 65535
                if (src_data_32[31]) // 负数
                    dst_data_32to16 = 16'h0000;
                else if (src_data_32 > 32'h0000FFFF) // 正数溢出
                    dst_data_32to16 = 16'hFFFF;
            end
        end else begin
            if (dst_signed) begin
                // U32 -> S16: 检查范围 0 ~ 32767
                if (src_data_32 > 32'h00007FFF)
                    dst_data_32to16 = 16'h7FFF;
            end else begin
                // U32 -> U16: 检查范围 0 ~ 65535
                if (src_data_32 > 32'h0000FFFF)
                    dst_data_32to16 = 16'hFFFF;
            end
        end
    end

    // 3. 16-bit -> 32-bit 转换逻辑 (扩展)
    always @(*) begin
        if (src_signed) begin
            // S16 -> S32: 符号扩展
            // S16 -> U32: 负数变0，正数零扩展
            if (dst_signed) 
                dst_data_16to32 = {{16{src_data_16[15]}}, src_data_16};
            else
                dst_data_16to32 = src_data_16[15] ? 32'd0 : {16'b0, src_data_16};
        end else begin
            // U16 -> S32/U32: 都是零扩展 (U16最大65535，在S32/U32范围内)
            dst_data_16to32 = {16'b0, src_data_16};
        end
    end

    // 4. 16-bit -> 16-bit 转换逻辑 (子字并行)
    // 低16位
    always @(*) begin
        in_low = in_reg[15:0];
        dst_data_16to16_low = in_low;
        
        if (src_signed) begin
            // S16 -> U16: 负数变0
            if (!dst_signed && in_low[15])
                dst_data_16to16_low = 16'h0000;
        end else begin
            // U16 -> S16: 大数饱和
            if (dst_signed && in_low[15]) // > 32767
                dst_data_16to16_low = 16'h7FFF;
        end
    end

    // 高16位
    always @(*) begin
        in_high = in_reg[31:16];
        dst_data_16to16_high = in_high;

        if (src_signed) begin
            // S16 -> U16: 负数变0
            if (!dst_signed && in_high[15])
                dst_data_16to16_high = 16'h0000;
        end else begin
            // U16 -> S16: 大数饱和
            if (dst_signed && in_high[15]) // > 32767
                dst_data_16to16_high = 16'h7FFF;
        end
    end

    // 结果选择与拼装
    assign dst_data_32to16_out = dst_pos ? {dst_data_32to16, 16'b0} : {16'b0, dst_data_32to16};

    always @(*) begin
        case ({src_prec, dst_prec})
            2'b11: dst_data = dst_data_32to32;        // 32 -> 32
            2'b10: dst_data = dst_data_32to16_out;    // 32 -> 16
            2'b01: dst_data = dst_data_16to32;        // 16 -> 32
            2'b00: dst_data = {dst_data_16to16_high, dst_data_16to16_low}; // 16 -> 16 (SIMD)
            default: dst_data = 32'd0;
        endcase
    end

    // 结果有效信号
    assign result_vld = instr_vld;

    // 指令无效时输出 0
    assign out_reg = instr_vld ? dst_data : 32'h00000000;

endmodule
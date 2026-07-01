`timescale 1ns/1ps
//----------------------------------------------------------------------------
// Filename: fpto_int.v
// Author: [Sunny]
// Editor: [Oliver]
// Date: 2025-8-30
// Version: 2.0
// Description: FP to INT conversion module, Pure combinational logic, synthesizable
// 结合子字并行模式与16to16转换，组成8个并行16位整数到16位浮点转换器
// 所有function转换为纯组合逻辑，确保可综合
//----------------------------------------------------------------------------
module fpto_int (
    // 微指令控制信号
    input  wire         inst_vld,             // 指令有效信号：1=有效，0=无效
    input  wire         src_prec,          // 源寄存器精度：0=16bit，1=32bit
    input  wire         dst_prec,          // 目的寄存器精度：0=16bit，1=32bit
    input  wire         src_pos,           // 源数据位置：0=低位，1=高位（仅在非全精度时有效）
    input  wire         dst_pos,           // 目的数据位置：0=低位，1=高位（仅在非全精度时有效）
    
    // 数据接口
    input  wire [31:0]  in_reg,          // 输入寄存器（浮点数）
    output wire [31:0]  out_reg,         // 输出寄存器（整数）
    output wire         result_vld     // 结果有效信号
);

// 源数据处理
wire [31:0] src_data;                   // 处理后的32位源数据
wire [15:0] src_data_16;                // 提取的16位源数据
wire [31:0] src_data_32;                // 扩展后的32位源数据

// 子字并行处理信号
wire subword_parallel_mode;             // 子字并行模式：32bit输入->16bit输出
wire [15:0] src_low_16, src_high_16;    // 子字并行的源数据
wire [15:0] dst_low_16, dst_high_16;    // 子字并行的目标数据

// 目标数据生成
wire [31:0] dst_data;                   // 最终输出数据
wire [15:0] dst_data_16;                // 16位转换结果
wire [31:0] dst_data_32;                // 32位转换结果

// 浮点数解析信号
wire        src_sign_bit;               // 符号位
wire [7:0]  src_exponent;               // 指数位（用于FP32）
wire [22:0] src_mantissa;               // 尾数位（用于FP32）
wire [4:0]  src_exp_16;                 // 指数位（用于FP16）
wire [9:0]  src_mant_16;                // 尾数位（用于FP16）

// ============= FP32转INT32转换的中间信号 =============
reg [31:0] fp32_to_int32_result;  // 在always块中赋值，需声明为reg
wire        fp32_sign;
wire [7:0]  fp32_exp;
wire [22:0] fp32_mant;
wire [8:0]  fp32_biased_exp;
wire [31:0] fp32_int_result;
wire [23:0] fp32_significand;
reg [31:0] fp32_shift_result;  // 在always块中赋值，需声明为reg
wire        fp32_is_inf_nan;
wire        fp32_is_zero;
wire        fp32_exp_overflow;
wire        fp32_exp_underflow;
wire        fp32_result_overflow;

// ============= FP16转INT16转换的中间信号 =============
reg [15:0] fp16_to_int16_result;  // 在always块中赋值，需声明为reg
wire        fp16_sign;
wire [4:0]  fp16_exp;
wire [9:0]  fp16_mant;
wire [5:0]  fp16_biased_exp;
wire [15:0] fp16_int_result;
wire [10:0] fp16_significand;
reg [15:0] fp16_shift_result;  // 在always块中赋值，需声明为reg
wire        fp16_is_inf_nan;
wire        fp16_is_zero;
wire        fp16_exp_overflow;
wire        fp16_exp_underflow;
wire        fp16_result_overflow;

// ============= FP32转INT16转换的中间信号 =============
reg [15:0] fp32_to_int16_result;  // 在always块中赋值，需声明为reg
wire [31:0] fp32_to_int16_temp_int32;

// ============= FP16转INT32转换的中间信号 =============
reg [31:0] fp16_to_int32_result;  // 在always块中赋值，需声明为reg
wire        fp16_to_int32_sign;
wire [4:0]  fp16_to_int32_exp;
wire [9:0]  fp16_to_int32_mant;
wire [5:0]  fp16_to_int32_biased_exp;
wire [31:0] fp16_to_int32_int_result;
wire [10:0] fp16_to_int32_significand;
reg [31:0] fp16_to_int32_shift_result;  // 在always块中赋值，需声明为reg
wire        fp16_to_int32_is_inf_nan;
wire        fp16_to_int32_is_zero;
wire        fp16_to_int32_exp_overflow;
wire        fp16_to_int32_exp_underflow;
wire        fp16_to_int32_result_overflow;

// 子字并行模式检测：32bit输入 -> 16bit输出时启用
assign subword_parallel_mode = (src_prec == 1'b0) && (dst_prec == 1'b0);

// 子字并行数据分离
assign src_low_16 = in_reg[15:0];      // 低16位
assign src_high_16 = in_reg[31:16];    // 高16位

// 提取源数据
assign src_data_16 = src_pos ? in_reg[31:16] : in_reg[15:0];
assign src_data_32 = in_reg;
assign src_data = src_prec ? src_data_32 : {16'b0, src_data_16};

// 浮点数位域解析（用于32位浮点数）
assign src_sign_bit = src_data[31];
assign src_exponent = src_data[30:23];
assign src_mantissa = src_data[22:0];

// 16位浮点数位域解析（用于16位浮点数）
assign src_exp_16 = src_data_16[14:10];
assign src_mant_16 = src_data_16[9:0];

// ============= FP32转INT32组合逻辑 =============
assign fp32_sign = src_data_32[31];
assign fp32_exp = src_data_32[30:23];
assign fp32_mant = src_data_32[22:0];
assign fp32_biased_exp = {1'b0, fp32_exp} - 9'd127;
assign fp32_significand = {1'b1, fp32_mant};
assign fp32_is_inf_nan = (fp32_exp == 8'hFF);
assign fp32_is_zero = (fp32_exp == 8'h00);
assign fp32_exp_overflow = ($signed(fp32_biased_exp) > $signed(9'd30));
assign fp32_exp_underflow = ($signed(fp32_biased_exp) < $signed(9'd0));

// FP32移位计算（README: +∞/NaN→正最大，-∞→负最大；溢出按符号饱和）
always @(*) begin
    if (fp32_is_inf_nan) begin
        fp32_to_int32_result = fp32_sign ? 32'h80000000 : 32'h7FFFFFFF;
    end else if (fp32_is_zero) begin
        fp32_to_int32_result = 32'h00000000;
    end else if (fp32_exp_overflow) begin
        fp32_to_int32_result = fp32_sign ? 32'h80000000 : 32'h7FFFFFFF;
    end else if (fp32_exp_underflow) begin
        fp32_to_int32_result = 32'h00000000;
    end else begin
        // 计算移位量
        if ((23 - fp32_biased_exp[7:0]) >= 0 && (23 - fp32_biased_exp[7:0]) < 24) begin
            fp32_shift_result = fp32_significand >> (23 - fp32_biased_exp[7:0]);
        end else if ((fp32_biased_exp[7:0] - 23) > 0 && (fp32_biased_exp[7:0] - 23) < 9) begin
            fp32_shift_result = fp32_significand << (fp32_biased_exp[7:0] - 23);
        end else begin
            fp32_shift_result = 32'h80000000;  // 溢出
        end
        
        // 应用符号和溢出检查
        if (fp32_sign) begin
            if (fp32_shift_result > 32'h80000000) begin
                fp32_to_int32_result = 32'h80000000;
            end else begin
                fp32_to_int32_result = (~fp32_shift_result + 1);
            end
        end else begin
            if (fp32_shift_result > 32'h7FFFFFFF) begin
                fp32_to_int32_result = 32'h7FFFFFFF;
            end else begin
                fp32_to_int32_result = fp32_shift_result;
            end
        end
    end
end

// ============= FP16转INT16组合逻辑 =============
assign fp16_sign = src_data_16[15];
assign fp16_exp = src_data_16[14:10];
assign fp16_mant = src_data_16[9:0];
assign fp16_biased_exp = {1'b0, fp16_exp} - 6'd15;
assign fp16_significand = {1'b1, fp16_mant};
assign fp16_is_inf_nan = (fp16_exp == 5'h1F);
assign fp16_is_zero = (fp16_exp == 5'h00);
assign fp16_exp_overflow = ($signed(fp16_biased_exp) > $signed(6'd14));
assign fp16_exp_underflow = ($signed(fp16_biased_exp) < $signed(6'd0));

// FP16移位计算（README: +∞/NaN→正最大，-∞→负最大）
always @(*) begin
    if (fp16_is_inf_nan) begin
        fp16_to_int16_result = fp16_sign ? 16'h8000 : 16'h7FFF;
    end else if (fp16_is_zero) begin
        fp16_to_int16_result = 16'h0000;
    end else if (fp16_exp_overflow) begin
        fp16_to_int16_result = fp16_sign ? 16'h8000 : 16'h7FFF;
    end else if (fp16_exp_underflow) begin
        fp16_to_int16_result = 16'h0000;
    end else begin
        // 计算移位量
        if ((10 - fp16_biased_exp[4:0]) >= 0 && (10 - fp16_biased_exp[4:0]) < 11) begin
            fp16_shift_result = fp16_significand >> (10 - fp16_biased_exp[4:0]);
        end else if ((fp16_biased_exp[4:0] - 10) > 0 && (fp16_biased_exp[4:0] - 10) < 6) begin
            fp16_shift_result = fp16_significand << (fp16_biased_exp[4:0] - 10);
        end else begin
            fp16_shift_result = fp16_sign ? 16'h8000 : 16'h7FFF;  // 溢出
        end
        
        // 应用符号和溢出检查
        if (fp16_sign) begin
            if (fp16_shift_result > 16'h8000) begin
                fp16_to_int16_result = 16'h8000;
            end else begin
                fp16_to_int16_result = (~fp16_shift_result + 1);
            end
        end else begin
            if (fp16_shift_result > 16'h7FFF) begin
                fp16_to_int16_result = 16'h7FFF;
            end else begin
                fp16_to_int16_result = fp16_shift_result[15:0];
            end
        end
    end
end

// ============= FP32转INT16组合逻辑（带饱和） =============
assign fp32_to_int16_temp_int32 = fp32_to_int32_result;
always @(*) begin
    if ($signed(fp32_to_int16_temp_int32) > $signed(32'h00007FFF)) begin
        fp32_to_int16_result = 16'h7FFF;    // 正溢出
    end else if ($signed(fp32_to_int16_temp_int32) < $signed(32'hFFFF8000)) begin
        fp32_to_int16_result = 16'h8000;    // 负溢出
    end else begin
        fp32_to_int16_result = fp32_to_int16_temp_int32[15:0];
    end
end

// ============= FP16转INT32组合逻辑 =============
assign fp16_to_int32_sign = src_data_16[15];
assign fp16_to_int32_exp = src_data_16[14:10];
assign fp16_to_int32_mant = src_data_16[9:0];
assign fp16_to_int32_biased_exp = {1'b0, fp16_to_int32_exp} - 6'd15;
assign fp16_to_int32_significand = {1'b1, fp16_to_int32_mant};
assign fp16_to_int32_is_inf_nan = (fp16_to_int32_exp == 5'h1F);
assign fp16_to_int32_is_zero = (fp16_to_int32_exp == 5'h00);
assign fp16_to_int32_exp_overflow = ($signed(fp16_to_int32_biased_exp) > $signed(6'd30));
assign fp16_to_int32_exp_underflow = ($signed(fp16_to_int32_biased_exp) < $signed(6'd0));

// FP16转INT32移位计算（README: +∞/NaN→正最大，-∞→负最大）
always @(*) begin
    if (fp16_to_int32_is_inf_nan) begin
        fp16_to_int32_result = fp16_to_int32_sign ? 32'h80000000 : 32'h7FFFFFFF;
    end else if (fp16_to_int32_is_zero) begin
        fp16_to_int32_result = 32'h00000000;
    end else if (fp16_to_int32_exp_overflow) begin
        fp16_to_int32_result = fp16_to_int32_sign ? 32'h80000000 : 32'h7FFFFFFF;
    end else if (fp16_to_int32_exp_underflow) begin
        fp16_to_int32_result = 32'h00000000;
    end else begin
        // 计算移位量
        if ((10 - fp16_to_int32_biased_exp[4:0]) >= 0 && (10 - fp16_to_int32_biased_exp[4:0]) < 11) begin
            fp16_to_int32_shift_result = fp16_to_int32_significand >> (10 - fp16_to_int32_biased_exp[4:0]);
        end else if ((fp16_to_int32_biased_exp[4:0] - 10) > 0 && (fp16_to_int32_biased_exp[4:0] - 10) < 22) begin
            fp16_to_int32_shift_result = fp16_to_int32_significand << (fp16_to_int32_biased_exp[4:0] - 10);
        end else begin
            fp16_to_int32_shift_result = fp16_to_int32_sign ? 32'h80000000 : 32'h7FFFFFFF;  // 溢出
        end
        
        // 应用符号和溢出检查
        if (fp16_to_int32_sign) begin
            if (fp16_to_int32_shift_result > 32'h80000000) begin
                fp16_to_int32_result = 32'h80000000;
            end else begin
                fp16_to_int32_result = (~fp16_to_int32_shift_result + 1);
            end
        end else begin
            if (fp16_to_int32_shift_result > 32'h7FFFFFFF) begin
                fp16_to_int32_result = 32'h7FFFFFFF;
            end else begin
                fp16_to_int32_result = fp16_to_int32_shift_result;
            end
        end
    end
end

//===================== 子字并行转换 ====================
// 并行转换低16位和高16位数据（FP16->INT16）
// 需要为src_low_16和src_high_16分别计算fp16_to_int16
reg [15:0] fp16_to_int16_low_result;  // 在always块中赋值，需声明为reg
reg [15:0] fp16_to_int16_high_result;  // 在always块中赋值，需声明为reg

// 为src_low_16计算FP16转INT16
wire        fp16_low_sign;
wire [4:0]  fp16_low_exp;
wire [9:0]  fp16_low_mant;
wire [5:0]  fp16_low_biased_exp;
wire [15:0] fp16_low_int_result;
wire [10:0] fp16_low_significand;
reg [15:0] fp16_low_shift_result;  // 在always块中赋值，需声明为reg
wire        fp16_low_is_inf_nan;
wire        fp16_low_is_zero;
wire        fp16_low_exp_overflow;
wire        fp16_low_exp_underflow;

assign fp16_low_sign = src_low_16[15];
assign fp16_low_exp = src_low_16[14:10];
assign fp16_low_mant = src_low_16[9:0];
assign fp16_low_biased_exp = {1'b0, fp16_low_exp} - 6'd15;
assign fp16_low_significand = {1'b1, fp16_low_mant};
assign fp16_low_is_inf_nan = (fp16_low_exp == 5'h1F);
assign fp16_low_is_zero = (fp16_low_exp == 5'h00);
assign fp16_low_exp_overflow = ($signed(fp16_low_biased_exp) > $signed(6'd14));
assign fp16_low_exp_underflow = ($signed(fp16_low_biased_exp) < $signed(6'd0));

always @(*) begin
    if (fp16_low_is_inf_nan) begin
        fp16_to_int16_low_result = fp16_low_sign ? 16'h8000 : 16'h7FFF;
    end else if (fp16_low_is_zero) begin
        fp16_to_int16_low_result = 16'h0000;
    end else if (fp16_low_exp_overflow) begin
        fp16_to_int16_low_result = fp16_low_sign ? 16'h8000 : 16'h7FFF;
    end else if (fp16_low_exp_underflow) begin
        fp16_to_int16_low_result = 16'h0000;
    end else begin
        if ((10 - fp16_low_biased_exp[4:0]) >= 0 && (10 - fp16_low_biased_exp[4:0]) < 11) begin
            fp16_low_shift_result = fp16_low_significand >> (10 - fp16_low_biased_exp[4:0]);
        end else if ((fp16_low_biased_exp[4:0] - 10) > 0 && (fp16_low_biased_exp[4:0] - 10) < 6) begin
            fp16_low_shift_result = fp16_low_significand << (fp16_low_biased_exp[4:0] - 10);
        end else begin
            fp16_low_shift_result = fp16_low_sign ? 16'h8000 : 16'h7FFF;
        end
        
        if (fp16_low_sign) begin
            if (fp16_low_shift_result > 16'h8000) begin
                fp16_to_int16_low_result = 16'h8000;
            end else begin
                fp16_to_int16_low_result = (~fp16_low_shift_result + 1);
            end
        end else begin
            if (fp16_low_shift_result > 16'h7FFF) begin
                fp16_to_int16_low_result = 16'h7FFF;
            end else begin
                fp16_to_int16_low_result = fp16_low_shift_result[15:0];
            end
        end
    end
end

// 为src_high_16计算FP16转INT16
wire        fp16_high_sign;
wire [4:0]  fp16_high_exp;
wire [9:0]  fp16_high_mant;
wire [5:0]  fp16_high_biased_exp;
wire [15:0] fp16_high_int_result;
wire [10:0] fp16_high_significand;
reg [15:0] fp16_high_shift_result;  // 在always块中赋值，需声明为reg
wire        fp16_high_is_inf_nan;
wire        fp16_high_is_zero;
wire        fp16_high_exp_overflow;
wire        fp16_high_exp_underflow;

assign fp16_high_sign = src_high_16[15];
assign fp16_high_exp = src_high_16[14:10];
assign fp16_high_mant = src_high_16[9:0];
assign fp16_high_biased_exp = {1'b0, fp16_high_exp} - 6'd15;
assign fp16_high_significand = {1'b1, fp16_high_mant};
assign fp16_high_is_inf_nan = (fp16_high_exp == 5'h1F);
assign fp16_high_is_zero = (fp16_high_exp == 5'h00);
assign fp16_high_exp_overflow = ($signed(fp16_high_biased_exp) > $signed(6'd14));
assign fp16_high_exp_underflow = ($signed(fp16_high_biased_exp) < $signed(6'd0));

always @(*) begin
    if (fp16_high_is_inf_nan) begin
        fp16_to_int16_high_result = fp16_high_sign ? 16'h8000 : 16'h7FFF;
    end else if (fp16_high_is_zero) begin
        fp16_to_int16_high_result = 16'h0000;
    end else if (fp16_high_exp_overflow) begin
        fp16_to_int16_high_result = fp16_high_sign ? 16'h8000 : 16'h7FFF;
    end else if (fp16_high_exp_underflow) begin
        fp16_to_int16_high_result = 16'h0000;
    end else begin
        if ((10 - fp16_high_biased_exp[4:0]) >= 0 && (10 - fp16_high_biased_exp[4:0]) < 11) begin
            fp16_high_shift_result = fp16_high_significand >> (10 - fp16_high_biased_exp[4:0]);
        end else if ((fp16_high_biased_exp[4:0] - 10) > 0 && (fp16_high_biased_exp[4:0] - 10) < 6) begin
            fp16_high_shift_result = fp16_high_significand << (fp16_high_biased_exp[4:0] - 10);
        end else begin
            fp16_high_shift_result = fp16_high_sign ? 16'h8000 : 16'h7FFF;
        end
        
        if (fp16_high_sign) begin
            if (fp16_high_shift_result > 16'h8000) begin
                fp16_to_int16_high_result = 16'h8000;
            end else begin
                fp16_to_int16_high_result = (~fp16_high_shift_result + 1);
            end
        end else begin
            if (fp16_high_shift_result > 16'h7FFF) begin
                fp16_to_int16_high_result = 16'h7FFF;
            end else begin
                fp16_to_int16_high_result = fp16_high_shift_result[15:0];
            end
        end
    end
end

assign dst_low_16 = fp16_to_int16_low_result;
assign dst_high_16 = fp16_to_int16_high_result;

//===================== 普通转换 ==========================
// 16位转换结果
assign dst_data_16 = src_prec ? fp32_to_int16_result : fp16_to_int16_result;

// 32位转换结果
assign dst_data_32 = src_prec ? fp32_to_int32_result : fp16_to_int32_result;

// 根据子字并行模式选择输出
wire [31:0] dst_data_16_result;
assign dst_data_16_result = subword_parallel_mode ? 
                           {dst_high_16, dst_low_16} :                                    // 子字并行：组合高低转换结果
                           (dst_pos ? {dst_data_16, 16'h0000} : {16'h0000, dst_data_16}); // 普通模式：结果占一半，另一半由阵列用上一拍 dr 填

// 选择最终输出数据  
assign dst_data = dst_prec ? dst_data_32 : dst_data_16_result;

// 与输入指令有效信号一致
assign result_vld = inst_vld;

// 指令无效时输出为0
assign out_reg = inst_vld ? dst_data : 32'h0;

endmodule

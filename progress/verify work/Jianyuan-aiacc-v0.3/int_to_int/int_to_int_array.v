//----------------------------------------------------------------------------
// Filename: int_to_int_array.v
// Author: [Oliver]
// Date: 2025-8-28
// Version: 1.0
// Description: INT to INT conversion module
//----------------------------------------------------------------------------
`timescale 1ns / 1ps
module int_to_int_array #(
    parameter SMC_ID = 0                // SMC ID for this module
)(
    input clk,                  // 时钟输入
    input rst_n,                // 低有效复位

    input wire [127:0] dvr_inttoint_s_in,    // 输入数据寄存器
    input wire [6:0]   cru_inttoint_in,      // 上行指令寄存器
    output reg [127:0] dr_inttoint_d_out,     // 输出数据寄存器
    output reg [6:0]   cru_inttoint_out,
    input wire [4:0]   smc_id_in
);

// 微指令解析
wire instr_vld = cru_inttoint_in[0];      // 指令有效信号
wire src_prec = cru_inttoint_in[1];       // 源寄存器精度：0=16bit，1=32bit
wire dst_prec = cru_inttoint_in[2];       // 目的寄存器精度：0=16bit，1=32bit
wire src_signed = cru_inttoint_in[3];     // 源数据符号位：0=无符号，1=有符号
wire dst_signed = cru_inttoint_in[4];     // 目的数据符号位：0=无符号，1=有符号
wire src_pos = cru_inttoint_in[5];        // 源数据位置：0=低位，1=高位（仅在非全精度时有效）
wire dst_pos = cru_inttoint_in[6];        // 目的数据位置：0=低位，1=高位（仅在非全精度时有效）

wire [31:0]  in_reg_0 = dvr_inttoint_s_in[127:96];        // 输入寄存器0（整数）
wire [31:0]  in_reg_1 = dvr_inttoint_s_in[95:64];         // 输入寄存器1（整数）
wire [31:0]  in_reg_2 = dvr_inttoint_s_in[63:32];         // 输入寄存器2（整数）
wire [31:0]  in_reg_3 = dvr_inttoint_s_in[31:0];          // 输入寄存器3（整数）

wire [31:0]  out_reg_0;       // 输出寄存器0（整数）
wire [31:0]  out_reg_1;       // 输出寄存器1（整数）
wire [31:0]  out_reg_2;       // 输出寄存器2（整数）
wire [31:0]  out_reg_3;       // 输出寄存器3（整数）

wire [3:0]   result_vld;     // 结果有效信号（4位）

int_to_int unit_0 (
    .instr_vld(instr_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_signed(src_signed),
    .dst_signed(dst_signed),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg_0),
    .out_reg(out_reg_0),
    .result_vld(result_vld[0])
);

int_to_int unit_1 (
    .instr_vld(instr_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_signed(src_signed),
    .dst_signed(dst_signed),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg_1),
    .out_reg(out_reg_1),
    .result_vld(result_vld[1])
);

int_to_int unit_2 (
    .instr_vld(instr_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_signed(src_signed),
    .dst_signed(dst_signed),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg_2),
    .out_reg(out_reg_2),
    .result_vld(result_vld[2])
);

int_to_int unit_3 (
    .instr_vld(instr_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_signed(src_signed),
    .dst_signed(dst_signed),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg_3),
    .out_reg(out_reg_3),
    .result_vld(result_vld[3])
);

// 输出寄存器更新
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dr_inttoint_d_out <= 128'd0;
    end else if (instr_vld) begin
        dr_inttoint_d_out[127:96]   <= out_reg_0;
        dr_inttoint_d_out[95:64]    <= out_reg_1;
        dr_inttoint_d_out[63:32]    <= out_reg_2;
        dr_inttoint_d_out[31:0]     <= out_reg_3;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cru_inttoint_out <= 7'd0;
    end else begin
        cru_inttoint_out <= cru_inttoint_in;
    end
end

endmodule
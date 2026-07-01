//----------------------------------------------------------------------------
// Filename: shift_up.v
// Author: [Oliver]
// Date: 2025-8-12
// Version: 1.0
// Description: Shift up.
//----------------------------------------------------------------------------
`timescale 1ns / 1ps
module shift_up #(
    parameter PARAM_UR_WORD_CNT = 4,    // User register宽度的字数，每个字为32bit
    parameter SMC_ID = 0                // 当前SMC_ID 
)(
    input wire clk,        // Clock input
    input wire rst_n,      // Active low reset

    input wire [134:0] cru_shiftup_in, // 135=1+128+5+1,代表SHIFTUP的上行指令寄存器，存储内容为微指令。

    output wire [127:0] dr_shiftup_out, // 128,代表SHIFTUP的计算输出数据。
    output wire [134:0] cru_shiftup_out // 135=1+128+5+1,代表SHIFTUP的上行指令寄存器，去往下游的输出信号。
);

reg  [127:0] dr_shiftup_reg; // 输出数据寄存器
reg  [134:0] cru_shiftup_reg; // 输出指令寄存器

assign dr_shiftup_out = dr_shiftup_reg;
assign cru_shiftup_out = cru_shiftup_reg;

wire            vld_in = cru_shiftup_in[0];          // 'b1：指令有效; 'b0：指令无效，相关逻辑IDLE，目标寄存器不更新
wire [127:0]    data_in = cru_shiftup_in[128:1];    // 写入数据
wire [4:0]      smc_id_in = cru_shiftup_in[133:129]; // 要写入的目的用户寄存器的SMC ID
wire            broadcast_in = cru_shiftup_in[134];  // 'b0：不广播; 'b1：广播

wire            vld_reg = cru_shiftup_reg[0];        // 'b1：寄存器有效; 'b0：寄存器无效，相关逻辑IDLE，目标寄存器不更新
wire [127:0]    data_reg = cru_shiftup_reg[128:1];  // 寄存器数据
wire [4:0]      smc_id_reg = cru_shiftup_reg[133:129]; // 寄存器的SMC ID
wire            broadcast_reg = cru_shiftup_reg[134]; // 'b0：不广播; 'b1：广播

wire [134:0]    cru_next = (vld_in && (SMC_ID <= smc_id_in))
                         ? cru_shiftup_in
                         : cru_shiftup_reg; // 下一个寄存器值

wire [127:0]    dr_next = (vld_in && (broadcast_in || (SMC_ID == smc_id_in)) && (SMC_ID <= smc_id_in))
                        ? data_in  // 当前指令满足条件
                        : (vld_reg && (broadcast_reg || (SMC_ID == smc_id_reg)))
                        ? data_reg // 寄存器中的指令满足条件
                        : dr_shiftup_reg; // 保持当前值

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cru_shiftup_reg <= 135'b0; // Reset output register
        dr_shiftup_reg <= 128'b0; // Reset output data register
    end else begin
        cru_shiftup_reg <= cru_next; // Update output register
        dr_shiftup_reg <= dr_next;   // Update output data register
    end
end
endmodule
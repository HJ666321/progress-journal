//----------------------------------------------------------------------------
// Filename: shift_down.v
// Author: [Oliver]
// Date: 2025-8-15
// Version: 1.0
// Description: Shift down module
//----------------------------------------------------------------------------
`timescale 1ns / 1ps
module shift_down #(
    parameter PARAM_UR_WORD_CNT = 4,    // User register宽度的字数，每个字为32bit
    parameter SMC_ID = 0                // SMC ID for this module
)(
    input wire clk,        // Clock input
    input wire rst_n,      // Active low reset

    input wire [133:0] crd_shiftdn_in, // 134=1+128+5,代表SHIFTDN下行指令寄存器
    input wire [127:0] dvr_shiftdn_in, // 128,代表SHIFTDN计算输出数据

    output wire [133:0] crd_shiftdn_out // 134=1+128+5,代表SHIFTDN下行指令寄存器
);

// 寄存器定义
reg [133:0] crd_shiftdn_reg; // 输出指令寄存器
assign crd_shiftdn_out = crd_shiftdn_reg;

// 输入信号分解 (位分布: [0]=vld, [128:1]=data, [133:129]=smc_id)
wire            vld_in     = crd_shiftdn_in[0];          // 指令有效位
wire [127:0]    data_in    = crd_shiftdn_in[128:1];     // 输入数据
wire [4:0]      smc_id_in  = crd_shiftdn_in[133:129];   // 目标SMC ID

// 组合逻辑计算下一个状态
reg [133:0] crd_next;

always @(*) begin
    // 默认保持当前值
    crd_next = crd_shiftdn_reg;
    
    if (vld_in) begin
        if (smc_id_in > SMC_ID) begin
            // 目标SMC_ID > 当前模块ID - 传递指令
            crd_next = crd_shiftdn_in;
        end else if (smc_id_in == SMC_ID) begin
            // 目标SMC_ID匹配 - 保存数据 (位分布: [133:129]=smc_id, [128:1]=data, [0]=vld)
            crd_next = {smc_id_in, dvr_shiftdn_in, 1'b1};
        end
        // 如果smc_id_in < SMC_ID，则保持当前值
    end
end

// 时序逻辑更新寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        crd_shiftdn_reg <= 134'b0; // 复位
    end else begin
        crd_shiftdn_reg <= crd_next; // 更新寄存器
    end
end

// 调试信息（仅用于仿真）
`ifndef SYNTHESIS
always @(posedge clk) begin
    if (vld_in) begin
        if (smc_id_in > SMC_ID) begin
            $display("[%t] SHIFT_DOWN: Passing instruction. SMC_ID=%0d, Input_SMC=%0d",
                     $time, SMC_ID, smc_id_in);
        end else if (smc_id_in == SMC_ID) begin
            $display("[%t] SHIFT_DOWN: Saving data. SMC_ID=%0d, Data=%32h",
                     $time, SMC_ID, dvr_shiftdn_in);
        end else begin
            $display("[%t] SHIFT_DOWN: Holding value. SMC_ID=%0d, Input_SMC=%0d, Current_Value=%32h",
                     $time, SMC_ID, smc_id_in, crd_shiftdn_reg[128:1]);
        end
    end
end
`endif

endmodule
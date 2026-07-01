`timescale 1ns / 1ps
//=========================================================
//File     : user_register.v
//Moudule  : User Register Module
//Author   : Oliver
//Email    :
//Created  : 2025-11-20
//Modified : 2025-11-20
//Version  : v1.0
//=========================================================
//Description:
//  用户寄存器模块
//
//Features:
//  1. 支持多读多写端口（不同时对同一个bank做操作）
//  2. 支持写入和读取流水线
//
//Architecture:
//  - 4个独立的BRAM Bank（Bank 0-3）
//  - 4个写端口（Write Port 0-3）
//  - 4个读端口（Read Port 0-3）
//  - 约束：同一时刻，多个端口不能访问同一个Bank
//    * 4个写端口必须访问不同的Bank
//    * 4个读端口必须访问不同的Bank
//    * 写端口和读端口可以同时访问不同的Bank（无冲突）
//    * 如果发生冲突，优先级为：Port 0 > Port 1 > Port 2 > Port 3
//
//Parameters:
//  SMC_ID                     : 片上模块ID
//  PARAM_UR_BYTE_CNT          : 用户寄存器字节数
//  PARAM_UR_WR_PORT_CNT       : 写端口数量
//  PARAM_UR_RD_PORT_CNT       : 读端口数量
//  PARAM_UR_BANK_CNT          : bank_sram 数量（默认 8），相关信号宽度与此一致
//  PARAM_UR_BANK_BIT_NUM      : 寄存器BANK编码位数
//  PARAM_UR_BANK_ADDR_BIT_NUM : 寄存器BANK地址位数
//  PARAM_UR_WRI_PIPE_CNT      : 写入流水线深度
//  PARAM_UR_RDI_PIPE_CNT      : 读取指令流水线深度
//  PARAM_UR_RDO_PIPE_CNT      : 读取数据流水线深度
//
//IO Ports:
//  i_clk              : 时钟信号
//  i_rst_n            : 复位信号，低有效
//  i_smc_id           : 片上模块ID
//  o_ur_rdata_X       : 读端口X数据输出
//  i_uvr_wdata_X      : 写端口X数据输入
//  i_cru_ur           : 控制寄存器单元输入信号
//
//Dependencies:
//  None
//
//Called by:
//  Top Module
//=========================================================
//Revision History:
//Date        Version    Author      Description
//2025-11-20  v1.0       Oliver      Created file
//=========================================================
module user_register #(
    parameter SMC_ID                     = 5'd0,
    parameter PARAM_UR_BYTE_CNT          = 5'd16,
    parameter PARAM_UR_WR_PORT_CNT       = 3'd4,
    parameter PARAM_UR_RD_PORT_CNT      = 3'd4,
    parameter PARAM_UR_BANK_CNT          = 4'd8,   // bank_sram 数量，与相关信号宽度一致
    parameter PARAM_UR_BANK_BIT_NUM     = 2'd3,
    parameter PARAM_UR_BANK_ADDR_BIT_NUM = 4'd8,
    parameter PARAM_UR_WRI_PIPE_CNT     = 1'd0,
    parameter PARAM_UR_RDI_PIPE_CNT     = 1'd0,
    parameter PARAM_UR_RDO_PIPE_CNT     = 1'd0
)(
    input  wire                       i_clk,
    input  wire                       i_rst_n,
    input  wire [4:0]                 i_smc_id,
    input  wire [159:0]               i_cru_ur,      //UR上行指令寄存器 1+(8+3)*4*2+16*4=161

    input  wire [127:0]               i_uvr_wdata_0,
    input  wire [127:0]               i_uvr_wdata_1,
    input  wire [127:0]               i_uvr_wdata_2,
    input  wire [127:0]               i_uvr_wdata_3,

    output reg  [127:0]               o_ur_rdata_0,
    output reg  [127:0]               o_ur_rdata_1,
    output reg  [127:0]               o_ur_rdata_2,
    output reg  [127:0]               o_ur_rdata_3,

    output reg  [159:0]               o_cru_ur      //留个空
);
// ==========================================================================
// 1. 控制信号提取
// ==========================================================================

// 控制寄存器单元有效信号
wire w_cru_ur_vld = (i_smc_id == SMC_ID);

// ==========================================================================
// i_cru_ur[159:0] 字段布局 (从低位到高位):
//   写端口0[27:0] -> 写端口1[55:28] -> 写端口2[83:56] -> 写端口3[111:84] ->
//   读端口0[123:112] -> 读端口1[135:124] -> 读端口2[147:136] -> 读端口3[159:148]
// 写端口格式 (28位，从低到高): {wbank[2:0], waddr[7:0], we, wbe[15:0]}
// 读端口格式 (12位，从低到高): {rbank[2:0], raddr[7:0], re}
// ==========================================================================

// 写端口0 [27:0] - 位序: we[0], wbank[3:1], waddr[11:4], wbe[27:12]
wire        w_ur_we_0    = i_cru_ur[0];
wire [2:0]  w_ur_wbank_0 = i_cru_ur[3:1];
wire [7:0]  w_ur_waddr_0 = i_cru_ur[11:4];
wire [15:0] w_ur_wbe_0   = i_cru_ur[27:12];

// 写端口1 [55:28] - 位序: we[28], wbank[31:29], waddr[39:32], wbe[55:40]
wire        w_ur_we_1    = i_cru_ur[28];
wire [2:0]  w_ur_wbank_1 = i_cru_ur[31:29];
wire [7:0]  w_ur_waddr_1 = i_cru_ur[39:32];
wire [15:0] w_ur_wbe_1   = i_cru_ur[55:40];

// 写端口2 [83:56] - 位序: we[56], wbank[59:57], waddr[67:60], wbe[83:68]
wire        w_ur_we_2    = i_cru_ur[56];
wire [2:0]  w_ur_wbank_2 = i_cru_ur[59:57];
wire [7:0]  w_ur_waddr_2 = i_cru_ur[67:60];
wire [15:0] w_ur_wbe_2   = i_cru_ur[83:68];

// 写端口3 [111:84] - 位序: we[84], wbank[87:85], waddr[95:88], wbe[111:96]
wire        w_ur_we_3    = i_cru_ur[84];
wire [2:0]  w_ur_wbank_3 = i_cru_ur[87:85];
wire [7:0]  w_ur_waddr_3 = i_cru_ur[95:88];
wire [15:0] w_ur_wbe_3   = i_cru_ur[111:96];

// 读端口0 [123:112] - 位序: re[112], rbank[115:113], raddr[123:116]
wire        w_ur_re_0    = i_cru_ur[112];
wire [2:0]  w_ur_rbank_0 = i_cru_ur[115:113];
wire [7:0]  w_ur_raddr_0 = i_cru_ur[123:116];

// 读端口1 [135:124] - 位序: re[124], rbank[127:125], raddr[135:128]
wire        w_ur_re_1    = i_cru_ur[124];
wire [2:0]  w_ur_rbank_1 = i_cru_ur[127:125];
wire [7:0]  w_ur_raddr_1 = i_cru_ur[135:128];

// 读端口2 [147:136] - 位序: re[136], rbank[139:137], raddr[147:140]
wire        w_ur_re_2    = i_cru_ur[136];
wire [2:0]  w_ur_rbank_2 = i_cru_ur[139:137];
wire [7:0]  w_ur_raddr_2 = i_cru_ur[147:140];

// 读端口3 [159:148] - 位序: re[148], rbank[151:149], raddr[159:152]
wire        w_ur_re_3    = i_cru_ur[148];
wire [2:0]  w_ur_rbank_3 = i_cru_ur[151:149];
wire [7:0]  w_ur_raddr_3 = i_cru_ur[159:152];

// ==========================================================================
// 2. pipeline寄存
// ==========================================================================
// 写入流水线寄存
reg         r_we_pipe[0:PARAM_UR_BANK_CNT-1];
reg [10:0]  r_waddr_pipe[0:PARAM_UR_BANK_CNT-1];
reg [15:0]  r_wbe_pipe[0:PARAM_UR_BANK_CNT-1];
reg [127:0] r_wdata_pipe[0:PARAM_UR_BANK_CNT-1];

// 读取流水线寄存
reg         r_re_pipe[0:PARAM_UR_BANK_CNT-1];
reg [10:0]  r_raddr_pipe[0:PARAM_UR_BANK_CNT-1];
reg [127:0] r_rdata_pipe[0:PARAM_UR_BANK_CNT-1];

// 声明为wire类型，用于连续赋值（与 bank_sram 数量一致）
wire [PARAM_UR_BANK_CNT-1:0]   w_bank_ena;
wire [PARAM_UR_BANK_CNT-1:0]   w_bank_enb;
wire [15:0]  w_bank_wbea [0:PARAM_UR_BANK_CNT-1];
wire [7:0]   w_bank_addra [0:PARAM_UR_BANK_CNT-1];
wire [7:0]   w_bank_addrb [0:PARAM_UR_BANK_CNT-1];
wire [127:0] w_bank_dina [0:PARAM_UR_BANK_CNT-1];
wire [127:0] w_bank_doutb [0:PARAM_UR_BANK_CNT-1];

// ==========================================================================
// 写入流水线寄存逻辑
// 注意：如果多个写端口访问同一个Bank，只有优先级最高的端口生效
// 优先级：Port 0 > Port 1 > Port 2 > Port 3
// 约束：外部应确保4个写端口访问不同的Bank，避免冲突
// ==========================================================================
integer i;
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        for (i = 0; i < PARAM_UR_BANK_CNT; i = i + 1) begin
            r_we_pipe[i]     <= 1'b0;
            r_waddr_pipe[i]  <= 11'd0;
            r_wbe_pipe[i]    <= 16'd0;
            r_wdata_pipe[i]  <= 128'd0;
        end
    end else begin
        for (i = 0; i < PARAM_UR_BANK_CNT; i = i + 1) begin
            // 优先级：Port 0 > Port 1 > Port 2 > Port 3
            if (w_ur_wbank_0 == i) begin
                r_we_pipe[i]     <= w_ur_we_0;
                r_waddr_pipe[i]  <= w_ur_waddr_0;
                r_wbe_pipe[i]    <= w_ur_wbe_0;
                r_wdata_pipe[i]  <= i_uvr_wdata_0;
            end else if (w_ur_wbank_1 == i) begin
                r_we_pipe[i]     <= w_ur_we_1;
                r_waddr_pipe[i]  <= w_ur_waddr_1;
                r_wbe_pipe[i]    <= w_ur_wbe_1;
                r_wdata_pipe[i]  <= i_uvr_wdata_1;
            end else if (w_ur_wbank_2 == i) begin
                r_we_pipe[i]     <= w_ur_we_2;
                r_waddr_pipe[i]  <= w_ur_waddr_2;
                r_wbe_pipe[i]    <= w_ur_wbe_2;
                r_wdata_pipe[i]  <= i_uvr_wdata_2;
            end else if (w_ur_wbank_3 == i) begin
                r_we_pipe[i]     <= w_ur_we_3;
                r_waddr_pipe[i]  <= w_ur_waddr_3;
                r_wbe_pipe[i]    <= w_ur_wbe_3;
                r_wdata_pipe[i]  <= i_uvr_wdata_3;
            end else begin
                r_we_pipe[i]     <= 0;
                r_waddr_pipe[i]  <= 0;
                r_wbe_pipe[i]    <= 0;
                r_wdata_pipe[i]  <= 0;
            end
        end
    end
end
// ==========================================================================
// 读取流水线寄存逻辑
// 注意：如果多个读端口访问同一个Bank，只有优先级最高的端口生效
// 优先级：Port 0 > Port 1 > Port 2 > Port 3
// 约束：外部应确保4个读端口访问不同的Bank，避免冲突
// ==========================================================================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        for (i = 0; i < PARAM_UR_BANK_CNT; i = i + 1) begin
            r_re_pipe[i]    <= 1'b0;
            r_raddr_pipe[i] <= 11'd0;
            r_rdata_pipe[i] <= 128'd0;
        end
    end else begin
        for (i = 0; i < PARAM_UR_BANK_CNT; i = i + 1) begin
            // 优先级：Port 0 > Port 1 > Port 2 > Port 3
            if (w_ur_rbank_0 == i) begin
                r_re_pipe[i]    <= w_ur_re_0;
                r_raddr_pipe[i] <= w_ur_raddr_0;
                r_rdata_pipe[i] <= w_bank_doutb[i];
            end else if (w_ur_rbank_1 == i) begin
                r_re_pipe[i]    <= w_ur_re_1;
                r_raddr_pipe[i] <= w_ur_raddr_1;
                r_rdata_pipe[i] <= w_bank_doutb[i];
            end else if (w_ur_rbank_2 == i) begin
                r_re_pipe[i]    <= w_ur_re_2;
                r_raddr_pipe[i] <= w_ur_raddr_2;
                r_rdata_pipe[i] <= w_bank_doutb[i];
            end else if (w_ur_rbank_3 == i) begin
                r_re_pipe[i]    <= w_ur_re_3;
                r_raddr_pipe[i] <= w_ur_raddr_3;
                r_rdata_pipe[i] <= w_bank_doutb[i];
            end else begin
                r_re_pipe[i]    <= r_re_pipe[i];
                r_raddr_pipe[i] <= r_raddr_pipe[i];
                r_rdata_pipe[i] <= r_rdata_pipe[i];
            end
        end
    end
end

// ==========================================================================
// Bank 索引打拍 - 用于匹配 memory 读延迟一拍
// ==========================================================================


// ==========================================================================
// 3. 端口信号连接转换 - 使用连续赋值代替过程赋值
// 注意：这里的条件表达式也遵循优先级：Port 0 > Port 1 > Port 2 > Port 3
// 如果多个端口访问同一个Bank，只有优先级最高的端口生效
// ==========================================================================
reg [2:0] ur_rbank_c0,ur_rbank_c1,ur_rbank_c2,ur_rbank_c3;
reg w_ur_re_0_d,w_ur_re_1_d,w_ur_re_2_d,w_ur_re_3_d;
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        ur_rbank_c0 <= 3'd0;
        ur_rbank_c1 <= 3'd0;
        ur_rbank_c2 <= 3'd0;
        ur_rbank_c3 <= 3'd0;
        w_ur_re_0_d <= 1'b0;
        w_ur_re_1_d <= 1'b0;
        w_ur_re_2_d <= 1'b0;
        w_ur_re_3_d <= 1'b0;
    end else begin
        ur_rbank_c0 <= w_ur_re_0 ? w_ur_rbank_0 : ur_rbank_c0;
        ur_rbank_c1 <= w_ur_re_1 ? w_ur_rbank_1 : ur_rbank_c1;
        ur_rbank_c2 <= w_ur_re_2 ? w_ur_rbank_2 : ur_rbank_c2;
        ur_rbank_c3 <= w_ur_re_3 ? w_ur_rbank_3 : ur_rbank_c3;
        w_ur_re_0_d <= w_ur_re_0;
        w_ur_re_1_d <= w_ur_re_1;
        w_ur_re_2_d <= w_ur_re_2;
        w_ur_re_3_d <= w_ur_re_3;
    end
end

genvar j;
generate
    for (j = 0; j < PARAM_UR_BANK_CNT; j = j + 1) begin : bank_signals
        // 写入控制信号 - 使用连续赋值（优先级：Port 0 > Port 1 > Port 2 > Port 3）
        assign w_bank_ena[j] = w_cru_ur_vld ? (
            (w_ur_wbank_0 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_we_pipe[j] : w_ur_we_0) :
            (w_ur_wbank_1 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_we_pipe[j] : w_ur_we_1) :
            (w_ur_wbank_2 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_we_pipe[j] : w_ur_we_2) :
            (w_ur_wbank_3 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_we_pipe[j] : w_ur_we_3) : 1'b0
        ) : 1'b0;
        assign w_bank_wbea[j] = w_cru_ur_vld ? (
            (w_ur_wbank_0 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_wbe_pipe[j] : w_ur_wbe_0) :
            (w_ur_wbank_1 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_wbe_pipe[j] : w_ur_wbe_1) :
            (w_ur_wbank_2 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_wbe_pipe[j] : w_ur_wbe_2) :
            (w_ur_wbank_3 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_wbe_pipe[j] : w_ur_wbe_3) : 16'd0
        ) : 16'd0;
        assign w_bank_addra[j] = w_cru_ur_vld ? (
            (w_ur_wbank_0 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_waddr_pipe[j][7:0] : w_ur_waddr_0) :
            (w_ur_wbank_1 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_waddr_pipe[j][7:0] : w_ur_waddr_1) :
            (w_ur_wbank_2 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_waddr_pipe[j][7:0] : w_ur_waddr_2) :
            (w_ur_wbank_3 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_waddr_pipe[j][7:0] : w_ur_waddr_3) : 8'd0
        ) : 8'd0;
        assign w_bank_dina[j] = w_cru_ur_vld ? (
            (w_ur_wbank_0 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_wdata_pipe[j] : i_uvr_wdata_0) :
            (w_ur_wbank_1 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_wdata_pipe[j] : i_uvr_wdata_1) :
            (w_ur_wbank_2 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_wdata_pipe[j] : i_uvr_wdata_2) :
            (w_ur_wbank_3 == j) ? (PARAM_UR_WRI_PIPE_CNT ? r_wdata_pipe[j] : i_uvr_wdata_3) : 128'd0
        ) : 128'd0;
        // 读取控制信号 - 使用连续赋值（优先级：Port 0 > Port 1 > Port 2 > Port 3）
        assign w_bank_enb[j] = w_cru_ur_vld ? (
            (w_ur_rbank_0 == j) ? (PARAM_UR_RDI_PIPE_CNT ? r_re_pipe[j] : w_ur_re_0) :
            (w_ur_rbank_1 == j) ? (PARAM_UR_RDI_PIPE_CNT ? r_re_pipe[j] : w_ur_re_1) :
            (w_ur_rbank_2 == j) ? (PARAM_UR_RDI_PIPE_CNT ? r_re_pipe[j] : w_ur_re_2) :
            (w_ur_rbank_3 == j) ? (PARAM_UR_RDI_PIPE_CNT ? r_re_pipe[j] : w_ur_re_3) : 1'b0
        ) : 1'b0;
        assign w_bank_addrb[j] = w_cru_ur_vld ? (
            (w_ur_rbank_0 == j) ? (PARAM_UR_RDI_PIPE_CNT ? r_raddr_pipe[j][7:0] : w_ur_raddr_0) :
            (w_ur_rbank_1 == j) ? (PARAM_UR_RDI_PIPE_CNT ? r_raddr_pipe[j][7:0] : w_ur_raddr_1) :
            (w_ur_rbank_2 == j) ? (PARAM_UR_RDI_PIPE_CNT ? r_raddr_pipe[j][7:0] : w_ur_raddr_2) :
            (w_ur_rbank_3 == j) ? (PARAM_UR_RDI_PIPE_CNT ? r_raddr_pipe[j][7:0] : w_ur_raddr_3) : 8'd0
        ) : 8'd0;
    end
endgenerate

// ==========================================================================
// 输出选择（组合逻辑，复位时赋 0）
// 注意：读数据输出不依赖于 w_cru_ur_vld，因为流水线中的数据可能来自之前的有效指令
// 注意：由于 memory 读数据延迟一拍，当 PARAM_UR_RDO_PIPE_CNT=0 时，需要使用打拍的 bank 索引
// ==========================================================================
always @(*) begin
    if (!i_rst_n) begin
        o_ur_rdata_0 = 128'b0;
        o_ur_rdata_1 = 128'b0;
        o_ur_rdata_2 = 128'b0;
        o_ur_rdata_3 = 128'b0;
    end else begin
        o_ur_rdata_0 = w_ur_re_0_d ? w_bank_doutb[ur_rbank_c0] : o_ur_rdata_0;
        o_ur_rdata_1 = w_ur_re_1_d ? w_bank_doutb[ur_rbank_c1] : o_ur_rdata_1;
        o_ur_rdata_2 = w_ur_re_2_d ? w_bank_doutb[ur_rbank_c2] : o_ur_rdata_2;
        o_ur_rdata_3 = w_ur_re_3_d ? w_bank_doutb[ur_rbank_c3] : o_ur_rdata_3;
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_cru_ur <= 160'd0;
    end else begin
        o_cru_ur <= i_cru_ur; //直接传递输入信号
    end
end

// ==========================================================================
// 4. 实例化BRAM BANK
// 每个Bank是独立的BRAM，支持同时读写（通过不同的端口）
// 注意：每个Bank在同一时刻只能被一个写端口和一个读端口访问
// ==========================================================================
genvar x;
generate
    for (x = 0; x < PARAM_UR_BANK_CNT; x = x + 1) begin : bram_bank_inst
        bank_sram u_bank_sram (
            .clk      (i_clk),
            .ena      (w_bank_ena[x]),      // 写使能（来自4个写端口的仲裁结果）
            .enb      (w_bank_enb[x]),      // 读使能（来自4个读端口的仲裁结果）
            .wea      (w_bank_wbea[x]),     // 写字节使能
            .addra    (w_bank_addra[x]),    // 写地址
            .addrb    (w_bank_addrb[x]),    // 读地址
            .dina     (w_bank_dina[x]),     // 写数据
            .doutb    (w_bank_doutb[x])     // 读数据
        );
    end
endgenerate



endmodule
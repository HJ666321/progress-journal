//==============================================================================
// FP16转FP32乘法器阵列模块
// 支持32组并行FP16乘法计算，结果输出为FP32格式
// 符合IEEE 754-2008标准
//==============================================================================

module fp16mul #(
    parameter SMC_ID = 0,    // SMC ID for this module
    parameter IEEE_754 = 1    // IEEE 754 mode
)(

    // 时钟和复位
    input  wire        clk,
    input  wire        rst_n,
    
    // SMC Identification (5bit, AIACC architecture v0.2.7)
    input  wire [4:0]  i_smc_id,
	
    // 数据输入接口
    input  wire [127:0] dvr_fp16mul_s0,    // S0数据输入 (FP16_A[3:0])
    input  wire [127:0] dvr_fp16mul_s1,    // S1数据输入 (FP16_A[7:4])
    input  wire [127:0] dvr_fp16mul_s2,    // S2数据输入 (FP16_A[11:8])
    input  wire [127:0] dvr_fp16mul_s3,    // S3数据输入 (FP16_A[15:12])
    input  wire [127:0] dvr_fp16mul_s4567, // S4-S7复用数据输入 (FP16_B)
    
    // 控制信号
    input  wire [1:0]   cru_fp16mul_s0123, // S0-S3控制信号
    input  wire [3:0]   cru_fp16mul_s4567, // S4-S7控制信号
    input  wire [2:0]   cru_fp16mul,       // 乘法控制信号
    input  wire [2:0]   i_rounding_mode,   // Rounding mode: 000=RNE, 001=RTZ, 010=RDN, 011=RUP, 100=RMM
    
    // 结果输出寄存器
    output reg  [127:0] dr_fp16mul_d0,     // FP32结果[3:0]
    output reg  [127:0] dr_fp16mul_d1,     // FP32结果[7:4]
    output reg  [127:0] dr_fp16mul_d2,     // FP32结果[11:8]
    output reg  [127:0] dr_fp16mul_d3,     // FP32结果[15:12]
    output reg  [127:0] dr_fp16mul_d4,     // FP32结果[19:16]
    output reg  [127:0] dr_fp16mul_d5,     // FP32结果[23:20]
    output reg  [127:0] dr_fp16mul_d6,     // FP32结果[27:24]
    output reg  [127:0] dr_fp16mul_d7,    // FP32结果[31:28]
    
    // 异常标志输出（每个乘法器一个，共32个）
    output wire [4:0]   o_exception_flags [31:0]  // Exception flags per multiplier: [0]=Invalid, [1]=DivZero, [2]=Overflow, [3]=Underflow, [4]=Inexact
);

//==============================================================================
// 设计参数
//==============================================================================
localparam PARAM_DR_FP16MUL_CNT = 32;      // fp16乘法器数量
localparam PARAM_DR_FP16MUL_S0_CNT = 2;    // s0-s3寄存器数量  
localparam PARAM_DR_FP16MUL_S1_CNT = 2;    // s4-s7寄存器数量

//==============================================================================
// 内部信号定义
//==============================================================================

// 源寄存器组A (S0-S3)
reg [127:0] s0_bank0_r, s0_bank1_r;
reg [127:0] s1_bank0_r, s1_bank1_r;
reg [127:0] s2_bank0_r, s2_bank1_r;
reg [127:0] s3_bank0_r, s3_bank1_r;

// 源寄存器组B (S4-S7)
reg [127:0] s4_bank0_r, s4_bank1_r;
reg [127:0] s5_bank0_r, s5_bank1_r;
reg [127:0] s6_bank0_r, s6_bank1_r;
reg [127:0] s7_bank0_r, s7_bank1_r;

// 锁存寄存器
reg [127:0] selected_s0_r, selected_s1_r, selected_s2_r, selected_s3_r;
reg [127:0] selected_s4_r, selected_s5_r, selected_s6_r, selected_s7_r;

// 计算有效信号
reg [4:0]   compute_valid_r;

// 乘法器输入信号
wire [15:0] fp16_a [31:0];
wire [15:0] fp16_b [31:0];
wire [31:0] fp32_result [31:0];
wire        mul_valid_o [31:0];  // Multiplier output valid signals
wire [4:0]  exception_flags_per_mul [31:0];  // Exception flags from each multiplier

//==============================================================================
// 源寄存器组A (S0-S3) 写入逻辑
//==============================================================================
//==============================================================================
// 控制信号解析
//==============================================================================
// cru_fp16mul_s0123 信号解析
wire cru_s0123_write_enable = cru_fp16mul_s0123[0];  // S0-S3写入使能
wire cru_s0123_bank_sel    = cru_fp16mul_s0123[1];   // S0-S3 Bank选择

// cru_fp16mul_s4567 信号解析
wire cru_s4567_write_enable = cru_fp16mul_s4567[0];  // S4-S7写入使能
wire cru_s4567_bank_sel     = cru_fp16mul_s4567[1];  // S4-S7 Bank选择
wire [1:0] cru_s4567_reg_sel = cru_fp16mul_s4567[3:2]; // S4-S7寄存器选择 (00=S4, 01=S5, 10=S6, 11=S7)
// S0寄存器组写入
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s0_bank0_r <= 128'd0;
        s0_bank1_r <= 128'd0;
    end else if (cru_s0123_write_enable) begin
        if (cru_s0123_bank_sel) begin
            s0_bank1_r <= dvr_fp16mul_s0;
    end else begin
            s0_bank0_r <= dvr_fp16mul_s0;
        end
    end
end

// S1寄存器组写入
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_bank0_r <= 128'd0;
        s1_bank1_r <= 128'd0;
    end else if (cru_s0123_write_enable) begin
        if (cru_s0123_bank_sel) begin
            s1_bank1_r <= dvr_fp16mul_s1;
        end else begin
            s1_bank0_r <= dvr_fp16mul_s1;
        end
    end
end

// S2寄存器组写入
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s2_bank0_r <= 128'd0;
        s2_bank1_r <= 128'd0;
    end else if (cru_s0123_write_enable) begin
        if (cru_s0123_bank_sel) begin
            s2_bank1_r <= dvr_fp16mul_s2;
        end else begin
            s2_bank0_r <= dvr_fp16mul_s2;
        end
    end
end

// S3寄存器组写入
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s3_bank0_r <= 128'd0;
        s3_bank1_r <= 128'd0;
    end else if (cru_s0123_write_enable) begin
        if (cru_s0123_bank_sel) begin
            s3_bank1_r <= dvr_fp16mul_s3;
        end else begin
            s3_bank0_r <= dvr_fp16mul_s3;
        end
    end
end

//==============================================================================
// 源寄存器组B (S4-S7) 写入逻辑
//==============================================================================

// S4寄存器组写入
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s4_bank0_r <= 128'd0;
        s4_bank1_r <= 128'd0;
    end else if (cru_s4567_write_enable && (cru_s4567_reg_sel == 2'b00)) begin
        if (cru_s4567_bank_sel) begin
            s4_bank1_r <= dvr_fp16mul_s4567;
        end else begin
            s4_bank0_r <= dvr_fp16mul_s4567;
        end
    end
end

// S5寄存器组写入
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s5_bank0_r <= 128'd0;
        s5_bank1_r <= 128'd0;
    end else if (cru_s4567_write_enable && (cru_s4567_reg_sel == 2'b01)) begin
        if (cru_s4567_bank_sel) begin
            s5_bank1_r <= dvr_fp16mul_s4567;
        end else begin
            s5_bank0_r <= dvr_fp16mul_s4567;
        end
    end
end

// S6寄存器组写入
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s6_bank0_r <= 128'd0;
        s6_bank1_r <= 128'd0;
    end else if (cru_s4567_write_enable && (cru_s4567_reg_sel == 2'b10)) begin
        if (cru_s4567_bank_sel) begin
            s6_bank1_r <= dvr_fp16mul_s4567;
        end else begin
            s6_bank0_r <= dvr_fp16mul_s4567;
        end
    end
end

// S7寄存器组写入
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s7_bank0_r <= 128'd0;
        s7_bank1_r <= 128'd0;
    end else if (cru_s4567_write_enable && (cru_s4567_reg_sel == 2'b11)) begin
        if (cru_s4567_bank_sel) begin
            s7_bank1_r <= dvr_fp16mul_s4567;
        end else begin
            s7_bank0_r <= dvr_fp16mul_s4567;
        end
    end
end



// cru_fp16mul 信号解析
wire inst_valid = cru_fp16mul[0];
wire inst_bank_sel_a = cru_fp16mul[1];
wire inst_bank_sel_b = cru_fp16mul[2];

//==============================================================================
// 数据锁存逻辑
//==============================================================================
// 选择S0-S3数据
always @(*) begin
    if (inst_valid) begin
        if (inst_bank_sel_a) begin
            selected_s0_r = s0_bank1_r;
            selected_s1_r = s1_bank1_r;
            selected_s2_r = s2_bank1_r;
            selected_s3_r = s3_bank1_r;
        end else begin
            selected_s0_r = s0_bank0_r;
            selected_s1_r = s1_bank0_r;
            selected_s2_r = s2_bank0_r;
            selected_s3_r = s3_bank0_r;
        end
    end else begin
        selected_s0_r = 128'd0;
        selected_s1_r = 128'd0;
        selected_s2_r = 128'd0;
        selected_s3_r = 128'd0;
    end
end

// 选择S4-S7数据
always @(*) begin
    if (inst_valid) begin
        if (inst_bank_sel_b) begin
            selected_s4_r = s4_bank1_r;
            selected_s5_r = s5_bank1_r;
            selected_s6_r = s6_bank1_r;
            selected_s7_r = s7_bank1_r;
        end else begin
            selected_s4_r = s4_bank0_r;
            selected_s5_r = s5_bank0_r;
            selected_s6_r = s6_bank0_r;
            selected_s7_r = s7_bank0_r;
        end
    end else begin
        selected_s4_r = 128'd0;
        selected_s5_r = 128'd0;
        selected_s6_r = 128'd0;
        selected_s7_r = 128'd0;
    end
end

// 计算有效信号延迟
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        compute_valid_r <= 5'd0;
    end else begin
        compute_valid_r <= {compute_valid_r[3:0], inst_valid};
    end
end

//==============================================================================
// 数据重组逻辑 - 将nibble数据重组为FP16格式
//==============================================================================

genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : gen_fp16_data
        // 重组FP16_A: {S3[4*i+3:4*i], S2[4*i+3:4*i], S1[4*i+3:4*i], S0[4*i+3:4*i]}
        assign fp16_a[i] = {
            selected_s3_r[4*i+3:4*i],
            selected_s2_r[4*i+3:4*i], 
            selected_s1_r[4*i+3:4*i],
            selected_s0_r[4*i+3:4*i]
        };
        
        // 重组FP16_B: {S7[4*i+3:4*i], S6[4*i+3:4*i], S5[4*i+3:4*i], S4[4*i+3:4*i]}
        assign fp16_b[i] = {
            selected_s7_r[4*i+3:4*i],
            selected_s6_r[4*i+3:4*i],
            selected_s5_r[4*i+3:4*i], 
            selected_s4_r[4*i+3:4*i]
        };
    end
endgenerate

//==============================================================================
// 32个FP16乘法器实例化
//==============================================================================

generate

    for (i = 0; i < 32; i = i + 1) begin : gen_fp16_mul_units
        /*
        fp16_mul_unit u_fp16_mul_unit (
            .fp16_a(fp16_a[i]),
            .fp16_b(fp16_b[i]),
            .fp32_result(fp32_result[i])
        );
*/
    fp16tofp32_multiplier #(
        .IEEE_754(IEEE_754)
    ) u_fp16tofp32_multiplier (
        .clk(clk),
        .rst_n(rst_n),
        .valid_i(inst_valid),
        .rounding_mode(i_rounding_mode),  // Pass rounding mode to multiplier
        .a(fp16_a[i]),
        .b(fp16_b[i]),
        .valid_o(mul_valid_o[i]),         // Multiplier output valid signal
        .result(fp32_result[i]),
        .exception_flags(exception_flags_per_mul[i])  // Get exception flags from multiplier
    );
    
    // Output exception flags
    assign o_exception_flags[i] = exception_flags_per_mul[i];
    end
endgenerate

//==============================================================================
// 结果输出逻辑 - 将FP32结果分散到8个输出寄存器
//==============================================================================

// 结果输出寄存器更新
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dr_fp16mul_d0 <= 128'd0;
        dr_fp16mul_d1 <= 128'd0;
        dr_fp16mul_d2 <= 128'd0;
        dr_fp16mul_d3 <= 128'd0;
        dr_fp16mul_d4 <= 128'd0;
        dr_fp16mul_d5 <= 128'd0;
        dr_fp16mul_d6 <= 128'd0;
        dr_fp16mul_d7 <= 128'd0;
    end else if (compute_valid_r[3]) begin
        // 分散FP32结果到8个输出寄存器
        dr_fp16mul_d0 <= {
            fp32_result[31][3:0], fp32_result[30][3:0], fp32_result[29][3:0], fp32_result[28][3:0],
            fp32_result[27][3:0], fp32_result[26][3:0], fp32_result[25][3:0], fp32_result[24][3:0],
            fp32_result[23][3:0], fp32_result[22][3:0], fp32_result[21][3:0], fp32_result[20][3:0],
            fp32_result[19][3:0], fp32_result[18][3:0], fp32_result[17][3:0], fp32_result[16][3:0],
            fp32_result[15][3:0], fp32_result[14][3:0], fp32_result[13][3:0], fp32_result[12][3:0],
            fp32_result[11][3:0], fp32_result[10][3:0], fp32_result[9][3:0], fp32_result[8][3:0],
            fp32_result[7][3:0], fp32_result[6][3:0], fp32_result[5][3:0], fp32_result[4][3:0],
            fp32_result[3][3:0], fp32_result[2][3:0], fp32_result[1][3:0], fp32_result[0][3:0]
        };
        dr_fp16mul_d1 <= {
            fp32_result[31][7:4], fp32_result[30][7:4], fp32_result[29][7:4], fp32_result[28][7:4],
            fp32_result[27][7:4], fp32_result[26][7:4], fp32_result[25][7:4], fp32_result[24][7:4],
            fp32_result[23][7:4], fp32_result[22][7:4], fp32_result[21][7:4], fp32_result[20][7:4],
            fp32_result[19][7:4], fp32_result[18][7:4], fp32_result[17][7:4], fp32_result[16][7:4],
            fp32_result[15][7:4], fp32_result[14][7:4], fp32_result[13][7:4], fp32_result[12][7:4],
            fp32_result[11][7:4], fp32_result[10][7:4], fp32_result[9][7:4], fp32_result[8][7:4],
            fp32_result[7][7:4], fp32_result[6][7:4], fp32_result[5][7:4], fp32_result[4][7:4],
            fp32_result[3][7:4], fp32_result[2][7:4], fp32_result[1][7:4], fp32_result[0][7:4]
        };
        dr_fp16mul_d2 <= {
            fp32_result[31][11:8], fp32_result[30][11:8], fp32_result[29][11:8], fp32_result[28][11:8],
            fp32_result[27][11:8], fp32_result[26][11:8], fp32_result[25][11:8], fp32_result[24][11:8],
            fp32_result[23][11:8], fp32_result[22][11:8], fp32_result[21][11:8], fp32_result[20][11:8],
            fp32_result[19][11:8], fp32_result[18][11:8], fp32_result[17][11:8], fp32_result[16][11:8],
            fp32_result[15][11:8], fp32_result[14][11:8], fp32_result[13][11:8], fp32_result[12][11:8],
            fp32_result[11][11:8], fp32_result[10][11:8], fp32_result[9][11:8], fp32_result[8][11:8],
            fp32_result[7][11:8], fp32_result[6][11:8], fp32_result[5][11:8], fp32_result[4][11:8],
            fp32_result[3][11:8], fp32_result[2][11:8], fp32_result[1][11:8], fp32_result[0][11:8]
        };
        dr_fp16mul_d3 <= {
            fp32_result[31][15:12], fp32_result[30][15:12], fp32_result[29][15:12], fp32_result[28][15:12],
            fp32_result[27][15:12], fp32_result[26][15:12], fp32_result[25][15:12], fp32_result[24][15:12],
            fp32_result[23][15:12], fp32_result[22][15:12], fp32_result[21][15:12], fp32_result[20][15:12],
            fp32_result[19][15:12], fp32_result[18][15:12], fp32_result[17][15:12], fp32_result[16][15:12],
            fp32_result[15][15:12], fp32_result[14][15:12], fp32_result[13][15:12], fp32_result[12][15:12],
            fp32_result[11][15:12], fp32_result[10][15:12], fp32_result[9][15:12], fp32_result[8][15:12],
            fp32_result[7][15:12], fp32_result[6][15:12], fp32_result[5][15:12], fp32_result[4][15:12],
            fp32_result[3][15:12], fp32_result[2][15:12], fp32_result[1][15:12], fp32_result[0][15:12]
        };
        dr_fp16mul_d4 <= {
            fp32_result[31][19:16], fp32_result[30][19:16], fp32_result[29][19:16], fp32_result[28][19:16],
            fp32_result[27][19:16], fp32_result[26][19:16], fp32_result[25][19:16], fp32_result[24][19:16],
            fp32_result[23][19:16], fp32_result[22][19:16], fp32_result[21][19:16], fp32_result[20][19:16],
            fp32_result[19][19:16], fp32_result[18][19:16], fp32_result[17][19:16], fp32_result[16][19:16],
            fp32_result[15][19:16], fp32_result[14][19:16], fp32_result[13][19:16], fp32_result[12][19:16],
            fp32_result[11][19:16], fp32_result[10][19:16], fp32_result[9][19:16], fp32_result[8][19:16],
            fp32_result[7][19:16], fp32_result[6][19:16], fp32_result[5][19:16], fp32_result[4][19:16],
            fp32_result[3][19:16], fp32_result[2][19:16], fp32_result[1][19:16], fp32_result[0][19:16]
        };
        dr_fp16mul_d5 <= {
            fp32_result[31][23:20], fp32_result[30][23:20], fp32_result[29][23:20], fp32_result[28][23:20],
            fp32_result[27][23:20], fp32_result[26][23:20], fp32_result[25][23:20], fp32_result[24][23:20],
            fp32_result[23][23:20], fp32_result[22][23:20], fp32_result[21][23:20], fp32_result[20][23:20],
            fp32_result[19][23:20], fp32_result[18][23:20], fp32_result[17][23:20], fp32_result[16][23:20],
            fp32_result[15][23:20], fp32_result[14][23:20], fp32_result[13][23:20], fp32_result[12][23:20],
            fp32_result[11][23:20], fp32_result[10][23:20], fp32_result[9][23:20], fp32_result[8][23:20],
            fp32_result[7][23:20], fp32_result[6][23:20], fp32_result[5][23:20], fp32_result[4][23:20],
            fp32_result[3][23:20], fp32_result[2][23:20], fp32_result[1][23:20], fp32_result[0][23:20]
        };
        dr_fp16mul_d6 <= {
            fp32_result[31][27:24], fp32_result[30][27:24], fp32_result[29][27:24], fp32_result[28][27:24],
            fp32_result[27][27:24], fp32_result[26][27:24], fp32_result[25][27:24], fp32_result[24][27:24],
            fp32_result[23][27:24], fp32_result[22][27:24], fp32_result[21][27:24], fp32_result[20][27:24],
            fp32_result[19][27:24], fp32_result[18][27:24], fp32_result[17][27:24], fp32_result[16][27:24],
            fp32_result[15][27:24], fp32_result[14][27:24], fp32_result[13][27:24], fp32_result[12][27:24],
            fp32_result[11][27:24], fp32_result[10][27:24], fp32_result[9][27:24], fp32_result[8][27:24],
            fp32_result[7][27:24], fp32_result[6][27:24], fp32_result[5][27:24], fp32_result[4][27:24],
            fp32_result[3][27:24], fp32_result[2][27:24], fp32_result[1][27:24], fp32_result[0][27:24]
        };
        dr_fp16mul_d7 <= {
            fp32_result[31][31:28], fp32_result[30][31:28], fp32_result[29][31:28], fp32_result[28][31:28],
            fp32_result[27][31:28], fp32_result[26][31:28], fp32_result[25][31:28], fp32_result[24][31:28],
            fp32_result[23][31:28], fp32_result[22][31:28], fp32_result[21][31:28], fp32_result[20][31:28],
            fp32_result[19][31:28], fp32_result[18][31:28], fp32_result[17][31:28], fp32_result[16][31:28],
            fp32_result[15][31:28], fp32_result[14][31:28], fp32_result[13][31:28], fp32_result[12][31:28],
            fp32_result[11][31:28], fp32_result[10][31:28], fp32_result[9][31:28], fp32_result[8][31:28],
            fp32_result[7][31:28], fp32_result[6][31:28], fp32_result[5][31:28], fp32_result[4][31:28],
            fp32_result[3][31:28], fp32_result[2][31:28], fp32_result[1][31:28], fp32_result[0][31:28]
        };
    end
end

endmodule


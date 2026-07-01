`timescale 1ns / 1ps

module intadd (
    input         clk,
    input         rst_n,
    input  [127:0] src_reg0,
    input  [127:0] src_reg1,
    input  [127:0] src_reg2,
    input  [12:0]  cru_intadd, // 扩展为13位：支持bit 12的sub_en
    input  [4:0]   i_smc_id,
    output reg [127:0] dst_reg0,
    output reg [127:0] dst_reg1,
    output reg [127:0] st,          // 状态寄存器
    output reg [12:0]  o_cru_intadd
);
/*
    // 从 cru_intadd 解码各字段（位顺序已反转）
    wire        inst_valid   = cru_intadd[0];
    wire        sign_d       = cru_intadd[1];
    wire        sign_s2      = cru_intadd[2];
    wire        sign_s1      = cru_intadd[3];
    wire        sign_s0      = cru_intadd[4];
    wire [1:0]  precision_s2 = cru_intadd[6:5];
    wire [1:0]  precision_s1 = cru_intadd[8:7];
    wire [1:0]  precision_s0 = cru_intadd[10:9];
    wire        update_st    = cru_intadd[11];
*/

    wire        inst_valid   = cru_intadd[0];
    wire [1:0]  precision_s0 = cru_intadd[2:1];
    wire [1:0]  precision_s1 = cru_intadd[4:3];
    wire [1:0]  precision_s2 = cru_intadd[6:5];
    wire        sign_s0      = cru_intadd[7];
    wire        sign_s1      = cru_intadd[8];
    wire        sign_s2      = cru_intadd[9];
    wire        sign_d       = cru_intadd[10];
    wire        update_st    = cru_intadd[11];
    wire        sub_en       = cru_intadd[12];  // 减法使能：1=减法，0=加法
    
    // 模块输出（add8/add32 根据 sub_en 执行加法或减法）
    wire [127:0] add8_dst0, add8_dst1;
    wire [127:0] add32_dst, add32_st;

    // add8/add32 模块实例化（支持加法和减法）
    add8 add8_unit (
        .src0(src_reg0),
        .src1(src_reg1),
        .src2(src_reg2),
        .sign_s0(sign_s0),
        .sign_s1(sign_s1),
        .sign_s2(sign_s2),
        .i_sign_d(sign_d),
        .sub_en(sub_en),      // 传递减法使能信号
        .dst0(add8_dst0),
        .dst1(add8_dst1)
    );
    
    add32 add32_unit (
        .src0(src_reg0),
        .src1(src_reg1),
        .sign_s0(sign_s0),
        .sign_s1(sign_s1),
        .i_sign_d(sign_d),
        .sub_en(sub_en),      // 传递减法使能信号
        .dst(add32_dst),
        .st(add32_st)
    );

    // 状态寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= 128'd0;
        end else if (inst_valid && update_st) begin
            if (precision_s0 == 2'b11 && precision_s1 == 2'b11) begin
                st <= add32_st; // 32bit模式（add32根据sub_en执行加法或减法）
            end else begin
                st <= st;  // 其他模式
            end
        end
        // 当update_st为0或inst_valid为0时，保持st_reg的当前值
        else begin
            st <= st;
        end
    end

    //align st and dst_reg0 dst_reg1    -zhuzl 20251027
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dst_reg0    <= 128'd0;
            dst_reg1    <= 128'd0;
        end else if(inst_valid && precision_s0 == 2'b00 && precision_s1 == 2'b00 && precision_s2 == 2'b00) begin
            dst_reg0    <= add8_dst0;  // add8根据sub_en执行加法或减法
            dst_reg1    <= add8_dst1;
        end else if(inst_valid && precision_s0 == 2'b11 && precision_s1 == 2'b11) begin
            dst_reg0    <= add32_dst;  // add32根据sub_en执行加法或减法
            dst_reg1    <= 128'd0;
        end else begin
            dst_reg0    <= dst_reg0;
            dst_reg1    <= dst_reg1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_cru_intadd    <= 13'd0;
        end else begin
            o_cru_intadd    <= cru_intadd;
        end
    end



    // 数据输出选择
    // assign dst_reg0 = (inst_valid && precision_s0 == 2'b00 && precision_s1 == 2'b00 && precision_s2 == 2'b00)
    //                   ? add8_dst0 :
    //                   (inst_valid && precision_s0 == 2'b11 && precision_s1 == 2'b11)
    //                   ? add32_dst : 128'd0;

    // assign dst_reg1 = (inst_valid && precision_s0 == 2'b00 && precision_s1 == 2'b00 && precision_s2 == 2'b00)
    //                   ? add8_dst1 : 128'd0;

endmodule

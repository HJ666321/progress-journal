`timescale 1ns / 1ps
module add32 (
    // input          clk,
    // input          rst_n,
    input  [127:0] src0,
    input  [127:0] src1,
    input          sign_s0,
    input          sign_s1,
    input          i_sign_d,
    input          sub_en,      // 减法使能：1=减法，0=加法
    output [127:0] dst,
    output [127:0] st
);
    
    // 4 个 32 位 lane：i=0 为 src0/dst[31:0]，i=1 为 [63:32]，i=2 为 [95:64]，i=3 为 [127:96]
    // 波形查看时请确认 s0_signed/s1_signed/sum_signed_real 来自同一 instance（同一 i）
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin
            add32_comb u_add32_comb(
                .src0           (src0[32*i +: 32]),
                .src1           (src1[32*i +: 32]),
                .sign_s0        (sign_s0),
                .sign_s1        (sign_s1),
                .i_sign_d       (i_sign_d),
                .sub_en         (sub_en),
                .dst            (dst[32*i +: 32]),
                .st             (st[32*i +: 32])
            );
        end
    endgenerate

    /*    genvar i;
    // 组合产生每组的 result -> dst（dst 是 wire）
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_add32
            wire [31:0] a = src0[i*32 +: 32]; // i=0 -> lowest 32 bits
            wire [31:0] b = src1[i*32 +: 32];

            // 符号/无符号扩展（组合）
            wire [63:0] s0_ext = sign_s0 ? {{32{a[31]}}, a} : {32'b0, a};
            wire [63:0] s1_ext = sign_s1 ? {{32{b[31]}}, b} : {32'b0, b};

            // 有符号求和，用于溢出判定；低 32 位为基础结果
            wire signed [63:0] s0_signed = $signed(s0_ext);
            wire signed [63:0] s1_signed = $signed(s1_ext);
            wire signed [63:0] sum_signed = s0_signed + s1_signed;
            wire [31:0] sum_lo = sum_signed[31:0];

            // 溢出/饱和处理（只在任一输入被视为有符号时生效）
            wire [31:0] result = (sign_s0 || sign_s1) ?
                ( ((s0_signed[63] == s1_signed[63]) && (sum_signed[63] != s0_signed[63])) ? 32'h7FFFFFFF : sum_lo )
                : sum_lo;

            assign dst[i*32 +: 32] = result;
        end
    endgenerate*/

    // 为每组 32 位数据生成 3 位状态信号
    // reg [127:0] st_temp; // 使用reg类型确保所有位都有明确的驱动
    
    // // 为每组 32 位数据生成 3 位状态信号
    // always_comb begin
    //     // 先初始化所有位为0
    //     st_temp = 128'b0;
        
    //     // 为每组 32 位数据生成 3 位状态信号
    //     for (int j = 0; j < 4; j = j + 1) begin
    //         // 在always块内不能声明wire，直接使用表达式
    //         reg gt, eq, ls;
            
    //         if (sign_s0 || sign_s1) begin
    //             // 有符号比较
    //             gt = ($signed(src0[j*32 +: 32]) > $signed(src1[j*32 +: 32]));
    //             ls = ($signed(src0[j*32 +: 32]) < $signed(src1[j*32 +: 32]));
    //         end else begin
    //             // 无符号比较
    //             gt = (src0[j*32 +: 32] > src1[j*32 +: 32]);
    //             ls = (src0[j*32 +: 32] < src1[j*32 +: 32]);
    //         end
    //         eq = (src0[j*32 +: 32] == src1[j*32 +: 32]);
            
    //         // 赋值对应的 3 位状态
    //         st_temp[j*32 + 0] = ls;
    //         st_temp[j*32 + 1] = eq;
    //         st_temp[j*32 + 2] = gt;
    //     end
    // end
    
    // // 最终赋值给输出端口
    // assign st = st_temp;

endmodule

//=========================================================================//
// Project  : inttofp
// File     : inttofp.v
// Module   : inttofp
// Author   : cypher
// Modified : 2025-12-4  
// Version  : 0.28
//=========================================================================//
// Description:
// 整数转浮点类型转换模块，支持多种数据格式转换
//
// Features:
// - 支持16/32位整数到16/32位浮点转换
// - 支持有符号和无符号整数
// - 支持高低位选择
// - 支持SMC架构
//
//=========================================================================//

module inttofp  #(
    parameter SMC_ID = 0                // SMC ID for this module
)(
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire [4:0]  i_smc_id,
    input  wire [127:0] i_dvr_inttofp_s,
    input  wire [5:0]  i_cru_inttofp,
    output reg  [127:0] o_dr_inttofp_d,
    output reg  [5:0]  o_cru_inttofp_o
);

    //=========================================================================
    // 微指令字段解码
    //=========================================================================
    wire w_valid      = i_cru_inttofp[0];
    wire w_src_is_32b = i_cru_inttofp[1];
    wire w_dst_is_32b = i_cru_inttofp[2];
    wire w_src_signed = i_cru_inttofp[3];
    wire w_src_high   = i_cru_inttofp[4];
    wire w_dst_high   = i_cru_inttofp[5];

    //=========================================================================
    // 数据分段
    //=========================================================================
    wire [31:0] w_src32 [0:3];
    wire [15:0] w_src16 [0:7];

    assign w_src32[0] = i_dvr_inttofp_s[31:0];
    assign w_src32[1] = i_dvr_inttofp_s[63:32];
    assign w_src32[2] = i_dvr_inttofp_s[95:64];
    assign w_src32[3] = i_dvr_inttofp_s[127:96];

    assign w_src16[0] = i_dvr_inttofp_s[15:0];
    assign w_src16[1] = i_dvr_inttofp_s[31:16];
    assign w_src16[2] = i_dvr_inttofp_s[47:32];
    assign w_src16[3] = i_dvr_inttofp_s[63:48];
    assign w_src16[4] = i_dvr_inttofp_s[79:64];
    assign w_src16[5] = i_dvr_inttofp_s[95:80];
    assign w_src16[6] = i_dvr_inttofp_s[111:96];
    assign w_src16[7] = i_dvr_inttofp_s[127:112];

    //=========================================================================
    // 转换结果
    //=========================================================================
    wire [31:0] w_fp32    [0:3];  // 32→32
    wire [31:0] w_fp32_16 [0:3];  // 16→32
    wire [15:0] w_fp16    [0:7];  // 16→16

    //=========================================================================
    // 32→32转换实例
    //=========================================================================
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_fp32
            int2fp32 u_fp32 (
                .i_in       (w_src32[gi]),
                .i_is_signed(w_src_signed),
                .o_out      (w_fp32[gi])
            );
        end
    endgenerate

    //=========================================================================
    // 16→16转换实例
    //=========================================================================
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_fp16
            int2fp16 u_fp16 (
                .i_in       (w_src16[gi]),
                .i_is_signed(w_src_signed),
                .o_out      (w_fp16[gi])
            );
        end
    endgenerate

    //=========================================================================
    // 16→32转换实例
    //=========================================================================
    wire [31:0] w_ext32 [0:3];
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_ext32
            wire [15:0] w_lo = w_src16[gi*2];
            wire [15:0] w_hi = w_src16[gi*2+1];
            
            assign w_ext32[gi] = w_src_high ? 
                {{16{w_src_signed ? w_hi[15] : 1'b0}}, w_hi} :
                {{16{w_src_signed ? w_lo[15] : 1'b0}}, w_lo};
                
            int2fp32 u_ext (
                .i_in       (w_ext32[gi]),
                .i_is_signed(w_src_signed),
                .o_out      (w_fp32_16[gi])
            );
        end
    endgenerate

    //=========================================================================
    // 32→16转换实例（每个32位整数转换为一个16位浮点）
    //=========================================================================
    wire [15:0] w_fp16_from_32 [0:3];  // 4个32→16转换结果

    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_int32tofp16
            int32tofp16 u_int32tofp16 (
                .i_in       (w_src32[gi]),        // 完整的32位整数输入
                .i_is_signed(w_src_signed),
                .o_out      (w_fp16_from_32[gi])
            );
        end
    endgenerate

    //=========================================================================
    // 时序逻辑
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // 复位时：输出数据和CRU-O均置0
            o_dr_inttofp_d   <= 128'd0;
            o_cru_inttofp_o  <= 6'd0;
        end else begin
            //=========================================================================
            // CRU-INTtoFP-O传递逻辑
            //=========================================================================
            o_cru_inttofp_o <= i_cru_inttofp;

            //=========================================================================
            // 输出映射逻辑
            //=========================================================================
            if (w_valid) begin
                case ({w_src_is_32b, w_dst_is_32b})
                    2'b11: o_dr_inttofp_d <= {w_fp32[3], w_fp32[2], w_fp32[1], w_fp32[0]};        // 32→32
                    2'b00: o_dr_inttofp_d <= {w_fp16[7], w_fp16[6], w_fp16[5], w_fp16[4],         // 16→16
                                             w_fp16[3], w_fp16[2], w_fp16[1], w_fp16[0]};
                    2'b01: o_dr_inttofp_d <= {w_fp32_16[3], w_fp32_16[2], w_fp32_16[1], w_fp32_16[0]}; // 16→32
                    2'b10: begin                                                                  // 32→16
                        if (w_dst_high) begin
                            // w_dst_high=1: 输出到奇数位置 DR[2x+1] = DVR-INTtoFP-S[x]的FP16结果
                            // 位范围: [16*(2x+1)+15 : 16*(2x+1)] 对应 DR[2x+1]
                            // DR[7]:32位源[3]->FP16, DR[5]:32位源[2]->FP16, DR[3]:32位源[1]->FP16, DR[1]:32位源[0]->FP16
                            // 偶数位置保持原有数据不变
                            o_dr_inttofp_d <= {w_fp16_from_32[3], o_dr_inttofp_d[111:96], w_fp16_from_32[2], o_dr_inttofp_d[79:64],
                                               w_fp16_from_32[1], o_dr_inttofp_d[47:32], w_fp16_from_32[0], o_dr_inttofp_d[15:0]};
                        end else begin
                            // w_dst_high=0: 输出到偶数位置 DR[2x] = DVR-INTtoFP-S[x]的FP16结果
                            // 位范围: [16*(2x)+15 : 16*(2x)] 对应 DR[2x]
                            // DR[6]:32位源[3]->FP16, DR[4]:32位源[2]->FP16, DR[2]:32位源[1]->FP16, DR[0]:32位源[0]->FP16
                            // 奇数位置保持原有数据不变
                            o_dr_inttofp_d <= {o_dr_inttofp_d[127:112], w_fp16_from_32[3], o_dr_inttofp_d[95:80], w_fp16_from_32[2],
                                               o_dr_inttofp_d[63:48], w_fp16_from_32[1], o_dr_inttofp_d[31:16], w_fp16_from_32[0]};
                        end
                    end
                    default: o_dr_inttofp_d <= 128'hxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
                endcase
            end else begin
                // valid=0时，输出保持不变
                o_dr_inttofp_d <= o_dr_inttofp_d;
                // $display("[inttofp] valid=0，输出保持为：%h", o_dr_inttofp_d);  // 已禁用打印
            end
        end
    end

endmodule
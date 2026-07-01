//=========================================================================
// Project:     AIACC
// File:        smi_iq_iic.v
// Module:      smi_iq_iic
// Author:      zhuzhenglong
// Email:       zhuzhenglong@inchitech.com
// Created:     2026-1-7
// Modified:    2025-1-7
// Version:     v0.1
//=========================================================================

// Description:
// 

// Parameters:
// 

//=========================================================================
// Revision History:
// v0.1 - 2026-1-7  - Initial version
//
//=========================================================================
`timescale 1ns/1ps

module smi_iq_iic #(
    parameter  PARA_IQ_ID                = 1,
    parameter  EN_EMBED                  = 1,
    parameter  BIT_EMBED                 = 3,
    parameter  EMBED_MSB_BIT             = 10,
    parameter  EN_EMBED_END              = 1,
    parameter  BITS_EMBED_END            = 6,
    parameter  EMBED_END_MSB_BIT         = 10,
    parameter  EN_LOOPS                  = 1,
    parameter  BITS_LOOPS                = 10,
    parameter  LOOPS_MSB_BIT             = 10,
    parameter  EN_COND                   = 1,
    parameter  BITS_COND                 = 7,
    parameter  COND_MSB_BIT              = 10,
    parameter  EN_DLY                    = 1,
    parameter  BITS_DLY                  = 3,
    parameter  DLY_MSB_BIT               = 10,
    parameter  EN_INC                    = 1,
    parameter  BITS_INC                  = 4,
    parameter  INC_MSB_BIT               = 10,
    parameter  EN_INC_EMBED              = 1,
    parameter  BITS_INC_EMBED            = 6,
    parameter  INC_EMBED_MSB_BIT         = 10,
    parameter  MIN_HIGH                  = 10,
    parameter  MIN_LOW                   = 10,
    parameter  BIT_CODE                  = 10,
    parameter  EXTRA_ADDR                = 1,
    parameter  EXTRA_DATA                = 1,
    parameter  WR_INST_WIDTH             = 32,
    parameter  WR_ADDR_WIDTH             = 32,  
    parameter  WR_DATA_WIDTH             = 32,
    parameter  SMI_IQ_AMOUNT             = 32,
    parameter  RD_ADDR_WIDTH             = 5,    //$clog2(INSTQ_DEPTH)
    parameter  INSTQ_DEPTH               = 32, 
    parameter  RD_DATA_WIDTH             = WR_INST_WIDTH + WR_ADDR_WIDTH + WR_DATA_WIDTH,
    parameter  DLY_DATA_WIDTH            = (EXTRA_ADDR && EXTRA_DATA) ? (1+2+1+BITS_COND + BITS_DLY + WR_ADDR_WIDTH + WR_DATA_WIDTH + BIT_CODE) : 
                                            EXTRA_ADDR                ? (1+2+1+BITS_COND + BITS_DLY + WR_ADDR_WIDTH + BIT_CODE)                 : 
                                            EXTRA_DATA                ? (1+2+1+BITS_COND + BITS_DLY + WR_DATA_WIDTH + BIT_CODE)                 : (1+2+1+BITS_COND + BITS_DLY + BIT_CODE),
    parameter  DLY_BIT_CODE              = (EXTRA_ADDR && EXTRA_DATA) ? (WR_ADDR_WIDTH + WR_DATA_WIDTH + BIT_CODE) :
                                            EXTRA_ADDR                ? (WR_ADDR_WIDTH + BIT_CODE)                 :
                                            EXTRA_DATA                ? (WR_DATA_WIDTH + BIT_CODE)                 : BIT_CODE,
    parameter  MICRO_ADDR_WIDTH          = 2
)(
    input                                clk,
    input                                rst_n,

    //instruction
    input        [SMI_IQ_AMOUNT-1:0]     inst_rdy_in,
    input        [31:0]                  inst_jump_in,

    //data from iq memory
    input                                rdi_start,
    input        [1:0]                   rdi_iqsid,
    output reg                           rdi_addr_valid,
    output reg   [RD_ADDR_WIDTH-1:0]     rdi_addr,
    input                                rdi_data_valid,
    input        [RD_DATA_WIDTH-1:0]     rdi_data,

    //write instruction amount every iqsid
    input        [7:0]                   inst_amount_siq0,
    input        [7:0]                   inst_amount_siq1,
    input        [7:0]                   inst_amount_siq2,
    input        [7:0]                   inst_amount_siq3,

    //to dly module
    output reg                           dly_data_valid,
    output reg   [DLY_DATA_WIDTH-1:0]    dly_data,
    input                                dly_queen_full,

    output       [7:0]                   error_iic,
    output                               jump_last,
    output                               jump_flag,
    output       [7:0]                   jump_len
);

parameter  INST_JUMP_MSB_BIT       = 7;
parameter  INST_JUMP_WIDTH         = 8;

localparam  IDLE                   = 8'b00000001;
localparam  FETCH_DECODE           = 8'b00000010;
localparam  LOOP_PARA_SET          = 8'b00000100;
localparam  EMBED_LOOP_CYCLE       = 8'b00001000;
localparam  JUMP_ADDR              = 8'b00010000;
localparam  LOOP_CYCLE             = 8'b00100000;
localparam  EXE_EMBED0_INST        = 8'b01000000;
localparam  EXE_ARRAY_INST         = 8'b10000000;

reg  [7:0]                          r_current_state;
reg  [7:0]                          r_next_state;
reg  [7:0]                          r_state;
reg  [BITS_LOOPS-1:0]               r_embed_lev0_loop;
reg  [BITS_LOOPS-1:0]               r_embed_lev1_loop;
reg  [BITS_LOOPS-1:0]               r_embed_lev2_loop;
reg  [BITS_LOOPS-1:0]               r_embed_lev3_loop;
reg  [BITS_LOOPS-1:0]               r_embed_lev4_loop;
reg  [BITS_LOOPS-1:0]               r_embed_lev5_loop;
reg  [BITS_LOOPS-1:0]               r_embed_lev6_loop;
reg  [BITS_LOOPS-1:0]               r_embed_lev0_cnt;
reg  [BITS_LOOPS-1:0]               r_embed_lev1_cnt;
reg  [BITS_LOOPS-1:0]               r_embed_lev2_cnt;
reg  [BITS_LOOPS-1:0]               r_embed_lev3_cnt;
reg  [BITS_LOOPS-1:0]               r_embed_lev4_cnt;
reg  [BITS_LOOPS-1:0]               r_embed_lev5_cnt;
reg  [BITS_LOOPS-1:0]               r_embed_lev6_cnt;
reg  [MIN_HIGH-MIN_LOW:0]           r_min_base_addr;    //min address
reg  [BITS_INC-1:0]                 r_inc;
reg  [BITS_COND-1:0]                r_cond;
reg  [BITS_DLY-1:0]                 r_dly;
reg  [BITS_INC_EMBED-1:0]           r_inc_embed;
reg  [BITS_EMBED_END-1:0]           r_embed_end;
reg  [BITS_EMBED_END-1:0]           r_embed_end_prev;
reg  [7:0]                          r_jump_code;
reg  [7:0]                          r_inst_siq_cnt;
reg  [BITS_LOOPS-1:0]               r_loops_cnt;
reg  [BITS_INC-1:0]                 r_inc_lev1;
reg  [BITS_INC-1:0]                 r_inc_lev2;
reg  [BITS_INC-1:0]                 r_inc_lev3;
reg  [BITS_INC-1:0]                 r_inc_lev4;
reg  [BITS_INC-1:0]                 r_inc_lev5;
reg  [BITS_INC-1:0]                 r_inc_lev6;

wire                                w_siq0_jump_overflow;
wire                                w_siq1_jump_overflow;
wire                                w_siq2_jump_overflow;
wire                                w_siq3_jump_overflow;
wire                                w_siq0_jump_underflow;
wire                                w_siq1_jump_underflow;
wire                                w_siq2_jump_underflow;
wire                                w_siq3_jump_underflow;
wire [BIT_CODE-1:0]                 w_code;
wire [INST_JUMP_WIDTH-1:0]          w_jump_comp;              //Two's Complement
wire [INST_JUMP_WIDTH-2:0]          w_jump_minus_comp;
wire [BITS_INC-1:0]                 w_inc_comp;               //Two's Complement
wire [BITS_INC-1:0]                 w_inc_minus_comp;
wire [MIN_HIGH-MIN_LOW:0]           w_min_base_addr;
wire [BITS_INC-1:0]                 w_inc;
wire [BIT_EMBED-1:0]                w_embed;
wire                                w_jump;
wire [7:0]                          w_jump_code;
wire                                w_valid;
wire [BITS_LOOPS-1:0]               w_loops;
wire [BITS_COND-1:0]                w_cond;
wire [BITS_DLY-1:0]                 w_dly;
wire [BITS_LOOPS-1:0]               w_embed_lev_loop;
wire                                w_jump_symbol;            //jump compare symbol
wire [1:0]                          w_jump_judge;
wire [31:0]                         w_jump_compare_val;
wire                                w_jump_last;
wire [BITS_INC_EMBED-1:0]           w_inc_embed;
wire [DLY_BIT_CODE-1:0]             w_new_code_tmp;
wire [DLY_BIT_CODE-1:0]             w_new_code_tmp_iq_normal;
wire [DLY_BIT_CODE-1:0]             w_new_code_tmp_iq_eq_2;
wire [DLY_BIT_CODE-1:0]             w_new_code;
wire [DLY_BIT_CODE-1:0]             w_specical_new_code;
wire                                w_siq_is_empty;
wire                                w_relate_cond_smc;
wire [MICRO_ADDR_WIDTH-1:0]         w_operate_micro_addr;    //SMC operate's micro instruction address
wire [BIT_CODE-1:0]                 w_operate_micro;         //SMC operate's micro instruction
wire [BITS_EMBED_END-1:0]           w_embed_end;
wire [MICRO_ADDR_WIDTH-1:0]         w_lev0_addr_offset;
wire [MICRO_ADDR_WIDTH-1:0]         w_lev1_addr_offset;
wire [MICRO_ADDR_WIDTH-1:0]         w_lev2_addr_offset;
wire [MICRO_ADDR_WIDTH-1:0]         w_lev3_addr_offset;
wire [MICRO_ADDR_WIDTH-1:0]         w_lev4_addr_offset;
wire [MICRO_ADDR_WIDTH-1:0]         w_lev5_addr_offset;
wire [MICRO_ADDR_WIDTH-1:0]         w_lev6_addr_offset;

wire [RD_DATA_WIDTH-1:0]            w_rdi_data_sel;
reg                                 r_exe_array_inst_flag;
reg  [RD_DATA_WIDTH-1:0]            r_array_embed0_data;
reg  [RD_DATA_WIDTH-1:0]            r_embed0_inst [0:INSTQ_DEPTH-1];
reg  [RD_ADDR_WIDTH-1:0]            r_wr_embed0_inst_cnt;
reg  [RD_ADDR_WIDTH-1:0]            r_rd_embed0_inst_cnt;

assign w_rdi_data_sel                     = r_exe_array_inst_flag ? r_array_embed0_data : rdi_data;

assign w_code                             = w_rdi_data_sel[(DLY_BIT_CODE-1) -: BIT_CODE];
// assign w_jump_minus_comp                  = ~w_rdi_data_sel[INST_JUMP_MSB_BIT-1 : 0] + 7'd1;
assign w_jump_minus_comp                  = ~w_rdi_data_sel[(WR_DATA_WIDTH + WR_ADDR_WIDTH + 6) -: 7] + 7'd1;
// assign w_jump_comp                        = w_rdi_data_sel[INST_JUMP_MSB_BIT] ? {1'b1, w_jump_minus_comp} :
//                                                                            w_jump_code;
assign w_jump_comp                        = w_rdi_data_sel[WR_DATA_WIDTH + WR_ADDR_WIDTH + 7] ? {1'b1, w_jump_minus_comp} :
                                                                                           w_jump_code;
assign w_inc_minus_comp                   = ~w_rdi_data_sel[INC_MSB_BIT-1 -: BITS_INC-1] + 'd1;
assign w_inc_comp                         = w_rdi_data_sel[INC_MSB_BIT] ? {1'b1, w_inc_minus_comp[BITS_INC-2:0]} :
                                                                     w_inc;
assign w_min_base_addr                    = w_rdi_data_sel[MIN_HIGH:MIN_LOW];
assign w_inc                              = w_rdi_data_sel[INC_MSB_BIT -: BITS_INC];
assign w_embed                            = w_rdi_data_sel[EMBED_MSB_BIT -: BIT_EMBED];
assign w_jump                             = w_rdi_data_sel[RD_DATA_WIDTH - 2];
assign w_valid                            = w_rdi_data_sel[RD_DATA_WIDTH - 1];
assign w_loops                            = w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
assign w_cond                             = w_rdi_data_sel[COND_MSB_BIT -: BITS_COND];
assign w_dly                              = w_rdi_data_sel[DLY_MSB_BIT -: BITS_DLY] & {BITS_DLY{(EN_DLY==1)}} & {BITS_DLY{w_valid}};
assign w_jump_code                        = w_rdi_data_sel[(WR_DATA_WIDTH + WR_ADDR_WIDTH + 7) -: INST_JUMP_WIDTH];
assign w_embed_end                        = w_rdi_data_sel[EMBED_END_MSB_BIT -: BITS_EMBED_END];
assign w_inc_embed                        = w_rdi_data_sel[INC_EMBED_MSB_BIT -: BITS_INC_EMBED];
assign w_jump_symbol                      = w_rdi_data_sel[42 + WR_ADDR_WIDTH + WR_DATA_WIDTH];
assign w_jump_judge                       = w_rdi_data_sel[(41 + WR_ADDR_WIDTH + WR_DATA_WIDTH) -: 2];
assign w_jump_compare_val                 = w_rdi_data_sel[(39 + WR_ADDR_WIDTH + WR_DATA_WIDTH) -: 32];
assign w_embed_lev_loop                   = w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
assign w_jump_last                        = (w_jump_judge == 2'b11);
assign w_lev0_addr_offset                 = EN_INC ? w_inc * r_embed_lev0_cnt : {MICRO_ADDR_WIDTH{1'b0}};
assign w_lev1_addr_offset                 = (r_inc_embed[0] && EN_INC) ? r_inc_lev1 * r_embed_lev1_cnt : {MICRO_ADDR_WIDTH{1'b0}};
assign w_lev2_addr_offset                 = (r_inc_embed[1] && EN_INC) ? r_inc_lev2 * r_embed_lev2_cnt : {MICRO_ADDR_WIDTH{1'b0}};
assign w_lev3_addr_offset                 = (r_inc_embed[2] && EN_INC) ? r_inc_lev3 * r_embed_lev3_cnt : {MICRO_ADDR_WIDTH{1'b0}};
assign w_lev4_addr_offset                 = (r_inc_embed[3] && EN_INC) ? r_inc_lev4 * r_embed_lev4_cnt : {MICRO_ADDR_WIDTH{1'b0}};
assign w_lev5_addr_offset                 = (r_inc_embed[4] && EN_INC) ? r_inc_lev5 * r_embed_lev5_cnt : {MICRO_ADDR_WIDTH{1'b0}};
assign w_lev6_addr_offset                 = (r_inc_embed[5] && EN_INC) ? r_inc_lev6 * r_embed_lev6_cnt : {MICRO_ADDR_WIDTH{1'b0}};
assign w_operate_micro_addr               = w_min_base_addr +  w_lev0_addr_offset + 
                                                              (w_lev1_addr_offset & {MICRO_ADDR_WIDTH{~EN_EMBED_END[0] | ~r_embed_end_prev[0]}}) +
                                                              (w_lev2_addr_offset & {MICRO_ADDR_WIDTH{~EN_EMBED_END[0] | ~r_embed_end_prev[1]}}) +
                                                              (w_lev3_addr_offset & {MICRO_ADDR_WIDTH{~EN_EMBED_END[0] | ~r_embed_end_prev[2]}}) +
                                                              (w_lev4_addr_offset & {MICRO_ADDR_WIDTH{~EN_EMBED_END[0] | ~r_embed_end_prev[3]}}) +
                                                              (w_lev5_addr_offset & {MICRO_ADDR_WIDTH{~EN_EMBED_END[0] | ~r_embed_end_prev[4]}}) +
                                                              (w_lev6_addr_offset & {MICRO_ADDR_WIDTH{~EN_EMBED_END[0] | ~r_embed_end_prev[5]}});

assign w_operate_micro                    = ((PARA_IQ_ID == 14) || (PARA_IQ_ID == 15) || (PARA_IQ_ID == 16) || (PARA_IQ_ID == 17)) ? {w_operate_micro_addr[7:0],  w_rdi_data_sel[3:0]}  :                                   //ur read bank {ur-raddr[7:0], ur-rbank[2:0], ur-re[0]}
                                            ((PARA_IQ_ID == 18) || (PARA_IQ_ID == 19) || (PARA_IQ_ID == 20) || (PARA_IQ_ID == 21)) ? {w_rdi_data_sel[(BIT_CODE-1) -: 16], w_operate_micro_addr[7:0],  w_rdi_data_sel[3:0]}  :     //ur write bank0 {ur-wbe-0[15:0], ur-waddr-0[7:0], ur-wbank-0[2:0], ur-we-0[0]}
                                            ((PARA_IQ_ID == 22))                                                                   ? {w_rdi_data_sel[(BIT_CODE-1) -: 77], w_operate_micro_addr[39:0], w_rdi_data_sel[18:0]} :     //STB {vld[0], smc_strb[5:0], byte_strb[3:0], brst[3:0], gr_base_addr[39:0], smc_id[4:0], ur_id[2:0], ur_addr[7:0]}
                                            ((PARA_IQ_ID == 23))                                                                   ? {w_rdi_data_sel[(BIT_CODE-1) -: 83], w_operate_micro_addr[39:0], w_rdi_data_sel[18:0]} :     //LDB {vld[0], smc_strb[5:0], byte_strb[3:0], brst[3:0], gr_base_addr[39:0], smc_id[4:0], ur_id[2:0], ur_addr[7:0]}
                                             (PARA_IQ_ID == 2)                                                                     ? {w_rdi_data_sel[BIT_CODE-1],         w_operate_micro_addr[2:0],  w_rdi_data_sel[4:0]}  :
                                                                                                                                      w_rdi_data_sel[(BIT_CODE-1)  : 0 ];
assign w_siq_is_empty                     = ((r_inst_siq_cnt >= inst_amount_siq0) && (rdi_iqsid == 2'b00)) ||
                                            ((r_inst_siq_cnt >= inst_amount_siq1) && (rdi_iqsid == 2'b01)) ||
                                            ((r_inst_siq_cnt >= inst_amount_siq2) && (rdi_iqsid == 2'b10)) ||
                                            ((r_inst_siq_cnt >= inst_amount_siq3) && (rdi_iqsid == 2'b11));         //maybe overflow
assign w_siq0_jump_overflow               = (rdi_iqsid == 2'b00) && (r_inst_siq_cnt >= inst_amount_siq0) && (~r_inst_siq_cnt[7]);
assign w_siq1_jump_overflow               = (rdi_iqsid == 2'b01) && (r_inst_siq_cnt >= inst_amount_siq1) && (~r_inst_siq_cnt[7]);
assign w_siq2_jump_overflow               = (rdi_iqsid == 2'b10) && (r_inst_siq_cnt >= inst_amount_siq2) && (~r_inst_siq_cnt[7]);
assign w_siq3_jump_overflow               = (rdi_iqsid == 2'b11) && (r_inst_siq_cnt >= inst_amount_siq3) && (~r_inst_siq_cnt[7]);
assign w_siq0_jump_underflow              = (rdi_iqsid == 2'b00) && (r_inst_siq_cnt >= inst_amount_siq0) && (r_inst_siq_cnt[7]);
assign w_siq1_jump_underflow              = (rdi_iqsid == 2'b01) && (r_inst_siq_cnt >= inst_amount_siq1) && (r_inst_siq_cnt[7]);
assign w_siq2_jump_underflow              = (rdi_iqsid == 2'b10) && (r_inst_siq_cnt >= inst_amount_siq2) && (r_inst_siq_cnt[7]);
assign w_siq3_jump_underflow              = (rdi_iqsid == 2'b11) && (r_inst_siq_cnt >= inst_amount_siq3) && (r_inst_siq_cnt[7]);
assign w_relate_cond_smc                  = inst_rdy_in[w_cond];
assign error_iic                          = {w_siq3_jump_underflow, w_siq2_jump_underflow, w_siq1_jump_underflow, w_siq0_jump_underflow,
                                             w_siq3_jump_overflow,  w_siq2_jump_overflow,  w_siq1_jump_overflow,  w_siq0_jump_overflow};
assign jump_last                          = w_jump_last & rdi_data_valid;                                                   //jump to last flag
assign jump_flag                          = (r_current_state == FETCH_DECODE) && rdi_data_valid && w_jump && w_valid;       //willing jump flag
assign jump_len                           = r_jump_code;

//SMC micro instruction valid is LSB
generate
    if(EXTRA_DATA && EXTRA_ADDR) begin
        assign w_new_code_tmp             = {w_operate_micro, w_rdi_data_sel[RD_DATA_WIDTH-1 -: (WR_DATA_WIDTH+WR_ADDR_WIDTH)]};
        assign w_new_code_tmp_iq_normal   = {w_new_code_tmp[(DLY_BIT_CODE-1)-:(BIT_CODE-1)], w_new_code_tmp[DLY_BIT_CODE-BIT_CODE] & w_valid, w_new_code_tmp[DLY_BIT_CODE-BIT_CODE-1:0]};  
        // assign w_new_code_tmp_iq_eq_2     = {w_new_code_tmp[(DLY_BIT_CODE-1)-:3], w_new_code_tmp[DLY_BIT_CODE-4] & w_valid, w_new_code_tmp[DLY_BIT_CODE-5], w_new_code_tmp[DLY_BIT_CODE-6] & w_valid, w_new_code_tmp[(DLY_BIT_CODE-7)-:2], w_new_code_tmp[DLY_BIT_CODE-9] & w_valid, w_new_code_tmp[(WR_DATA_WIDTH+WR_ADDR_WIDTH-1):0]};    //valid is LSB
        assign w_specical_new_code        = {w_code[(DLY_BIT_CODE-1)-:(BIT_CODE-1)], w_code[DLY_BIT_CODE-BIT_CODE] & w_valid, w_code[DLY_BIT_CODE-BIT_CODE-1:0]};
    end else if(EXTRA_DATA) begin
        assign w_new_code_tmp             = {w_operate_micro, w_rdi_data_sel[RD_DATA_WIDTH-1 -: WR_DATA_WIDTH]};
        assign w_new_code_tmp_iq_normal   = {w_new_code_tmp[(DLY_BIT_CODE-1)-:(BIT_CODE-1)], w_new_code_tmp[DLY_BIT_CODE-BIT_CODE] & w_valid, w_new_code_tmp[DLY_BIT_CODE-BIT_CODE-1:0]};  
        // assign w_new_code_tmp_iq_eq_2     = {w_new_code_tmp[(DLY_BIT_CODE-1)-:3], w_new_code_tmp[DLY_BIT_CODE-4] & w_valid, w_new_code_tmp[DLY_BIT_CODE-5], w_new_code_tmp[DLY_BIT_CODE-6] & w_valid, w_new_code_tmp[(DLY_BIT_CODE-7)-:2], w_new_code_tmp[DLY_BIT_CODE-9] & w_valid, w_new_code_tmp[(WR_DATA_WIDTH-1):0]};    //valid is LSB
        assign w_specical_new_code        = {w_code[(DLY_BIT_CODE-1)-:(BIT_CODE-1)], w_code[DLY_BIT_CODE-BIT_CODE] & w_valid, w_code[DLY_BIT_CODE-BIT_CODE-1:0]};
    end else if(EXTRA_ADDR) begin
        assign w_new_code_tmp             = {w_operate_micro, w_rdi_data_sel[RD_DATA_WIDTH-1 -: WR_ADDR_WIDTH]};
        assign w_new_code_tmp_iq_normal   = {w_new_code_tmp[(DLY_BIT_CODE-1)-:(BIT_CODE-1)], w_new_code_tmp[DLY_BIT_CODE-BIT_CODE] & w_valid, w_new_code_tmp[DLY_BIT_CODE-BIT_CODE-1:0]};
        // assign w_new_code_tmp_iq_eq_2     = {w_new_code_tmp[(DLY_BIT_CODE-1)-:3], w_new_code_tmp[DLY_BIT_CODE-4] & w_valid, w_new_code_tmp[DLY_BIT_CODE-5], w_new_code_tmp[DLY_BIT_CODE-6] & w_valid, w_new_code_tmp[(DLY_BIT_CODE-7)-:2], w_new_code_tmp[DLY_BIT_CODE-9] & w_valid, w_new_code_tmp[(WR_ADDR_WIDTH-1):0]};    //valid is LSB
        assign w_specical_new_code        = {w_code[(DLY_BIT_CODE-1)-:(BIT_CODE-1)], w_code[DLY_BIT_CODE-BIT_CODE] & w_valid, w_code[DLY_BIT_CODE-BIT_CODE-1:0]};
    end else begin
        assign w_new_code_tmp             = w_operate_micro;
        assign w_new_code_tmp_iq_normal   = {w_new_code_tmp[DLY_BIT_CODE-1:1], w_new_code_tmp[0] & w_valid};                    //valid is LSB
        // assign w_new_code_tmp_iq_eq_2     = {w_new_code_tmp[(DLY_BIT_CODE-1)-:3], w_new_code_tmp[DLY_BIT_CODE-4] & w_valid, w_new_code_tmp[DLY_BIT_CODE-5], w_new_code_tmp[DLY_BIT_CODE-6] & w_valid, w_new_code_tmp[(DLY_BIT_CODE-7)-:2], w_new_code_tmp[DLY_BIT_CODE-9] & w_valid};    //valid is LSB
        assign w_specical_new_code        = {w_code[DLY_BIT_CODE-1:1], w_code[0] & w_valid};
    end
    
    // assign w_new_code                     = (PARA_IQ_ID == 2) ? w_new_code_tmp_iq_eq_2 : w_new_code_tmp_iq_normal;
    assign w_new_code                     = w_new_code_tmp_iq_normal;
endgenerate

//get jump value
always @(*) begin
    r_jump_code                                      = 8'd0;

    if(w_jump_symbol) begin    //signed number
        case(w_jump_judge)
            2'b00: begin
                if($signed(inst_jump_in) > $signed(w_jump_compare_val)) begin
                    r_jump_code                      = w_jump_comp;
                end else begin
                    r_jump_code                      = 8'd1;
                end
            end

            2'b01: begin
                if($signed(inst_jump_in) == $signed(w_jump_compare_val)) begin
                    r_jump_code                      = w_jump_comp;
                end else begin
                    r_jump_code                      = 8'd1;
                end
            end

            2'b10: begin
                if($signed(inst_jump_in) < $signed(w_jump_compare_val)) begin
                    r_jump_code                      = w_jump_comp;
                end else begin
                    r_jump_code                      = 8'd1;
                end
            end

            default: begin
                r_jump_code                          = 8'd0;
            end
        endcase
    end else begin    //unsigned number
        case(w_jump_judge)
            2'b00: begin
                if(inst_jump_in > w_jump_compare_val) begin
                    r_jump_code                      = w_jump_comp;
                end else begin
                    r_jump_code                      = 8'd1;
                end
            end

            2'b01: begin
                if(inst_jump_in == w_jump_compare_val) begin
                    r_jump_code                      = w_jump_comp;
                end else begin
                    r_jump_code                      = 8'd1;
                end
            end

            2'b10: begin
                if(inst_jump_in < w_jump_compare_val) begin
                    r_jump_code                      = w_jump_comp;
                end else begin
                    r_jump_code                      = 8'd1;
                end
            end

            default: begin
                r_jump_code                          = 8'd0;
            end
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        r_current_state                              <= 7'd0;
    end else begin
        r_current_state                              <= r_next_state;
    end
end

always @(*) begin
    r_next_state                                     = r_current_state;

    case(r_current_state)
        IDLE: begin
            if(rdi_start) begin
                r_next_state                         = FETCH_DECODE;
            end
        end

        FETCH_DECODE: begin
            if(rdi_data_valid) begin
                //check whether it is nested in a loop
                // if(EN_EMBED && (w_embed <= 6)) begin
                if(EN_EMBED && ~(&w_embed)) begin
                    if(~(|w_embed)) begin
                        if(~(|w_embed_lev_loop)) begin    //w_embed_lev_loop=0
                            if(|w_embed_end) begin
                                if(((r_embed_lev1_cnt == r_embed_lev1_loop) || (r_embed_end_prev[0] && EN_EMBED_END)) &&
                                  ((r_embed_lev2_cnt == r_embed_lev2_loop) || (r_embed_end_prev[1] && EN_EMBED_END)) &&
                                  ((r_embed_lev3_cnt == r_embed_lev3_loop) || (r_embed_end_prev[2] && EN_EMBED_END)) &&
                                  ((r_embed_lev4_cnt == r_embed_lev4_loop) || (r_embed_end_prev[3] && EN_EMBED_END)) &&
                                  ((r_embed_lev5_cnt == r_embed_lev5_loop) || (r_embed_end_prev[4] && EN_EMBED_END)) &&
                                  ((r_embed_lev6_cnt == r_embed_lev6_loop) || (r_embed_end_prev[5] && EN_EMBED_END))) begin                 //loop
                                    if(w_siq_is_empty) begin
                                        r_next_state                      = IDLE;
                                    end else begin
                                        r_next_state                      = FETCH_DECODE;
                                    end
                                end else begin                 //loop=0
                                    r_next_state                      = EXE_ARRAY_INST;
                                end
                            end else begin
                                r_next_state                 = FETCH_DECODE;
                            end
                        end else begin    //w_embed_lev_loop!=0
                            r_next_state                     = EXE_EMBED0_INST;
                        end
                    end else begin
                        r_next_state                         = LOOP_PARA_SET;
                    end

                //check whether it is jump
                end else if(w_jump && w_valid) begin                   //JUMP && VALID
                    if(EN_COND) begin
                        if(w_relate_cond_smc) begin                     //other SMC-IQ is ready
                            if(w_jump_last || w_siq_is_empty) begin    //memory tail || w_siq_is_empty==1
                                r_next_state         = IDLE;
                            end
                        end else begin
                            r_next_state             = JUMP_ADDR;
                        end
                    end else begin
                        if(w_jump_last || w_siq_is_empty) begin        //memory tail || w_siq_is_empty==1
                            r_next_state             = IDLE;
                        end
                    end

                //check whether it is loop
                end else if(EN_LOOPS && w_loops >= 'd1) begin
                    if(~dly_queen_full) begin
                        r_next_state                 = LOOP_CYCLE;
                    end
                //normal instruction
                end else begin
                    if(w_siq_is_empty) begin
                        r_next_state                 = IDLE;
                    end
                end
            end
        end

        EXE_EMBED0_INST: begin    //execute continue embed=0 instruction
            if((r_embed_lev0_cnt == w_embed_lev_loop) && EN_LOOPS && ~dly_queen_full) begin
                if(|w_embed_end) begin
                    if(((r_embed_lev1_cnt == r_embed_lev1_loop) || (r_embed_end_prev[0] && EN_EMBED_END)) &&
                      ((r_embed_lev2_cnt == r_embed_lev2_loop) || (r_embed_end_prev[1] && EN_EMBED_END)) &&
                      ((r_embed_lev3_cnt == r_embed_lev3_loop) || (r_embed_end_prev[2] && EN_EMBED_END)) &&
                      ((r_embed_lev4_cnt == r_embed_lev4_loop) || (r_embed_end_prev[3] && EN_EMBED_END)) &&
                      ((r_embed_lev5_cnt == r_embed_lev5_loop) || (r_embed_end_prev[4] && EN_EMBED_END)) &&
                      ((r_embed_lev6_cnt == r_embed_lev6_loop) || (r_embed_end_prev[5] && EN_EMBED_END))) begin
                        if(w_siq_is_empty) begin
                            r_next_state                = IDLE;
                        end else begin
                            r_next_state                = FETCH_DECODE;
                        end
                    end else begin
                        r_next_state                    = EXE_ARRAY_INST;
                    end
                end else begin
                    if(w_siq_is_empty) begin
                        r_next_state                    = IDLE;
                    end else begin
                        r_next_state                    = FETCH_DECODE;
                    end
                end
            end
        end

        LOOP_PARA_SET: begin
            if(rdi_data_valid && ~(|w_embed) && ~dly_queen_full) begin        //w_embed == 0
                if(~(|w_embed)) begin
                    if(~(|w_embed_lev_loop)) begin    //w_embed_lev_loop=0
                        if(|w_embed_end) begin
                            if(((r_embed_lev1_cnt == r_embed_lev1_loop) || (r_embed_end_prev[0] && EN_EMBED_END)) &&
                              ((r_embed_lev2_cnt == r_embed_lev2_loop) || (r_embed_end_prev[1] && EN_EMBED_END)) &&
                              ((r_embed_lev3_cnt == r_embed_lev3_loop) || (r_embed_end_prev[2] && EN_EMBED_END)) &&
                              ((r_embed_lev4_cnt == r_embed_lev4_loop) || (r_embed_end_prev[3] && EN_EMBED_END)) &&
                              ((r_embed_lev5_cnt == r_embed_lev5_loop) || (r_embed_end_prev[4] && EN_EMBED_END)) &&
                              ((r_embed_lev6_cnt == r_embed_lev6_loop) || (r_embed_end_prev[5] && EN_EMBED_END))) begin
                                if(w_siq_is_empty) begin
                                    r_next_state                  = IDLE;
                                end else begin
                                    r_next_state                  = FETCH_DECODE;
                                end
                            end else begin
                                r_next_state                      = EXE_ARRAY_INST;
                            end
                        end else begin
                            r_next_state                 = FETCH_DECODE;
                        end
                    end else begin    //w_embed_lev_loop!=0
                        r_next_state                     = EXE_EMBED0_INST;
                    end
                end
            end
        end

        EXE_ARRAY_INST: begin
            if((r_embed_lev0_cnt == w_embed_lev_loop) && ((r_rd_embed0_inst_cnt+1) == r_wr_embed0_inst_cnt)) begin
                if(((r_embed_lev1_cnt == r_embed_lev1_loop) || (r_embed_end_prev[0] && EN_EMBED_END)) &&
                  ((r_embed_lev2_cnt == r_embed_lev2_loop) || (r_embed_end_prev[1] && EN_EMBED_END)) &&
                  ((r_embed_lev3_cnt == r_embed_lev3_loop) || (r_embed_end_prev[2] && EN_EMBED_END)) &&
                  ((r_embed_lev4_cnt == r_embed_lev4_loop) || (r_embed_end_prev[3] && EN_EMBED_END)) &&
                  ((r_embed_lev5_cnt == r_embed_lev5_loop) || (r_embed_end_prev[4] && EN_EMBED_END)) &&
                  ((r_embed_lev6_cnt == r_embed_lev6_loop) || (r_embed_end_prev[5] && EN_EMBED_END))) begin
                    //check whether is the last data
                    if(w_siq_is_empty) begin    
                        r_next_state                  = IDLE;
                    end else begin
                        r_next_state                  = FETCH_DECODE;
                    end
                end
            end
        end

        JUMP_ADDR: begin
            if(w_relate_cond_smc) begin                                //other SMC-IQ is ready
                if(w_jump_last || w_siq_is_empty) begin
                    r_next_state                     = IDLE;
                end else begin
                    r_next_state                     = FETCH_DECODE;
                end
            end
        end

        LOOP_CYCLE: begin
            if(~dly_queen_full) begin
                if(r_loops_cnt == w_loops) begin
                    r_next_state                     = FETCH_DECODE;
    
                    if(w_siq_is_empty) begin
                        r_next_state                 = IDLE;
                    end else begin
                        r_next_state                 = FETCH_DECODE;
                    end
                end
            end
        end

        default: begin
            r_next_state                             = IDLE;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rdi_addr_valid                               <= 1'b0;
        rdi_addr                                     <= {RD_ADDR_WIDTH{1'b0}};
        r_inst_siq_cnt                               <= 8'd0;
        r_embed_lev0_loop                            <= {BITS_LOOPS{1'b0}};
        r_embed_lev1_loop                            <= {BITS_LOOPS{1'b0}};
        r_embed_lev2_loop                            <= {BITS_LOOPS{1'b0}};
        r_embed_lev3_loop                            <= {BITS_LOOPS{1'b0}};
        r_embed_lev4_loop                            <= {BITS_LOOPS{1'b0}};
        r_embed_lev5_loop                            <= {BITS_LOOPS{1'b0}};
        r_embed_lev6_loop                            <= {BITS_LOOPS{1'b0}};
        r_embed_lev0_cnt                             <= {BITS_LOOPS{1'b0}};
        r_embed_lev1_cnt                             <= {BITS_LOOPS{1'b0}};
        r_embed_lev2_cnt                             <= {BITS_LOOPS{1'b0}};
        r_embed_lev3_cnt                             <= {BITS_LOOPS{1'b0}};
        r_embed_lev4_cnt                             <= {BITS_LOOPS{1'b0}};
        r_embed_lev5_cnt                             <= {BITS_LOOPS{1'b0}};
        r_embed_lev6_cnt                             <= {BITS_LOOPS{1'b0}};
        r_inc                                        <= {BITS_INC{1'b0}};
        r_inc_lev1                                   <= {BITS_INC{1'b0}};
        r_inc_lev2                                   <= {BITS_INC{1'b0}};
        r_inc_lev3                                   <= {BITS_INC{1'b0}};
        r_inc_lev4                                   <= {BITS_INC{1'b0}};
        r_inc_lev5                                   <= {BITS_INC{1'b0}};
        r_inc_lev6                                   <= {BITS_INC{1'b0}};
        dly_data_valid                               <= 1'b0;
        r_loops_cnt                                  <= {BITS_LOOPS{1'b0}};
        r_embed_end                                  <= {BITS_EMBED_END{1'b0}};
        r_embed_end_prev                             <= {BITS_EMBED_END{1'b0}};
        r_current_state                              <= IDLE;
        r_wr_embed0_inst_cnt                         <= {RD_ADDR_WIDTH{1'b0}};
        r_rd_embed0_inst_cnt                         <= {RD_ADDR_WIDTH{1'b0}};
        r_exe_array_inst_flag                        <= 1'b0;
    end else begin
        case (r_current_state)
            IDLE: begin
                dly_data_valid                      <= 1'b0;

                if(rdi_start) begin
                    rdi_addr_valid                   <= 1'b1;
                    rdi_addr                         <= {RD_ADDR_WIDTH{1'b0}};
                    r_inst_siq_cnt                   <= 8'd0;
                    dly_data_valid                   <= 1'b0;
                    // r_state                          <= FETCH_DECODE;
                end
            end
    
            FETCH_DECODE: begin
                r_dly                                <= w_dly;
                r_min_base_addr                      <= {(MIN_HIGH-MIN_LOW+1){1'b1}};
                
                if(rdi_data_valid) begin
                    //check whether it is nested in a loop
                    // if(EN_EMBED && (w_embed <= 6)) begin
                    if(EN_EMBED && ~(&w_embed)) begin
                        dly_data_valid               <= 1'b0;
                        rdi_addr_valid               <= 1'b1;
                        rdi_addr                     <= rdi_addr + 'd1;
                        r_inst_siq_cnt               <= r_inst_siq_cnt + 8'd1;
                        //detect the level of the nested loop
                        case(w_embed)
                            3'd0: begin                                    //level 0
                                r_embed_lev0_loop    <= w_embed_lev_loop;
                                r_inc                <= w_inc_comp;
                                r_cond               <= w_cond;
                                rdi_addr_valid       <= 1'b0;
                                rdi_addr             <= rdi_addr;
                                r_inst_siq_cnt       <= r_inst_siq_cnt;

                                // r_min_base_addr      <= w_min_base_addr & {(MIN_HIGH-MIN_LOW+1){(EN_INC==1)}};
                                r_min_base_addr      <= w_min_base_addr;
                                if(|w_embed_end) begin
                                    r_embed_end          <= w_embed_end;
                                    r_embed_end_prev     <= r_embed_end;
                                end
                                r_inc_embed          <= w_inc_embed;
                                // rdi_addr_valid       <= 1'b0;

                                if(~dly_queen_full) begin
                                    dly_data_valid       <= 1'b1;
    
                                    if((r_wr_embed0_inst_cnt == 'd0) && (r_embed_lev0_cnt == 'd0)) begin
                                        dly_data             <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, r_cond, w_dly, w_new_code};
                                    end else begin
                                        dly_data             <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, r_cond, {BITS_DLY{1'b0}}, w_new_code};
                                    end
    
                                    if(~(|w_embed_lev_loop)) begin      //w_embed_lev_loop=0
                                        if(|w_embed_end) begin
                                            if(((r_embed_lev1_cnt == r_embed_lev1_loop) || (r_embed_end_prev[0] && EN_EMBED_END)) &&
                                              ((r_embed_lev2_cnt == r_embed_lev2_loop) || (r_embed_end_prev[1] && EN_EMBED_END)) &&
                                              ((r_embed_lev3_cnt == r_embed_lev3_loop) || (r_embed_end_prev[2] && EN_EMBED_END)) &&
                                              ((r_embed_lev4_cnt == r_embed_lev4_loop) || (r_embed_end_prev[3] && EN_EMBED_END)) &&
                                              ((r_embed_lev5_cnt == r_embed_lev5_loop) || (r_embed_end_prev[4] && EN_EMBED_END)) &&
                                              ((r_embed_lev6_cnt == r_embed_lev6_loop) || (r_embed_end_prev[5] && EN_EMBED_END))) begin
                                                r_rd_embed0_inst_cnt              <= 'd0;
                                                r_wr_embed0_inst_cnt              <= 'd0;
                                                r_exe_array_inst_flag             <= 1'b0;
                                                // dly_data_valid                    <= 1'b0;
                                            end else begin
                                                if(|r_wr_embed0_inst_cnt) begin
                                                    r_array_embed0_data           <= r_embed0_inst[0];
                                                end else begin
                                                    r_array_embed0_data           <= w_rdi_data_sel;
                                                end
                                                
                                                r_rd_embed0_inst_cnt          <= 'd0;

                                                if(~(|w_embed_lev_loop)) begin
                                                    if((r_embed_lev1_loop == 'd0) || (r_embed_end_prev[0] && EN_EMBED_END)) begin
                                                        if((r_embed_lev2_loop == 'd0) || (r_embed_end_prev[1] && EN_EMBED_END)) begin
                                                            if((r_embed_lev3_loop == 'd0) || (r_embed_end_prev[2] && EN_EMBED_END)) begin
                                                                if((r_embed_lev4_loop == 'd0) || (r_embed_end_prev[3] && EN_EMBED_END)) begin
                                                                    if((r_embed_lev5_loop == 'd0) || (r_embed_end_prev[4] && EN_EMBED_END)) begin
                                                                        if((r_embed_lev6_loop == 'd0) || (r_embed_end_prev[5] && EN_EMBED_END)) begin
                                                                            r_embed_lev6_cnt        <= r_embed_lev6_cnt;
                                                                        end else begin
                                                                            r_embed_lev6_cnt        <= r_embed_lev6_cnt + 'd1;
                                                                        end
                                                                    end else begin
                                                                        r_embed_lev5_cnt            <= r_embed_lev5_cnt + 'd1;
                                                                    end
                                                                end else begin
                                                                    r_embed_lev4_cnt                <= r_embed_lev4_cnt + 'd1;
                                                                end
                                                            end else begin
                                                                r_embed_lev3_cnt                    <= r_embed_lev3_cnt + 'd1;
                                                            end
                                                        end else begin
                                                            r_embed_lev2_cnt                        <= r_embed_lev2_cnt + 'd1;
                                                        end
                                                    end else begin
                                                        r_embed_lev1_cnt                            <= r_embed_lev1_cnt + 'd1;
                                                    end
                                                end

                                                r_exe_array_inst_flag             <= 1'b1;
                                            end
                                        end else begin
                                            rdi_addr_valid               <= 1'b1;
                                            rdi_addr                     <= rdi_addr + 'd1;
                                            r_inst_siq_cnt               <= r_inst_siq_cnt + 8'd1;
                                        end
    
                                        r_embed_lev0_cnt                 <= {BITS_LOOPS{1'b0}};
                                    end else begin
                                        r_embed_lev0_cnt                 <= r_embed_lev0_cnt + 'd1;
                                    end
    
                                    r_embed0_inst[r_wr_embed0_inst_cnt]               <= w_rdi_data_sel;
                                    r_wr_embed0_inst_cnt                              <= r_wr_embed0_inst_cnt + 'd1;
                                end

                            end
                            3'd1: begin                                    //level 1
                                r_inc_lev1           <= w_inc_comp;
                                r_embed_lev1_loop    <= w_embed_lev_loop;
                                r_embed_end          <= {r_embed_end[(BITS_EMBED_END-1)-:5], 1'b0};
                            end
                            3'd2: begin                                    //level 2
                                r_inc_lev2           <= w_inc_comp;
                                r_embed_lev2_loop    <= w_embed_lev_loop;
                                r_embed_end          <= {r_embed_end[(BITS_EMBED_END-1)-:4], 1'b0, r_embed_end[0]};
                            end
                            3'd3: begin                                    //level 3
                                r_inc_lev3           <= w_inc_comp;
                                r_embed_lev3_loop    <= w_embed_lev_loop;
                                r_embed_end          <= {r_embed_end[(BITS_EMBED_END-1)-:3], 1'b0, r_embed_end[1:0]};
                            end
                            3'd4: begin                                    //level 4
                                r_inc_lev4           <= w_inc_comp;
                                r_embed_lev4_loop    <= w_embed_lev_loop;
                                r_embed_end          <= {r_embed_end[(BITS_EMBED_END-1)-:2], 1'b0, r_embed_end[2:0]};
                            end
                            3'd5: begin                                    //level 5
                                r_inc_lev5           <= w_inc_comp;
                                r_embed_lev5_loop    <= w_embed_lev_loop;
                                r_embed_end          <= {r_embed_end[BITS_EMBED_END-1], 1'b0, r_embed_end[3:0]};
                            end
                            3'd6: begin                                    //level 6
                                r_inc_lev6           <= w_inc_comp;
                                r_embed_lev6_loop    <= w_embed_lev_loop;
                                r_embed_end          <= {1'b0, r_embed_end[4:0]};
                            end
                        endcase

                    //check whether it is jump
                    end else if(w_jump && w_valid) begin                   //JUMP && VALID
                        dly_data_valid               <= 1'b0;

                        if(EN_COND) begin
                            if(w_relate_cond_smc) begin                    //other SMC-IQ is ready
                                if(w_jump_last || w_siq_is_empty) begin    //memory tail || w_siq_is_empty==1
                                    rdi_addr_valid   <= 1'b0;
                                    // r_state          <= IDLE;
                                end else begin
                                    rdi_addr_valid   <= 1'b1;
                                    rdi_addr         <= rdi_addr + r_jump_code;
                                    r_inst_siq_cnt   <= r_inst_siq_cnt + r_jump_code;
                                end
                            end else begin                                 //still need wait
                                // r_state              <= JUMP_ADDR;
                            end
                        end else begin
                            if(w_jump_last || w_siq_is_empty) begin        //memory tail || w_siq_is_empty==1
                                rdi_addr_valid       <= 1'b0;
                                // r_state              <= IDLE;
                            end else begin
                                rdi_addr_valid       <= 1'b1;
                                rdi_addr             <= rdi_addr + r_jump_code;
                                r_inst_siq_cnt       <= r_inst_siq_cnt + r_jump_code;
                            end
                        end
                    //check whether it is loop
                    end else if(EN_LOOPS && w_loops >= 'd1) begin
                        if(dly_queen_full) begin
                            rdi_addr_valid           <= 1'b0;
                            dly_data_valid           <= 1'b0;
                        end else begin
                            r_loops_cnt              <= r_loops_cnt + 'd1;
                            r_inst_siq_cnt           <= r_inst_siq_cnt + 'd1;
                            rdi_addr_valid           <= 1'b0;
                            dly_data_valid           <= 1'b1;
                            dly_data                 <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, w_cond, w_dly, w_new_code};
                            // r_state                  <= LOOP_CYCLE;
                        end
                    //normal instruction
                    end else begin    
                        if(~w_siq_is_empty) begin
                            if(dly_queen_full) begin
                                rdi_addr_valid       <= 1'b0;
                                dly_data_valid       <= 1'b0;
                            end else begin
                                rdi_addr_valid       <= 1'b1;
                                rdi_addr             <= rdi_addr + 'd1;
                                r_inst_siq_cnt       <= r_inst_siq_cnt + 8'd1;
                                dly_data_valid       <= 1'b1;
                                //when MIC-IQ vld = 0, then set SMC operater vld =0
                                //when MIC-IQ vld = 1, then keep SMC operater vld state
                                dly_data             <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, w_cond, w_dly, w_new_code};
                            end
                        end else begin
                            rdi_addr_valid           <= 1'b0;
                            dly_data_valid           <= 1'b1;
                            dly_data                 <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, w_cond, w_dly, w_new_code};
                            // r_state                  <= IDLE;
                        end
                    end
                end else begin
                    dly_data_valid                   <= 1'b0;
                    rdi_addr_valid                   <= 1'b0;
                end
            end

            EXE_EMBED0_INST: begin    //execute continue embed=0 instruction
                if((r_embed_lev0_cnt == w_embed_lev_loop) && EN_LOOPS) begin
                    if(~dly_queen_full) begin
                        r_embed_lev0_cnt             <= 'd0;
                        dly_data_valid               <= 1'b1;
                        dly_data                     <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, r_cond, {BITS_DLY{1'b0}}, w_new_code};

                        if(w_embed_end == 6'd0) begin
                            rdi_addr_valid           <= 1'b1;
                            rdi_addr                 <= rdi_addr + 'd1;
                            r_inst_siq_cnt           <= r_inst_siq_cnt + 8'd1;
                        end else begin
                            //r_wr_embed0_inst_cnt=0
                            if(((r_embed_lev1_cnt == r_embed_lev1_loop) || (r_embed_end_prev[0] && EN_EMBED_END)) &&
                              ((r_embed_lev2_cnt == r_embed_lev2_loop) || (r_embed_end_prev[1] && EN_EMBED_END)) &&
                              ((r_embed_lev3_cnt == r_embed_lev3_loop) || (r_embed_end_prev[2] && EN_EMBED_END)) &&
                              ((r_embed_lev4_cnt == r_embed_lev4_loop) || (r_embed_end_prev[3] && EN_EMBED_END)) &&
                              ((r_embed_lev5_cnt == r_embed_lev5_loop) || (r_embed_end_prev[4] && EN_EMBED_END)) &&
                              ((r_embed_lev6_cnt == r_embed_lev6_loop) || (r_embed_end_prev[5] && EN_EMBED_END))) begin
                                r_rd_embed0_inst_cnt           <= 'd0;
                                r_wr_embed0_inst_cnt           <= 'd0;
                                r_exe_array_inst_flag          <= 1'b0;
                                // dly_data_valid                 <= 1'b0;
                            end else begin
                                r_rd_embed0_inst_cnt           <= 'd0;
                                r_array_embed0_data            <= r_embed0_inst[0];

                                if((r_embed_lev1_loop == 'd0) || (r_embed_end_prev[0] && EN_EMBED_END)) begin
                                    if((r_embed_lev2_loop == 'd0) || (r_embed_end_prev[1] && EN_EMBED_END)) begin
                                        if((r_embed_lev3_loop == 'd0) || (r_embed_end_prev[2] && EN_EMBED_END)) begin
                                            if((r_embed_lev4_loop == 'd0) || (r_embed_end_prev[3] && EN_EMBED_END)) begin
                                                if((r_embed_lev5_loop == 'd0) || (r_embed_end_prev[4] && EN_EMBED_END)) begin
                                                    if((r_embed_lev6_loop == 'd0) || (r_embed_end_prev[5] && EN_EMBED_END)) begin
                                                        r_embed_lev6_cnt        <= r_embed_lev6_cnt;
                                                    end else begin
                                                        r_embed_lev6_cnt        <= r_embed_lev6_cnt + 'd1;
                                                    end
                                                end else begin
                                                    r_embed_lev5_cnt            <= r_embed_lev5_cnt + 'd1;
                                                end
                                            end else begin
                                                r_embed_lev4_cnt                <= r_embed_lev4_cnt + 'd1;
                                            end
                                        end else begin
                                            r_embed_lev3_cnt                    <= r_embed_lev3_cnt + 'd1;
                                        end
                                    end else begin
                                        r_embed_lev2_cnt                        <= r_embed_lev2_cnt + 'd1;
                                    end
                                end else begin
                                    r_embed_lev1_cnt                            <= r_embed_lev1_cnt + 'd1;
                                end

                                r_exe_array_inst_flag          <= 1'b1;
                            end
                        end
                    end
                end else if(EN_LOOPS)begin
                    if(~dly_queen_full) begin
                        r_embed_lev0_cnt             <= r_embed_lev0_cnt + 'd1;
                        dly_data_valid               <= 1'b1;
                        dly_data                     <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, r_cond, {BITS_DLY{1'b0}}, w_new_code};
                    end
                end
            end
    
            LOOP_PARA_SET: begin
                dly_data_valid                       <= 1'b0;
                r_min_base_addr                      <= {(MIN_HIGH-MIN_LOW+1){1'b1}};

                if(rdi_data_valid) begin
                    if(|w_embed) begin
                        rdi_addr_valid                   <= 1'b1;
                        rdi_addr                         <= rdi_addr + 'd1;
                        r_inst_siq_cnt                   <= r_inst_siq_cnt + 8'd1;
                    end else begin
                        rdi_addr_valid                   <= 1'b0;
                    end

                    //detect the level of the nested loop
                    case(w_embed)
                        3'd0: begin                                        //level 0
                            r_embed_lev0_loop        <= w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
                            r_inc                    <= w_inc_comp;
                            // r_min_base_addr          <= w_min_base_addr & {(MIN_HIGH-MIN_LOW+1){(EN_INC==1)}};
                            r_min_base_addr          <= w_min_base_addr;
                            r_cond                   <= w_cond;
                            r_dly                    <= w_dly;
                            // r_embed_lev0_cnt         <= {BITS_LOOPS{1'b0}};
                            r_embed_lev1_cnt         <= {BITS_LOOPS{1'b0}};
                            r_embed_lev2_cnt         <= {BITS_LOOPS{1'b0}};
                            r_embed_lev3_cnt         <= {BITS_LOOPS{1'b0}};
                            r_embed_lev4_cnt         <= {BITS_LOOPS{1'b0}};
                            r_embed_lev5_cnt         <= {BITS_LOOPS{1'b0}};
                            r_embed_lev6_cnt         <= {BITS_LOOPS{1'b0}};
                            if(|w_embed_end) begin
                                r_embed_end              <= w_embed_end;
                                r_embed_end_prev         <= r_embed_end;
                            end
                            r_inc_embed              <= w_inc_embed;
                            rdi_addr_valid           <= 1'b0;

                            if(~dly_queen_full) begin
                                dly_data_valid       <= 1'b1;

                                if((r_wr_embed0_inst_cnt == 'd0) && (r_embed_lev0_cnt == 'd0)) begin
                                    dly_data             <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, r_cond, w_dly, w_new_code};
                                end else begin
                                    dly_data             <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, r_cond, {BITS_DLY{1'b0}}, w_new_code};
                                end

                                if(~(|w_embed_lev_loop)) begin      //w_embed_lev_loop=0
                                    if(|w_embed_end) begin
                                        if(((r_embed_lev1_cnt == r_embed_lev1_loop) || (r_embed_end_prev[0] && EN_EMBED_END)) &&
                                          ((r_embed_lev2_cnt == r_embed_lev2_loop) || (r_embed_end_prev[1] && EN_EMBED_END)) &&
                                          ((r_embed_lev3_cnt == r_embed_lev3_loop) || (r_embed_end_prev[2] && EN_EMBED_END)) &&
                                          ((r_embed_lev4_cnt == r_embed_lev4_loop) || (r_embed_end_prev[3] && EN_EMBED_END)) &&
                                          ((r_embed_lev5_cnt == r_embed_lev5_loop) || (r_embed_end_prev[4] && EN_EMBED_END)) &&
                                          ((r_embed_lev6_cnt == r_embed_lev6_loop) || (r_embed_end_prev[5] && EN_EMBED_END))) begin
                                            r_rd_embed0_inst_cnt              <= 'd0;
                                            r_wr_embed0_inst_cnt              <= 'd0;
                                            r_exe_array_inst_flag             <= 1'b0;
                                            // dly_data_valid                    <= 1'b0;
                                        end else begin
                                            if(|r_wr_embed0_inst_cnt) begin
                                                r_array_embed0_data           <= r_embed0_inst[0];
                                            end else begin
                                                r_array_embed0_data           <= w_rdi_data_sel;
                                            end
                                            
                                            r_rd_embed0_inst_cnt          <= 'd0;

                                            if(~(|w_embed_lev_loop)) begin
                                                if((r_embed_lev1_loop == 'd0) || (r_embed_end_prev[0] && EN_EMBED_END)) begin
                                                    if((r_embed_lev2_loop == 'd0) || (r_embed_end_prev[1] && EN_EMBED_END)) begin
                                                        if((r_embed_lev3_loop == 'd0) || (r_embed_end_prev[2] && EN_EMBED_END)) begin
                                                            if((r_embed_lev4_loop == 'd0) || (r_embed_end_prev[3] && EN_EMBED_END)) begin
                                                                if((r_embed_lev5_loop == 'd0) || (r_embed_end_prev[4] && EN_EMBED_END)) begin
                                                                    if((r_embed_lev6_loop == 'd0) || (r_embed_end_prev[5] && EN_EMBED_END)) begin
                                                                        r_embed_lev6_cnt        <= r_embed_lev6_cnt;
                                                                    end else begin
                                                                        r_embed_lev6_cnt        <= r_embed_lev6_cnt + 'd1;
                                                                    end
                                                                end else begin
                                                                    r_embed_lev5_cnt            <= r_embed_lev5_cnt + 'd1;
                                                                end
                                                            end else begin
                                                                r_embed_lev4_cnt                <= r_embed_lev4_cnt + 'd1;
                                                            end
                                                        end else begin
                                                            r_embed_lev3_cnt                    <= r_embed_lev3_cnt + 'd1;
                                                        end
                                                    end else begin
                                                        r_embed_lev2_cnt                        <= r_embed_lev2_cnt + 'd1;
                                                    end
                                                end else begin
                                                    r_embed_lev1_cnt                            <= r_embed_lev1_cnt + 'd1;
                                                end
                                            end

                                            r_exe_array_inst_flag             <= 1'b1;
                                        end
                                    end else begin
                                        rdi_addr_valid               <= 1'b1;
                                        rdi_addr                     <= rdi_addr + 'd1;
                                        r_inst_siq_cnt               <= r_inst_siq_cnt + 8'd1;
                                    end

                                    r_embed_lev0_cnt                 <= {BITS_LOOPS{1'b0}};
                                end else begin
                                    r_embed_lev0_cnt                 <= r_embed_lev0_cnt + 'd1;
                                end

                                r_embed0_inst[r_wr_embed0_inst_cnt]               <= w_rdi_data_sel;
                                r_wr_embed0_inst_cnt                              <= r_wr_embed0_inst_cnt + 'd1;

                            end
                        end
                        3'd1: begin                                        //level 1
                            r_inc_lev1               <= w_inc_comp;
                            r_embed_lev1_loop        <= w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
                            r_embed_end              <= {r_embed_end[(BITS_EMBED_END-1)-:5], 1'b0};    //when set loop, then disable the correspond embed_end
                        end
                        3'd2: begin                                       //level 2
                            r_inc_lev2               <= w_inc_comp;
                            r_embed_lev2_loop        <= w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
                            r_embed_end              <= {r_embed_end[(BITS_EMBED_END-1)-:4], 1'b0, r_embed_end[0]};
                        end
                        3'd3: begin                                       //level 3
                            r_inc_lev3               <= w_inc_comp;
                            r_embed_lev3_loop        <= w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
                            r_embed_end              <= {r_embed_end[(BITS_EMBED_END-1)-:3], 1'b0, r_embed_end[1:0]};
                        end
                        3'd4: begin                                        //level 4
                            r_inc_lev4               <= w_inc_comp;
                            r_embed_lev4_loop        <= w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
                            r_embed_end              <= {r_embed_end[(BITS_EMBED_END-1)-:2], 1'b0, r_embed_end[2:0]};
                        end
                        3'd5: begin                                        //level 5
                            r_inc_lev5               <= w_inc_comp;
                            r_embed_lev5_loop        <= w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
                            r_embed_end              <= {r_embed_end[(BITS_EMBED_END-1)-1], 1'b0, r_embed_end[3:0]};
                        end
                        3'd6: begin                                        //level 6
                            r_inc_lev6               <= w_inc_comp;
                            r_embed_lev6_loop        <= w_rdi_data_sel[LOOPS_MSB_BIT -: BITS_LOOPS];
                            r_embed_end              <= {1'b0, r_embed_end[4:0]};
                        end
                    endcase
                end
            end

            EXE_ARRAY_INST: begin
                if(~dly_queen_full) begin
                    dly_data_valid                                           <= 1'b1;
                    dly_data                                                 <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, r_cond, {BITS_DLY{1'b0}}, w_new_code};
                    r_embed_lev0_cnt                                         <= r_embed_lev0_cnt + 'd1;
                    
                    if(r_embed_lev0_cnt == w_embed_lev_loop) begin
                        r_embed_lev0_cnt                                     <= 'd0;

                        if(((r_rd_embed0_inst_cnt+1) == r_wr_embed0_inst_cnt) || (r_wr_embed0_inst_cnt == 'd1)) begin
                            r_rd_embed0_inst_cnt                             <= 'd0;
                            r_array_embed0_data                              <= r_embed0_inst[0];

                            r_embed_lev1_cnt                                 <= r_embed_lev1_cnt + 'd1;

                            if((r_embed_lev1_cnt == r_embed_lev1_loop) || (r_embed_end_prev[0] && EN_EMBED_END)) begin
                                r_embed_lev1_cnt                                 <= 'd0;
                                r_embed_lev2_cnt                                 <= r_embed_lev2_cnt + 'd1;
        
                                if((r_embed_lev2_cnt == r_embed_lev2_loop) || (r_embed_end_prev[1] && EN_EMBED_END)) begin
                                    r_embed_lev2_cnt                             <= 'd0;
                                    r_embed_lev3_cnt                             <= r_embed_lev3_cnt + 'd1;
        
                                    if((r_embed_lev3_cnt == r_embed_lev3_loop) || (r_embed_end_prev[2] && EN_EMBED_END)) begin
                                        r_embed_lev3_cnt                         <= 'd0;
                                        r_embed_lev4_cnt                         <= r_embed_lev4_cnt + 'd1;
        
                                        if((r_embed_lev4_cnt == r_embed_lev4_loop) || (r_embed_end_prev[3] && EN_EMBED_END)) begin
                                            r_embed_lev4_cnt                     <= 'd0;
                                            r_embed_lev5_cnt                     <= r_embed_lev5_cnt + 'd1;
        
                                            if((r_embed_lev5_cnt == r_embed_lev5_loop) || (r_embed_end_prev[4] && EN_EMBED_END)) begin
                                                r_embed_lev5_cnt                 <= 'd0;
                                                r_embed_lev6_cnt                 <= r_embed_lev6_cnt + 'd1;
        
                                                if((r_embed_lev6_cnt == r_embed_lev6_loop) || (r_embed_end_prev[5] && EN_EMBED_END)) begin
                                                    r_embed_lev6_cnt             <= 'd0;
                                                    
                                                    r_exe_array_inst_flag                          <= 1'b0;
                                                    r_rd_embed0_inst_cnt                           <= 6'd0;
                                                    r_wr_embed0_inst_cnt                           <= 6'd0;
                                                    // dly_data_valid                                 <= 1'b0;
        
                                                    //check whether is the last data
                                                    if(w_siq_is_empty) begin    
                                                        rdi_addr_valid           <= 1'b0;
                                                        // r_state                  <= IDLE;
                                                    end else begin
                                                        rdi_addr_valid           <= 1'b1;
                                                        rdi_addr                 <= rdi_addr + 'd1;
                                                        r_inst_siq_cnt           <= r_inst_siq_cnt + 8'd1;
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end else begin
                            r_rd_embed0_inst_cnt                             <= r_rd_embed0_inst_cnt + 'd1;
                            r_array_embed0_data                              <= r_embed0_inst[r_rd_embed0_inst_cnt + 'd1];
                        end
                    end
                end
            end

            JUMP_ADDR: begin                                               //do not send jump data to SMC
                if(w_relate_cond_smc) begin                                //other SMC-IQ is ready
                    if(w_jump_last || w_siq_is_empty) begin
                        rdi_addr_valid           <= 1'b0;
                        // r_state                  <= IDLE;
                    end else begin
                        rdi_addr_valid           <= 1'b1;
                        rdi_addr                 <= rdi_addr + r_jump_code;
                        r_inst_siq_cnt           <= r_inst_siq_cnt + r_jump_code;
                        // r_state                  <= FETCH_DECODE;
                    end
                end
            end

            LOOP_CYCLE: begin
                if(dly_queen_full) begin
                    dly_data_valid               <= 1'b0;
                    rdi_addr_valid               <= 1'b0;
                end else begin
                    if(r_loops_cnt == w_loops) begin
                        r_loops_cnt              <= {BITS_LOOPS{1'b0}};
                        dly_data_valid           <= 1'b1;
                        // dly_data                 <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, w_cond, w_dly, w_new_code};
                        dly_data                 <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, w_cond, {BITS_DLY{1'b0}}, w_new_code};
                        // r_state                  <= FETCH_DECODE;
    
                        if(w_siq_is_empty) begin
                            rdi_addr_valid       <= 1'b0;
                            // r_state              <= IDLE;
                        end else begin
                            rdi_addr_valid       <= 1'b1;
                            rdi_addr             <= rdi_addr + 'd1;
                            // r_state              <= FETCH_DECODE;
                        end
                    end else begin
                        r_loops_cnt              <= r_loops_cnt + 'd1;
                        dly_data_valid           <= 1'b1;
                        // dly_data                 <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, w_cond, w_dly, w_new_code};
                        dly_data                 <= {~w_siq_is_empty, rdi_iqsid, {EN_COND==1}, w_cond, {BITS_DLY{1'b0}}, w_new_code};
                    end
                end
            end
    
            default: begin
                rdi_addr_valid                   <= 1'b0;
                rdi_addr                         <= {RD_ADDR_WIDTH{1'b0}};
                r_inst_siq_cnt                   <= 8'd0;
                // r_state                          <= IDLE;
            end
        endcase
    end
end

endmodule
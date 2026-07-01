//=========================================================================
// Project:     AIACC
// File:        smi_iq.v
// Module:      smi_iq
// Author:      zhuzhenglong
// Email:       zhuzhenglong@inchitech.com
// Created:     2026-1-9
// Modified:    2025-1-9
// Version:     v0.1
//=========================================================================

// Description:
// 

// Parameters:
// - 

//=========================================================================
// Revision History:
// v0.1 - 2026-1-9  - Initial version
//
//=========================================================================
`timescale 1ns/1ps

module smi_iq #(
    parameter  PARA_IQ_ID                = 9,
    parameter  SUB_IQ_NUM                = 4,
    parameter  EXTRA_ADDR                = 0,
    parameter  EXTRA_DATA                = 0,
    parameter  WR_ADDR_WIDTH             = 0,  
    parameter  WR_DATA_WIDTH             = 0,
    parameter  EN_INC_EMBED              = 1,
    parameter  BITS_INC_EMBED            = 6,
    parameter  BIT_CODE                  = ((PARA_IQ_ID == 14) || (PARA_IQ_ID == 15) || (PARA_IQ_ID == 16) || (PARA_IQ_ID == 17)) ? 12  :     //ur-rd
                                           ((PARA_IQ_ID == 18) || (PARA_IQ_ID == 19) || (PARA_IQ_ID == 20) || (PARA_IQ_ID == 21)) ? 28  :     //ur-wr
                                           ((PARA_IQ_ID == 22))                                                                   ? 136 :     //STB
                                           ((PARA_IQ_ID == 23))                                                                   ? 142 :     //LDB
                                           ((PARA_IQ_ID >= 24) && (PARA_IQ_ID <= 87))                                             ? 7   :     //RtoVR
                                           ((PARA_IQ_ID == 0))                                                                    ? 13  :     //INTADD   spec 0.3.15   12-->13
                                           ((PARA_IQ_ID == 1))                                                                    ? 2   :     //INT8toFP16
                                           ((PARA_IQ_ID == 4) || (PARA_IQ_ID == 5))                                               ? 3   :     //FP32ADDTREE8TO1    FPMUL
                                           ((PARA_IQ_ID == 2))                                                                    ? 9   :     //FP16MUL
                                           ((PARA_IQ_ID == 3))                                                                    ? 1   :     //FP32ADDTREE5TO1
                                           ((PARA_IQ_ID == 6))                                                                    ? 5   :     //FPADD   spec 0.3.15   4-->5
                                           ((PARA_IQ_ID == 7) || (PARA_IQ_ID == 9))                                               ? 5   :     //FPtoFP   FPtoINT
                                           ((PARA_IQ_ID == 8))                                                                    ? 7   :     //INTtoINT
                                           ((PARA_IQ_ID == 10) || (PARA_IQ_ID == 11))                                             ? 6   :     //INTtoFP   LOGIC
                                           ((PARA_IQ_ID == 12))                                                                   ? 135 :     //SHIFTUP
                                           ((PARA_IQ_ID == 13))                                                                   ? 134 : 0,  //SHIFTDN,
    parameter  INC_EMBED_MSB_BIT         = WR_ADDR_WIDTH+WR_DATA_WIDTH+BIT_CODE+BITS_INC_EMBED-1,
    parameter  EN_INC                    = 1,
    parameter  BITS_INC                  = 4,
    parameter  INC_MSB_BIT               = WR_ADDR_WIDTH+WR_DATA_WIDTH+BIT_CODE+BITS_INC_EMBED+BITS_INC-1,      
    parameter  EN_DLY                    = 1,
    parameter  BITS_DLY                  = 3,
    parameter  DLY_MSB_BIT               = WR_ADDR_WIDTH+WR_DATA_WIDTH+BIT_CODE+BITS_INC_EMBED+BITS_INC+BITS_DLY-1,    
    parameter  EN_COND                   = 1,
    parameter  BITS_COND                 = 7,
    parameter  COND_MSB_BIT              = WR_ADDR_WIDTH+WR_DATA_WIDTH+BIT_CODE+BITS_INC_EMBED+BITS_INC+BITS_DLY+BITS_COND-1,       
    parameter  EN_LOOPS                  = 1,
    parameter  BITS_LOOPS                = 10,
    parameter  LOOPS_MSB_BIT             = WR_ADDR_WIDTH+WR_DATA_WIDTH+BIT_CODE+BITS_INC_EMBED+BITS_INC+BITS_DLY+BITS_COND+BITS_LOOPS-1,
    parameter  EN_EMBED_END              = 1,
    parameter  BITS_EMBED_END            = 6,
    parameter  EMBED_END_MSB_BIT         = WR_ADDR_WIDTH+WR_DATA_WIDTH+BIT_CODE+BITS_INC_EMBED+BITS_INC+BITS_DLY+BITS_COND+BITS_LOOPS+BITS_EMBED_END-1,
    parameter  EN_EMBED                  = 1,
    parameter  BIT_EMBED                 = 3,
    parameter  EMBED_MSB_BIT             = WR_ADDR_WIDTH+WR_DATA_WIDTH+BIT_CODE+BITS_INC_EMBED+BITS_INC+BITS_DLY+BITS_COND+BITS_LOOPS+BITS_EMBED_END+BIT_EMBED-1,    
    parameter  MIN_HIGH                  = ((PARA_IQ_ID == 14) || (PARA_IQ_ID == 15) || (PARA_IQ_ID == 16) || (PARA_IQ_ID == 17)) ? 11  :     //ur-rd   8
                                           ((PARA_IQ_ID == 18) || (PARA_IQ_ID == 19) || (PARA_IQ_ID == 20) || (PARA_IQ_ID == 21)) ? 11  :     //ur-wr    24
                                           ((PARA_IQ_ID == 22) || (PARA_IQ_ID == 23))                                             ? 58  :     //STB  LDB,
                                           ((PARA_IQ_ID == 2))                                                                    ? 8   : 2,  //FP16MUL
    parameter  MIN_LOW                   = ((PARA_IQ_ID == 14) || (PARA_IQ_ID == 15) || (PARA_IQ_ID == 16) || (PARA_IQ_ID == 17)) ? 4   :     //ur-rd  1
                                           ((PARA_IQ_ID == 18) || (PARA_IQ_ID == 19) || (PARA_IQ_ID == 20) || (PARA_IQ_ID == 21)) ? 4   :     //ur-wr    17
                                           ((PARA_IQ_ID == 22) || (PARA_IQ_ID == 23))                                             ? 19  :     //STB  LDB,
                                           ((PARA_IQ_ID == 2))                                                                    ? 6   : 1,  //FP16MUL
    //VLD(1)+JUMP(1)+EMBED(3)+EMBED_END(6)+LOOPS(10)+COND(7)+DLY(3)+INC(4)+INC_EMBED(6)+CODE=41+CODE
    parameter  WR_INST_WIDTH             = 41+BIT_CODE,
    parameter  INSTQ_DEPTH               = 32,                     //instruction memory depth
    parameter  RD_ADDR_WIDTH             = $clog2(INSTQ_DEPTH),    //$clog2(INSTQ_DEPTH)
    parameter  ADDRQ_DEPTH               = 8,                      //address memory depth
    parameter  DATAQ_DEPTH               = 8,                      //data memory depth
    parameter  SMI_IQ_AMOUNT             = 88,
    // parameter  JUMP_BIT                  = 10,
    parameter  DLY_INST_WIDTH            = (EXTRA_ADDR && EXTRA_DATA) ? BIT_CODE + WR_ADDR_WIDTH + WR_DATA_WIDTH :
                                           (EXTRA_ADDR)               ? BIT_CODE + WR_ADDR_WIDTH                 :
                                           (EXTRA_DATA)               ? BIT_CODE + WR_DATA_WIDTH                 : BIT_CODE,
    parameter  RD_DATA_WIDTH             = (EXTRA_ADDR && EXTRA_DATA) ? WR_INST_WIDTH + WR_ADDR_WIDTH + WR_DATA_WIDTH :
                                            EXTRA_ADDR                ? WR_INST_WIDTH + WR_ADDR_WIDTH :
                                            EXTRA_DATA                ? WR_INST_WIDTH + WR_DATA_WIDTH : WR_INST_WIDTH,
    parameter  DLY_DATA_WIDTH            = (EXTRA_ADDR && EXTRA_DATA) ? (1+2+1+BITS_COND + BITS_DLY + WR_ADDR_WIDTH + WR_DATA_WIDTH + BIT_CODE) : 
                                            EXTRA_ADDR                ? (1+2+1+BITS_COND + BITS_DLY + WR_ADDR_WIDTH + BIT_CODE)                 : 
                                            EXTRA_DATA                ? (1+2+1+BITS_COND + BITS_DLY + WR_DATA_WIDTH + BIT_CODE)                 : (1+2+1+BITS_COND + BITS_DLY + BIT_CODE),
    parameter  MICRO_ADDR_WIDTH          = ((PARA_IQ_ID == 14)  || (PARA_IQ_ID == 15) || (PARA_IQ_ID == 16) || (PARA_IQ_ID == 17) || (PARA_IQ_ID == 18) || (PARA_IQ_ID == 19) || (PARA_IQ_ID == 20) || (PARA_IQ_ID == 21)) ? 8 :    //ur-rd  ur-wr
                                           ((PARA_IQ_ID == 22) || (PARA_IQ_ID == 23)) ? 40 :        //STB  LDB
                                           (PARA_IQ_ID == 2)                          ? 3  : BITS_LOOPS      //FP16MUL
    ) (
    input                                clk,
    input                                rst_n,
    output       [DLY_INST_WIDTH-1:0]    inst,
    output                               inst_keep,
    output                               inst_valid,
    output       [5:0]                   inst_id,
    output                               inst_rdy,
    input        [SMI_IQ_AMOUNT-1:0]     inst_rdy_in,
    input        [31:0]                  inst_jump_in,

    //start and stop send iq instruction
    input                                rdi_start,
    input        [1:0]                   rdi_iqsid,
    output                               rdi_done,
    output       [1:0]                   rdi_iqeid,

    //write instruction
    input        [WR_INST_WIDTH-1:0]     wri_data,
    input                                wri_vld,
    input                                wri_start,
    input                                wri_end,
    input        [1:0]                   wri_iqsid,

    //write address
    input        [WR_ADDR_WIDTH-1:0]     wra_data,
    input                                wra_vld,
    input                                wra_start,
    input                                wra_end,
    input        [1:0]                   wra_iqsid,
    output                               wra_full,

    //write data
    input        [WR_DATA_WIDTH-1:0]     wrd_data,
    input                                wrd_vld,
    input                                wrd_start,
    input                                wrd_end,
    input        [1:0]                   wrd_iqsid,
    output                               wrd_full
);

wire [7:0]                              w_inst_amount_siq0;
wire [7:0]                              w_inst_amount_siq1;
wire [7:0]                              w_inst_amount_siq2;
wire [7:0]                              w_inst_amount_siq3;
wire                                    w_rdi_addr_valid;
wire [RD_ADDR_WIDTH-1:0]                w_rdi_addr;
wire                                    w_rdi_data_valid;
wire [RD_DATA_WIDTH-1:0]                w_rdi_data;
wire                                    w_dly_data_valid;
wire [DLY_DATA_WIDTH-1:0]               w_dly_data;
wire                                    w_dly_queen_full;
wire [SUB_IQ_NUM*3-1:0]                 w_error_inst_queen;
wire [7:0]                              w_error_iic;
wire                                    w_rdi_start_new;
wire [1:0]                              w_rdi_iqsid_new;
wire                                    w_jump_last;
wire                                    w_jump_flag;
wire [7:0]                              w_jump_len;
wire [SUB_IQ_NUM-1:0]                   w_extra_addr_exist_data;
wire [SUB_IQ_NUM-1:0]                   w_extra_data_exist_data;

smi_iq_inst_queen #(
    .PARA_IQ_ID         (PARA_IQ_ID),
    .SUB_IQ_NUM         (SUB_IQ_NUM),
    .WR_INST_WIDTH      (WR_INST_WIDTH),
    .WR_ADDR_WIDTH      (WR_ADDR_WIDTH),
    .WR_DATA_WIDTH      (WR_DATA_WIDTH),
    .RD_DATA_WIDTH      (RD_DATA_WIDTH),
    .EN_COND            (EN_COND),
    .COND_MSB_BIT       (COND_MSB_BIT),
    .EXTRA_ADDR         (EXTRA_ADDR),
    .EXTRA_DATA         (EXTRA_DATA),
    .INSTQ_DEPTH        (INSTQ_DEPTH),
    .RD_ADDR_WIDTH      (RD_ADDR_WIDTH),
    .ADDRQ_DEPTH        (ADDRQ_DEPTH),
    .DATAQ_DEPTH        (DATAQ_DEPTH)
) u_smi_iq_inst_queen(
    .clk                         (clk),
    .rst_n                       (rst_n),
    .wri_data                    (wri_data),
    .wri_vld                     (wri_vld),
    .wri_start                   (wri_start),
    .wri_end                     (wri_end),
    .wri_iqsid                   (wri_iqsid),
    .wra_data                    (wra_data),
    .wra_vld                     (wra_vld),
    .wra_start                   (wra_start),
    .wra_end                     (wra_end),
    .wra_iqsid                   (wra_iqsid),
    .wra_full                    (wra_full),
    .wrd_data                    (wrd_data),
    .wrd_vld                     (wrd_vld),
    .wrd_start                   (wrd_start),
    .wrd_end                     (wrd_end),
    .wrd_iqsid                   (wrd_iqsid),
    .wrd_full                    (wrd_full),
    .inst_amount_siq0            (w_inst_amount_siq0),
    .inst_amount_siq1            (w_inst_amount_siq1),
    .inst_amount_siq2            (w_inst_amount_siq2),
    .inst_amount_siq3            (w_inst_amount_siq3),
    .rdi_start                   (rdi_start),
    .rdi_iqsid                   (rdi_iqsid),
    .rdi_start_new               (w_rdi_start_new),
    .rdi_iqsid_new               (w_rdi_iqsid_new),
    .rdi_done                    (rdi_done),
    .rdi_iqeid                   (rdi_iqeid),
    .rdi_addr_valid              (w_rdi_addr_valid),
    .rdi_addr                    (w_rdi_addr),
    .rdi_data_valid              (w_rdi_data_valid),
    .rdi_data                    (w_rdi_data),
    .error_inst_queen            (w_error_inst_queen),
    .jump_last                   (w_jump_last),
    .jump_flag                   (w_jump_flag),
    .jump_len                    (w_jump_len),
    .extra_addr_exist_data       (w_extra_addr_exist_data),
    .extra_data_exist_data       (w_extra_data_exist_data)
);

smi_iq_iic #(
    .PARA_IQ_ID              (PARA_IQ_ID),
    .EN_EMBED                (EN_EMBED),
    .BIT_EMBED               (BIT_EMBED),
    .EMBED_MSB_BIT           (EMBED_MSB_BIT),
    .EN_EMBED_END            (EN_EMBED_END),
    .BITS_EMBED_END          (BITS_EMBED_END),
    .EMBED_END_MSB_BIT       (EMBED_END_MSB_BIT),
    .EN_LOOPS                (EN_LOOPS),
    .BITS_LOOPS              (BITS_LOOPS),
    .LOOPS_MSB_BIT           (LOOPS_MSB_BIT),
    .EN_COND                 (EN_COND),
    .BITS_COND               (BITS_COND),
    .COND_MSB_BIT            (COND_MSB_BIT),
    .EN_DLY                  (EN_DLY),
    .BITS_DLY                (BITS_DLY),
    .DLY_MSB_BIT             (DLY_MSB_BIT),
    .EN_INC                  (EN_INC),
    .BITS_INC                (BITS_INC),
    .INC_MSB_BIT             (INC_MSB_BIT),
    .EN_INC_EMBED            (EN_INC_EMBED),
    .BITS_INC_EMBED          (BITS_INC_EMBED),
    .INC_EMBED_MSB_BIT       (INC_EMBED_MSB_BIT),
    .MIN_HIGH                (MIN_HIGH),
    .MIN_LOW                 (MIN_LOW),
    .BIT_CODE                (BIT_CODE),
    .EXTRA_ADDR              (EXTRA_ADDR),
    .EXTRA_DATA              (EXTRA_DATA),
    .WR_INST_WIDTH           (WR_INST_WIDTH),
    .WR_ADDR_WIDTH           (WR_ADDR_WIDTH),
    .WR_DATA_WIDTH           (WR_DATA_WIDTH),
    .SMI_IQ_AMOUNT           (SMI_IQ_AMOUNT),
    .RD_DATA_WIDTH           (RD_DATA_WIDTH),
    .RD_ADDR_WIDTH           (RD_ADDR_WIDTH),
    .INSTQ_DEPTH             (INSTQ_DEPTH),
    .DLY_DATA_WIDTH          (DLY_DATA_WIDTH),
    .MICRO_ADDR_WIDTH        (MICRO_ADDR_WIDTH)
) u_smi_iq_iic(
    .clk                     (clk),
    .rst_n                   (rst_n),
    .inst_rdy_in             (inst_rdy_in),
    .inst_jump_in            (inst_jump_in),
    .rdi_start               (w_rdi_start_new),
    .rdi_iqsid               (w_rdi_iqsid_new),
    .rdi_addr_valid          (w_rdi_addr_valid),
    .rdi_addr                (w_rdi_addr),
    .rdi_data_valid          (w_rdi_data_valid),
    .rdi_data                (w_rdi_data),
    .inst_amount_siq0        (w_inst_amount_siq0),
    .inst_amount_siq1        (w_inst_amount_siq1),
    .inst_amount_siq2        (w_inst_amount_siq2),
    .inst_amount_siq3        (w_inst_amount_siq3),
    .dly_data_valid          (w_dly_data_valid),
    .dly_data                (w_dly_data),
    .dly_queen_full          (w_dly_queen_full),
    .error_iic               (w_error_iic),
    .jump_last               (w_jump_last),
    .jump_flag               (w_jump_flag),
    .jump_len                (w_jump_len)
);

smi_iq_dly_queen #(
    .PARA_IQ_ID               (PARA_IQ_ID),
    .SUB_IQ_NUM               (SUB_IQ_NUM),
    .WR_INST_WIDTH            (WR_INST_WIDTH),
    .WR_ADDR_WIDTH            (WR_ADDR_WIDTH),
    .WR_DATA_WIDTH            (WR_DATA_WIDTH),
    .SMI_IQ_AMOUNT            (SMI_IQ_AMOUNT),
    .BITS_COND                (BITS_COND),
    .BITS_DLY                 (BITS_DLY),
    .BIT_CODE                 (BIT_CODE),
    .EN_COND                  (EN_COND),
    .EN_DLY                   (EN_DLY),
    .EXTRA_ADDR               (EXTRA_ADDR),
    .EXTRA_DATA               (EXTRA_DATA),
    .DLY_INST_WIDTH           (DLY_INST_WIDTH),
    .DLY_DATA_WIDTH           (DLY_DATA_WIDTH)
) u_smi_iq_dly_queen(    
    .clk                      (clk),
    .rst_n                    (rst_n),
    .dly_data_valid           (w_dly_data_valid),
    .dly_data                 (w_dly_data),
    .dly_queen_full           (w_dly_queen_full),
    .rdi_start                (w_rdi_start_new),
    .rdi_iqsid                (w_rdi_iqsid_new),
    .rdi_done                 (rdi_done),
    .inst                     (inst),
    .inst_keep                (inst_keep),
    .inst_valid               (inst_valid),
    .inst_id                  (inst_id),
    .inst_rdy                 (inst_rdy),
    .inst_rdy_in              (inst_rdy_in),
    .extra_addr_exist_data    (w_extra_addr_exist_data),
    .extra_data_exist_data    (w_extra_data_exist_data)
);

endmodule
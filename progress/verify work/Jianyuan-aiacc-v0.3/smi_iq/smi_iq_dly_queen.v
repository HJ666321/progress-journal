//=========================================================================
// Project:     AIACC
// File:        smi_iq_dly_queen.v
// Module:      smi_iq_dly_queen
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

module smi_iq_dly_queen #(
    parameter  PARA_IQ_ID                = 1,
    parameter  SUB_IQ_NUM                = 4,
    parameter  WR_INST_WIDTH             = 32,
    parameter  WR_ADDR_WIDTH             = 32,  
    parameter  WR_DATA_WIDTH             = 32,
    parameter  SMI_IQ_AMOUNT             = 32,
    parameter  BITS_COND                 = 7,
    parameter  BITS_DLY                  = 3,
    parameter  BIT_CODE                  = 10,
    parameter  EN_COND                   = 1,
    parameter  EN_DLY                    = 1,
    parameter  EXTRA_ADDR                = 1,
    parameter  EXTRA_DATA                = 1,
    parameter  DLY_INST_WIDTH            = BIT_CODE + WR_ADDR_WIDTH + WR_DATA_WIDTH,
    parameter  DLY_DATA_WIDTH            = (EXTRA_ADDR && EXTRA_DATA) ? (1+2+1+BITS_COND + BITS_DLY + WR_ADDR_WIDTH + WR_DATA_WIDTH + BIT_CODE) : 
                                            EXTRA_ADDR                ? (1+2+1+BITS_COND + BITS_DLY + WR_ADDR_WIDTH + BIT_CODE)                 : 
                                            EXTRA_DATA                ? (1+2+1+BITS_COND + BITS_DLY + WR_DATA_WIDTH + BIT_CODE)                 : (1+2+1+BITS_COND + BITS_DLY + BIT_CODE)
)(
    input                                clk,
    input                                rst_n,

    //from smi_iq_iic
    input                                dly_data_valid,
    input        [DLY_DATA_WIDTH-1:0]    dly_data,
    output                               dly_queen_full,

    //iqsid start and done
    input                                rdi_start,
    input        [1:0]                   rdi_iqsid,
    input                                rdi_done,

    //to SMC
    output reg   [DLY_INST_WIDTH-1:0]    inst,
    output reg                           inst_keep,
    output reg                           inst_valid,
    output reg   [5:0]                   inst_id,
    output reg                           inst_rdy,
    input        [SMI_IQ_AMOUNT-1:0]     inst_rdy_in,
    output       [SUB_IQ_NUM*3-1:0]      error_inst_queen,

    input reg    [SUB_IQ_NUM-1:0]        extra_addr_exist_data,          //extra address memory already have data
    input reg    [SUB_IQ_NUM-1:0]        extra_data_exist_data           //extra data memory already have data
);

localparam  IDLE             = 5'b00001;
localparam  INST_DECODE      = 5'b00010;
localparam  WAIT_DLY         = 5'b00100;
localparam  WAIT_COND        = 5'b01000;

localparam  MEM_DEPTH        = 32;
localparam  MEM_CLOG2        = $clog2(MEM_DEPTH);

reg  [4:0]                     r_state;
reg  [4:0]                     r_current_state;
reg  [4:0]                     r_next_state;
reg  [DLY_DATA_WIDTH-1:0]      r_inst_data_mem[MEM_DEPTH-1:0];   //depth =32 
reg  [MEM_CLOG2:0]             r_mem_wr_cnt;
reg  [MEM_CLOG2:0]             r_mem_rd_cnt;
reg  [DLY_DATA_WIDTH-1:0]      r_mem_rd_data;       //{iq_last-flag, iqsid, cond_en, cond, dly, code}
reg  [BITS_DLY-1:0]            r_dly_cnt;
reg  [DLY_INST_WIDTH-1:0]      r_mem_data_prev;

wire                           w_mem_empty;
wire                           w_mem_full;
// wire                           w_mem_iq_last_data_flag;
// wire [1:0]                     w_mem_iqsid;
// wire                           w_mem_cond_en;
wire [BITS_COND-1:0]           w_mem_cond;
wire [BITS_DLY-1:0]            w_mem_dly;
wire [DLY_INST_WIDTH-1:0]      w_mem_data;

assign w_mem_full              = (r_mem_rd_cnt[MEM_CLOG2-1:0] == r_mem_wr_cnt[MEM_CLOG2-1:0]) && (r_mem_rd_cnt[MEM_CLOG2] ^ r_mem_wr_cnt[MEM_CLOG2]);   //MSB not same is full flag
assign w_mem_empty             = r_mem_rd_cnt == r_mem_wr_cnt;
assign dly_queen_full          = w_mem_full;

//decode memory data
// assign w_mem_iq_last_data_flag = r_mem_rd_data[DLY_DATA_WIDTH-1];
// assign w_mem_iqsid             = r_mem_rd_data[DLY_DATA_WIDTH-2 -: 2];
// assign w_mem_cond_en           = r_mem_rd_data[DLY_DATA_WIDTH-4];
assign w_mem_cond              = r_mem_rd_data[DLY_DATA_WIDTH-5 -: BITS_COND];
assign w_mem_dly               = r_mem_rd_data[DLY_INST_WIDTH +: BITS_DLY];
assign w_mem_data              = r_mem_rd_data[DLY_INST_WIDTH-1:0];

//write instruction to reg array
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        r_mem_wr_cnt                                            <= 'd0;
        inst_id                                                 <= PARA_IQ_ID;
    end else begin
        inst_id                                                 <= PARA_IQ_ID;

        if((dly_data_valid) && ~w_mem_full) begin
            r_mem_wr_cnt                                        <= r_mem_wr_cnt + 'd1;
            r_inst_data_mem[r_mem_wr_cnt[MEM_CLOG2-1:0]]        <= dly_data;
        end
    end
end

//handle dly and cond
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        r_mem_rd_cnt                              <= 'd0;
        inst_keep                                 <= 1'b0;
        r_state                                   <= IDLE;
        r_dly_cnt                                 <= {BITS_DLY{1'b0}};
        inst_valid                                <= 1'b0;
        inst                                      <= {DLY_INST_WIDTH{1'b0}};
    end else begin
        case (r_state)
            IDLE: begin
                inst_valid                        <= 1'b0;

                if(~w_mem_empty) begin
                    r_mem_rd_cnt                  <= r_mem_rd_cnt + 'd1;
                    r_mem_rd_data                 <= r_inst_data_mem[r_mem_rd_cnt[MEM_CLOG2-1:0]];
                    r_state                       <= INST_DECODE;
                end
            end
 
            INST_DECODE: begin
                r_mem_data_prev                   <= w_mem_data;
                if(r_mem_data_prev == w_mem_data) begin
                    inst_keep                     <= 1'b1;
                end else begin
                    inst_keep                     <= 1'b0;
                end

                //when dly=0 && cond is ready
                if((~(|w_mem_dly) && EN_DLY) && (inst_rdy_in[w_mem_cond] && EN_COND)) begin
                    r_mem_rd_data                 <= r_inst_data_mem[r_mem_rd_cnt[MEM_CLOG2-1:0]];
                    inst_valid                    <= 1'b1;
                    inst                          <= w_mem_data;

                    if(w_mem_empty) begin
                        r_state                   <= IDLE;
                    end else begin
                        r_mem_rd_cnt              <= r_mem_rd_cnt + 'd1;
                    end
                end else if((|w_mem_dly) && EN_DLY) begin                       //w_mem_dly != 0
                    r_dly_cnt                     <= w_mem_dly - 'd1;
                    inst_valid                    <= 1'b0;
                    // rdi_done                      <= 1'b0;
                    r_state                       <= WAIT_DLY;
                end else if(inst_rdy_in[w_mem_cond] && EN_COND) begin           //if(~inst_rdy_in[w_mem_cond]) 
                    inst_valid                    <= 1'b0;
                    r_state                       <= WAIT_COND;
                end else begin
                    r_mem_rd_data                 <= r_inst_data_mem[r_mem_rd_cnt[MEM_CLOG2-1:0]];
                    inst_valid                    <= 1'b1;
                    inst                          <= w_mem_data;

                    if(w_mem_empty) begin
                        r_state                   <= IDLE;
                    end else begin
                        r_mem_rd_cnt              <= r_mem_rd_cnt + 'd1;
                    end
                end
            end
 
            WAIT_DLY: begin
                if(~(|r_dly_cnt)) begin                                         //r_dly_cnt == 0
                    if(EN_COND) begin
                        // r_state                   <= WAIT_COND;

                        if(inst_rdy_in[w_mem_cond]) begin
                            r_mem_rd_data         <= r_inst_data_mem[r_mem_rd_cnt[MEM_CLOG2-1:0]];
                            inst_valid            <= 1'b1;
                            inst                  <= w_mem_data;
        
                            if(w_mem_empty) begin
                                r_state           <= IDLE;
                            end else begin
                                r_mem_rd_cnt      <= r_mem_rd_cnt + 'd1;
                                r_state           <= INST_DECODE;
                            end
                        end else begin
                            r_state               <= WAIT_COND;
                        end
                    end else begin
                        r_mem_rd_data             <= r_inst_data_mem[r_mem_rd_cnt[MEM_CLOG2-1:0]];
                        inst_valid                <= 1'b1;
                        inst                      <= w_mem_data;
    
                        if(w_mem_empty) begin
                            r_state               <= IDLE;
                        end else begin
                            r_mem_rd_cnt          <= r_mem_rd_cnt + 'd1;
                            r_state               <= INST_DECODE;
                        end
                    end
                end else begin
                    r_dly_cnt                     <= r_dly_cnt - 'd1;
                end
            end
 
            WAIT_COND: begin
                if(inst_rdy_in[w_mem_cond]) begin
                    r_mem_rd_data                 <= r_inst_data_mem[r_mem_rd_cnt[MEM_CLOG2-1:0]];
                    inst_valid                    <= 1'b1;
                    inst                          <= w_mem_data;

                    if(w_mem_empty) begin
                        r_state                   <= IDLE;
                    end else begin
                        r_mem_rd_cnt              <= r_mem_rd_cnt + 'd1;
                        r_state                   <= INST_DECODE;
                    end
                end
            end
 
            default: begin
                r_state                           <= IDLE;
                r_dly_cnt                         <= {BITS_DLY{1'b0}};
                inst_valid                        <= 1'b0;
                inst                              <= {DLY_INST_WIDTH{1'b0}};
            end
        endcase
    end
end

//generate inst_rdy
generate
    if(EXTRA_ADDR && EXTRA_DATA) begin
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                inst_rdy                                  <= 1'b0;
            end else begin
                if(rdi_start & extra_data_exist_data[rdi_iqsid] & extra_addr_exist_data[rdi_iqsid]) begin
                    inst_rdy                              <= 1'b1;
                end
        
                if(rdi_done) begin
                    inst_rdy                              <= 1'b0;
                end
            end
        end
    end else if(EXTRA_ADDR) begin
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                inst_rdy                                  <= 1'b0;
            end else begin
                if(rdi_start & extra_addr_exist_data[rdi_iqsid]) begin
                    inst_rdy                              <= 1'b1;
                end
        
                if(rdi_done) begin
                    inst_rdy                              <= 1'b0;
                end
            end
        end
    end else if(EXTRA_DATA) begin
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                inst_rdy                                  <= 1'b0;
            end else begin
                if(rdi_start & extra_data_exist_data[rdi_iqsid]) begin
                    inst_rdy                              <= 1'b1;
                end
        
                if(rdi_done) begin
                    inst_rdy                              <= 1'b0;
                end
            end
        end
    end else begin
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                inst_rdy                                  <= 1'b0;
            end else begin
                if(rdi_start) begin
                    inst_rdy                              <= 1'b1;
                end
        
                if(rdi_done) begin
                    inst_rdy                              <= 1'b0;
                end
            end
        end
    end
endgenerate

endmodule    

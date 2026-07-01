//=========================================================================
// Project:     AIACC
// File:        smi_iq_inst_queen.v
// Module:      smi_iq_inst_queen
// Author:      zhuzhenglong
// Email:       zhuzhenglong@inchitech.com
// Created:     2026-1-5
// Modified:    2025-1-5
// Version:     v0.1
//=========================================================================

// Description:
// 

// Parameters:
// - 

//=========================================================================
// Revision History:
// v0.1 - 2026-1-5  - Initial version
//
//=========================================================================
`timescale 1ns/1ps

module  smi_iq_inst_queen#(
    parameter  PARA_IQ_ID                = 1,
    parameter  SUB_IQ_NUM                = 4,
    parameter  WR_INST_WIDTH             = 32,
    parameter  WR_ADDR_WIDTH             = 32,  
    parameter  WR_DATA_WIDTH             = 32,  
    parameter  RD_DATA_WIDTH             = WR_INST_WIDTH + WR_ADDR_WIDTH + WR_DATA_WIDTH,
    parameter  EN_COND                   = 1,
    parameter  COND_MSB_BIT              = 10,
    parameter  EXTRA_ADDR                = 1,
    parameter  EXTRA_DATA                = 1,
    parameter  INSTQ_DEPTH               = 32,
    parameter  RD_ADDR_WIDTH             = 5,    //$clog2(INSTQ_DEPTH)
    parameter  ADDRQ_DEPTH               = 8,
    parameter  DATAQ_DEPTH               = 8
)(
    input                                clk,
    input                                rst_n,

    //write instruction
    input        [WR_INST_WIDTH-1:0]     wri_data,
    input                                wri_vld,
    input                                wri_start,
    input                                wri_end,
    input        [1:0]                   wri_iqsid,

    //wrire addr
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
    output                               wrd_full,

    //write instruction amount every iqsid
    output       [7:0]                   inst_amount_siq0,
    output       [7:0]                   inst_amount_siq1,
    output       [7:0]                   inst_amount_siq2,
    output       [7:0]                   inst_amount_siq3,

    //start and done signal
    input                                rdi_start,
    input        [1:0]                   rdi_iqsid,
    output reg                           rdi_start_new,    //start may be continuous, so generate a interval start
    output reg   [1:0]                   rdi_iqsid_new,
    output reg                           rdi_done,
    output reg   [1:0]                   rdi_iqeid,

    //read data from inst/data/address memory
    input                                rdi_addr_valid,
    input        [RD_ADDR_WIDTH-1:0]     rdi_addr,
    output                               rdi_data_valid,
    output       [RD_DATA_WIDTH-1:0]     rdi_data,

    //error for debug
    output       [SUB_IQ_NUM*3-1:0]      error_inst_queen,
    input                                jump_last,
    input                                jump_flag,
    input        [7:0]                   jump_len,
    output reg   [SUB_IQ_NUM-1:0]        extra_addr_exist_data,          //extra address memory already have data
    output reg   [SUB_IQ_NUM-1:0]        extra_data_exist_data           //extra data memory already have data
);
localparam WAIT_START               = 2'b01;
localparam WAIT_DONE                = 2'b10;

reg [1:0]                      rdi_state;
reg [WR_INST_WIDTH-1:0]        r_inst [0:SUB_IQ_NUM-1][0:INSTQ_DEPTH-1];
reg [7:0]                      r_wr_inst_cnt [0:SUB_IQ_NUM-1];
reg [7:0]                      r_rd_mem_cnt  [0:SUB_IQ_NUM-1];
reg [RD_DATA_WIDTH-1:0]        r_rdi_data_tmp [0:SUB_IQ_NUM-1];
reg [SUB_IQ_NUM-1:0]           r_rdi_data_valid_tmp;
reg [SUB_IQ_NUM-1:0]           r_err_wr_inst_addr_overflow;
reg [SUB_IQ_NUM-1:0]           r_mem_inst_writable;
reg [SUB_IQ_NUM-1:0]           r_err_wr_data_addr_overflow;
reg [SUB_IQ_NUM-1:0]           r_err_wr_addr_addr_overflow;
reg [SUB_IQ_NUM-1:0]           r_mem_addr_writable;
reg [7:0]                      r_wr_addr_cnt [0:SUB_IQ_NUM-1];
reg [WR_ADDR_WIDTH-1:0]        r_addr [0:SUB_IQ_NUM-1][0:ADDRQ_DEPTH-1];
reg [SUB_IQ_NUM-1:0]           r_mem_data_writable;
reg [7:0]                      r_wr_data_cnt [0:SUB_IQ_NUM-1];
reg [WR_DATA_WIDTH-1:0]        r_data [0:SUB_IQ_NUM-1][0:DATAQ_DEPTH-1];
// reg [0:0]                   r_rdi_start_array [3:0];
reg [1:0]                      r_rdi_iqsid_array [3:0];
reg [2:0]                      r_rdi_start_wr_cnt;             //when r_rdi_start_wr_cnt[1:0]==r_rdi_start_rd_cnt[1:0]     
                                                               //r_rdi_start_wr_cnt[2]==r_rdi_start_rd_cnt[2]==>empty    
                                                               //r_rdi_start_wr_cnt[2]!=r_rdi_start_rd_cnt[2]==>full
reg [2:0]                      r_rdi_start_rd_cnt;
reg                            r_rdi_iqsid_can_send;           //iqsid can send data(already receive start)

//error summary
assign error_inst_queen        = {r_err_wr_data_addr_overflow, r_err_wr_addr_addr_overflow, r_err_wr_inst_addr_overflow};
//the quantity of memory stored
assign inst_amount_siq0        = r_wr_inst_cnt[0];
assign inst_amount_siq1        = r_wr_inst_cnt[1];
assign inst_amount_siq2        = r_wr_inst_cnt[2];
assign inst_amount_siq3        = r_wr_inst_cnt[3];
assign rdi_data_valid          = |r_rdi_data_valid_tmp;
assign rdi_data                = (rdi_iqsid_new == 2'b00) ? r_rdi_data_tmp[0] : 
                                 (rdi_iqsid_new == 2'b01) ? r_rdi_data_tmp[1] : 
                                 (rdi_iqsid_new == 2'b10) ? r_rdi_data_tmp[2] : 
                                 (rdi_iqsid_new == 2'b11) ? r_rdi_data_tmp[3] : {RD_DATA_WIDTH{1'b0}};

//write instruction memory
genvar i;
generate
    for(i = 0; i < SUB_IQ_NUM; i = i + 1) begin : get_inst_memory_addr
        //only between wri_start and wri_end can write instruction to instruction memory
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                r_mem_inst_writable[i]                <= 1'b0;
            end else if(wri_vld) begin
                if(wri_start & wri_end) begin
                    r_mem_inst_writable[i]            <= 1'b0;
                end else if(wri_start) begin
                    r_mem_inst_writable[i]            <= 1'b1;
                end else if(wri_end) begin
                    r_mem_inst_writable[i]            <= 1'b0;
                end
            end
        end

        //write count
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                r_wr_inst_cnt[i]                      <= 8'd0;
                r_err_wr_inst_addr_overflow[i]        <= 1'b0;
            end else begin
                if(wri_vld && (wri_iqsid == i)) begin
                   if(wri_start) begin
                       r_wr_inst_cnt[i]               <= 8'd0;
                   end else if(r_mem_inst_writable[i]) begin
                       r_wr_inst_cnt[i]               <= r_wr_inst_cnt[i] + 8'd1;
                   end
                end

                //when overflow, report error
                if(r_wr_inst_cnt[i] >= INSTQ_DEPTH)
                    r_err_wr_inst_addr_overflow[i]    <= 1'b1;
            end
        end

        //write instruction memory
        always @(posedge clk) begin
            if(wri_vld && (wri_iqsid == i)) begin
                if(wri_start) begin
                    r_inst[i][0]                      <= wri_data;
                end else begin
                    r_inst[i][r_wr_inst_cnt[i]+1]     <= wri_data;    //because r_wr_inst_cnt[i] is a non-blocking assignment, so index using r_wr_inst_cnt[i]+1
                end
            end
        end
    end
endgenerate

//write addrress memory
genvar m;
generate
    if(EXTRA_ADDR) begin
        assign wra_full     = (wra_iqsid == 2'b00) && (r_wr_addr_cnt[0] == ADDRQ_DEPTH-1) ? 1'b1 :
                              (wra_iqsid == 2'b01) && (r_wr_addr_cnt[1] == ADDRQ_DEPTH-1) ? 1'b1 :
                              (wra_iqsid == 2'b10) && (r_wr_addr_cnt[2] == ADDRQ_DEPTH-1) ? 1'b1 :
                              (wra_iqsid == 2'b11) && (r_wr_addr_cnt[3] == ADDRQ_DEPTH-1) ? 1'b1 : 1'b0;

        for(m = 0; m < SUB_IQ_NUM; m = m + 1) begin : get_addr_memory_addr
            //only between wra_start and wra_end can write address to address memory
            always @(posedge clk or negedge rst_n) begin
                if(!rst_n) begin
                    r_mem_addr_writable[m]                <= 1'b0;
                end else if(wra_vld) begin
                    if(wra_start & wra_end) begin
                        r_mem_addr_writable[m]            <= 1'b0;
                    end else if(wra_start) begin
                        r_mem_addr_writable[m]            <= 1'b1;
                    end else if(wra_end) begin
                        r_mem_addr_writable[m]            <= 1'b0;
                    end
                end
            end
    
            //write address count
            always @(posedge clk or negedge rst_n) begin
                if(!rst_n) begin
                    r_wr_addr_cnt[m]                      <= 8'd0;
                    r_err_wr_addr_addr_overflow[m]        <= 1'b0;
                end else begin
                    if(wra_vld && (wra_iqsid == m)) begin
                        if(wra_start) begin
                            r_wr_addr_cnt[m]              <= 8'd0;
                        end else if(r_mem_addr_writable[m]) begin
                            r_wr_addr_cnt[m]              <= r_wr_addr_cnt[m] + 8'd1;
                        end
                    end
    
                    if(r_wr_addr_cnt[m] >= ADDRQ_DEPTH)
                        r_err_wr_addr_addr_overflow[m]    <= 1'b1;
                end
            end
    
            //write address memory
            always @(posedge clk) begin
                if(wra_vld && (wra_iqsid == m)) begin
                    if(wra_start) begin
                        r_addr[m][0]                      <= wra_data;
                    end else begin
                        r_addr[m][r_wr_addr_cnt[m]+1]     <= wra_data;
                    end
                end
            end
        end
    end else begin
        assign wra_full                                   = 1'b0;

        always @(posedge clk) begin
            r_err_wr_addr_addr_overflow                   <= 4'b0000;
        end
    end
endgenerate

//write data memory
genvar p;
generate
    if(EXTRA_DATA) begin
        assign wrd_full     = (wrd_iqsid == 2'b00) && (r_wr_data_cnt[0] == DATAQ_DEPTH-1) ? 1'b1 :
                              (wrd_iqsid == 2'b01) && (r_wr_data_cnt[1] == DATAQ_DEPTH-1) ? 1'b1 :
                              (wrd_iqsid == 2'b10) && (r_wr_data_cnt[2] == DATAQ_DEPTH-1) ? 1'b1 :
                              (wrd_iqsid == 2'b11) && (r_wr_data_cnt[3] == DATAQ_DEPTH-1) ? 1'b1 : 1'b0;

        for(p = 0; p < SUB_IQ_NUM; p = p + 1) begin : get_data_memory_addr
            //only between wrd_start and wrd_end can write address to address memory
            always @(posedge clk or negedge rst_n) begin
                if(!rst_n) begin
                    r_mem_data_writable[p]                <= 1'b0;
                end else if(wrd_vld) begin
                    if(wrd_start & wrd_end) begin
                        r_mem_data_writable[p]            <= 1'b0;
                    end else if(wrd_start) begin
                        r_mem_data_writable[p]            <= 1'b1;
                    end else if(wrd_end) begin
                        r_mem_data_writable[p]            <= 1'b0;
                    end
                end
            end
    
            //write data count
            always @(posedge clk or negedge rst_n) begin
                if(!rst_n) begin
                    r_wr_data_cnt[p]                      <= 8'd0;
                    r_err_wr_data_addr_overflow[p]        <= 1'b0;
                end else begin
                    if(wrd_vld && (wrd_iqsid == p)) begin
                        if(wrd_start) begin
                            r_wr_data_cnt[p]              <= 8'd0;
                        end else if(r_mem_data_writable[p]) begin
                            r_wr_data_cnt[p]              <= r_wr_data_cnt[p] + 8'd1;
                        end
                    end
    
                    if(r_wr_data_cnt[p] >= DATAQ_DEPTH)
                        r_err_wr_data_addr_overflow[p]    <= 1'b1;
                end
            end
    
            //write data memory
            always @(posedge clk) begin
                if(wrd_vld && (wrd_iqsid == p)) begin
                    if(wrd_start) begin
                        r_data[p][0]                      <= wrd_data;
                    end else begin
                        r_data[p][r_wr_data_cnt[p]+1]     <= wrd_data;
                    end
                end
            end
        end
    end else begin
        assign wrd_full                                  = 1'b0;

        always @(posedge clk) begin
            r_err_wr_data_addr_overflow                   <= 4'b0000;
        end
    end
endgenerate

//store the received rdi_start in an array
//rdi_start may be continous
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        r_rdi_start_wr_cnt                                <= 3'd0;
    end else begin
        if(rdi_start) begin
            r_rdi_start_wr_cnt                            <= r_rdi_start_wr_cnt + 3'd1;
        end
    end
end

//store rdi_iqsid
always @(posedge clk) begin    //write memory
    if(rdi_start) begin
        // r_rdi_start_array[r_rdi_start_wr_cnt]     <= 1'b1;    //
        r_rdi_iqsid_array[r_rdi_start_wr_cnt[1:0]]        <= rdi_iqsid;
    // end else if(rdi_done) begin
        // r_rdi_start_array[r_rdi_start_rd_cnt]     <= 1'b0;
        // r_rdi_iqsid_array[r_rdi_start_rd_cnt]     <= 2'b00;
    end
end

//generate new   rdi_start_new and rdi_iqsid_new to replace rdi_start and rdi_iqsid
always @(posedge clk or negedge rst_n) begin    //generate new start
    if(~rst_n) begin
        rdi_start_new                    <= 1'b0;
        rdi_iqsid_new                    <= 2'b00;
        rdi_done                         <= 1'b0;
        r_rdi_start_rd_cnt               <= 3'd0;
        r_rdi_iqsid_can_send             <= 1'b0;
        rdi_state                        <= WAIT_START;
    end else begin
        case (rdi_state)
            WAIT_START : begin
                rdi_done                 <= 1'b0;

                if(r_rdi_start_wr_cnt != r_rdi_start_rd_cnt) begin
                    rdi_start_new        <= 1'b1;
                    r_rdi_iqsid_can_send <= 1'b1;
                    rdi_iqsid_new        <= r_rdi_iqsid_array[r_rdi_start_rd_cnt[1:0]];
                    rdi_state            <= WAIT_DONE;
                end
            end

            WAIT_DONE: begin
                rdi_start_new            <= 1'b0;

                //wait read all instruction
                if(((rdi_iqsid_new == 2'b00) && (r_rd_mem_cnt[0] >= (r_wr_inst_cnt[0]+1))) || 
                   ((rdi_iqsid_new == 2'b01) && (r_rd_mem_cnt[1] >= (r_wr_inst_cnt[1]+1))) || 
                   ((rdi_iqsid_new == 2'b10) && (r_rd_mem_cnt[2] >= (r_wr_inst_cnt[2]+1))) || 
                   ((rdi_iqsid_new == 2'b11) && (r_rd_mem_cnt[3] >= (r_wr_inst_cnt[3]+1)))) begin    //wait count equal
                    rdi_done             <= 1'b1;
                    r_rdi_iqsid_can_send <= 1'b0;
                    r_rdi_start_rd_cnt   <= r_rdi_start_rd_cnt + 3'd1;
                    rdi_iqeid            <= r_rdi_iqsid_array[r_rdi_start_rd_cnt[1:0]];
                    rdi_state            <= WAIT_START;
                end
            end
        endcase
    end
end

//receive data count
genvar y;
generate
    for(y = 0; y < SUB_IQ_NUM; y = y + 1) begin : read_memory_data_cnt
        always @(posedge clk or negedge rst_n) begin
            if(~rst_n) begin
                r_rd_mem_cnt[y]                           <= 8'd0;
            end else begin
                // if(rdi_start_new && rdi_addr_valid && (rdi_iqsid_new == y)) begin
                if(rdi_start_new && (rdi_iqsid_new == y)) begin
                    r_rd_mem_cnt[y]                       <= 8'd0;
                end else if(jump_last && (rdi_iqsid_new == y)) begin                      //when jump to last, end the current queue
                    r_rd_mem_cnt[y]                       <= r_wr_inst_cnt[y] + 8'd1;
                end else if((rdi_iqsid_new == y) && rdi_addr_valid && jump_flag) begin    //when fetch jump instruction, jump length from code section
                    r_rd_mem_cnt[y]                       <= r_rd_mem_cnt[y] + jump_len;
                end else if((rdi_iqsid_new == y) && rdi_addr_valid) begin
                    r_rd_mem_cnt[y]                       <= r_rd_mem_cnt[y] + 8'd1;
                end
            end
        end
    end
endgenerate

reg  [2:0]    r_current_state [SUB_IQ_NUM-1:0];
reg  [2:0]    r_next_state [SUB_IQ_NUM-1:0];
localparam WAIT_RD_REQ      = 3'b001;
localparam WAIT_SEND        = 3'b010;

//read data from instruction memory
genvar z;
generate
    for(z = 0; z < SUB_IQ_NUM; z = z + 1) begin : read_memory_data
        if(EXTRA_ADDR && EXTRA_DATA) begin    //need wait extra address and extra data
            //confirm whether extra data and address is empty
            always @(posedge clk or negedge rst_n) begin
                if(~rst_n) begin
                    extra_data_exist_data[z]              <= 1'b0;
                    extra_addr_exist_data[z]              <= 1'b0;
                end else begin
                    if(wra_start && (wra_iqsid == z)) begin
                        extra_addr_exist_data[z]          <= 1'b1;
                    //when last extra data read out, then extra_addr_exist_data[z]=0
                    end else if(((r_rd_mem_cnt[z] >= (r_wr_inst_cnt[z]+1)) && r_rdi_data_valid_tmp[z]) && ((r_rd_mem_cnt[z] >= (r_wr_data_cnt[z]+1)) && r_rdi_data_valid_tmp[z]) && ((r_rd_mem_cnt[z] >= (r_wr_addr_cnt[z]+1)) && r_rdi_data_valid_tmp[z])) begin
                        extra_addr_exist_data[z]          <= 1'b0;
                    end

                    if(wrd_start && (wrd_iqsid == z)) begin
                        extra_data_exist_data[z]          <= 1'b1;
                    end else if(((r_rd_mem_cnt[z] >= (r_wr_inst_cnt[z]+1)) && r_rdi_data_valid_tmp[z]) && ((r_rd_mem_cnt[z] >= (r_wr_data_cnt[z]+1)) && r_rdi_data_valid_tmp[z]) && ((r_rd_mem_cnt[z] >= (r_wr_addr_cnt[z]+1)) && r_rdi_data_valid_tmp[z])) begin
                        extra_data_exist_data[z]          <= 1'b0;
                    end
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if(~rst_n) begin
                    r_current_state[z]                    <= WAIT_RD_REQ;
                    r_next_state[z]                       <= WAIT_RD_REQ;
                end else begin
                    r_current_state[z]                    <= r_next_state[z];
                end
            end

            always @(*) begin
                case(r_current_state[z])
                    WAIT_RD_REQ: begin
                        r_rdi_data_valid_tmp[z]           = 1'b0;

                        if((rdi_iqsid_new == z) && r_rdi_iqsid_can_send && rdi_addr_valid) begin
                            if((r_rd_mem_cnt[z] <= r_wr_inst_cnt[z]) && ((r_rd_mem_cnt[z] <= r_wr_data_cnt[z]) && extra_data_exist_data[z]) && ((r_rd_mem_cnt[z] <= r_wr_addr_cnt[z])  && extra_addr_exist_data[z])) begin    //instruction/data/address memory all have data
                                r_rdi_data_valid_tmp[z]   = 1'b1;
                                r_rdi_data_tmp[z]         = {r_addr[z][rdi_addr], r_data[z][rdi_addr], r_inst[z][rdi_addr]};
                            end else begin
                                r_rdi_data_valid_tmp[z]   = 1'b0;
                                //when rdi_addr_valid=1, but memory is not ready, need wait
                                r_next_state[z]           = WAIT_SEND;
                            end
                        end
                    end
    
                    WAIT_SEND: begin
                        //when extra data/addr data is ready
                        if((r_rd_mem_cnt[z] <= r_wr_inst_cnt[z]+1) && ((r_rd_mem_cnt[z] <= r_wr_data_cnt[z]+1) && extra_data_exist_data[z]) && ((r_rd_mem_cnt[z] <= r_wr_addr_cnt[z]+1)  && extra_addr_exist_data[z])) begin    //instruction/data/address memory all have data
                            r_rdi_data_valid_tmp[z]       = 1'b1;
                            r_rdi_data_tmp[z]             = {r_addr[z][rdi_addr], r_data[z][rdi_addr], r_inst[z][rdi_addr]};
                            r_next_state[z]               = WAIT_RD_REQ;
                        end
                    end
    
                    default: begin
                        r_rdi_data_valid_tmp[z]           = 1'b0;
                        r_rdi_data_tmp[z]                 = {r_addr[z][rdi_addr], r_data[z][rdi_addr], r_inst[z][rdi_addr]};
                        r_next_state[z]                   = WAIT_SEND;
                    end
                endcase
            end




        end else if(EXTRA_DATA) begin    //need wait extra data
            //confirm whether extra data is empty
            always @(posedge clk or negedge rst_n) begin
                if(~rst_n) begin
                    extra_data_exist_data[z]              <= 1'b0;
                    extra_addr_exist_data[z]              <= 1'b0;
                end else begin
                    if(wrd_start && (wrd_iqsid == z)) begin
                        extra_data_exist_data[z]          <= 1'b1;
                    end else if((r_rd_mem_cnt[z] <= (r_wr_inst_cnt[z]+1)) && (r_rd_mem_cnt[z] >= (r_wr_data_cnt[z]+1))) begin
                        extra_data_exist_data[z]          <= 1'b0;
                    end
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if(~rst_n) begin
                    r_current_state[z]                    <= WAIT_RD_REQ;
                    r_next_state[z]                       <= WAIT_RD_REQ;
                end else begin
                    r_current_state[z]                    <= r_next_state[z];
                end
            end

            always @(*) begin
                case(r_current_state[z])
                    WAIT_RD_REQ: begin
                        r_rdi_data_valid_tmp[z]           = 1'b0;

                        if((rdi_iqsid_new == z) && r_rdi_iqsid_can_send && rdi_addr_valid)  begin
                            if((r_rd_mem_cnt[z] <= r_wr_inst_cnt[z]) && ((r_rd_mem_cnt[z] <= r_wr_data_cnt[z]) && extra_data_exist_data[z])) begin    //instruction/data memory all have data
                                r_rdi_data_valid_tmp[z]   = 1'b1;
                                r_rdi_data_tmp[z]         = {r_data[z][rdi_addr], r_inst[z][rdi_addr]};
                            end else begin
                                r_rdi_data_valid_tmp[z]   = 1'b0;
                                //when rdi_addr_valid=1, but memory is not ready, need wait
                                r_next_state[z]           = WAIT_SEND;
                            end
                        end
                    end
    
                    WAIT_SEND: begin
                        if((r_rd_mem_cnt[z] <= r_wr_inst_cnt[z]) && ((r_rd_mem_cnt[z] <= r_wr_data_cnt[z]) && extra_data_exist_data[z])) begin    //instruction/data memory all have data
                            r_rdi_data_valid_tmp[z]       = 1'b1;
                            r_rdi_data_tmp[z]             = {r_data[z][rdi_addr], r_inst[z][rdi_addr]};
                            r_next_state[z]               = WAIT_RD_REQ;
                        end
                    end
    
                    default: begin
                        r_rdi_data_valid_tmp[z]           = 1'b0;
                        r_rdi_data_tmp[z]                 = {r_data[z][rdi_addr], r_inst[z][rdi_addr]};
                        r_next_state[z]                   = WAIT_SEND;
                    end
                endcase
            end
        end else if(EXTRA_ADDR) begin    //need wait extra address
            //confirm whether extra address is empty
            always @(posedge clk or negedge rst_n) begin
                if(~rst_n) begin
                    extra_addr_exist_data[z]              <= 1'b0;
                    extra_data_exist_data[z]              <= 1'b0;
                end else begin
                    if(wra_start && (wra_iqsid == z)) begin
                        extra_addr_exist_data[z]          <= 1'b1;
                    end else if((r_rd_mem_cnt[z] >= (r_wr_inst_cnt[z]+1)) && (r_rd_mem_cnt[z] >= (r_wr_addr_cnt[z]+1))) begin
                        extra_addr_exist_data[z]          <= 1'b0;
                    end
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if(~rst_n) begin
                    r_current_state[z]                    <= WAIT_RD_REQ;
                    r_next_state[z]                       <= WAIT_RD_REQ;
                end else begin
                    r_current_state[z]                    <= r_next_state[z];
                end
            end

            always @(*) begin
                case(r_current_state[z])
                    WAIT_RD_REQ: begin
                        r_rdi_data_valid_tmp[z]           = 1'b0;

                        if((rdi_iqsid_new == z) && r_rdi_iqsid_can_send && rdi_addr_valid) begin
                            if((r_rd_mem_cnt[z] <= r_wr_inst_cnt[z]) && ((r_rd_mem_cnt[z] <= r_wr_addr_cnt[z]) && extra_addr_exist_data[z])) begin    //instruction/address memory all have data
                                r_rdi_data_valid_tmp[z]   = 1'b1;
                                r_rdi_data_tmp[z]         = {r_addr[z][rdi_addr], r_inst[z][rdi_addr]};
                            end else begin
                                r_rdi_data_valid_tmp[z]   = 1'b0;
                                //when rdi_addr_valid=1, but memory is not ready, need wait
                                r_next_state[z]           = WAIT_SEND;
                            end
                        end
                    end
    
                    WAIT_SEND: begin
                            if((r_rd_mem_cnt[z] <= r_wr_inst_cnt[z]) && ((r_rd_mem_cnt[z] <= r_wr_addr_cnt[z]) && extra_addr_exist_data[z])) begin    //instruction/address memory all have data
                            r_rdi_data_valid_tmp[z]       = 1'b1;
                            r_rdi_data_tmp[z]             = {r_addr[z][rdi_addr], r_inst[z][rdi_addr]};
                            r_next_state[z]               = WAIT_RD_REQ;
                        end
                    end
    
                    default: begin
                        r_rdi_data_valid_tmp[z]           = 1'b0;
                        r_rdi_data_tmp[z]                 = {r_addr[z][rdi_addr], r_inst[z][rdi_addr]};
                        r_next_state[z]                   = WAIT_SEND;
                    end
                endcase
            end
        end else begin    //!EXTRA_ADDR && !EXTRA_DATA    //don't need wait extra address and extra data
            always @(posedge clk) begin
                extra_data_exist_data[z]                  <= 1'b0;
                extra_addr_exist_data[z]                  <= 1'b0;
                r_current_state[z]                        <= WAIT_RD_REQ;
                r_next_state[z]                           <= WAIT_RD_REQ;
            end

            always @(*) begin
                if((rdi_iqsid_new == z) && r_rdi_iqsid_can_send) begin
                    //rd amount <= wr amount
                    if((r_rd_mem_cnt[z] <= (r_wr_inst_cnt[z]+1)) && rdi_addr_valid) begin
                        r_rdi_data_valid_tmp[z]           = 1'b1;
                        r_rdi_data_tmp[z]                 = r_inst[z][rdi_addr];
                    end else begin
                        r_rdi_data_valid_tmp[z]           = 1'b0;
                    end
                end
            end
        end
    end
endgenerate

endmodule

//==========================================================================
// Project   : Common Delay Align Module
// File      : delay_align.v
// Author    : sunny
// Created   : 2025-11-24
// Description:
//   - Generic, parameterizable delay alignment module in SystemVerilog style
//   - Implements a simple shift-register pipeline with selectable tap
//
// Parameters:
//   WIDTH     : data width
//   MAX_DELAY : maximum delay in cycles (0..MAX_DELAY)
//
// Notes:
//   - i_delay_cfg is the number of cycles between input sampling
//     and the selected output tap (0..MAX_DELAY).
//==========================================================================

`timescale 1ns/1ps

module delay_align_8to1 #(
    parameter int WIDTH     = 32,
    parameter int MAX_DELAY = 15
) (
    input  wire                         i_clk,
    input  wire                         i_rst_n,

    // Data to be delayed
    input  wire [WIDTH-1:0]             i_data,

    // Delay configuration: 0..MAX_DELAY cycles
    input  wire [$clog2(MAX_DELAY+1)-1:0] i_delay_cfg,

    // Delayed output
    output reg  [WIDTH-1:0]             o_data
);

    // Simple shift-register pipeline: stage 0..MAX_DELAY
    reg [WIDTH-1:0] data_pipe [0:MAX_DELAY];

    integer idx;

    // Sequential pipeline
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (idx = 0; idx <= MAX_DELAY; idx = idx + 1) begin
                data_pipe[idx] <= {WIDTH{1'b0}};
            end
        end else begin
            // Stage 0 captures new input each cycle
            data_pipe[0] <= i_data;

            // Propagate through pipeline
            for (idx = 0; idx < MAX_DELAY; idx = idx + 1) begin
                data_pipe[idx+1] <= data_pipe[idx];
            end
        end
    end

    // Select tap according to delay configuration
    always @(*) begin
        o_data = data_pipe[i_delay_cfg];
    end

endmodule

`timescale 1ns / 1ps
module bank_sram #(
    parameter DATA_WIDTH = 128,                    // Data bus width
    parameter MEMORY_DEPTH = 256,                  // Memory depth in words
    parameter ADDR_WIDTH = $clog2(MEMORY_DEPTH)    // Address width
)(
    // Clock and reset
    input                      clk,          // Clock signal
    
    // Port A - Write port
    input                      ena,          // Write enable
    input  [ADDR_WIDTH-1:0]    addra,        // Write address
    input  [DATA_WIDTH-1:0]    dina,         // Write data
    input  [(DATA_WIDTH/8)-1:0] wea,         // Write byte enable
    
    // Port B - Read port
    input                      enb,          // Read enable  
    input  [ADDR_WIDTH-1:0]    addrb,        // Read address
    output [DATA_WIDTH-1:0]    doutb         // Read data
);

    // =========================================================================
    // Memory Declaration
    // =========================================================================
    (*ram_style = "block"*) reg [DATA_WIDTH-1:0] memory_array [0:MEMORY_DEPTH-1];

    reg [DATA_WIDTH-1:0] doutb_tmp;
    // =========================================================================
    // Write Operation (Port A)
    // =========================================================================
    integer byte_idx;
    always @(posedge clk) begin
        if (ena) begin
            // Byte-enabled write operation
            for (byte_idx = 0; byte_idx < (DATA_WIDTH/8); byte_idx = byte_idx + 1) begin
                if (wea[byte_idx]) begin
                    memory_array[addra][(byte_idx*8)+:8] <= dina[(byte_idx*8)+:8];
                end
            end
        end
    end

    // =========================================================================
    // Read Operation (Port B)  
    // =========================================================================
    always @(posedge clk) begin
        if (enb) begin
            doutb_tmp <= memory_array[addrb];
        end
    end
    assign doutb = doutb_tmp;

endmodule
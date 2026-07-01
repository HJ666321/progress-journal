/*****************************************************************************
** Project  :  AIACC NPU                                                     **
******************************************************************************
**                                      **                                  **
** File name:  OPR.sv                     **             [Company]            **
** Designer :  [Designer Name]            **  [Division]                      **
**                                      **                                  **
******************************************************************************
******************************************************************************
**                                                                          **
** Module Description:                                                      **
**                                                                          **
** Input Pipeline Register (OPR) - VOUT0 Module                            **
**                                                                          **
** This module implements a pipeline register that delays the input data   **
** by one clock cycle when the control signal is valid.                    **
**                                                                          **
** Function:                                                               **
**   - When CRU-VOUT0[0] (vld) = 1:                                        **
**     DR-VOUT0-D <= DVR-VOUT0-S (one cycle delay)                         **
**   - When CRU-VOUT0[0] (vld) = 0:                                        **
**     DR-VOUT0-D holds previous value (no update)                         **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
** Hierarchy:                                                               **
**                                                                          **
** SMC -> OPR (VOUT0)                                                      **
**                                                                          **
******************************************************************************
******************************************************************************
**                                                                          **
**   Revision        Date            By               Reason                **
** ------------   ------------   ------------      ------------             **
**     1.0                                           Creation               **
**                                                                          **
******************************************************************************
****************************************************************************** 
** This file has been provided pursuant to a License Agreement containing   **
** restrictions on its use. This data contains valuable trade secrets       **
** and proprietary information of [Company] and is protected                **
*****************************************************************************/
// $Revision: 1.0 $

`timescale 1ns / 1ps

module OPR #(
    parameter SMC_ID = 5'd0
)(
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // SMC ID
    input  wire [4:0]  i_smc_id,
    
    // Control Register Upstream (CRU-VOUT0)
    // Bit 0: vld - instruction valid
    input  wire        cru_vout0,
    
    // Data Vector Register Source (DVR-VOUT0-S)
    input  wire [127:0] dvr_vout0_s,
    
    // Data Register Output (DR-VOUT0-D)
    output reg  [127:0] dr_vout0_d,
    
    // Control Register Upstream Output (CRU-VOUT0-O)
    output reg         cru_vout0_o
);

// ==========================================================================
// 1. Control Signal Extraction
// ==========================================================================
// Check if this SMC is selected and instruction is valid
wire w_cru_vout0_vld = (i_smc_id == SMC_ID) && cru_vout0;

// ==========================================================================
// 2. Pipeline Register Logic
// ==========================================================================
// When CRU-VOUT0 is valid, output DVR-VOUT0-S with one cycle delay
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dr_vout0_d <= 128'b0;
    end else begin
        if (w_cru_vout0_vld) begin
            dr_vout0_d <= dvr_vout0_s;  // One cycle delay
        end
        // If not valid, hold previous value (no update)
    end
end

// ==========================================================================
// 3. CRU Output (Pass through with optional pipeline)
// ==========================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cru_vout0_o <= 1'b0;
    end else begin
        cru_vout0_o <= cru_vout0;  // Pass through CRU input
    end
end

endmodule

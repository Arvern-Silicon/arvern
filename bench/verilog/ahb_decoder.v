//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    ahb_decoder
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : ahb_decoder.v
// Module Description : Behavioural AHB address decoder for the testbench.
//----------------------------------------------------------------------------

module  ahb_decoder #(

// PARAMETERs
//======================================
    parameter         ROM_SIZE     = 8*1024,                // Size of the memory instance (in Bytes)
    parameter         SRAM_X_SIZE  = 8*1024,                // Size of the memory instance (in Bytes)
    parameter         SRAM_NX_SIZE = 8*1024                 // Size of the memory instance (in Bytes)
) (

// DECODER INTERFACES
    input  wire [31:0] decoder_addr_i,
    output wire  [7:0] decoder_1hot_o
);


//=============================================================================
// AHB DECODER
//=============================================================================

assign decoder_1hot_o[0]  = (decoder_addr_i>=32'h20000000) & (decoder_addr_i<(32'h20000000+ROM_SIZE    )); //   ROM/FLASH
assign decoder_1hot_o[1]  = (decoder_addr_i>=32'h80000000) & (decoder_addr_i<(32'h80000000+SRAM_X_SIZE )); //   Executable SRAM
assign decoder_1hot_o[2]  = (decoder_addr_i>=32'h81000000) & (decoder_addr_i<(32'h81000000+SRAM_NX_SIZE)); //   Non-executable SRAM
assign decoder_1hot_o[3]  = (decoder_addr_i>=32'h10040000) & (decoder_addr_i<(32'h10040080             )); //   128B AHB PERIPH #0
assign decoder_1hot_o[4]  = (decoder_addr_i>=32'h10041000) & (decoder_addr_i<(32'h10041080             )); //   128B AHB PERIPH #1
assign decoder_1hot_o[5]  = (decoder_addr_i>=32'h10042000) & (decoder_addr_i<(32'h10042080             )); //   128B AHB PERIPH #2
assign decoder_1hot_o[6]  = (decoder_addr_i>=32'h0C000000) & (decoder_addr_i<(32'h0C400000             )); //   4MB AHB PLIC (SiFive/QEMU-virt convention)
assign decoder_1hot_o[7]  = (decoder_addr_i>=32'h02000000) & (decoder_addr_i<(32'h02010000             )); //  64KB AHB ACLINT (SiFive CLINT-compatible base)


endmodule

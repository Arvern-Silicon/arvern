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

`include "timescale.v"

module  ahb_decoder #(

// PARAMETERs
//======================================
    parameter         ROM_SIZE     = 8*1024,                // Size of the memory instance (in Bytes)
    parameter         SRAM_X_SIZE  = 8*1024,                // Size of the memory instance (in Bytes)
    parameter         SRAM_NX_SIZE = 8*1024,                // Size of the memory instance (in Bytes)
    parameter         SRAM_LO_X_SIZE = 128                  // Size of the memory instance (in Bytes)
) (

// DECODER INTERFACES
    input  wire [31:0] decoder_addr_i,
    input  wire        sram_x_alias_en_i,                   // Map every otherwise-unmapped address >= 0x1000 onto the executable SRAM
    output wire  [8:0] decoder_1hot_o
);


//=============================================================================
// AHB DECODER
//=============================================================================

// Executable SRAM alias (test-controlled, off by default): with sram_x_alias_en_i
// set, any address that selects no slave and lies outside the low 4 KB window
// reaches the executable SRAM, which decodes only its low address bits. Address-walk
// tests use it to run code and access data at arbitrary high addresses.
wire         sram_x_alias_hit = sram_x_alias_en_i & (decoder_addr_i>=32'h00001000) & ~(|decoder_1hot_o[8:3]) &
                                ~((decoder_addr_i>=32'h20000000) & (decoder_addr_i<(32'h20000000+ROM_SIZE   ))) &
                                ~((decoder_addr_i>=32'h80000000) & (decoder_addr_i<(32'h80000000+SRAM_X_SIZE)));

// Bits [2:0] are the executable slaves, in the order the executable interconnect
// expects them (ahb_bus_system.v passes decoder_1hot_o[2:0] to its s_x port).
assign decoder_1hot_o[0]  = (decoder_addr_i>=32'h20000000) & (decoder_addr_i<(32'h20000000+ROM_SIZE      )); //   ROM/FLASH
assign decoder_1hot_o[1]  = (decoder_addr_i>=32'h80000000) & (decoder_addr_i<(32'h80000000+SRAM_X_SIZE   )) | //   Executable SRAM
                            sram_x_alias_hit;                                                                   //   (+ alias, see below)
assign decoder_1hot_o[2]  =                                  (decoder_addr_i<(32'h00000000+SRAM_LO_X_SIZE)); //   Executable SRAM at address 0 (base is 0, so no lower bound)
assign decoder_1hot_o[3]  = (decoder_addr_i>=32'h81000000) & (decoder_addr_i<(32'h81000000+SRAM_NX_SIZE  )); //   Non-executable SRAM
assign decoder_1hot_o[4]  = (decoder_addr_i>=32'h10040000) & (decoder_addr_i<(32'h10040080               )); //   128B AHB PERIPH #0
assign decoder_1hot_o[5]  = (decoder_addr_i>=32'h10041000) & (decoder_addr_i<(32'h10041080               )); //   128B AHB PERIPH #1
assign decoder_1hot_o[6]  = (decoder_addr_i>=32'h10042000) & (decoder_addr_i<(32'h10042080               )); //   128B AHB PERIPH #2
assign decoder_1hot_o[7]  = (decoder_addr_i>=32'h0C000000) & (decoder_addr_i<(32'h0C400000               )); //   4MB AHB PLIC (SiFive/QEMU-virt convention)
assign decoder_1hot_o[8]  = (decoder_addr_i>=32'h02000000) & (decoder_addr_i<(32'h02010000               )); //  64KB AHB ACLINT (SiFive CLINT-compatible base)


endmodule

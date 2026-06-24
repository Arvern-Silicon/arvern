//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    probes_mem
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : probes_mem.v
// Module Description : Hierarchical probes into the ROM and SRAM models.
//----------------------------------------------------------------------------

module  probes_rom;

    // ROM probes
    wire [31:0] rom_0    = ahb_bus_system_inst.rom_inst0.mem[0];   // 0x20000000
    wire [31:0] rom_1    = ahb_bus_system_inst.rom_inst0.mem[1];   // 0x20000004
    wire [31:0] rom_2    = ahb_bus_system_inst.rom_inst0.mem[2];   // 0x20000008
    wire [31:0] rom_3    = ahb_bus_system_inst.rom_inst0.mem[3];   // 0x2000000C
    wire [31:0] rom_4    = ahb_bus_system_inst.rom_inst0.mem[4];   // 0x20000010
    wire [31:0] rom_5    = ahb_bus_system_inst.rom_inst0.mem[5];   // 0x20000014
    wire [31:0] rom_6    = ahb_bus_system_inst.rom_inst0.mem[6];   // 0x20000018
    wire [31:0] rom_7    = ahb_bus_system_inst.rom_inst0.mem[7];   // 0x2000001C
    wire [31:0] rom_8    = ahb_bus_system_inst.rom_inst0.mem[8];   // 0x20000020
    wire [31:0] rom_9    = ahb_bus_system_inst.rom_inst0.mem[9];   // 0x20000024
    wire [31:0] rom_A    = ahb_bus_system_inst.rom_inst0.mem[10];  // 0x20000028
    wire [31:0] rom_B    = ahb_bus_system_inst.rom_inst0.mem[11];  // 0x2000002C
    wire [31:0] rom_C    = ahb_bus_system_inst.rom_inst0.mem[12];  // 0x20000030
    wire [31:0] rom_D    = ahb_bus_system_inst.rom_inst0.mem[13];  // 0x20000034
    wire [31:0] rom_E    = ahb_bus_system_inst.rom_inst0.mem[14];  // 0x20000038
    wire [31:0] rom_F    = ahb_bus_system_inst.rom_inst0.mem[15];  // 0x2000003C

endmodule

module  probes_sram;

    // SRAM probes
    wire [31:0] sram_0   = ahb_bus_system_inst.sram_x_inst.mem[0];  // 0x80000000
    wire [31:0] sram_1   = ahb_bus_system_inst.sram_x_inst.mem[1];  // 0x80000004
    wire [31:0] sram_2   = ahb_bus_system_inst.sram_x_inst.mem[2];  // 0x80000008
    wire [31:0] sram_3   = ahb_bus_system_inst.sram_x_inst.mem[3];  // 0x8000000C
    wire [31:0] sram_4   = ahb_bus_system_inst.sram_x_inst.mem[4];  // 0x80000010
    wire [31:0] sram_5   = ahb_bus_system_inst.sram_x_inst.mem[5];  // 0x80000014
    wire [31:0] sram_6   = ahb_bus_system_inst.sram_x_inst.mem[6];  // 0x80000018
    wire [31:0] sram_7   = ahb_bus_system_inst.sram_x_inst.mem[7];  // 0x8000001C
    wire [31:0] sram_8   = ahb_bus_system_inst.sram_x_inst.mem[8];  // 0x80000020
    wire [31:0] sram_9   = ahb_bus_system_inst.sram_x_inst.mem[9];  // 0x80000024
    wire [31:0] sram_A   = ahb_bus_system_inst.sram_x_inst.mem[10]; // 0x80000028
    wire [31:0] sram_B   = ahb_bus_system_inst.sram_x_inst.mem[11]; // 0x8000002C
    wire [31:0] sram_C   = ahb_bus_system_inst.sram_x_inst.mem[12]; // 0x80000030
    wire [31:0] sram_D   = ahb_bus_system_inst.sram_x_inst.mem[13]; // 0x80000034
    wire [31:0] sram_E   = ahb_bus_system_inst.sram_x_inst.mem[14]; // 0x80000038
    wire [31:0] sram_F   = ahb_bus_system_inst.sram_x_inst.mem[15]; // 0x8000003C

endmodule

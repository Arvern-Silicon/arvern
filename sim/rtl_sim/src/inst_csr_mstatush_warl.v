//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_mstatush_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MSTATUSH WARL - only MDT (bit 10) is implemented
//   MDT is the Smdbltrp M-mode double-trap bit: WARL, software writable, and
//   it RESETS TO 1. Every other bit reads 0, and no access may trap.
//   Write, zero and set paths are checked separately.
//
//   Scratchpad: 0x00 trap_count, 0x04 mcause, 0x0C reset value,
//               0x10 after all-ones, 0x14 after zero, 0x18 after csrrs
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] rb;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" ===============================================");
    $display("|  MSTATUSH WARL: every bit reads 0             |");
    $display(" ===============================================");

    @(probes_cpu.x31 == 32'h22222222);
    repeat(3) @(posedge free_clk);

    rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
    $display("");
    $display("--- reset value -> 0x%h (MDT=1: protection by default) ---", rb);
    check_mem_value(`SPAD(32'h0C), 32'h00000400);

    rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
    $display("--- csrw 0xFFFFFFFF -> reads 0x%h (only MDT sticks) ---", rb);
    check_mem_value(`SPAD(32'h10), 32'h00000400);

    rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];
    $display("--- csrw 0x00000000 -> reads 0x%h (MDT clears) ---", rb);
    check_mem_value(`SPAD(32'h14), 32'h00000000);

    rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
    $display("--- csrs 0xFFFFFFFF -> reads 0x%h ---", rb);
    check_mem_value(`SPAD(32'h18), 32'h00000400);

    $display("");
    $display("--- mstatush is a legal M CSR: no access may trap ---");
    check_mem_value(`SPAD(32'h00), 32'h00000000);
    check_mem_value(`SPAD(32'h04), 32'h00000000);

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

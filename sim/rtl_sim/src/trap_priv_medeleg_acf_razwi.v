//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_medeleg_acf_razwi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MEDELEG ACF - medeleg[5]/[7] RAZ/WI with S-mode PRESENT
//   Causes 5 and 7 are RESERVED and never raised; a data bus
//   error is an RNMI, which is M-mode only and not delegable. So those two
//   bits must not stick, while their neighbours (4 and 6, the misaligned
//   causes) must -- that is what makes this a real check.
//
//   Scratchpad: 0x00 trap_count, 0x04 mcause,
//               0x20 medeleg after all-ones, 0x24 medeleg after zero
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// bits 0..9 implemented, minus bit 5 (load acf) and bit 7 (store acf)
// medeleg[5] / [7] track whether causes 5 and 7 have a producer. With PMP they are
// ordinary delegation bits; without it nothing can raise those causes -- a data-bus error
// is an RNMI, and RNMIs are M-only -- so they read 0 like any other unimplementable cause.
localparam [31:0] MEDELEG_EXPECTED = (PMP_NR != 0) ? 32'h000003FF : 32'h0000035F;

reg [31:0] rb;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" ===============================================");
    $display("|  MEDELEG ACF: bits 5 and 7 must be RAZ/WI     |");
    $display(" ===============================================");

    @(probes_cpu.x31 == 32'h22222222);
    repeat(3) @(posedge free_clk);

    rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
    $display("");
    $display("--- medeleg after writing 0xFFFFFFFF ---");
    $display("readback = 0x%h   bit5(ld acf)=%0d  bit7(st acf)=%0d", rb, rb[5], rb[7]);
    $display("neighbours that MUST stick: bit4(ld misalign)=%0d  bit6(st misalign)=%0d",
             rb[4], rb[6]);
    check_mem_value(`SPAD(32'h20), MEDELEG_EXPECTED);

    if (rb[4] !== 1'b1 || rb[6] !== 1'b1) begin
       $display("ERROR: the misaligned causes must still be delegable -- a readback of");
       $display("       0 for every bit would pass a bit5/bit7 check vacuously %t ns", $time);
       error = error + 1;
    end

    @(probes_cpu.x31 == 32'hdeadbeef);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- medeleg after writing 0x00000000 ---");
    check_mem_value(`SPAD(32'h24), 32'h00000000);

    $display("");
    $display("--- no trap may be taken: medeleg is WARL, not illegal ---");
    check_mem_value(`SPAD(32'h00), 32'h00000000);
    check_mem_value(`SPAD(32'h04), 32'h00000000);

    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

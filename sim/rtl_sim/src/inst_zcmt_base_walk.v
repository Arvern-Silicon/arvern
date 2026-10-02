//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcmt_base_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CM.JT / CM.JALT jump-table base walk over bits 16..31 -- see
//              inst_zcmt_base_walk.s. Arms the bench executable-SRAM alias,
//              then checks the firmware's verdict: 64 landings, 128 compares,
//              no mismatch, no trap.
//----------------------------------------------------------------------------

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31==32'h11111111);
    ahb_bus_system_inst.sram_x_alias_en = 1'b1;

    @(probes_cpu.x31==32'hdeadbeef);
    ahb_bus_system_inst.sram_x_alias_en = 1'b0;
    random_irq_enable = 0;
    check_cpu_reg( 8, 32'd64);          // s0: landings (32 bases x 2)
    check_cpu_reg(20, 32'd128);         // s4: compares
    check_cpu_reg( 9, 32'd0);           // s1: mismatches
    check_cpu_reg(18, 32'd0);           // s2: first failing code
    check_cpu_reg(24, 32'd0);           // s8: traps
    check_cpu_reg(25, 32'd0);           // s9: first trap mcause
    check_cpu_reg(26, 32'd0);           // s10: first trap mepc

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

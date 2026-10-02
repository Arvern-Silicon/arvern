//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_marv_addr_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MARV ADDRESS WALK -- see trap_marv_addr_walk.s. Phase A runs
//              with the executable-SRAM alias armed (marv_epc walks PC bits
//              12..31), phase B with it disarmed (marv_eaddr walks address
//              bits over unmapped space, loads and stores). The firmware checks
//              every RNMI and reports a verdict in registers.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);
    error_on_exception = 0;             // 97 expected data-bus errors

    @(probes_cpu.x31==32'h11111111);
    ahb_bus_system_inst.sram_x_alias_en = 1'b1;
    $display("PHASE A: alias armed, stub at (1<<k)|0x800 %t ns", $time);

    @(probes_cpu.x31==32'h22222222);
    ahb_bus_system_inst.sram_x_alias_en = 1'b0;
    $display("PHASE B: alias disarmed, lw/sw at unmapped addresses %t ns", $time);

    @(probes_cpu.x31==32'hdeadbeef);
    random_irq_enable = 0;
    check_cpu_reg( 8, 32'd97);          // s0: rounds (20 phase A + 77 phase B)
    check_cpu_reg( 9, 32'd0);           // s1: errors
    check_cpu_reg( 7, 32'h00000000);    // t2: first failing address / stub address
    check_cpu_reg(18, 32'd0);           // s2: rounds without an RNMI
    check_cpu_reg(19, 32'd97);          // s3: RNMIs delivered, exactly one per access

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

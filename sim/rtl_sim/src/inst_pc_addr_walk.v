//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_pc_addr_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PC ADDRESS WALK -- see inst_pc_addr_walk.s. Arms the bench
//              executable-SRAM alias, then checks the firmware's verdict.
//----------------------------------------------------------------------------

initial begin
    @(posedge free_clk);
    @(posedge hresetn);
    error_on_exception = 0;             // 40 expected ecalls

    @(probes_cpu.x31==32'h11111111);
    ahb_bus_system_inst.sram_x_alias_en = 1'b1;

    @(probes_cpu.x31==32'hdeadbeef);
    ahb_bus_system_inst.sram_x_alias_en = 1'b0;
    check_cpu_reg( 8, 32'd40);          // s0: rounds
    check_cpu_reg( 9, 32'd0);           // s1: errors
    check_cpu_reg( 7, 32'h00000000);    // t2: first failing address

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

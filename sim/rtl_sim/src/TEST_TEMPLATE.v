//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      TEST_TEMPLATE
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Skeleton template for new tests (intentionally NOT registered in run_config.json so it never runs in regression).
//----------------------------------------------------------------------------

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // Reset peripherals
    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    // Wait for first sync point and check init values
    @(probes_cpu.x31==32'hFFFFFFFF);
    check_cpu_reg(1, 32'hFFFFFFFF);
    // ...

    // Wait for final sync and check results
    @(probes_cpu.x31==32'hdeadbeef);
    random_irq_enable = 0;       // Disable random IRQs before final checks
    check_cpu_reg(1, 32'h0000000A);
    check_cpu_reg(3, 32'h0000001E);
    // ...

    // End of test
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;           // Signals the testbench harness to finish
end

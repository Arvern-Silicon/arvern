//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_platform_clear_race
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: a platform IRQ pending bit cleared through mip / sip right
// after its level source drops must clear (see the .s header).
//----------------------------------------------------------------------------
// Level device: line high while periph #0 register 1 != register 0
reg dev_en = 1'b0;
always @(*)
    if (dev_en)
        irq_platform = {15'h0000, periph0_reg_01_out != periph0_reg_00_out};

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    dev_en = 1'b1;

    @(probes_cpu.x31==32'h11111111);
    $display("");
    $display(" ====================================================================");
    $display("|   PLATFORM IRQ: PENDING CLEAR RIGHT AFTER THE SOURCE DROPS          |");
    $display(" ====================================================================");

    @(probes_cpu.x31==32'hdeadbeef);
    repeat(5) @(posedge free_clk);
    dev_en       = 1'b0;
    irq_platform = 16'h0000;

    check_cpu_reg(8, (SU_MODE_EN ? 32'd32 : 32'd16));   // trials run
    check_cpu_reg(9, 32'd0);                              // clears refused

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

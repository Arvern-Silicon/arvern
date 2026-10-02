//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_wfi_halt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG HALTREQ during WFI sleep over the DMI bus (Sdext)
//   Verifies a debugger can halt a WFI-sleeping (clock-gated) hart over the DMI
//   bus -- NOT via a backdoor. The DMI helper tasks are driven from the always-on
//   free_clk, so a pending DMI request ungates the core clock (arvern.v
//   dmi_keepalive) and dm_halt/dm_resume reach the Debug Module even while the
//   hart is WFI clock-gated. The clock-keep-alive assertions are preserved:
//     - dut_hclk_en (= hclk_en_o) observed LOW during WFI sleep,
//     - entry into Debug Mode after dm_halt (over DMI),
//     - dut_hclk_en HIGH again while halted (clock kept alive for the DM),
//     - GPRs frozen while halted.
//   The primary spec assertion (RISC-V Debug Spec, Sdext): a halt during WFI
//   completes the WFI, so dpc = WFI+4 and resume proceeds PAST the WFI. No
//   interrupt is enabled in the firmware, so the hart reaching the post-WFI
//   marker on its own proves dpc pointed past the WFI (not a re-executed WFI).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

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

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG WFI HALT: halt request wakes a clock-gated WFI-sleeping hart |");
    $display(" ====================================================================");

    // Firmware is about to execute WFI.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware about to sleep (x31=0x11111111) %t ns", $time);

    // Wait for the core to gate its clock (WFI sleep, AHB drained).
    to = 0;
    while ((dut_hclk_en !== 1'b0) && (to < 2000)) begin @(posedge free_clk); to = to + 1; end
    if (dut_hclk_en !== 1'b0) begin
        $display("ERROR: core never gated its clock during WFI (dut_hclk_en stayed high) %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  core asleep, clock gated (dut_hclk_en=0, %0d cyc) %t ns", to, $time);
    end

    // --- halt the sleeping hart over the DMI bus ---
    // dm_halt polls dmstatus.allhalted internally and bumps `error` on timeout.
    // The DMI tasks run on the always-on free_clk, so the pending request ungates
    // the gated core clock and reaches the DM even though the hart is asleep.
    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: sleeping hart did NOT wake into Debug Mode on DMI haltreq %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  WFI-sleeping hart entered Debug Mode over DMI %t ns", $time);
    end

    // Clock must be alive again while halted (else the DM could never talk to it).
    repeat (5) @(posedge free_clk);
    if (dut_hclk_en !== 1'b1) begin
        $display("ERROR: clock not kept alive in Debug Mode (dut_hclk_en=%b) %t ns", dut_hclk_en, $time);
        error = error + 1;
    end else begin
        $display("PASS:  clock kept alive in Debug Mode (dut_hclk_en=1) %t ns", $time);
    end
    if (probes_cpu.x20 !== 32'h00000000) begin
        $display("ERROR: firmware ran past WFI while halted (x20=%h) %t ns", probes_cpu.x20, $time);
        error = error + 1;
    end else begin
        $display("PASS:  GPRs frozen while halted (x20=0) %t ns", $time);
    end

    // --- resume over the DMI bus: per spec the WFI completed, so the hart
    //     proceeds PAST it. dm_resume polls dmstatus.allrunning and bumps
    //     `error` on timeout. ---
    dm_resume;
    if (dbg_debug_mode !== 1'b0) begin
        $display("ERROR: hart did NOT resume from Debug Mode %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  resumed from Debug Mode over DMI %t ns", $time);
    end

    // No interrupt is enabled: reaching the post-WFI marker proves dpc = WFI+4
    // (resume past the WFI), the spec-mandated behaviour. If dpc had pointed at
    // the WFI, the hart would re-sleep here and the run would time out.
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, 32'h0000D09E);   // proceeded past WFI on resume (dpc = WFI+4)
    check_cpu_reg(18, 32'hA5A5A5A5);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

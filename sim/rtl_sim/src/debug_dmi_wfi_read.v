//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_wfi_read
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NON-HALTING DMI access during WFI sleep (Sdext)
//   The non-halting discriminator for the DMI keepalive path. Where debug_wfi_halt
//   proves a HALTING DMI request (dm_halt) reaches a clock-gated WFI-sleeping hart,
//   this proves a NON-halting DMI access (a bare dmstatus read) also completes
//   while the hart sleeps -- and, crucially, that the access ungates the core clock
//   only for its duration: the hart stays asleep, never enters Debug Mode, never
//   runs past the WFI, and the clock RE-GATES once the request drops.
//
//   The bare dmstatus read uses no preceding dmcontrol.dmactive write on purpose:
//   the keepalive ungates on ANY pending DMI request, so a setup write would mask
//   the very behaviour under test. Note dmi_read has no internal timeout -- if it
//   ever hangs here, that is a real keepalive failure (the request never ungated
//   the clock to reach the DM), not a test bug.
//
//   The WFI wake source is a TB-driven machine-external IRQ (mie.MEIE), raised
//   only AFTER the non-halting read window, so the wake is fully controlled (no
//   race against the read).
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

    // Controlled wake only: no stray random IRQ may wake the WFI during the
    // asleep window (steps 2-6). Disable for the whole test.
    random_irq_enable = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG DMI WFI READ: non-halting DMI access while WFI clock-gated  |");
    $display(" ====================================================================");

    // 1. Firmware is about to execute WFI.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware about to sleep (x31=0x11111111) %t ns", $time);

    // 2. Wait for the core to gate its clock (WFI sleep, AHB drained).
    to = 0;
    while ((dut_hclk_en !== 1'b0) && (to < 2000)) begin @(posedge free_clk); to = to + 1; end
    if (dut_hclk_en !== 1'b0) begin
        $display("ERROR: core never gated its clock during WFI (dut_hclk_en stayed high) %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  core asleep, clock gated (dut_hclk_en=0, %0d cyc) %t ns", to, $time);
    end

    // 3. While asleep, issue a NON-halting DMI access (bare dmstatus read).
    //    dmi_read returns only when the response strobe is seen, so reaching the
    //    next line proves the access completed -- i.e. the pending request ungated
    //    the gated core clock and reached the DM.
    dmi_read(7'h11);
    $display("PASS:  non-halting DMI dmstatus read COMPLETED while hart asleep (dmstatus=%h) %t ns",
             dmi_readval, $time);
    if ((dmi_readval & 32'h00000200) !== 32'h0) begin
        $display("ERROR: dmstatus.allhalted set after non-halting read (hart should NOT be halted) %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  dmstatus.allhalted clear (read did not halt the hart) %t ns", $time);
    end

    // 4. The hart must NOT have entered Debug Mode from a non-halting access.
    if (dbg_debug_mode !== 1'b0) begin
        $display("ERROR: hart entered Debug Mode on a non-halting DMI read (dbg_debug_mode=1) %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  hart NOT in Debug Mode after non-halting read (dbg_debug_mode=0) %t ns", $time);
    end

    // 5. Key response-phase check: the access ungated the clock only for its
    //    duration. After the request drops, the hart re-evaluates WFI and the
    //    clock must RE-GATE (dut_hclk_en back to 0).
    repeat (5) @(posedge free_clk);
    to = 0;
    while ((dut_hclk_en !== 1'b0) && (to < 2000)) begin @(posedge free_clk); to = to + 1; end
    if (dut_hclk_en !== 1'b0) begin
        $display("ERROR: clock did NOT re-gate after the DMI access (dut_hclk_en stuck high) %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  clock re-gated after the access, hart still asleep (dut_hclk_en=0, %0d cyc) %t ns", to, $time);
    end

    // 6. Firmware must NOT have run past the WFI just because of the read.
    if (probes_cpu.x20 !== 32'h00000000) begin
        $display("ERROR: firmware ran past WFI due to the DMI read (x20=%h, expected 0) %t ns",
                 probes_cpu.x20, $time);
        error = error + 1;
    end else begin
        $display("PASS:  firmware still parked at WFI (x20=0) %t ns", $time);
    end

    // 7. Now wake the WFI naturally via the armed machine-external IRQ. The
    //    handler masks MEIE and returns past the WFI (mepc = WFI+4).
    repeat (3) @(posedge free_clk);
    irq_m_external = 1'b1;
    $display("Raised machine external IRQ to wake the WFI %t ns", $time);

    @(probes_cpu.x31==32'hdeadbeef);
    irq_m_external = 1'b0;              // drop the line (handler already masked MEIE)
    check_cpu_reg(20, 32'h0000D09E);   // proceeded past WFI on wake (mepc = WFI+4)
    check_cpu_reg(18, 32'hA5A5A5A5);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

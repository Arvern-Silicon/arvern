//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_priv_restore
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG HALTREQ privilege restore (Sdext)
//   Halts the hart while it executes in U-mode and proves resume restores
//   U-mode (from dcsr.prv) rather than M. The firmware's post-resume M-only CSR
//   access traps only if it is genuinely in U-mode; the M-handler then sets the
//   success flag (x23=0x600D). A broken priv-restore would resume in M, the CSR
//   access would not trap, and x23 would stay 0 (caught here).
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
    $display("|  DEBUG PRIV RESTORE: halt in U-mode, resume must return to U-mode  |");
    $display(" ====================================================================");

    // Firmware has dropped to U-mode and is spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware in U-mode, ready to halt (x31=0x11111111) %t ns", $time);

    // --- halt while in U-mode (DMI dmcontrol.haltreq) ---
    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: hart not in Debug Mode after dm_halt %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  entered Debug Mode while in U-mode %t ns", $time);
    end

    // Hold halted a while: success flag must not appear (hart frozen).
    repeat (60) @(posedge free_clk);
    if (probes_cpu.x23 !== 32'h00000000) begin
        $display("ERROR: firmware progressed while halted (x23=%h) %t ns", probes_cpu.x23, $time);
        error = error + 1;
    end

    // --- resume: privilege must be restored to U-mode (DMI dmcontrol.resumereq) ---
    dm_resume;
    if (dbg_debug_mode !== 1'b0) begin
        $display("ERROR: hart still in Debug Mode after dm_resume %t ns", $time);
        error = error + 1;
    end

    @(probes_cpu.x31==32'hdeadbeef);
    // x23=0x600D only if the post-resume M-only CSR access trapped from U-mode.
    check_cpu_reg(23, 32'h0000600D);   // privilege restored to U-mode after resume
    check_cpu_reg(22, 32'h00000000);   // the "wrong-privilege" path was never taken
    check_cpu_reg(18, 32'hA5A5A5A5);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_haltreq
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG HALTREQ (Sdext, Debug Spec 1.0 — hart-side)
//   Halts/resumes over the DMI bus (dm_halt/dm_resume) and checks the frozen-hart model:
//     - dm_halt -> hart enters Debug Mode; GPRs FROZEN while halted.
//     - dm_resume -> Debug Mode clears; execution resumes
//       at exactly dpc (each instruction runs once).
//   Correctness of resume-at-dpc is checked NOT by "did it advance" (insensitive
//   to off-by-one) but by exact loop-sum invariants the firmware computes:
//     x5  = 0x8080  (Phase A: sum 1..256 — any boundary replay/skip corrupts it)
//     x9  = 0x820   (Phase B: sum 1..64)
//     x10 = 0x299C  (Phase B: in-flight DIV drained correctly across the halt)
//   Phase A is halted at two different offsets; Phase B halt lands mid-DIV.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;     // handshake timeout counter (used inside the task)

// One external halt/resume cycle: assert haltreq, confirm Debug-Mode entry,
// confirm the GPRs are frozen for a window, then resume. Per-result correctness
// (exact sums) is checked by the caller after the relevant loop completes.
task do_halt_and_resume;
    input integer pre_cycles;     // active cycles to let the loop spin before halting
    reg    [31:0] cap5, cap9, cap10;
    begin
        repeat (pre_cycles) @(posedge free_clk);

        // --- halt (over the DMI bus: dmcontrol.haltreq -> poll allhalted) ---
        dm_halt;
        if (dbg_debug_mode !== 1'b1) begin
            $display("ERROR: hart not in Debug Mode after dm_halt %t ns", $time);
            error = error + 1;
        end

        // --- frozen check ---
        repeat (5) @(posedge free_clk);
        cap5 = probes_cpu.x05; cap9 = probes_cpu.x09; cap10 = probes_cpu.x10;
        repeat (150) @(posedge free_clk);
        if ((probes_cpu.x05 !== cap5) || (probes_cpu.x09 !== cap9) || (probes_cpu.x10 !== cap10)) begin
            $display("ERROR: GPR changed while halted (x5 %h->%h, x9 %h->%h, x10 %h->%h) %t ns",
                     cap5, probes_cpu.x05, cap9, probes_cpu.x09, cap10, probes_cpu.x10, $time);
            error = error + 1;
        end else begin
            $display("PASS:  GPRs frozen while halted %t ns", $time);
        end
        if (dbg_halted !== 1'b1) begin
            $display("ERROR: dbg_halted not asserted while in Debug Mode %t ns", $time);
            error = error + 1;
        end

        // --- resume (over the DMI bus: drop haltreq, dmcontrol.resumereq) ---
        dm_resume;
        if (dbg_debug_mode !== 1'b0) begin
            $display("ERROR: hart still in Debug Mode after dm_resume %t ns", $time);
            error = error + 1;
        end
    end
endtask

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

    //=================================================================
    // PHASE A: off-by-one detector — halt the pure add/addi loop twice
    //=================================================================
    $display("");
    $display(" ====================================================================");
    $display("|  PHASE A: halt/resume during add/addi loop (off-by-one detector)   |");
    $display(" ====================================================================");
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware in loop A (x31=0x11111111) %t ns", $time);
    do_halt_and_resume(20);    // halt early in the loop
    do_halt_and_resume(60);    // halt at a different offset

    @(probes_cpu.x31==32'h22222222);
    $display("Phase A complete (x31=0x22222222) %t ns", $time);
    check_cpu_reg(5, 32'h00008080);    // sum(1..256): off-by-one would corrupt this

    //=================================================================
    // PHASE B: multi-cycle in-flight op — halt during the DIV loop
    //=================================================================
    $display("");
    $display(" ====================================================================");
    $display("|  PHASE B: halt/resume during DIV loop (in-flight op drain)         |");
    $display(" ====================================================================");
    @(probes_cpu.x31==32'h33333333);
    $display("Firmware in loop B (x31=0x33333333) %t ns", $time);
    do_halt_and_resume(40);    // async halt lands mid-DIV

    @(probes_cpu.x31==32'h44444444);
    $display("Phase B complete (x31=0x44444444) %t ns", $time);
    check_cpu_reg(9,  32'h00000820);   // sum(1..64): off-by-one detector
    check_cpu_reg(10, 32'h0000299c);   // last quotient: DIV drained correctly across halt

    //=================================================================
    // Done
    //=================================================================
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(7, 32'hA5A5A5A5);    // sentinel marker intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

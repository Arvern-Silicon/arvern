//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_haltreq_zcmp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG HALTREQ during a Zcmp UOP sequence (Sdext)
//   A cm.push/cm.pop UOP is driven from the decode-stage micro-op sequencer
//   (unlike a DIV, which vacates ID). On an async halt mid-sequence the decode
//   stage can present a stale id_pc; if dpc latches it, resume re-executes the
//   whole cm.push. The firmware makes any such double-execution observable two
//   ways, both checked here once the loop has finished:
//     x14 = 0x820       loop sum 1..64 (replayed body pass corrupts it)
//     x11 = 0x0         final SP - initial SP (replayed push/pop unbalances it)
//   The hart is halted several times at different offsets so at least one halt
//   lands mid-UOP across the timing variants.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;     // handshake timeout counter (used inside the task)

// One external halt/resume cycle: assert haltreq, confirm Debug-Mode entry,
// confirm GPRs are frozen for a window, then resume. Final correctness (exact
// SP balance + loop sum) is checked by the caller after the loop completes.
task do_halt_and_resume;
    input integer pre_cycles;     // active cycles to let the loop spin before halting
    reg    [31:0] cap13, cap14;
    begin
        repeat (pre_cycles) @(posedge free_clk);

        // --- halt (over the DMI bus: dmcontrol.haltreq -> poll allhalted) ---
        dm_halt;
        if (dbg_debug_mode !== 1'b1) begin
            $display("ERROR: hart not in Debug Mode after dm_halt %t ns", $time);
            error = error + 1;
        end

        // --- frozen check: the accumulator/counter must not advance while halted ---
        repeat (5) @(posedge free_clk);
        cap13 = probes_cpu.x13; cap14 = probes_cpu.x14;
        repeat (60) @(posedge free_clk);
        if ((probes_cpu.x13 !== cap13) || (probes_cpu.x14 !== cap14)) begin
            $display("ERROR: GPR changed while halted (x13 %h->%h, x14 %h->%h) %t ns",
                     cap13, probes_cpu.x13, cap14, probes_cpu.x14, $time);
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
    // PHASE C: halt/resume during the cm.push/cm.pop UOP loop
    //=================================================================
    $display("");
    $display(" ====================================================================");
    $display("|  PHASE C: halt/resume during Zcmp push/pop loop (UOP drain)        |");
    $display(" ====================================================================");
    @(probes_cpu.x31==32'h55555555);
    $display("Firmware in loop C (x31=0x55555555) %t ns", $time);
    do_halt_and_resume(18);    // halt at several offsets so one lands mid-UOP
    do_halt_and_resume(33);
    do_halt_and_resume(47);

    @(probes_cpu.x31==32'h66666666);
    $display("Phase C complete (x31=0x66666666) %t ns", $time);
    check_cpu_reg(14, 32'h00000820);   // sum(1..64): replayed body pass corrupts it
    check_cpu_reg(11, 32'h00000000);   // SP balance: replayed push/pop unbalances it

    //=================================================================
    // Done
    //=================================================================
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(5, 32'hA5A5A5A5);    // sentinel marker intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

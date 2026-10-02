//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_resumereq_single_write
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ONE dmcontrol write {haltreq=0, resumereq=1} resumes the hart
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Debug Spec 1.0, dmcontrol:
//     haltreq   "Writing 0 clears the halt request bit for all currently
//                selected harts."
//     resumereq "Writing 1 causes the currently selected harts to resume once,
//                if they are halted when the write occurs. It also clears the
//                resume ack bit for those harts. resumereq is ignored if
//                haltreq is set."
//   The haltreq written in the SAME transaction is 0, so the halt request is
//   cleared and the resume request must be honoured by that one write -- no
//   separate "drop haltreq" transaction is needed (every other test issues one,
//   which is why the shared dm_resume helper is NOT used here).
//
//   ROUND 1
//     (a) halt via haltreq=1; allhalted=1; snapshot the loop counter x5.
//     (b) NEGATIVE: write haltreq=1 AND resumereq=1 -> ignored: allhalted
//         stays 1 across a polling window, allresumeack never sets, x5 frozen.
//     (c) THE CHECK: ONE write {dmactive=1, haltreq=0, resumereq=1} ->
//         allresumeack=1 then allrunning=1 within a bounded number of polls,
//         x5 advancing again.
//   ROUND 2
//     halt again, then the single write straight away (no negative step) ->
//     the single-write resume is repeatable (resumeack re-set after being
//     cleared by the request).
//   FINAL: the firmware completes its loop on its own (post-resume marker).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
integer ack_seen;
reg [31:0] x5_snap;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DMCONTROL = 7'h10;
localparam [6:0] DMI_DMSTATUS  = 7'h11;

// dmcontrol field constants
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_HALTREQ    = 32'h80000000;  // [31] haltreq
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;  // [30] resumereq
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset

// dmstatus field masks
localparam [31:0] DMS_ALLHALTED    = 32'h00000200; // [9]
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800; // [11]
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000; // [17]

// Bounded poll budget for the resume handshake (each poll is one DMI read).
localparam integer RESUME_POLLS = 20;

// Halt the hart with haltreq=1 and poll allhalted.
task halt_hart;
   input [8*8:1] tag;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: %0s hart did not halt on dmcontrol.haltreq (allhalted=0) %t ns", tag, $time);
         error = error + 1;
      end else $display("PASS:  %0s hart halted via DMI haltreq (allhalted=1, %0d polls) %t ns", tag, to, $time);
      if (dbg_debug_mode !== 1'b1) begin
         $display("ERROR: %0s dbg_debug_mode not asserted while allhalted=1 %t ns", tag, $time);
         error = error + 1;
      end
   end
endtask

// THE CHECK: one dmcontrol write {dmactive=1, haltreq=0, resumereq=1}, then
// allresumeack and allrunning must both set within RESUME_POLLS polls each,
// and the loop counter must move again.
task single_write_resume;
   input [8*8:1] tag;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);   // haltreq=0 in the SAME word

      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) && (to < RESUME_POLLS)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) begin
         $display("ERROR: %0s no allresumeack within %0d polls after the single {haltreq=0,resumereq=1} write (dmstatus=%h) %t ns",
                  tag, RESUME_POLLS, dmi_readval, $time);
         error = error + 1;
      end else $display("PASS:  %0s allresumeack set after the single {haltreq=0,resumereq=1} write (%0d polls) %t ns", tag, to, $time);

      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < RESUME_POLLS)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
         $display("ERROR: %0s hart not running within %0d polls after the single write (allrunning=0, dmstatus=%h) %t ns",
                  tag, RESUME_POLLS, dmi_readval, $time);
         error = error + 1;
      end else $display("PASS:  %0s hart running after the single write (allrunning=1, %0d polls) %t ns", tag, to, $time);
      if ((dmi_readval & DMS_ALLHALTED) !== 32'h0) begin
         $display("ERROR: %0s allhalted still 1 after the single write (dmstatus=%h) %t ns", tag, dmi_readval, $time);
         error = error + 1;
      end
      if (dbg_debug_mode !== 1'b0) begin
         $display("ERROR: %0s hart still in Debug Mode after the single write %t ns", tag, $time);
         error = error + 1;
      end

      // firmware progress: the loop is still in flight, so x5 must move
      x5_snap = probes_cpu.x05;
      repeat (40) @(posedge free_clk);
      if (probes_cpu.x05 === x5_snap) begin
         $display("ERROR: %0s loop counter x5 still frozen after the single-write resume (%h) %t ns", tag, x5_snap, $time);
         error = error + 1;
      end else $display("PASS:  %0s loop counter x5 advancing after the single-write resume (%h -> %h) %t ns", tag, x5_snap, probes_cpu.x05, $time);
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

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG RESUMEREQ SINGLE WRITE: {haltreq=0,resumereq=1} in ONE write |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);  // clear sticky havereset

    //========================================================================
    // ROUND 1 (a): halt
    //========================================================================
    halt_hart("R1");
    x5_snap = probes_cpu.x05;

    //========================================================================
    // ROUND 1 (b): NEGATIVE -- haltreq=1 AND resumereq=1 in one write is
    //   ignored: allhalted stays 1, allresumeack never sets, x5 frozen.
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ | DMC_RESUMEREQ);

    ack_seen = 0;
    for (to = 0; to < 20; to = to + 1) begin
        dmi_read(DMI_DMSTATUS);
        if ((dmi_readval & DMS_ALLRESUMEACK) !== 32'h0) ack_seen = 1;
        if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
            $display("ERROR: (b) hart LEFT halted state on {haltreq=1,resumereq=1} (dmstatus=%h, poll %0d) %t ns", dmi_readval, to, $time);
            error = error + 1;
        end
    end
    if (ack_seen) begin
        $display("ERROR: (b) allresumeack SET on resumereq written with haltreq=1 (must be ignored) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  (b) {haltreq=1,resumereq=1} ignored (no resumeack, still halted) %t ns", $time);

    if (probes_cpu.x05 !== x5_snap) begin
        $display("ERROR: (b) loop counter x5 advanced while halted (%h -> %h) %t ns", x5_snap, probes_cpu.x05, $time);
        error = error + 1;
    end else $display("PASS:  (b) loop counter x5 frozen across the ignored resume attempt (%h) %t ns", x5_snap, $time);
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: (b) hart left Debug Mode on {haltreq=1,resumereq=1} %t ns", $time);
        error = error + 1;
    end

    //========================================================================
    // ROUND 1 (c): THE CHECK -- one write {haltreq=0, resumereq=1} resumes.
    //========================================================================
    single_write_resume("R1(c)");

    //========================================================================
    // ROUND 2: halt again, single write straight away -> repeatable.
    //========================================================================
    repeat (50) @(posedge free_clk);
    halt_hart("R2");
    x5_snap = probes_cpu.x05;
    repeat (20) @(posedge free_clk);
    if (probes_cpu.x05 !== x5_snap) begin
        $display("ERROR: R2 loop counter x5 advanced while halted (%h -> %h) %t ns", x5_snap, probes_cpu.x05, $time);
        error = error + 1;
    end
    single_write_resume("R2");

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware must complete the loop and reach the end on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, 32'h0000D09E);   // post-resume marker => the hart really resumed
    check_cpu_reg(18, 32'hA5A5A5A5);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

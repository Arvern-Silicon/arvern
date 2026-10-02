//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmstatus_states
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: dmstatus exactly-one-state coverage (Debug Spec 1.0)
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Per Debug Spec 1.0 every hart is
//   in EXACTLY ONE of the states {running, halted, unavailable} and dmstatus
//   must reflect that in the any*/all* pairs (bits [13:8] = allunavail,
//   anyunavail, allrunning, anyrunning, allhalted, anyhalted):
//     (a) RUNNING : spinning hart -> any/allrunning=1, halted/unavail all 0
//                   (state field == 0x0C00 exactly);
//     (b) HALTED  : after haltreq -> any/allhalted=1, others 0 (== 0x0300);
//     (c) UNAVAIL : resume, then HOLD dmcontrol.ndmreset=1 (hart held in
//                   reset; the DM lives on dbgresetn and stays reachable) ->
//                   any/allunavail=1, others 0 (== 0x3000);
//     (d) RELEASE : drop ndmreset -> hart reboots and runs (== 0x0C00);
//                   dmstatus.anyhavereset/allhavereset must be SET (sticky,
//                   the ndmreset needs acknowledging), then ackhavereset
//                   clears it; the restarted firmware re-runs its loop to the
//                   done sentinel on its own.
//   The ndmreset choreography (hart reset via hresetn = POR|ndmreset, DM kept
//   alive on POR-only dbgresetn) follows the reset contract modelled by
//   reset_gen / debug_reset_halt; here ndmreset is asserted while RUNNING
//   (the simpler sequence, same as dm_reset_halt does) but HELD across
//   dmstatus polls instead of pulsed.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DMCONTROL = 7'h10;
localparam [6:0] DMI_DMSTATUS  = 7'h11;

// dmcontrol field constants
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_NDMRESET   = 32'h00000002;  // [1]  ndmreset
localparam [31:0] DMC_HALTREQ    = 32'h80000000;  // [31] haltreq
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;  // [30] resumereq
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset

// dmstatus field masks
localparam [31:0] DMS_ANYHALTED    = 32'h00000100; // [8]
localparam [31:0] DMS_ALLHALTED    = 32'h00000200; // [9]
localparam [31:0] DMS_ANYRUNNING   = 32'h00000400; // [10]
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800; // [11]
localparam [31:0] DMS_ANYUNAVAIL   = 32'h00001000; // [12]
localparam [31:0] DMS_ALLUNAVAIL   = 32'h00002000; // [13]
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000; // [17]
localparam [31:0] DMS_ANYHAVERESET = 32'h00040000; // [18]
localparam [31:0] DMS_ALLHAVERESET = 32'h00080000; // [19]

// exactly-one-state field: dmstatus[13:8] = {allunavail, anyunavail,
// allrunning, anyrunning, allhalted, anyhalted}. With a single hart the any/all
// pair of the active state must both be 1 and every other bit 0.
localparam [31:0] DMS_STATE_MASK    = 32'h00003F00;
localparam [31:0] DMS_STATE_RUNNING = DMS_ALLRUNNING | DMS_ANYRUNNING; // 0x0C00
localparam [31:0] DMS_STATE_HALTED  = DMS_ALLHALTED  | DMS_ANYHALTED;  // 0x0300
localparam [31:0] DMS_STATE_UNAVAIL = DMS_ALLUNAVAIL | DMS_ANYUNAVAIL; // 0x3000

// Check that dmstatus (in dmi_readval) reports exactly the expected state.
task check_state;
   input [31:0] expect_state;
   input [127:0] label;
   begin
      if ((dmi_readval & DMS_STATE_MASK) !== expect_state) begin
         $display("ERROR: %0s: dmstatus state bits=%h (expected exactly %h) [dmstatus=%h] %t ns",
                  label, dmi_readval & DMS_STATE_MASK, expect_state, dmi_readval, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s: exactly-one-state (dmstatus[13:8]=%h) %t ns", label, expect_state, $time);
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
    $display("|  DEBUG DMSTATUS STATES: exactly one of running/halted/unavail, incl. |");
    $display("|  allunavail=1 while dmcontrol.ndmreset holds the hart in reset       |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) and ack the sticky POR havereset ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    //========================================================================
    // (a) RUNNING: any/allrunning=1, halted and unavail all 0.
    //========================================================================
    dmi_read(DMI_DMSTATUS);
    check_state(DMS_STATE_RUNNING, "(a) running");

    //========================================================================
    // (b) HALTED: haltreq -> any/allhalted=1, others 0.
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: hart did not halt on dmcontrol.haltreq (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart halted via DMI haltreq (allhalted=1, %0d polls) %t ns", to, $time);
    check_state(DMS_STATE_HALTED, "(b) halted");

    // resume back to running before the ndmreset leg (assert ndmreset from the
    // simpler RUNNING state, as dm_reset_halt does)
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                 // drop haltreq
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ); // request resume
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart not running after resume (allrunning=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart running after resume (%0d polls) %t ns", to, $time);
    check_state(DMS_STATE_RUNNING, "(b') resumed running");

    //========================================================================
    // (c) UNAVAILABLE: HOLD dmcontrol.ndmreset=1. The hart is held in reset
    //     (hresetn = POR|ndmreset) but the DM stays alive (POR-only dbgresetn)
    //     and the DMI keeps responding: any/allunavail=1, others 0.
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_NDMRESET);  // assert AND HOLD ndmreset
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLUNAVAIL) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLUNAVAIL) === 32'h0) begin
        $display("ERROR: allunavail not set while ndmreset holds the hart in reset (dmstatus=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  allunavail=1 while ndmreset held (%0d polls) %t ns", to, $time);
    check_state(DMS_STATE_UNAVAIL, "(c) unavailable (ndmreset held)");

    // hold a little longer and confirm the state is stable (still exactly unavail)
    repeat (20) @(posedge free_clk);
    dmi_read(DMI_DMSTATUS);
    check_state(DMS_STATE_UNAVAIL, "(c') unavailable stable");

    //========================================================================
    // (d) RELEASE: drop ndmreset -> the hart reboots and runs again;
    //     anyhavereset/allhavereset must be set (sticky) until ackhavereset.
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                 // release ndmreset
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 400)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart not running after ndmreset release (dmstatus=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  hart running again after ndmreset release (%0d polls) %t ns", to, $time);
    check_state(DMS_STATE_RUNNING, "(d) running after release");

    // sticky havereset from the ndmreset: any AND all (single hart) must be set...
    if ((dmi_readval & DMS_ANYHAVERESET) === 32'h0) begin
        $display("ERROR: anyhavereset not set after ndmreset (dmstatus=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  anyhavereset=1 after ndmreset %t ns", $time);
    if ((dmi_readval & DMS_ALLHAVERESET) === 32'h0) begin
        $display("ERROR: allhavereset not set after ndmreset (dmstatus=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  allhavereset=1 after ndmreset %t ns", $time);

    // ...and ackhavereset clears it.
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dmi_read(DMI_DMSTATUS);
    if ((dmi_readval & (DMS_ANYHAVERESET | DMS_ALLHAVERESET)) !== 32'h0) begin
        $display("ERROR: havereset did not clear on ackhavereset (dmstatus=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  havereset cleared by ackhavereset %t ns", $time);
    check_state(DMS_STATE_RUNNING, "(d') still running after ack");

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- the RESTARTED firmware re-runs its loop to the end on its own.
    //     Level wait: the re-run may already have completed by now. ---
    wait (probes_cpu.x31==32'hdeadbeef);
    $display("PASS:  restarted firmware reached 0xdeadbeef after ndmreset release %t ns", $time);
    check_cpu_reg(20, 32'h0000D09E);   // post-loop marker (set on the re-run)
    check_cpu_reg(18, 32'hA5A5A5A5);   // sentinel (re-initialized on the re-run)

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

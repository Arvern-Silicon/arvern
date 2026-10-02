//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_resumereq_haltreq
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: dmcontrol.resumereq is IGNORED while haltreq is set
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Per Debug Spec 1.0 ("Setting
//   resumereq ... is ignored if haltreq is set"):
//     (a) halt the hart, then write dmcontrol with BOTH haltreq=1 AND
//         resumereq=1 in the same write: allresumeack must NOT set and the
//         hart must STAY halted (allhalted=1) across a polling window;
//     (b) with haltreq still 1, write haltreq=1|resumereq=1 again (a second
//         resume attempt against a held haltreq): still ignored;
//         the loop counter x5 is provably FROZEN across (a)+(b);
//     (c) clear haltreq (dmcontrol=dmactive), then resumereq alone: NORMAL
//         resume (allresumeack sets, then allrunning; x5 advancing again),
//         and the firmware completes its loop to the done sentinel.
//   NOTE on (b): haltreq is an ordinary dmcontrol register bit, so keeping
//   "haltreq still 1" requires every write to re-drive haltreq=1; a write with
//   haltreq=0 would clear it and turn the resumereq into a legal resume.
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
    $display("|  DEBUG RESUMEREQ vs HALTREQ: resumereq is ignored while haltreq=1   |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);  // clear sticky havereset

    // --- halt the hart via dmcontrol.haltreq, poll dmstatus.allhalted ---
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

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode %t ns", $time);

    // snapshot the loop counter: it must stay frozen through (a) and (b)
    x5_snap = probes_cpu.x05;

    //========================================================================
    // (a) haltreq=1 AND resumereq=1 in the SAME dmcontrol write: the resume
    //     request must be IGNORED. Poll a whole window: allresumeack must
    //     never set and allhalted must stay 1.
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ | DMC_RESUMEREQ);

    ack_seen = 0;
    for (to = 0; to < 20; to = to + 1) begin
        dmi_read(DMI_DMSTATUS);
        if ((dmi_readval & DMS_ALLRESUMEACK) !== 32'h0) ack_seen = 1;
        if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
            $display("ERROR: (a) hart LEFT halted state with haltreq=1 (dmstatus=%h, poll %0d) %t ns", dmi_readval, to, $time);
            error = error + 1;
        end
    end
    if (ack_seen) begin
        $display("ERROR: (a) allresumeack SET on resumereq while haltreq=1 (must be ignored) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  (a) resumereq written together with haltreq=1 ignored (no resumeack, still halted) %t ns", $time);

    //========================================================================
    // (b) with haltreq STILL 1, write resumereq=1 again (second attempt):
    //     still ignored.
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ | DMC_RESUMEREQ);

    ack_seen = 0;
    for (to = 0; to < 20; to = to + 1) begin
        dmi_read(DMI_DMSTATUS);
        if ((dmi_readval & DMS_ALLRESUMEACK) !== 32'h0) ack_seen = 1;
        if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
            $display("ERROR: (b) hart LEFT halted state with haltreq=1 (dmstatus=%h, poll %0d) %t ns", dmi_readval, to, $time);
            error = error + 1;
        end
    end
    if (ack_seen) begin
        $display("ERROR: (b) allresumeack SET on repeated resumereq while haltreq=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  (b) repeated resumereq while haltreq=1 ignored (no resumeack, still halted) %t ns", $time);

    // frozen-hart proof: the loop counter must not have advanced across (a)+(b)
    if (probes_cpu.x05 !== x5_snap) begin
        $display("ERROR: loop counter x5 advanced while halted (%h -> %h) %t ns", x5_snap, probes_cpu.x05, $time);
        error = error + 1;
    end else $display("PASS:  loop counter x5 frozen across both ignored resume attempts (%h) %t ns", x5_snap, $time);

    //========================================================================
    // (c) clear haltreq, THEN resumereq: normal resume (allresumeack sets,
    //     hart runs, counter advances again).
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                       // drop haltreq (and resumereq)
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);       // resumereq alone

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) begin
        $display("ERROR: (c) no allresumeack after resumereq with haltreq clear %t ns", $time);
        error = error + 1;
    end else $display("PASS:  (c) allresumeack set once haltreq was cleared (%0d polls) %t ns", to, $time);

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: (c) hart not running after resume (allrunning=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  (c) hart running after resume (allrunning=1) %t ns", $time);

    // counter advancing again: the loop (0x1000 iterations) is still in flight,
    // so a short observation window must see x5 move.
    x5_snap = probes_cpu.x05;
    repeat (40) @(posedge free_clk);
    if (probes_cpu.x05 === x5_snap) begin
        $display("ERROR: (c) loop counter x5 still frozen after the real resume (%h) %t ns", x5_snap, $time);
        error = error + 1;
    end else $display("PASS:  (c) loop counter x5 advancing again after the real resume (%h -> %h) %t ns", x5_snap, probes_cpu.x05, $time);

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware must complete the loop and reach the end on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, 32'h0000D09E);   // post-resume marker => the hart really resumed
    check_cpu_reg(18, 32'hA5A5A5A5);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

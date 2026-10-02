//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_runctrl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DMI run-control (Debug Module)
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Proves the Debug Module's run
//   control end-to-end:
//     - dmcontrol.dmactive releases the DM from reset;
//     - dmstatus.allhavereset is sticky-SET after reset, cleared by ackhavereset;
//     - dmcontrol.haltreq halts the spinning hart -> dmstatus.allhalted;
//     - the loop counter (x5) is FROZEN while halted (frozen hart);
//     - dmcontrol.resumereq resumes -> dmstatus.allresumeack then allrunning;
//     - the firmware completes the loop and sets the post-resume marker.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
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
localparam [31:0] DMS_ALLHAVERESET = 32'h00080000; // [19]

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
    $display("|  DEBUG DMI RUNCTRL: halt/resume a hart over the DMI bus (no DTM)    |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);

    // dmstatus sanity: version must be 1.0 (==3), hart must be running, and
    // allhavereset must be SET (sticky, "reset and not yet acknowledged").
    dmi_read(DMI_DMSTATUS);
    if (dmi_readval[3:0] !== 4'd3) begin
        $display("ERROR: dmstatus.version=%0d (expected 3 for Debug Spec 1.0) %t ns", dmi_readval[3:0], $time);
        error = error + 1;
    end else $display("PASS:  dmstatus.version=3 (Debug Spec 1.0) %t ns", $time);

    if ((dmi_readval & DMS_ALLHAVERESET) === 32'h0) begin
        $display("ERROR: dmstatus.allhavereset not set after reset (sticky havereset missing) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dmstatus.allhavereset set after reset %t ns", $time);

    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart not reported running before halt (allrunning=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart reported running before halt %t ns", $time);

    // --- acknowledge havereset, confirm it clears ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dmi_read(DMI_DMSTATUS);
    if ((dmi_readval & DMS_ALLHAVERESET) !== 32'h0) begin
        $display("ERROR: dmstatus.allhavereset did not clear after ackhavereset %t ns", $time);
        error = error + 1;
    end else $display("PASS:  allhavereset cleared by ackhavereset %t ns", $time);

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

    // --- frozen-hart check: the loop counter x5 must not advance while halted ---
    x5_snap = probes_cpu.x05;
    repeat (40) @(posedge free_clk);
    if (probes_cpu.x05 !== x5_snap) begin
        $display("ERROR: loop counter x5 advanced while halted (%h -> %h) %t ns", x5_snap, probes_cpu.x05, $time);
        error = error + 1;
    end else $display("PASS:  hart frozen while halted (x5 stable at %h) %t ns", x5_snap, $time);

    // --- clear haltreq, then resume via dmcontrol.resumereq ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                       // drop haltreq
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);       // request resume

    // Poll for resume acknowledge, then running.
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) begin
        $display("ERROR: no allresumeack after resumereq %t ns", $time);
        error = error + 1;
    end else $display("PASS:  allresumeack set after resume (%0d polls) %t ns", to, $time);

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart not running after resume (allrunning=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart running after resume (allrunning=1) %t ns", $time);

    // --- APB wait-state / data-valid contract: drive the raw APB slave INLINE
    //     (bypassing the helper tasks) and confirm the timing the DTM master
    //     relies on: SETUP -> ACCESS, one wait state (PREADY low the first ACCESS
    //     cycle), then PREADY high with valid PRDATA, then PREADY self-clears
    //     (single-transfer completion). Exercised here where it is easy to
    //     localise. dmstatus.version==3 is the known-good read-back value.
    // Drive a hair AFTER the rising edge and sample mid-cycle at the falling edge.
    // Driving ON the edge the DM samples leaves the ordering undefined -- measured,
    // Icarus and Verilator disagree by one cycle on when PREADY rises. The rest of the
    // suite hides this because debug_dmi_tasks.v polls PREADY instead of asserting an
    // exact cycle count; this is the only test that pins the wait state down.
    @(posedge dut_hclk); #1;
    dmi_paddr   = {DMI_DMSTATUS, 2'b00}; // reg index in PADDR[8:2]
    dmi_pwrite  = 1'b0;                   // read
    dmi_psel    = 1'b1;
    dmi_penable = 1'b0;                   // SETUP phase
    @(posedge dut_hclk); #1;
    dmi_penable = 1'b1;                   // ACCESS phase begins at the next rising edge
    @(negedge dut_hclk);                 // inside the first ACCESS cycle
    if (dmi_pready !== 1'b0) begin
        $display("ERROR: APB PREADY high in first ACCESS cycle (expected 1 wait state) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  APB inserts one wait state (PREADY low first ACCESS cycle) %t ns", $time);
    @(negedge dut_hclk);                 // inside the cycle after the wait state
    if (dmi_pready !== 1'b1) begin
        $display("ERROR: APB PREADY not asserted after the wait state %t ns", $time);
        error = error + 1;
    end else if (dmi_prdata[3:0] !== 4'd3) begin
        $display("ERROR: APB PRDATA invalid on PREADY (dmstatus.version=%0d, expected 3) %t ns", dmi_prdata[3:0], $time);
        error = error + 1;
    end else
        $display("PASS:  APB PRDATA valid on PREADY (dmstatus read back) %t ns", $time);
    dmi_psel    = 1'b0;                   // complete the transfer
    dmi_penable = 1'b0;
    @(negedge dut_hclk);
    if (dmi_pready !== 1'b0) begin
        $display("ERROR: APB PREADY did not self-clear after completion %t ns", $time);
        error = error + 1;
    end else $display("PASS:  APB PREADY self-cleared (single-transfer completion) %t ns", $time);

    // --- firmware must complete the loop and reach the end on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, 32'h0000D09E);   // post-resume marker => the hart really resumed
    check_cpu_reg(18, 32'hA5A5A5A5);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

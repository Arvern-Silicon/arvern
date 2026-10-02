//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_stoptime
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DMI dcsr.stoptime drives the dbg_stoptime SoC pin (Debug Spec 1.0)
//   Drives the hclk-domain DMI bus (no DTM) via the dmi_write/dmi_read helpers.
//   The external pin dbg_stoptime_o (TB wire dbg_stoptime) is asserted exactly
//   when (the hart is in Debug Mode) AND (dcsr.stoptime, CSR 0x7b0 bit 9) is set.
//   This core has no internal time counter to freeze; stoptime only exports the
//   SoC-level mtime-freeze request, so the pin is the observable under test.
//
//   Sequence:
//     a. before halt: dbg_stoptime == 0 (not in Debug Mode).
//     b. halt via dmcontrol.haltreq; with stoptime=0 (reset default) -> pin == 0.
//     c. read-modify-write dcsr to SET   stoptime -> pin == 1 (Debug Mode & set).
//     d. read-modify-write dcsr to CLEAR stoptime -> pin == 0.
//     e. SET stoptime again -> pin == 1; resume; after allrunning (Debug-Mode term
//        gone) -> pin == 0 even though the dcsr.stoptime bit is still set.
//     f. firmware reaches 0xdeadbeef (proves resume; prv preserved -> M-mode).
//
//   dcsr is reached by the same abstract Access Register routing used by
//   debug_dmi_csr for mscratch (regno = the 12-bit CSR address directly). The
//   dcsr read-back uses no dedicated task: dmi_read(DMI_DATA0) then dmi_readval.
//   The read-modify-write preserves dcsr.prv[1:0] so the hart resumes into M-mode.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

// dmcontrol field constants
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_HALTREQ    = 32'h80000000;  // [31] haltreq
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;  // [30] resumereq
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset

// dmstatus field masks
localparam [31:0] DMS_ALLHALTED    = 32'h00000200; // [9]
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800; // [11]
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000; // [17]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0, aarsize=2, transfer=1)
//   regno = the 12-bit CSR address directly
localparam [31:0] CMD_RD_DCSR = 32'h00200000 | 32'h00020000 |              32'h000007b0; // = 0x002207b0
localparam [31:0] CMD_WR_DCSR = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h000007b0; // = 0x002307b0

// dcsr fields
localparam [31:0] DCSR_STOPTIME = 32'h00000200; // [9] stoptime

localparam [31:0] X18_SENTINEL = 32'hA5A5A5A5;

// Issue an abstract command and wait for abstractcs.busy to clear; the final
// abstractcs value (incl. cmderr) is left in dmi_readval. (dcsr read-back, when
// needed, is a separate dmi_read(DMI_DATA0); there is no dedicated task for it.)
task abs_run;
   input [31:0] cmd;
   begin
      dmi_write(DMI_COMMAND, cmd);
      to = 0;
      dmi_read(DMI_ABSTRACTCS);
      while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
         dmi_read(DMI_ABSTRACTCS);
         to = to + 1;
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

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG DMI STOPTIME: dcsr.stoptime drives the dbg_stoptime pin       |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    //========================================================================
    // (a) Before any halt: not in Debug Mode -> pin deasserted.
    //========================================================================
    if (dbg_stoptime !== 1'b0) begin
        $display("ERROR: dbg_stoptime asserted before halt (not in Debug Mode) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dbg_stoptime=0 before halt (not in Debug Mode) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);  // clear sticky havereset

    //========================================================================
    // (b) Halt the hart; with stoptime=0 (reset default) the pin stays 0 even
    //     though we are now in Debug Mode.
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

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode %t ns", $time);

    @(posedge dut_hclk);                                  // let the pin settle
    if (dbg_stoptime !== 1'b0) begin
        $display("ERROR: dbg_stoptime asserted in Debug Mode with stoptime=0 (default) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dbg_stoptime=0 in Debug Mode with stoptime=0 (default) %t ns", $time);

    //========================================================================
    // (c) Set dcsr.stoptime (read-modify-write, prv preserved) -> pin asserts.
    //========================================================================
    abs_run(CMD_RD_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);                                  // dmi_readval = current dcsr
    dmi_write(DMI_DATA0, dmi_readval | DCSR_STOPTIME);    // set stoptime, keep the rest
    abs_run(CMD_WR_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr write (set stoptime) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.stoptime set (read-modify-write, prv preserved) %t ns", $time);

    @(posedge dut_hclk);                                  // let the pin settle
    if (dbg_stoptime !== 1'b1) begin
        $display("ERROR: dbg_stoptime NOT asserted with stoptime=1 in Debug Mode %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dbg_stoptime=1 with stoptime=1 in Debug Mode %t ns", $time);

    //========================================================================
    // (d) Clear dcsr.stoptime -> pin deasserts (still in Debug Mode).
    //========================================================================
    abs_run(CMD_RD_DCSR);
    dmi_read(DMI_DATA0);
    dmi_write(DMI_DATA0, dmi_readval & ~DCSR_STOPTIME);   // clear stoptime, keep the rest
    abs_run(CMD_WR_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr write (clear stoptime) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.stoptime cleared (read-modify-write, prv preserved) %t ns", $time);

    @(posedge dut_hclk);
    if (dbg_stoptime !== 1'b0) begin
        $display("ERROR: dbg_stoptime still asserted after clearing stoptime in Debug Mode %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dbg_stoptime=0 after clearing stoptime (Debug Mode) %t ns", $time);

    //========================================================================
    // (e) Set stoptime again -> pin=1; then resume. After resume the Debug-Mode
    //     term is gone, so the pin must drop to 0 even though dcsr.stoptime=1.
    //========================================================================
    abs_run(CMD_RD_DCSR);
    dmi_read(DMI_DATA0);
    dmi_write(DMI_DATA0, dmi_readval | DCSR_STOPTIME);    // set stoptime again
    abs_run(CMD_WR_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr write (re-set stoptime) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end

    @(posedge dut_hclk);
    if (dbg_stoptime !== 1'b1) begin
        $display("ERROR: dbg_stoptime NOT asserted after re-setting stoptime %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dbg_stoptime=1 after re-setting stoptime (Debug Mode) %t ns", $time);

    //========================================================================
    // RESUME
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                 // drop haltreq
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ); // request resume

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

    // Debug-Mode term is gone now (allrunning=1) -> pin must be 0 even though the
    // dcsr.stoptime bit was left set. Sample only after confirming allrunning.
    @(posedge dut_hclk);
    if (dbg_stoptime !== 1'b0) begin
        $display("ERROR: dbg_stoptime asserted after resume (dcsr.stoptime still set but not in Debug Mode) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dbg_stoptime=0 after resume (Debug-Mode term gone, stoptime bit still set) %t ns", $time);

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware must resume from dpc (prv preserved = M-mode) and reach done ---
    @(probes_cpu.x31==32'hdeadbeef);
    // sentinel must be untouched by any of the abstract accesses
    check_cpu_reg(18, X18_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

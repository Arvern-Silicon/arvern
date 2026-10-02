//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_csr_upriv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DMI abstract CSR access bypasses privilege
//   Halts the hart while it is parked in U-mode and proves the Debug Module has
//   full M-mode CSR visibility regardless of the hart's current privilege. Over
//   the DMI bus the testbench:
//     - abstract-WRITES mscratch (0x340, an M-only CSR) = 0x0BADF00D, then
//       abstract-READS it back -> cmderr=0 and round-trips. Without the DM
//       privilege bypass, a machine-CSR access while privilege=U would fault
//       (cmderr=3), so cmderr=0 here is exactly the discriminating property.
//     - abstract-READS mcycle (0xB00), a machine counter -> cmderr=0
//       (counter-permission bypass; mcounteren does not gate the DM).
//   After resume (still in U-mode) the firmware ecalls into M-mode and reads
//   mscratch into x20; x20 == 0x0BADF00D confirms the DM write reached the
//   architectural M-only CSR while the hart was halted in U-mode.
//
//   The cmderr=0 checks on the mscratch write/read run after allhalted and are
//   race-immune (they are the headline property and do not depend on firmware);
//   only the post-resume firmware read-back depends on the halt landing mid-spin,
//   and that path can only fail, never false-pass (the DM write provably precedes
//   resume).
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
localparam [31:0] CMD_WR_MSCRATCH = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h00000340; // = 0x00230340
localparam [31:0] CMD_RD_MSCRATCH = 32'h00200000 | 32'h00020000 |              32'h00000340; // = 0x00220340
localparam [31:0] CMD_RD_MCYCLE   = 32'h00200000 | 32'h00020000 |              32'h00000b00; // = 0x00220b00

localparam [31:0] MSCRATCH_VAL = 32'h0BADF00D;
localparam [31:0] X18_SENTINEL = 32'hA5A5A5A5;

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
    $display("|  DEBUG DMI CSR UPRIV: DM M-CSR access while hart halted in U-mode  |");
    $display(" ====================================================================");

    // Firmware has dropped to U-mode and is spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware in U-mode, spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);  // clear sticky havereset

    // --- halt the hart (it is parked in U-mode), poll dmstatus.allhalted ---
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
    end else $display("PASS:  hart halted in U-mode via DMI haltreq (allhalted=1, %0d polls) %t ns", to, $time);

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode (parked from U-mode) %t ns", $time);

    //========================================================================
    // PRIVILEGE BYPASS: write+read an M-only CSR (mscratch) while halted in U.
    //   cmderr=0 here is the discriminating property of the DM bypass.
    //========================================================================
    dmi_write(DMI_DATA0, MSCRATCH_VAL);          // arg0 = value to inject
    dmi_write(DMI_COMMAND, CMD_WR_MSCRATCH);      // transfer+write mscratch from data0

    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
        $display("ERROR: abstractcs.busy stuck after mscratch write %t ns", $time);
        error = error + 1;
    end else $display("PASS:  abstract mscratch write completed (busy clear, %0d polls) %t ns", to, $time);

    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d on M-only mscratch write while halted in U (expected 0=bypass) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=0 on M-only mscratch write while halted in U (privilege bypass) %t ns", $time);

    dmi_write(DMI_COMMAND, CMD_RD_MSCRATCH);
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d on M-only mscratch read while halted in U (expected 0=bypass) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=0 on M-only mscratch read while halted in U (privilege bypass) %t ns", $time);

    dmi_read(DMI_DATA0);
    if (dmi_readval !== MSCRATCH_VAL) begin
        $display("ERROR: abstract read-back of mscratch returned %h (expected %h) %t ns", dmi_readval, MSCRATCH_VAL, $time);
        error = error + 1;
    end else $display("PASS:  abstract mscratch round-trip (while halted in U) returned %h %t ns", MSCRATCH_VAL, $time);

    //========================================================================
    // COUNTER-PERMISSION BYPASS: read mcycle (0xB00) while halted in U.
    //   mcounteren gating does not apply to the DM -> cmderr=0.
    //========================================================================
    dmi_write(DMI_COMMAND, CMD_RD_MCYCLE);
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d on mcycle read while halted in U (expected 0=bypass) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=0 on machine-counter mcycle read while halted in U (bypass) %t ns", $time);

    //========================================================================
    // RESUME + final check
    //========================================================================
    // The firmware deliberately ecalls (U->M) after resume to read mscratch back
    // in M-mode; that ECALL is expected, so disarm the exception monitor before the
    // resume so the legitimate environment call is not flagged as an error.
    error_on_exception = 0;
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

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware resumes (in U), ecalls into M-mode, reads mscratch into x20 ---
    @(probes_cpu.x31==32'hdeadbeef);
    // x20 = mscratch read in M-mode after resume; equals the DM-injected value
    // only if the abstract write reached the architectural M-only CSR while the
    // hart was halted in U-mode (the privilege bypass, end-to-end).
    check_cpu_reg(20, MSCRATCH_VAL);
    // sentinel must be untouched by any of the abstract accesses
    check_cpu_reg(18, X18_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

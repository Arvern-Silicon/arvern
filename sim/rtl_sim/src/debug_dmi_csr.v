//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_csr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DMI abstract CSR access (Debug Module, Access Register command)
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Halts the spinning hart, then uses
//   the Debug Module abstract "Access Register" command (command[0x17], data0
//   [0x04], abstractcs[0x16]) to access CONTROL/STATUS REGISTERS of the frozen
//   hart (regno = the 12-bit CSR address directly):
//     - mscratch round-trip : abstract-write 0xC5A17E5C, abstract-read it back
//                             (cmderr=0, value matches); after resume the
//                             firmware reads mscratch into x20 -> proves the DM
//                             write landed in the architectural CSR.
//     - dpc read            : abstract-read dpc (0x7b1), the parked halt PC;
//                             must be cmderr=0, nonzero and halfword-aligned.
//                             (this case sits on the GPR-vs-CSR routing boundary)
//     - nonexistent CSR     : abstract-read 0x3f0 -> cmderr=3 (exception), W1C clear.
//     - read-only write     : abstract-write mvendorid (0xf11) -> cmderr=3,
//                             W1C clear, then abstract-READ mvendorid -> cmderr=0.
//     - resume + final check: firmware reads mscratch into x20 -> 0xC5A17E5C.
//
//   NOTE (RTL-behavior assumptions, per the test spec's cmderr table): a write
//   to read-only mvendorid and a read of nonexistent 0x3f0 are both expected to
//   raise abstractcs.cmderr=3 (exception). A strict-WARL DM could instead ignore
//   the RO write with cmderr=0; if this test ever fails on those two checks, that
//   routing decision is the first thing to confirm.
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

// Access Register command words (command[0x17], cmdtype=0)
//   [22:20] aarsize=2 (32-bit) -> 0x00200000 ; [17] transfer=1 -> 0x00020000
//   [16] write ; [15:0] regno = the 12-bit CSR address directly
localparam [31:0] CMD_WR_MSCRATCH = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h00000340; // = 0x00230340
localparam [31:0] CMD_RD_MSCRATCH = 32'h00200000 | 32'h00020000 |              32'h00000340; // = 0x00220340
localparam [31:0] CMD_RD_DPC      = 32'h00200000 | 32'h00020000 |              32'h000007b1; // = 0x002207b1
localparam [31:0] CMD_RD_BADCSR   = 32'h00200000 | 32'h00020000 |              32'h000003f0; // = 0x002203f0
localparam [31:0] CMD_WR_MVENDOR  = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h00000f11; // = 0x00230f11
localparam [31:0] CMD_RD_MVENDOR  = 32'h00200000 | 32'h00020000 |              32'h00000f11; // = 0x00220f11

localparam [31:0] MSCRATCH_VAL = 32'hC5A17E5C;
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
    $display("|  DEBUG DMI CSR: abstract Access Register read/write of CSRs (halted) |");
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
    end else $display("PASS:  hart in Debug Mode (abstract CSR access permitted) %t ns", $time);

    //========================================================================
    // mscratch round-trip: abstract-write 0xC5A17E5C, abstract-read it back
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
        $display("ERROR: abstractcs.cmderr=%0d after mscratch write (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  abstractcs.cmderr=0 after mscratch write %t ns", $time);

    dmi_write(DMI_COMMAND, CMD_RD_MSCRATCH);      // read mscratch back into data0
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after mscratch read (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  abstractcs.cmderr=0 after mscratch read %t ns", $time);

    dmi_read(DMI_DATA0);
    if (dmi_readval !== MSCRATCH_VAL) begin
        $display("ERROR: abstract read-back of mscratch returned %h (expected %h) %t ns", dmi_readval, MSCRATCH_VAL, $time);
        error = error + 1;
    end else $display("PASS:  abstract mscratch round-trip returned injected %h %t ns", MSCRATCH_VAL, $time);

    //========================================================================
    // dpc read: the parked halt PC. cmderr=0, nonzero, halfword-aligned.
    //   (GPR-vs-CSR routing boundary: dpc is a CSR, not a GPR.)
    //   The hart resumes FROM dpc, so reaching 0xdeadbeef post-resume also
    //   corroborates that dpc held a sane address (we only read it, never write).
    //========================================================================
    dmi_write(DMI_COMMAND, CMD_RD_DPC);
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after dpc read (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  abstractcs.cmderr=0 after dpc read %t ns", $time);

    dmi_read(DMI_DATA0);
    if (dmi_readval === 32'h0) begin
        $display("ERROR: abstract read of dpc returned 0 (expected a halt PC) %t ns", $time);
        error = error + 1;
    end else if ((dmi_readval & 32'h1) !== 32'h0) begin
        $display("ERROR: abstract read of dpc=%h not halfword-aligned %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  abstract read of dpc=%h (nonzero, halfword-aligned) %t ns", dmi_readval, $time);

    //========================================================================
    // nonexistent CSR: abstract-read 0x3f0 must raise cmderr=3 (exception),
    // then W1C-clear and confirm cmderr reads back 0.
    //========================================================================
    dmi_write(DMI_COMMAND, CMD_RD_BADCSR);
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if (((dmi_readval & ACS_CMDERR) >> 8) !== 3'd3) begin
        $display("ERROR: cmderr=%0d after read of nonexistent CSR 0x3f0 (expected 3=exception) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=3 (exception) on read of nonexistent CSR 0x3f0 %t ns", $time);

    // W1C-clear and confirm 0 BEFORE issuing the next command (a non-zero cmderr
    // blocks all subsequent abstract commands -> would false-pass the next check).
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
    dmi_read(DMI_ABSTRACTCS);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr did not clear via W1C after bad-CSR read (still %0d) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr cleared by W1C after bad-CSR read %t ns", $time);

    //========================================================================
    // read-only write: abstract-write mvendorid (0xf11) must raise cmderr=3,
    // then W1C-clear; a subsequent abstract-READ of mvendorid is cmderr=0.
    //========================================================================
    dmi_write(DMI_DATA0, 32'hDEADBEEF);           // value the DM tries (must be rejected)
    dmi_write(DMI_COMMAND, CMD_WR_MVENDOR);
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if (((dmi_readval & ACS_CMDERR) >> 8) !== 3'd3) begin
        $display("ERROR: cmderr=%0d after write of read-only mvendorid (expected 3=exception) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=3 (exception) on write of read-only mvendorid %t ns", $time);

    // clear before the read-of-RO check
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
    dmi_read(DMI_ABSTRACTCS);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr did not clear via W1C after RO write (still %0d) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr cleared by W1C after RO write %t ns", $time);

    dmi_write(DMI_COMMAND, CMD_RD_MVENDOR);       // reading a read-only CSR is fine
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after read of read-only mvendorid (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=0 on read of read-only mvendorid %t ns", $time);

    //========================================================================
    // RESUME + final check
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

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware must complete the loop and read back mscratch on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    // x20 = mscratch read by firmware after resume; equals the DM-injected value
    // only if the abstract write truly reached the architectural CSR.
    check_cpu_reg(20, MSCRATCH_VAL);
    // sentinel must be untouched by any of the abstract accesses
    check_cpu_reg(18, X18_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

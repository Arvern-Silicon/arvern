//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_gpr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DMI abstract GPR access (Debug Module, Access Register command)
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Halts the spinning hart, then uses
//   the Debug Module abstract "Access Register" command (command[0x17], data0
//   [0x04], abstractcs[0x16]) to access general-purpose registers of the frozen
//   hart:
//     - READ  : abstract read of x18 returns the firmware sentinel 0xA5A5A5A5,
//               cross-checked against the actual register file (probes_cpu.x18);
//     - WRITE : abstract write injects 0xCAFE0000 into x20 while halted,
//               read back via abstract read and cross-checked against the
//               register file (probes_cpu.x20);
//     - ERROR : a deliberately unsupported command (aarsize=3, 64-bit on RV32)
//               sets abstractcs.cmderr=2 (not supported), then W1C clears it;
//     - RESUME: after resume the firmware adds 0x123 to the injected x20, so the
//               final x20 = 0xCAFE0123 proves the write reached the regfile AND
//               the hart truly resumed; the x18 sentinel must remain intact.
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
localparam [31:0] DMS_ALLHAVERESET = 32'h00080000; // [19]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0)
//   [22:20] aarsize=2 (32-bit) -> 0x00200000 ; [17] transfer=1 -> 0x00020000
//   [16] write ; [15:0] regno = 0x1000 + gpr_index
//     x18 -> regno 0x1012 ; x20 -> regno 0x1014
localparam [31:0] CMD_READ_X18  = 32'h00200000 | 32'h00020000 | 32'h00001012; // = 0x00221012
localparam [31:0] CMD_WRITE_X20 = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h00001014; // = 0x00231014
localparam [31:0] CMD_READ_X20  = 32'h00200000 | 32'h00020000 | 32'h00001014; // = 0x00221014
// Unsupported command: aarsize=3 (64-bit) [22:20]=011 -> 0x00300000, transfer=1, read, regno x18
localparam [31:0] CMD_BAD_SIZE  = 32'h00300000 | 32'h00020000 | 32'h00001012; // = 0x00321012

localparam [31:0] X18_SENTINEL  = 32'hA5A5A5A5;
localparam [31:0] X20_INJECT    = 32'hCAFE0000;
localparam [31:0] X20_FINAL     = 32'hCAFE0123;  // injected + firmware post-resume +0x123

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
    $display("|  DEBUG DMI GPR: abstract Access Register read/write of a halted hart |");
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
    end else $display("PASS:  hart in Debug Mode (abstract GPR access permitted) %t ns", $time);

    //========================================================================
    // READ test: abstract Access Register read of x18 -> data0
    //========================================================================
    dmi_write(DMI_COMMAND, CMD_READ_X18);

    // poll abstractcs.busy clear
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
        $display("ERROR: abstractcs.busy stuck after read command %t ns", $time);
        error = error + 1;
    end else $display("PASS:  abstract read command completed (busy clear, %0d polls) %t ns", to, $time);

    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after x18 read (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  abstractcs.cmderr=0 after x18 read %t ns", $time);

    dmi_read(DMI_DATA0);
    if (dmi_readval !== X18_SENTINEL) begin
        $display("ERROR: abstract read of x18 returned %h (expected %h) %t ns", dmi_readval, X18_SENTINEL, $time);
        error = error + 1;
    end else $display("PASS:  abstract read of x18 returned sentinel %h %t ns", X18_SENTINEL, $time);

    // cross-check the abstract read against the actual register file
    if (probes_cpu.x18 !== X18_SENTINEL) begin
        $display("ERROR: regfile x18=%h disagrees with sentinel %h %t ns", probes_cpu.x18, X18_SENTINEL, $time);
        error = error + 1;
    end else $display("PASS:  abstract read agrees with regfile x18=%h %t ns", probes_cpu.x18, $time);

    //========================================================================
    // WRITE test: abstract Access Register write of x20 from data0
    //========================================================================
    dmi_write(DMI_DATA0, X20_INJECT);          // arg0 = value to inject
    dmi_write(DMI_COMMAND, CMD_WRITE_X20);      // transfer+write x20 from data0

    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
        $display("ERROR: abstractcs.busy stuck after write command %t ns", $time);
        error = error + 1;
    end else $display("PASS:  abstract write command completed (busy clear, %0d polls) %t ns", to, $time);

    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after x20 write (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  abstractcs.cmderr=0 after x20 write %t ns", $time);

    // cross-check: the abstract write actually reached the register file while halted
    if (probes_cpu.x20 !== X20_INJECT) begin
        $display("ERROR: regfile x20=%h after abstract write (expected %h) %t ns", probes_cpu.x20, X20_INJECT, $time);
        error = error + 1;
    end else $display("PASS:  abstract write reached regfile x20=%h while halted %t ns", X20_INJECT, $time);

    // read x20 back over DMI and confirm it matches the injected value
    dmi_write(DMI_COMMAND, CMD_READ_X20);
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after x20 read-back (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);
    if (dmi_readval !== X20_INJECT) begin
        $display("ERROR: abstract read-back of x20 returned %h (expected %h) %t ns", dmi_readval, X20_INJECT, $time);
        error = error + 1;
    end else $display("PASS:  abstract read-back of x20 returned injected %h %t ns", X20_INJECT, $time);

    //========================================================================
    // ERROR test: unsupported command must set abstractcs.cmderr=2, then W1C
    //========================================================================
    dmi_write(DMI_COMMAND, CMD_BAD_SIZE);       // aarsize=3 (64-bit) not supported on RV32
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if (((dmi_readval & ACS_CMDERR) >> 8) !== 3'd2) begin
        $display("ERROR: cmderr=%0d after unsupported command (expected 2=not supported) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=2 (not supported) on unsupported command %t ns", $time);

    // clear cmderr by writing 1s to abstractcs[10:8] and confirm it reads back 0
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
    dmi_read(DMI_ABSTRACTCS);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr did not clear via W1C (still %0d) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr cleared by W1C %t ns", $time);

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

    // --- firmware must complete the loop and reach the end on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    // final x20 = injected (0xCAFE0000) + firmware post-resume 0x123 => proves both
    // the injected abstract write survived AND the hart really resumed and executed.
    check_cpu_reg(20, X20_FINAL);
    // sentinel must be untouched by the abstract read
    check_cpu_reg(18, X18_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

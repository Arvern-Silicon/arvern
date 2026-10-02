//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_gpr_div
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DMI abstract GPR read of a DRAINING hart (drain-qualified halted)
//   Discriminating companion to debug_dmi_gpr. The firmware spins in a loop whose
//   body is a slow 33-cycle radix-2 DIVIDE writing x9. This testbench halts the
//   hart over the DMI bus while a divide is in flight, then issues an abstract
//   Access Register READ of x9 and proves the read returns the COMPLETED quotient
//   rather than the destination register's stale pre-divide POISON value.
//
//   Why this is the discriminating test debug_dmi_gpr cannot provide:
//     - debug_dmi_gpr's firmware is a single-cycle loop, so the hart is always
//       already drained when it halts; an abstract read can never observe an
//       in-flight op there.
//     - Here, correct drain-qualification means dmstatus.allhalted only asserts
//       after the in-flight divide retires, so data0 == quotient (0x00C0FFEE).
//     - If drain-qualification were broken/absent, allhalted would assert mid-
//       divide and the abstract read would return the poison (0xDEAD0000) — the
//       register's stale pre-divide value. data0 != poison is therefore the
//       direct broken-drain detector.
//
//   Divide: 0x09CCFF16 / 0x0000000D = 0x00C0FFEE (exact, remainder 0).
//
//   No fixed cycle counts are used: allhalted and abstractcs.busy are POLLED, so
//   the test stays correct under random ROM/SRAM wait states that move the drain
//   window around.
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

// Access Register command word (command[0x17], cmdtype=0)
//   [22:20] aarsize=2 (32-bit) -> 0x00200000 ; [17] transfer=1 -> 0x00020000
//   write=0 (read) ; [15:0] regno = 0x1000 + 9 = 0x1009 for x9
localparam [31:0] CMD_READ_X9 = 32'h00200000 | 32'h00020000 | 32'h00001009; // = 0x00221009

localparam [31:0] DIV_QUOTIENT = 32'h00C0FFEE;  // 0x09CCFF16 / 0xD, the completed result
localparam [31:0] DIV_POISON   = 32'hDEAD0000;  // x9 pre-divide value; a stale read == this
localparam [31:0] X20_MARKER   = 32'h0000D09E;  // firmware post-divide marker

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
    $display("|  DEBUG DMI GPR DIV: abstract read of a halting hart with DIV draining|");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning in the divide loop.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning in divide loop (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1), clear sticky havereset ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    // --- halt the hart via dmcontrol.haltreq, poll dmstatus.allhalted ---
    //     A correct drain-qualified DM holds allhalted=0 until the in-flight
    //     divide retires; we only proceed once allhalted=1.
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
    // DRAIN-QUALIFICATION test: abstract read of the divide destination x9.
    //   With correct drain-qual, allhalted asserted only after the divide wrote
    //   back, so x9 holds the completed quotient. A stale (poison) value here
    //   would mean allhalted asserted mid-divide => broken drain-qualification.
    //========================================================================
    dmi_write(DMI_COMMAND, CMD_READ_X9);

    // poll abstractcs.busy clear
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
        $display("ERROR: abstractcs.busy stuck after x9 read command %t ns", $time);
        error = error + 1;
    end else $display("PASS:  abstract read command completed (busy clear, %0d polls) %t ns", to, $time);

    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after x9 read (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  abstractcs.cmderr=0 after x9 read %t ns", $time);

    dmi_read(DMI_DATA0);
    // KEY ASSERTION 1: the abstract read returns the COMPLETED quotient.
    if (dmi_readval !== DIV_QUOTIENT) begin
        $display("ERROR: abstract read of x9 returned %h (expected quotient %h) %t ns", dmi_readval, DIV_QUOTIENT, $time);
        error = error + 1;
    end else $display("PASS:  abstract read of x9 = completed quotient %h (DIV drained before halt) %t ns", DIV_QUOTIENT, $time);

    // KEY ASSERTION 2: the read must NOT be the stale pre-divide poison value.
    //   data0 == poison would mean allhalted asserted while the divide was still
    //   in flight => the drain-qualified-halted property is broken.
    if (dmi_readval === DIV_POISON) begin
        $display("ERROR: abstract read of x9 = poison %h => STALE pre-divide value (broken drain-qualification: allhalted asserted mid-divide) %t ns", DIV_POISON, $time);
        error = error + 1;
    end else $display("PASS:  abstract read of x9 != poison %h (no stale in-flight value observed) %t ns", DIV_POISON, $time);

    // Cross-check the abstract read against the actual register file.
    if (probes_cpu.x09 !== DIV_QUOTIENT) begin
        $display("ERROR: regfile x9=%h disagrees with completed quotient %h %t ns", probes_cpu.x09, DIV_QUOTIENT, $time);
        error = error + 1;
    end else $display("PASS:  abstract read agrees with regfile x9=%h while halted %t ns", probes_cpu.x09, $time);

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
    check_cpu_reg(20, X20_MARKER);     // post-divide marker => the hart really resumed
    check_cpu_reg( 9, DIV_QUOTIENT);   // destination still holds the completed quotient

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

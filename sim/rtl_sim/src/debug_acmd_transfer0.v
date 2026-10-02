//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_acmd_transfer0
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Access Register command with transfer=0 is a LEGAL NO-OP
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Per Debug Spec 1.0, an Access
//   Register command with transfer=0 (and postexec=0, aarpostincrement=0)
//   performs NO register transfer but must still complete successfully:
//     - NO-OP    : prime x5 with a firmware sentinel, prime data0 with garbage,
//                  issue transfer=0 / write=1 / aarsize=2 / regno=0x1005 (x5).
//                  Must complete with busy clear and cmderr=0, and the "write"
//                  must NOT land: a plain transfer=1 read of x5 (and the
//                  regfile probe) must still return the sentinel; data0 must
//                  still hold the garbage (no transfer happened in either
//                  direction);
//     - CONTROL  : transfer=1 write of x6 works normally (cmderr=0, value
//                  lands in the regfile);
//     - RESUME   : after resume the firmware adds 0x111 to the injected x6, so
//                  the final x6 = 0xCAFE0111 proves the control write reached
//                  the regfile AND the hart truly resumed; x5/x18 sentinels
//                  must be intact.
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
//   [22:20] aarsize=2 (32-bit) -> 0x00200000 ; [19] aarpostincrement=0 ;
//   [18] postexec=0 ; [17] transfer -> 0x00020000 ; [16] write -> 0x00010000 ;
//   [15:0] regno = 0x1000 + gpr_index  (x5 -> 0x1005 ; x6 -> 0x1006)
localparam [31:0] CMD_NOOP_WR_X5 = 32'h00200000 | 32'h00010000 | 32'h00001005; // = 0x00211005 (transfer=0!)
localparam [31:0] CMD_READ_X5    = 32'h00200000 | 32'h00020000 | 32'h00001005; // = 0x00221005
localparam [31:0] CMD_WRITE_X6   = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h00001006; // = 0x00231006
localparam [31:0] CMD_READ_X6    = 32'h00200000 | 32'h00020000 | 32'h00001006; // = 0x00221006

localparam [31:0] X5_SENTINEL  = 32'h5AFE0005;
localparam [31:0] DATA0_GARBAGE = 32'hBAD0BAD0;  // primed into data0 before the no-op
localparam [31:0] X6_INJECT    = 32'hCAFE0000;
localparam [31:0] X6_FINAL     = 32'hCAFE0111;   // injected + firmware post-resume +0x111
localparam [31:0] X18_SENTINEL = 32'hA5A5A5A5;

// Issue an abstract command and wait for abstractcs.busy to clear; the final
// abstractcs value (incl. cmderr) is left in dmi_readval.
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
      if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
         $display("ERROR: abstractcs.busy stuck after command %h %t ns", cmd, $time);
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

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG ACMD TRANSFER0: transfer=0 is a legal no-op (cmderr=0,       |");
    $display("|  NO side effects) - write must NOT land in the register file        |");
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
    end else $display("PASS:  hart in Debug Mode (abstract access permitted) %t ns", $time);

    //========================================================================
    // NO-OP: transfer=0 / write=1 / regno=x5 with garbage in data0.
    //   Must complete with cmderr=0 and must NOT touch x5 (or data0).
    //========================================================================
    dmi_write(DMI_DATA0, DATA0_GARBAGE);        // garbage that must NOT reach x5
    abs_run(CMD_NOOP_WR_X5);

    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after transfer=0 command (expected 0: legal no-op) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  transfer=0 command completed with cmderr=0 (legal no-op) %t ns", $time);

    // The "write" must NOT have landed: regfile probe still holds the sentinel.
    if (probes_cpu.x05 !== X5_SENTINEL) begin
        $display("ERROR: transfer=0 write LANDED: regfile x5=%h (expected sentinel %h) %t ns", probes_cpu.x05, X5_SENTINEL, $time);
        error = error + 1;
    end else $display("PASS:  regfile x5 untouched by the transfer=0 command (%h) %t ns", X5_SENTINEL, $time);

    // No transfer in either direction: data0 must still hold the garbage.
    dmi_read(DMI_DATA0);
    if (dmi_readval !== DATA0_GARBAGE) begin
        $display("ERROR: data0=%h after transfer=0 command (expected untouched %h) %t ns", dmi_readval, DATA0_GARBAGE, $time);
        error = error + 1;
    end else $display("PASS:  data0 untouched by the transfer=0 command (%h) %t ns", DATA0_GARBAGE, $time);

    // Cross-check over the DMI: a plain transfer=1 read of x5 returns the sentinel.
    abs_run(CMD_READ_X5);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after x5 read (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);
    if (dmi_readval !== X5_SENTINEL) begin
        $display("ERROR: abstract read of x5 returned %h (expected sentinel %h) %t ns", dmi_readval, X5_SENTINEL, $time);
        error = error + 1;
    end else $display("PASS:  abstract read of x5 still returns the sentinel %h %t ns", X5_SENTINEL, $time);

    //========================================================================
    // CONTROL: transfer=1 write of x6 works normally.
    //========================================================================
    dmi_write(DMI_DATA0, X6_INJECT);
    abs_run(CMD_WRITE_X6);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after control x6 write (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  control transfer=1 write completed with cmderr=0 %t ns", $time);

    if (probes_cpu.x06 !== X6_INJECT) begin
        $display("ERROR: regfile x6=%h after control write (expected %h) %t ns", probes_cpu.x06, X6_INJECT, $time);
        error = error + 1;
    end else $display("PASS:  control transfer=1 write reached regfile x6=%h %t ns", X6_INJECT, $time);

    // read x6 back over DMI as well
    abs_run(CMD_READ_X6);
    dmi_read(DMI_DATA0);
    if (dmi_readval !== X6_INJECT) begin
        $display("ERROR: abstract read-back of x6 returned %h (expected %h) %t ns", dmi_readval, X6_INJECT, $time);
        error = error + 1;
    end else $display("PASS:  abstract read-back of x6 returned injected %h %t ns", X6_INJECT, $time);

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

    // --- firmware must complete the loop and reach the end on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    // x5 sentinel: the transfer=0 "write" never landed, before or after resume.
    check_cpu_reg(5,  X5_SENTINEL);
    // final x6 = injected (0xCAFE0000) + firmware post-resume 0x111 => proves the
    // control write survived AND the hart really resumed and executed.
    check_cpu_reg(6,  X6_FINAL);
    // marker sentinel untouched by any abstract access
    check_cpu_reg(18, X18_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_abstract_options
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Access Register option fields (aarpostincrement streams,
//   transfer=0, postexec, aarsize, reserved bit, cmdtype, time/timeh)
//   debug_interface.md §6 "Abstract command engine":
//   - "Only the Access Register command is supported, and only in its 32-bit
//     form: cmdtype = 0, aarsize = 2 (32-bit), postexec = 0.
//     aarpostincrement is supported."
//   - "transfer = 0 is a legal no-op (per spec, regno/write are ignored when
//     transfer = 0): the command completes with cmderr = 0 and touches no
//     register."
//   - cmderr 2: "non-Access-Register cmd, aarsize != 2, postexec set, or
//     reserved bit 23 of the command word set"
//   - cmderr 3: "any regno outside the CSR and GPR ranges - FPR, vector, custom"
//   - "An error latches only from cmderr == 0; while cmderr != 0 no new
//     command is acted on (clear via W1C). A read captures its result into
//     data0 only on a non-faulting access."
//   - "time/timeh (0xC01/0xC81) are unsupported via abstract access ->
//     cmderr=2."
//   - "the effective regno increments by 1 after each successful transfer
//     ... running off a valid range simply yields an eventually-invalid regno
//     reported via cmderr".
//
//   A: rejected READS of x5 (postexec, aarsize 0/1/3/4, bit 23, cmdtype 1/2):
//      cmderr = 2, data0 keeps its preloaded sentinel
//   B: rejected WRITES of x5 (aarsize 1/3, bit 23, cmdtype 2): cmderr = 2,
//      x5 unchanged. postexec + write on x6: cmderr = 2 (x6 side effect is
//      reported, not asserted - see NOTE)
//   C: sticky cmderr: with cmderr = 2 latched a valid write of x7 is not
//      performed; after W1C the same write lands
//   D: time / timeh reads: cmderr = 2 (ZICNTR_EN=1), data0 unchanged
//   E: transfer = 0 with write=1 on x5 and with an FPR regno: cmderr = 0,
//      nothing written, data0 unchanged
//   F: aarpostincrement WRITE stream over x10..x17 (one command + 7 data0
//      writes with autoexecdata0)
//   G: aarpostincrement READ stream over x12..x15 (settle-read method, the
//      triggering read's own return is only reported)
//   H: postincrement read of x31, replay -> regno 0x1020 (FPR) -> cmderr = 3,
//      data0 keeps the value written by the triggering data0 write
//   I: cmdtype = 0xFF (command = 0xFF000000) -> cmderr = 2 ("not supported:
//      The command in command is not supported"), data0 unchanged, W1C clear
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

integer to;
reg [31:0] v, cap, x18_before;

localparam [6:0]  DMI_DATA0        = 7'h04;
localparam [6:0]  DMI_DMCONTROL    = 7'h10;
localparam [6:0]  DMI_ABSTRACTCS   = 7'h16;
localparam [6:0]  DMI_COMMAND      = 7'h17;
localparam [6:0]  DMI_ABSTRACTAUTO = 7'h18;

localparam [31:0] DMC_DMACTIVE     = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST   = 32'h10000000;
localparam [31:0] ACS_BUSY         = 32'h00001000;
localparam [31:0] ACS_CMDERR       = 32'h00000700;

localparam [31:0] CMD_RD           = 32'h00220000;   // aarsize=2, transfer
localparam [31:0] CMD_WR           = 32'h00230000;   // aarsize=2, transfer, write
localparam [31:0] AAR_SIZE_MASK    = 32'h00700000;
localparam [31:0] AAR_POSTINC      = 32'h00080000;   // [19]
localparam [31:0] AAR_POSTEXEC     = 32'h00040000;   // [18]
localparam [31:0] AAR_TRANSFER     = 32'h00020000;   // [17]
localparam [31:0] AAR_RSVD23       = 32'h00800000;   // [23]

localparam [31:0] SENT_DATA0       = 32'hD0D0D0D0;
localparam [31:0] BAD_DATA         = 32'hBAD0BAD0;

task chk;
   input [8*56:1] what;
   input [31:0]   got;
   input [31:0]   exp;
   begin
      if (got !== exp) begin
         $display("ERROR: %0s = %h (expected %h) %t ns", what, got, exp, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s = %h %t ns", what, got, $time);
   end
endtask

// abstractcs after busy drops, left in dmi_readval
task acs_wait;
   begin
      to = 0;
      dmi_read(DMI_ABSTRACTCS);
      while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
         dmi_read(DMI_ABSTRACTCS);
         to = to + 1;
      end
      if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
         $display("ERROR: abstractcs.busy stuck %t ns", $time);
         error = error + 1;
      end
   end
endtask

// Issue cmd, check cmderr == exp, W1C-clear it.
task cmd_expect;
   input [8*56:1] what;
   input [31:0]   cmd;
   input [2:0]    exp;
   begin
      dmi_write(DMI_COMMAND, cmd);
      acs_wait;
      chk(what, (dmi_readval & ACS_CMDERR) >> 8, {29'd0, exp});
      dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
   end
endtask

task rd_gpr;
   input  [15:0] regno;
   output [31:0] val;
   begin
      dmi_write(DMI_COMMAND, CMD_RD | regno);
      acs_wait;
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: read regno %h -> cmderr=%0d %t ns", regno, (dmi_readval & ACS_CMDERR) >> 8, $time);
         error = error + 1;
         dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
      end
      dmi_read(DMI_DATA0);
      val = dmi_readval;
   end
endtask

task data0_chk;
   input [8*56:1] what;
   input [31:0]   exp;
   begin
      dmi_read(DMI_DATA0);
      chk(what, dmi_readval, exp);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    $display("");
    $display(" ======================================================");
    $display("|  DEBUG ABSTRACT OPTIONS: Access Register fields       |");
    $display(" ======================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);

    //--------------------------------------------------------------------
    // A: rejected reads -> cmderr 2, data0 untouched
    //--------------------------------------------------------------------
    dmi_write(DMI_DATA0, SENT_DATA0);
    cmd_expect("A: read x5 postexec=1 -> cmderr",          CMD_RD | AAR_POSTEXEC | 32'h1005, 3'd2);
    data0_chk("A: data0 after the rejected postexec read", SENT_DATA0);
    cmd_expect("A: read x5 aarsize=3 -> cmderr",           (CMD_RD & ~AAR_SIZE_MASK) | 32'h00300000 | 32'h1005, 3'd2);
    cmd_expect("A: read x5 aarsize=0 -> cmderr",           (CMD_RD & ~AAR_SIZE_MASK) | 32'h1005, 3'd2);
    cmd_expect("A: read x5 aarsize=1 -> cmderr",           (CMD_RD & ~AAR_SIZE_MASK) | 32'h00100000 | 32'h1005, 3'd2);
    cmd_expect("A: read x5 aarsize=4 -> cmderr",           (CMD_RD & ~AAR_SIZE_MASK) | 32'h00400000 | 32'h1005, 3'd2);
    cmd_expect("A: read x5 reserved bit 23 -> cmderr",     CMD_RD | AAR_RSVD23 | 32'h1005, 3'd2);
    cmd_expect("A: cmdtype=1 (quick access) -> cmderr",    32'h01000000, 3'd2);
    cmd_expect("A: cmdtype=2 (access memory) -> cmderr",   32'h02200000, 3'd2);
    data0_chk("A: data0 after the rejected reads", SENT_DATA0);

    //--------------------------------------------------------------------
    // B: rejected writes -> cmderr 2, register untouched
    //--------------------------------------------------------------------
    dmi_write(DMI_DATA0, BAD_DATA);
    cmd_expect("B: write x5 aarsize=3 -> cmderr",          (CMD_WR & ~AAR_SIZE_MASK) | 32'h00300000 | 32'h1005, 3'd2);
    cmd_expect("B: write x5 aarsize=1 -> cmderr",          (CMD_WR & ~AAR_SIZE_MASK) | 32'h00100000 | 32'h1005, 3'd2);
    cmd_expect("B: write x5 reserved bit 23 -> cmderr",    CMD_WR | AAR_RSVD23 | 32'h1005, 3'd2);
    cmd_expect("B: cmdtype=2 write -> cmderr",             32'h02210000, 3'd2);
    chk("B: x5 (probe) after the rejected writes", probes_cpu.x05, 32'h55550005);
    rd_gpr(16'h1005, v);
    chk("B: x5 (abstract read) after rejected writes", v, 32'h55550005);

    dmi_write(DMI_DATA0, BAD_DATA);
    cmd_expect("B: write x6 postexec=1 -> cmderr",         CMD_WR | AAR_POSTEXEC | 32'h1006, 3'd2);
    if (probes_cpu.x06 === 32'h66660006)
        $display("NOTE:  B: postexec write rejected before the transfer (x6 unchanged) %t ns", $time);
    else
        $display("NOTE:  B: postexec write performed the transfer before failing (x6=%h) %t ns", probes_cpu.x06, $time);
    dmi_write(DMI_DATA0, 32'h66660006);           // restore x6 whatever happened
    cmd_expect("B: restore x6 -> cmderr",                  CMD_WR | 32'h1006, 3'd0);

    //--------------------------------------------------------------------
    // C: sticky cmderr gates a valid command
    //--------------------------------------------------------------------
    dmi_write(DMI_COMMAND, CMD_RD | AAR_RSVD23 | 32'h1007);   // cmderr = 2, not cleared
    acs_wait;
    chk("C: cmderr latched", (dmi_readval & ACS_CMDERR) >> 8, 32'd2);
    dmi_write(DMI_DATA0, 32'h7777C0DE);
    dmi_write(DMI_COMMAND, CMD_WR | 32'h1007);                // must not be acted on
    acs_wait;
    chk("C: cmderr still 2 after a command while set", (dmi_readval & ACS_CMDERR) >> 8, 32'd2);
    chk("C: x7 not written while cmderr != 0", probes_cpu.x07, 32'h77770007);
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
    dmi_read(DMI_ABSTRACTCS);
    chk("C: cmderr after W1C", (dmi_readval & ACS_CMDERR) >> 8, 32'd0);
    cmd_expect("C: same write once cleared -> cmderr",     CMD_WR | 32'h1007, 3'd0);
    chk("C: x7 written once cmderr cleared", probes_cpu.x07, 32'h7777C0DE);

    //--------------------------------------------------------------------
    // D: time / timeh through an abstract command
    //--------------------------------------------------------------------
    dmi_write(DMI_DATA0, SENT_DATA0);
    if (ZICNTR_EN != 0) begin
        cmd_expect("D: read time (0xC01) -> cmderr",       CMD_RD | 32'h0c01, 3'd2);
        cmd_expect("D: read timeh (0xC81) -> cmderr",      CMD_RD | 32'h0c81, 3'd2);
    end else begin
        dmi_write(DMI_COMMAND, CMD_RD | 32'h0c01);
        acs_wait;
        $display("NOTE:  D: ZICNTR_EN=0: read time -> cmderr=%0d (doc: 2; CSR absent) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        if (((dmi_readval & ACS_CMDERR) >> 8) === 32'd0) begin
            $display("ERROR: D: time read through an abstract command succeeded %t ns", $time);
            error = error + 1;
        end
        dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
    end
    data0_chk("D: data0 after the time/timeh reads", SENT_DATA0);

    //--------------------------------------------------------------------
    // E: transfer = 0 is a no-op whatever regno/write say
    //--------------------------------------------------------------------
    dmi_write(DMI_DATA0, 32'hFEEDFACE);
    cmd_expect("E: transfer=0 write x5 -> cmderr",         (CMD_WR & ~AAR_TRANSFER) | 32'h1005, 3'd0);
    chk("E: x5 untouched by transfer=0", probes_cpu.x05, 32'h55550005);
    cmd_expect("E: transfer=0 read FPR 0x1020 -> cmderr",  (CMD_RD & ~AAR_TRANSFER) | 32'h1020, 3'd0);
    data0_chk("E: data0 untouched by transfer=0", 32'hFEEDFACE);

    //--------------------------------------------------------------------
    // F: postincrement WRITE stream x10..x17
    //--------------------------------------------------------------------
    x18_before = probes_cpu.x18;
    dmi_write(DMI_DATA0, 32'h5EED000A);
    cmd_expect("F: write x10 postincrement -> cmderr",     CMD_WR | AAR_POSTINC | 32'h100a, 3'd0);
    dmi_write(DMI_ABSTRACTAUTO, 32'h1);
    for (ii = 11; ii <= 17; ii = ii + 1) begin
        dmi_write(DMI_DATA0, 32'h5EED0000 + ii);
        acs_wait;
        if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
            $display("ERROR: F: cmderr=%0d on the stream write to x%0d %t ns", (dmi_readval & ACS_CMDERR) >> 8, ii, $time);
            error = error + 1;
        end
    end
    dmi_write(DMI_ABSTRACTAUTO, 32'h0);           // before any data0 access: regno is x18 now
    chk("F: x10", probes_cpu.x10, 32'h5EED000A);
    chk("F: x11", probes_cpu.x11, 32'h5EED000B);
    chk("F: x12", probes_cpu.x12, 32'h5EED000C);
    chk("F: x13", probes_cpu.x13, 32'h5EED000D);
    chk("F: x14", probes_cpu.x14, 32'h5EED000E);
    chk("F: x15", probes_cpu.x15, 32'h5EED000F);
    chk("F: x16", probes_cpu.x16, 32'h5EED0010);
    chk("F: x17", probes_cpu.x17, 32'h5EED0011);
    chk("F: x18 not reached by the stream", probes_cpu.x18, x18_before);
    rd_gpr(16'h1011, v);
    chk("F: x17 (abstract read)", v, 32'h5EED0011);

    //--------------------------------------------------------------------
    // G: postincrement READ stream x12..x15 (settle reads)
    //--------------------------------------------------------------------
    cmd_expect("G: read x12 postincrement -> cmderr",      CMD_RD | AAR_POSTINC | 32'h100c, 3'd0);
    data0_chk("G: stream #0 (x12)", 32'h5EED000C);
    for (ii = 13; ii <= 15; ii = ii + 1) begin
        dmi_write(DMI_ABSTRACTAUTO, 32'h1);
        dmi_read(DMI_DATA0);                      // triggers the read of x<ii>
        cap = dmi_readval;
        acs_wait;
        if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
            $display("ERROR: G: cmderr=%0d on the stream read of x%0d %t ns", (dmi_readval & ACS_CMDERR) >> 8, ii, $time);
            error = error + 1;
        end
        dmi_write(DMI_ABSTRACTAUTO, 32'h0);
        dmi_read(DMI_DATA0);
        $display("INFO:  G: triggering read returned %h, settled data0 %h %t ns", cap, dmi_readval, $time);
        chk("G: stream settled value", dmi_readval, 32'h5EED0000 + ii);
    end

    //--------------------------------------------------------------------
    // H: postincrement past x31 -> FPR regno -> cmderr 3
    //--------------------------------------------------------------------
    cmd_expect("H: read x31 postincrement -> cmderr",      CMD_RD | AAR_POSTINC | 32'h101f, 3'd0);
    data0_chk("H: x31 read", 32'h11111111);
    dmi_write(DMI_ABSTRACTAUTO, 32'h1);
    dmi_write(DMI_DATA0, 32'hABCD1234);           // triggers the read of regno 0x1020
    acs_wait;
    chk("H: cmderr after running off x31", (dmi_readval & ACS_CMDERR) >> 8, 32'd3);
    dmi_write(DMI_ABSTRACTAUTO, 32'h0);
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
    data0_chk("H: data0 not captured by the failed read", 32'hABCD1234);
    chk("H: x31 unchanged", probes_cpu.x31, 32'h11111111);

    //--------------------------------------------------------------------
    // I: an unknown command type
    //--------------------------------------------------------------------
    dmi_write(DMI_DATA0, SENT_DATA0);
    cmd_expect("I: cmdtype=0xFF -> cmderr",                32'hFF000000, 3'd2);
    dmi_read(DMI_ABSTRACTCS);
    chk("I: cmderr after W1C", (dmi_readval & ACS_CMDERR) >> 8, 32'd0);
    data0_chk("I: data0 after the rejected command", SENT_DATA0);

    //--------------------------------------------------------------------
    // Resume
    //--------------------------------------------------------------------
    dmi_write(DMI_DATA0, 32'h1);
    cmd_expect("release: write x29 -> cmderr",             CMD_WR | 32'h101d, 3'd0);
    dm_resume;

    random_irq_enable = 0;
    wait (probes_cpu.x31 === 32'hdeadbeef);
    check_cpu_reg(5,  32'h55550005);
    check_cpu_reg(6,  32'h66660006);
    check_cpu_reg(7,  32'h7777C0DE);
    check_cpu_reg(10, 32'h5EED000A);
    check_cpu_reg(17, 32'h5EED0011);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

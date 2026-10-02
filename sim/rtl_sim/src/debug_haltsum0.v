//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_haltsum0
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: haltsum0 (DM 0x40) with the hart running, halted, held in
//   ndmreset and halted out of reset
//   debug_interface.md §6: "0x40 haltsum0 RO Halt Summary 0 (Debug Spec 1.0):
//   bit 0 = this hart halted; bits [31:1] = 0."
//   Debug 1.0 3.14.18: "Each bit in this read-only register indicates whether
//   one specific hart is halted or not. Unavailable/nonexistent harts are not
//   considered to be halted."
//   debug_interface.md §6 dmstatus: "anyhalted[8]/allhalted[9] (= hart halted)".
//
//   (a) running                      -> haltsum0 == 0
//   (b) haltreq, polled              -> haltsum0 == 1; whenever it reads 1 the
//                                       next dmstatus read shows allhalted
//   (c) resumed                      -> haltsum0 == 0
//   (d) ndmreset held (unavailable)  -> haltsum0 == 0
//   (e) released with resethaltreq   -> haltsum0 == 1 (dcsr.cause = 5)
//   (f) resumed, loop released by SBA -> haltsum0 == 0, firmware finishes
//   A write to haltsum0 is ignored (read-only).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
reg [31:0] v;

localparam [6:0]  DMI_DATA0      = 7'h04;
localparam [6:0]  DMI_DMCONTROL  = 7'h10;
localparam [6:0]  DMI_DMSTATUS   = 7'h11;
localparam [6:0]  DMI_ABSTRACTCS = 7'h16;
localparam [6:0]  DMI_COMMAND    = 7'h17;
localparam [6:0]  DMI_HALTSUM0   = 7'h40;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_NDMRESET   = 32'h00000002;
localparam [31:0] DMC_CLRRHR     = 32'h00000004;
localparam [31:0] DMC_SETRHR     = 32'h00000008;
localparam [31:0] DMC_HALTREQ    = 32'h80000000;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;

localparam [31:0] DMS_ALLHALTED  = 32'h00000200;
localparam [31:0] DMS_ALLRUNNING = 32'h00000800;
localparam [31:0] DMS_ALLUNAVAIL = 32'h00002000;

localparam [31:0] ACS_BUSY       = 32'h00001000;
localparam [31:0] ACS_CMDERR     = 32'h00000700;

localparam [31:0] CMD_RD         = 32'h00220000;
localparam [31:0] CMD_WR         = 32'h00230000;

task chk;
   input [8*48:1] what;
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
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: abstract command %h -> cmderr=%0d %t ns", cmd, (dmi_readval & ACS_CMDERR) >> 8, $time);
         error = error + 1;
         dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
      end
   end
endtask

task rd_haltsum0;
   input [8*48:1] what;
   input [31:0]   exp;
   begin
      dmi_read(DMI_HALTSUM0);
      chk(what, dmi_readval, exp);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    $display("");
    $display(" ======================================================");
    $display("|  DEBUG HALTSUM0: halt summary across hart states      |");
    $display(" ======================================================");

    wait (probes_cpu.x31 === 32'h11111111);

    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    to = 0;
    dmi_read(DMI_DMCONTROL);
    while (((dmi_readval & DMC_DMACTIVE) === 32'h0) && (to < 50)) begin
        dmi_read(DMI_DMCONTROL);
        to = to + 1;
    end
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    //--------------------------------------------------------------------
    // (a) running
    //--------------------------------------------------------------------
    dmi_read(DMI_DMSTATUS);
    chk("(a) dmstatus.allrunning", dmi_readval & DMS_ALLRUNNING, DMS_ALLRUNNING);
    rd_haltsum0("(a) haltsum0 while running", 32'h0);

    // read-only: a write must not change it
    dmi_write(DMI_HALTSUM0, 32'hFFFFFFFF);
    rd_haltsum0("(a) haltsum0 after a write (RO)", 32'h0);

    //--------------------------------------------------------------------
    // (b) halt: poll haltsum0 itself; a 1 must agree with dmstatus
    //--------------------------------------------------------------------
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
    to = 0;
    dmi_read(DMI_HALTSUM0);
    while ((dmi_readval === 32'h0) && (to < 200)) begin
        dmi_read(DMI_HALTSUM0);
        to = to + 1;
    end
    chk("(b) haltsum0 after haltreq", dmi_readval, 32'h1);
    dmi_read(DMI_DMSTATUS);
    chk("(b) dmstatus.allhalted once haltsum0=1", dmi_readval & DMS_ALLHALTED, DMS_ALLHALTED);
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: (b) haltsum0=1 but dbg_debug_mode=0 %t ns", $time);
        error = error + 1;
    end
    rd_haltsum0("(b) haltsum0 stable while halted", 32'h1);
    dmi_write(DMI_HALTSUM0, 32'h00000000);
    rd_haltsum0("(b) haltsum0 after a write (RO)", 32'h1);

    //--------------------------------------------------------------------
    // (c) resume
    //--------------------------------------------------------------------
    dm_resume;
    rd_haltsum0("(c) haltsum0 after resume", 32'h0);

    //--------------------------------------------------------------------
    // (d) hart held in reset by ndmreset: unavailable, not halted
    //--------------------------------------------------------------------
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_SETRHR);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_NDMRESET);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLUNAVAIL) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    chk("(d) dmstatus.allunavail under ndmreset", dmi_readval & DMS_ALLUNAVAIL, DMS_ALLUNAVAIL);
    rd_haltsum0("(d) haltsum0 while unavailable", 32'h0);
    repeat (20) @(posedge free_clk);
    rd_haltsum0("(d) haltsum0 while unavailable (later)", 32'h0);

    //--------------------------------------------------------------------
    // (e) release with resethaltreq: halted out of reset
    //--------------------------------------------------------------------
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 400)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    chk("(e) dmstatus.allhalted out of reset", dmi_readval & DMS_ALLHALTED, DMS_ALLHALTED);
    rd_haltsum0("(e) haltsum0 halted out of reset", 32'h1);
    abs_run(CMD_RD | 32'h07b0);
    dmi_read(DMI_DATA0);
    chk("(e) dcsr.cause (5=resethaltreq)", {29'd0, dmi_readval[8:6]}, 32'd5);

    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_CLRRHR);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dmi_write(DMI_DATA0, 32'h0);
    abs_run(CMD_WR | 32'h101f);                   // x31 = 0: the rerun sets it again

    //--------------------------------------------------------------------
    // (f) resume, release the loop over SBA, firmware finishes
    //--------------------------------------------------------------------
    dm_resume;
    rd_haltsum0("(f) haltsum0 after resume from reset-halt", 32'h0);

    wait (probes_cpu.x31 === 32'h11111111);
    sba_write32(32'h80000100, 32'h1);             // release flag (hart running)
    random_irq_enable = 0;
    wait (probes_cpu.x31 === 32'hdeadbeef);
    rd_haltsum0("(f) haltsum0 at end", 32'h0);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

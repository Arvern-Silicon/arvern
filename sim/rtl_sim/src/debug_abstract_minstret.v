//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_abstract_minstret
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG ABSTRACT - minstret/minstreth through Access Register while
//   halted. A debugger read is not a dispatched instruction, so it sees the count
//   exactly: an abstract write of X reads back X, twice (Debug 1.0 3.7.1.1; the
//   counter does not move while halted with the default stopcount).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

reg [31:0] pc_parked;
reg [31:0] target_addr;
reg [31:0] mtvec_val;
reg [31:0] dpc_now;
reg [31:0] dpc_prev;
reg [31:0] dcsr_now;
reg [2:0]  cause_now;
reg [31:0] csr_val;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_HALTREQ    = 32'h80000000;
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;

localparam [31:0] DMS_ALLHALTED    = 32'h00000200;
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800;
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000;

localparam [31:0] ACS_BUSY   = 32'h00001000;
localparam [31:0] ACS_CMDERR = 32'h00000700;

// Access Register command words (cmdtype=0, aarsize=2, transfer=1)
localparam [31:0] CMD_RD_DCSR   = 32'h002207b0;
localparam [31:0] CMD_WR_DCSR   = 32'h002307b0;
localparam [31:0] CMD_RD_DPC    = 32'h002207b1;
localparam [31:0] CMD_RD_X13    = 32'h0022100d;
localparam [31:0] CMD_WR_X12    = 32'h0023100c;
localparam [31:0] CMD_RD_MTVEC  = 32'h00220305;
localparam [31:0] CMD_RD_MEPC   = 32'h00220341;
localparam [31:0] CMD_RD_MCAUSE = 32'h00220342;
localparam [31:0] CMD_RD_MTVAL  = 32'h00220343;

localparam [31:0] DCSR_STEP = 32'h00000004;

localparam [31:0] X18_SENTINEL    = 32'hA5A5A5A5;
localparam [31:0] RD_SENTINEL     = 32'hDEAD0000;
localparam [31:0] MISALIGNED_ADDR = 32'h80000101;
localparam [31:0] X5_VAL          = 32'h00000011;
localparam [31:0] X6_VAL          = 32'h00000022;

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

task chk_cmderr;
   input [8*32:1] where;
   begin
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after %0s %t ns", (dmi_readval & ACS_CMDERR) >> 8, where, $time);
         error = error + 1;
      end
   end
endtask

task read_dpc;
   begin
      abs_run(CMD_RD_DPC);
      chk_cmderr("dpc read");
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      dpc_now = dmi_readval;
   end
endtask

task read_dcsr;
   begin
      abs_run(CMD_RD_DCSR);
      chk_cmderr("dcsr read");
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      dcsr_now  = dmi_readval;
      cause_now = dcsr_now[8:6];
   end
endtask

task read_csr;
   input  [31:0] cmd;
   input  [8*32:1] where;
   output [31:0] val;
   begin
      abs_run(cmd);
      chk_cmderr(where);
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      val = dmi_readval;
   end
endtask

// Single-step: drop haltreq, assert resumereq, poll allhalted for the auto re-halt.
task do_step;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
   end
endtask

// Common post-step checks: auto re-halt, dcsr.cause==4, dpc == expected.
task chk_step;
   input [8*32:1] what;
   input [31:0]   dpc_exp;
   begin
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: %0s did not auto re-halt (allhalted=0) %t ns", what, $time);
         error = error + 1;
      end else $display("PASS:  %0s auto re-halted (allhalted=1) %t ns", what, $time);
      read_dcsr;
      if (cause_now !== 3'd4) begin
         $display("ERROR: %0s dcsr.cause=%0d (expected 4=step) %t ns", what, cause_now, $time);
         error = error + 1;
      end else $display("PASS:  %0s dcsr.cause=4 (step) %t ns", what, $time);
      read_dpc;
      if (dpc_now !== dpc_exp) begin
         $display("ERROR: %0s dpc=%h (expected %h) %t ns", what, dpc_now, dpc_exp, $time);
         error = error + 1;
      end else $display("PASS:  %0s dpc=%h as expected %t ns", what, dpc_now, $time);
   end
endtask

localparam [31:0] ACS_CLR      = 32'h00000700;
localparam [31:0] CMD_RD_DSCR0 = 32'h002207b2;
localparam [31:0] CMD_WR_DSCR0 = 32'h002307b2;
localparam [31:0] CMD_RD_DSCR1 = 32'h002207b3;
localparam [31:0] CMD_RD_X15   = 32'h0022100f;
localparam [31:0] CMD_RD_X16   = 32'h00221010;
localparam [31:0] CMD_WR_X16   = 32'h00231010;
localparam [31:0] CMD_RD_F0    = 32'h00221020;   // FPR f0: no F extension
localparam [31:0] CMD_WR_F0    = 32'h00231020;
localparam [31:0] CMD_RD_CUST  = 32'h0022c000;   // custom regno range
localparam [31:0] CMD_RD_X0_64 = 32'h00321000;   // aarsize=3 (64-bit): unsupported option

task expect_cmderr;
   input [31:0]   cmd;
   input [2:0]    exp;
   input [8*24:1] what;
   begin
      abs_run(cmd);
      if (((dmi_readval & ACS_CMDERR) >> 8) !== exp) begin
         $display("ERROR: %0s: cmderr=%0d (expected %0d) %t ns", what, (dmi_readval & ACS_CMDERR) >> 8, exp, $time);
         error = error + 1;
      end else $display("PASS:  %0s: cmderr=%0d %t ns", what, exp, $time);
      dmi_write(DMI_ABSTRACTCS, ACS_CLR);             // W1C
   end
endtask

localparam [31:0] CMD_WR_MINSTRET  = 32'h00230b02;
localparam [31:0] CMD_RD_MINSTRET  = 32'h00220b02;
localparam [31:0] CMD_WR_MINSTRETH = 32'h00230b82;
localparam [31:0] CMD_RD_MINSTRETH = 32'h00220b82;

task abs_write;
   input [31:0] cmd;
   input [31:0] val;
   begin
      dmi_write(DMI_DATA0, val);
      abs_run(cmd);
      chk_cmderr("abstract write");
   end
endtask

task abs_read_chk;
   input [31:0]   cmd;
   input [31:0]   exp;
   input [8*24:1] what;
   begin
      abs_run(cmd);
      chk_cmderr("abstract read");
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      if (dmi_readval !== exp) begin
         $display("ERROR: %0s = 0x%h (expected 0x%h) %t ns", what, dmi_readval, exp, $time);
         error = error + 1;
      end else $display("PASS:  %0s = 0x%h %t ns", what, exp, $time);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    $display("");
    $display(" ===============================================");
    $display("|  DEBUG ABSTRACT: minstret write / read back   |");
    $display(" ===============================================");

    @(probes_cpu.x15 == 32'h11111111);
    repeat(20) @(posedge free_clk);                    // let the spin loop retire instructions
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);

    abs_write(CMD_WR_MINSTRET, 32'h00001000);
    abs_read_chk(CMD_RD_MINSTRET, 32'h00001000, "minstret after write");
    abs_read_chk(CMD_RD_MINSTRET, 32'h00001000, "minstret, second read");
    abs_write(CMD_WR_MINSTRETH, 32'h00000005);
    abs_read_chk(CMD_RD_MINSTRETH, 32'h00000005, "minstreth after write");
    abs_read_chk(CMD_RD_MINSTRET, 32'h00001000, "minstret after minstreth");

    dm_resume;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

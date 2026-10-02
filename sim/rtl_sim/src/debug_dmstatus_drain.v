//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmstatus_drain
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG DMSTATUS DRAIN - between a halt request and the halted
//   state, dmstatus reports the hart as running (never unavailable): the hart
//   is draining a multi-cycle op or a posted store, it has not disappeared.
//   Several halt/resume rounds at different alignments; every dmstatus poll
//   must show exactly one of allrunning / allhalted, and never anyunavail.
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

localparam [31:0] DMS_ANYUNAVAIL = 32'h00001000;
localparam [31:0] DMS_ANYHALTED   = 32'h00000100;
localparam [31:0] DMS_ANYRUNNING  = 32'h00000400;

integer round, polls, unavail_seen, bad_state;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    $display("");
    $display(" ===============================================");
    $display("|  DEBUG: dmstatus during the halt drain        |");
    $display(" ===============================================");

    @(probes_cpu.x31 == 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    unavail_seen = 0;
    bad_state    = 0;

    for (round = 0; round < 8; round = round + 1) begin
       repeat(round * 3 + 1) @(posedge free_clk);
       dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
       polls = 0;
       dmi_read(DMI_DMSTATUS);
       while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (polls < 400)) begin
          if ((dmi_readval & DMS_ANYUNAVAIL) !== 32'h0) unavail_seen = unavail_seen + 1;
          if ((((dmi_readval & DMS_ANYRUNNING) !== 32'h0) + ((dmi_readval & DMS_ANYHALTED) !== 32'h0)) != 1)
             bad_state = bad_state + 1;
          dmi_read(DMI_DMSTATUS);
          polls = polls + 1;
       end
       if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
          $display("ERROR: round %0d: hart did not halt %t ns", round, $time);
          error = error + 1;
       end
       dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
       dm_resume;
    end

    $display("dmstatus polls showing anyunavail: %0d, not exactly one of running/halted: %0d", unavail_seen, bad_state);
    if (unavail_seen != 0) begin
       $display("ERROR: dmstatus reported unavailable during a halt drain %t ns", $time);
       error = error + 1;
    end
    if (bad_state != 0) begin
       $display("ERROR: dmstatus not exactly one of running/halted %t ns", $time);
       error = error + 1;
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

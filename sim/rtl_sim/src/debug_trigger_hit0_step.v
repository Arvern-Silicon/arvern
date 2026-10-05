//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_hit0_step
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: a single step that halts on an armed execute trigger's address
// must not set mcontrol6.hit0 (the trigger did not fire). See the .s.
//----------------------------------------------------------------------------
`define VERY_LONG_TIMEOUT

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;
integer to;
reg [31:0] v, pre_pc, tgt_pc;

localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;
localparam [31:0] DMS_ALLHALTED  = 32'h00000200;
localparam [31:0] ACS_BUSY   = 32'h00001000;
localparam [31:0] ACS_CMDERR = 32'h00000700;
localparam [31:0] CMD_WR_TSELECT = 32'h00230000 | 32'h000007a0;
localparam [31:0] CMD_WR_TDATA1  = 32'h00230000 | 32'h000007a1;
localparam [31:0] CMD_RD_TDATA1  = 32'h00220000 | 32'h000007a1;
localparam [31:0] CMD_RD_DCSR    = 32'h00220000 | 32'h000007b0;
localparam [31:0] CMD_WR_DCSR    = 32'h00230000 | 32'h000007b0;
localparam [31:0] CMD_RD_DPC     = 32'h00220000 | 32'h000007b1;
localparam [31:0] CMD_WR_DPC     = 32'h00230000 | 32'h000007b1;
localparam [31:0] CMD_RD_A0      = 32'h00220000 | 32'h0000100a;
localparam [31:0] CMD_RD_A1      = 32'h00220000 | 32'h0000100b;
localparam [31:0] HIT0       = 32'h00400000;
localparam [31:0] DCSR_STEP  = 32'h00000004;
localparam [31:0] DCSR_CAUSE = 32'h000001C0;

reg [31:0] acmd_rdata;

// Issue an abstract command, wait busy clear; abstractcs left in dmi_readval.
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

// Abstract CSR/GPR write of `val` (expect cmderr==0).
task abs_wr;
   input [31:0] cmd;
   input [31:0] val;
   begin
      dmi_write(DMI_DATA0, val);
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after abstract write (cmd=%h val=%h) %t ns",
                  (dmi_readval & ACS_CMDERR) >> 8, cmd, val, $time);
         error = error + 1;
      end
   end
endtask

// Abstract CSR/GPR read (expect cmderr==0); data -> acmd_rdata.
task abs_rd;
   input [31:0] cmd;
   begin
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after abstract read (cmd=%h) %t ns",
                  (dmi_readval & ACS_CMDERR) >> 8, cmd, $time);
         error = error + 1;
      end
      dmi_read(DMI_DATA0);
      acmd_rdata = dmi_readval;
   end
endtask


initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|   STEP HALT ON AN ARMED EXECUTE TRIGGER: hit0 MUST STAY 0           |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      dmi_write(DMI_DMCONTROL, 32'h00000001);
      dm_halt;
      abs_rd(CMD_RD_A0); pre_pc = acmd_rdata;
      abs_rd(CMD_RD_A1); tgt_pc = acmd_rdata;

      // Step `pre`: the step halts with target (the trigger address) next
      abs_wr(CMD_WR_DPC, pre_pc);
      abs_rd(CMD_RD_DCSR);
      abs_wr(CMD_WR_DCSR, acmd_rdata | DCSR_STEP);
      dm_resume;
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 2000)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end

      abs_rd(CMD_RD_DCSR);
      v = acmd_rdata;
      if ((v & DCSR_CAUSE) !== 32'h00000100)
         begin $display("ERROR: dcsr.cause=%0d after the step, expected 4 (step)", (v & DCSR_CAUSE) >> 6); error = error + 1; end
      abs_rd(CMD_RD_DPC);
      if (acmd_rdata !== tgt_pc)
         begin $display("ERROR: dpc=0x%h after the step, expected the trigger address 0x%h", acmd_rdata, tgt_pc); error = error + 1; end
      abs_wr(CMD_WR_TSELECT, 32'h0);
      abs_rd(CMD_RD_TDATA1);
      $display("INFO:  tdata1 after the step halt = 0x%h", acmd_rdata);
      if ((acmd_rdata & HIT0) !== 32'h0)
         begin $display("ERROR: hit0=1 after a step halt -- the trigger did not fire"); error = error + 1; end
      else
         $display("PASS:  hit0=0 after the step halt");

      // Disarm, leave single-step, run to the end
      abs_wr(CMD_WR_TDATA1, 32'h0);
      abs_rd(CMD_RD_DCSR);
      abs_wr(CMD_WR_DCSR, acmd_rdata & ~DCSR_STEP);
      dm_resume;

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

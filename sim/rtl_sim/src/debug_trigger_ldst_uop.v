//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_ldst_uop
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdtrig LOAD WATCHPOINT (action=1) on a CM.POPRET pop load, a
//   CM.JT table read and a misaligned load. For each: the debugger halts the
//   spinning hart, arms trigger 0, resumes, and the hart must enter Debug Mode
//   by itself with dcsr.cause=2 and dpc = the watched instruction; the debugger
//   then disarms and resumes. The firmware results (return values, minstret
//   reference vs watched) are checked at the end.
//----------------------------------------------------------------------------

integer to;
integer nphases;

`define LONG_TIMEOUT

`define SPAD(byte_off)  ((byte_off)/4)

localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;
localparam [31:0] DMS_ALLHALTED  = 32'h00000200;
localparam [31:0] ACS_BUSY       = 32'h00001000;
localparam [31:0] ACS_CMDERR     = 32'h00000700;

localparam [31:0] CMD_WR_TSELECT = 32'h00230000 | 32'h000007a0;
localparam [31:0] CMD_WR_TDATA1  = 32'h00230000 | 32'h000007a1;
localparam [31:0] CMD_RD_DCSR    = 32'h00220000 | 32'h000007b0;
localparam [31:0] CMD_RD_DPC     = 32'h00220000 | 32'h000007b1;
localparam [31:0] CMD_RD_X6      = 32'h00220000 | 32'h00001006;

// type6 | dmode | action=1 | size=any | m | load | match=0
localparam [31:0] ARM_LD_TDATA1  = 32'h68001041;

localparam [31:0] DCSR_CAUSE         = 32'h000001C0;
localparam [31:0] DCSR_CAUSE_TRIGGER = 32'h00000080;

reg [31:0] acmd_rdata;
reg [31:0] expected_dpc;
reg [31:0] fell_through;

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

task abs_wr;
   input [31:0] cmd;
   input [31:0] val;
   begin
      dmi_write(DMI_DATA0, val);
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr after abstract write (cmd=%h) %t ns", cmd, $time);
         error = error + 1;
      end
   end
endtask

task abs_rd;
   input [31:0] cmd;
   begin
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr after abstract read (cmd=%h) %t ns", cmd, $time);
         error = error + 1;
      end
      dmi_read(DMI_DATA0);
      acmd_rdata = dmi_readval;
   end
endtask

// Halt, arm, resume, expect the watchpoint halt at x6, disarm, resume.
task watch_phase;
   input [8*8-1:0] name;
   begin
      dm_halt;
      abs_rd(CMD_RD_X6);
      expected_dpc = acmd_rdata;
      abs_wr(CMD_WR_TSELECT, 32'h0);
      abs_wr(CMD_WR_TDATA1, ARM_LD_TDATA1);
      dm_resume;

      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 20000)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: %0s: the watchpoint did not enter Debug Mode %t ns", name, $time);
         error = error + 1;
      end else begin
         abs_rd(CMD_RD_DCSR);
         if ((acmd_rdata & DCSR_CAUSE) !== DCSR_CAUSE_TRIGGER) begin
            $display("ERROR: %0s: dcsr.cause=%0d, expected 2 %t ns", name, (acmd_rdata & DCSR_CAUSE) >> 6, $time);
            error = error + 1;
         end
         abs_rd(CMD_RD_DPC);
         if (acmd_rdata !== expected_dpc) begin
            $display("ERROR: %0s: dpc=%h, expected %h %t ns", name, acmd_rdata, expected_dpc, $time);
            error = error + 1;
         end else
            $display("PASS:  %0s: Debug Mode entered, cause 2, dpc=%h %t ns", name, acmd_rdata, $time);
      end
      abs_wr(CMD_WR_TSELECT, 32'h0);
      abs_wr(CMD_WR_TDATA1, 32'h0);
      dm_resume;
   end
endtask

task check_equal;
   input [31:0] got;
   input [31:0] expected;
   input [8*40-1:0] what;
   begin
      if (got !== expected) begin
         $display("ERROR: %0s = 0x%h, expected 0x%h %t ns", what, got, expected, $time);
         error = error + 1;
      end
   end
endtask

// A sequence that falls through its CM.POPRET / CM.JT writes 0xBAD0BAD0
initial begin
   fell_through = 0;
   wait (probes_cpu.x31 === 32'hBAD0BAD0);
   fell_through = 1;
   $display("ERROR: a watched sequence fell through its UOP instruction %t ns", $time);
   error = error + 1;
end

initial begin
   @(posedge free_clk);
   @(posedge hresetn);

   error_on_exception = 0;                 // phase M traps as misaligned on purpose
   random_irq_enable  = 0;

   $display("");
   $display(" ====================================================================");
   $display("|  DEBUG TRIGGER LDST UOP: watchpoint on pop / table / misaligned     |");
   $display(" ====================================================================");

   dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
   dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

   nphases = 0;
   @(probes_cpu.x31==32'h11111111);
   watch_phase("P popret");
   nphases = nphases + 1;

   if (C_EXTENSION >= 4) begin
      @(probes_cpu.x31==32'h22222222);
      watch_phase("J cm.jt");
      nphases = nphases + 1;
   end

   @(probes_cpu.x31==32'h33333333);
   watch_phase("M misal");
   nphases = nphases + 1;

   @(probes_cpu.x31==32'hdeadbeef);
   repeat(40) @(posedge free_clk);

   // P: the popret re-executed and returned with s0/sp restored
   check_equal(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)], 32'h50505050, "P s0 after cm.popret");
   check_equal(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)], 32'h8000E000, "P sp after cm.popret");
   if (C_EXTENSION >= 4)
      check_equal(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)], 32'h1,  "J landed on the table target");
   // M: two misaligned traps (reference, then after the resume), nothing else
   check_equal(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)], 32'h2,  "trap count");
   check_equal(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)], 32'h4,  "last mcause");
   // The instruction that entered Debug Mode is retired once, as in the reference
   if (ZICNTR_EN) begin
      check_equal(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)], "P minstret delta (watched vs reference)");
      if (C_EXTENSION >= 4)
         check_equal(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)],
                     ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)], "J minstret delta (watched vs reference)");
      check_equal(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)], "M minstret delta (watched vs reference)");
   end
   $display("Watched phases: %0d", nphases);

   repeat(20) @(posedge free_clk);
   stimulus_done = 1;
end

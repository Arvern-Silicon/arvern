//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_ls_action1_idx
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: load and store watchpoints with action=1 on trigger index 1
//   and on the highest implemented index (DM_TRIGGER_NR-1)
//   debug_interface.md §8: "Load/store (data-address) watchpoints
//   (load/store=1, select=0): when tdata2 matches the data address, the
//   trigger fires at EX, before the access completes (store does not modify
//   memory; load does not update its destination): action=1 -> Debug Mode,
//   dcsr.cause=2, dpc = the load/store instruction's PC".
//   "hit0 ... Hardware sets it when that trigger fires"; "dmode write-
//   protection is whole-register: when a trigger's stored dmode=1, its entire
//   tdata1+tdata2 are read-only to M-mode software and writable only from the
//   debug path" (so every disarm here goes through abstract access).
//   debug_interface.md §7: "On resume: ... PC <- dpc".
//
//   Per phase (idx 1 load, idx 1 store, idx NR-1 load, idx NR-1 store), with
//   every other trigger disarmed:
//     - Debug Mode entry, dcsr.cause = 2, dcsr.prv = 3, dpc = &instruction
//     - load: destination still holds its PRE value
//     - store: the watched word still holds its sentinel (SBA read)
//     - hit0 set on the armed trigger only
//   After the last resume the firmware has re-executed every access.
//   With DM_TRIGGER_NR = 2 the two index choices coincide (index 1 twice).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

integer to, t, hi;
reg [31:0] v, pc_ld1, pc_st1, pc_ld2, pc_st2;
reg [7:0]  hit_mask;

localparam [6:0]  DMI_DATA0      = 7'h04;
localparam [6:0]  DMI_DMCONTROL  = 7'h10;
localparam [6:0]  DMI_DMSTATUS   = 7'h11;
localparam [6:0]  DMI_ABSTRACTCS = 7'h16;
localparam [6:0]  DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;
localparam [31:0] DMS_ALLHALTED  = 32'h00000200;
localparam [31:0] DMS_ALLRESACK  = 32'h00020000;
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;
localparam [31:0] ACS_BUSY       = 32'h00001000;
localparam [31:0] ACS_CMDERR     = 32'h00000700;

localparam [31:0] CMD_RD         = 32'h00220000;
localparam [31:0] CMD_WR         = 32'h00230000;

localparam [31:0] LD_DM          = 32'h68001041;   // type 6 | dmode | action=1 | m | load
localparam [31:0] ST_DM          = 32'h68001042;   // type 6 | dmode | action=1 | m | store

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

// Resume and wait for allresumeack only: the hart may re-halt on the next
// watchpoint before an allrunning poll would see it running.
task resume_ack;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLRESACK) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLRESACK) === 32'h0) begin
         $display("ERROR: resume not acknowledged %t ns", $time);
         error = error + 1;
      end
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

task rd_reg;
   input  [15:0] regno;
   output [31:0] val;
   begin
      abs_run(CMD_RD | regno);
      dmi_read(DMI_DATA0);
      val = dmi_readval;
   end
endtask

task wr_reg;
   input [15:0] regno;
   input [31:0] val;
   begin
      dmi_write(DMI_DATA0, val);
      abs_run(CMD_WR | regno);
   end
endtask

task disarm_all;
   begin
      for (t = 0; t < DM_TRIGGER_NR; t = t + 1) begin
         wr_reg(16'h07a0, t);
         wr_reg(16'h07a1, 32'h0);
      end
   end
endtask

task arm;
   input integer idx;
   input [31:0]  addr;
   input [31:0]  t1val;
   begin
      disarm_all;
      wr_reg(16'h07a0, idx);
      rd_reg(16'h07a0, v);
      chk("tselect read-back", v, idx);
      wr_reg(16'h07a2, addr);
      wr_reg(16'h07a1, t1val);
      rd_reg(16'h07a1, v);
      chk("tdata1 armed (hit0 clear)", v & 32'hF840F0FF, t1val);
   end
endtask

task resume_wait_halt;
   input [8*8:1] tag;
   begin
      resume_ack;
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 2000)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: %0s: watchpoint did not enter Debug Mode %t ns", tag, $time);
         error = error + 1;
      end
      rd_reg(16'h07b0, v);
      chk("dcsr.cause (2=trigger)", {29'd0, v[8:6]}, 32'd2);
      chk("dcsr.prv (3=M)", {30'd0, v[1:0]}, 32'd3);
   end
endtask

task chk_hits;
   input integer idx;
   begin
      hit_mask = 8'h00;
      for (t = 0; t < DM_TRIGGER_NR; t = t + 1) begin
         wr_reg(16'h07a0, t);
         rd_reg(16'h07a1, v);
         hit_mask[t] = v[22];
      end
      chk("hit0 per trigger", {24'd0, hit_mask}, 32'h1 << idx);
   end
endtask

task phase;
   input [8*8:1] tag;
   input integer idx;
   input         is_store;
   input [31:0]  addr;
   input [31:0]  pc;
   input [31:0]  pre;          // x5 PRE value (load) / watched-word sentinel (store)
   begin
      $display("----- %0s: %0s watchpoint, action=1, trigger %0d -----", tag, is_store ? "store" : "load", idx);
      arm(idx, addr, is_store ? ST_DM : LD_DM);
      resume_wait_halt(tag);
      rd_reg(16'h07b1, v);
      chk("dpc = &load/store instruction", v, pc);
      if (is_store) begin
         sba_read32(addr);
         chk("watched word not modified", sba_rdata, pre);
      end else begin
         rd_reg(16'h1005, v);
         chk("load destination x5 not updated", v, pre);
      end
      chk_hits(idx);
      wr_reg(16'h07a0, idx);
      wr_reg(16'h07a1, 32'h0);                  // disarm through the debug path
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    random_irq_enable = 0;

    $display("");
    $display(" ======================================================");
    $display("|  TRIGGERS: ld/st watchpoints, action=1, index 1 / max |");
    $display(" ======================================================");

    hi = DM_TRIGGER_NR - 1;

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;

    rd_reg(16'h1006, pc_ld1);
    rd_reg(16'h1007, pc_st1);
    rd_reg(16'h1008, pc_ld2);
    rd_reg(16'h1009, pc_st2);
    wr_reg(16'h101d, 32'h1);                      // x29: leave the wait loop

    phase("ld1", 1,  1'b0, 32'h80001000, pc_ld1, 32'hBEEF0000);
    phase("st1", 1,  1'b1, 32'h80001010, pc_st1, 32'h5A5A5A5A);
    phase("ld2", hi, 1'b0, 32'h80001020, pc_ld2, 32'hBEEF0001);
    phase("st2", hi, 1'b1, 32'h80001030, pc_st2, 32'h5C5C5C5C);

    disarm_all;
    dm_resume;

    wait (probes_cpu.x31 === 32'hdeadbeef);
    check_cpu_reg(21, 32'h0B0B0B0B);              // ld1 re-executed after resume
    check_cpu_reg(22, 32'hA5A5A5A5);              // st1 re-executed after resume
    check_cpu_reg(23, 32'h0C0C0C0C);              // ld2 re-executed after resume
    check_cpu_reg(24, 32'hC5C5C5C5);              // st2 re-executed after resume
    repeat(40) @(posedge free_clk);
    check_mem_value(`SPAD(32'h1010), 32'hA5A5A5A5);
    check_mem_value(`SPAD(32'h1030), 32'hC5C5C5C5);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

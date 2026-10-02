//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_multi_dmode
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: debugger-armed mcontrol6 triggers (action=1): trigger 1 alone,
//   all triggers on one instruction, and action=1 + action=0 together
//   Debug 1.0 5.3: "When multiple triggers in the same priority fire at once,
//   hit (if implemented) is set for all of them." / "... the hart must enter
//   Debug Mode and ignore the breakpoint exception. In the latter case, hit of
//   the trigger whose action is 0 must still be set".
//   dcsr.cause "2 (trigger): A Trigger Module trigger fired with action=1."
//   Table 9 (mcontrol6, hit1=0): dpc = "the address of the instruction which
//   caused the trigger to fire".
//
//   A: t1 on tgtA, t0 on tgtB (action=1) -> cause 2, dpc tgtA, hit0 {t1}
//   B: all triggers on tgtB (action=1)   -> cause 2, dpc tgtB, hit0 all
//   C: t0 action=0 + t1 action=1 on tgtC -> Debug Mode, hit0 {t0, t1}
//   Every hit0 check also requires the rest of tdata1 unchanged.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

integer to, t;

reg [31:0] v, dcsr_v, tgt_a, tgt_b, tgt_c, hnd;
reg [31:0] armed [0:7];
reg [7:0]  hit_mask, all_mask;

localparam [6:0]  DMI_DATA0      = 7'h04;
localparam [6:0]  DMI_DMCONTROL  = 7'h10;
localparam [6:0]  DMI_DMSTATUS   = 7'h11;
localparam [6:0]  DMI_ABSTRACTCS = 7'h16;
localparam [6:0]  DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;
localparam [31:0] DMS_ALLHALTED  = 32'h00000200;
localparam [31:0] DMS_ALLRESACK  = 32'h00020000;
localparam [31:0] ACS_BUSY       = 32'h00001000;
localparam [31:0] ACS_CMDERR     = 32'h00000700;

localparam [31:0] CMD_RD         = 32'h00220000;
localparam [31:0] CMD_WR         = 32'h00230000;

localparam [31:0] HIT0           = 32'h00400000;
localparam [31:0] EXEC_DM        = 32'h68001044;   // type 6 | dmode | action=1 | m | execute
localparam [31:0] EXEC_BP        = 32'h60000044;   // type 6 | action=0 | m | execute

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

task chk;
   input [8*40:1] what;
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

// Arm trigger idx (tdata1 cleared first, then tdata2, then tdata1) and keep
// the WARL read-back as the reference for the post-fire comparison.
task arm;
   input integer idx;
   input [31:0]  addr;
   input [31:0]  t1val;
   begin
      wr_reg(16'h07a0, idx);
      wr_reg(16'h07a1, 32'h0);
      wr_reg(16'h07a2, addr);
      wr_reg(16'h07a1, t1val);
      rd_reg(16'h07a1, v);
      armed[idx] = v;
      if (v[22] !== 1'b0) begin
         $display("ERROR: trigger %0d hit0 set right after arming (tdata1=%h) %t ns", idx, v, $time);
         error = error + 1;
      end
      if (v[15:12] !== t1val[15:12]) begin
         $display("ERROR: trigger %0d action read-back %0d (written %0d) %t ns", idx, v[15:12], t1val[15:12], $time);
         error = error + 1;
      end
   end
endtask

task disarm_all;
   begin
      for (t = 0; t < DM_TRIGGER_NR; t = t + 1) begin
         wr_reg(16'h07a0, t);
         wr_reg(16'h07a1, 32'h0);
         armed[t] = 32'h0;
      end
   end
endtask

// Read tdata1 of every trigger: hit0 pattern must be exp_hit, and every other
// bit must equal the armed read-back (untouched triggers keep reading as armed).
task chk_hits;
   input [8*2:1] tag;
   input [7:0]   exp_hit;
   begin
      hit_mask = 8'h00;
      for (t = 0; t < DM_TRIGGER_NR; t = t + 1) begin
         wr_reg(16'h07a0, t);
         rd_reg(16'h07a1, v);
         hit_mask[t] = v[22];
         $display("       %0s: trigger %0d tdata1 = %h", tag, t, v);
         if (armed[t] !== 32'h0 && ((v & ~HIT0) !== armed[t])) begin
            $display("ERROR: %0s: trigger %0d tdata1 changed beyond hit0 (%h, armed %h) %t ns", tag, t, v, armed[t], $time);
            error = error + 1;
         end
      end
      if (hit_mask !== exp_hit) begin
         $display("ERROR: %0s: hit0 per trigger = %b (expected %b) %t ns", tag, hit_mask, exp_hit, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s: hit0 per trigger = %b %t ns", tag, hit_mask, $time);
   end
endtask

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

task wait_trigger_halt;
   input [8*2:1] tag;
   begin
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 400)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: %0s: no trigger halt %t ns", tag, $time);
         error = error + 1;
      end
      rd_reg(16'h07b0, dcsr_v);
      chk("dcsr.cause (2=trigger)", {29'd0, dcsr_v[8:6]}, 32'd2);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    $display("");
    $display(" ======================================================");
    $display("|  TRIGGERS: multiple firing / index>=1, action=1      |");
    $display(" ======================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;

    rd_reg(16'h1005, tgt_a);
    rd_reg(16'h1006, tgt_b);
    rd_reg(16'h1007, tgt_c);
    rd_reg(16'h1008, hnd);
    all_mask = 8'h00;
    for (t = 0; t < DM_TRIGGER_NR; t = t + 1) begin
        all_mask[t] = 1'b1;
        armed[t]    = 32'h0;
    end

    //--------------------------------------------------------------------
    // A: trigger 1 alone matches (trigger 0 armed further down the code)
    //--------------------------------------------------------------------
    disarm_all;
    arm(1, tgt_a, EXEC_DM);
    arm(0, tgt_b, EXEC_DM);
    wr_reg(16'h101d, 32'h1);                     // x29: leave the wait loop
    resume_ack;
    wait_trigger_halt("A");
    rd_reg(16'h07b1, v);
    chk("A: dpc = tgtA", v, tgt_a);
    chk_hits("A", 8'b0000_0010);

    //--------------------------------------------------------------------
    // B: every trigger matches tgtB
    //--------------------------------------------------------------------
    disarm_all;
    for (t = 0; t < DM_TRIGGER_NR; t = t + 1) arm(t, tgt_b, EXEC_DM);
    resume_ack;
    wait_trigger_halt("B");
    rd_reg(16'h07b1, v);
    chk("B: dpc = tgtB", v, tgt_b);
    chk_hits("B", all_mask);
    chk("B: breakpoint exceptions (x27)", probes_cpu.x27, 32'h0);

    //--------------------------------------------------------------------
    // C: trigger 0 action=0 and trigger 1 action=1 on the same instruction
    //--------------------------------------------------------------------
    disarm_all;
    arm(0, tgt_c, EXEC_BP);
    arm(1, tgt_c, EXEC_DM);
    resume_ack;
    wait_trigger_halt("C");
    rd_reg(16'h07b1, v);
    if (v === tgt_c)
        $display("PASS:  C: dpc = tgtC (Debug Mode entered, breakpoint exception not taken first) %t ns", $time);
    else if (v === hnd)
        $display("NOTE:  C: dpc = m_handler (breakpoint exception taken first, then Debug Mode; allowed by 5.3) %t ns", $time);
    else begin
        $display("ERROR: C: dpc = %h (expected tgtC %h, or m_handler %h) %t ns", v, tgt_c, hnd, $time);
        error = error + 1;
    end
    chk_hits("C", 8'b0000_0011);

    disarm_all;
    resume_ack;

    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 4000)) begin @(posedge free_clk); to = to + 1; end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: firmware did not reach 0xdeadbeef (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end
    check_cpu_reg(21, 32'h000000A1);             // tgtA executed after resume
    check_cpu_reg(22, 32'h000000B2);             // tgtB executed after resume
    check_cpu_reg(23, 32'h000000C3);             // tgtC executed after resume
    $display("NOTE:  breakpoint exceptions taken for phase C: %0d (0 or 1 allowed by Debug 1.0 5.3)", probes_cpu.x27);
    if (probes_cpu.x27 > 32'd1) begin
        $display("ERROR: %0d breakpoint exceptions (at most 1, from phase C) %t ns", probes_cpu.x27, $time);
        error = error + 1;
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

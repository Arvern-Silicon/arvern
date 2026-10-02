//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_ldst_all
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: debugger-armed load watchpoint (action=1) on every trigger index
//   Debug 1.0 mcontrol6.action "1: Enter Debug Mode. dpc must contain the
//   virtual address of the next instruction that must be executed to
//   preserve the correct execution"; "This action is only legal when the
//   trigger's dmode is 1. Since tdata1 is WARL, hardware must prevent it
//   from containing dmode=0 and action=1." dcsr.cause "2 (trigger)".
//   A load watchpoint fires before the access is performed: dpc = the lw,
//   its destination register unchanged.
//
//   tdata1 = 0x68001041: type 6 | dmode | action=1 | m | load, match=equal.
//   For t = 0 .. DM_TRIGGER_NR-1 (no trigger work when 0):
//     trigger t armed on D_t (tselect t, tdata1 0, tdata2 D_t, tdata1),
//     resume -> Debug Mode with cause 2, dpc = &lw_site, x20 = t,
//     x5 = PRE, hit0 set on trigger t only;
//     trigger t disarmed, trigger t+1 armed, resume.
//   End: R_t = D_t for every t (each lw completed after the disarm), no trap.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

integer to, t, u;

reg [31:0] v, dcsr_v, lw_pc, armed_v;
reg [7:0]  hit_mask;

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
localparam [31:0] LD_DM          = 32'h68001041;   // type 6 | dmode | action=1 | m | load
localparam [31:0] D_BASE         = 32'h80001000;
localparam [31:0] D_VAL          = 32'h0D0D0D00;
localparam [31:0] PRE_LD         = 32'hBEEF0000;

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

// Arm trigger idx as a load watchpoint on addr; keep the WARL read-back.
task arm;
   input integer idx;
   input [31:0]  addr;
   begin
      wr_reg(16'h07a0, idx);
      wr_reg(16'h07a1, 32'h0);
      wr_reg(16'h07a2, addr);
      wr_reg(16'h07a1, LD_DM);
      rd_reg(16'h07a1, armed_v);
      if ((armed_v[31:28] !== 4'd6) || (armed_v[27] !== 1'b1) || (armed_v[15:12] !== 4'd1) ||
          (armed_v[6] !== 1'b1) || (armed_v[0] !== 1'b1) || (armed_v[22] !== 1'b0)) begin
         $display("ERROR: trigger %0d tdata1 read-back %h after writing %h %t ns", idx, armed_v, LD_DM, $time);
         error = error + 1;
      end
      rd_reg(16'h07a2, v);
      chk("tdata2 read-back", v, addr);
   end
endtask

task disarm;
   input integer idx;
   begin
      wr_reg(16'h07a0, idx);
      wr_reg(16'h07a1, 32'h0);
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

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    $display("");
    $display(" ======================================================");
    $display("|  TRIGGERS: load watchpoint action=1 on every index    |");
    $display(" ======================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;

    rd_reg(16'h1006, lw_pc);
    $display("INFO:  &lw_site = %h, DM_TRIGGER_NR = %0d %t ns", lw_pc, DM_TRIGGER_NR, $time);
    wr_reg(16'h101c, DM_TRIGGER_NR);                 // x28: iteration count
    if (DM_TRIGGER_NR > 0)
        arm(0, D_BASE);
    wr_reg(16'h101d, 32'h1);                         // x29: leave the wait loop
    resume_ack;

    for (t = 0; t < DM_TRIGGER_NR; t = t + 1) begin
        to = 0;
        dmi_read(DMI_DMSTATUS);
        while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 400)) begin
            dmi_read(DMI_DMSTATUS);
            to = to + 1;
        end
        if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
            $display("ERROR: trigger %0d: load watchpoint did not enter Debug Mode %t ns", t, $time);
            error = error + 1;
        end else
            $display("PASS:  trigger %0d: load watchpoint entered Debug Mode %t ns", t, $time);

        rd_reg(16'h07b0, dcsr_v);
        chk("dcsr.cause (2=trigger)", {29'd0, dcsr_v[8:6]}, 32'd2);
        rd_reg(16'h07b1, v);
        chk("dpc = &lw_site", v, lw_pc);
        rd_reg(16'h1014, v);
        chk("x20 (iteration) = trigger index", v, t);
        rd_reg(16'h1005, v);
        chk("x5 still PRE (load not performed)", v, PRE_LD);

        hit_mask = 8'h00;
        for (u = 0; u < DM_TRIGGER_NR; u = u + 1) begin
            wr_reg(16'h07a0, u);
            rd_reg(16'h07a1, v);
            hit_mask[u] = v[22];
            if (u == t) begin
                if ((v & ~HIT0) !== armed_v) begin
                    $display("ERROR: trigger %0d tdata1 %h changed beyond hit0 (armed %h) %t ns", u, v, armed_v, $time);
                    error = error + 1;
                end
            end else
                $display("       trigger %0d (disarmed) tdata1 = %h", u, v);
        end
        chk("hit0 per trigger", {24'd0, hit_mask}, 32'h1 << t);

        disarm(t);
        if (t + 1 < DM_TRIGGER_NR)
            arm(t + 1, D_BASE + 4*(t + 1));
        resume_ack;
    end

    random_irq_enable = 0;
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 20000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: firmware did not reach 0xdeadbeef (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end
    repeat(40) @(posedge free_clk);

    for (t = 0; t < DM_TRIGGER_NR; t = t + 1)
        check_mem_value(`SPAD(32'h1100 + 4*t), D_VAL + t);   // each lw completed
    check_cpu_reg(20, DM_TRIGGER_NR);
    check_cpu_reg(27, 32'h0);                                 // no trap

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

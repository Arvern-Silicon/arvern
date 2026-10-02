//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_su_only
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: mcontrol6 execute trigger with only the s and/or u bits set
//   fires in S / U and never in M
//   Debug 1.0 mcontrol6: "s: When set, enable this trigger in S/HS-mode.
//   This bit is hard-wired to 0 if the hart does not support S-mode." /
//   "u: When set, enable this trigger in U-mode. This bit is hard-wired to 0
//   if the hart does not support U-mode."
//   debug_interface.md §8: "m/s/u[6/4/3] (s/u read 0 when SU_MODE_EN=0)";
//   "action=0 -> breakpoint exception: mcause=3, mepc = matching PC,
//   mtval=0"; "action=1 -> enter Debug Mode, dcsr.cause=2, dpc = matching PC".
//   debug_interface.md §7: "On entry: ... dcsr.prv <- current privilege."
//
//   Expected breakpoint counts (firmware passes, see the .s):
//     pass 0 (s only):  M 0, S 1, U 0
//     pass 1 (u only):  M 0, S 0, U 1
//     pass 2 (s and u): M 0, S 1, U 1
//   SU_MODE_EN=0: only the M calls run, s/u read back 0, nothing fires.
//   Debugger pass (SU_MODE_EN=1): action=1 s-only trigger halts in S at tgt
//   (cause 2, prv 1, dpc = &tgt, hit0 set) after the M and U calls passed.
//   x20 (non-fired tgt executions): 8 with S/U, 3 without.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

integer to, p;
reg [31:0] v, tgt_addr;
reg [31:0] exp_rb [0:2];
reg [31:0] exp_s  [0:2];
reg [31:0] exp_u  [0:2];

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

localparam [31:0] RB_MASK        = 32'hF000005F;   // type, m, s, u, execute, store, load
localparam [31:0] EXEC_DM_S      = 32'h68001014;   // type 6 | dmode | action=1 | s | execute

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

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;                       // breakpoints and ecalls are the stimulus
    random_irq_enable  = 0;

    $display("");
    $display(" ======================================================");
    $display("|  TRIGGERS: s/u-only execute trigger vs privilege      |");
    $display(" ======================================================");

    if (SU_MODE_EN != 0) begin
        exp_rb[0] = 32'h60000014; exp_rb[1] = 32'h6000000C; exp_rb[2] = 32'h6000001C;
        exp_s[0]  = 1; exp_s[1] = 0; exp_s[2] = 1;
        exp_u[0]  = 0; exp_u[1] = 1; exp_u[2] = 1;
    end else begin
        exp_rb[0] = 32'h60000004; exp_rb[1] = 32'h60000004; exp_rb[2] = 32'h60000004;
        exp_s[0]  = 0; exp_s[1] = 0; exp_s[2] = 0;
        exp_u[0]  = 0; exp_u[1] = 0; exp_u[2] = 0;
    end

    //--------------------------------------------------------------------
    // Debugger pass: action=1, s only
    //--------------------------------------------------------------------
    if (SU_MODE_EN != 0) begin
        wait (probes_cpu.x31 === 32'h11111111);
        dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
        dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
        dm_halt;

        rd_reg(16'h1008, tgt_addr);
        wr_reg(16'h07a0, 32'h0);
        wr_reg(16'h07a1, 32'h0);
        wr_reg(16'h07a2, tgt_addr);
        wr_reg(16'h07a1, EXEC_DM_S);
        rd_reg(16'h07a1, v);
        chk("D: tdata1 armed (type/m/s/u/x/st/ld)", v & RB_MASK, EXEC_DM_S & RB_MASK);
        wr_reg(16'h101d, 32'h1);                  // x29: leave the wait loop
        resume_ack;

        to = 0;
        dmi_read(DMI_DMSTATUS);
        while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 2000)) begin
            dmi_read(DMI_DMSTATUS);
            to = to + 1;
        end
        chk("D: trigger halt (allhalted)", dmi_readval & DMS_ALLHALTED, DMS_ALLHALTED);
        rd_reg(16'h07b0, v);
        chk("D: dcsr.cause (2=trigger)", {29'd0, v[8:6]}, 32'd2);
        chk("D: dcsr.prv (1=S)", {30'd0, v[1:0]}, 32'd1);
        rd_reg(16'h07b1, v);
        chk("D: dpc = &tgt", v, tgt_addr);
        rd_reg(16'h07a1, v);
        chk("D: tdata1.hit0", {31'd0, v[22]}, 32'd1);
        chk("D: x20 before the S execution (M, U ran)", probes_cpu.x20, 32'd7);

        wr_reg(16'h07a1, 32'h0);                  // disarm through the debug path (dmode=1)
        dm_resume;
    end

    wait (probes_cpu.x31 === 32'hdeadbeef);
    repeat(40) @(posedge free_clk);

    for (p = 0; p < 3; p = p + 1) begin
        v = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10C + 4*p)];
        chk("tdata1 read-back (type/m/s/u/x/st/ld)", v & RB_MASK, exp_rb[p]);
        check_mem_value(`SPAD(32'h40*p + 32'hC), 32'd0);    // M: never fires
        check_mem_value(`SPAD(32'h40*p + 32'h4), exp_s[p]); // S
        check_mem_value(`SPAD(32'h40*p + 32'h0), exp_u[p]); // U
    end
    check_mem_value(`SPAD(32'h100), 32'd0);        // bad mepc
    check_mem_value(`SPAD(32'h104), 32'd0);        // bad mtval
    check_mem_value(`SPAD(32'h108), 32'd0);        // unexpected traps
    if (SU_MODE_EN != 0)
        check_cpu_reg(20, 8);
    else
        check_cpu_reg(20, 3);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

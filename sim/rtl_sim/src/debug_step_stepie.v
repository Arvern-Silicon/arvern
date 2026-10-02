//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_step_stepie
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: single-step with dcsr.stepie=0 vs stepie=1 (Debug 1.0 Sdext)
//   Debug 1.0 dcsr.stepie: "1 (interrupts enabled): Interrupts (including NMI)
//   are enabled during single stepping with step set."
//   Debug 1.0 4.5.1: "If control is transferred to a trap handler while
//   executing the instruction, then Debug Mode is re-entered immediately after
//   the PC is changed to the trap handler ... none of the trap handler is
//   executed". Table 9: dpc for single step = "Address of the instruction
//   that would be executed next if no debugging was going on."
//
//   A: MEI pending, stepie=0 -> cause 4, dpc = spin1, no trap (mcause/mepc
//      unchanged, mstatus.MIE still 1).
//   B: MEI pending, stepie=1 -> cause 4, dpc = irq_handler, mcause=0x8000000b,
//      mepc = spin1, mstatus.MIE=0/MPIE=1, handler flag x20 still 0.
//   C: NMI pending, stepie=0 -> dcsr.nmip=1, cause 4, dpc = spin2, no RNMI
//      (mncause/mnepc unchanged, NMIE still 1).
//   D: NMI pending, stepie=1 -> cause 4, dpc = nmi_handler, mncause=0x80000002,
//      mnepc = spin2, NMIE=0, handler flag x21 still 0.
//   After B and D, free-run: each handler runs exactly then (flag set).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

integer to;

reg [31:0] spin_pc, irq_h, nmi_h, v, dcsr_v, base_cause, base_epc;

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

localparam [31:0] DCSR_STEP      = 32'h00000004;
localparam [31:0] DCSR_NMIP      = 32'h00000008;
localparam [31:0] DCSR_STEPIE    = 32'h00000800;

// Access Register, aarsize=2, transfer=1 (+write)
localparam [31:0] CMD_RD         = 32'h00220000;
localparam [31:0] CMD_WR         = 32'h00230000;

// Abstract command; leaves the final abstractcs in dmi_readval and bumps error
// on cmderr != 0 (then clears it so the next command can run).
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

// Set dcsr step/stepie (read-modify-write, prv and the rest preserved) and
// check the two bits read back as written.
task set_step;
   input step_b;
   input stepie_b;
   begin
      rd_reg(16'h07b0, dcsr_v);
      dcsr_v = (dcsr_v & ~(DCSR_STEP | DCSR_STEPIE))
             | (step_b   ? DCSR_STEP   : 32'h0)
             | (stepie_b ? DCSR_STEPIE : 32'h0);
      wr_reg(16'h07b0, dcsr_v);
      rd_reg(16'h07b0, v);
      chk("dcsr.step",   {31'd0, v[2]},  {31'd0, step_b});
      chk("dcsr.stepie", {31'd0, v[11]}, {31'd0, stepie_b});
   end
endtask

// One single step: drop haltreq, resumereq, poll the automatic re-halt.
task do_step;
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
         $display("ERROR: step resume not acknowledged %t ns", $time);
         error = error + 1;
      end
      to = 0;
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: single step did not re-halt %t ns", $time);
         error = error + 1;
      end
      rd_reg(16'h07b0, dcsr_v);
      chk("dcsr.cause after step", {29'd0, dcsr_v[8:6]}, 32'd4);
   end
endtask

task wait_flag;
   input [8*20:1] what;
   input integer  xreg;
   begin
      to = 0;
      while ((((xreg == 20) ? probes_cpu.x20 : probes_cpu.x21) !== 32'h0000BEEF) && (to < 4000)) begin
         @(posedge free_clk); to = to + 1;
      end
      if (to >= 4000) begin
         $display("ERROR: %0s never ran after the free-run resume %t ns", what, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s ran after the free-run resume %t ns", what, $time);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    $display("");
    $display(" ================================================");
    $display("|  DEBUG STEP: dcsr.stepie=0 vs 1 (IRQ and NMI)  |");
    $display(" ================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;

    rd_reg(16'h100f, spin_pc);      // x15 = &spin1
    rd_reg(16'h100d, irq_h);        // x13 = &irq_handler
    rd_reg(16'h07b1, v);
    chk("dpc at halt (spin1)", v, spin_pc);

    //--------------------------------------------------------------------
    // A: machine external IRQ pending, stepie=0 -> not taken during step
    //--------------------------------------------------------------------
    set_step(1'b1, 1'b0);
    rd_reg(16'h0342, base_cause);
    rd_reg(16'h0341, base_epc);
    irq_m_external = 1'b1;
    repeat (4) @(posedge free_clk);

    do_step;
    rd_reg(16'h07b1, v);
    chk("A: dpc (stepie=0, next instr)", v, spin_pc);
    rd_reg(16'h0342, v);
    chk("A: mcause unchanged", v, base_cause);
    rd_reg(16'h0341, v);
    chk("A: mepc unchanged", v, base_epc);
    rd_reg(16'h0300, v);
    chk("A: mstatus.MIE still 1", {31'd0, v[3]}, 32'd1);
    chk("A: handler flag x20", probes_cpu.x20, 32'h0);

    //--------------------------------------------------------------------
    // B: same pending IRQ, stepie=1 -> taken, halt on handler entry
    //--------------------------------------------------------------------
    set_step(1'b1, 1'b1);
    do_step;
    rd_reg(16'h07b1, v);
    chk("B: dpc = irq_handler entry", v, irq_h);
    rd_reg(16'h0342, v);
    chk("B: mcause (M external IRQ)", v, 32'h8000000b);
    rd_reg(16'h0341, v);
    chk("B: mepc = spin1", v, spin_pc);
    rd_reg(16'h0300, v);
    chk("B: mstatus.MIE cleared by trap", {31'd0, v[3]}, 32'd0);
    chk("B: mstatus.MPIE set by trap",    {31'd0, v[7]}, 32'd1);
    chk("B: handler flag x20 (no handler instr)", probes_cpu.x20, 32'h0);

    set_step(1'b0, 1'b0);
    dm_resume;
    wait_flag("irq_handler", 20);
    irq_m_external = 1'b0;

    //--------------------------------------------------------------------
    // C: NMI pending, stepie=0 -> not taken during step
    //--------------------------------------------------------------------
    wait (probes_cpu.x31 === 32'h22222222);
    dm_halt;
    rd_reg(16'h100f, spin_pc);      // x15 = &spin2
    rd_reg(16'h100e, nmi_h);        // x14 = &nmi_handler
    rd_reg(16'h07b1, v);
    chk("dpc at halt (spin2)", v, spin_pc);
    rd_reg(16'h0744, v);
    chk("mnstatus.NMIE before step", {31'd0, v[3]}, 32'd1);

    set_step(1'b1, 1'b0);
    rd_reg(16'h0742, base_cause);
    rd_reg(16'h0741, base_epc);
    nmi = 1'b1;
    repeat (4) @(posedge free_clk);
    rd_reg(16'h07b0, v);
    chk("C: dcsr.nmip with NMI pending", {31'd0, v[3]}, 32'd1);

    do_step;
    rd_reg(16'h07b1, v);
    chk("C: dpc (stepie=0, next instr)", v, spin_pc);
    rd_reg(16'h0742, v);
    chk("C: mncause unchanged", v, base_cause);
    rd_reg(16'h0741, v);
    chk("C: mnepc unchanged", v, base_epc);
    rd_reg(16'h0744, v);
    chk("C: mnstatus.NMIE still 1", {31'd0, v[3]}, 32'd1);
    chk("C: handler flag x21", probes_cpu.x21, 32'h0);

    //--------------------------------------------------------------------
    // D: same pending NMI, stepie=1 -> RNMI taken, halt on handler entry
    //--------------------------------------------------------------------
    set_step(1'b1, 1'b1);
    do_step;
    rd_reg(16'h07b1, v);
    chk("D: dpc = nmi_handler entry", v, nmi_h);
    rd_reg(16'h0742, v);
    chk("D: mncause (nmi_i pin)", v, 32'h80000002);
    rd_reg(16'h0741, v);
    chk("D: mnepc = spin2", v, spin_pc);
    rd_reg(16'h0744, v);
    chk("D: mnstatus.NMIE cleared by RNMI", {31'd0, v[3]}, 32'd0);
    chk("D: handler flag x21 (no handler instr)", probes_cpu.x21, 32'h0);

    nmi = 1'b0;                      // NMIE=0: the pin can drop now
    set_step(1'b0, 1'b0);
    dm_resume;
    wait_flag("nmi_handler", 21);

    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 4000)) begin @(posedge free_clk); to = to + 1; end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: firmware did not reach 0xdeadbeef (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

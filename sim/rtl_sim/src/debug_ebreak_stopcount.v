//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_ebreak_stopcount
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG EBREAK + dcsr.stopcount -- Debug 1.0 dcsr.stopcount=1: "Don't
//   increment any hart-local counters while in Debug Mode or on ebreak instructions
//   that cause entry into Debug Mode." The firmware brackets an M-mode ebreak (ebreakm=1)
//   with two minstret reads; the debugger advances dpc past it and resumes.
//   The ebreak halts in decode before it is dispatched, so it never retires: minstret
//   advances by 1 (the first csrr only) with stopcount=1 AND with stopcount=0 (an ebreak
//   that enters Debug Mode is not an executed instruction, like one that traps).
//   Results: scratchpad 0x80000000 (pass 1), 0x80000004 (pass 2).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

integer to;

reg [31:0] v, dcsr_v, dpc_v, ebr_addr;

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

localparam [31:0] DCSR_EBREAKM   = 32'h00008000;
localparam [31:0] DCSR_EBREAKS   = 32'h00002000;
localparam [31:0] DCSR_EBREAKU   = 32'h00001000;

localparam [31:0] CMD_RD         = 32'h00220000;
localparam [31:0] CMD_WR         = 32'h00230000;

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

// Resume and wait for the resume acknowledge (the hart may re-halt on its
// next ebreak before a dmstatus.allrunning poll could see it running).
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

// Write the three ebreak bits (RMW, prv/step preserved) and check read-back.
task set_ebreak;
   input m_b, s_b, u_b;
   begin
      rd_reg(16'h07b0, dcsr_v);
      dcsr_v = (dcsr_v & ~(DCSR_EBREAKM | DCSR_EBREAKS | DCSR_EBREAKU))
             | (m_b ? DCSR_EBREAKM : 32'h0)
             | (s_b ? DCSR_EBREAKS : 32'h0)
             | (u_b ? DCSR_EBREAKU : 32'h0);
      wr_reg(16'h07b0, dcsr_v);
      rd_reg(16'h07b0, v);
      chk("dcsr.ebreakm read-back", {31'd0, v[15]}, {31'd0, m_b});
      chk("dcsr.ebreaks read-back", {31'd0, v[13]}, {31'd0, s_b & (SU_MODE_EN != 0)});
      chk("dcsr.ebreaku read-back", {31'd0, v[12]}, {31'd0, u_b & (SU_MODE_EN != 0)});
   end
endtask

// An ebreak must enter Debug Mode: halt, cause=1, prv, dpc = s6. Resume past it.
task expect_ebreak_halt;
   input [8*8:1] tag;
   input [1:0]   prv;
   begin
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 400)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: %0s ebreak did not enter Debug Mode %t ns", tag, $time);
         error = error + 1;
      end else begin
         $display("PASS:  %0s ebreak entered Debug Mode %t ns", tag, $time);
         rd_reg(16'h07b0, dcsr_v);
         chk("dcsr.cause (1=ebreak)", {29'd0, dcsr_v[8:6]}, 32'd1);
         chk("dcsr.prv at entry",     {30'd0, dcsr_v[1:0]}, {30'd0, prv});
         rd_reg(16'h1016, ebr_addr);                   // s6 = x22
         rd_reg(16'h07b1, dpc_v);
         chk("dpc = ebreak address",  dpc_v, ebr_addr);
         wr_reg(16'h07b1, dpc_v + 32'd4);
         resume_ack;
      end
   end
endtask

// Firmware slot check. exc=1: breakpoint exception expected with MPP = mpp.
// exc=0: Debug-Mode entry expected, so the handler never wrote the slot.
task chk_slot;
   input [8*12:1] tag;
   input [31:0]   off;
   input          exc;
   input [1:0]    mpp;
   reg   [31:0]   w;
   begin
      w = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off)];
      if (exc) begin
         if (w !== 32'd3) begin
            $display("ERROR: %0s: mcause = %h (expected 3, breakpoint exception) %t ns", tag, w, $time);
            error = error + 1;
         end else $display("PASS:  %0s: breakpoint exception (mcause 3) %t ns", tag, $time);
         w = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'h4)];
         if (w !== ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'hC)]) begin
            $display("ERROR: %0s: mepc = %h (expected ebreak at %h) %t ns", tag, w, ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'hC)], $time);
            error = error + 1;
         end
         w = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'h8)];
         if (w[12:11] !== mpp) begin
            $display("ERROR: %0s: mstatus.MPP = %0d (expected %0d) %t ns", tag, w[12:11], mpp, $time);
            error = error + 1;
         end
      end else begin
         if (w !== 32'd0) begin
            $display("ERROR: %0s: trap handler ran (mcause = %h), expected Debug-Mode entry %t ns", tag, w, $time);
            error = error + 1;
         end else $display("PASS:  %0s: no trap taken (Debug-Mode entry) %t ns", tag, $time);
      end
   end
endtask

localparam [31:0] DCSR_STOPCOUNT = 32'h00000400;

task one_pass;
   input stop;
   begin
      dm_halt;
      rd_reg(16'h07b0, dcsr_v);
      dcsr_v = (dcsr_v & ~DCSR_STOPCOUNT) | DCSR_EBREAKM | (stop ? DCSR_STOPCOUNT : 32'h0);
      wr_reg(16'h07b0, dcsr_v);
      rd_reg(16'h07b0, v);
      chk("dcsr.stopcount read-back", {31'd0, v[10]}, {31'd0, stop});
      wr_reg(16'h101d, 32'h1);                         // x29: release the pass
      resume_ack;
      expect_ebreak_halt("ebreak", 2'd3);              // checks cause/dpc, dpc += 4, resumes
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);
    error_on_exception = 0;

    $display("");
    $display(" ===================================================");
    $display("|  DEBUG EBREAK: dcsr.stopcount and minstret        |");
    $display(" ===================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    one_pass(1'b1);
    wait (probes_cpu.x31 === 32'h22222222);
    one_pass(1'b0);

    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 20000)) begin @(posedge free_clk); to = to + 1; end
    repeat(40) @(posedge free_clk);
    check_mem_value(`SPAD(32'h000), 32'd1);        // stopcount=1: ebreak not counted
    check_mem_value(`SPAD(32'h004), 32'd1);        // stopcount=0: still not counted (not dispatched)

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dpc_value_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: dpc walking-one / walking-zero values over abstract access
//   Debug 1.0 4.9.2: "The writability of dpc follows the same rules as mepc
//   as defined in the Privileged Spec. In particular, dpc must be able to
//   hold all valid virtual addresses and the writability of the low bits
//   depends on IALIGN"; "A debugger may write dpc to change where the hart
//   resumes." debug_interface.md dpc: "bit 0 always reads 0, and on a non-C
//   build (C_EXTENSION=0, IALIGN=32) bit 1 reads 0 as well".
//
//   Hart halted; dpc saved. Then:
//     walking ones   dpc <- (1<<k) | 1, k = 1..31     -> (1<<k) & mask
//     walking zeros  dpc <- ~(1<<k),    k = 0..31     -> ~(1<<k) & mask
//     all ones / zero                                 -> mask / 0
//   mask = ~1 (C implemented) or ~3 (no C). Every value is read twice with a
//   dcsr read in between (dpc stable, dcsr.cause = 3 haltreq). dpc restored,
//   read back, x29 = 1, resume; the firmware reaches deadbeef.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

integer to, k, nerr;

reg [31:0] dpc_saved, mask, wv, ev, v1, v2, dcsr_v;

localparam [6:0]  DMI_DATA0      = 7'h04;
localparam [6:0]  DMI_DMCONTROL  = 7'h10;
localparam [6:0]  DMI_ABSTRACTCS = 7'h16;
localparam [6:0]  DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;
localparam [31:0] ACS_BUSY       = 32'h00001000;
localparam [31:0] ACS_CMDERR     = 32'h00000700;

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

// Write dpc, read it, read dcsr, read dpc again.
task dpc_probe;
   input [31:0] wval;
   input [31:0] eval;
   begin
      wr_reg(16'h07b1, wval);
      rd_reg(16'h07b1, v1);
      rd_reg(16'h07b0, dcsr_v);
      rd_reg(16'h07b1, v2);
      if ((v1 !== eval) || (v2 !== eval)) begin
         $display("ERROR: dpc <- %h read %h / %h after a dcsr read (expected %h) %t ns", wval, v1, v2, eval, $time);
         error = error + 1;
         nerr = nerr + 1;
      end
      if (dcsr_v[8:6] !== 3'd3) begin
         $display("ERROR: dcsr.cause = %0d between dpc reads (expected 3) %t ns", dcsr_v[8:6], $time);
         error = error + 1;
         nerr = nerr + 1;
      end
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    $display("");
    $display(" ======================================================");
    $display("|  DEBUG dpc VALUE WALK                                 |");
    $display(" ======================================================");

    mask = (C_EXTENSION != 0) ? 32'hFFFFFFFE : 32'hFFFFFFFC;

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;

    rd_reg(16'h07b1, dpc_saved);
    $display("INFO:  saved dpc = %h %t ns", dpc_saved, $time);

    nerr = 0;
    for (k = 1; k < 32; k = k + 1) begin
        wv = (32'h1 << k) | 32'h1;
        dpc_probe(wv, wv & mask);
    end
    if (nerr == 0) $display("PASS:  dpc walking ones k=1..31 %t ns", $time);

    nerr = 0;
    for (k = 0; k < 32; k = k + 1) begin
        wv = ~(32'h1 << k);
        dpc_probe(wv, wv & mask);
    end
    if (nerr == 0) $display("PASS:  dpc walking zeros k=0..31 %t ns", $time);

    nerr = 0;
    dpc_probe(32'hFFFFFFFF, mask);
    dpc_probe(32'h00000000, 32'h00000000);
    if (nerr == 0) $display("PASS:  dpc all-ones / zero %t ns", $time);

    wr_reg(16'h07b1, dpc_saved);
    rd_reg(16'h07b1, v1);
    chk("dpc restored", v1, dpc_saved);

    wr_reg(16'h101d, 32'h1);                      // x29: leave the wait loop
    dm_resume;

    random_irq_enable = 0;
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 4000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: firmware did not reach 0xdeadbeef after the dpc restore (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end
    check_cpu_reg(18, 32'hA5A5A5A5);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

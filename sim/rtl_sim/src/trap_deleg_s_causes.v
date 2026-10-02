//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_deleg_s_causes
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: medeleg routing of causes 0/1/3/5/7 from U and S, and from M
//   Priv §3.1.8: a set medeleg bit delegates the trap "when occurring in
//   S-mode or U-mode, to the S-mode trap handler"; "Traps never transition
//   from a more-privileged mode to a less-privileged mode". For every case:
//   the handler (S when delegated from U/S, M otherwise), cause, epc, tval
//   (doc §2 table), previous privilege, medeleg readback and a single trap.
//   Cause 0 runs only at C_EXTENSION=0; causes 1/5/7 only at PMP_NR>0.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)
`define MEM(byte_off)   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(byte_off)]

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] base;
reg [31:0] cause_of [0:4];
reg [31:0] tval_of  [0:4];
reg        en_of    [0:4];
integer    org, nodeleg, col, idx;
reg [31:0] exp_id, exp_pp, exp_deleg, exp_tval;

task check_case;
   input integer index;
   input integer c;
   input [31:0] id;
   input [31:0] pp;
   input [31:0] deleg;
   begin
      base     = 32'h100 + index*64;
      exp_tval = (c == 0) ? `MEM(base + 24) : tval_of[c];
      $display("");
      $display("--- slot %0d: cause %0d, expected handler %s, previous priv %0d ---", index, cause_of[c], (id == 2) ? "S" : "M", pp);
      check_mem_value(`SPAD(base + 0),  id);
      check_mem_value(`SPAD(base + 4),  cause_of[c]);
      check_mem_value(`SPAD(base + 8),  `MEM(base + 20));
      check_mem_value(`SPAD(base + 12), exp_tval);
      check_mem_value(`SPAD(base + 16), pp);
      check_mem_value(`SPAD(base + 28), deleg);
      check_mem_value(`SPAD(base + 32), 32'h00000001);
   end
endtask

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      cause_of[0] = 32'd0;  tval_of[0] = 32'h0;          en_of[0] = (C_EXTENSION == 0);
      cause_of[1] = 32'd1;  tval_of[1] = 32'h80004000;   en_of[1] = (PMP_NR > 0);
      cause_of[2] = 32'd3;  tval_of[2] = 32'h00000000;   en_of[2] = 1'b1;
      cause_of[3] = 32'd5;  tval_of[3] = 32'h80004044;   en_of[3] = (PMP_NR > 0);
      cause_of[4] = 32'd7;  tval_of[4] = 32'h80004008;   en_of[4] = (PMP_NR > 0);

      wait(probes_cpu.x31 == 32'h11111111);
      $display("medeleg cause routing: init done %t ns", $time);
      wait(probes_cpu.x31 == 32'h22222222);
      $display("U-origin cases done %t ns", $time);
      wait(probes_cpu.x31 == 32'h33333333);
      $display("S-origin cases done %t ns", $time);

      wait(probes_cpu.x31 == 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|     medeleg: U/S traps to S when delegated, to M otherwise         |");
      $display(" ====================================================================");

      for (org = 0; org < 2; org = org + 1)
         for (nodeleg = 0; nodeleg < 2; nodeleg = nodeleg + 1)
            for (col = 0; col < 5; col = col + 1)
               if (en_of[col]) begin
                  idx       = org*10 + nodeleg*5 + col;
                  exp_id    = nodeleg ? 32'd1 : 32'd2;
                  exp_pp    = org;
                  exp_deleg = nodeleg ? 32'h0 : (32'h1 << cause_of[col]);
                  check_case(idx, col, exp_id, exp_pp, exp_deleg);
               end

      $display("");
      $display(" ====================================================================");
      $display("|     M-origin traps stay in M although delegated                    |");
      $display(" ====================================================================");
      exp_deleg = 32'h8 | ((C_EXTENSION == 0) ? 32'h1 : 32'h0) | ((PMP_NR > 0) ? 32'hA2 : 32'h0);
      if (C_EXTENSION == 0)
         check_case(20, 0, 32'd1, 32'd3, exp_deleg);
      check_case(22, 2, 32'd1, 32'd3, exp_deleg);

      $display("");
      $display("--- no unexpected trap ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

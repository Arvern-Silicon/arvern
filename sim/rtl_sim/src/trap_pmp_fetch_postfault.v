//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_fetch_postfault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: nothing past a PMP fetch fault may execute
//
//   a3/a4 are canaries planted in the two executable words that follow the
//   refused one. Either changing means a word fetched behind the fault was
//   dispatched before the fault was reported.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|             PMP FETCH: NOTHING PAST THE FAULT EXECUTES              |");
      $display(" ====================================================================");
      $display("");

      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Probe 1: jump onto the last word of D ---");
      check_mem_value(`SPAD(32'h100), 32'd1);          // cause 1
      check_mem_value(`SPAD(32'h104), 32'h8000041C);   // at LAST
      $display("--- Probe 2: flow into D from the nops before it ---");
      check_mem_value(`SPAD(32'h108), 32'd1);          // cause 1
      check_mem_value(`SPAD(32'h10C), 32'h80000410);   // at D+0
      $display("--- canaries behind the fault never ran ---");
      check_cpu_reg(13, 32'h0000600D);   // a3
      check_cpu_reg(14, 32'h0000600D);   // a4
      check_cpu_reg(10, 32'h00000002);   // a0: exactly two traps

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

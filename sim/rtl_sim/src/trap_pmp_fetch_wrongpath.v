//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_fetch_wrongpath
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP fetch faults on the wrong path and on a redirect target
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
      $display("|         PMP FETCH: WRONG-PATH PREFETCH vs REDIRECT TARGET          |");
      $display(" ====================================================================");
      $display("");

      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Probes 1, 2: prefetch into D behind a taken ret -- discarded ---");
      check_mem_value(`SPAD(32'h100), 32'd0);
      check_mem_value(`SPAD(32'h108), 32'd0);
      $display("--- Probe 3: prefetch into D behind a trap redirect -- discarded ---");
      check_mem_value(`SPAD(32'h110), 32'd11);
      $display("--- Probe 4: D as a jalr target -- reported ---");
      check_mem_value(`SPAD(32'h118), 32'd1);
      check_mem_value(`SPAD(32'h11C), 32'h80000410);
      $display("--- Probe 5: D as an mret target -- reported ---");
      check_mem_value(`SPAD(32'h120), 32'd1);
      check_mem_value(`SPAD(32'h124), 32'h80000410);
      $display("--- exactly three traps in total ---");
      check_cpu_reg(10, 32'h00000003);

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

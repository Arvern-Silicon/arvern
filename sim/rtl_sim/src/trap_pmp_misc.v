//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_misc
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP -- NA4, execute-only, and misaligned-access priority
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
      $display("|          PMP: NA4 / EXECUTE-ONLY / MISALIGNED PRIORITY             |");
      $display(" ====================================================================");
      $display("");

      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- NA4 is exactly four bytes ---");
      check_mem_value(`SPAD(32'h100), 32'd7);
      check_mem_value(`SPAD(32'h104), 32'h80000400);
      check_mem_value(`SPAD(32'h108), 32'd0);          // below: no trap
      check_mem_value(`SPAD(32'h110), 32'd0);          // above: no trap
      check_cpu_reg(10, 32'h5A5A5A5A);   // a0: word below was written
      check_cpu_reg(11, 32'h22220000);   // a1: the region itself was not
      check_cpu_reg(12, 32'h5A5A5A5A);   // a2: word above was written

      $display("--- execute-only: runs, unreadable ---");
      check_mem_value(`SPAD(32'h118), 32'd0);          // jalr: no trap
      check_mem_value(`SPAD(32'h120), 32'd5);
      check_mem_value(`SPAD(32'h124), 32'h80000500);

      $display("--- PMP denial outranks the misalignment (Priv 3.1.15: either is legal) ---");
      check_mem_value(`SPAD(32'h128), 32'd5);          // aligned load:  PMP
      check_mem_value(`SPAD(32'h130), 32'd5);          // misaligned:    still the PMP fault
      check_mem_value(`SPAD(32'h134), 32'h80000602);
      check_mem_value(`SPAD(32'h138), 32'd7);          // aligned store: PMP
      check_mem_value(`SPAD(32'h140), 32'd7);          // misaligned:    still the PMP fault
      check_mem_value(`SPAD(32'h144), 32'h80000602);
      check_cpu_reg(13, 32'h00000006);   // a3: six traps

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

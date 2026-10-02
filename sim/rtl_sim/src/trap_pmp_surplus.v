//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_surplus
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP entries beyond PMP_NR are read-only zero and inert
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|         PMP SURPLUS ENTRIES ARE READ-ONLY ZERO (PMP_NR=%0d)          |", PMP_NR);
      $display(" ====================================================================");
      $display("");

      wait(probes_cpu.x31==32'h11111111 || probes_cpu.x31==32'h0BAD0BAD);
      repeat(3) @(posedge free_clk);
      if (probes_cpu.x31==32'h0BAD0BAD) begin
         $display("ERROR: a trap was taken -- a surplus entry took effect   %t ns", $time);
         error = error + 1;
      end

      $display("--- entry 15: writes ignored, rule inert ---");
      check_cpu_reg(10, 32'h00000000);   // a0: pmpaddr15
      check_cpu_reg(11, 32'h00000000);   // a1: pmpcfg3
      check_cpu_reg(12, 32'h12345678);   // a2: the store landed
      $display("--- first surplus entry reads zero; last writable entry does not ---");
      check_cpu_reg(13, 32'h00000000);   // a3
      check_cpu_reg(14, 32'h00000000);   // a4
      check_cpu_reg(15, 32'h0BADF00D);   // a5
      check_cpu_reg(16, 32'h01000000);   // a6

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

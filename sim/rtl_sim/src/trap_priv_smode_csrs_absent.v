//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_smode_csrs_absent
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SU_MODE PRIV - S-mode CSRs, and the M-mode registers that only
//              serve a lower privilege, are absent when SU_MODE_EN=0
//
//   Fifteen addresses, read and written, must each raise illegal-instruction --
//   30 traps in total. A RAZ/WI implementation would take none of them, so the
//   trap count is what makes this a real check rather than a vacuous one.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Every CSR access in this test is expected to trap.
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|      S-MODE / LOWER-PRIVILEGE CSRs ABSENT  (SU_MODE_EN = 0)         |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 2: all fifteen reads trap
      //=================================================================
      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 2: reads raise illegal-instruction ---");
      check_cpu_reg(10, 32'd15);          // a0: one trap per read
      check_cpu_reg(11, 32'd2);           // a1: MCAUSE = illegal instruction

      //=================================================================
      // PHASE 3/4: all fifteen writes trap; misa advertises neither S nor U
      //=================================================================
      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 3: writes raise illegal-instruction ---");
      check_cpu_reg(12, 32'd30);          // a2: 15 reads + 15 writes

      $display("--- Phase 4: misa[18] (S) and misa[20] (U) are zero ---");
      if (probes_cpu.x13[18] !== 1'b0) begin
         $display("ERROR: misa[18] (S) = %0b, expected 0 %t ns", probes_cpu.x13[18], $time);
         error = error + 1;
      end
      if (probes_cpu.x13[20] !== 1'b0) begin
         $display("ERROR: misa[20] (U) = %0b, expected 0 %t ns", probes_cpu.x13[20], $time);
         error = error + 1;
      end
      if (probes_cpu.x13[18] === 1'b0 && probes_cpu.x13[20] === 1'b0)
         $display("PASS:  misa = 0x%08x -- neither S nor U advertised", probes_cpu.x13);

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_fetch
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP fetch checker
//
//   A locked rule without X denies instruction fetch (MCAUSE=1) while still
//   granting reads, and the denied fetch is suppressed rather than performed.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // The test takes PMP faults on purpose.
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|                       PMP FETCH CHECKER                            |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 1: a locked rule without X denies the fetch
      //=================================================================
      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 1: locked rule without X, fetch denied ---");
      check_cpu_reg(10, 32'h00000001);   // a0: MCAUSE = instruction access fault
      check_cpu_reg(11, 32'h80000300);   // a1: MEPC   = the unfetchable address
      check_cpu_reg(12, 32'h80000300);   // a2: MTVAL  = the unfetchable address

      //=================================================================
      // PHASE 2: the same rule still grants reads
      //=================================================================
      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 2: no execute, but still readable ---");
      check_cpu_reg(13, 32'h00000007);   // a3: MCAUSE = store access fault
      check_cpu_reg(14, 32'hC0DE0000);   // a4: the seed, so the denied store never landed
      check_cpu_reg(15, 32'h00000002);   // a5: exactly two faults

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

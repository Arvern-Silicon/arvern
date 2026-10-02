//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_ldst
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP load/store checker
//
//   Machine mode throughout. Checks that an unlocked rule leaves M-mode alone,
//   that a locked one does not, that MCAUSE separates load (5) from store (7),
//   that MTVAL carries the faulting data address, and that a denied store never
//   reaches memory.
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
      $display("|                    PMP LOAD/STORE CHECKER                          |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 1: an UNLOCKED rule does not bind M-mode
      //=================================================================
      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 1: unlocked rule, machine mode is not bound ---");
      check_cpu_reg(11, 32'h11110000);   // a1: the store landed
      check_cpu_reg(10, 32'h00000000);   // a0: and took no trap

      //=================================================================
      // PHASE 2: a LOCKED rule binds M-mode -- store gives MCAUSE 7
      //=================================================================
      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 2: locked rule, store denied ---");
      check_cpu_reg(12, 32'h00000007);   // a2: MCAUSE = store access fault
      check_cpu_reg(13, 32'h80000210);   // a3: MTVAL  = faulting address

      //=================================================================
      // PHASE 3: load denied too, and the denied store never landed
      //=================================================================
      wait(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 3: locked rule, load denied; memory untouched ---");
      check_cpu_reg(14, 32'hEE110000);   // a4: destination register unwritten
      check_cpu_reg(15, 32'h00000005);   // a5: MCAUSE = load access fault
      check_cpu_reg(16, 32'h80000210);   // a6: MTVAL  = faulting address
      check_cpu_reg(24, 32'hBBBB0000);   // s8: the seed, so the store was suppressed

      //=================================================================
      // PHASE 4: a locked read-only rule permits the load, refuses the store
      //=================================================================
      wait(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 4: locked read-only rule ---");
      check_cpu_reg(17, 32'hCCCC0000);   // a7: the load was allowed
      check_cpu_reg(18, 32'h00000007);   // s2: MCAUSE = store access fault
      check_cpu_reg(19, 32'h80000220);   // s3: MTVAL  = faulting address
      check_cpu_reg(23, 32'h00000003);   // s7: exactly three faults in total

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_tor
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP top-of-range (TOR) matching
//
//   Checks both edges of [pmpaddr[g-1], pmpaddr[g]). The lower edge is the one
//   that matters: it is derived from the neighbouring entry's bound, so dropping
//   or mis-deriving it would silently extend the region down to address zero.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|                    PMP TOP-OF-RANGE MATCHING                       |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 1: inside the range -- read allowed, write refused
      //=================================================================
      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 1: inside [LO,HI) -- locked read-only ---");
      check_cpu_reg(10, 32'hBB000000);   // a0: the load was permitted
      check_cpu_reg(11, 32'h00000007);   // a1: MCAUSE = store access fault
      check_cpu_reg(12, 32'h80000400);   // a2: MTVAL  = the faulting address

      //=================================================================
      // PHASE 2/3: both edges -- outside the range, machine mode proceeds
      //=================================================================
      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 2: one word BELOW the lower bound ---");
      check_cpu_reg(13, 32'h22220000);   // a3: the store landed, so no match
      $display("--- Phase 3: at the upper bound (TOR is exclusive) ---");
      check_cpu_reg(14, 32'h33330000);   // a4: the store landed, so no match
      check_cpu_reg(15, 32'h00000001);   // a5: exactly one fault in total

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

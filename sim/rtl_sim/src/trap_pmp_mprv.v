//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_mprv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP under mstatus.MPRV
//
//   Loads and stores from M-mode with MPRV=1 are checked at MPP's privilege;
//   instruction fetch is not. The register readbacks below say which accesses
//   landed, the trap slots say which were refused and why.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|                    PMP UNDER mstatus.MPRV                          |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 0/1
      //=================================================================
      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 0: NMIE=0, MPRV=1/U -- MPRV ignored, store lands ---");
      check_cpu_reg(10, 32'hAAAA0000);   // a0
      $display("--- Phase 1: MPRV=1/U -- store refused, load permitted ---");
      check_cpu_reg(11, 32'hAAAA0000);   // a1: the denied store left it untouched

      //=================================================================
      // PHASE 2/3/4
      //=================================================================
      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 3: MPRV=1/M -- unlocked entry ignored, store lands ---");
      check_cpu_reg(12, 32'hCCCC0000);   // a2
      $display("--- Trap record ---");
      check_cpu_reg(14, 32'h00000003);   // a4: exactly three faults
      check_cpu_reg(15, 32'h00000007);   // a5: P1 store  -> store access fault
      check_cpu_reg(16, 32'h80000400);   // a6:             at REGION
      check_cpu_reg(17, 32'h00000007);   // a7: P2 store  -> store access fault
      check_cpu_reg(18, 32'h80000500);   // s2:             at NOMATCH
      check_cpu_reg(19, 32'h00000005);   // s3: P2 load   -> load access fault
      check_cpu_reg(20, 32'h80000500);   // s4:             at NOMATCH
      $display("--- Phase 4: fetch with MPRV=1/U ran (no fourth fault) ---");

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

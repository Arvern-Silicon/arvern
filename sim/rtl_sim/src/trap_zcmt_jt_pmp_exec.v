//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_zcmt_jt_pmp_exec
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: the Zcmt jump-table read is an INSTRUCTION FETCH under PMP
//   (Unpriv 28.14.2). Three M-mode phases, MML=0:
//     (a) locked R-only table : cm.jt traps MCAUSE=1, MEPC=&cm.jt,
//         MTVAL=table entry address, and does NOT jump
//     (b) locked X-only table : cm.jt jumps (read permission is irrelevant)
//     (c) unlocked no-X table under MPRV=1/MPP=U : cm.jt jumps (the implicit
//         fetch is checked at the current privilege, M, not at MPP)
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Phase (a) takes an instruction access fault on purpose.
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|         ZCMT CM.JT: jump-table read is an instruction fetch (PMP)  |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE (a): locked R=1,X=0 table -> instruction access fault
      //=================================================================
      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Phase (a): table R-only (locked): cm.jt must fault, not jump ---");
      check_cpu_reg(10, 32'h00000001);   // a0: MCAUSE = instruction access fault (NOT 5)
      check_cpu_reg(11, 32'h00000000);   // a1: MEPC == &cm.jt
      check_cpu_reg(12, 32'h80000404);   // a2: MTVAL = the table entry fetch address (TBL_A + 4)
      check_cpu_reg(13, 32'h00000001);   // a3: exactly one trap
      check_cpu_reg(14, 32'h00A0FA11);   // a4: resumed on the fall-through, target never reached

      //=================================================================
      // PHASE (b): locked X=1,R=0 table -> jump succeeds
      //=================================================================
      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- Phase (b): table X-only (locked): cm.jt must jump ---");
      check_cpu_reg(15, 32'h000B0B0);    // a5: landed on the table target

      //=================================================================
      // PHASE (c): MPRV=1/MPP=U, unlocked no-X table -> jump succeeds
      //=================================================================
      wait(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("--- Phase (c): MPRV=1/MPP=U, table no-X unlocked: fetch checked as M, cm.jt must jump ---");
      check_cpu_reg(16, 32'h000C0C0);    // a6: landed on the table target
      check_cpu_reg(17, 32'h00000001);   // a7: trap count still 1 (no fault in (b) or (c))
      check_cpu_reg(18, 32'h00000000);   // s2: MPRV cleared again

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

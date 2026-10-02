//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_lock_rlb_mmwp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP lock semantics, mseccfg.RLB, and the two no-match policies
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
      $display("|            PMP LOCKS, mseccfg.RLB, MML / MMWP NO-MATCH             |");
      $display(" ====================================================================");
      $display("");

      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Part A: RLB and locks ---");
      check_cpu_reg(10, 32'h00000004);   // a0: RLB set while nothing locked
      check_cpu_reg(11, 32'h00000099);   // a1: entry 0 installed, locked
      check_cpu_reg(12, 32'h0000009B);   // a2: RLB let the locked cfg be edited
      check_cpu_reg(13, 32'h20000805);   // a3: ...and the locked addr
      check_cpu_reg(14, 32'h00000000);   // a4: RLB cleared
      check_cpu_reg(15, 32'h00000000);   // a5: cannot be set again with a lock present
      check_cpu_reg(16, 32'h0000009B);   // a6: locked cfg write ignored
      check_cpu_reg(17, 32'h20000805);   // a7: locked addr write ignored
      check_cpu_reg(18, 32'h20000804);   // s2: pmpaddr1 locked by entry 2's TOR
      check_cpu_reg(19, 32'h0089019B);   // s3: entry 1's own cfg still writable

      $display("--- Part B: MML only -- no-match data allowed, execute refused ---");
      check_mem_value(`SPAD(32'h100), 32'd0);
      check_mem_value(`SPAD(32'h104), 32'd0);
      check_mem_value(`SPAD(32'h108), 32'd1);

      $display("--- Part C: MMWP -- no-match refused, sticky, matches unaffected ---");
      check_cpu_reg(20, 32'h00000003);   // s4: MML | MMWP
      check_mem_value(`SPAD(32'h10C), 32'd5);
      check_mem_value(`SPAD(32'h110), 32'd7);
      check_mem_value(`SPAD(32'h114), 32'd1);
      check_mem_value(`SPAD(32'h118), 32'd0);
      check_cpu_reg(21, 32'h00000003);   // s5: MMWP clear attempt ignored

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

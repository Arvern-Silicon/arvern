//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_fetch_straddle
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP fetch checker -- instruction straddling a region boundary
//
//   A 32-bit instruction at 0x8000030E has its high half in a locked region
//   without X. MTVAL must name that half (0x80000310), not the instruction's
//   own address (0x8000030E), which MEPC carries instead.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|             PMP FETCH -- STRADDLING A REGION BOUNDARY              |");
      $display(" ====================================================================");
      $display("");

      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- high half unfetchable: MEPC and MTVAL must differ ---");
      check_cpu_reg(10, 32'h00000001);   // a0: MCAUSE = instruction access fault
      check_cpu_reg(11, 32'h8000030E);   // a1: MEPC  = the straddling instruction
      check_cpu_reg(12, 32'h80000310);   // a2: MTVAL = the half that faulted
      check_cpu_reg(13, 32'h00000001);   // a3: exactly one fault

      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

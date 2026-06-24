//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_csr_mcycle_priv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: M-MODE COUNTERS U-MODE PRIVILEGE TRAP
//   Verifies that U-mode reads of mcycle / minstret / mcycleh raise an
//   illegal-instruction trap each (MCAUSE=2). Pre-fix, those reads slipped
//   through silently; post-fix, exactly 3 traps are taken.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Three illegal-instruction traps + one ECALL trap are expected.
      error_on_exception = 0;


      //=================================================================
      // Wait for end-of-test sentinel
      //=================================================================
      $display("");
      $display(" Waiting for end-of-test sentinel");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(10) @(posedge free_clk);


      //=================================================================
      // Verify three U-mode CSRR illegal-instruction traps
      //=================================================================
      $display("");
      $display(" Scratchpad checks");

      // trap_count == 3 (one per M-only counter read attempt from U-mode).
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      // Latest MCAUSE == 2 (illegal instruction).
      check_mem_value(`SPAD(32'h04), 32'h00000002);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ldst_reserved
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: RESERVED LOAD/STORE FUNCT3 -> ILLEGAL
//   Checks trap_count == 3 and final MCAUSE == 2 (illegal instruction).
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

      // Three illegal-instruction traps are expected by design.
      error_on_exception = 0;


      //=================================================================
      // Wait for end-of-test sentinel
      //=================================================================
      $display("");
      $display(" Waiting for end-of-test sentinel");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(10) @(posedge free_clk);


      //=================================================================
      // Verify each reserved encoding raised an illegal-instruction trap
      //=================================================================
      $display("");
      $display(" Scratchpad checks");

      // Three illegal encodings, three traps.
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      // Latest MCAUSE = 2 (illegal instruction).
      check_mem_value(`SPAD(32'h04), 32'h00000002);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_smode_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: S-MODE WARL CSRs + SIE/SIP MIDELEG MASK
//   Checks that scounteren / senvcfg / menvcfg / menvcfgh / satp are now
//   accessible (no illegal-instruction trap), and that SIE read is masked by
//   mideleg per Privileged spec §3.1.9.
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


      //=================================================================
      // Wait for end-of-test sentinel
      //=================================================================
      $display("");
      $display(" Waiting for end-of-test sentinel");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(10) @(posedge free_clk);


      //=================================================================
      // Verify each WARL behavior
      //=================================================================

      // scounteren: 11 bits writable, the 0x7E5 mid-write should latch.
      check_mem_value(`SPAD(32'h00), 32'h000007E5);

      // senvcfg / menvcfg / menvcfgh / satp -- WARL hardwired zero
      check_mem_value(`SPAD(32'h04), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000000);
      check_mem_value(`SPAD(32'h0C), 32'h00000000);
      check_mem_value(`SPAD(32'h10), 32'h00000000);

      // SIE with mideleg=0 must read 0
      check_mem_value(`SPAD(32'h14), 32'h00000000);

      // SIE with mideleg=0x222 must read 0x222 (delegated bits visible)
      check_mem_value(`SPAD(32'h18), 32'h00000222);

      // trap_count == 0 -- none of the CSR accesses should have trapped
      check_mem_value(`SPAD(32'h1C), 32'h00000000);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_csr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT CSR
//   Verifies the CSR-stall HPM event counter (event selector 0x04).
//
//   Checks that mhpmcounter3 >= 5 after reading the time CSR (0xC01).
//
//   The testbench guarantees at least 5 CSR stall cycles by forcing
//   time_gnt=0 when the firmware signals x31=0x11111111 (just before the
//   csrr TIME instruction), holding it low for 5 clocks, then releasing.
//   This replaces the previous approach that relied on the harness's
//   randomised 0-5 cycle grant delay (which produced count=0 ~1/6 of runs).
//
//   Requires: ZICNTR_EN == 1 (time CSR must be present).
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] csr_count;
reg [31:0] time_lo;

`define SPAD(byte_off) (byte_off/4)

initial
   begin
      random_irq_enable = 0;

      @(posedge free_clk);
      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Force time_gnt=0 now so the harness cannot grant a same-cycle or
      // early request before we are ready to control the delay ourselves.
      force time_gnt = 1'b0;

      random_irq_enable = 1;

      $display("");
      $display(" ====================================================================");
      $display("|               ZIHPM EVENT CSR: CSR STALL COUNTER TEST              |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // Wait for firmware sync: x31=0x11111111 fires just before the
      // csrr TIME instruction.  Hold time_gnt=0 for 5 more clocks to
      // guarantee at least 5 CSR stall cycles, then release so the
      // harness can complete the grant.
      //=================================================================
      @(probes_cpu.x31 == 32'h11111111);
      repeat(5) @(posedge free_clk);
      release time_gnt;   // harness takes over and will grant within 0-5 more cycles

      //=================================================================
      // Wait for end of test
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;        // disable random IRQs before reading results
      repeat(3) @(posedge free_clk);

      //=================================================================
      // Read and verify CSR-stall counter
      //=================================================================
      csr_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      time_lo   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

      $display("  time CSR value = 0x%h (grant received)  %t ns", time_lo, $time);
      $display("  CSR stall count = %0d (after 1 time CSR read, >= 5 guaranteed)", csr_count);

      // >= 5: testbench held time_gnt=0 for 5 cycles after the sync,
      // guaranteeing at least 5 ex_csr_ready=0 cycles.
      if (csr_count >= 32'd5)
         $display("  PASS  CSR stall count=%0d >= 5 (CSR stall event functional)  %t ns",
                  csr_count, $time);
      else begin
         $display("  ERROR CSR stall count=%0d, expected >= 5 (time_gnt held low 5 cycles)  %t ns",
                  csr_count, $time);
         error = error + 1;
      end

      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_alu
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT ALU
//   Verifies the ALU-stall HPM event counter (event selector 0x03).
//
//   Checks that mhpmcounter3 > 0 after executing one DIVU instruction.
//   The multi-cycle divider stalls the pipeline for 11-32 cycles depending
//   on DIV_TYPE, so any value > 0 confirms the counter is working.
//
//   Requires: M_EXTENSION == 2 (full RV32M with divide support).
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] alu_count;

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

      random_irq_enable = 1;

      $display("");
      $display(" ====================================================================");
      $display("|               ZIHPM EVENT ALU: ALU STALL COUNTER TEST              |");
      $display(" ====================================================================");
      $display("");

      // Wait for end of test (level-sensitive in case back-to-back)
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;        // disable random IRQs before reading results
      repeat(3) @(posedge free_clk);

      //=================================================================
      // Read and verify ALU-stall counter
      //=================================================================
      alu_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("  ALU stall count = %0d (after 1 DIVU instruction)", alu_count);

      if (alu_count > 32'd0)
         $display("  PASS  ALU stall count=%0d > 0 (multi-cycle divide)  %t ns",
                  alu_count, $time);
      else begin
         $display("  ERROR ALU stall count=%0d = 0, expected > 0 from divider  %t ns",
                  alu_count, $time);
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

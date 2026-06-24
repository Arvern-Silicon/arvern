//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_inhibit_from_zero
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM INHIBIT FROM ZERO
//   Verifies that mcountinhibit gates counting from a zero baseline:
//   Phase 1: inhibit ON + 7 branches → counter3 must remain 0
//   Phase 2: inhibit OFF + 7 branches → counter3 must equal 7
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] p1_inhibited_count;
reg [31:0] p2_running_count;

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

      $display("");
      $display(" ====================================================================");
      $display("|          ZIHPM INHIBIT FROM ZERO: GATE ENABLE TEST                |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 1: inhibit ON — counter must stay at 0
      //=================================================================
      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      p1_inhibited_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("  Phase 1: inhibit active, 7 branch-taken events");
      $display("    counter3 = %0d  %t ns", p1_inhibited_count, $time);

      if (p1_inhibited_count === 32'd0)
         $display("  PASS  phase1: counter3 stayed at 0 with inhibit active  %t ns", $time);
      else begin
         $display("  ERROR phase1: counter3 = %0d, expected 0 (inhibit should gate counting)  %t ns",
                  p1_inhibited_count, $time);
         error = error + 1;
      end

      //=================================================================
      // PHASE 2: inhibit OFF — counter must count exactly 7
      //=================================================================
      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      p2_running_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

      $display("");
      $display("  Phase 2: inhibit cleared, 7 branch-taken events");
      $display("    counter3 = %0d  %t ns", p2_running_count, $time);

      if (p2_running_count === 32'd7)
         $display("  PASS  phase2: counter3 = 7 (counting correctly from zero)  %t ns", $time);
      else begin
         $display("  ERROR phase2: counter3 = %0d, expected 7  %t ns",
                  p2_running_count, $time);
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

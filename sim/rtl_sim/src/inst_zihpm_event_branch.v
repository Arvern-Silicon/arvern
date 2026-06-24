//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_branch
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT BRANCH
//   Verifies HPM event counters for branch-taken (0x05) and branch-not-taken
//   (0x06).  Both phases execute the same mixed sequence:
//   7 taken branches + 5 not-taken branches
//
//   Phase 1 (event 0x05): counter3 must equal exactly 7.
//   Exact match confirms: taken events counted, not-taken events NOT leaked.
//   Phase 2 (event 0x06): counter3 must equal exactly 5.
//   Exact match confirms: not-taken events counted, taken events NOT leaked.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] taken_count;
reg [31:0] nottaken_count;

`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Disable random IRQs immediately — this test requires no_random_irq
      random_irq_enable = 0;

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      $display("");
      $display(" ====================================================================");
      $display("|            ZIHPM EVENT BRANCH: HPM BRANCH EVENT TEST               |");
      $display(" ====================================================================");
      $display("");
      $display("  Sequence per phase: 7 taken branches + 5 not-taken branches");
      $display("  Phase 1 (event 0x05): expect counter3 = 7  (negative: not-taken must NOT count)");
      $display("  Phase 2 (event 0x06): expect counter3 = 5  (negative: taken must NOT count)");
      $display("");

      //=================================================================
      // PHASE 1: branch-taken event (0x05) — expect exactly 7
      //=================================================================
      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      taken_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("  Phase 1 (event 0x05): counter3 = %0d  %t ns", taken_count, $time);

      if (taken_count === 32'd7)
         $display("  PASS  phase1: counter3 = 7 (taken counted; not-taken did not leak)  %t ns",
                  $time);
      else begin
         $display("  ERROR phase1: counter3 = %0d, expected 7  %t ns", taken_count, $time);
         if (taken_count > 32'd7)
            $display("         (> 7 suggests not-taken events are leaking into event 0x05)");
         else
            $display("         (< 7 suggests taken events are being missed)");
         error = error + 1;
      end

      //=================================================================
      // PHASE 2: branch-not-taken event (0x06) — expect exactly 5
      //=================================================================
      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      nottaken_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

      $display("");
      $display("  Phase 2 (event 0x06): counter3 = %0d  %t ns", nottaken_count, $time);

      if (nottaken_count === 32'd5)
         $display("  PASS  phase2: counter3 = 5 (not-taken counted; taken did not leak)  %t ns",
                  $time);
      else begin
         $display("  ERROR phase2: counter3 = %0d, expected 5  %t ns", nottaken_count, $time);
         if (nottaken_count > 32'd5)
            $display("         (> 5 suggests taken events are leaking into event 0x06)");
         else
            $display("         (< 5 suggests not-taken events are being missed)");
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

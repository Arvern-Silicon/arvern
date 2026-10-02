//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcmp_push_load_raw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Bug reproducer - load into a register immediately followed by
//              a CM.PUSH containing that register: the FIRST store of the
//              push sequence is suspected to push the STALE (pre-load) value.
//
// Firmware self-checks every stacked word (error code in x30 = 0x0000CCNN,
// CC = case, NN = check; x11 = actual, x12 = expected) and stashes the
// critical stacked word of each case in a dedicated register:
//   x13 (a3) = case 1 stacked s1 (lw s1  ; cm.push {ra,s0-s1})   expect 0x600D0001
//   x14 (a4) = case 2 stacked s2 (lw s2  ; cm.push {ra,s0-s2})   expect 0x600D0002
//   x15 (a5) = case 3 stacked s1 (lw ; NOP ; cm.push - CONTROL)  expect 0x600D0003
//   x16 (a6) = case 4 stacked s1 (c.lw ; cm.push, same fetch wd) expect 0x600D0004
//
// Expected FAIL signature on buggy RTL: x31 = 0xBADC0DE0 with
// x30 = 0x00000102 (case 1, check 2), x11 = 0xBADBAD01, x12 = 0x600D0001.
// The control case (3) must pass even on buggy RTL.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial
   begin
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
      $display("");
      $display(" ====================================================================");
      $display("|      CM.PUSH LOAD-RAW HAZARD TEST (lw -> cm.push back-to-back)    |");
      $display(" ====================================================================");
      $display("");

      //---------------------------------------------------------------
      // Case 1: lw s1 ; cm.push {ra, s0-s1}, -16 (back-to-back)
      //---------------------------------------------------------------
      $display("Waiting for case 1 (lw s1 ; cm.push {ra,s0-s1}) ...");
      @(probes_cpu.x31==32'h11111111 || probes_cpu.x31==32'hBADC0DE0);
      if (probes_cpu.x31 == 32'hBADC0DE0) begin
          $display("");
          $display("======================================================================");
          $display("ERROR: Test FAILED - x31 = 0xBADC0DE0");
          $display("Error Code (x30):     0x%08h  (0x0000CCNN: CC=case, NN=check)", probes_cpu.x30);
          $display("Actual Value (x11):   0x%08h", probes_cpu.x11);
          $display("Expected Value (x12): 0x%08h", probes_cpu.x12);
          $display("Stack Pointer (x02):  0x%08h", probes_cpu.x02);
          $display("(BUG SIGNATURE: x30=0x00000102, x11=0xBADBAD01 => CM.PUSH first");
          $display(" store used the STALE pre-load value of s1)");
          $display("======================================================================");
          $display("");
          stimulus_done = 1;
          $finish;
      end
      check_cpu_reg(13, 32'h600D0001);   // a3 = stacked s1 (fresh, not 0xBADBAD01)
      $display("Case 1 passed.");

      //---------------------------------------------------------------
      // Case 2: lw s2 ; cm.push {ra, s0-s2}, -16 (back-to-back)
      //---------------------------------------------------------------
      $display("Waiting for case 2 (lw s2 ; cm.push {ra,s0-s2}) ...");
      @(probes_cpu.x31==32'h22222222 || probes_cpu.x31==32'hBADC0DE0);
      if (probes_cpu.x31 == 32'hBADC0DE0) begin
          $display("");
          $display("======================================================================");
          $display("ERROR: Test FAILED in case 2 - x31 = 0xBADC0DE0");
          $display("Error Code (x30):     0x%08h", probes_cpu.x30);
          $display("Actual Value (x11):   0x%08h", probes_cpu.x11);
          $display("Expected Value (x12): 0x%08h", probes_cpu.x12);
          $display("Stack Pointer (x02):  0x%08h", probes_cpu.x02);
          $display("======================================================================");
          $display("");
          stimulus_done = 1;
          $finish;
      end
      check_cpu_reg(14, 32'h600D0002);   // a4 = stacked s2 (fresh, not 0xBADBAD02)
      $display("Case 2 passed.");

      //---------------------------------------------------------------
      // Case 3 (CONTROL): lw s1 ; NOP ; cm.push {ra, s0-s1}, -16
      //---------------------------------------------------------------
      $display("Waiting for case 3 (CONTROL: lw s1 ; nop ; cm.push) ...");
      @(probes_cpu.x31==32'h33333333 || probes_cpu.x31==32'hBADC0DE0);
      if (probes_cpu.x31 == 32'hBADC0DE0) begin
          $display("");
          $display("======================================================================");
          $display("ERROR: Test FAILED in case 3 (CONTROL, 1-instruction gap)");
          $display("This case must pass even on RTL with the back-to-back RAW bug!");
          $display("Error Code (x30):     0x%08h", probes_cpu.x30);
          $display("Actual Value (x11):   0x%08h", probes_cpu.x11);
          $display("Expected Value (x12): 0x%08h", probes_cpu.x12);
          $display("Stack Pointer (x02):  0x%08h", probes_cpu.x02);
          $display("======================================================================");
          $display("");
          stimulus_done = 1;
          $finish;
      end
      check_cpu_reg(15, 32'h600D0003);   // a5 = stacked s1 (control case)
      $display("Case 3 (control) passed.");

      //---------------------------------------------------------------
      // Case 4: c.lw s1 ; cm.push {ra, s0-s1}, -16 (same fetch word)
      //---------------------------------------------------------------
      $display("Waiting for case 4 (c.lw s1 ; cm.push, compressed load) ...");
      @(probes_cpu.x31==32'h44444444 || probes_cpu.x31==32'hBADC0DE0);
      if (probes_cpu.x31 == 32'hBADC0DE0) begin
          $display("");
          $display("======================================================================");
          $display("ERROR: Test FAILED in case 4 (c.lw ; cm.push back-to-back)");
          $display("Error Code (x30):     0x%08h", probes_cpu.x30);
          $display("Actual Value (x11):   0x%08h", probes_cpu.x11);
          $display("Expected Value (x12): 0x%08h", probes_cpu.x12);
          $display("Stack Pointer (x02):  0x%08h", probes_cpu.x02);
          $display("======================================================================");
          $display("");
          stimulus_done = 1;
          $finish;
      end
      check_cpu_reg(16, 32'h600D0004);   // a6 = stacked s1 (compressed load case)
      $display("Case 4 passed.");

      //---------------------------------------------------------------
      // Final sync and end-of-test checks
      //---------------------------------------------------------------
      $display("");
      $display("Waiting for test completion...");
      @(probes_cpu.x31==32'hDEADBEEF || probes_cpu.x31==32'hBADC0DE0);

      // Disable random IRQ injection before final checks (defensive - this
      // test never enables it, it is fully deterministic)
      random_irq_enable = 0;

      if (probes_cpu.x31 == 32'hBADC0DE0) begin
          $display("");
          $display("======================================================================");
          $display("ERROR: Test FAILED - x31 = 0xBADC0DE0");
          $display("Error Code (x30):     0x%08h", probes_cpu.x30);
          $display("Actual Value (x11):   0x%08h", probes_cpu.x11);
          $display("Expected Value (x12): 0x%08h", probes_cpu.x12);
          $display("======================================================================");
          $display("");
          stimulus_done = 1;
          $finish;
      end

      $display("");
      $display("Firmware self-checks passed - verifying registers and memory...");
      $display("");

      // Stashed critical stacked words (one per case, never rewritten)
      check_cpu_reg(13, 32'h600D0001);   // case 1: stacked s1 (BUG CHECK)
      check_cpu_reg(14, 32'h600D0002);   // case 2: stacked s2 (BUG CHECK)
      check_cpu_reg(15, 32'h600D0003);   // case 3: stacked s1 (control)
      check_cpu_reg(16, 32'h600D0004);   // case 4: stacked s1 (BUG CHECK)

      // Final SP = case 4 stack: 0x80004000 - 16 = 0x80003FF0
      check_cpu_reg(2, 32'h80003FF0);

      // Fresh-data source words: 0x80000F00..0x80000F0C -> indices 960..963
      check_mem_value(960, 32'h600D0001);
      check_mem_value(961, 32'h600D0002);
      check_mem_value(962, 32'h600D0003);
      check_mem_value(963, 32'h600D0004);

      // Case 1 stack frame (new sp = 0x80000FF0):
      //   ra at 0x80000FF4 (idx 1021), s0 at 0x80000FF8 (idx 1022),
      //   s1 at 0x80000FFC (idx 1023) = old_sp-4 = FIRST store of the push
      check_mem_value(1021, 32'hC1000011);   // ra
      check_mem_value(1022, 32'hC1000022);   // s0
      check_mem_value(1023, 32'h600D0001);   // s1 - THE bug signature word

      // Case 2 stack frame (new sp = 0x80001FF0):
      //   ra at idx 2044, s0 at 2045, s1 at 2046, s2 at 2047 (FIRST store)
      check_mem_value(2044, 32'hC2000011);   // ra
      check_mem_value(2045, 32'hC2000022);   // s0
      check_mem_value(2046, 32'hC2000033);   // s1
      check_mem_value(2047, 32'h600D0002);   // s2 - THE bug signature word

      // Case 3 stack frame (new sp = 0x80002FF0) - control case
      check_mem_value(3069, 32'hC3000011);   // ra
      check_mem_value(3070, 32'hC3000022);   // s0
      check_mem_value(3071, 32'h600D0003);   // s1

      // Case 4 stack frame (new sp = 0x80003FF0) - compressed load case
      check_mem_value(4093, 32'hC4000011);   // ra
      check_mem_value(4094, 32'hC4000022);   // s0
      check_mem_value(4095, 32'h600D0004);   // s1 - THE bug signature word

      $display("");
      $display("Test PASSED - CM.PUSH stored the FRESH load value in all cases");
      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

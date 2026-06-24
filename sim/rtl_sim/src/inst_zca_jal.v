//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_jal
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.JAL
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
      $display("|                 CHECK REGISTER VALUES BEFORE C.JAL                 |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

      // Initial register values
      check_cpu_reg(1,  32'h00000000);   // ra - will be modified
      check_cpu_reg(2,  32'hDEADBEEF);   // sp
      check_cpu_reg(3,  32'hCAFEBABE);
      check_cpu_reg(4,  32'h12345678);
      check_cpu_reg(5,  32'hABCDEF01);
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h00000000);
      check_cpu_reg(9,  32'h00000000);
      check_cpu_reg(10, 32'h11111111);   // Test counter
      check_cpu_reg(11, 32'h22222222);   // Test counter
      check_cpu_reg(12, 32'h33333333);   // Test counter
      check_cpu_reg(13, 32'h44444444);   // Test counter
      check_cpu_reg(14, 32'h55555555);   // Test counter
      check_cpu_reg(15, 32'h00000000);
      check_cpu_reg(16, 32'h00000000);
      check_cpu_reg(17, 32'h00000000);
      check_cpu_reg(18, 32'h00000000);
      check_cpu_reg(19, 32'h00000000);
      check_cpu_reg(20, 32'h00000000);
      check_cpu_reg(21, 32'h00000000);
      check_cpu_reg(22, 32'h00000000);
      check_cpu_reg(23, 32'h00000000);
      check_cpu_reg(24, 32'h00000000);
      check_cpu_reg(25, 32'h00000000);
      check_cpu_reg(26, 32'h00000000);
      check_cpu_reg(27, 32'h00000000);
      check_cpu_reg(28, 32'h00000000);
      check_cpu_reg(29, 32'h00000000);
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hAAAAAAAA);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           CHECK INTERMEDIATE STATE AFTER BASIC JUMPS               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hBBBBBBBB);

      // Verify jump targets were reached and skipped code was not executed
      check_cpu_reg(2,  32'hDEADBEEF);   // sp unchanged
      check_cpu_reg(3,  32'hCAFEBABE);   // unchanged
      check_cpu_reg(4,  32'h12345678);   // unchanged
      check_cpu_reg(5,  32'hABCDEF01);   // unchanged

      // Verify counters were incremented (proves jumps occurred)
      check_cpu_reg(10, 32'h11111112);   // Test 1: +1 (skipped c.li x10, -1 instructions)
      check_cpu_reg(11, 32'h22222224);   // Test 2: +2 (skipped c.li x11, -1 instructions)
      check_cpu_reg(12, 32'h33333336);   // Test 3: +3 (skipped NOPs)
      check_cpu_reg(13, 32'h44444448);   // Test 4: +4 (backward jump worked)
      check_cpu_reg(14, 32'h5555555A);   // Test 5: +5 (subroutine call and return)

      // Verify saved return addresses from subroutines
      // x15 should have backed up x1 value before first subroutine call
      // x16 should have return address from subroutine_1
      // x17 should have previous x1 value (same as x15)

      // Note: We don't check exact PC values since they depend on code layout,
      // but we verify they are non-zero and different from initial state
      $display("INFO: x15 (backed up x1) = 0x%08h", probes_cpu.x15);
      $display("INFO: x16 (return addr from sub1) = 0x%08h", probes_cpu.x16);
      $display("INFO: x17 (previous x1 value) = 0x%08h", probes_cpu.x17);

      if (probes_cpu.x16 == 32'h00000000) begin
         $display("ERROR: x16 should contain return address from subroutine_1");
         error = error + 1;
      end

      // Verify nested subroutine counter
      check_cpu_reg(18, 32'h00000011);   // 1 + 4 + 2 + 10 = 17 (nested calls worked)

      // Verify return addresses were saved in nested calls
      $display("INFO: x19 (return addr from sub2) = 0x%08h", probes_cpu.x19);
      $display("INFO: x20 (return addr from sub3) = 0x%08h", probes_cpu.x20);

      if (probes_cpu.x19 == 32'h00000000) begin
         $display("ERROR: x19 should contain return address from subroutine_2");
         error = error + 1;
      end

      if (probes_cpu.x20 == 32'h00000000) begin
         $display("ERROR: x20 should contain return address from subroutine_3");
         error = error + 1;
      end

      // Verify other tests
      check_cpu_reg(21, 32'h00000007);   // Test 7: large offset jump

      // x22 should have return address from test_8
      $display("INFO: x22 (return addr from test8) = 0x%08h", probes_cpu.x22);
      if (probes_cpu.x22 == 32'h00000000) begin
         $display("ERROR: x22 should contain return address from test_8");
         error = error + 1;
      end

      // Remaining registers should be zero at this checkpoint
      check_cpu_reg(23, 32'h00000000);   // Not set yet
      check_cpu_reg(24, 32'h00000000);   // Not set yet
      check_cpu_reg(25, 32'h00000000);
      check_cpu_reg(26, 32'h00000000);
      check_cpu_reg(27, 32'h00000000);
      check_cpu_reg(28, 32'h00000000);
      check_cpu_reg(29, 32'h00000000);
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hBBBBBBBB);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|         CHECK FINAL STATE AFTER ALL C.JAL TESTS                   |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hDEADBEEF);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Final state verification
      check_cpu_reg(2,  32'hDEADBEEF);   // sp unchanged
      check_cpu_reg(3,  32'hCAFEBABE);   // unchanged
      check_cpu_reg(4,  32'h12345678);   // unchanged
      check_cpu_reg(5,  32'hABCDEF01);   // unchanged

      // All test counters should have their final values
      check_cpu_reg(10, 32'h11111112);   // Test 1: +1
      check_cpu_reg(11, 32'h22222224);   // Test 2: +2
      check_cpu_reg(12, 32'h33333336);   // Test 3: +3
      check_cpu_reg(13, 32'h44444448);   // Test 4: +4
      check_cpu_reg(14, 32'h5555555A);   // Test 5: +5
      check_cpu_reg(18, 32'h00000011);   // Test 6: nested calls = 17
      check_cpu_reg(21, 32'h00000007);   // Test 7: 7
      check_cpu_reg(23, 32'h00000009);   // Test 9: 9
      check_cpu_reg(24, 32'h0000000A);   // Test 10: 10
      check_cpu_reg(25, 32'h0000000B);   // Test 11: 11 (max positive offset +2046)
      check_cpu_reg(26, 32'h0000000C);   // Test 12: 12 (max negative offset -2048)
      check_cpu_reg(27, 32'h00000000);   // Skipped instruction after max negative jump

      // Saved return addresses should still be non-zero
      if (probes_cpu.x16 == 32'h00000000) begin
         $display("ERROR: x16 should still contain return address");
         error = error + 1;
      end
      if (probes_cpu.x17 == 32'h00000000) begin
         $display("ERROR: x17 should still contain backed up x1");
         error = error + 1;
      end
      if (probes_cpu.x19 == 32'h00000000) begin
         $display("ERROR: x19 should still contain return address");
         error = error + 1;
      end
      if (probes_cpu.x20 == 32'h00000000) begin
         $display("ERROR: x20 should still contain return address");
         error = error + 1;
      end
      if (probes_cpu.x22 == 32'h00000000) begin
         $display("ERROR: x22 should still contain return address");
         error = error + 1;
      end

      // x1 will have changed multiple times, verify it's non-zero
      $display("INFO: Final x1 (ra) = 0x%08h", probes_cpu.x01);
      if (probes_cpu.x01 == 32'h00000000) begin
         $display("ERROR: x1 should contain a return address");
         error = error + 1;
      end

      // Verify x15 and x17 match (both should have the backed up x1 value)
      if (probes_cpu.x15 != probes_cpu.x17) begin
         $display("ERROR: x15 and x17 should match (backed up x1 value)");
         error = error + 1;
      end

      // Unused registers should remain zero
      check_cpu_reg(6,  32'h00000000);
      check_cpu_reg(7,  32'h00000000);
      check_cpu_reg(8,  32'h00000000);
      check_cpu_reg(9,  32'h00000000);
      // x25, x26, x27 are now used by boundary offset tests (Tests 11-12)
      check_cpu_reg(28, 32'h00000000);
      check_cpu_reg(29, 32'h00000000);
      check_cpu_reg(30, 32'h00000000);
      check_cpu_reg(31, 32'hDEADBEEF);   // Test complete marker

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

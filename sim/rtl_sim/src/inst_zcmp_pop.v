//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcmp_pop
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CM.POP
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
      $display("|           CHECK INITIAL REGISTER VALUES (CM.POP TEST)             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for initial firmware setup...");

      @(probes_cpu.x31==32'h31313131);

	  check_cpu_reg(1,  32'h11111111);
 	  check_cpu_reg(2,  32'h22222222);
 	  check_cpu_reg(3,  32'h33333333);
 	  check_cpu_reg(4,  32'h44444444);
	  check_cpu_reg(5,  32'h55555555);
	  check_cpu_reg(6,  32'h66666666);
	  check_cpu_reg(7,  32'h77777777);
	  check_cpu_reg(8,  32'h88888888);
	  check_cpu_reg(9,  32'h99999999);
	  check_cpu_reg(10, 32'hAAAAAAAA);
	  check_cpu_reg(11, 32'hBBBBBBBB);
	  check_cpu_reg(12, 32'hCCCCCCCC);
	  check_cpu_reg(13, 32'hDDDDDDDD);
	  check_cpu_reg(14, 32'hEEEEEEEE);
	  check_cpu_reg(15, 32'h0F0F0F0F);
	  check_cpu_reg(16, 32'h10101010);
	  check_cpu_reg(17, 32'h17171717);
	  check_cpu_reg(18, 32'h18181818);
	  check_cpu_reg(19, 32'h19191919);
	  check_cpu_reg(20, 32'h20202020);
	  check_cpu_reg(21, 32'h21212121);
	  check_cpu_reg(22, 32'h22222222);
	  check_cpu_reg(23, 32'h23232323);
	  check_cpu_reg(24, 32'h24242424);
	  check_cpu_reg(25, 32'h25252525);
	  check_cpu_reg(26, 32'h26262626);
	  check_cpu_reg(27, 32'h27272727);
	  check_cpu_reg(28, 32'h28282828);
	  check_cpu_reg(29, 32'h29292929);
	  check_cpu_reg(30, 32'h30303030);
	  check_cpu_reg(31, 32'h31313131);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|            CHECK RESULTS AFTER CM.POP TESTS                       |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for test completion...");
      @(probes_cpu.x31==32'hDEADBEEF || probes_cpu.x31==32'hBADC0DE0);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      // Check if test passed or failed
      if (probes_cpu.x31 == 32'hBADC0DE0) begin
          $display("");
          $display("======================================================================");
          $display("ERROR: Test FAILED - x31 = 0xBADC0DE0");
          $display("----------------------------------------------------------------------");
          $display("Error Code (x30):     0x%08h", probes_cpu.x30);
          $display("  Test Number:        %0d", (probes_cpu.x30 >> 8) & 8'hFF);
          $display("  Check Number:       %0d", probes_cpu.x30 & 8'hFF);
          $display("----------------------------------------------------------------------");
          $display("Actual Value (x11):   0x%08h", probes_cpu.x11);
          $display("Expected Value (x12): 0x%08h", probes_cpu.x12);
          $display("Stack Pointer (x02):  0x%08h", probes_cpu.x02);
          $display("======================================================================");
          $display("");
          stimulus_done = 1;
          $finish;
      end

      // If we get here, x31 = 0xDEADBEEF (success)
      $display("");
      $display("Test PASSED - All CM.POP operations completed successfully");
      $display("");

      // Verify final SP value (after Test 16 stress loop, last pop restores SP)
      // Test 16: SP = 0x8000FE00
      check_cpu_reg(2, 32'h8000FE00);

      // Verify final register values from Test 16 last iteration (iter=19, 0x13)
      // Values: 0x16000000 | (19 << 4) | reg_id = 0x16000130 | reg_id
      check_cpu_reg(1,  32'h16000131);  // ra
      check_cpu_reg(8,  32'h16000132);  // s0
      check_cpu_reg(9,  32'h16000133);  // s1
      check_cpu_reg(18, 32'h16000134);  // s2
      check_cpu_reg(19, 32'h16000135);  // s3
      check_cpu_reg(20, 32'h16000136);  // s4
      check_cpu_reg(21, 32'h16000137);  // s5
      check_cpu_reg(22, 32'h16000138);  // s6
      check_cpu_reg(23, 32'h16000139);  // s7
      check_cpu_reg(24, 32'h1600013A);  // s8
      check_cpu_reg(25, 32'h1600013B);  // s9
      check_cpu_reg(26, 32'h1600013C);  // s10
      check_cpu_reg(27, 32'h1600013D);  // s11

      // Verify memory contents that were set up by the firmware for representative tests
      // Test 1: SP=0x80001000, ra stored at [SP+12]=0x8000100C, index=(0x100C)/4=1027
      check_mem_value(1027, 32'h01000001);
      // Test 2: SP=0x80002000, ra at [SP+24]=0x80002018, index=0x2018/4=2054
      check_mem_value(2054, 32'h02000001);
      // s0 at [SP+28]=0x8000201C, index=0x201C/4=2055
      check_mem_value(2055, 32'h02000002);
      // Test 12: SP=0x8000C000, ra at [SP+12]=0x8000C00C, index=0xC00C/4=12291
      check_mem_value(12291, 32'h0C000001);
      // s11 at [SP+60]=0x8000C03C, index=0xC03C/4=12303
      check_mem_value(12303, 32'h0C00000D);

      $display("");
      $display("All register and memory checks passed!");
      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

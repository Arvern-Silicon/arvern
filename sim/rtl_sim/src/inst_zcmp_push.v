//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcmp_push
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CM.PUSH
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
      $display("|           CHECK INITIAL REGISTER VALUES (CM.PUSH TEST)            |");
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
      $display("|            CHECK RESULTS AFTER CM.PUSH TESTS                      |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for IRQ stress loop to start...");
      @(probes_cpu.x31==32'hF0F0F0F0 || probes_cpu.x31==32'hBADC0DE0);
      if (probes_cpu.x31 == 32'hBADC0DE0) begin
          $display("ERROR: Test FAILED before reaching IRQ stress loop");
      end else begin
          $display("Starting IRQ stress loop (20 iterations of CM.PUSH {ra, s0-s11})...");
          @(probes_cpu.x31==32'hF1F1F1F1 || probes_cpu.x31==32'hBADC0DE0);
          if (probes_cpu.x31 != 32'hBADC0DE0)
              $display("IRQ stress loop completed successfully");
      end

      $display("");
      $display("Waiting for test completion...");
      if (probes_cpu.x31 != 32'hBADC0DE0)
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

      // If we get here, x31 = 0xdeadbeef (success)
      $display("");
      $display("Test PASSED - All CM.PUSH operations completed successfully");
      $display("");

      // Verify final SP value (after Test 16 stress loop)
      // Test 16: SP = 0x8000FE00 - 64 = 0x8000FDC0
      check_cpu_reg(2, 32'h8000FDC0);

      // Verify some memory contents from Test 1
      // Test 1: SP=0x80000FF0, ra at [SP+12]=0x80000FFC
      // SRAM index = (0x80000FFC - 0x80000000) / 4 = 1023
      check_mem_value(1023, 32'hDEADBEEF);  // ra at [SP+12]

      // Verify memory contents from Test 2
      // Test 2: SP=0x80001FE0, ra at [SP+24]=0x80001FF8, s0 at [SP+28]=0x80001FFC
      // SRAM indices = 2046, 2047
      check_mem_value(2046, 32'hABCD1234);  // ra at [SP+24]
      check_mem_value(2047, 32'h5678CDEF);  // s0 at [SP+28]

      // Verify memory contents from Test 3
      // Test 3: SP=0x80002FD0, registers at [SP+28] through [SP+44]
      // SRAM indices = 3067-3071
      check_mem_value(3067, 32'h00000001);  // ra at [SP+28]
      check_mem_value(3068, 32'h00000002);  // s0 at [SP+32]
      check_mem_value(3069, 32'h00000003);  // s1 at [SP+36]
      check_mem_value(3070, 32'h00000004);  // s2 at [SP+40]
      check_mem_value(3071, 32'h00000005);  // s3 at [SP+44]

      // Verify memory contents from Test 4 (maximum push)
      // Test 4: SP=0x80003FC0, 13 registers at [SP+12] through [SP+60]
      check_mem_value(4083, 32'hF0000001);  // ra at [SP+12]
      check_mem_value(4084, 32'hF0000002);  // s0 at [SP+16]
      check_mem_value(4085, 32'hF0000003);  // s1 at [SP+20]
      check_mem_value(4086, 32'hF0000004);  // s2 at [SP+24]
      check_mem_value(4087, 32'hF0000005);  // s3 at [SP+28]
      check_mem_value(4088, 32'hF0000006);  // s4 at [SP+32]
      check_mem_value(4089, 32'hF0000007);  // s5 at [SP+36]
      check_mem_value(4090, 32'hF0000008);  // s6 at [SP+40]
      check_mem_value(4091, 32'hF0000009);  // s7 at [SP+44]
      check_mem_value(4092, 32'hF000000A);  // s8 at [SP+48]
      check_mem_value(4093, 32'hF000000B);  // s9 at [SP+52]
      check_mem_value(4094, 32'hF000000C);  // s10 at [SP+56]
      check_mem_value(4095, 32'hF000000D);  // s11 at [SP+60]

      // Verify memory contents from Test 5 (different stack adjustments)
      // Test 5a: SP=0x80004FF0, {ra,s0-s1} -16, regs at [SP+4],[SP+8],[SP+12]
      check_mem_value(5117, 32'hAAA00001);  // ra at [SP+4]
      check_mem_value(5118, 32'hAAA00002);  // s0 at [SP+8]
      check_mem_value(5119, 32'hAAA00003);  // s1 at [SP+12]
      // Test 5b: SP=0x800050E0, {ra,s0-s1} -32, regs at [SP+20],[SP+24],[SP+28]
      check_mem_value(5181, 32'hBBB00001);  // ra at [SP+20]
      check_mem_value(5182, 32'hBBB00002);  // s0 at [SP+24]
      check_mem_value(5183, 32'hBBB00003);  // s1 at [SP+28]
      // Test 5c: SP=0x800051D0, {ra,s0-s1} -48, regs at [SP+36],[SP+40],[SP+44]
      check_mem_value(5245, 32'hCCC00001);  // ra at [SP+36]
      check_mem_value(5246, 32'hCCC00002);  // s0 at [SP+40]
      check_mem_value(5247, 32'hCCC00003);  // s1 at [SP+44]

      // Verify memory contents from Test 6 (consecutive pushes)
      // Second push at SP=0x80005FC0: ra at [SP+24], s0 at [SP+28]
      // Indices: 6134, 6135
      check_mem_value(6134, 32'hFEDCBA98);  // 2nd push ra at [SP+24]
      check_mem_value(6135, 32'h76543210);  // 2nd push s0 at [SP+28]
      // First push at 0x80005FE0: ra at [0x80005FF8], s0 at [0x80005FFC]
      // Indices: 6142, 6143
      check_mem_value(6142, 32'h12345678);  // 1st push ra at [SP+56]
      check_mem_value(6143, 32'h9ABCDEF0);  // 1st push s0 at [SP+60]

      // Verify memory contents from Test 7 ({ra,s0-s2}, -48)
      // SP=0x80006FD0, ra at [SP+32]=0x80006FF0, s2 at [SP+44]=0x80006FFC
      check_mem_value(7164, 32'h07000001);  // ra at [SP+32]
      check_mem_value(7165, 32'h07000002);  // s0 at [SP+36]
      check_mem_value(7166, 32'h07000003);  // s1 at [SP+40]
      check_mem_value(7167, 32'h07000004);  // s2 at [SP+44]

      // Verify memory contents from Test 8 ({ra,s0-s4}, -48)
      // SP=0x80007FD0, ra at [SP+24]=0x80007FE8
      check_mem_value(8186, 32'h08000001);  // ra at [SP+24]
      check_mem_value(8187, 32'h08000002);  // s0 at [SP+28]
      check_mem_value(8188, 32'h08000003);  // s1 at [SP+32]
      check_mem_value(8189, 32'h08000004);  // s2 at [SP+36]
      check_mem_value(8190, 32'h08000005);  // s3 at [SP+40]
      check_mem_value(8191, 32'h08000006);  // s4 at [SP+44]

      // Verify memory contents from Test 9 ({ra,s0-s5}, -80)
      // SP=0x80008FB0, ra at [SP+52]=0x80008FE4
      check_mem_value(9209, 32'h09000001);  // ra at [SP+52]
      check_mem_value(9210, 32'h09000002);  // s0 at [SP+56]
      check_mem_value(9211, 32'h09000003);  // s1 at [SP+60]
      check_mem_value(9212, 32'h09000004);  // s2 at [SP+64]
      check_mem_value(9213, 32'h09000005);  // s3 at [SP+68]
      check_mem_value(9214, 32'h09000006);  // s4 at [SP+72]
      check_mem_value(9215, 32'h09000007);  // s5 at [SP+76]

      // Verify memory contents from Test 10 ({ra,s0-s6}, -32)
      // SP=0x80009FE0, ra at [SP+0]=0x80009FE0
      check_mem_value(10232, 32'h0A000001);  // ra at [SP+0]
      check_mem_value(10233, 32'h0A000002);  // s0 at [SP+4]
      check_mem_value(10234, 32'h0A000003);  // s1 at [SP+8]
      check_mem_value(10235, 32'h0A000004);  // s2 at [SP+12]
      check_mem_value(10236, 32'h0A000005);  // s3 at [SP+16]
      check_mem_value(10237, 32'h0A000006);  // s4 at [SP+20]
      check_mem_value(10238, 32'h0A000007);  // s5 at [SP+24]
      check_mem_value(10239, 32'h0A000008);  // s6 at [SP+28]

      // Verify memory contents from Test 11 ({ra,s0-s7}, -80)
      // SP=0x8000AFB0, ra at [SP+44]=0x8000AFDC
      check_mem_value(11255, 32'h0B000001);  // ra at [SP+44]
      check_mem_value(11256, 32'h0B000002);  // s0 at [SP+48]
      check_mem_value(11257, 32'h0B000003);  // s1 at [SP+52]
      check_mem_value(11258, 32'h0B000004);  // s2 at [SP+56]
      check_mem_value(11259, 32'h0B000005);  // s3 at [SP+60]
      check_mem_value(11260, 32'h0B000006);  // s4 at [SP+64]
      check_mem_value(11261, 32'h0B000007);  // s5 at [SP+68]
      check_mem_value(11262, 32'h0B000008);  // s6 at [SP+72]
      check_mem_value(11263, 32'h0B000009);  // s7 at [SP+76]

      // Verify memory contents from Test 12 ({ra,s0-s8}, -64)
      // SP=0x8000BFC0, ra at [SP+24]=0x8000BFD8
      check_mem_value(12278, 32'h0C000001);  // ra at [SP+24]
      check_mem_value(12279, 32'h0C000002);  // s0 at [SP+28]
      check_mem_value(12280, 32'h0C000003);  // s1 at [SP+32]
      check_mem_value(12281, 32'h0C000004);  // s2 at [SP+36]
      check_mem_value(12282, 32'h0C000005);  // s3 at [SP+40]
      check_mem_value(12283, 32'h0C000006);  // s4 at [SP+44]
      check_mem_value(12284, 32'h0C000007);  // s5 at [SP+48]
      check_mem_value(12285, 32'h0C000008);  // s6 at [SP+52]
      check_mem_value(12286, 32'h0C000009);  // s7 at [SP+56]
      check_mem_value(12287, 32'h0C00000A);  // s8 at [SP+60]

      // Verify memory contents from Test 13 ({ra,s0-s9}, -96)
      // SP=0x8000CFA0, ra at [SP+52]=0x8000CFD4
      check_mem_value(13301, 32'h0D000001);  // ra at [SP+52]
      check_mem_value(13302, 32'h0D000002);  // s0 at [SP+56]
      check_mem_value(13303, 32'h0D000003);  // s1 at [SP+60]
      check_mem_value(13304, 32'h0D000004);  // s2 at [SP+64]
      check_mem_value(13305, 32'h0D000005);  // s3 at [SP+68]
      check_mem_value(13306, 32'h0D000006);  // s4 at [SP+72]
      check_mem_value(13307, 32'h0D000007);  // s5 at [SP+76]
      check_mem_value(13308, 32'h0D000008);  // s6 at [SP+80]
      check_mem_value(13309, 32'h0D000009);  // s7 at [SP+84]
      check_mem_value(13310, 32'h0D00000A);  // s8 at [SP+88]
      check_mem_value(13311, 32'h0D00000B);  // s9 at [SP+92]

      // Verify memory contents from Test 14 ({ra,s0-s11}, -96)
      // SP=0x8000DFA0, ra at [SP+44]=0x8000DFCC
      check_mem_value(14323, 32'h0E000001);  // ra at [SP+44]
      check_mem_value(14324, 32'h0E000002);  // s0 at [SP+48]
      check_mem_value(14325, 32'h0E000003);  // s1 at [SP+52]
      check_mem_value(14326, 32'h0E000004);  // s2 at [SP+56]
      check_mem_value(14327, 32'h0E000005);  // s3 at [SP+60]
      check_mem_value(14328, 32'h0E000006);  // s4 at [SP+64]
      check_mem_value(14329, 32'h0E000007);  // s5 at [SP+68]
      check_mem_value(14330, 32'h0E000008);  // s6 at [SP+72]
      check_mem_value(14331, 32'h0E000009);  // s7 at [SP+76]
      check_mem_value(14332, 32'h0E00000A);  // s8 at [SP+80]
      check_mem_value(14333, 32'h0E00000B);  // s9 at [SP+84]
      check_mem_value(14334, 32'h0E00000C);  // s10 at [SP+88]
      check_mem_value(14335, 32'h0E00000D);  // s11 at [SP+92]

      // Verify memory contents from Test 15 (hazard tests)
      // 15a: SP=0x8000EFF0, ra at 0x8000EFFC
      check_mem_value(15359, 32'hFA000001);  // 15a: ra at [SP+12]
      // 15b: SP=0x8000F0F0, ra at 0x8000F0FC
      check_mem_value(15423, 32'hFB000001);  // 15b: ra at [SP+12]
      // 15c: SP=0x8000F1F0, ra at 0x8000F1FC
      check_mem_value(15487, 32'hFC000001);  // 15c: ra at [SP+12]
      // 15d: SP=0x8000F2E0, ra at 0x8000F2F8, s0 at 0x8000F2FC
      check_mem_value(15550, 32'hFD000001);  // 15d: ra at [SP+24]
      check_mem_value(15551, 32'hFD000002);  // 15d: s0 at [SP+28]
      // 15e: SP=0x8000F3D0, back-to-back pushes
      check_mem_value(15610, 32'hFE000001);  // 15e: 2nd push ra at [SP+24]
      check_mem_value(15611, 32'hFE000002);  // 15e: 2nd push s0 at [SP+28]
      check_mem_value(15615, 32'hFE000001);  // 15e: 1st push ra at [SP+44]
      // 15f: SP=0x8000F4F0, ra at 0x8000F4FC
      check_mem_value(15679, 32'hFF000001);  // 15f: ra at [SP+12]
      // 15g: SP=0x8000F5E0, ra at 0x8000F5F8, s0 at 0x8000F5FC
      check_mem_value(15742, 32'hF1000001);  // 15g: ra at [SP+24]
      check_mem_value(15743, 32'hF1000002);  // 15g: s0 at [SP+28]

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


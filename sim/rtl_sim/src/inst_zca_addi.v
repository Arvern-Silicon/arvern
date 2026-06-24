//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_addi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.ADDI
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
      $display("|                 CHECK REGISTER VALUES BEFORE THE C.ADDI            |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x18==32'h80000000);

	   check_cpu_reg(1,  32'h12345DDD);
 	   check_cpu_reg(2,  32'hdeadbFFF);
 	   check_cpu_reg(3,  32'h10000112);
 	   check_cpu_reg(4,  32'habcd1556);
	   check_cpu_reg(5,  32'h0bad099A);
	   check_cpu_reg(6,  32'h0000fDDE);
	   check_cpu_reg(7,  32'hffff0012);
	   check_cpu_reg(8,  32'h1111189A);
	   check_cpu_reg(9,  32'h33344FED);
	   check_cpu_reg(10, 32'h55555765);
	   check_cpu_reg(11, 32'h00000000);
	   check_cpu_reg(12, 32'h00000000);
	   check_cpu_reg(13, 32'h00000000);
	   check_cpu_reg(14, 32'h00000000);
	   check_cpu_reg(15, 32'h00000000);
	   check_cpu_reg(16, 32'hAAAA5555);
	   check_cpu_reg(17, 32'h7FFFFFFF);
	   check_cpu_reg(18, 32'h80000000);
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
	   check_cpu_reg(31, 32'h00000000);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER THE C.ADDI             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

	  // Basic positive/negative immediate tests
	  check_cpu_reg(1,  32'h12345DDE);   // 32'h12345DDD +  1
 	  check_cpu_reg(2,  32'hdeadbFFE);   // 32'hdeadbFFF -  1
 	  check_cpu_reg(3,  32'h10000117);   // 32'h10000112 +  5
 	  check_cpu_reg(4,  32'habcd154C);   // 32'habcd1556 - 10
	  check_cpu_reg(5,  32'h0bad09A9);   // 32'h0bad099A + 15
	  check_cpu_reg(6,  32'h0000fDCA);   // 32'h0000fDDE - 20
	  check_cpu_reg(7,  32'hffff002B);   // 32'hffff0012 + 25
	  check_cpu_reg(8,  32'h1111187C);   // 32'h1111189A - 30
	  check_cpu_reg(9,  32'h33344FF9);   // 32'h33344FED + 12
	  check_cpu_reg(10, 32'h55555760);   // 32'h55555765 -  5
	  check_cpu_reg(11, 32'h00000007);   // 32'h00000000 +  7
	  check_cpu_reg(12, 32'hfffffff8);   // 32'h00000000 -  8
	  check_cpu_reg(13, 32'h00000002);   // 32'h00000000 +  2
	  check_cpu_reg(14, 32'hfffffffd);   // 32'h00000000 -  3
	  check_cpu_reg(15, 32'h00000001);   // 32'h00000000 +  1

	  // Boundary value tests: +31 (max), -32 (min)
	  check_cpu_reg(16, 32'hAAAA5554);   // 32'hAAAA5555 + 31 - 32 = -1

	  // Overflow/underflow tests (32-bit wraparound)
	  check_cpu_reg(17, 32'h80000000);   // 32'h7FFFFFFF + 1 (overflow to negative)
	  check_cpu_reg(18, 32'h7FFFFFFF);   // 32'h80000000 - 1 (underflow to positive)

	  // Remaining registers unchanged
	  check_cpu_reg(0,  32'h00000000);   // x0 must always be zero (HINT test)
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
	  check_cpu_reg(31, 32'hdeadbeef);

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_slt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SLT
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
      $display("|                 CHECK REGISTER VALUES BEFORE THE SLT               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hFFFFFFFF);

	   check_cpu_reg(1,  32'hffffffff);
 	   check_cpu_reg(2,  32'hffffffff);
 	   check_cpu_reg(3,  32'hffffffff);
 	   check_cpu_reg(4,  32'hffffffff);
	   check_cpu_reg(5,  32'hffffffff);
	   check_cpu_reg(6,  32'hffffffff);
	   check_cpu_reg(7,  32'hffffffff);
	   check_cpu_reg(8,  32'hffffffff);
	   check_cpu_reg(9,  32'hffffffff);
	   check_cpu_reg(10, 32'hffffffff);
	   check_cpu_reg(11, 32'hffffffff);
	   check_cpu_reg(12, 32'hffffffff);
	   check_cpu_reg(13, 32'hffffffff);
	   check_cpu_reg(14, 32'hffffffff);
	   check_cpu_reg(15, 32'hffffffff);
	   check_cpu_reg(16, 32'hffffffff);
	   check_cpu_reg(17, 32'hffffffff);
	   check_cpu_reg(18, 32'hffffffff);
	   check_cpu_reg(19, 32'hffffffff);
	   check_cpu_reg(20, 32'hffffffff);
	   check_cpu_reg(21, 32'hffffffff);
	   check_cpu_reg(22, 32'hffffffff);
	   check_cpu_reg(23, 32'hffffffff);
	   check_cpu_reg(24, 32'hffffffff);
	   check_cpu_reg(25, 32'hffffffff);
	   check_cpu_reg(26, 32'hffffffff);
	   check_cpu_reg(27, 32'hffffffff);
	   check_cpu_reg(28, 32'hffffffff);
	   check_cpu_reg(29, 32'hffffffff);
	   check_cpu_reg(30, 32'hffffffff);
	   check_cpu_reg(31, 32'hffffffff);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER THE SLT                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

	  check_cpu_reg(1,  32'hFFFFFFFF);   // -1 (from test 11)
 	  check_cpu_reg(2,  32'h00000000);   // SLT result (max < -1 ? 0)
 	  check_cpu_reg(3,  32'hFFFFFFFF);   // -1 (from test 12)
 	  check_cpu_reg(4,  32'h7FFFFFFF);   // max positive
	  check_cpu_reg(5,  32'h00000001);   // SLT result (-1 < max ? 1)
	  check_cpu_reg(6,  32'h00000001);   // SLT result (1 < 2)
	  check_cpu_reg(7,  32'h0000000A);   // 10
	  check_cpu_reg(8,  32'h00000003);   // 3
	  check_cpu_reg(9,  32'h00000000);   // SLT result (10 < 3 ? 0)
	  check_cpu_reg(10, 32'hFFFFFFFF);   // -1
	  check_cpu_reg(11, 32'h00000001);   // 1
	  check_cpu_reg(12, 32'h00000001);   // SLT result (-1 < 1 ? 1)
	  check_cpu_reg(13, 32'h00000001);   // 1
	  check_cpu_reg(14, 32'hFFFFFFFF);   // -1
	  check_cpu_reg(15, 32'h00000000);   // SLT result (1 < -1 ? 0)
	  check_cpu_reg(16, 32'hFFFFFFFB);   // -5
	  check_cpu_reg(17, 32'hFFFFFFFF);   // -1
	  check_cpu_reg(18, 32'h00000001);   // SLT result (-5 < -1 ? 1)
	  check_cpu_reg(19, 32'hFFFFFFFF);   // -1
	  check_cpu_reg(20, 32'hFFFFFFFB);   // -5
	  check_cpu_reg(21, 32'h00000000);   // SLT result (-1 < -5 ? 0)
	  check_cpu_reg(22, 32'h80000000);   // -2^31
	  check_cpu_reg(23, 32'h00000000);   // 0
	  check_cpu_reg(24, 32'h00000001);   // SLT result (-2^31 < 0 ? 1)
	  check_cpu_reg(25, 32'h00000000);   // 0
	  check_cpu_reg(26, 32'h80000000);   // -2^31
	  check_cpu_reg(27, 32'h00000000);   // SLT result (0 < -2^31 ? 0)
	  check_cpu_reg(28, 32'h7FFFFFFF);   // max positive
	  check_cpu_reg(29, 32'h7FFFFFFF);   // max positive
	  check_cpu_reg(30, 32'h00000000);   // SLT result (max < max ? 0)
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

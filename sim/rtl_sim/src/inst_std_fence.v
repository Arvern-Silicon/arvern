//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_fence
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: FENCE
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
      $display("|                 CHECK REGISTER VALUES BEFORE THE FENCE             |");
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
      $display("|                 CHECK REGISTER VALUES AFTER THE FENCE              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

	  check_cpu_reg(0,  32'h00000000);
	  check_cpu_reg(1,  32'h12345874);
 	  check_cpu_reg(2,  32'hdeadbeef);
 	  check_cpu_reg(3,  32'h10000543);
 	  check_cpu_reg(4,  32'habcd149d);
	  check_cpu_reg(5,  32'h0bad0db2);
	  check_cpu_reg(6,  32'h0000fa3f);
	  check_cpu_reg(7,  32'hffff019c);
	  check_cpu_reg(8,  32'h11111e48);
	  check_cpu_reg(9,  32'h333447be);
	  check_cpu_reg(10, 32'h55555123);
	  check_cpu_reg(11, 32'h77788234);
	  check_cpu_reg(12, 32'h99999432);
	  check_cpu_reg(13, 32'hBBBCC654);
	  check_cpu_reg(14, 32'hDDDDD678);
	  check_cpu_reg(15, 32'hFFF009ca);
	  check_cpu_reg(16, 32'h11223aed);
	  check_cpu_reg(17, 32'h55667dea);
	  check_cpu_reg(18, 32'h99AABdbe);
	  check_cpu_reg(19, 32'hDDEEFefd);
	  check_cpu_reg(20, 32'h01234ead);
	  check_cpu_reg(21, 32'h89ABCbee);
	  check_cpu_reg(22, 32'hFEDCBfde);
	  check_cpu_reg(23, 32'h76543adb);
	  check_cpu_reg(24, 32'h00FFEeef);
	  check_cpu_reg(25, 32'hCCBBAcaf);
	  check_cpu_reg(26, 32'h88776efa);
	  check_cpu_reg(27, 32'h44332ce0);
	  check_cpu_reg(28, 32'h135799de);
	  check_cpu_reg(29, 32'h02468abc);
	  check_cpu_reg(30, 32'hcba86420);
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

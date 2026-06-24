//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_sw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SW
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
      $display("|                        CHECK REGISTER VALUES                       |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_sram.sram_0==32'h12345DDD);          // Wait for first SW instruction (to first SRAM word)

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

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
	   check_cpu_reg(11, 32'h7778800F);
	   check_cpu_reg(12, 32'h99999CCB);
	   check_cpu_reg(13, 32'hBBBCC887);
	   check_cpu_reg(14, 32'hDDDDD443);
	   check_cpu_reg(15, 32'hFFF00135);
	   check_cpu_reg(16, 32'h11223024);
	   check_cpu_reg(17, 32'h55667451);
	   check_cpu_reg(18, 32'h99AAB234);
	   check_cpu_reg(19, 32'hDDEEFead);
	   check_cpu_reg(20, 32'h01234000);
	   check_cpu_reg(21, 32'h89ABCbcd);
	   check_cpu_reg(22, 32'hFEDCBbad);
	   check_cpu_reg(23, 32'h76543000);
	   check_cpu_reg(24, 32'h00FFEfff);
	   check_cpu_reg(25, 32'hCCBBA111);
	   check_cpu_reg(26, 32'h88776334);
	   check_cpu_reg(27, 32'h44332555);
	   check_cpu_reg(28, 32'h13579778);

	   check_cpu_reg(29, 32'h80000010);
	   check_cpu_reg(30, 32'h10040010);
	   check_cpu_reg(31, 32'h10041010);

      $display("");
      $display("Waiting for the firmware...");
      @(periph1_reg_00_out==32'h44332555);          // Wait for last SW instruction (to first Periph #0 word)

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                         CHECK SRAM VALUES                          |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      check_mem_value(0, 32'h12345DDD);
      check_mem_value(1, 32'habcd1556);
      check_mem_value(2, 32'hffff0012);
      check_mem_value(3, 32'h55555765);
      check_mem_value(4, 32'hBBBCC887);
      check_mem_value(5, 32'h11223024);
      check_mem_value(6, 32'hDDEEFead);
      check_mem_value(7, 32'hFEDCBbad);
      check_mem_value(8, 32'hCCBBA111);

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                         CHECK PERIPH #0 VALUES                     |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      check_periph_reg_value(0, 0, 32'h88776334);
      check_periph_reg_value(0, 1, 32'h01234000);
      check_periph_reg_value(0, 2, 32'hDDDDD443);
      check_periph_reg_value(0, 3, 32'h1111189A);
      check_periph_reg_value(0, 4, 32'hdeadbFFF);
      check_periph_reg_value(0, 5, 32'h0bad099A);
      check_periph_reg_value(0, 6, 32'h7778800F);
      check_periph_reg_value(0, 7, 32'h55667451);

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                         CHECK PERIPH #1 VALUES                     |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      check_periph_reg_value(1, 0, 32'h44332555);
      check_periph_reg_value(1, 1, 32'h00FFEfff);
      check_periph_reg_value(1, 2, 32'h89ABCbcd);
      check_periph_reg_value(1, 3, 32'h99AAB234);
      check_periph_reg_value(1, 4, 32'hFFF00135);
      check_periph_reg_value(1, 5, 32'h99999CCB);
      check_periph_reg_value(1, 6, 32'h33344FED);
      check_periph_reg_value(1, 7, 32'h0000fDDE);

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

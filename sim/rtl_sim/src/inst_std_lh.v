//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_lh
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: LH
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

      // Initialize peripheral 0 read values
      periph0_reg_08_in = 32'h33344FED;
      periph0_reg_09_in = 32'h55555765;
      periph0_reg_10_in = 32'h7778800F;
      periph0_reg_11_in = 32'h99999CCB;
      periph0_reg_12_in = 32'hBBBCC887;
      periph0_reg_13_in = 32'hDDDDD443;
      periph0_reg_14_in = 32'hFFF00135;
      periph0_reg_15_in = 32'h11223024;

      // Initialize peripheral 1 read values
      periph1_reg_08_in = 32'h55667451;
      periph1_reg_09_in = 32'h99AAB234;
      periph1_reg_10_in = 32'hDDEEFead;
      periph1_reg_11_in = 32'h01234021;
      periph1_reg_12_in = 32'h89ABCbcd;
      periph1_reg_13_in = 32'hFEDCBbad;
      periph1_reg_14_in = 32'h76543012;
      periph1_reg_15_in = 32'h00FFEfff;


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES BEFORE THE LOADS             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_sram.sram_0==32'h12345DDD);          // Wait for first SW instruction (to first SRAM word)

	   check_cpu_reg(1,  32'h12345DDD);
 	   check_cpu_reg(2,  32'hdeadbFFF);
 	   check_cpu_reg(3,  32'h10000112);
 	   check_cpu_reg(4,  32'habcd1556);
	   check_cpu_reg(5,  32'h0bad099A);
	   check_cpu_reg(6,  32'h0000fDDE);
	   check_cpu_reg(7,  32'hffff0012);
	   check_cpu_reg(8,  32'h1111189A);
	   check_cpu_reg(9,  32'h00000000);
	   check_cpu_reg(10, 32'h00000000);
	   check_cpu_reg(11, 32'h00000000);
	   check_cpu_reg(12, 32'h00000000);
	   check_cpu_reg(13, 32'h00000000);
	   check_cpu_reg(14, 32'h00000000);
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

	   check_cpu_reg(29, 32'h80000010);
	   check_cpu_reg(30, 32'h10040030);
	   check_cpu_reg(31, 32'h10041030);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x30==32'h0000099A);          // Wait for last SW instruction (to first Periph #0 word)

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER THE LOADS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

	   check_cpu_reg(1,  32'h00004FED);
 	   check_cpu_reg(2,  32'h00005765);
 	   check_cpu_reg(3,  32'hFFFF800F);
 	   check_cpu_reg(4,  32'hFFFF9CCB);
	   check_cpu_reg(5,  32'hFFFFC887);
	   check_cpu_reg(6,  32'hFFFFD443);
	   check_cpu_reg(7,  32'h00000135);
	   check_cpu_reg(8,  32'h00003024);
	   check_cpu_reg(9,  32'h0000099A);
	   check_cpu_reg(10, 32'h0000189A);
	   check_cpu_reg(11, 32'h00000012);
	   check_cpu_reg(12, 32'hFFFFfDDE);
	   check_cpu_reg(13, 32'h0000099A);
	   check_cpu_reg(14, 32'h00001556);
	   check_cpu_reg(15, 32'h00000112);
	   check_cpu_reg(16, 32'hFFFFbFFF);
	   check_cpu_reg(17, 32'h00005DDD);
	   check_cpu_reg(18, 32'h00007451);
	   check_cpu_reg(19, 32'hFFFFB234);
	   check_cpu_reg(20, 32'hFFFFFead);
	   check_cpu_reg(21, 32'h00004021);
	   check_cpu_reg(22, 32'hFFFFCbcd);
	   check_cpu_reg(23, 32'hFFFFBbad);
	   check_cpu_reg(24, 32'h00003012);
	   check_cpu_reg(25, 32'hFFFFEfff);
	   check_cpu_reg(26, 32'h00000000);
	   check_cpu_reg(27, 32'h00000BAD);
	   check_cpu_reg(28, 32'h00000000);

	   check_cpu_reg(29, 32'h80000010);
	   check_cpu_reg(30, 32'h0000099A);
	   check_cpu_reg(31, 32'h10041030);


      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

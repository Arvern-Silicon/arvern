//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_csrrs
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CSRRS
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
      $display("|                 CHECK REGISTER VALUES BEFORE THE CSRRS             |");
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
      $display("|                 CHECK REGISTER VALUES AFTER THE CSRRS              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

      check_mem_value( 0, 32'h800A5001);
      check_mem_value( 1, 32'h00000000);
      check_mem_value( 2, 32'h800A5001);

      check_mem_value( 3, 32'h10052008);
      check_mem_value( 4, 32'h800A5001);
      check_mem_value( 5, 32'h900F7009);

	   check_mem_value( 6, 32'h02400930);
      check_mem_value( 7, 32'h900F7009);
      check_mem_value( 8, 32'h924F7939);

	   check_mem_value( 9, 32'h28138481);
      check_mem_value(10, 32'h924F7939);
      check_mem_value(11, 32'hBA5FFDB9);

	   check_mem_value(12, 32'h00834000);
      check_mem_value(13, 32'hBA5FFDB9);
      check_mem_value(14, 32'hBADFFDB9);

	   check_mem_value(15, 32'h45200246);
      check_mem_value(16, 32'hBADFFDB9);
      check_mem_value(17, 32'hFFFFFFFF);

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_csrrsi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CSRRSI
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
      $display("|                 CHECK REGISTER VALUES BEFORE THE CSRRSI            |");
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
	   check_cpu_reg(10, 32'h10042000);
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
      $display("|                 CHECK REGISTER VALUES AFTER THE CSRRSI             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

	   check_cpu_reg(1,  32'h00000000);
 	   check_cpu_reg(2,  32'h00000000);
 	   check_cpu_reg(3,  32'h00000000);
 	   check_cpu_reg(4,  32'h00000000);
	   check_cpu_reg(5,  32'h00000000);
	   check_cpu_reg(6,  32'h00000000);
	   check_cpu_reg(7,  32'h00000000);
	   check_cpu_reg(8,  32'h00000000);
	   check_cpu_reg(9,  32'h00000000);
	   check_cpu_reg(10, 32'h10042000);
	   check_cpu_reg(11, 32'h00000003);
	   check_cpu_reg(12, 32'h00000017);
	   check_cpu_reg(13, 32'h0000000C);
	   check_cpu_reg(14, 32'h00000006);
	   check_cpu_reg(15, 32'h00000012);
	   check_cpu_reg(16, 32'h00000018);
	   check_cpu_reg(17, 32'h00000001);
	   check_cpu_reg(18, 32'h00000014);
	   check_cpu_reg(19, 32'hffffffff);
	   check_cpu_reg(20, 32'hffffffff);
	   check_cpu_reg(21, 32'h0000000B);
	   check_cpu_reg(22, 32'h0000001F);
	   check_cpu_reg(23, 32'h0000001E);
	   check_cpu_reg(24, 32'h00000017);
	   check_cpu_reg(25, 32'h00000016);
	   check_cpu_reg(26, 32'h00000019);
	   check_cpu_reg(27, 32'h00000009);
	   check_cpu_reg(28, 32'h00000015);
	   check_cpu_reg(29, 32'hffffffff);
	   check_cpu_reg(30, 32'hffffffff);

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_lui
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: LUI
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

      $display(" ====================================================================");
      $display("|                  CHECK DEFAULT REGISTER VALUES                     |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");

      `ifndef RANDOM_IRQ
      for (ii = 0; ii < 32; ii = ii + 1) begin
         check_cpu_reg(ii, 32'h00000000);
      end
      `endif

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                  CHECK FIRST PASS REGISTER VALUES                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(periph0_reg_00_out==32'hABCDEF01);

      check_cpu_reg(0,  32'h00000000);
	  check_cpu_reg(1,  32'h12345000);
 	  check_cpu_reg(2,  32'hdeadb000);
 	  check_cpu_reg(3,  32'h10000000);
 	  check_cpu_reg(4,  32'habcd1000);
	  check_cpu_reg(5,  32'h0bad0000);
	  check_cpu_reg(6,  32'h0000f000);
	  check_cpu_reg(7,  32'hffff0000);
	  check_cpu_reg(8,  32'h11111000);
	  check_cpu_reg(9,  32'h33344000);
	  check_cpu_reg(10, 32'h55555000);
	  check_cpu_reg(11, 32'h77788000);
	  check_cpu_reg(12, 32'h99999000);
	  check_cpu_reg(13, 32'hBBBCC000);
	  check_cpu_reg(14, 32'hDDDDD000);
	  check_cpu_reg(15, 32'hFFF00000);
	  check_cpu_reg(16, 32'h11223000);
	  check_cpu_reg(17, 32'h55667000);
	  check_cpu_reg(18, 32'h99AAB000);
	  check_cpu_reg(19, 32'hDDEEF000);
	  check_cpu_reg(20, 32'h01234000);
	  check_cpu_reg(21, 32'h89ABC000);
	  check_cpu_reg(22, 32'hFEDCB000);
	  check_cpu_reg(23, 32'h76543000);
	  check_cpu_reg(24, 32'h00FFE000);
	  check_cpu_reg(25, 32'hCCBBA000);
	  check_cpu_reg(26, 32'h88776000);
	  check_cpu_reg(27, 32'h44332000);
	  check_cpu_reg(28, 32'h13579000);
	  check_cpu_reg(29, 32'h02468000);
	  check_cpu_reg(30, 32'hABCDEF01);
	  check_cpu_reg(31, 32'h10040000);

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                  CHECK SECOND PASS REGISTER VALUES                 |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(periph0_reg_01_out==32'h23456789);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      check_cpu_reg(0,  32'h00000000);
	  check_cpu_reg(1,  32'h23456789);
 	  check_cpu_reg(2,  32'h10040000);
 	  check_cpu_reg(3,  32'h00001000);
 	  check_cpu_reg(4,  32'h00002000);
	  check_cpu_reg(5,  32'h00004000);
	  check_cpu_reg(6,  32'h00008000);
	  check_cpu_reg(7,  32'h00010000);
	  check_cpu_reg(8,  32'h00020000);
	  check_cpu_reg(9,  32'h00040000);
	  check_cpu_reg(10, 32'h00080000);
	  check_cpu_reg(11, 32'h00100000);
	  check_cpu_reg(12, 32'h00200000);
	  check_cpu_reg(13, 32'h00400000);
	  check_cpu_reg(14, 32'h00800000);
	  check_cpu_reg(15, 32'h01000000);
	  check_cpu_reg(16, 32'h02000000);
	  check_cpu_reg(17, 32'h04000000);
	  check_cpu_reg(18, 32'h08000000);
	  check_cpu_reg(19, 32'h10000000);
	  check_cpu_reg(20, 32'h20000000);
	  check_cpu_reg(21, 32'h40000000);
	  check_cpu_reg(22, 32'h80000000);
	  check_cpu_reg(23, 32'h40000000);
	  check_cpu_reg(24, 32'h20000000);
	  check_cpu_reg(25, 32'h10000000);
	  check_cpu_reg(26, 32'h08000000);
	  check_cpu_reg(27, 32'h04000000);
	  check_cpu_reg(28, 32'h02000000);
	  check_cpu_reg(29, 32'h01000000);
	  check_cpu_reg(30, 32'h00800000);
	  check_cpu_reg(31, 32'h00400000);

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

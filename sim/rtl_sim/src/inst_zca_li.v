//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_li
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.LI
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
      $display("|                 CHECK REGISTER VALUES BEFORE THE C.LI              |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x10==32'hDEADBEEF);

	   check_cpu_reg(1,  32'hFFFFFFFF);
 	   check_cpu_reg(2,  32'hFFFFFFFF);
 	   check_cpu_reg(3,  32'hFFFFFFFF);
 	   check_cpu_reg(4,  32'hFFFFFFFF);
	   check_cpu_reg(5,  32'hFFFFFFFF);
	   check_cpu_reg(6,  32'hFFFFFFFF);
	   check_cpu_reg(7,  32'hFFFFFFFF);
	   check_cpu_reg(8,  32'hFFFFFFFF);
	   check_cpu_reg(9,  32'hFFFFFFFF);
	   check_cpu_reg(10, 32'hDEADBEEF);
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
	   check_cpu_reg(29, 32'h00000000);
	   check_cpu_reg(30, 32'h00000000);
	   check_cpu_reg(31, 32'h00000000);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER THE C.LI               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

	  // Positive immediate values
	  check_cpu_reg(1,  32'h00000001);   // c.li x1, 1
 	  check_cpu_reg(2,  32'h00000005);   // c.li x2, 5
 	  check_cpu_reg(3,  32'h0000000A);   // c.li x3, 10
 	  check_cpu_reg(4,  32'h0000000F);   // c.li x4, 15
	  check_cpu_reg(5,  32'h00000014);   // c.li x5, 20
	  check_cpu_reg(6,  32'h00000019);   // c.li x6, 25
	  check_cpu_reg(7,  32'h0000001E);   // c.li x7, 30
	  check_cpu_reg(8,  32'h0000001F);   // c.li x8, 31 (max positive)

	  // Negative immediate values (sign-extended)
	  check_cpu_reg(9,  32'hFFFFFFFF);   // c.li x9, -1
	  check_cpu_reg(11, 32'hFFFFFFFB);   // c.li x11, -5
	  check_cpu_reg(12, 32'hFFFFFFF6);   // c.li x12, -10
	  check_cpu_reg(13, 32'hFFFFFFF1);   // c.li x13, -15
	  check_cpu_reg(14, 32'hFFFFFFEC);   // c.li x14, -20
	  check_cpu_reg(15, 32'hFFFFFFE7);   // c.li x15, -25
	  check_cpu_reg(16, 32'hFFFFFFE2);   // c.li x16, -30
	  check_cpu_reg(17, 32'hFFFFFFE0);   // c.li x17, -32 (min)

	  // Zero immediate
	  check_cpu_reg(18, 32'h00000000);   // c.li x18, 0

	  // Additional tests
	  check_cpu_reg(19, 32'h00000007);   // c.li x19, 7
	  check_cpu_reg(20, 32'hFFFFFFF9);   // c.li x20, -7
	  check_cpu_reg(21, 32'h0000000C);   // c.li x21, 12
	  check_cpu_reg(22, 32'hFFFFFFF4);   // c.li x22, -12

	  // x0 must remain zero (HINT test)
	  check_cpu_reg(0,  32'h00000000);   // x0 always zero

	  // Remaining registers
	  check_cpu_reg(10, 32'hDEADBEEF);   // Unchanged marker
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


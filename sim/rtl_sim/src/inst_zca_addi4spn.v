//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_addi4spn
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.ADDI4SPN
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
      $display("|                 CHECK REGISTER VALUES BEFORE THE C.ADDI4SPN        |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hAAAAAAAA);

	   check_cpu_reg(1,  32'hDEADBEEF);
 	   check_cpu_reg(2,  32'h20000000);   // sp
 	   check_cpu_reg(3,  32'h00000000);
 	   check_cpu_reg(4,  32'h00000000);
	   check_cpu_reg(5,  32'h00000000);
	   check_cpu_reg(6,  32'h00000000);
	   check_cpu_reg(7,  32'h00000000);
	   check_cpu_reg(8,  32'h00000000);
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
	   check_cpu_reg(29, 32'h00000000);
	   check_cpu_reg(30, 32'h00000000);
	   check_cpu_reg(31, 32'hAAAAAAAA);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES AFTER THE C.ADDI4SPN         |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

	  // C.ADDI4SPN tests - all values are sp + immediate
	  // sp = 0x20000000
	  check_cpu_reg(1,  32'hDEADBEEF);   // Unchanged marker
	  check_cpu_reg(2,  32'h20000000);   // sp unchanged

	  // Compressed registers (x8-x15) - final values after all operations
	  check_cpu_reg(8,  32'h20000040);   // 0x20000000 + 64 (second set)
	  check_cpu_reg(9,  32'h20000080);   // 0x20000000 + 128 (second set)
	  check_cpu_reg(10, 32'h20000100);   // 0x20000000 + 256 (second set)
	  check_cpu_reg(11, 32'h20000200);   // 0x20000000 + 512 (second set)
	  check_cpu_reg(12, 32'h20000004);   // 0x20000000 + 4 (min, second set)
	  check_cpu_reg(13, 32'h200003FC);   // 0x20000000 + 1020 (max, second set)
	  check_cpu_reg(14, 32'h20000064);   // 0x20000000 + 100 (second set)
	  check_cpu_reg(15, 32'h20000020);   // 0x20000000 + 32 (first set, unchanged)

	  // Backup registers (x16-x23) - first set of c.addi4spn operations
	  check_cpu_reg(16, 32'h20000004);   // Backup of x8:  sp + 4
	  check_cpu_reg(17, 32'h20000008);   // Backup of x9:  sp + 8
	  check_cpu_reg(18, 32'h2000000C);   // Backup of x10: sp + 12
	  check_cpu_reg(19, 32'h20000010);   // Backup of x11: sp + 16
	  check_cpu_reg(20, 32'h20000014);   // Backup of x12: sp + 20
	  check_cpu_reg(21, 32'h20000018);   // Backup of x13: sp + 24
	  check_cpu_reg(22, 32'h2000001C);   // Backup of x14: sp + 28
	  check_cpu_reg(23, 32'h20000020);   // Backup of x15: sp + 32

	  // Remaining registers unchanged
	  check_cpu_reg(3,  32'h00000000);
	  check_cpu_reg(4,  32'h00000000);
	  check_cpu_reg(5,  32'h00000000);
	  check_cpu_reg(6,  32'h00000000);
	  check_cpu_reg(7,  32'h00000000);
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


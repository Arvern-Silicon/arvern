//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_all
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CSR MSCRATCH
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
      $display("|            CHECK REGISTER VALUES BEFORE CSR TESTS                  |");
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
      $display("|             CHECK REGISTER VALUES AFTER CSR TESTS                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

      $display("");
      $display("  --- CSRRW Tests ---");
      check_cpu_reg(11, 32'h00000000);  // Old value (MSCRATCH starts at 0)
      check_cpu_reg(12, 32'h12345678);  // Read back (0x12345678 written)
      check_cpu_reg(13, 32'h12345678);  // Old value from first write
      check_cpu_reg(14, 32'hAABBCCDD);  // Read back (0xAABBCCDD written)

      $display("");
      $display("  --- CSRRS Tests ---");
      check_cpu_reg(16, 32'hAABBCCDD);  // Old value from csrrw clear
      check_cpu_reg(17, 32'h00000000);  // Old value (cleared)
      check_cpu_reg(18, 32'h0F0F0F0F);  // Read back (bits set)
      check_cpu_reg(19, 32'h0F0F0F0F);  // Old value
      check_cpu_reg(20, 32'hFFFFFFFF);  // Read back (all bits set)

      $display("");
      $display("  --- CSRRC Tests ---");
      check_cpu_reg(22, 32'hFFFFFFFF);  // Old value
      check_cpu_reg(23, 32'hFFFF0000);  // Read back (lower 16 cleared)
      check_cpu_reg(24, 32'hFFFF0000);  // Old value
      check_cpu_reg(25, 32'h00000000);  // Read back (all cleared)

      $display("");
      $display("  --- CSRRWI Tests ---");
      check_cpu_reg(1, 32'h00000000);   // Old value
      check_cpu_reg(2, 32'h0000000F);   // Read back (15 written)
      check_cpu_reg(3, 32'h0000000F);   // Old value (15)
      check_cpu_reg(4, 32'h0000001F);   // Read back (31 written)

      $display("");
      $display("  --- CSRRSI Tests ---");
      check_cpu_reg(5, 32'h0000001F);   // Old value from csrrwi clear
      check_cpu_reg(6, 32'h00000000);   // Old value (cleared)
      check_cpu_reg(7, 32'h0000000F);   // Read back (bits 0-3 set)
      check_cpu_reg(8, 32'h0000000F);   // Old value
      check_cpu_reg(9, 32'h0000001F);   // Read back (bit 4 also set)

      $display("");
      $display("  --- CSRRCI Tests ---");
      check_cpu_reg(26, 32'h0000001F);  // Old value (0x1F)
      check_cpu_reg(27, 32'h00000010);  // Read back (lower 4 bits cleared)
      check_cpu_reg(28, 32'h00000010);  // Old value
      check_cpu_reg(29, 32'h00000000);  // Read back (bit 4 cleared)

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


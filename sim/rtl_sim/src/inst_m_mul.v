//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_m_mul
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MUL/MULH/MULHSU/MULHU
//----------------------------------------------------------------------------

`define VERY_LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;
reg      [8*32-1:0] expected_results [0:(24*24-1)]; // i, j, dividend, divisor, DIV, DIVU, REM, REMU

// Check division results for a given iteration
task check_mem_results;

   input integer i;
   input integer j;
   input integer exp_op1;
   input integer exp_op2;
   input integer exp_result_mul;
   input integer exp_result_mulh;
   input integer exp_result_mulhsu;
   input integer exp_result_mulhu;

   integer mem_op1;
   integer mem_op2;
   integer mem_result_mul;
   integer mem_result_mulh;
   integer mem_result_mulhsu;
   integer mem_result_mulhu;
   integer error_before;
   begin
	 	mem_op1           = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 0];
	 	mem_op2           = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 1];
	 	mem_result_mul    = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 2];
	 	mem_result_mulh   = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 3];
	 	mem_result_mulhsu = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 4];
	 	mem_result_mulhu  = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 5];
		error_before      = error;
		$display("========== i=%0d j=%0d ==========",i, j);
    	$display("Expected --> %h*%h -- MUL=%h MULH=%h MULHSU=%h MULHU=%h", exp_op1, exp_op2, exp_result_mul, exp_result_mulh, exp_result_mulhsu, exp_result_mulhu);
    	$display("Got      --> %h*%h -- MUL=%h MULH=%h MULHSU=%h MULHU=%h", mem_op1, mem_op2, mem_result_mul, mem_result_mulh, mem_result_mulhsu, mem_result_mulhu);
		if ((exp_op1!==mem_op1) || (exp_op2!==mem_op2)) begin
			$display("                                                                                            ERROR: Operands are not matching. Issue in testbench.");
			error = error+1;
		end
		if (exp_result_mul!==mem_result_mul) begin
			$display("                                                                                            ERROR: wrong MUL    result");
			error = error+1;
		end
		if (exp_result_mulh!==mem_result_mulh) begin
			$display("                                                                                            ERROR: wrong MULH   result");
			error = error+1;
		end
		if (exp_result_mulhsu!==mem_result_mulhsu) begin
			$display("                                                                                            ERROR: wrong MULHSU result");
			error = error+1;
		end
		if (exp_result_mulhu!==mem_result_mulhu) begin
			$display("                                                                                            ERROR: wrong MULHU  result");
			error = error+1;
		end
		if (error_before==error) begin
			$display("PASS");
		end

   end
endtask


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
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      $display("");
      $display(" ================================================================================");
      $display("|      CHECK MEMORY VALUES AFTER THE MUL/MULH/MULHSU/MULHU                       |");
      $display(" ================================================================================");

      //               | Index |   Op1(hex)  |   Op2(hex)  |  MUL (Low)  | MULH (High S*S) | MULHSU (High S*U) | MULHU (High U*U) |   Operation (Signed/Unsigned)
      //---------------+-------+-------------+-------------+-------------+-----------------+-------------------+------------------+-------------------------------------
      check_mem_results(  0,  0, 32'h00000000, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 0
      check_mem_results(  0,  1, 32'h00000000, 32'h00000001, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 1
      check_mem_results(  0,  2, 32'h00000000, 32'hffffffff, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -1
      check_mem_results(  0,  3, 32'h00000000, 32'h00000002, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 2
      check_mem_results(  0,  4, 32'h00000000, 32'hfffffffe, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -2
      check_mem_results(  0,  5, 32'h00000000, 32'h7fffffff, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 2147483647
      check_mem_results(  0,  6, 32'h00000000, 32'h80000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -2147483648
      check_mem_results(  0,  7, 32'h00000000, 32'h80000001, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -2147483647
      check_mem_results(  0,  8, 32'h00000000, 32'h12345678, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 305419896
      check_mem_results(  0,  9, 32'h00000000, 32'h87654321, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -2023406815
      check_mem_results(  0, 10, 32'h00000000, 32'h0000ffff, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 65535
      check_mem_results(  0, 11, 32'h00000000, 32'hffff0000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -65536
      check_mem_results(  0, 12, 32'h00000000, 32'h40000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 1073741824
      check_mem_results(  0, 13, 32'h00000000, 32'hc0000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -1073741824
      check_mem_results(  0, 14, 32'h00000000, 32'h7f7f7f7f, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 2139062143
      check_mem_results(  0, 15, 32'h00000000, 32'h80808080, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -2139062144
      check_mem_results(  0, 16, 32'h00000000, 32'h13579bdf, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 324508639
      check_mem_results(  0, 17, 32'h00000000, 32'h2468ace0, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 610839776
      check_mem_results(  0, 18, 32'h00000000, 32'h00007fff, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 32767
      check_mem_results(  0, 19, 32'h00000000, 32'hffff8000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -32768
      check_mem_results(  0, 20, 32'h00000000, 32'h01010101, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * 16843009
      check_mem_results(  0, 21, 32'h00000000, 32'hf0f0f0f0, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -252645136
      check_mem_results(  0, 22, 32'h00000000, 32'hdeadbeef, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -559038737
      check_mem_results(  0, 23, 32'h00000000, 32'hcafebabe, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 0 * -889275714

      check_mem_results(  1,  0, 32'h00000001, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 0
      check_mem_results(  1,  1, 32'h00000001, 32'h00000001, 32'h00000001,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 1
      check_mem_results(  1,  2, 32'h00000001, 32'hffffffff, 32'hffffffff,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -1
      check_mem_results(  1,  3, 32'h00000001, 32'h00000002, 32'h00000002,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 2
      check_mem_results(  1,  4, 32'h00000001, 32'hfffffffe, 32'hfffffffe,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -2
      check_mem_results(  1,  5, 32'h00000001, 32'h7fffffff, 32'h7fffffff,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 2147483647
      check_mem_results(  1,  6, 32'h00000001, 32'h80000000, 32'h80000000,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -2147483648
      check_mem_results(  1,  7, 32'h00000001, 32'h80000001, 32'h80000001,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -2147483647
      check_mem_results(  1,  8, 32'h00000001, 32'h12345678, 32'h12345678,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 305419896
      check_mem_results(  1,  9, 32'h00000001, 32'h87654321, 32'h87654321,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -2023406815
      check_mem_results(  1, 10, 32'h00000001, 32'h0000ffff, 32'h0000ffff,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 65535
      check_mem_results(  1, 11, 32'h00000001, 32'hffff0000, 32'hffff0000,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -65536
      check_mem_results(  1, 12, 32'h00000001, 32'h40000000, 32'h40000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 1073741824
      check_mem_results(  1, 13, 32'h00000001, 32'hc0000000, 32'hc0000000,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -1073741824
      check_mem_results(  1, 14, 32'h00000001, 32'h7f7f7f7f, 32'h7f7f7f7f,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 2139062143
      check_mem_results(  1, 15, 32'h00000001, 32'h80808080, 32'h80808080,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -2139062144
      check_mem_results(  1, 16, 32'h00000001, 32'h13579bdf, 32'h13579bdf,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 324508639
      check_mem_results(  1, 17, 32'h00000001, 32'h2468ace0, 32'h2468ace0,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 610839776
      check_mem_results(  1, 18, 32'h00000001, 32'h00007fff, 32'h00007fff,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 32767
      check_mem_results(  1, 19, 32'h00000001, 32'hffff8000, 32'hffff8000,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -32768
      check_mem_results(  1, 20, 32'h00000001, 32'h01010101, 32'h01010101,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1 * 16843009
      check_mem_results(  1, 21, 32'h00000001, 32'hf0f0f0f0, 32'hf0f0f0f0,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -252645136
      check_mem_results(  1, 22, 32'h00000001, 32'hdeadbeef, 32'hdeadbeef,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -559038737
      check_mem_results(  1, 23, 32'h00000001, 32'hcafebabe, 32'hcafebabe,     32'hffffffff,       32'h00000000,     32'h00000000 ); // 1 * -889275714

      check_mem_results(  2,  0, 32'hffffffff, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -1 * 0
      check_mem_results(  2,  1, 32'hffffffff, 32'h00000001, 32'hffffffff,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -1 * 1
      check_mem_results(  2,  2, 32'hffffffff, 32'hffffffff, 32'h00000001,     32'h00000000,       32'hffffffff,     32'hfffffffe ); // -1 * -1
      check_mem_results(  2,  3, 32'hffffffff, 32'h00000002, 32'hfffffffe,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -1 * 2
      check_mem_results(  2,  4, 32'hffffffff, 32'hfffffffe, 32'h00000002,     32'h00000000,       32'hffffffff,     32'hfffffffd ); // -1 * -2
      check_mem_results(  2,  5, 32'hffffffff, 32'h7fffffff, 32'h80000001,     32'hffffffff,       32'hffffffff,     32'h7ffffffe ); // -1 * 2147483647
      check_mem_results(  2,  6, 32'hffffffff, 32'h80000000, 32'h80000000,     32'h00000000,       32'hffffffff,     32'h7fffffff ); // -1 * -2147483648
      check_mem_results(  2,  7, 32'hffffffff, 32'h80000001, 32'h7fffffff,     32'h00000000,       32'hffffffff,     32'h80000000 ); // -1 * -2147483647
      check_mem_results(  2,  8, 32'hffffffff, 32'h12345678, 32'hedcba988,     32'hffffffff,       32'hffffffff,     32'h12345677 ); // -1 * 305419896
      check_mem_results(  2,  9, 32'hffffffff, 32'h87654321, 32'h789abcdf,     32'h00000000,       32'hffffffff,     32'h87654320 ); // -1 * -2023406815
      check_mem_results(  2, 10, 32'hffffffff, 32'h0000ffff, 32'hffff0001,     32'hffffffff,       32'hffffffff,     32'h0000fffe ); // -1 * 65535
      check_mem_results(  2, 11, 32'hffffffff, 32'hffff0000, 32'h00010000,     32'h00000000,       32'hffffffff,     32'hfffeffff ); // -1 * -65536
      check_mem_results(  2, 12, 32'hffffffff, 32'h40000000, 32'hc0000000,     32'hffffffff,       32'hffffffff,     32'h3fffffff ); // -1 * 1073741824
      check_mem_results(  2, 13, 32'hffffffff, 32'hc0000000, 32'h40000000,     32'h00000000,       32'hffffffff,     32'hbfffffff ); // -1 * -1073741824
      check_mem_results(  2, 14, 32'hffffffff, 32'h7f7f7f7f, 32'h80808081,     32'hffffffff,       32'hffffffff,     32'h7f7f7f7e ); // -1 * 2139062143
      check_mem_results(  2, 15, 32'hffffffff, 32'h80808080, 32'h7f7f7f80,     32'h00000000,       32'hffffffff,     32'h8080807f ); // -1 * -2139062144
      check_mem_results(  2, 16, 32'hffffffff, 32'h13579bdf, 32'heca86421,     32'hffffffff,       32'hffffffff,     32'h13579bde ); // -1 * 324508639
      check_mem_results(  2, 17, 32'hffffffff, 32'h2468ace0, 32'hdb975320,     32'hffffffff,       32'hffffffff,     32'h2468acdf ); // -1 * 610839776
      check_mem_results(  2, 18, 32'hffffffff, 32'h00007fff, 32'hffff8001,     32'hffffffff,       32'hffffffff,     32'h00007ffe ); // -1 * 32767
      check_mem_results(  2, 19, 32'hffffffff, 32'hffff8000, 32'h00008000,     32'h00000000,       32'hffffffff,     32'hffff7fff ); // -1 * -32768
      check_mem_results(  2, 20, 32'hffffffff, 32'h01010101, 32'hfefefeff,     32'hffffffff,       32'hffffffff,     32'h01010100 ); // -1 * 16843009
      check_mem_results(  2, 21, 32'hffffffff, 32'hf0f0f0f0, 32'h0f0f0f10,     32'h00000000,       32'hffffffff,     32'hf0f0f0ef ); // -1 * -252645136
      check_mem_results(  2, 22, 32'hffffffff, 32'hdeadbeef, 32'h21524111,     32'h00000000,       32'hffffffff,     32'hdeadbeee ); // -1 * -559038737
      check_mem_results(  2, 23, 32'hffffffff, 32'hcafebabe, 32'h35014542,     32'h00000000,       32'hffffffff,     32'hcafebabd ); // -1 * -889275714

      check_mem_results(  3,  0, 32'h00000002, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 0
      check_mem_results(  3,  1, 32'h00000002, 32'h00000001, 32'h00000002,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 1
      check_mem_results(  3,  2, 32'h00000002, 32'hffffffff, 32'hfffffffe,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -1
      check_mem_results(  3,  3, 32'h00000002, 32'h00000002, 32'h00000004,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 2
      check_mem_results(  3,  4, 32'h00000002, 32'hfffffffe, 32'hfffffffc,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -2
      check_mem_results(  3,  5, 32'h00000002, 32'h7fffffff, 32'hfffffffe,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 2147483647
      check_mem_results(  3,  6, 32'h00000002, 32'h80000000, 32'h00000000,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -2147483648
      check_mem_results(  3,  7, 32'h00000002, 32'h80000001, 32'h00000002,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -2147483647
      check_mem_results(  3,  8, 32'h00000002, 32'h12345678, 32'h2468acf0,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 305419896
      check_mem_results(  3,  9, 32'h00000002, 32'h87654321, 32'h0eca8642,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -2023406815
      check_mem_results(  3, 10, 32'h00000002, 32'h0000ffff, 32'h0001fffe,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 65535
      check_mem_results(  3, 11, 32'h00000002, 32'hffff0000, 32'hfffe0000,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -65536
      check_mem_results(  3, 12, 32'h00000002, 32'h40000000, 32'h80000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 1073741824
      check_mem_results(  3, 13, 32'h00000002, 32'hc0000000, 32'h80000000,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -1073741824
      check_mem_results(  3, 14, 32'h00000002, 32'h7f7f7f7f, 32'hfefefefe,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 2139062143
      check_mem_results(  3, 15, 32'h00000002, 32'h80808080, 32'h01010100,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -2139062144
      check_mem_results(  3, 16, 32'h00000002, 32'h13579bdf, 32'h26af37be,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 324508639
      check_mem_results(  3, 17, 32'h00000002, 32'h2468ace0, 32'h48d159c0,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 610839776
      check_mem_results(  3, 18, 32'h00000002, 32'h00007fff, 32'h0000fffe,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 32767
      check_mem_results(  3, 19, 32'h00000002, 32'hffff8000, 32'hffff0000,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -32768
      check_mem_results(  3, 20, 32'h00000002, 32'h01010101, 32'h02020202,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2 * 16843009
      check_mem_results(  3, 21, 32'h00000002, 32'hf0f0f0f0, 32'he1e1e1e0,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -252645136
      check_mem_results(  3, 22, 32'h00000002, 32'hdeadbeef, 32'hbd5b7dde,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -559038737
      check_mem_results(  3, 23, 32'h00000002, 32'hcafebabe, 32'h95fd757c,     32'hffffffff,       32'h00000001,     32'h00000001 ); // 2 * -889275714

      check_mem_results(  4,  0, 32'hfffffffe, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -2 * 0
      check_mem_results(  4,  1, 32'hfffffffe, 32'h00000001, 32'hfffffffe,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -2 * 1
      check_mem_results(  4,  2, 32'hfffffffe, 32'hffffffff, 32'h00000002,     32'h00000000,       32'hfffffffe,     32'hfffffffd ); // -2 * -1
      check_mem_results(  4,  3, 32'hfffffffe, 32'h00000002, 32'hfffffffc,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -2 * 2
      check_mem_results(  4,  4, 32'hfffffffe, 32'hfffffffe, 32'h00000004,     32'h00000000,       32'hfffffffe,     32'hfffffffc ); // -2 * -2
      check_mem_results(  4,  5, 32'hfffffffe, 32'h7fffffff, 32'h00000002,     32'hffffffff,       32'hffffffff,     32'h7ffffffe ); // -2 * 2147483647
      check_mem_results(  4,  6, 32'hfffffffe, 32'h80000000, 32'h00000000,     32'h00000001,       32'hffffffff,     32'h7fffffff ); // -2 * -2147483648
      check_mem_results(  4,  7, 32'hfffffffe, 32'h80000001, 32'hfffffffe,     32'h00000000,       32'hfffffffe,     32'h7fffffff ); // -2 * -2147483647
      check_mem_results(  4,  8, 32'hfffffffe, 32'h12345678, 32'hdb975310,     32'hffffffff,       32'hffffffff,     32'h12345677 ); // -2 * 305419896
      check_mem_results(  4,  9, 32'hfffffffe, 32'h87654321, 32'hf13579be,     32'h00000000,       32'hfffffffe,     32'h8765431f ); // -2 * -2023406815
      check_mem_results(  4, 10, 32'hfffffffe, 32'h0000ffff, 32'hfffe0002,     32'hffffffff,       32'hffffffff,     32'h0000fffe ); // -2 * 65535
      check_mem_results(  4, 11, 32'hfffffffe, 32'hffff0000, 32'h00020000,     32'h00000000,       32'hfffffffe,     32'hfffefffe ); // -2 * -65536
      check_mem_results(  4, 12, 32'hfffffffe, 32'h40000000, 32'h80000000,     32'hffffffff,       32'hffffffff,     32'h3fffffff ); // -2 * 1073741824
      check_mem_results(  4, 13, 32'hfffffffe, 32'hc0000000, 32'h80000000,     32'h00000000,       32'hfffffffe,     32'hbffffffe ); // -2 * -1073741824
      check_mem_results(  4, 14, 32'hfffffffe, 32'h7f7f7f7f, 32'h01010102,     32'hffffffff,       32'hffffffff,     32'h7f7f7f7e ); // -2 * 2139062143
      check_mem_results(  4, 15, 32'hfffffffe, 32'h80808080, 32'hfefeff00,     32'h00000000,       32'hfffffffe,     32'h8080807e ); // -2 * -2139062144
      check_mem_results(  4, 16, 32'hfffffffe, 32'h13579bdf, 32'hd950c842,     32'hffffffff,       32'hffffffff,     32'h13579bde ); // -2 * 324508639
      check_mem_results(  4, 17, 32'hfffffffe, 32'h2468ace0, 32'hb72ea640,     32'hffffffff,       32'hffffffff,     32'h2468acdf ); // -2 * 610839776
      check_mem_results(  4, 18, 32'hfffffffe, 32'h00007fff, 32'hffff0002,     32'hffffffff,       32'hffffffff,     32'h00007ffe ); // -2 * 32767
      check_mem_results(  4, 19, 32'hfffffffe, 32'hffff8000, 32'h00010000,     32'h00000000,       32'hfffffffe,     32'hffff7ffe ); // -2 * -32768
      check_mem_results(  4, 20, 32'hfffffffe, 32'h01010101, 32'hfdfdfdfe,     32'hffffffff,       32'hffffffff,     32'h01010100 ); // -2 * 16843009
      check_mem_results(  4, 21, 32'hfffffffe, 32'hf0f0f0f0, 32'h1e1e1e20,     32'h00000000,       32'hfffffffe,     32'hf0f0f0ee ); // -2 * -252645136
      check_mem_results(  4, 22, 32'hfffffffe, 32'hdeadbeef, 32'h42a48222,     32'h00000000,       32'hfffffffe,     32'hdeadbeed ); // -2 * -559038737
      check_mem_results(  4, 23, 32'hfffffffe, 32'hcafebabe, 32'h6a028a84,     32'h00000000,       32'hfffffffe,     32'hcafebabc ); // -2 * -889275714

      check_mem_results(  5,  0, 32'h7fffffff, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2147483647 * 0
      check_mem_results(  5,  1, 32'h7fffffff, 32'h00000001, 32'h7fffffff,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2147483647 * 1
      check_mem_results(  5,  2, 32'h7fffffff, 32'hffffffff, 32'h80000001,     32'hffffffff,       32'h7ffffffe,     32'h7ffffffe ); // 2147483647 * -1
      check_mem_results(  5,  3, 32'h7fffffff, 32'h00000002, 32'hfffffffe,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2147483647 * 2
      check_mem_results(  5,  4, 32'h7fffffff, 32'hfffffffe, 32'h00000002,     32'hffffffff,       32'h7ffffffe,     32'h7ffffffe ); // 2147483647 * -2
      check_mem_results(  5,  5, 32'h7fffffff, 32'h7fffffff, 32'h00000001,     32'h3fffffff,       32'h3fffffff,     32'h3fffffff ); // 2147483647 * 2147483647
      check_mem_results(  5,  6, 32'h7fffffff, 32'h80000000, 32'h80000000,     32'hc0000000,       32'h3fffffff,     32'h3fffffff ); // 2147483647 * -2147483648
      check_mem_results(  5,  7, 32'h7fffffff, 32'h80000001, 32'hffffffff,     32'hc0000000,       32'h3fffffff,     32'h3fffffff ); // 2147483647 * -2147483647
      check_mem_results(  5,  8, 32'h7fffffff, 32'h12345678, 32'hedcba988,     32'h091a2b3b,       32'h091a2b3b,     32'h091a2b3b ); // 2147483647 * 305419896
      check_mem_results(  5,  9, 32'h7fffffff, 32'h87654321, 32'hf89abcdf,     32'hc3b2a190,       32'h43b2a18f,     32'h43b2a18f ); // 2147483647 * -2023406815
      check_mem_results(  5, 10, 32'h7fffffff, 32'h0000ffff, 32'h7fff0001,     32'h00007fff,       32'h00007fff,     32'h00007fff ); // 2147483647 * 65535
      check_mem_results(  5, 11, 32'h7fffffff, 32'hffff0000, 32'h00010000,     32'hffff8000,       32'h7fff7fff,     32'h7fff7fff ); // 2147483647 * -65536
      check_mem_results(  5, 12, 32'h7fffffff, 32'h40000000, 32'hc0000000,     32'h1fffffff,       32'h1fffffff,     32'h1fffffff ); // 2147483647 * 1073741824
      check_mem_results(  5, 13, 32'h7fffffff, 32'hc0000000, 32'h40000000,     32'he0000000,       32'h5fffffff,     32'h5fffffff ); // 2147483647 * -1073741824
      check_mem_results(  5, 14, 32'h7fffffff, 32'h7f7f7f7f, 32'h00808081,     32'h3fbfbfbf,       32'h3fbfbfbf,     32'h3fbfbfbf ); // 2147483647 * 2139062143
      check_mem_results(  5, 15, 32'h7fffffff, 32'h80808080, 32'h7f7f7f80,     32'hc0404040,       32'h4040403f,     32'h4040403f ); // 2147483647 * -2139062144
      check_mem_results(  5, 16, 32'h7fffffff, 32'h13579bdf, 32'h6ca86421,     32'h09abcdef,       32'h09abcdef,     32'h09abcdef ); // 2147483647 * 324508639
      check_mem_results(  5, 17, 32'h7fffffff, 32'h2468ace0, 32'hdb975320,     32'h1234566f,       32'h1234566f,     32'h1234566f ); // 2147483647 * 610839776
      check_mem_results(  5, 18, 32'h7fffffff, 32'h00007fff, 32'h7fff8001,     32'h00003fff,       32'h00003fff,     32'h00003fff ); // 2147483647 * 32767
      check_mem_results(  5, 19, 32'h7fffffff, 32'hffff8000, 32'h00008000,     32'hffffc000,       32'h7fffbfff,     32'h7fffbfff ); // 2147483647 * -32768
      check_mem_results(  5, 20, 32'h7fffffff, 32'h01010101, 32'h7efefeff,     32'h00808080,       32'h00808080,     32'h00808080 ); // 2147483647 * 16843009
      check_mem_results(  5, 21, 32'h7fffffff, 32'hf0f0f0f0, 32'h0f0f0f10,     32'hf8787878,       32'h78787877,     32'h78787877 ); // 2147483647 * -252645136
      check_mem_results(  5, 22, 32'h7fffffff, 32'hdeadbeef, 32'ha1524111,     32'hef56df77,       32'h6f56df76,     32'h6f56df76 ); // 2147483647 * -559038737
      check_mem_results(  5, 23, 32'h7fffffff, 32'hcafebabe, 32'h35014542,     32'he57f5d5f,       32'h657f5d5e,     32'h657f5d5e ); // 2147483647 * -889275714

      check_mem_results(  6,  0, 32'h80000000, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -2147483648 * 0
      check_mem_results(  6,  1, 32'h80000000, 32'h00000001, 32'h80000000,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -2147483648 * 1
      check_mem_results(  6,  2, 32'h80000000, 32'hffffffff, 32'h80000000,     32'h00000000,       32'h80000000,     32'h7fffffff ); // -2147483648 * -1
      check_mem_results(  6,  3, 32'h80000000, 32'h00000002, 32'h00000000,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -2147483648 * 2
      check_mem_results(  6,  4, 32'h80000000, 32'hfffffffe, 32'h00000000,     32'h00000001,       32'h80000001,     32'h7fffffff ); // -2147483648 * -2
      check_mem_results(  6,  5, 32'h80000000, 32'h7fffffff, 32'h80000000,     32'hc0000000,       32'hc0000000,     32'h3fffffff ); // -2147483648 * 2147483647
      check_mem_results(  6,  6, 32'h80000000, 32'h80000000, 32'h00000000,     32'h40000000,       32'hc0000000,     32'h40000000 ); // -2147483648 * -2147483648
      check_mem_results(  6,  7, 32'h80000000, 32'h80000001, 32'h80000000,     32'h3fffffff,       32'hbfffffff,     32'h40000000 ); // -2147483648 * -2147483647
      check_mem_results(  6,  8, 32'h80000000, 32'h12345678, 32'h00000000,     32'hf6e5d4c4,       32'hf6e5d4c4,     32'h091a2b3c ); // -2147483648 * 305419896
      check_mem_results(  6,  9, 32'h80000000, 32'h87654321, 32'h80000000,     32'h3c4d5e6f,       32'hbc4d5e6f,     32'h43b2a190 ); // -2147483648 * -2023406815
      check_mem_results(  6, 10, 32'h80000000, 32'h0000ffff, 32'h80000000,     32'hffff8000,       32'hffff8000,     32'h00007fff ); // -2147483648 * 65535
      check_mem_results(  6, 11, 32'h80000000, 32'hffff0000, 32'h00000000,     32'h00008000,       32'h80008000,     32'h7fff8000 ); // -2147483648 * -65536
      check_mem_results(  6, 12, 32'h80000000, 32'h40000000, 32'h00000000,     32'he0000000,       32'he0000000,     32'h20000000 ); // -2147483648 * 1073741824
      check_mem_results(  6, 13, 32'h80000000, 32'hc0000000, 32'h00000000,     32'h20000000,       32'ha0000000,     32'h60000000 ); // -2147483648 * -1073741824
      check_mem_results(  6, 14, 32'h80000000, 32'h7f7f7f7f, 32'h80000000,     32'hc0404040,       32'hc0404040,     32'h3fbfbfbf ); // -2147483648 * 2139062143
      check_mem_results(  6, 15, 32'h80000000, 32'h80808080, 32'h00000000,     32'h3fbfbfc0,       32'hbfbfbfc0,     32'h40404040 ); // -2147483648 * -2139062144
      check_mem_results(  6, 16, 32'h80000000, 32'h13579bdf, 32'h80000000,     32'hf6543210,       32'hf6543210,     32'h09abcdef ); // -2147483648 * 324508639
      check_mem_results(  6, 17, 32'h80000000, 32'h2468ace0, 32'h00000000,     32'hedcba990,       32'hedcba990,     32'h12345670 ); // -2147483648 * 610839776
      check_mem_results(  6, 18, 32'h80000000, 32'h00007fff, 32'h80000000,     32'hffffc000,       32'hffffc000,     32'h00003fff ); // -2147483648 * 32767
      check_mem_results(  6, 19, 32'h80000000, 32'hffff8000, 32'h00000000,     32'h00004000,       32'h80004000,     32'h7fffc000 ); // -2147483648 * -32768
      check_mem_results(  6, 20, 32'h80000000, 32'h01010101, 32'h80000000,     32'hff7f7f7f,       32'hff7f7f7f,     32'h00808080 ); // -2147483648 * 16843009
      check_mem_results(  6, 21, 32'h80000000, 32'hf0f0f0f0, 32'h00000000,     32'h07878788,       32'h87878788,     32'h78787878 ); // -2147483648 * -252645136
      check_mem_results(  6, 22, 32'h80000000, 32'hdeadbeef, 32'h80000000,     32'h10a92088,       32'h90a92088,     32'h6f56df77 ); // -2147483648 * -559038737
      check_mem_results(  6, 23, 32'h80000000, 32'hcafebabe, 32'h00000000,     32'h1a80a2a1,       32'h9a80a2a1,     32'h657f5d5f ); // -2147483648 * -889275714

      check_mem_results(  7,  0, 32'h80000001, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -2147483647 * 0
      check_mem_results(  7,  1, 32'h80000001, 32'h00000001, 32'h80000001,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -2147483647 * 1
      check_mem_results(  7,  2, 32'h80000001, 32'hffffffff, 32'h7fffffff,     32'h00000000,       32'h80000001,     32'h80000000 ); // -2147483647 * -1
      check_mem_results(  7,  3, 32'h80000001, 32'h00000002, 32'h00000002,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -2147483647 * 2
      check_mem_results(  7,  4, 32'h80000001, 32'hfffffffe, 32'hfffffffe,     32'h00000000,       32'h80000001,     32'h7fffffff ); // -2147483647 * -2
      check_mem_results(  7,  5, 32'h80000001, 32'h7fffffff, 32'hffffffff,     32'hc0000000,       32'hc0000000,     32'h3fffffff ); // -2147483647 * 2147483647
      check_mem_results(  7,  6, 32'h80000001, 32'h80000000, 32'h80000000,     32'h3fffffff,       32'hc0000000,     32'h40000000 ); // -2147483647 * -2147483648
      check_mem_results(  7,  7, 32'h80000001, 32'h80000001, 32'h00000001,     32'h3fffffff,       32'hc0000000,     32'h40000001 ); // -2147483647 * -2147483647
      check_mem_results(  7,  8, 32'h80000001, 32'h12345678, 32'h12345678,     32'hf6e5d4c4,       32'hf6e5d4c4,     32'h091a2b3c ); // -2147483647 * 305419896
      check_mem_results(  7,  9, 32'h80000001, 32'h87654321, 32'h07654321,     32'h3c4d5e6f,       32'hbc4d5e70,     32'h43b2a191 ); // -2147483647 * -2023406815
      check_mem_results(  7, 10, 32'h80000001, 32'h0000ffff, 32'h8000ffff,     32'hffff8000,       32'hffff8000,     32'h00007fff ); // -2147483647 * 65535
      check_mem_results(  7, 11, 32'h80000001, 32'hffff0000, 32'hffff0000,     32'h00007fff,       32'h80008000,     32'h7fff8000 ); // -2147483647 * -65536
      check_mem_results(  7, 12, 32'h80000001, 32'h40000000, 32'h40000000,     32'he0000000,       32'he0000000,     32'h20000000 ); // -2147483647 * 1073741824
      check_mem_results(  7, 13, 32'h80000001, 32'hc0000000, 32'hc0000000,     32'h1fffffff,       32'ha0000000,     32'h60000000 ); // -2147483647 * -1073741824
      check_mem_results(  7, 14, 32'h80000001, 32'h7f7f7f7f, 32'hff7f7f7f,     32'hc0404040,       32'hc0404040,     32'h3fbfbfbf ); // -2147483647 * 2139062143
      check_mem_results(  7, 15, 32'h80000001, 32'h80808080, 32'h80808080,     32'h3fbfbfbf,       32'hbfbfbfc0,     32'h40404040 ); // -2147483647 * -2139062144
      check_mem_results(  7, 16, 32'h80000001, 32'h13579bdf, 32'h93579bdf,     32'hf6543210,       32'hf6543210,     32'h09abcdef ); // -2147483647 * 324508639
      check_mem_results(  7, 17, 32'h80000001, 32'h2468ace0, 32'h2468ace0,     32'hedcba990,       32'hedcba990,     32'h12345670 ); // -2147483647 * 610839776
      check_mem_results(  7, 18, 32'h80000001, 32'h00007fff, 32'h80007fff,     32'hffffc000,       32'hffffc000,     32'h00003fff ); // -2147483647 * 32767
      check_mem_results(  7, 19, 32'h80000001, 32'hffff8000, 32'hffff8000,     32'h00003fff,       32'h80004000,     32'h7fffc000 ); // -2147483647 * -32768
      check_mem_results(  7, 20, 32'h80000001, 32'h01010101, 32'h81010101,     32'hff7f7f7f,       32'hff7f7f7f,     32'h00808080 ); // -2147483647 * 16843009
      check_mem_results(  7, 21, 32'h80000001, 32'hf0f0f0f0, 32'hf0f0f0f0,     32'h07878787,       32'h87878788,     32'h78787878 ); // -2147483647 * -252645136
      check_mem_results(  7, 22, 32'h80000001, 32'hdeadbeef, 32'h5eadbeef,     32'h10a92088,       32'h90a92089,     32'h6f56df78 ); // -2147483647 * -559038737
      check_mem_results(  7, 23, 32'h80000001, 32'hcafebabe, 32'hcafebabe,     32'h1a80a2a0,       32'h9a80a2a1,     32'h657f5d5f ); // -2147483647 * -889275714

      check_mem_results(  8,  0, 32'h12345678, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 305419896 * 0
      check_mem_results(  8,  1, 32'h12345678, 32'h00000001, 32'h12345678,     32'h00000000,       32'h00000000,     32'h00000000 ); // 305419896 * 1
      check_mem_results(  8,  2, 32'h12345678, 32'hffffffff, 32'hedcba988,     32'hffffffff,       32'h12345677,     32'h12345677 ); // 305419896 * -1
      check_mem_results(  8,  3, 32'h12345678, 32'h00000002, 32'h2468acf0,     32'h00000000,       32'h00000000,     32'h00000000 ); // 305419896 * 2
      check_mem_results(  8,  4, 32'h12345678, 32'hfffffffe, 32'hdb975310,     32'hffffffff,       32'h12345677,     32'h12345677 ); // 305419896 * -2
      check_mem_results(  8,  5, 32'h12345678, 32'h7fffffff, 32'hedcba988,     32'h091a2b3b,       32'h091a2b3b,     32'h091a2b3b ); // 305419896 * 2147483647
      check_mem_results(  8,  6, 32'h12345678, 32'h80000000, 32'h00000000,     32'hf6e5d4c4,       32'h091a2b3c,     32'h091a2b3c ); // 305419896 * -2147483648
      check_mem_results(  8,  7, 32'h12345678, 32'h80000001, 32'h12345678,     32'hf6e5d4c4,       32'h091a2b3c,     32'h091a2b3c ); // 305419896 * -2147483647
      check_mem_results(  8,  8, 32'h12345678, 32'h12345678, 32'h1df4d840,     32'h014b66dc,       32'h014b66dc,     32'h014b66dc ); // 305419896 * 305419896
      check_mem_results(  8,  9, 32'h12345678, 32'h87654321, 32'h70b88d78,     32'hf76c768d,       32'h09a0cd05,     32'h09a0cd05 ); // 305419896 * -2023406815
      check_mem_results(  8, 10, 32'h12345678, 32'h0000ffff, 32'h4443a988,     32'h00001234,       32'h00001234,     32'h00001234 ); // 305419896 * 65535
      check_mem_results(  8, 11, 32'h12345678, 32'hffff0000, 32'ha9880000,     32'hffffedcb,       32'h12344443,     32'h12344443 ); // 305419896 * -65536
      check_mem_results(  8, 12, 32'h12345678, 32'h40000000, 32'h00000000,     32'h048d159e,       32'h048d159e,     32'h048d159e ); // 305419896 * 1073741824
      check_mem_results(  8, 13, 32'h12345678, 32'hc0000000, 32'h00000000,     32'hfb72ea62,       32'h0da740da,     32'h0da740da ); // 305419896 * -1073741824
      check_mem_results(  8, 14, 32'h12345678, 32'h7f7f7f7f, 32'h6c646d88,     32'h091107ed,       32'h091107ed,     32'h091107ed ); // 305419896 * 2139062143
      check_mem_results(  8, 15, 32'h12345678, 32'h80808080, 32'h81673c00,     32'hf6eef812,       32'h09234e8a,     32'h09234e8a ); // 305419896 * -2139062144
      check_mem_results(  8, 16, 32'h12345678, 32'h13579bdf, 32'hd6b9fa88,     32'h01601d49,       32'h01601d49,     32'h01601d49 ); // 305419896 * 324508639
      check_mem_results(  8, 17, 32'h12345678, 32'h2468ace0, 32'h18a44900,     32'h0296cdb7,       32'h0296cdb7,     32'h0296cdb7 ); // 305419896 * 610839776
      check_mem_results(  8, 18, 32'h12345678, 32'h00007fff, 32'h1907a988,     32'h0000091a,       32'h0000091a,     32'h0000091a ); // 305419896 * 32767
      check_mem_results(  8, 19, 32'h12345678, 32'hffff8000, 32'hd4c40000,     32'hfffff6e5,       32'h12344d5d,     32'h12344d5d ); // 305419896 * -32768
      check_mem_results(  8, 20, 32'h12345678, 32'h01010101, 32'h1502ce78,     32'h0012469d,       32'h0012469d,     32'h0012469d ); // 305419896 * 16843009
      check_mem_results(  8, 21, 32'h12345678, 32'hf0f0f0f0, 32'hb2a19080,     32'hfeeddccb,       32'h11223343,     32'h11223343 ); // 305419896 * -252645136
      check_mem_results(  8, 22, 32'h12345678, 32'hdeadbeef, 32'h5621ca08,     32'hfda16776,       32'h0fd5bdee,     32'h0fd5bdee ); // 305419896 * -559038737
      check_mem_results(  8, 23, 32'h12345678, 32'hcafebabe, 32'h04bb5d10,     32'hfc3b12f8,       32'h0e6f6970,     32'h0e6f6970 ); // 305419896 * -889275714

      check_mem_results(  9,  0, 32'h87654321, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -2023406815 * 0
      check_mem_results(  9,  1, 32'h87654321, 32'h00000001, 32'h87654321,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -2023406815 * 1
      check_mem_results(  9,  2, 32'h87654321, 32'hffffffff, 32'h789abcdf,     32'h00000000,       32'h87654321,     32'h87654320 ); // -2023406815 * -1
      check_mem_results(  9,  3, 32'h87654321, 32'h00000002, 32'h0eca8642,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -2023406815 * 2
      check_mem_results(  9,  4, 32'h87654321, 32'hfffffffe, 32'hf13579be,     32'h00000000,       32'h87654321,     32'h8765431f ); // -2023406815 * -2
      check_mem_results(  9,  5, 32'h87654321, 32'h7fffffff, 32'hf89abcdf,     32'hc3b2a190,       32'hc3b2a190,     32'h43b2a18f ); // -2023406815 * 2147483647
      check_mem_results(  9,  6, 32'h87654321, 32'h80000000, 32'h80000000,     32'h3c4d5e6f,       32'hc3b2a190,     32'h43b2a190 ); // -2023406815 * -2147483648
      check_mem_results(  9,  7, 32'h87654321, 32'h80000001, 32'h07654321,     32'h3c4d5e6f,       32'hc3b2a190,     32'h43b2a191 ); // -2023406815 * -2147483647
      check_mem_results(  9,  8, 32'h87654321, 32'h12345678, 32'h70b88d78,     32'hf76c768d,       32'hf76c768d,     32'h09a0cd05 ); // -2023406815 * 305419896
      check_mem_results(  9,  9, 32'h87654321, 32'h87654321, 32'hd7a44a41,     32'h38d16e98,       32'hc036b1b9,     32'h479bf4da ); // -2023406815 * -2023406815
      check_mem_results(  9, 10, 32'h87654321, 32'h0000ffff, 32'hbbbbbcdf,     32'hffff8765,       32'hffff8765,     32'h00008764 ); // -2023406815 * 65535
      check_mem_results(  9, 11, 32'h87654321, 32'hffff0000, 32'hbcdf0000,     32'h0000789a,       32'h8765bbbb,     32'h8764bbbb ); // -2023406815 * -65536
      check_mem_results(  9, 12, 32'h87654321, 32'h40000000, 32'h40000000,     32'he1d950c8,       32'he1d950c8,     32'h21d950c8 ); // -2023406815 * 1073741824
      check_mem_results(  9, 13, 32'h87654321, 32'hc0000000, 32'hc0000000,     32'h1e26af37,       32'ha58bf258,     32'h658bf258 ); // -2023406815 * -1073741824
      check_mem_results(  9, 14, 32'h87654321, 32'h7f7f7f7f, 32'h13e8ac5f,     32'hc3ef2b79,       32'hc3ef2b79,     32'h436eaaf8 ); // -2023406815 * 2139062143
      check_mem_results(  9, 15, 32'h87654321, 32'h80808080, 32'h64b21080,     32'h3c10d487,       32'hc37617a8,     32'h43f69828 ); // -2023406815 * -2139062144
      check_mem_results(  9, 16, 32'h87654321, 32'h13579bdf, 32'h841174bf,     32'hf6e33df6,       32'hf6e33df6,     32'h0a3ad9d5 ); // -2023406815 * 324508639
      check_mem_results(  9, 17, 32'h87654321, 32'h2468ace0, 32'h6b1ce8e0,     32'heed8ed22,       32'heed8ed22,     32'h13419a02 ); // -2023406815 * 610839776
      check_mem_results(  9, 18, 32'h87654321, 32'h00007fff, 32'h1a2b3cdf,     32'hffffc3b3,       32'hffffc3b3,     32'h000043b2 ); // -2023406815 * 32767
      check_mem_results(  9, 19, 32'h87654321, 32'hffff8000, 32'h5e6f8000,     32'h00003c4d,       32'h87657f6e,     32'h8764ff6e ); // -2023406815 * -32768
      check_mem_results(  9, 20, 32'h87654321, 32'h01010101, 32'h50c96421,     32'hff86ec2f,       32'hff86ec2f,     32'h0087ed30 ); // -2023406815 * 16843009
      check_mem_results(  9, 21, 32'h87654321, 32'hf0f0f0f0, 32'hbccddef0,     32'h0718293a,       32'h8e7d6c5b,     32'h7f6e5d4b ); // -2023406815 * -252645136
      check_mem_results(  9, 22, 32'h87654321, 32'hdeadbeef, 32'h8aa929cf,     32'h0fb2b290,       32'h9717f5b1,     32'h75c5b4a0 ); // -2023406815 * -559038737
      check_mem_results(  9, 23, 32'h87654321, 32'hcafebabe, 32'hb4abcc7e,     32'h18f8a255,       32'ha05de576,     32'h6b5ca034 ); // -2023406815 * -889275714

      check_mem_results( 10,  0, 32'h0000ffff, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 65535 * 0
      check_mem_results( 10,  1, 32'h0000ffff, 32'h00000001, 32'h0000ffff,     32'h00000000,       32'h00000000,     32'h00000000 ); // 65535 * 1
      check_mem_results( 10,  2, 32'h0000ffff, 32'hffffffff, 32'hffff0001,     32'hffffffff,       32'h0000fffe,     32'h0000fffe ); // 65535 * -1
      check_mem_results( 10,  3, 32'h0000ffff, 32'h00000002, 32'h0001fffe,     32'h00000000,       32'h00000000,     32'h00000000 ); // 65535 * 2
      check_mem_results( 10,  4, 32'h0000ffff, 32'hfffffffe, 32'hfffe0002,     32'hffffffff,       32'h0000fffe,     32'h0000fffe ); // 65535 * -2
      check_mem_results( 10,  5, 32'h0000ffff, 32'h7fffffff, 32'h7fff0001,     32'h00007fff,       32'h00007fff,     32'h00007fff ); // 65535 * 2147483647
      check_mem_results( 10,  6, 32'h0000ffff, 32'h80000000, 32'h80000000,     32'hffff8000,       32'h00007fff,     32'h00007fff ); // 65535 * -2147483648
      check_mem_results( 10,  7, 32'h0000ffff, 32'h80000001, 32'h8000ffff,     32'hffff8000,       32'h00007fff,     32'h00007fff ); // 65535 * -2147483647
      check_mem_results( 10,  8, 32'h0000ffff, 32'h12345678, 32'h4443a988,     32'h00001234,       32'h00001234,     32'h00001234 ); // 65535 * 305419896
      check_mem_results( 10,  9, 32'h0000ffff, 32'h87654321, 32'hbbbbbcdf,     32'hffff8765,       32'h00008764,     32'h00008764 ); // 65535 * -2023406815
      check_mem_results( 10, 10, 32'h0000ffff, 32'h0000ffff, 32'hfffe0001,     32'h00000000,       32'h00000000,     32'h00000000 ); // 65535 * 65535
      check_mem_results( 10, 11, 32'h0000ffff, 32'hffff0000, 32'h00010000,     32'hffffffff,       32'h0000fffe,     32'h0000fffe ); // 65535 * -65536
      check_mem_results( 10, 12, 32'h0000ffff, 32'h40000000, 32'hc0000000,     32'h00003fff,       32'h00003fff,     32'h00003fff ); // 65535 * 1073741824
      check_mem_results( 10, 13, 32'h0000ffff, 32'hc0000000, 32'h40000000,     32'hffffc000,       32'h0000bfff,     32'h0000bfff ); // 65535 * -1073741824
      check_mem_results( 10, 14, 32'h0000ffff, 32'h7f7f7f7f, 32'hffff8081,     32'h00007f7e,       32'h00007f7e,     32'h00007f7e ); // 65535 * 2139062143
      check_mem_results( 10, 15, 32'h0000ffff, 32'h80808080, 32'hffff7f80,     32'hffff8080,       32'h0000807f,     32'h0000807f ); // 65535 * -2139062144
      check_mem_results( 10, 16, 32'h0000ffff, 32'h13579bdf, 32'h88876421,     32'h00001357,       32'h00001357,     32'h00001357 ); // 65535 * 324508639
      check_mem_results( 10, 17, 32'h0000ffff, 32'h2468ace0, 32'h88775320,     32'h00002468,       32'h00002468,     32'h00002468 ); // 65535 * 610839776
      check_mem_results( 10, 18, 32'h0000ffff, 32'h00007fff, 32'h7ffe8001,     32'h00000000,       32'h00000000,     32'h00000000 ); // 65535 * 32767
      check_mem_results( 10, 19, 32'h0000ffff, 32'hffff8000, 32'h80008000,     32'hffffffff,       32'h0000fffe,     32'h0000fffe ); // 65535 * -32768
      check_mem_results( 10, 20, 32'h0000ffff, 32'h01010101, 32'hfffffeff,     32'h00000100,       32'h00000100,     32'h00000100 ); // 65535 * 16843009
      check_mem_results( 10, 21, 32'h0000ffff, 32'hf0f0f0f0, 32'hffff0f10,     32'hfffff0f0,       32'h0000f0ef,     32'h0000f0ef ); // 65535 * -252645136
      check_mem_results( 10, 22, 32'h0000ffff, 32'hdeadbeef, 32'he0414111,     32'hffffdead,       32'h0000deac,     32'h0000deac ); // 65535 * -559038737
      check_mem_results( 10, 23, 32'h0000ffff, 32'hcafebabe, 32'hefbf4542,     32'hffffcafe,       32'h0000cafd,     32'h0000cafd ); // 65535 * -889275714

      check_mem_results( 11,  0, 32'hffff0000, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -65536 * 0
      check_mem_results( 11,  1, 32'hffff0000, 32'h00000001, 32'hffff0000,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -65536 * 1
      check_mem_results( 11,  2, 32'hffff0000, 32'hffffffff, 32'h00010000,     32'h00000000,       32'hffff0000,     32'hfffeffff ); // -65536 * -1
      check_mem_results( 11,  3, 32'hffff0000, 32'h00000002, 32'hfffe0000,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -65536 * 2
      check_mem_results( 11,  4, 32'hffff0000, 32'hfffffffe, 32'h00020000,     32'h00000000,       32'hffff0000,     32'hfffefffe ); // -65536 * -2
      check_mem_results( 11,  5, 32'hffff0000, 32'h7fffffff, 32'h00010000,     32'hffff8000,       32'hffff8000,     32'h7fff7fff ); // -65536 * 2147483647
      check_mem_results( 11,  6, 32'hffff0000, 32'h80000000, 32'h00000000,     32'h00008000,       32'hffff8000,     32'h7fff8000 ); // -65536 * -2147483648
      check_mem_results( 11,  7, 32'hffff0000, 32'h80000001, 32'hffff0000,     32'h00007fff,       32'hffff7fff,     32'h7fff8000 ); // -65536 * -2147483647
      check_mem_results( 11,  8, 32'hffff0000, 32'h12345678, 32'ha9880000,     32'hffffedcb,       32'hffffedcb,     32'h12344443 ); // -65536 * 305419896
      check_mem_results( 11,  9, 32'hffff0000, 32'h87654321, 32'hbcdf0000,     32'h0000789a,       32'hffff789a,     32'h8764bbbb ); // -65536 * -2023406815
      check_mem_results( 11, 10, 32'hffff0000, 32'h0000ffff, 32'h00010000,     32'hffffffff,       32'hffffffff,     32'h0000fffe ); // -65536 * 65535
      check_mem_results( 11, 11, 32'hffff0000, 32'hffff0000, 32'h00000000,     32'h00000001,       32'hffff0001,     32'hfffe0001 ); // -65536 * -65536
      check_mem_results( 11, 12, 32'hffff0000, 32'h40000000, 32'h00000000,     32'hffffc000,       32'hffffc000,     32'h3fffc000 ); // -65536 * 1073741824
      check_mem_results( 11, 13, 32'hffff0000, 32'hc0000000, 32'h00000000,     32'h00004000,       32'hffff4000,     32'hbfff4000 ); // -65536 * -1073741824
      check_mem_results( 11, 14, 32'hffff0000, 32'h7f7f7f7f, 32'h80810000,     32'hffff8080,       32'hffff8080,     32'h7f7effff ); // -65536 * 2139062143
      check_mem_results( 11, 15, 32'hffff0000, 32'h80808080, 32'h7f800000,     32'h00007f7f,       32'hffff7f7f,     32'h807fffff ); // -65536 * -2139062144
      check_mem_results( 11, 16, 32'hffff0000, 32'h13579bdf, 32'h64210000,     32'hffffeca8,       32'hffffeca8,     32'h13578887 ); // -65536 * 324508639
      check_mem_results( 11, 17, 32'hffff0000, 32'h2468ace0, 32'h53200000,     32'hffffdb97,       32'hffffdb97,     32'h24688877 ); // -65536 * 610839776
      check_mem_results( 11, 18, 32'hffff0000, 32'h00007fff, 32'h80010000,     32'hffffffff,       32'hffffffff,     32'h00007ffe ); // -65536 * 32767
      check_mem_results( 11, 19, 32'hffff0000, 32'hffff8000, 32'h80000000,     32'h00000000,       32'hffff0000,     32'hfffe8000 ); // -65536 * -32768
      check_mem_results( 11, 20, 32'hffff0000, 32'h01010101, 32'hfeff0000,     32'hfffffefe,       32'hfffffefe,     32'h0100ffff ); // -65536 * 16843009
      check_mem_results( 11, 21, 32'hffff0000, 32'hf0f0f0f0, 32'h0f100000,     32'h00000f0f,       32'hffff0f0f,     32'hf0efffff ); // -65536 * -252645136
      check_mem_results( 11, 22, 32'hffff0000, 32'hdeadbeef, 32'h41110000,     32'h00002152,       32'hffff2152,     32'hdeace041 ); // -65536 * -559038737
      check_mem_results( 11, 23, 32'hffff0000, 32'hcafebabe, 32'h45420000,     32'h00003501,       32'hffff3501,     32'hcafdefbf ); // -65536 * -889275714

      check_mem_results( 12,  0, 32'h40000000, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1073741824 * 0
      check_mem_results( 12,  1, 32'h40000000, 32'h00000001, 32'h40000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1073741824 * 1
      check_mem_results( 12,  2, 32'h40000000, 32'hffffffff, 32'hc0000000,     32'hffffffff,       32'h3fffffff,     32'h3fffffff ); // 1073741824 * -1
      check_mem_results( 12,  3, 32'h40000000, 32'h00000002, 32'h80000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 1073741824 * 2
      check_mem_results( 12,  4, 32'h40000000, 32'hfffffffe, 32'h80000000,     32'hffffffff,       32'h3fffffff,     32'h3fffffff ); // 1073741824 * -2
      check_mem_results( 12,  5, 32'h40000000, 32'h7fffffff, 32'hc0000000,     32'h1fffffff,       32'h1fffffff,     32'h1fffffff ); // 1073741824 * 2147483647
      check_mem_results( 12,  6, 32'h40000000, 32'h80000000, 32'h00000000,     32'he0000000,       32'h20000000,     32'h20000000 ); // 1073741824 * -2147483648
      check_mem_results( 12,  7, 32'h40000000, 32'h80000001, 32'h40000000,     32'he0000000,       32'h20000000,     32'h20000000 ); // 1073741824 * -2147483647
      check_mem_results( 12,  8, 32'h40000000, 32'h12345678, 32'h00000000,     32'h048d159e,       32'h048d159e,     32'h048d159e ); // 1073741824 * 305419896
      check_mem_results( 12,  9, 32'h40000000, 32'h87654321, 32'h40000000,     32'he1d950c8,       32'h21d950c8,     32'h21d950c8 ); // 1073741824 * -2023406815
      check_mem_results( 12, 10, 32'h40000000, 32'h0000ffff, 32'hc0000000,     32'h00003fff,       32'h00003fff,     32'h00003fff ); // 1073741824 * 65535
      check_mem_results( 12, 11, 32'h40000000, 32'hffff0000, 32'h00000000,     32'hffffc000,       32'h3fffc000,     32'h3fffc000 ); // 1073741824 * -65536
      check_mem_results( 12, 12, 32'h40000000, 32'h40000000, 32'h00000000,     32'h10000000,       32'h10000000,     32'h10000000 ); // 1073741824 * 1073741824
      check_mem_results( 12, 13, 32'h40000000, 32'hc0000000, 32'h00000000,     32'hf0000000,       32'h30000000,     32'h30000000 ); // 1073741824 * -1073741824
      check_mem_results( 12, 14, 32'h40000000, 32'h7f7f7f7f, 32'hc0000000,     32'h1fdfdfdf,       32'h1fdfdfdf,     32'h1fdfdfdf ); // 1073741824 * 2139062143
      check_mem_results( 12, 15, 32'h40000000, 32'h80808080, 32'h00000000,     32'he0202020,       32'h20202020,     32'h20202020 ); // 1073741824 * -2139062144
      check_mem_results( 12, 16, 32'h40000000, 32'h13579bdf, 32'hc0000000,     32'h04d5e6f7,       32'h04d5e6f7,     32'h04d5e6f7 ); // 1073741824 * 324508639
      check_mem_results( 12, 17, 32'h40000000, 32'h2468ace0, 32'h00000000,     32'h091a2b38,       32'h091a2b38,     32'h091a2b38 ); // 1073741824 * 610839776
      check_mem_results( 12, 18, 32'h40000000, 32'h00007fff, 32'hc0000000,     32'h00001fff,       32'h00001fff,     32'h00001fff ); // 1073741824 * 32767
      check_mem_results( 12, 19, 32'h40000000, 32'hffff8000, 32'h00000000,     32'hffffe000,       32'h3fffe000,     32'h3fffe000 ); // 1073741824 * -32768
      check_mem_results( 12, 20, 32'h40000000, 32'h01010101, 32'h40000000,     32'h00404040,       32'h00404040,     32'h00404040 ); // 1073741824 * 16843009
      check_mem_results( 12, 21, 32'h40000000, 32'hf0f0f0f0, 32'h00000000,     32'hfc3c3c3c,       32'h3c3c3c3c,     32'h3c3c3c3c ); // 1073741824 * -252645136
      check_mem_results( 12, 22, 32'h40000000, 32'hdeadbeef, 32'hc0000000,     32'hf7ab6fbb,       32'h37ab6fbb,     32'h37ab6fbb ); // 1073741824 * -559038737
      check_mem_results( 12, 23, 32'h40000000, 32'hcafebabe, 32'h80000000,     32'hf2bfaeaf,       32'h32bfaeaf,     32'h32bfaeaf ); // 1073741824 * -889275714

      check_mem_results( 13,  0, 32'hc0000000, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -1073741824 * 0
      check_mem_results( 13,  1, 32'hc0000000, 32'h00000001, 32'hc0000000,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -1073741824 * 1
      check_mem_results( 13,  2, 32'hc0000000, 32'hffffffff, 32'h40000000,     32'h00000000,       32'hc0000000,     32'hbfffffff ); // -1073741824 * -1
      check_mem_results( 13,  3, 32'hc0000000, 32'h00000002, 32'h80000000,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -1073741824 * 2
      check_mem_results( 13,  4, 32'hc0000000, 32'hfffffffe, 32'h80000000,     32'h00000000,       32'hc0000000,     32'hbffffffe ); // -1073741824 * -2
      check_mem_results( 13,  5, 32'hc0000000, 32'h7fffffff, 32'h40000000,     32'he0000000,       32'he0000000,     32'h5fffffff ); // -1073741824 * 2147483647
      check_mem_results( 13,  6, 32'hc0000000, 32'h80000000, 32'h00000000,     32'h20000000,       32'he0000000,     32'h60000000 ); // -1073741824 * -2147483648
      check_mem_results( 13,  7, 32'hc0000000, 32'h80000001, 32'hc0000000,     32'h1fffffff,       32'hdfffffff,     32'h60000000 ); // -1073741824 * -2147483647
      check_mem_results( 13,  8, 32'hc0000000, 32'h12345678, 32'h00000000,     32'hfb72ea62,       32'hfb72ea62,     32'h0da740da ); // -1073741824 * 305419896
      check_mem_results( 13,  9, 32'hc0000000, 32'h87654321, 32'hc0000000,     32'h1e26af37,       32'hde26af37,     32'h658bf258 ); // -1073741824 * -2023406815
      check_mem_results( 13, 10, 32'hc0000000, 32'h0000ffff, 32'h40000000,     32'hffffc000,       32'hffffc000,     32'h0000bfff ); // -1073741824 * 65535
      check_mem_results( 13, 11, 32'hc0000000, 32'hffff0000, 32'h00000000,     32'h00004000,       32'hc0004000,     32'hbfff4000 ); // -1073741824 * -65536
      check_mem_results( 13, 12, 32'hc0000000, 32'h40000000, 32'h00000000,     32'hf0000000,       32'hf0000000,     32'h30000000 ); // -1073741824 * 1073741824
      check_mem_results( 13, 13, 32'hc0000000, 32'hc0000000, 32'h00000000,     32'h10000000,       32'hd0000000,     32'h90000000 ); // -1073741824 * -1073741824
      check_mem_results( 13, 14, 32'hc0000000, 32'h7f7f7f7f, 32'h40000000,     32'he0202020,       32'he0202020,     32'h5f9f9f9f ); // -1073741824 * 2139062143
      check_mem_results( 13, 15, 32'hc0000000, 32'h80808080, 32'h00000000,     32'h1fdfdfe0,       32'hdfdfdfe0,     32'h60606060 ); // -1073741824 * -2139062144
      check_mem_results( 13, 16, 32'hc0000000, 32'h13579bdf, 32'h40000000,     32'hfb2a1908,       32'hfb2a1908,     32'h0e81b4e7 ); // -1073741824 * 324508639
      check_mem_results( 13, 17, 32'hc0000000, 32'h2468ace0, 32'h00000000,     32'hf6e5d4c8,       32'hf6e5d4c8,     32'h1b4e81a8 ); // -1073741824 * 610839776
      check_mem_results( 13, 18, 32'hc0000000, 32'h00007fff, 32'h40000000,     32'hffffe000,       32'hffffe000,     32'h00005fff ); // -1073741824 * 32767
      check_mem_results( 13, 19, 32'hc0000000, 32'hffff8000, 32'h00000000,     32'h00002000,       32'hc0002000,     32'hbfffa000 ); // -1073741824 * -32768
      check_mem_results( 13, 20, 32'hc0000000, 32'h01010101, 32'hc0000000,     32'hffbfbfbf,       32'hffbfbfbf,     32'h00c0c0c0 ); // -1073741824 * 16843009
      check_mem_results( 13, 21, 32'hc0000000, 32'hf0f0f0f0, 32'h00000000,     32'h03c3c3c4,       32'hc3c3c3c4,     32'hb4b4b4b4 ); // -1073741824 * -252645136
      check_mem_results( 13, 22, 32'hc0000000, 32'hdeadbeef, 32'h40000000,     32'h08549044,       32'hc8549044,     32'ha7024f33 ); // -1073741824 * -559038737
      check_mem_results( 13, 23, 32'hc0000000, 32'hcafebabe, 32'h80000000,     32'h0d405150,       32'hcd405150,     32'h983f0c0e ); // -1073741824 * -889275714

      check_mem_results( 14,  0, 32'h7f7f7f7f, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2139062143 * 0
      check_mem_results( 14,  1, 32'h7f7f7f7f, 32'h00000001, 32'h7f7f7f7f,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2139062143 * 1
      check_mem_results( 14,  2, 32'h7f7f7f7f, 32'hffffffff, 32'h80808081,     32'hffffffff,       32'h7f7f7f7e,     32'h7f7f7f7e ); // 2139062143 * -1
      check_mem_results( 14,  3, 32'h7f7f7f7f, 32'h00000002, 32'hfefefefe,     32'h00000000,       32'h00000000,     32'h00000000 ); // 2139062143 * 2
      check_mem_results( 14,  4, 32'h7f7f7f7f, 32'hfffffffe, 32'h01010102,     32'hffffffff,       32'h7f7f7f7e,     32'h7f7f7f7e ); // 2139062143 * -2
      check_mem_results( 14,  5, 32'h7f7f7f7f, 32'h7fffffff, 32'h00808081,     32'h3fbfbfbf,       32'h3fbfbfbf,     32'h3fbfbfbf ); // 2139062143 * 2147483647
      check_mem_results( 14,  6, 32'h7f7f7f7f, 32'h80000000, 32'h80000000,     32'hc0404040,       32'h3fbfbfbf,     32'h3fbfbfbf ); // 2139062143 * -2147483648
      check_mem_results( 14,  7, 32'h7f7f7f7f, 32'h80000001, 32'hff7f7f7f,     32'hc0404040,       32'h3fbfbfbf,     32'h3fbfbfbf ); // 2139062143 * -2147483647
      check_mem_results( 14,  8, 32'h7f7f7f7f, 32'h12345678, 32'h6c646d88,     32'h091107ed,       32'h091107ed,     32'h091107ed ); // 2139062143 * 305419896
      check_mem_results( 14,  9, 32'h7f7f7f7f, 32'h87654321, 32'h13e8ac5f,     32'hc3ef2b79,       32'h436eaaf8,     32'h436eaaf8 ); // 2139062143 * -2023406815
      check_mem_results( 14, 10, 32'h7f7f7f7f, 32'h0000ffff, 32'hffff8081,     32'h00007f7e,       32'h00007f7e,     32'h00007f7e ); // 2139062143 * 65535
      check_mem_results( 14, 11, 32'h7f7f7f7f, 32'hffff0000, 32'h80810000,     32'hffff8080,       32'h7f7effff,     32'h7f7effff ); // 2139062143 * -65536
      check_mem_results( 14, 12, 32'h7f7f7f7f, 32'h40000000, 32'hc0000000,     32'h1fdfdfdf,       32'h1fdfdfdf,     32'h1fdfdfdf ); // 2139062143 * 1073741824
      check_mem_results( 14, 13, 32'h7f7f7f7f, 32'hc0000000, 32'h40000000,     32'he0202020,       32'h5f9f9f9f,     32'h5f9f9f9f ); // 2139062143 * -1073741824
      check_mem_results( 14, 14, 32'h7f7f7f7f, 32'h7f7f7f7f, 32'hc1814101,     32'h3f7fbfff,       32'h3f7fbfff,     32'h3f7fbfff ); // 2139062143 * 2139062143
      check_mem_results( 14, 15, 32'h7f7f7f7f, 32'h80808080, 32'hbeff3f80,     32'hc0803fff,       32'h3fffbf7e,     32'h3fffbf7e ); // 2139062143 * -2139062144
      check_mem_results( 14, 16, 32'h7f7f7f7f, 32'h13579bdf, 32'h036af4a1,     32'h09a2186c,       32'h09a2186c,     32'h09a2186c ); // 2139062143 * 324508639
      check_mem_results( 14, 17, 32'h7f7f7f7f, 32'h2468ace0, 32'he0d0e320,     32'h12220fd2,       32'h12220fd2,     32'h12220fd2 ); // 2139062143 * 610839776
      check_mem_results( 14, 18, 32'h7f7f7f7f, 32'h00007fff, 32'h40400081,     32'h00003fbf,       32'h00003fbf,     32'h00003fbf ); // 2139062143 * 32767
      check_mem_results( 14, 19, 32'h7f7f7f7f, 32'hffff8000, 32'h40408000,     32'hffffc040,       32'h7f7f3fbf,     32'h7f7f3fbf ); // 2139062143 * -32768
      check_mem_results( 14, 20, 32'h7f7f7f7f, 32'h01010101, 32'hfd7dfe7f,     32'h007fff7e,       32'h007fff7e,     32'h007fff7e ); // 2139062143 * 16843009
      check_mem_results( 14, 21, 32'h7f7f7f7f, 32'hf0f0f0f0, 32'ha61e9710,     32'hf880078e,       32'h77ff870d,     32'h77ff870d ); // 2139062143 * -252645136
      check_mem_results( 14, 22, 32'h7f7f7f7f, 32'hdeadbeef, 32'hf37b4991,     32'hef679951,       32'h6ee718d0,     32'h6ee718d0 ); // 2139062143 * -559038737
      check_mem_results( 14, 23, 32'h7f7f7f7f, 32'hcafebabe, 32'hf944e642,     32'he599f89c,       32'h6519781b,     32'h6519781b ); // 2139062143 * -889275714

      check_mem_results( 15,  0, 32'h80808080, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -2139062144 * 0
      check_mem_results( 15,  1, 32'h80808080, 32'h00000001, 32'h80808080,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -2139062144 * 1
      check_mem_results( 15,  2, 32'h80808080, 32'hffffffff, 32'h7f7f7f80,     32'h00000000,       32'h80808080,     32'h8080807f ); // -2139062144 * -1
      check_mem_results( 15,  3, 32'h80808080, 32'h00000002, 32'h01010100,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -2139062144 * 2
      check_mem_results( 15,  4, 32'h80808080, 32'hfffffffe, 32'hfefeff00,     32'h00000000,       32'h80808080,     32'h8080807e ); // -2139062144 * -2
      check_mem_results( 15,  5, 32'h80808080, 32'h7fffffff, 32'h7f7f7f80,     32'hc0404040,       32'hc0404040,     32'h4040403f ); // -2139062144 * 2147483647
      check_mem_results( 15,  6, 32'h80808080, 32'h80000000, 32'h00000000,     32'h3fbfbfc0,       32'hc0404040,     32'h40404040 ); // -2139062144 * -2147483648
      check_mem_results( 15,  7, 32'h80808080, 32'h80000001, 32'h80808080,     32'h3fbfbfbf,       32'hc040403f,     32'h40404040 ); // -2139062144 * -2147483647
      check_mem_results( 15,  8, 32'h80808080, 32'h12345678, 32'h81673c00,     32'hf6eef812,       32'hf6eef812,     32'h09234e8a ); // -2139062144 * 305419896
      check_mem_results( 15,  9, 32'h80808080, 32'h87654321, 32'h64b21080,     32'h3c10d487,       32'hbc915507,     32'h43f69828 ); // -2139062144 * -2023406815
      check_mem_results( 15, 10, 32'h80808080, 32'h0000ffff, 32'hffff7f80,     32'hffff8080,       32'hffff8080,     32'h0000807f ); // -2139062144 * 65535
      check_mem_results( 15, 11, 32'h80808080, 32'hffff0000, 32'h7f800000,     32'h00007f7f,       32'h8080ffff,     32'h807fffff ); // -2139062144 * -65536
      check_mem_results( 15, 12, 32'h80808080, 32'h40000000, 32'h00000000,     32'he0202020,       32'he0202020,     32'h20202020 ); // -2139062144 * 1073741824
      check_mem_results( 15, 13, 32'h80808080, 32'hc0000000, 32'h00000000,     32'h1fdfdfe0,       32'ha0606060,     32'h60606060 ); // -2139062144 * -1073741824
      check_mem_results( 15, 14, 32'h80808080, 32'h7f7f7f7f, 32'hbeff3f80,     32'hc0803fff,       32'hc0803fff,     32'h3fffbf7e ); // -2139062144 * 2139062143
      check_mem_results( 15, 15, 32'h80808080, 32'h80808080, 32'hc0804000,     32'h3f7fc000,       32'hc0004080,     32'h4080c100 ); // -2139062144 * -2139062144
      check_mem_results( 15, 16, 32'h80808080, 32'h13579bdf, 32'he93d6f80,     32'hf65de793,       32'hf65de793,     32'h09b58372 ); // -2139062144 * 324508639
      check_mem_results( 15, 17, 32'h80808080, 32'h2468ace0, 32'hfac67000,     32'hedddf02c,       32'hedddf02c,     32'h12469d0c ); // -2139062144 * 610839776
      check_mem_results( 15, 18, 32'h80808080, 32'h00007fff, 32'hbfbf7f80,     32'hffffc040,       32'hffffc040,     32'h0000403f ); // -2139062144 * 32767
      check_mem_results( 15, 19, 32'h80808080, 32'hffff8000, 32'hbfc00000,     32'h00003fbf,       32'h8080c03f,     32'h8080403f ); // -2139062144 * -32768
      check_mem_results( 15, 20, 32'h80808080, 32'h01010101, 32'h01810080,     32'hff800081,       32'hff800081,     32'h00810182 ); // -2139062144 * 16843009
      check_mem_results( 15, 21, 32'h80808080, 32'hf0f0f0f0, 32'h68f07800,     32'h077ff871,       32'h880078f1,     32'h78f169e1 ); // -2139062144 * -252645136
      check_mem_results( 15, 22, 32'h80808080, 32'hdeadbeef, 32'h2dd6f780,     32'h109866ae,       32'h9118e72e,     32'h6fc6a61d ); // -2139062144 * -559038737
      check_mem_results( 15, 23, 32'h80808080, 32'hcafebabe, 32'h3bbc5f00,     32'h1a660763,       32'h9ae687e3,     32'h65e542a1 ); // -2139062144 * -889275714

      check_mem_results( 16,  0, 32'h13579bdf, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 324508639 * 0
      check_mem_results( 16,  1, 32'h13579bdf, 32'h00000001, 32'h13579bdf,     32'h00000000,       32'h00000000,     32'h00000000 ); // 324508639 * 1
      check_mem_results( 16,  2, 32'h13579bdf, 32'hffffffff, 32'heca86421,     32'hffffffff,       32'h13579bde,     32'h13579bde ); // 324508639 * -1
      check_mem_results( 16,  3, 32'h13579bdf, 32'h00000002, 32'h26af37be,     32'h00000000,       32'h00000000,     32'h00000000 ); // 324508639 * 2
      check_mem_results( 16,  4, 32'h13579bdf, 32'hfffffffe, 32'hd950c842,     32'hffffffff,       32'h13579bde,     32'h13579bde ); // 324508639 * -2
      check_mem_results( 16,  5, 32'h13579bdf, 32'h7fffffff, 32'h6ca86421,     32'h09abcdef,       32'h09abcdef,     32'h09abcdef ); // 324508639 * 2147483647
      check_mem_results( 16,  6, 32'h13579bdf, 32'h80000000, 32'h80000000,     32'hf6543210,       32'h09abcdef,     32'h09abcdef ); // 324508639 * -2147483648
      check_mem_results( 16,  7, 32'h13579bdf, 32'h80000001, 32'h93579bdf,     32'hf6543210,       32'h09abcdef,     32'h09abcdef ); // 324508639 * -2147483647
      check_mem_results( 16,  8, 32'h13579bdf, 32'h12345678, 32'hd6b9fa88,     32'h01601d49,       32'h01601d49,     32'h01601d49 ); // 324508639 * 305419896
      check_mem_results( 16,  9, 32'h13579bdf, 32'h87654321, 32'h841174bf,     32'hf6e33df6,       32'h0a3ad9d5,     32'h0a3ad9d5 ); // 324508639 * -2023406815
      check_mem_results( 16, 10, 32'h13579bdf, 32'h0000ffff, 32'h88876421,     32'h00001357,       32'h00001357,     32'h00001357 ); // 324508639 * 65535
      check_mem_results( 16, 11, 32'h13579bdf, 32'hffff0000, 32'h64210000,     32'hffffeca8,       32'h13578887,     32'h13578887 ); // 324508639 * -65536
      check_mem_results( 16, 12, 32'h13579bdf, 32'h40000000, 32'hc0000000,     32'h04d5e6f7,       32'h04d5e6f7,     32'h04d5e6f7 ); // 324508639 * 1073741824
      check_mem_results( 16, 13, 32'h13579bdf, 32'hc0000000, 32'h40000000,     32'hfb2a1908,       32'h0e81b4e7,     32'h0e81b4e7 ); // 324508639 * -1073741824
      check_mem_results( 16, 14, 32'h13579bdf, 32'h7f7f7f7f, 32'h036af4a1,     32'h09a2186c,       32'h09a2186c,     32'h09a2186c ); // 324508639 * 2139062143
      check_mem_results( 16, 15, 32'h13579bdf, 32'h80808080, 32'he93d6f80,     32'hf65de793,       32'h09b58372,     32'h09b58372 ); // 324508639 * -2139062144
      check_mem_results( 16, 16, 32'h13579bdf, 32'h13579bdf, 32'h6a79cc41,     32'h01761f1e,       32'h01761f1e,     32'h01761f1e ); // 324508639 * 324508639
      check_mem_results( 16, 17, 32'h13579bdf, 32'h2468ace0, 32'h77fa3720,     32'h02c03a92,       32'h02c03a92,     32'h02c03a92 ); // 324508639 * 610839776
      check_mem_results( 16, 18, 32'h13579bdf, 32'h00007fff, 32'hba97e421,     32'h000009ab,       32'h000009ab,     32'h000009ab ); // 324508639 * 32767
      check_mem_results( 16, 19, 32'h13579bdf, 32'hffff8000, 32'h32108000,     32'hfffff654,       32'h13579233,     32'h13579233 ); // 324508639 * -32768
      check_mem_results( 16, 20, 32'h13579bdf, 32'h01010101, 32'he5d27adf,     32'h00136b06,       32'h00136b06,     32'h00136b06 ); // 324508639 * 16843009
      check_mem_results( 16, 21, 32'h13579bdf, 32'hf0f0f0f0, 32'h75533110,     32'hfedcba98,       32'h12345677,     32'h12345677 ); // 324508639 * -252645136
      check_mem_results( 16, 22, 32'h13579bdf, 32'hdeadbeef, 32'hcc2d0731,     32'hfd7b7ded,       32'h10d319cc,     32'h10d319cc ); // 324508639 * -559038737
      check_mem_results( 16, 23, 32'h13579bdf, 32'hcafebabe, 32'h9f87b582,     32'hfbfec427,       32'h0f566006,     32'h0f566006 ); // 324508639 * -889275714

      check_mem_results( 17,  0, 32'h2468ace0, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 610839776 * 0
      check_mem_results( 17,  1, 32'h2468ace0, 32'h00000001, 32'h2468ace0,     32'h00000000,       32'h00000000,     32'h00000000 ); // 610839776 * 1
      check_mem_results( 17,  2, 32'h2468ace0, 32'hffffffff, 32'hdb975320,     32'hffffffff,       32'h2468acdf,     32'h2468acdf ); // 610839776 * -1
      check_mem_results( 17,  3, 32'h2468ace0, 32'h00000002, 32'h48d159c0,     32'h00000000,       32'h00000000,     32'h00000000 ); // 610839776 * 2
      check_mem_results( 17,  4, 32'h2468ace0, 32'hfffffffe, 32'hb72ea640,     32'hffffffff,       32'h2468acdf,     32'h2468acdf ); // 610839776 * -2
      check_mem_results( 17,  5, 32'h2468ace0, 32'h7fffffff, 32'hdb975320,     32'h1234566f,       32'h1234566f,     32'h1234566f ); // 610839776 * 2147483647
      check_mem_results( 17,  6, 32'h2468ace0, 32'h80000000, 32'h00000000,     32'hedcba990,       32'h12345670,     32'h12345670 ); // 610839776 * -2147483648
      check_mem_results( 17,  7, 32'h2468ace0, 32'h80000001, 32'h2468ace0,     32'hedcba990,       32'h12345670,     32'h12345670 ); // 610839776 * -2147483647
      check_mem_results( 17,  8, 32'h2468ace0, 32'h12345678, 32'h18a44900,     32'h0296cdb7,       32'h0296cdb7,     32'h0296cdb7 ); // 610839776 * 305419896
      check_mem_results( 17,  9, 32'h2468ace0, 32'h87654321, 32'h6b1ce8e0,     32'heed8ed22,       32'h13419a02,     32'h13419a02 ); // 610839776 * -2023406815
      check_mem_results( 17, 10, 32'h2468ace0, 32'h0000ffff, 32'h88775320,     32'h00002468,       32'h00002468,     32'h00002468 ); // 610839776 * 65535
      check_mem_results( 17, 11, 32'h2468ace0, 32'hffff0000, 32'h53200000,     32'hffffdb97,       32'h24688877,     32'h24688877 ); // 610839776 * -65536
      check_mem_results( 17, 12, 32'h2468ace0, 32'h40000000, 32'h00000000,     32'h091a2b38,       32'h091a2b38,     32'h091a2b38 ); // 610839776 * 1073741824
      check_mem_results( 17, 13, 32'h2468ace0, 32'hc0000000, 32'h00000000,     32'hf6e5d4c8,       32'h1b4e81a8,     32'h1b4e81a8 ); // 610839776 * -1073741824
      check_mem_results( 17, 14, 32'h2468ace0, 32'h7f7f7f7f, 32'he0d0e320,     32'h12220fd2,       32'h12220fd2,     32'h12220fd2 ); // 610839776 * 2139062143
      check_mem_results( 17, 15, 32'h2468ace0, 32'h80808080, 32'hfac67000,     32'hedddf02c,       32'h12469d0c,     32'h12469d0c ); // 610839776 * -2139062144
      check_mem_results( 17, 16, 32'h2468ace0, 32'h13579bdf, 32'h77fa3720,     32'h02c03a92,       32'h02c03a92,     32'h02c03a92 ); // 610839776 * 324508639
      check_mem_results( 17, 17, 32'h2468ace0, 32'h2468ace0, 32'heabdc400,     32'h052d9b6b,       32'h052d9b6b,     32'h052d9b6b ); // 610839776 * 610839776
      check_mem_results( 17, 18, 32'h2468ace0, 32'h00007fff, 32'h32075320,     32'h00001234,       32'h00001234,     32'h00001234 ); // 610839776 * 32767
      check_mem_results( 17, 19, 32'h2468ace0, 32'hffff8000, 32'ha9900000,     32'hffffedcb,       32'h24689aab,     32'h24689aab ); // 610839776 * -32768
      check_mem_results( 17, 20, 32'h2468ace0, 32'h01010101, 32'h19f58ce0,     32'h00248d3a,       32'h00248d3a,     32'h00248d3a ); // 610839776 * 16843009
      check_mem_results( 17, 21, 32'h2468ace0, 32'hf0f0f0f0, 32'h56341200,     32'hfddbb998,       32'h22446678,     32'h22446678 ); // 610839776 * -252645136
      check_mem_results( 17, 22, 32'h2468ace0, 32'hdeadbeef, 32'hc167a520,     32'hfb42ceee,       32'h1fab7bce,     32'h1fab7bce ); // 610839776 * -559038737
      check_mem_results( 17, 23, 32'h2468ace0, 32'hcafebabe, 32'h598b0e40,     32'hf87625f3,       32'h1cded2d3,     32'h1cded2d3 ); // 610839776 * -889275714

      check_mem_results( 18,  0, 32'h00007fff, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 32767 * 0
      check_mem_results( 18,  1, 32'h00007fff, 32'h00000001, 32'h00007fff,     32'h00000000,       32'h00000000,     32'h00000000 ); // 32767 * 1
      check_mem_results( 18,  2, 32'h00007fff, 32'hffffffff, 32'hffff8001,     32'hffffffff,       32'h00007ffe,     32'h00007ffe ); // 32767 * -1
      check_mem_results( 18,  3, 32'h00007fff, 32'h00000002, 32'h0000fffe,     32'h00000000,       32'h00000000,     32'h00000000 ); // 32767 * 2
      check_mem_results( 18,  4, 32'h00007fff, 32'hfffffffe, 32'hffff0002,     32'hffffffff,       32'h00007ffe,     32'h00007ffe ); // 32767 * -2
      check_mem_results( 18,  5, 32'h00007fff, 32'h7fffffff, 32'h7fff8001,     32'h00003fff,       32'h00003fff,     32'h00003fff ); // 32767 * 2147483647
      check_mem_results( 18,  6, 32'h00007fff, 32'h80000000, 32'h80000000,     32'hffffc000,       32'h00003fff,     32'h00003fff ); // 32767 * -2147483648
      check_mem_results( 18,  7, 32'h00007fff, 32'h80000001, 32'h80007fff,     32'hffffc000,       32'h00003fff,     32'h00003fff ); // 32767 * -2147483647
      check_mem_results( 18,  8, 32'h00007fff, 32'h12345678, 32'h1907a988,     32'h0000091a,       32'h0000091a,     32'h0000091a ); // 32767 * 305419896
      check_mem_results( 18,  9, 32'h00007fff, 32'h87654321, 32'h1a2b3cdf,     32'hffffc3b3,       32'h000043b2,     32'h000043b2 ); // 32767 * -2023406815
      check_mem_results( 18, 10, 32'h00007fff, 32'h0000ffff, 32'h7ffe8001,     32'h00000000,       32'h00000000,     32'h00000000 ); // 32767 * 65535
      check_mem_results( 18, 11, 32'h00007fff, 32'hffff0000, 32'h80010000,     32'hffffffff,       32'h00007ffe,     32'h00007ffe ); // 32767 * -65536
      check_mem_results( 18, 12, 32'h00007fff, 32'h40000000, 32'hc0000000,     32'h00001fff,       32'h00001fff,     32'h00001fff ); // 32767 * 1073741824
      check_mem_results( 18, 13, 32'h00007fff, 32'hc0000000, 32'h40000000,     32'hffffe000,       32'h00005fff,     32'h00005fff ); // 32767 * -1073741824
      check_mem_results( 18, 14, 32'h00007fff, 32'h7f7f7f7f, 32'h40400081,     32'h00003fbf,       32'h00003fbf,     32'h00003fbf ); // 32767 * 2139062143
      check_mem_results( 18, 15, 32'h00007fff, 32'h80808080, 32'hbfbf7f80,     32'hffffc040,       32'h0000403f,     32'h0000403f ); // 32767 * -2139062144
      check_mem_results( 18, 16, 32'h00007fff, 32'h13579bdf, 32'hba97e421,     32'h000009ab,       32'h000009ab,     32'h000009ab ); // 32767 * 324508639
      check_mem_results( 18, 17, 32'h00007fff, 32'h2468ace0, 32'h32075320,     32'h00001234,       32'h00001234,     32'h00001234 ); // 32767 * 610839776
      check_mem_results( 18, 18, 32'h00007fff, 32'h00007fff, 32'h3fff0001,     32'h00000000,       32'h00000000,     32'h00000000 ); // 32767 * 32767
      check_mem_results( 18, 19, 32'h00007fff, 32'hffff8000, 32'hc0008000,     32'hffffffff,       32'h00007ffe,     32'h00007ffe ); // 32767 * -32768
      check_mem_results( 18, 20, 32'h00007fff, 32'h01010101, 32'h7f7f7eff,     32'h00000080,       32'h00000080,     32'h00000080 ); // 32767 * 16843009
      check_mem_results( 18, 21, 32'h00007fff, 32'hf0f0f0f0, 32'h87870f10,     32'hfffff878,       32'h00007877,     32'h00007877 ); // 32767 * -252645136
      check_mem_results( 18, 22, 32'h00007fff, 32'hdeadbeef, 32'h00c9c111,     32'hffffef57,       32'h00006f56,     32'h00006f56 ); // 32767 * -559038737
      check_mem_results( 18, 23, 32'h00007fff, 32'hcafebabe, 32'h92604542,     32'hffffe57f,       32'h0000657e,     32'h0000657e ); // 32767 * -889275714

      check_mem_results( 19,  0, 32'hffff8000, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -32768 * 0
      check_mem_results( 19,  1, 32'hffff8000, 32'h00000001, 32'hffff8000,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -32768 * 1
      check_mem_results( 19,  2, 32'hffff8000, 32'hffffffff, 32'h00008000,     32'h00000000,       32'hffff8000,     32'hffff7fff ); // -32768 * -1
      check_mem_results( 19,  3, 32'hffff8000, 32'h00000002, 32'hffff0000,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -32768 * 2
      check_mem_results( 19,  4, 32'hffff8000, 32'hfffffffe, 32'h00010000,     32'h00000000,       32'hffff8000,     32'hffff7ffe ); // -32768 * -2
      check_mem_results( 19,  5, 32'hffff8000, 32'h7fffffff, 32'h00008000,     32'hffffc000,       32'hffffc000,     32'h7fffbfff ); // -32768 * 2147483647
      check_mem_results( 19,  6, 32'hffff8000, 32'h80000000, 32'h00000000,     32'h00004000,       32'hffffc000,     32'h7fffc000 ); // -32768 * -2147483648
      check_mem_results( 19,  7, 32'hffff8000, 32'h80000001, 32'hffff8000,     32'h00003fff,       32'hffffbfff,     32'h7fffc000 ); // -32768 * -2147483647
      check_mem_results( 19,  8, 32'hffff8000, 32'h12345678, 32'hd4c40000,     32'hfffff6e5,       32'hfffff6e5,     32'h12344d5d ); // -32768 * 305419896
      check_mem_results( 19,  9, 32'hffff8000, 32'h87654321, 32'h5e6f8000,     32'h00003c4d,       32'hffffbc4d,     32'h8764ff6e ); // -32768 * -2023406815
      check_mem_results( 19, 10, 32'hffff8000, 32'h0000ffff, 32'h80008000,     32'hffffffff,       32'hffffffff,     32'h0000fffe ); // -32768 * 65535
      check_mem_results( 19, 11, 32'hffff8000, 32'hffff0000, 32'h80000000,     32'h00000000,       32'hffff8000,     32'hfffe8000 ); // -32768 * -65536
      check_mem_results( 19, 12, 32'hffff8000, 32'h40000000, 32'h00000000,     32'hffffe000,       32'hffffe000,     32'h3fffe000 ); // -32768 * 1073741824
      check_mem_results( 19, 13, 32'hffff8000, 32'hc0000000, 32'h00000000,     32'h00002000,       32'hffffa000,     32'hbfffa000 ); // -32768 * -1073741824
      check_mem_results( 19, 14, 32'hffff8000, 32'h7f7f7f7f, 32'h40408000,     32'hffffc040,       32'hffffc040,     32'h7f7f3fbf ); // -32768 * 2139062143
      check_mem_results( 19, 15, 32'hffff8000, 32'h80808080, 32'hbfc00000,     32'h00003fbf,       32'hffffbfbf,     32'h8080403f ); // -32768 * -2139062144
      check_mem_results( 19, 16, 32'hffff8000, 32'h13579bdf, 32'h32108000,     32'hfffff654,       32'hfffff654,     32'h13579233 ); // -32768 * 324508639
      check_mem_results( 19, 17, 32'hffff8000, 32'h2468ace0, 32'ha9900000,     32'hffffedcb,       32'hffffedcb,     32'h24689aab ); // -32768 * 610839776
      check_mem_results( 19, 18, 32'hffff8000, 32'h00007fff, 32'hc0008000,     32'hffffffff,       32'hffffffff,     32'h00007ffe ); // -32768 * 32767
      check_mem_results( 19, 19, 32'hffff8000, 32'hffff8000, 32'h40000000,     32'h00000000,       32'hffff8000,     32'hffff0000 ); // -32768 * -32768
      check_mem_results( 19, 20, 32'hffff8000, 32'h01010101, 32'h7f7f8000,     32'hffffff7f,       32'hffffff7f,     32'h01010080 ); // -32768 * 16843009
      check_mem_results( 19, 21, 32'hffff8000, 32'hf0f0f0f0, 32'h87880000,     32'h00000787,       32'hffff8787,     32'hf0f07877 ); // -32768 * -252645136
      check_mem_results( 19, 22, 32'hffff8000, 32'hdeadbeef, 32'h20888000,     32'h000010a9,       32'hffff90a9,     32'hdead4f98 ); // -32768 * -559038737
      check_mem_results( 19, 23, 32'hffff8000, 32'hcafebabe, 32'ha2a10000,     32'h00001a80,       32'hffff9a80,     32'hcafe553e ); // -32768 * -889275714

      check_mem_results( 20,  0, 32'h01010101, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // 16843009 * 0
      check_mem_results( 20,  1, 32'h01010101, 32'h00000001, 32'h01010101,     32'h00000000,       32'h00000000,     32'h00000000 ); // 16843009 * 1
      check_mem_results( 20,  2, 32'h01010101, 32'hffffffff, 32'hfefefeff,     32'hffffffff,       32'h01010100,     32'h01010100 ); // 16843009 * -1
      check_mem_results( 20,  3, 32'h01010101, 32'h00000002, 32'h02020202,     32'h00000000,       32'h00000000,     32'h00000000 ); // 16843009 * 2
      check_mem_results( 20,  4, 32'h01010101, 32'hfffffffe, 32'hfdfdfdfe,     32'hffffffff,       32'h01010100,     32'h01010100 ); // 16843009 * -2
      check_mem_results( 20,  5, 32'h01010101, 32'h7fffffff, 32'h7efefeff,     32'h00808080,       32'h00808080,     32'h00808080 ); // 16843009 * 2147483647
      check_mem_results( 20,  6, 32'h01010101, 32'h80000000, 32'h80000000,     32'hff7f7f7f,       32'h00808080,     32'h00808080 ); // 16843009 * -2147483648
      check_mem_results( 20,  7, 32'h01010101, 32'h80000001, 32'h81010101,     32'hff7f7f7f,       32'h00808080,     32'h00808080 ); // 16843009 * -2147483647
      check_mem_results( 20,  8, 32'h01010101, 32'h12345678, 32'h1502ce78,     32'h0012469d,       32'h0012469d,     32'h0012469d ); // 16843009 * 305419896
      check_mem_results( 20,  9, 32'h01010101, 32'h87654321, 32'h50c96421,     32'hff86ec2f,       32'h0087ed30,     32'h0087ed30 ); // 16843009 * -2023406815
      check_mem_results( 20, 10, 32'h01010101, 32'h0000ffff, 32'hfffffeff,     32'h00000100,       32'h00000100,     32'h00000100 ); // 16843009 * 65535
      check_mem_results( 20, 11, 32'h01010101, 32'hffff0000, 32'hfeff0000,     32'hfffffefe,       32'h0100ffff,     32'h0100ffff ); // 16843009 * -65536
      check_mem_results( 20, 12, 32'h01010101, 32'h40000000, 32'h40000000,     32'h00404040,       32'h00404040,     32'h00404040 ); // 16843009 * 1073741824
      check_mem_results( 20, 13, 32'h01010101, 32'hc0000000, 32'hc0000000,     32'hffbfbfbf,       32'h00c0c0c0,     32'h00c0c0c0 ); // 16843009 * -1073741824
      check_mem_results( 20, 14, 32'h01010101, 32'h7f7f7f7f, 32'hfd7dfe7f,     32'h007fff7e,       32'h007fff7e,     32'h007fff7e ); // 16843009 * 2139062143
      check_mem_results( 20, 15, 32'h01010101, 32'h80808080, 32'h01810080,     32'hff800081,       32'h00810182,     32'h00810182 ); // 16843009 * -2139062144
      check_mem_results( 20, 16, 32'h01010101, 32'h13579bdf, 32'he5d27adf,     32'h00136b06,       32'h00136b06,     32'h00136b06 ); // 16843009 * 324508639
      check_mem_results( 20, 17, 32'h01010101, 32'h2468ace0, 32'h19f58ce0,     32'h00248d3a,       32'h00248d3a,     32'h00248d3a ); // 16843009 * 610839776
      check_mem_results( 20, 18, 32'h01010101, 32'h00007fff, 32'h7f7f7eff,     32'h00000080,       32'h00000080,     32'h00000080 ); // 16843009 * 32767
      check_mem_results( 20, 19, 32'h01010101, 32'hffff8000, 32'h7f7f8000,     32'hffffff7f,       32'h01010080,     32'h01010080 ); // 16843009 * -32768
      check_mem_results( 20, 20, 32'h01010101, 32'h01010101, 32'h04030201,     32'h00010203,       32'h00010203,     32'h00010203 ); // 16843009 * 16843009
      check_mem_results( 20, 21, 32'h01010101, 32'hf0f0f0f0, 32'hc2d1e0f0,     32'hfff0e1d2,       32'h00f1e2d3,     32'h00f1e2d3 ); // 16843009 * -252645136
      check_mem_results( 20, 22, 32'h01010101, 32'hdeadbeef, 32'h3a5badef,     32'hffde8c4b,       32'h00df8d4c,     32'h00df8d4c ); // 16843009 * -559038737
      check_mem_results( 20, 23, 32'h01010101, 32'hcafebabe, 32'h427778be,     32'hffcac984,       32'h00cbca85,     32'h00cbca85 ); // 16843009 * -889275714

      check_mem_results( 21,  0, 32'hf0f0f0f0, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -252645136 * 0
      check_mem_results( 21,  1, 32'hf0f0f0f0, 32'h00000001, 32'hf0f0f0f0,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -252645136 * 1
      check_mem_results( 21,  2, 32'hf0f0f0f0, 32'hffffffff, 32'h0f0f0f10,     32'h00000000,       32'hf0f0f0f0,     32'hf0f0f0ef ); // -252645136 * -1
      check_mem_results( 21,  3, 32'hf0f0f0f0, 32'h00000002, 32'he1e1e1e0,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -252645136 * 2
      check_mem_results( 21,  4, 32'hf0f0f0f0, 32'hfffffffe, 32'h1e1e1e20,     32'h00000000,       32'hf0f0f0f0,     32'hf0f0f0ee ); // -252645136 * -2
      check_mem_results( 21,  5, 32'hf0f0f0f0, 32'h7fffffff, 32'h0f0f0f10,     32'hf8787878,       32'hf8787878,     32'h78787877 ); // -252645136 * 2147483647
      check_mem_results( 21,  6, 32'hf0f0f0f0, 32'h80000000, 32'h00000000,     32'h07878788,       32'hf8787878,     32'h78787878 ); // -252645136 * -2147483648
      check_mem_results( 21,  7, 32'hf0f0f0f0, 32'h80000001, 32'hf0f0f0f0,     32'h07878787,       32'hf8787877,     32'h78787878 ); // -252645136 * -2147483647
      check_mem_results( 21,  8, 32'hf0f0f0f0, 32'h12345678, 32'hb2a19080,     32'hfeeddccb,       32'hfeeddccb,     32'h11223343 ); // -252645136 * 305419896
      check_mem_results( 21,  9, 32'hf0f0f0f0, 32'h87654321, 32'hbccddef0,     32'h0718293a,       32'hf8091a2a,     32'h7f6e5d4b ); // -252645136 * -2023406815
      check_mem_results( 21, 10, 32'hf0f0f0f0, 32'h0000ffff, 32'hffff0f10,     32'hfffff0f0,       32'hfffff0f0,     32'h0000f0ef ); // -252645136 * 65535
      check_mem_results( 21, 11, 32'hf0f0f0f0, 32'hffff0000, 32'h0f100000,     32'h00000f0f,       32'hf0f0ffff,     32'hf0efffff ); // -252645136 * -65536
      check_mem_results( 21, 12, 32'hf0f0f0f0, 32'h40000000, 32'h00000000,     32'hfc3c3c3c,       32'hfc3c3c3c,     32'h3c3c3c3c ); // -252645136 * 1073741824
      check_mem_results( 21, 13, 32'hf0f0f0f0, 32'hc0000000, 32'h00000000,     32'h03c3c3c4,       32'hf4b4b4b4,     32'hb4b4b4b4 ); // -252645136 * -1073741824
      check_mem_results( 21, 14, 32'hf0f0f0f0, 32'h7f7f7f7f, 32'ha61e9710,     32'hf880078e,       32'hf880078e,     32'h77ff870d ); // -252645136 * 2139062143
      check_mem_results( 21, 15, 32'hf0f0f0f0, 32'h80808080, 32'h68f07800,     32'h077ff871,       32'hf870e961,     32'h78f169e1 ); // -252645136 * -2139062144
      check_mem_results( 21, 16, 32'hf0f0f0f0, 32'h13579bdf, 32'h75533110,     32'hfedcba98,       32'hfedcba98,     32'h12345677 ); // -252645136 * 324508639
      check_mem_results( 21, 17, 32'hf0f0f0f0, 32'h2468ace0, 32'h56341200,     32'hfddbb998,       32'hfddbb998,     32'h22446678 ); // -252645136 * 610839776
      check_mem_results( 21, 18, 32'hf0f0f0f0, 32'h00007fff, 32'h87870f10,     32'hfffff878,       32'hfffff878,     32'h00007877 ); // -252645136 * 32767
      check_mem_results( 21, 19, 32'hf0f0f0f0, 32'hffff8000, 32'h87880000,     32'h00000787,       32'hf0f0f877,     32'hf0f07877 ); // -252645136 * -32768
      check_mem_results( 21, 20, 32'hf0f0f0f0, 32'h01010101, 32'hc2d1e0f0,     32'hfff0e1d2,       32'hfff0e1d2,     32'h00f1e2d3 ); // -252645136 * 16843009
      check_mem_results( 21, 21, 32'hf0f0f0f0, 32'hf0f0f0f0, 32'ha4c2e100,     32'h00e2c4a6,       32'hf1d3b596,     32'he2c4a686 ); // -252645136 * -252645136
      check_mem_results( 21, 22, 32'hf0f0f0f0, 32'hdeadbeef, 32'hb5f31010,     32'h01f5c797,       32'hf2e6b887,     32'hd1947776 ); // -252645136 * -559038737
      check_mem_results( 21, 23, 32'hf0f0f0f0, 32'hcafebabe, 32'h50013220,     32'h031e3140,       32'hf40f2230,     32'hbf0ddcee ); // -252645136 * -889275714

      check_mem_results( 22,  0, 32'hdeadbeef, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -559038737 * 0
      check_mem_results( 22,  1, 32'hdeadbeef, 32'h00000001, 32'hdeadbeef,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -559038737 * 1
      check_mem_results( 22,  2, 32'hdeadbeef, 32'hffffffff, 32'h21524111,     32'h00000000,       32'hdeadbeef,     32'hdeadbeee ); // -559038737 * -1
      check_mem_results( 22,  3, 32'hdeadbeef, 32'h00000002, 32'hbd5b7dde,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -559038737 * 2
      check_mem_results( 22,  4, 32'hdeadbeef, 32'hfffffffe, 32'h42a48222,     32'h00000000,       32'hdeadbeef,     32'hdeadbeed ); // -559038737 * -2
      check_mem_results( 22,  5, 32'hdeadbeef, 32'h7fffffff, 32'ha1524111,     32'hef56df77,       32'hef56df77,     32'h6f56df76 ); // -559038737 * 2147483647
      check_mem_results( 22,  6, 32'hdeadbeef, 32'h80000000, 32'h80000000,     32'h10a92088,       32'hef56df77,     32'h6f56df77 ); // -559038737 * -2147483648
      check_mem_results( 22,  7, 32'hdeadbeef, 32'h80000001, 32'h5eadbeef,     32'h10a92088,       32'hef56df77,     32'h6f56df78 ); // -559038737 * -2147483647
      check_mem_results( 22,  8, 32'hdeadbeef, 32'h12345678, 32'h5621ca08,     32'hfda16776,       32'hfda16776,     32'h0fd5bdee ); // -559038737 * 305419896
      check_mem_results( 22,  9, 32'hdeadbeef, 32'h87654321, 32'h8aa929cf,     32'h0fb2b290,       32'hee60717f,     32'h75c5b4a0 ); // -559038737 * -2023406815
      check_mem_results( 22, 10, 32'hdeadbeef, 32'h0000ffff, 32'he0414111,     32'hffffdead,       32'hffffdead,     32'h0000deac ); // -559038737 * 65535
      check_mem_results( 22, 11, 32'hdeadbeef, 32'hffff0000, 32'h41110000,     32'h00002152,       32'hdeade041,     32'hdeace041 ); // -559038737 * -65536
      check_mem_results( 22, 12, 32'hdeadbeef, 32'h40000000, 32'hc0000000,     32'hf7ab6fbb,       32'hf7ab6fbb,     32'h37ab6fbb ); // -559038737 * 1073741824
      check_mem_results( 22, 13, 32'hdeadbeef, 32'hc0000000, 32'h40000000,     32'h08549044,       32'he7024f33,     32'ha7024f33 ); // -559038737 * -1073741824
      check_mem_results( 22, 14, 32'hdeadbeef, 32'h7f7f7f7f, 32'hf37b4991,     32'hef679951,       32'hef679951,     32'h6ee718d0 ); // -559038737 * 2139062143
      check_mem_results( 22, 15, 32'hdeadbeef, 32'h80808080, 32'h2dd6f780,     32'h109866ae,       32'hef46259d,     32'h6fc6a61d ); // -559038737 * -2139062144
      check_mem_results( 22, 16, 32'hdeadbeef, 32'h13579bdf, 32'hcc2d0731,     32'hfd7b7ded,       32'hfd7b7ded,     32'h10d319cc ); // -559038737 * 324508639
      check_mem_results( 22, 17, 32'hdeadbeef, 32'h2468ace0, 32'hc167a520,     32'hfb42ceee,       32'hfb42ceee,     32'h1fab7bce ); // -559038737 * 610839776
      check_mem_results( 22, 18, 32'hdeadbeef, 32'h00007fff, 32'h00c9c111,     32'hffffef57,       32'hffffef57,     32'h00006f56 ); // -559038737 * 32767
      check_mem_results( 22, 19, 32'hdeadbeef, 32'hffff8000, 32'h20888000,     32'h000010a9,       32'hdeadcf98,     32'hdead4f98 ); // -559038737 * -32768
      check_mem_results( 22, 20, 32'hdeadbeef, 32'h01010101, 32'h3a5badef,     32'hffde8c4b,       32'hffde8c4b,     32'h00df8d4c ); // -559038737 * 16843009
      check_mem_results( 22, 21, 32'hdeadbeef, 32'hf0f0f0f0, 32'hb5f31010,     32'h01f5c797,       32'he0a38686,     32'hd1947776 ); // -559038737 * -252645136
      check_mem_results( 22, 22, 32'hdeadbeef, 32'hdeadbeef, 32'h216da321,     32'h04564f34,       32'he3040e23,     32'hc1b1cd12 ); // -559038737 * -559038737
      check_mem_results( 22, 23, 32'hdeadbeef, 32'hcafebabe, 32'h88cf5b62,     32'h06e631ce,       32'he593f0bd,     32'hb092ab7b ); // -559038737 * -889275714

      check_mem_results( 23,  0, 32'hcafebabe, 32'h00000000, 32'h00000000,     32'h00000000,       32'h00000000,     32'h00000000 ); // -889275714 * 0
      check_mem_results( 23,  1, 32'hcafebabe, 32'h00000001, 32'hcafebabe,     32'hffffffff,       32'hffffffff,     32'h00000000 ); // -889275714 * 1
      check_mem_results( 23,  2, 32'hcafebabe, 32'hffffffff, 32'h35014542,     32'h00000000,       32'hcafebabe,     32'hcafebabd ); // -889275714 * -1
      check_mem_results( 23,  3, 32'hcafebabe, 32'h00000002, 32'h95fd757c,     32'hffffffff,       32'hffffffff,     32'h00000001 ); // -889275714 * 2
      check_mem_results( 23,  4, 32'hcafebabe, 32'hfffffffe, 32'h6a028a84,     32'h00000000,       32'hcafebabe,     32'hcafebabc ); // -889275714 * -2
      check_mem_results( 23,  5, 32'hcafebabe, 32'h7fffffff, 32'h35014542,     32'he57f5d5f,       32'he57f5d5f,     32'h657f5d5e ); // -889275714 * 2147483647
      check_mem_results( 23,  6, 32'hcafebabe, 32'h80000000, 32'h00000000,     32'h1a80a2a1,       32'he57f5d5f,     32'h657f5d5f ); // -889275714 * -2147483648
      check_mem_results( 23,  7, 32'hcafebabe, 32'h80000001, 32'hcafebabe,     32'h1a80a2a0,       32'he57f5d5e,     32'h657f5d5f ); // -889275714 * -2147483647
      check_mem_results( 23,  8, 32'hcafebabe, 32'h12345678, 32'h04bb5d10,     32'hfc3b12f8,       32'hfc3b12f8,     32'h0e6f6970 ); // -889275714 * 305419896
      check_mem_results( 23,  9, 32'hcafebabe, 32'h87654321, 32'hb4abcc7e,     32'h18f8a255,       32'he3f75d13,     32'h6b5ca034 ); // -889275714 * -2023406815
      check_mem_results( 23, 10, 32'hcafebabe, 32'h0000ffff, 32'hefbf4542,     32'hffffcafe,       32'hffffcafe,     32'h0000cafd ); // -889275714 * 65535
      check_mem_results( 23, 11, 32'hcafebabe, 32'hffff0000, 32'h45420000,     32'h00003501,       32'hcafeefbf,     32'hcafdefbf ); // -889275714 * -65536
      check_mem_results( 23, 12, 32'hcafebabe, 32'h40000000, 32'h80000000,     32'hf2bfaeaf,       32'hf2bfaeaf,     32'h32bfaeaf ); // -889275714 * 1073741824
      check_mem_results( 23, 13, 32'hcafebabe, 32'hc0000000, 32'h80000000,     32'h0d405150,       32'hd83f0c0e,     32'h983f0c0e ); // -889275714 * -1073741824
      check_mem_results( 23, 14, 32'hcafebabe, 32'h7f7f7f7f, 32'hf944e642,     32'he599f89c,       32'he599f89c,     32'h6519781b ); // -889275714 * 2139062143
      check_mem_results( 23, 15, 32'hcafebabe, 32'h80808080, 32'h3bbc5f00,     32'h1a660763,       32'he564c221,     32'h65e542a1 ); // -889275714 * -2139062144
      check_mem_results( 23, 16, 32'hcafebabe, 32'h13579bdf, 32'h9f87b582,     32'hfbfec427,       32'hfbfec427,     32'h0f566006 ); // -889275714 * 324508639
      check_mem_results( 23, 17, 32'hcafebabe, 32'h2468ace0, 32'h598b0e40,     32'hf87625f3,       32'hf87625f3,     32'h1cded2d3 ); // -889275714 * 610839776
      check_mem_results( 23, 18, 32'hcafebabe, 32'h00007fff, 32'h92604542,     32'hffffe57f,       32'hffffe57f,     32'h0000657e ); // -889275714 * 32767
      check_mem_results( 23, 19, 32'hcafebabe, 32'hffff8000, 32'ha2a10000,     32'h00001a80,       32'hcafed53e,     32'hcafe553e ); // -889275714 * -32768
      check_mem_results( 23, 20, 32'hcafebabe, 32'h01010101, 32'h427778be,     32'hffcac984,       32'hffcac984,     32'h00cbca85 ); // -889275714 * 16843009
      check_mem_results( 23, 21, 32'hcafebabe, 32'hf0f0f0f0, 32'h50013220,     32'h031e3140,       32'hce1cebfe,     32'hbf0ddcee ); // -889275714 * -252645136
      check_mem_results( 23, 22, 32'hcafebabe, 32'hdeadbeef, 32'h88cf5b62,     32'h06e631ce,       32'hd1e4ec8c,     32'hb092ab7b ); // -889275714 * -559038737
      check_mem_results( 23, 23, 32'hcafebabe, 32'hcafebabe, 32'hf140a504,     32'h0af986ae,       32'hd5f8416c,     32'ha0f6fc2a ); // -889275714 * -889275714

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

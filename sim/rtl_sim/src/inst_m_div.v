//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_m_div
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DIV/DIVU/REM/REMU
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
   input integer exp_dividend;
   input integer exp_divisor;
   input integer exp_result_div;
   input integer exp_result_divu;
   input integer exp_result_rem;
   input integer exp_result_remu;

   integer mem_dividend;
   integer mem_divisor;
   integer mem_result_div;
   integer mem_result_divu;
   integer mem_result_rem;
   integer mem_result_remu;
   integer error_before;
   begin
	 	mem_dividend    = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 0];
	 	mem_divisor     = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 1];
	 	mem_result_div  = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 2];
	 	mem_result_divu = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 3];
	 	mem_result_rem  = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 4];
	 	mem_result_remu = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[6*(24*i+j) + 5];
		error_before    = error;
		$display("========== i=%0d j=%0d ==========",i, j);
    	$display("Expected --> %h/%h -- DIV=%h DIVU=%h REM=%h REMU=%h", exp_dividend, exp_divisor, exp_result_div, exp_result_divu, exp_result_rem, exp_result_remu);
    	$display("Got      --> %h/%h -- DIV=%h DIVU=%h REM=%h REMU=%h", mem_dividend, mem_divisor, mem_result_div, mem_result_divu, mem_result_rem, mem_result_remu);
		if ((exp_dividend!==mem_dividend) || (exp_divisor!==mem_divisor)) begin
			$display("                                                                                            ERROR: Dividend and Divisor not matching. Issue in testbench.");
			error = error+1;
		end
		if (exp_result_div!==mem_result_div) begin
			$display("                                                                                            ERROR: wrong DIV  result");
			error = error+1;
		end
		if (exp_result_divu!==mem_result_divu) begin
			$display("                                                                                            ERROR: wrong DIVU result");
			error = error+1;
		end
		if (exp_result_rem!==mem_result_rem) begin
			$display("                                                                                            ERROR: wrong REM  result");
			error = error+1;
		end
		if (exp_result_remu!==mem_result_remu) begin
			$display("                                                                                            ERROR: wrong REMU result");
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
      $display("|      CHECK MEMORY VALUES AFTER THE DIV/DIVU/REM/REMU                           |");
      $display(" ================================================================================");


	  //                  i, j,   dividend,      divisor,         DIV,         DIVU,         REM,         REMU
      check_mem_results(  0, 0, 32'h00000000, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000 ); // 0/0                      ,         -1, 4294967295,          0,          0
      check_mem_results(  0, 1, 32'h00000000, 32'h00000001, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/1                      ,          0,          0,          0,          0
      check_mem_results(  0, 2, 32'h00000000, 32'hffffffff, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-1                     ,          0,          0,          0,          0
      check_mem_results(  0, 3, 32'h00000000, 32'h00000002, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/2                      ,          0,          0,          0,          0
      check_mem_results(  0, 4, 32'h00000000, 32'hfffffffe, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-2                     ,          0,          0,          0,          0
      check_mem_results(  0, 5, 32'h00000000, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/2147483647             ,          0,          0,          0,          0
      check_mem_results(  0, 6, 32'h00000000, 32'h80000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-2147483648            ,          0,          0,          0,          0
      check_mem_results(  0, 7, 32'h00000000, 32'h80000001, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-2147483647            ,          0,          0,          0,          0
      check_mem_results(  0, 8, 32'h00000000, 32'h12345678, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/305419896              ,          0,          0,          0,          0
      check_mem_results(  0, 9, 32'h00000000, 32'h87654321, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-2023406815            ,          0,          0,          0,          0
      check_mem_results(  0,10, 32'h00000000, 32'h0000ffff, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/65535                  ,          0,          0,          0,          0
      check_mem_results(  0,11, 32'h00000000, 32'hffff0000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-65536                 ,          0,          0,          0,          0
      check_mem_results(  0,12, 32'h00000000, 32'h40000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/1073741824             ,          0,          0,          0,          0
      check_mem_results(  0,13, 32'h00000000, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-1073741824            ,          0,          0,          0,          0
      check_mem_results(  0,14, 32'h00000000, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/2139062143             ,          0,          0,          0,          0
      check_mem_results(  0,15, 32'h00000000, 32'h80808080, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-2139062144            ,          0,          0,          0,          0
      check_mem_results(  0,16, 32'h00000000, 32'h13579bdf, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/324508639              ,          0,          0,          0,          0
      check_mem_results(  0,17, 32'h00000000, 32'h2468ace0, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/610839776              ,          0,          0,          0,          0
      check_mem_results(  0,18, 32'h00000000, 32'h00007fff, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/32767                  ,          0,          0,          0,          0
      check_mem_results(  0,19, 32'h00000000, 32'hffff8000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-32768                 ,          0,          0,          0,          0
      check_mem_results(  0,20, 32'h00000000, 32'h01010101, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/16843009               ,          0,          0,          0,          0
      check_mem_results(  0,21, 32'h00000000, 32'hf0f0f0f0, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-252645136             ,          0,          0,          0,          0
      check_mem_results(  0,22, 32'h00000000, 32'hdeadbeef, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-559038737             ,          0,          0,          0,          0
      check_mem_results(  0,23, 32'h00000000, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000 ); // 0/-889275714             ,          0,          0,          0,          0

      check_mem_results(  1, 0, 32'h00000001, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h00000001, 32'h00000001 ); // 1/0                      ,         -1, 4294967295,          1,          1
      check_mem_results(  1, 1, 32'h00000001, 32'h00000001, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 1/1                      ,          1,          1,          0,          0
      check_mem_results(  1, 2, 32'h00000001, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000, 32'h00000001 ); // 1/-1                     ,         -1,          0,          0,          1
      check_mem_results(  1, 3, 32'h00000001, 32'h00000002, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/2                      ,          0,          0,          1,          1
      check_mem_results(  1, 4, 32'h00000001, 32'hfffffffe, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-2                     ,          0,          0,          1,          1
      check_mem_results(  1, 5, 32'h00000001, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/2147483647             ,          0,          0,          1,          1
      check_mem_results(  1, 6, 32'h00000001, 32'h80000000, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-2147483648            ,          0,          0,          1,          1
      check_mem_results(  1, 7, 32'h00000001, 32'h80000001, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-2147483647            ,          0,          0,          1,          1
      check_mem_results(  1, 8, 32'h00000001, 32'h12345678, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/305419896              ,          0,          0,          1,          1
      check_mem_results(  1, 9, 32'h00000001, 32'h87654321, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-2023406815            ,          0,          0,          1,          1
      check_mem_results(  1,10, 32'h00000001, 32'h0000ffff, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/65535                  ,          0,          0,          1,          1
      check_mem_results(  1,11, 32'h00000001, 32'hffff0000, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-65536                 ,          0,          0,          1,          1
      check_mem_results(  1,12, 32'h00000001, 32'h40000000, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/1073741824             ,          0,          0,          1,          1
      check_mem_results(  1,13, 32'h00000001, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-1073741824            ,          0,          0,          1,          1
      check_mem_results(  1,14, 32'h00000001, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/2139062143             ,          0,          0,          1,          1
      check_mem_results(  1,15, 32'h00000001, 32'h80808080, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-2139062144            ,          0,          0,          1,          1
      check_mem_results(  1,16, 32'h00000001, 32'h13579bdf, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/324508639              ,          0,          0,          1,          1
      check_mem_results(  1,17, 32'h00000001, 32'h2468ace0, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/610839776              ,          0,          0,          1,          1
      check_mem_results(  1,18, 32'h00000001, 32'h00007fff, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/32767                  ,          0,          0,          1,          1
      check_mem_results(  1,19, 32'h00000001, 32'hffff8000, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-32768                 ,          0,          0,          1,          1
      check_mem_results(  1,20, 32'h00000001, 32'h01010101, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/16843009               ,          0,          0,          1,          1
      check_mem_results(  1,21, 32'h00000001, 32'hf0f0f0f0, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-252645136             ,          0,          0,          1,          1
      check_mem_results(  1,22, 32'h00000001, 32'hdeadbeef, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-559038737             ,          0,          0,          1,          1
      check_mem_results(  1,23, 32'h00000001, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h00000001, 32'h00000001 ); // 1/-889275714             ,          0,          0,          1,          1

      check_mem_results(  2, 0, 32'hffffffff, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'hffffffff ); // -1/0                     ,         -1, 4294967295,         -1, 4294967295
      check_mem_results(  2, 1, 32'hffffffff, 32'h00000001, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000 ); // -1/1                     ,         -1, 4294967295,          0,          0
      check_mem_results(  2, 2, 32'hffffffff, 32'hffffffff, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -1/-1                    ,          1,          1,          0,          0
      check_mem_results(  2, 3, 32'hffffffff, 32'h00000002, 32'h00000000, 32'h7fffffff, 32'hffffffff, 32'h00000001 ); // -1/2                     ,          0, 2147483647,         -1,          1
      check_mem_results(  2, 4, 32'hffffffff, 32'hfffffffe, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h00000001 ); // -1/-2                    ,          0,          1,         -1,          1
      check_mem_results(  2, 5, 32'hffffffff, 32'h7fffffff, 32'h00000000, 32'h00000002, 32'hffffffff, 32'h00000001 ); // -1/2147483647            ,          0,          2,         -1,          1
      check_mem_results(  2, 6, 32'hffffffff, 32'h80000000, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h7fffffff ); // -1/-2147483648           ,          0,          1,         -1, 2147483647
      check_mem_results(  2, 7, 32'hffffffff, 32'h80000001, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h7ffffffe ); // -1/-2147483647           ,          0,          1,         -1, 2147483646
      check_mem_results(  2, 8, 32'hffffffff, 32'h12345678, 32'h00000000, 32'h0000000e, 32'hffffffff, 32'h0123456f ); // -1/305419896             ,          0,         14,         -1,   19088751
      check_mem_results(  2, 9, 32'hffffffff, 32'h87654321, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h789abcde ); // -1/-2023406815           ,          0,          1,         -1, 2023406814
      check_mem_results(  2,10, 32'hffffffff, 32'h0000ffff, 32'h00000000, 32'h00010001, 32'hffffffff, 32'h00000000 ); // -1/65535                 ,          0,      65537,         -1,          0
      check_mem_results(  2,11, 32'hffffffff, 32'hffff0000, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h0000ffff ); // -1/-65536                ,          0,          1,         -1,      65535
      check_mem_results(  2,12, 32'hffffffff, 32'h40000000, 32'h00000000, 32'h00000003, 32'hffffffff, 32'h3fffffff ); // -1/1073741824            ,          0,          3,         -1, 1073741823
      check_mem_results(  2,13, 32'hffffffff, 32'hc0000000, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h3fffffff ); // -1/-1073741824           ,          0,          1,         -1, 1073741823
      check_mem_results(  2,14, 32'hffffffff, 32'h7f7f7f7f, 32'h00000000, 32'h00000002, 32'hffffffff, 32'h01010101 ); // -1/2139062143            ,          0,          2,         -1,   16843009
      check_mem_results(  2,15, 32'hffffffff, 32'h80808080, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h7f7f7f7f ); // -1/-2139062144           ,          0,          1,         -1, 2139062143
      check_mem_results(  2,16, 32'hffffffff, 32'h13579bdf, 32'h00000000, 32'h0000000d, 32'hffffffff, 32'h048d15ac ); // -1/324508639             ,          0,         13,         -1,   76354988
      check_mem_results(  2,17, 32'hffffffff, 32'h2468ace0, 32'h00000000, 32'h00000007, 32'hffffffff, 32'h012345df ); // -1/610839776             ,          0,          7,         -1,   19088863
      check_mem_results(  2,18, 32'hffffffff, 32'h00007fff, 32'h00000000, 32'h00020004, 32'hffffffff, 32'h00000003 ); // -1/32767                 ,          0,     131076,         -1,          3
      check_mem_results(  2,19, 32'hffffffff, 32'hffff8000, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h00007fff ); // -1/-32768                ,          0,          1,         -1,      32767
      check_mem_results(  2,20, 32'hffffffff, 32'h01010101, 32'h00000000, 32'h000000ff, 32'hffffffff, 32'h00000000 ); // -1/16843009              ,          0,        255,         -1,          0
      check_mem_results(  2,21, 32'hffffffff, 32'hf0f0f0f0, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h0f0f0f0f ); // -1/-252645136            ,          0,          1,         -1,  252645135
      check_mem_results(  2,22, 32'hffffffff, 32'hdeadbeef, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h21524110 ); // -1/-559038737            ,          0,          1,         -1,  559038736
      check_mem_results(  2,23, 32'hffffffff, 32'hcafebabe, 32'h00000000, 32'h00000001, 32'hffffffff, 32'h35014541 ); // -1/-889275714            ,          0,          1,         -1,  889275713

      check_mem_results(  3, 0, 32'h00000002, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h00000002, 32'h00000002 ); // 2/0                      ,         -1, 4294967295,          2,          2
      check_mem_results(  3, 1, 32'h00000002, 32'h00000001, 32'h00000002, 32'h00000002, 32'h00000000, 32'h00000000 ); // 2/1                      ,          2,          2,          0,          0
      check_mem_results(  3, 2, 32'h00000002, 32'hffffffff, 32'hfffffffe, 32'h00000000, 32'h00000000, 32'h00000002 ); // 2/-1                     ,         -2,          0,          0,          2
      check_mem_results(  3, 3, 32'h00000002, 32'h00000002, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 2/2                      ,          1,          1,          0,          0
      check_mem_results(  3, 4, 32'h00000002, 32'hfffffffe, 32'hffffffff, 32'h00000000, 32'h00000000, 32'h00000002 ); // 2/-2                     ,         -1,          0,          0,          2
      check_mem_results(  3, 5, 32'h00000002, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/2147483647             ,          0,          0,          2,          2
      check_mem_results(  3, 6, 32'h00000002, 32'h80000000, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-2147483648            ,          0,          0,          2,          2
      check_mem_results(  3, 7, 32'h00000002, 32'h80000001, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-2147483647            ,          0,          0,          2,          2
      check_mem_results(  3, 8, 32'h00000002, 32'h12345678, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/305419896              ,          0,          0,          2,          2
      check_mem_results(  3, 9, 32'h00000002, 32'h87654321, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-2023406815            ,          0,          0,          2,          2
      check_mem_results(  3,10, 32'h00000002, 32'h0000ffff, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/65535                  ,          0,          0,          2,          2
      check_mem_results(  3,11, 32'h00000002, 32'hffff0000, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-65536                 ,          0,          0,          2,          2
      check_mem_results(  3,12, 32'h00000002, 32'h40000000, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/1073741824             ,          0,          0,          2,          2
      check_mem_results(  3,13, 32'h00000002, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-1073741824            ,          0,          0,          2,          2
      check_mem_results(  3,14, 32'h00000002, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/2139062143             ,          0,          0,          2,          2
      check_mem_results(  3,15, 32'h00000002, 32'h80808080, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-2139062144            ,          0,          0,          2,          2
      check_mem_results(  3,16, 32'h00000002, 32'h13579bdf, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/324508639              ,          0,          0,          2,          2
      check_mem_results(  3,17, 32'h00000002, 32'h2468ace0, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/610839776              ,          0,          0,          2,          2
      check_mem_results(  3,18, 32'h00000002, 32'h00007fff, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/32767                  ,          0,          0,          2,          2
      check_mem_results(  3,19, 32'h00000002, 32'hffff8000, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-32768                 ,          0,          0,          2,          2
      check_mem_results(  3,20, 32'h00000002, 32'h01010101, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/16843009               ,          0,          0,          2,          2
      check_mem_results(  3,21, 32'h00000002, 32'hf0f0f0f0, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-252645136             ,          0,          0,          2,          2
      check_mem_results(  3,22, 32'h00000002, 32'hdeadbeef, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-559038737             ,          0,          0,          2,          2
      check_mem_results(  3,23, 32'h00000002, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h00000002, 32'h00000002 ); // 2/-889275714             ,          0,          0,          2,          2

      check_mem_results(  4, 0, 32'hfffffffe, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'hfffffffe, 32'hfffffffe ); // -2/0                     ,         -1, 4294967295,         -2, 4294967294
      check_mem_results(  4, 1, 32'hfffffffe, 32'h00000001, 32'hfffffffe, 32'hfffffffe, 32'h00000000, 32'h00000000 ); // -2/1                     ,         -2, 4294967294,          0,          0
      check_mem_results(  4, 2, 32'hfffffffe, 32'hffffffff, 32'h00000002, 32'h00000000, 32'h00000000, 32'hfffffffe ); // -2/-1                    ,          2,          0,          0, 4294967294
      check_mem_results(  4, 3, 32'hfffffffe, 32'h00000002, 32'hffffffff, 32'h7fffffff, 32'h00000000, 32'h00000000 ); // -2/2                     ,         -1, 2147483647,          0,          0
      check_mem_results(  4, 4, 32'hfffffffe, 32'hfffffffe, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -2/-2                    ,          1,          1,          0,          0
      check_mem_results(  4, 5, 32'hfffffffe, 32'h7fffffff, 32'h00000000, 32'h00000002, 32'hfffffffe, 32'h00000000 ); // -2/2147483647            ,          0,          2,         -2,          0
      check_mem_results(  4, 6, 32'hfffffffe, 32'h80000000, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h7ffffffe ); // -2/-2147483648           ,          0,          1,         -2, 2147483646
      check_mem_results(  4, 7, 32'hfffffffe, 32'h80000001, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h7ffffffd ); // -2/-2147483647           ,          0,          1,         -2, 2147483645
      check_mem_results(  4, 8, 32'hfffffffe, 32'h12345678, 32'h00000000, 32'h0000000e, 32'hfffffffe, 32'h0123456e ); // -2/305419896             ,          0,         14,         -2,   19088750
      check_mem_results(  4, 9, 32'hfffffffe, 32'h87654321, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h789abcdd ); // -2/-2023406815           ,          0,          1,         -2, 2023406813
      check_mem_results(  4,10, 32'hfffffffe, 32'h0000ffff, 32'h00000000, 32'h00010000, 32'hfffffffe, 32'h0000fffe ); // -2/65535                 ,          0,      65536,         -2,      65534
      check_mem_results(  4,11, 32'hfffffffe, 32'hffff0000, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h0000fffe ); // -2/-65536                ,          0,          1,         -2,      65534
      check_mem_results(  4,12, 32'hfffffffe, 32'h40000000, 32'h00000000, 32'h00000003, 32'hfffffffe, 32'h3ffffffe ); // -2/1073741824            ,          0,          3,         -2, 1073741822
      check_mem_results(  4,13, 32'hfffffffe, 32'hc0000000, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h3ffffffe ); // -2/-1073741824           ,          0,          1,         -2, 1073741822
      check_mem_results(  4,14, 32'hfffffffe, 32'h7f7f7f7f, 32'h00000000, 32'h00000002, 32'hfffffffe, 32'h01010100 ); // -2/2139062143            ,          0,          2,         -2,   16843008
      check_mem_results(  4,15, 32'hfffffffe, 32'h80808080, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h7f7f7f7e ); // -2/-2139062144           ,          0,          1,         -2, 2139062142
      check_mem_results(  4,16, 32'hfffffffe, 32'h13579bdf, 32'h00000000, 32'h0000000d, 32'hfffffffe, 32'h048d15ab ); // -2/324508639             ,          0,         13,         -2,   76354987
      check_mem_results(  4,17, 32'hfffffffe, 32'h2468ace0, 32'h00000000, 32'h00000007, 32'hfffffffe, 32'h012345de ); // -2/610839776             ,          0,          7,         -2,   19088862
      check_mem_results(  4,18, 32'hfffffffe, 32'h00007fff, 32'h00000000, 32'h00020004, 32'hfffffffe, 32'h00000002 ); // -2/32767                 ,          0,     131076,         -2,          2
      check_mem_results(  4,19, 32'hfffffffe, 32'hffff8000, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h00007ffe ); // -2/-32768                ,          0,          1,         -2,      32766
      check_mem_results(  4,20, 32'hfffffffe, 32'h01010101, 32'h00000000, 32'h000000fe, 32'hfffffffe, 32'h01010100 ); // -2/16843009              ,          0,        254,         -2,   16843008
      check_mem_results(  4,21, 32'hfffffffe, 32'hf0f0f0f0, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h0f0f0f0e ); // -2/-252645136            ,          0,          1,         -2,  252645134
      check_mem_results(  4,22, 32'hfffffffe, 32'hdeadbeef, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h2152410f ); // -2/-559038737            ,          0,          1,         -2,  559038735
      check_mem_results(  4,23, 32'hfffffffe, 32'hcafebabe, 32'h00000000, 32'h00000001, 32'hfffffffe, 32'h35014540 ); // -2/-889275714            ,          0,          1,         -2,  889275712

      check_mem_results(  5, 0, 32'h7fffffff, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h7fffffff, 32'h7fffffff ); // 2147483647/0             ,         -1, 4294967295, 2147483647, 2147483647
      check_mem_results(  5, 1, 32'h7fffffff, 32'h00000001, 32'h7fffffff, 32'h7fffffff, 32'h00000000, 32'h00000000 ); // 2147483647/1             , 2147483647, 2147483647,          0,          0
      check_mem_results(  5, 2, 32'h7fffffff, 32'hffffffff, 32'h80000001, 32'h00000000, 32'h00000000, 32'h7fffffff ); // 2147483647/-1            , -2147483647,          0,          0, 2147483647
      check_mem_results(  5, 3, 32'h7fffffff, 32'h00000002, 32'h3fffffff, 32'h3fffffff, 32'h00000001, 32'h00000001 ); // 2147483647/2             , 1073741823, 1073741823,          1,          1
      check_mem_results(  5, 4, 32'h7fffffff, 32'hfffffffe, 32'hc0000001, 32'h00000000, 32'h00000001, 32'h7fffffff ); // 2147483647/-2            , -1073741823,          0,          1, 2147483647
      check_mem_results(  5, 5, 32'h7fffffff, 32'h7fffffff, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 2147483647/2147483647    ,          1,          1,          0,          0
      check_mem_results(  5, 6, 32'h7fffffff, 32'h80000000, 32'h00000000, 32'h00000000, 32'h7fffffff, 32'h7fffffff ); // 2147483647/-2147483648   ,          0,          0, 2147483647, 2147483647
      check_mem_results(  5, 7, 32'h7fffffff, 32'h80000001, 32'hffffffff, 32'h00000000, 32'h00000000, 32'h7fffffff ); // 2147483647/-2147483647   ,         -1,          0,          0, 2147483647
      check_mem_results(  5, 8, 32'h7fffffff, 32'h12345678, 32'h00000007, 32'h00000007, 32'h0091a2b7, 32'h0091a2b7 ); // 2147483647/305419896     ,          7,          7,    9544375,    9544375
      check_mem_results(  5, 9, 32'h7fffffff, 32'h87654321, 32'hffffffff, 32'h00000000, 32'h07654320, 32'h7fffffff ); // 2147483647/-2023406815   ,         -1,          0,  124076832, 2147483647
      check_mem_results(  5,10, 32'h7fffffff, 32'h0000ffff, 32'h00008000, 32'h00008000, 32'h00007fff, 32'h00007fff ); // 2147483647/65535         ,      32768,      32768,      32767,      32767
      check_mem_results(  5,11, 32'h7fffffff, 32'hffff0000, 32'hffff8001, 32'h00000000, 32'h0000ffff, 32'h7fffffff ); // 2147483647/-65536        ,     -32767,          0,      65535, 2147483647
      check_mem_results(  5,12, 32'h7fffffff, 32'h40000000, 32'h00000001, 32'h00000001, 32'h3fffffff, 32'h3fffffff ); // 2147483647/1073741824    ,          1,          1, 1073741823, 1073741823
      check_mem_results(  5,13, 32'h7fffffff, 32'hc0000000, 32'hffffffff, 32'h00000000, 32'h3fffffff, 32'h7fffffff ); // 2147483647/-1073741824   ,         -1,          0, 1073741823, 2147483647
      check_mem_results(  5,14, 32'h7fffffff, 32'h7f7f7f7f, 32'h00000001, 32'h00000001, 32'h00808080, 32'h00808080 ); // 2147483647/2139062143    ,          1,          1,    8421504,    8421504
      check_mem_results(  5,15, 32'h7fffffff, 32'h80808080, 32'hffffffff, 32'h00000000, 32'h0080807f, 32'h7fffffff ); // 2147483647/-2139062144   ,         -1,          0,    8421503, 2147483647
      check_mem_results(  5,16, 32'h7fffffff, 32'h13579bdf, 32'h00000006, 32'h00000006, 32'h0bf258c5, 32'h0bf258c5 ); // 2147483647/324508639     ,          6,          6,  200431813,  200431813
      check_mem_results(  5,17, 32'h7fffffff, 32'h2468ace0, 32'h00000003, 32'h00000003, 32'h12c5f95f, 32'h12c5f95f ); // 2147483647/610839776     ,          3,          3,  314964319,  314964319
      check_mem_results(  5,18, 32'h7fffffff, 32'h00007fff, 32'h00010002, 32'h00010002, 32'h00000001, 32'h00000001 ); // 2147483647/32767         ,      65538,      65538,          1,          1
      check_mem_results(  5,19, 32'h7fffffff, 32'hffff8000, 32'hffff0001, 32'h00000000, 32'h00007fff, 32'h7fffffff ); // 2147483647/-32768        ,     -65535,          0,      32767, 2147483647
      check_mem_results(  5,20, 32'h7fffffff, 32'h01010101, 32'h0000007f, 32'h0000007f, 32'h00808080, 32'h00808080 ); // 2147483647/16843009      ,        127,        127,    8421504,    8421504
      check_mem_results(  5,21, 32'h7fffffff, 32'hf0f0f0f0, 32'hfffffff8, 32'h00000000, 32'h0787877f, 32'h7fffffff ); // 2147483647/-252645136    ,         -8,          0,  126322559, 2147483647
      check_mem_results(  5,22, 32'h7fffffff, 32'hdeadbeef, 32'hfffffffd, 32'h00000000, 32'h1c093ccc, 32'h7fffffff ); // 2147483647/-559038737    ,         -3,          0,  470367436, 2147483647
      check_mem_results(  5,23, 32'h7fffffff, 32'hcafebabe, 32'hfffffffe, 32'h00000000, 32'h15fd757b, 32'h7fffffff ); // 2147483647/-889275714    ,         -2,          0,  368932219, 2147483647

      check_mem_results(  6, 0, 32'h80000000, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h80000000, 32'h80000000 ); // -2147483648/0            ,         -1, 4294967295, -2147483648, 2147483648
      check_mem_results(  6, 1, 32'h80000000, 32'h00000001, 32'h80000000, 32'h80000000, 32'h00000000, 32'h00000000 ); // -2147483648/1            , -2147483648, 2147483648,          0,          0
      check_mem_results(  6, 2, 32'h80000000, 32'hffffffff, 32'h80000000, 32'h00000000, 32'h00000000, 32'h80000000 ); // -2147483648/-1           , -2147483648,          0,          0, 2147483648
      check_mem_results(  6, 3, 32'h80000000, 32'h00000002, 32'hc0000000, 32'h40000000, 32'h00000000, 32'h00000000 ); // -2147483648/2            , -1073741824, 1073741824,          0,          0
      check_mem_results(  6, 4, 32'h80000000, 32'hfffffffe, 32'h40000000, 32'h00000000, 32'h00000000, 32'h80000000 ); // -2147483648/-2           , 1073741824,          0,          0, 2147483648
      check_mem_results(  6, 5, 32'h80000000, 32'h7fffffff, 32'hffffffff, 32'h00000001, 32'hffffffff, 32'h00000001 ); // -2147483648/2147483647   ,         -1,          1,         -1,          1
      check_mem_results(  6, 6, 32'h80000000, 32'h80000000, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -2147483648/-2147483648  ,          1,          1,          0,          0
      check_mem_results(  6, 7, 32'h80000000, 32'h80000001, 32'h00000001, 32'h00000000, 32'hffffffff, 32'h80000000 ); // -2147483648/-2147483647  ,          1,          0,         -1, 2147483648
      check_mem_results(  6, 8, 32'h80000000, 32'h12345678, 32'hfffffff9, 32'h00000007, 32'hff6e5d48, 32'h0091a2b8 ); // -2147483648/305419896    ,         -7,          7,   -9544376,    9544376
      check_mem_results(  6, 9, 32'h80000000, 32'h87654321, 32'h00000001, 32'h00000000, 32'hf89abcdf, 32'h80000000 ); // -2147483648/-2023406815  ,          1,          0, -124076833, 2147483648
      check_mem_results(  6,10, 32'h80000000, 32'h0000ffff, 32'hffff8000, 32'h00008000, 32'hffff8000, 32'h00008000 ); // -2147483648/65535        ,     -32768,      32768,     -32768,      32768
      check_mem_results(  6,11, 32'h80000000, 32'hffff0000, 32'h00008000, 32'h00000000, 32'h00000000, 32'h80000000 ); // -2147483648/-65536       ,      32768,          0,          0, 2147483648
      check_mem_results(  6,12, 32'h80000000, 32'h40000000, 32'hfffffffe, 32'h00000002, 32'h00000000, 32'h00000000 ); // -2147483648/1073741824   ,         -2,          2,          0,          0
      check_mem_results(  6,13, 32'h80000000, 32'hc0000000, 32'h00000002, 32'h00000000, 32'h00000000, 32'h80000000 ); // -2147483648/-1073741824  ,          2,          0,          0, 2147483648
      check_mem_results(  6,14, 32'h80000000, 32'h7f7f7f7f, 32'hffffffff, 32'h00000001, 32'hff7f7f7f, 32'h00808081 ); // -2147483648/2139062143   ,         -1,          1,   -8421505,    8421505
      check_mem_results(  6,15, 32'h80000000, 32'h80808080, 32'h00000001, 32'h00000000, 32'hff7f7f80, 32'h80000000 ); // -2147483648/-2139062144  ,          1,          0,   -8421504, 2147483648
      check_mem_results(  6,16, 32'h80000000, 32'h13579bdf, 32'hfffffffa, 32'h00000006, 32'hf40da73a, 32'h0bf258c6 ); // -2147483648/324508639    ,         -6,          6, -200431814,  200431814
      check_mem_results(  6,17, 32'h80000000, 32'h2468ace0, 32'hfffffffd, 32'h00000003, 32'hed3a06a0, 32'h12c5f960 ); // -2147483648/610839776    ,         -3,          3, -314964320,  314964320
      check_mem_results(  6,18, 32'h80000000, 32'h00007fff, 32'hfffefffe, 32'h00010002, 32'hfffffffe, 32'h00000002 ); // -2147483648/32767        ,     -65538,      65538,         -2,          2
      check_mem_results(  6,19, 32'h80000000, 32'hffff8000, 32'h00010000, 32'h00000000, 32'h00000000, 32'h80000000 ); // -2147483648/-32768       ,      65536,          0,          0, 2147483648
      check_mem_results(  6,20, 32'h80000000, 32'h01010101, 32'hffffff81, 32'h0000007f, 32'hff7f7f7f, 32'h00808081 ); // -2147483648/16843009     ,       -127,        127,   -8421505,    8421505
      check_mem_results(  6,21, 32'h80000000, 32'hf0f0f0f0, 32'h00000008, 32'h00000000, 32'hf8787880, 32'h80000000 ); // -2147483648/-252645136   ,          8,          0, -126322560, 2147483648
      check_mem_results(  6,22, 32'h80000000, 32'hdeadbeef, 32'h00000003, 32'h00000000, 32'he3f6c333, 32'h80000000 ); // -2147483648/-559038737   ,          3,          0, -470367437, 2147483648
      check_mem_results(  6,23, 32'h80000000, 32'hcafebabe, 32'h00000002, 32'h00000000, 32'hea028a84, 32'h80000000 ); // -2147483648/-889275714   ,          2,          0, -368932220, 2147483648

      check_mem_results(  7, 0, 32'h80000001, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h80000001, 32'h80000001 ); // -2147483647/0            ,         -1, 4294967295, -2147483647, 2147483649
      check_mem_results(  7, 1, 32'h80000001, 32'h00000001, 32'h80000001, 32'h80000001, 32'h00000000, 32'h00000000 ); // -2147483647/1            , -2147483647, 2147483649,          0,          0
      check_mem_results(  7, 2, 32'h80000001, 32'hffffffff, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h80000001 ); // -2147483647/-1           , 2147483647,          0,          0, 2147483649
      check_mem_results(  7, 3, 32'h80000001, 32'h00000002, 32'hc0000001, 32'h40000000, 32'hffffffff, 32'h00000001 ); // -2147483647/2            , -1073741823, 1073741824,         -1,          1
      check_mem_results(  7, 4, 32'h80000001, 32'hfffffffe, 32'h3fffffff, 32'h00000000, 32'hffffffff, 32'h80000001 ); // -2147483647/-2           , 1073741823,          0,         -1, 2147483649
      check_mem_results(  7, 5, 32'h80000001, 32'h7fffffff, 32'hffffffff, 32'h00000001, 32'h00000000, 32'h00000002 ); // -2147483647/2147483647   ,         -1,          1,          0,          2
      check_mem_results(  7, 6, 32'h80000001, 32'h80000000, 32'h00000000, 32'h00000001, 32'h80000001, 32'h00000001 ); // -2147483647/-2147483648  ,          0,          1, -2147483647,          1
      check_mem_results(  7, 7, 32'h80000001, 32'h80000001, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -2147483647/-2147483647  ,          1,          1,          0,          0
      check_mem_results(  7, 8, 32'h80000001, 32'h12345678, 32'hfffffff9, 32'h00000007, 32'hff6e5d49, 32'h0091a2b9 ); // -2147483647/305419896    ,         -7,          7,   -9544375,    9544377
      check_mem_results(  7, 9, 32'h80000001, 32'h87654321, 32'h00000001, 32'h00000000, 32'hf89abce0, 32'h80000001 ); // -2147483647/-2023406815  ,          1,          0, -124076832, 2147483649
      check_mem_results(  7,10, 32'h80000001, 32'h0000ffff, 32'hffff8000, 32'h00008000, 32'hffff8001, 32'h00008001 ); // -2147483647/65535        ,     -32768,      32768,     -32767,      32769
      check_mem_results(  7,11, 32'h80000001, 32'hffff0000, 32'h00007fff, 32'h00000000, 32'hffff0001, 32'h80000001 ); // -2147483647/-65536       ,      32767,          0,     -65535, 2147483649
      check_mem_results(  7,12, 32'h80000001, 32'h40000000, 32'hffffffff, 32'h00000002, 32'hc0000001, 32'h00000001 ); // -2147483647/1073741824   ,         -1,          2, -1073741823,          1
      check_mem_results(  7,13, 32'h80000001, 32'hc0000000, 32'h00000001, 32'h00000000, 32'hc0000001, 32'h80000001 ); // -2147483647/-1073741824  ,          1,          0, -1073741823, 2147483649
      check_mem_results(  7,14, 32'h80000001, 32'h7f7f7f7f, 32'hffffffff, 32'h00000001, 32'hff7f7f80, 32'h00808082 ); // -2147483647/2139062143   ,         -1,          1,   -8421504,    8421506
      check_mem_results(  7,15, 32'h80000001, 32'h80808080, 32'h00000001, 32'h00000000, 32'hff7f7f81, 32'h80000001 ); // -2147483647/-2139062144  ,          1,          0,   -8421503, 2147483649
      check_mem_results(  7,16, 32'h80000001, 32'h13579bdf, 32'hfffffffa, 32'h00000006, 32'hf40da73b, 32'h0bf258c7 ); // -2147483647/324508639    ,         -6,          6, -200431813,  200431815
      check_mem_results(  7,17, 32'h80000001, 32'h2468ace0, 32'hfffffffd, 32'h00000003, 32'hed3a06a1, 32'h12c5f961 ); // -2147483647/610839776    ,         -3,          3, -314964319,  314964321
      check_mem_results(  7,18, 32'h80000001, 32'h00007fff, 32'hfffefffe, 32'h00010002, 32'hffffffff, 32'h00000003 ); // -2147483647/32767        ,     -65538,      65538,         -1,          3
      check_mem_results(  7,19, 32'h80000001, 32'hffff8000, 32'h0000ffff, 32'h00000000, 32'hffff8001, 32'h80000001 ); // -2147483647/-32768       ,      65535,          0,     -32767, 2147483649
      check_mem_results(  7,20, 32'h80000001, 32'h01010101, 32'hffffff81, 32'h0000007f, 32'hff7f7f80, 32'h00808082 ); // -2147483647/16843009     ,       -127,        127,   -8421504,    8421506
      check_mem_results(  7,21, 32'h80000001, 32'hf0f0f0f0, 32'h00000008, 32'h00000000, 32'hf8787881, 32'h80000001 ); // -2147483647/-252645136   ,          8,          0, -126322559, 2147483649
      check_mem_results(  7,22, 32'h80000001, 32'hdeadbeef, 32'h00000003, 32'h00000000, 32'he3f6c334, 32'h80000001 ); // -2147483647/-559038737   ,          3,          0, -470367436, 2147483649
      check_mem_results(  7,23, 32'h80000001, 32'hcafebabe, 32'h00000002, 32'h00000000, 32'hea028a85, 32'h80000001 ); // -2147483647/-889275714   ,          2,          0, -368932219, 2147483649

      check_mem_results(  8, 0, 32'h12345678, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h12345678, 32'h12345678 ); // 305419896/0              ,         -1, 4294967295,  305419896,  305419896
      check_mem_results(  8, 1, 32'h12345678, 32'h00000001, 32'h12345678, 32'h12345678, 32'h00000000, 32'h00000000 ); // 305419896/1              ,  305419896,  305419896,          0,          0
      check_mem_results(  8, 2, 32'h12345678, 32'hffffffff, 32'hedcba988, 32'h00000000, 32'h00000000, 32'h12345678 ); // 305419896/-1             , -305419896,          0,          0,  305419896
      check_mem_results(  8, 3, 32'h12345678, 32'h00000002, 32'h091a2b3c, 32'h091a2b3c, 32'h00000000, 32'h00000000 ); // 305419896/2              ,  152709948,  152709948,          0,          0
      check_mem_results(  8, 4, 32'h12345678, 32'hfffffffe, 32'hf6e5d4c4, 32'h00000000, 32'h00000000, 32'h12345678 ); // 305419896/-2             , -152709948,          0,          0,  305419896
      check_mem_results(  8, 5, 32'h12345678, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/2147483647     ,          0,          0,  305419896,  305419896
      check_mem_results(  8, 6, 32'h12345678, 32'h80000000, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/-2147483648    ,          0,          0,  305419896,  305419896
      check_mem_results(  8, 7, 32'h12345678, 32'h80000001, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/-2147483647    ,          0,          0,  305419896,  305419896
      check_mem_results(  8, 8, 32'h12345678, 32'h12345678, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 305419896/305419896      ,          1,          1,          0,          0
      check_mem_results(  8, 9, 32'h12345678, 32'h87654321, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/-2023406815    ,          0,          0,  305419896,  305419896
      check_mem_results(  8,10, 32'h12345678, 32'h0000ffff, 32'h00001234, 32'h00001234, 32'h000068ac, 32'h000068ac ); // 305419896/65535          ,       4660,       4660,      26796,      26796
      check_mem_results(  8,11, 32'h12345678, 32'hffff0000, 32'hffffedcc, 32'h00000000, 32'h00005678, 32'h12345678 ); // 305419896/-65536         ,      -4660,          0,      22136,  305419896
      check_mem_results(  8,12, 32'h12345678, 32'h40000000, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/1073741824     ,          0,          0,  305419896,  305419896
      check_mem_results(  8,13, 32'h12345678, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/-1073741824    ,          0,          0,  305419896,  305419896
      check_mem_results(  8,14, 32'h12345678, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/2139062143     ,          0,          0,  305419896,  305419896
      check_mem_results(  8,15, 32'h12345678, 32'h80808080, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/-2139062144    ,          0,          0,  305419896,  305419896
      check_mem_results(  8,16, 32'h12345678, 32'h13579bdf, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/324508639      ,          0,          0,  305419896,  305419896
      check_mem_results(  8,17, 32'h12345678, 32'h2468ace0, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/610839776      ,          0,          0,  305419896,  305419896
      check_mem_results(  8,18, 32'h12345678, 32'h00007fff, 32'h00002468, 32'h00002468, 32'h00007ae0, 32'h00007ae0 ); // 305419896/32767          ,       9320,       9320,      31456,      31456
      check_mem_results(  8,19, 32'h12345678, 32'hffff8000, 32'hffffdb98, 32'h00000000, 32'h00005678, 32'h12345678 ); // 305419896/-32768         ,      -9320,          0,      22136,  305419896
      check_mem_results(  8,20, 32'h12345678, 32'h01010101, 32'h00000012, 32'h00000012, 32'h00224466, 32'h00224466 ); // 305419896/16843009       ,         18,         18,    2245734,    2245734
      check_mem_results(  8,21, 32'h12345678, 32'hf0f0f0f0, 32'hffffffff, 32'h00000000, 32'h03254768, 32'h12345678 ); // 305419896/-252645136     ,         -1,          0,   52774760,  305419896
      check_mem_results(  8,22, 32'h12345678, 32'hdeadbeef, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/-559038737     ,          0,          0,  305419896,  305419896
      check_mem_results(  8,23, 32'h12345678, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h12345678, 32'h12345678 ); // 305419896/-889275714     ,          0,          0,  305419896,  305419896

      check_mem_results(  9, 0, 32'h87654321, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h87654321, 32'h87654321 ); // -2023406815/0            ,         -1, 4294967295, -2023406815, 2271560481
      check_mem_results(  9, 1, 32'h87654321, 32'h00000001, 32'h87654321, 32'h87654321, 32'h00000000, 32'h00000000 ); // -2023406815/1            , -2023406815, 2271560481,          0,          0
      check_mem_results(  9, 2, 32'h87654321, 32'hffffffff, 32'h789abcdf, 32'h00000000, 32'h00000000, 32'h87654321 ); // -2023406815/-1           , 2023406815,          0,          0, 2271560481
      check_mem_results(  9, 3, 32'h87654321, 32'h00000002, 32'hc3b2a191, 32'h43b2a190, 32'hffffffff, 32'h00000001 ); // -2023406815/2            , -1011703407, 1135780240,         -1,          1
      check_mem_results(  9, 4, 32'h87654321, 32'hfffffffe, 32'h3c4d5e6f, 32'h00000000, 32'hffffffff, 32'h87654321 ); // -2023406815/-2           , 1011703407,          0,         -1, 2271560481
      check_mem_results(  9, 5, 32'h87654321, 32'h7fffffff, 32'h00000000, 32'h00000001, 32'h87654321, 32'h07654322 ); // -2023406815/2147483647   ,          0,          1, -2023406815,  124076834
      check_mem_results(  9, 6, 32'h87654321, 32'h80000000, 32'h00000000, 32'h00000001, 32'h87654321, 32'h07654321 ); // -2023406815/-2147483648  ,          0,          1, -2023406815,  124076833
      check_mem_results(  9, 7, 32'h87654321, 32'h80000001, 32'h00000000, 32'h00000001, 32'h87654321, 32'h07654320 ); // -2023406815/-2147483647  ,          0,          1, -2023406815,  124076832
      check_mem_results(  9, 8, 32'h87654321, 32'h12345678, 32'hfffffffa, 32'h00000007, 32'hf49f49f1, 32'h07f6e5d9 ); // -2023406815/305419896    ,         -6,          7, -190887439,  133621209
      check_mem_results(  9, 9, 32'h87654321, 32'h87654321, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -2023406815/-2023406815  ,          1,          1,          0,          0
      check_mem_results(  9,10, 32'h87654321, 32'h0000ffff, 32'hffff8765, 32'h00008765, 32'hffffca86, 32'h0000ca86 ); // -2023406815/65535        ,     -30875,      34661,     -13690,      51846
      check_mem_results(  9,11, 32'h87654321, 32'hffff0000, 32'h0000789a, 32'h00000000, 32'hffff4321, 32'h87654321 ); // -2023406815/-65536       ,      30874,          0,     -48351, 2271560481
      check_mem_results(  9,12, 32'h87654321, 32'h40000000, 32'hffffffff, 32'h00000002, 32'hc7654321, 32'h07654321 ); // -2023406815/1073741824   ,         -1,          2, -949664991,  124076833
      check_mem_results(  9,13, 32'h87654321, 32'hc0000000, 32'h00000001, 32'h00000000, 32'hc7654321, 32'h87654321 ); // -2023406815/-1073741824  ,          1,          0, -949664991, 2271560481
      check_mem_results(  9,14, 32'h87654321, 32'h7f7f7f7f, 32'h00000000, 32'h00000001, 32'h87654321, 32'h07e5c3a2 ); // -2023406815/2139062143   ,          0,          1, -2023406815,  132498338
      check_mem_results(  9,15, 32'h87654321, 32'h80808080, 32'h00000000, 32'h00000001, 32'h87654321, 32'h06e4c2a1 ); // -2023406815/-2139062144  ,          0,          1, -2023406815,  115655329
      check_mem_results(  9,16, 32'h87654321, 32'h13579bdf, 32'hfffffffa, 32'h00000007, 32'hfb72ea5b, 32'h00000008 ); // -2023406815/324508639    ,         -6,          7,  -76354981,          8
      check_mem_results(  9,17, 32'h87654321, 32'h2468ace0, 32'hfffffffd, 32'h00000003, 32'hf49f49c1, 32'h1a2b3c81 ); // -2023406815/610839776    ,         -3,          3, -190887487,  439041153
      check_mem_results(  9,18, 32'h87654321, 32'h00007fff, 32'hffff0ec9, 32'h00010ecc, 32'hffffd1ea, 32'h000051ed ); // -2023406815/32767        ,     -61751,      69324,     -11798,      20973
      check_mem_results(  9,19, 32'h87654321, 32'hffff8000, 32'h0000f135, 32'h00000000, 32'hffffc321, 32'h87654321 ); // -2023406815/-32768       ,      61749,          0,     -15583, 2271560481
      check_mem_results(  9,20, 32'h87654321, 32'h01010101, 32'hffffff88, 32'h00000086, 32'hffddbb99, 32'h00debc9b ); // -2023406815/16843009     ,       -120,        134,   -2245735,   14597275
      check_mem_results(  9,21, 32'h87654321, 32'hf0f0f0f0, 32'h00000008, 32'h00000000, 32'hffddbba1, 32'h87654321 ); // -2023406815/-252645136   ,          8,          0,   -2245727, 2271560481
      check_mem_results(  9,22, 32'h87654321, 32'hdeadbeef, 32'h00000003, 32'h00000000, 32'heb5c0654, 32'h87654321 ); // -2023406815/-559038737   ,          3,          0, -346290604, 2271560481
      check_mem_results(  9,23, 32'h87654321, 32'hcafebabe, 32'h00000002, 32'h00000000, 32'hf167cda5, 32'h87654321 ); // -2023406815/-889275714   ,          2,          0, -244855387, 2271560481

      check_mem_results( 10, 0, 32'h0000ffff, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h0000ffff, 32'h0000ffff ); // 65535/0                  ,         -1, 4294967295,      65535,      65535
      check_mem_results( 10, 1, 32'h0000ffff, 32'h00000001, 32'h0000ffff, 32'h0000ffff, 32'h00000000, 32'h00000000 ); // 65535/1                  ,      65535,      65535,          0,          0
      check_mem_results( 10, 2, 32'h0000ffff, 32'hffffffff, 32'hffff0001, 32'h00000000, 32'h00000000, 32'h0000ffff ); // 65535/-1                 ,     -65535,          0,          0,      65535
      check_mem_results( 10, 3, 32'h0000ffff, 32'h00000002, 32'h00007fff, 32'h00007fff, 32'h00000001, 32'h00000001 ); // 65535/2                  ,      32767,      32767,          1,          1
      check_mem_results( 10, 4, 32'h0000ffff, 32'hfffffffe, 32'hffff8001, 32'h00000000, 32'h00000001, 32'h0000ffff ); // 65535/-2                 ,     -32767,          0,          1,      65535
      check_mem_results( 10, 5, 32'h0000ffff, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/2147483647         ,          0,          0,      65535,      65535
      check_mem_results( 10, 6, 32'h0000ffff, 32'h80000000, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-2147483648        ,          0,          0,      65535,      65535
      check_mem_results( 10, 7, 32'h0000ffff, 32'h80000001, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-2147483647        ,          0,          0,      65535,      65535
      check_mem_results( 10, 8, 32'h0000ffff, 32'h12345678, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/305419896          ,          0,          0,      65535,      65535
      check_mem_results( 10, 9, 32'h0000ffff, 32'h87654321, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-2023406815        ,          0,          0,      65535,      65535
      check_mem_results( 10,10, 32'h0000ffff, 32'h0000ffff, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 65535/65535              ,          1,          1,          0,          0
      check_mem_results( 10,11, 32'h0000ffff, 32'hffff0000, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-65536             ,          0,          0,      65535,      65535
      check_mem_results( 10,12, 32'h0000ffff, 32'h40000000, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/1073741824         ,          0,          0,      65535,      65535
      check_mem_results( 10,13, 32'h0000ffff, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-1073741824        ,          0,          0,      65535,      65535
      check_mem_results( 10,14, 32'h0000ffff, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/2139062143         ,          0,          0,      65535,      65535
      check_mem_results( 10,15, 32'h0000ffff, 32'h80808080, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-2139062144        ,          0,          0,      65535,      65535
      check_mem_results( 10,16, 32'h0000ffff, 32'h13579bdf, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/324508639          ,          0,          0,      65535,      65535
      check_mem_results( 10,17, 32'h0000ffff, 32'h2468ace0, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/610839776          ,          0,          0,      65535,      65535
      check_mem_results( 10,18, 32'h0000ffff, 32'h00007fff, 32'h00000002, 32'h00000002, 32'h00000001, 32'h00000001 ); // 65535/32767              ,          2,          2,          1,          1
      check_mem_results( 10,19, 32'h0000ffff, 32'hffff8000, 32'hffffffff, 32'h00000000, 32'h00007fff, 32'h0000ffff ); // 65535/-32768             ,         -1,          0,      32767,      65535
      check_mem_results( 10,20, 32'h0000ffff, 32'h01010101, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/16843009           ,          0,          0,      65535,      65535
      check_mem_results( 10,21, 32'h0000ffff, 32'hf0f0f0f0, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-252645136         ,          0,          0,      65535,      65535
      check_mem_results( 10,22, 32'h0000ffff, 32'hdeadbeef, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-559038737         ,          0,          0,      65535,      65535
      check_mem_results( 10,23, 32'h0000ffff, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h0000ffff, 32'h0000ffff ); // 65535/-889275714         ,          0,          0,      65535,      65535

      check_mem_results( 11, 0, 32'hffff0000, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'hffff0000, 32'hffff0000 ); // -65536/0                 ,         -1, 4294967295,     -65536, 4294901760
      check_mem_results( 11, 1, 32'hffff0000, 32'h00000001, 32'hffff0000, 32'hffff0000, 32'h00000000, 32'h00000000 ); // -65536/1                 ,     -65536, 4294901760,          0,          0
      check_mem_results( 11, 2, 32'hffff0000, 32'hffffffff, 32'h00010000, 32'h00000000, 32'h00000000, 32'hffff0000 ); // -65536/-1                ,      65536,          0,          0, 4294901760
      check_mem_results( 11, 3, 32'hffff0000, 32'h00000002, 32'hffff8000, 32'h7fff8000, 32'h00000000, 32'h00000000 ); // -65536/2                 ,     -32768, 2147450880,          0,          0
      check_mem_results( 11, 4, 32'hffff0000, 32'hfffffffe, 32'h00008000, 32'h00000000, 32'h00000000, 32'hffff0000 ); // -65536/-2                ,      32768,          0,          0, 4294901760
      check_mem_results( 11, 5, 32'hffff0000, 32'h7fffffff, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h7fff0001 ); // -65536/2147483647        ,          0,          1,     -65536, 2147418113
      check_mem_results( 11, 6, 32'hffff0000, 32'h80000000, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h7fff0000 ); // -65536/-2147483648       ,          0,          1,     -65536, 2147418112
      check_mem_results( 11, 7, 32'hffff0000, 32'h80000001, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h7ffeffff ); // -65536/-2147483647       ,          0,          1,     -65536, 2147418111
      check_mem_results( 11, 8, 32'hffff0000, 32'h12345678, 32'h00000000, 32'h0000000e, 32'hffff0000, 32'h01224570 ); // -65536/305419896         ,          0,         14,     -65536,   19023216
      check_mem_results( 11, 9, 32'hffff0000, 32'h87654321, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h7899bcdf ); // -65536/-2023406815       ,          0,          1,     -65536, 2023341279
      check_mem_results( 11,10, 32'hffff0000, 32'h0000ffff, 32'hffffffff, 32'h00010000, 32'hffffffff, 32'h00000000 ); // -65536/65535             ,         -1,      65536,         -1,          0
      check_mem_results( 11,11, 32'hffff0000, 32'hffff0000, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -65536/-65536            ,          1,          1,          0,          0
      check_mem_results( 11,12, 32'hffff0000, 32'h40000000, 32'h00000000, 32'h00000003, 32'hffff0000, 32'h3fff0000 ); // -65536/1073741824        ,          0,          3,     -65536, 1073676288
      check_mem_results( 11,13, 32'hffff0000, 32'hc0000000, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h3fff0000 ); // -65536/-1073741824       ,          0,          1,     -65536, 1073676288
      check_mem_results( 11,14, 32'hffff0000, 32'h7f7f7f7f, 32'h00000000, 32'h00000002, 32'hffff0000, 32'h01000102 ); // -65536/2139062143        ,          0,          2,     -65536,   16777474
      check_mem_results( 11,15, 32'hffff0000, 32'h80808080, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h7f7e7f80 ); // -65536/-2139062144       ,          0,          1,     -65536, 2138996608
      check_mem_results( 11,16, 32'hffff0000, 32'h13579bdf, 32'h00000000, 32'h0000000d, 32'hffff0000, 32'h048c15ad ); // -65536/324508639         ,          0,         13,     -65536,   76289453
      check_mem_results( 11,17, 32'hffff0000, 32'h2468ace0, 32'h00000000, 32'h00000007, 32'hffff0000, 32'h012245e0 ); // -65536/610839776         ,          0,          7,     -65536,   19023328
      check_mem_results( 11,18, 32'hffff0000, 32'h00007fff, 32'hfffffffe, 32'h00020002, 32'hfffffffe, 32'h00000002 ); // -65536/32767             ,         -2,     131074,         -2,          2
      check_mem_results( 11,19, 32'hffff0000, 32'hffff8000, 32'h00000002, 32'h00000000, 32'h00000000, 32'hffff0000 ); // -65536/-32768            ,          2,          0,          0, 4294901760
      check_mem_results( 11,20, 32'hffff0000, 32'h01010101, 32'h00000000, 32'h000000fe, 32'hffff0000, 32'h01000102 ); // -65536/16843009          ,          0,        254,     -65536,   16777474
      check_mem_results( 11,21, 32'hffff0000, 32'hf0f0f0f0, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h0f0e0f10 ); // -65536/-252645136        ,          0,          1,     -65536,  252579600
      check_mem_results( 11,22, 32'hffff0000, 32'hdeadbeef, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h21514111 ); // -65536/-559038737        ,          0,          1,     -65536,  558973201
      check_mem_results( 11,23, 32'hffff0000, 32'hcafebabe, 32'h00000000, 32'h00000001, 32'hffff0000, 32'h35004542 ); // -65536/-889275714        ,          0,          1,     -65536,  889210178

      check_mem_results( 12, 0, 32'h40000000, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h40000000, 32'h40000000 ); // 1073741824/0             ,         -1, 4294967295, 1073741824, 1073741824
      check_mem_results( 12, 1, 32'h40000000, 32'h00000001, 32'h40000000, 32'h40000000, 32'h00000000, 32'h00000000 ); // 1073741824/1             , 1073741824, 1073741824,          0,          0
      check_mem_results( 12, 2, 32'h40000000, 32'hffffffff, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h40000000 ); // 1073741824/-1            , -1073741824,          0,          0, 1073741824
      check_mem_results( 12, 3, 32'h40000000, 32'h00000002, 32'h20000000, 32'h20000000, 32'h00000000, 32'h00000000 ); // 1073741824/2             ,  536870912,  536870912,          0,          0
      check_mem_results( 12, 4, 32'h40000000, 32'hfffffffe, 32'he0000000, 32'h00000000, 32'h00000000, 32'h40000000 ); // 1073741824/-2            , -536870912,          0,          0, 1073741824
      check_mem_results( 12, 5, 32'h40000000, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h40000000, 32'h40000000 ); // 1073741824/2147483647    ,          0,          0, 1073741824, 1073741824
      check_mem_results( 12, 6, 32'h40000000, 32'h80000000, 32'h00000000, 32'h00000000, 32'h40000000, 32'h40000000 ); // 1073741824/-2147483648   ,          0,          0, 1073741824, 1073741824
      check_mem_results( 12, 7, 32'h40000000, 32'h80000001, 32'h00000000, 32'h00000000, 32'h40000000, 32'h40000000 ); // 1073741824/-2147483647   ,          0,          0, 1073741824, 1073741824
      check_mem_results( 12, 8, 32'h40000000, 32'h12345678, 32'h00000003, 32'h00000003, 32'h0962fc98, 32'h0962fc98 ); // 1073741824/305419896     ,          3,          3,  157482136,  157482136
      check_mem_results( 12, 9, 32'h40000000, 32'h87654321, 32'h00000000, 32'h00000000, 32'h40000000, 32'h40000000 ); // 1073741824/-2023406815   ,          0,          0, 1073741824, 1073741824
      check_mem_results( 12,10, 32'h40000000, 32'h0000ffff, 32'h00004000, 32'h00004000, 32'h00004000, 32'h00004000 ); // 1073741824/65535         ,      16384,      16384,      16384,      16384
      check_mem_results( 12,11, 32'h40000000, 32'hffff0000, 32'hffffc000, 32'h00000000, 32'h00000000, 32'h40000000 ); // 1073741824/-65536        ,     -16384,          0,          0, 1073741824
      check_mem_results( 12,12, 32'h40000000, 32'h40000000, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 1073741824/1073741824    ,          1,          1,          0,          0
      check_mem_results( 12,13, 32'h40000000, 32'hc0000000, 32'hffffffff, 32'h00000000, 32'h00000000, 32'h40000000 ); // 1073741824/-1073741824   ,         -1,          0,          0, 1073741824
      check_mem_results( 12,14, 32'h40000000, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h40000000, 32'h40000000 ); // 1073741824/2139062143    ,          0,          0, 1073741824, 1073741824
      check_mem_results( 12,15, 32'h40000000, 32'h80808080, 32'h00000000, 32'h00000000, 32'h40000000, 32'h40000000 ); // 1073741824/-2139062144   ,          0,          0, 1073741824, 1073741824
      check_mem_results( 12,16, 32'h40000000, 32'h13579bdf, 32'h00000003, 32'h00000003, 32'h05f92c63, 32'h05f92c63 ); // 1073741824/324508639     ,          3,          3,  100215907,  100215907
      check_mem_results( 12,17, 32'h40000000, 32'h2468ace0, 32'h00000001, 32'h00000001, 32'h1b975320, 32'h1b975320 ); // 1073741824/610839776     ,          1,          1,  462902048,  462902048
      check_mem_results( 12,18, 32'h40000000, 32'h00007fff, 32'h00008001, 32'h00008001, 32'h00000001, 32'h00000001 ); // 1073741824/32767         ,      32769,      32769,          1,          1
      check_mem_results( 12,19, 32'h40000000, 32'hffff8000, 32'hffff8000, 32'h00000000, 32'h00000000, 32'h40000000 ); // 1073741824/-32768        ,     -32768,          0,          0, 1073741824
      check_mem_results( 12,20, 32'h40000000, 32'h01010101, 32'h0000003f, 32'h0000003f, 32'h00c0c0c1, 32'h00c0c0c1 ); // 1073741824/16843009      ,         63,         63,   12632257,   12632257
      check_mem_results( 12,21, 32'h40000000, 32'hf0f0f0f0, 32'hfffffffc, 32'h00000000, 32'h03c3c3c0, 32'h40000000 ); // 1073741824/-252645136    ,         -4,          0,   63161280, 1073741824
      check_mem_results( 12,22, 32'h40000000, 32'hdeadbeef, 32'hffffffff, 32'h00000000, 32'h1eadbeef, 32'h40000000 ); // 1073741824/-559038737    ,         -1,          0,  514703087, 1073741824
      check_mem_results( 12,23, 32'h40000000, 32'hcafebabe, 32'hffffffff, 32'h00000000, 32'h0afebabe, 32'h40000000 ); // 1073741824/-889275714    ,         -1,          0,  184466110, 1073741824

      check_mem_results( 13, 0, 32'hc0000000, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'hc0000000, 32'hc0000000 ); // -1073741824/0            ,         -1, 4294967295, -1073741824, 3221225472
      check_mem_results( 13, 1, 32'hc0000000, 32'h00000001, 32'hc0000000, 32'hc0000000, 32'h00000000, 32'h00000000 ); // -1073741824/1            , -1073741824, 3221225472,          0,          0
      check_mem_results( 13, 2, 32'hc0000000, 32'hffffffff, 32'h40000000, 32'h00000000, 32'h00000000, 32'hc0000000 ); // -1073741824/-1           , 1073741824,          0,          0, 3221225472
      check_mem_results( 13, 3, 32'hc0000000, 32'h00000002, 32'he0000000, 32'h60000000, 32'h00000000, 32'h00000000 ); // -1073741824/2            , -536870912, 1610612736,          0,          0
      check_mem_results( 13, 4, 32'hc0000000, 32'hfffffffe, 32'h20000000, 32'h00000000, 32'h00000000, 32'hc0000000 ); // -1073741824/-2           ,  536870912,          0,          0, 3221225472
      check_mem_results( 13, 5, 32'hc0000000, 32'h7fffffff, 32'h00000000, 32'h00000001, 32'hc0000000, 32'h40000001 ); // -1073741824/2147483647   ,          0,          1, -1073741824, 1073741825
      check_mem_results( 13, 6, 32'hc0000000, 32'h80000000, 32'h00000000, 32'h00000001, 32'hc0000000, 32'h40000000 ); // -1073741824/-2147483648  ,          0,          1, -1073741824, 1073741824
      check_mem_results( 13, 7, 32'hc0000000, 32'h80000001, 32'h00000000, 32'h00000001, 32'hc0000000, 32'h3fffffff ); // -1073741824/-2147483647  ,          0,          1, -1073741824, 1073741823
      check_mem_results( 13, 8, 32'hc0000000, 32'h12345678, 32'hfffffffd, 32'h0000000a, 32'hf69d0368, 32'h09f49f50 ); // -1073741824/305419896    ,         -3,         10, -157482136,  167026512
      check_mem_results( 13, 9, 32'hc0000000, 32'h87654321, 32'h00000000, 32'h00000001, 32'hc0000000, 32'h389abcdf ); // -1073741824/-2023406815  ,          0,          1, -1073741824,  949664991
      check_mem_results( 13,10, 32'hc0000000, 32'h0000ffff, 32'hffffc000, 32'h0000c000, 32'hffffc000, 32'h0000c000 ); // -1073741824/65535        ,     -16384,      49152,     -16384,      49152
      check_mem_results( 13,11, 32'hc0000000, 32'hffff0000, 32'h00004000, 32'h00000000, 32'h00000000, 32'hc0000000 ); // -1073741824/-65536       ,      16384,          0,          0, 3221225472
      check_mem_results( 13,12, 32'hc0000000, 32'h40000000, 32'hffffffff, 32'h00000003, 32'h00000000, 32'h00000000 ); // -1073741824/1073741824   ,         -1,          3,          0,          0
      check_mem_results( 13,13, 32'hc0000000, 32'hc0000000, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -1073741824/-1073741824  ,          1,          1,          0,          0
      check_mem_results( 13,14, 32'hc0000000, 32'h7f7f7f7f, 32'h00000000, 32'h00000001, 32'hc0000000, 32'h40808081 ); // -1073741824/2139062143   ,          0,          1, -1073741824, 1082163329
      check_mem_results( 13,15, 32'hc0000000, 32'h80808080, 32'h00000000, 32'h00000001, 32'hc0000000, 32'h3f7f7f80 ); // -1073741824/-2139062144  ,          0,          1, -1073741824, 1065320320
      check_mem_results( 13,16, 32'hc0000000, 32'h13579bdf, 32'hfffffffd, 32'h00000009, 32'hfa06d39d, 32'h11eb8529 ); // -1073741824/324508639    ,         -3,          9, -100215907,  300647721
      check_mem_results( 13,17, 32'hc0000000, 32'h2468ace0, 32'hffffffff, 32'h00000005, 32'he468ace0, 32'h09f49fa0 ); // -1073741824/610839776    ,         -1,          5, -462902048,  167026592
      check_mem_results( 13,18, 32'hc0000000, 32'h00007fff, 32'hffff7fff, 32'h00018003, 32'hffffffff, 32'h00000003 ); // -1073741824/32767        ,     -32769,      98307,         -1,          3
      check_mem_results( 13,19, 32'hc0000000, 32'hffff8000, 32'h00008000, 32'h00000000, 32'h00000000, 32'hc0000000 ); // -1073741824/-32768       ,      32768,          0,          0, 3221225472
      check_mem_results( 13,20, 32'hc0000000, 32'h01010101, 32'hffffffc1, 32'h000000bf, 32'hff3f3f3f, 32'h00404041 ); // -1073741824/16843009     ,        -63,        191,  -12632257,    4210753
      check_mem_results( 13,21, 32'hc0000000, 32'hf0f0f0f0, 32'h00000004, 32'h00000000, 32'hfc3c3c40, 32'hc0000000 ); // -1073741824/-252645136   ,          4,          0,  -63161280, 3221225472
      check_mem_results( 13,22, 32'hc0000000, 32'hdeadbeef, 32'h00000001, 32'h00000000, 32'he1524111, 32'hc0000000 ); // -1073741824/-559038737   ,          1,          0, -514703087, 3221225472
      check_mem_results( 13,23, 32'hc0000000, 32'hcafebabe, 32'h00000001, 32'h00000000, 32'hf5014542, 32'hc0000000 ); // -1073741824/-889275714   ,          1,          0, -184466110, 3221225472

      check_mem_results( 14, 0, 32'h7f7f7f7f, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h7f7f7f7f, 32'h7f7f7f7f ); // 2139062143/0             ,         -1, 4294967295, 2139062143, 2139062143
      check_mem_results( 14, 1, 32'h7f7f7f7f, 32'h00000001, 32'h7f7f7f7f, 32'h7f7f7f7f, 32'h00000000, 32'h00000000 ); // 2139062143/1             , 2139062143, 2139062143,          0,          0
      check_mem_results( 14, 2, 32'h7f7f7f7f, 32'hffffffff, 32'h80808081, 32'h00000000, 32'h00000000, 32'h7f7f7f7f ); // 2139062143/-1            , -2139062143,          0,          0, 2139062143
      check_mem_results( 14, 3, 32'h7f7f7f7f, 32'h00000002, 32'h3fbfbfbf, 32'h3fbfbfbf, 32'h00000001, 32'h00000001 ); // 2139062143/2             , 1069531071, 1069531071,          1,          1
      check_mem_results( 14, 4, 32'h7f7f7f7f, 32'hfffffffe, 32'hc0404041, 32'h00000000, 32'h00000001, 32'h7f7f7f7f ); // 2139062143/-2            , -1069531071,          0,          1, 2139062143
      check_mem_results( 14, 5, 32'h7f7f7f7f, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h7f7f7f7f, 32'h7f7f7f7f ); // 2139062143/2147483647    ,          0,          0, 2139062143, 2139062143
      check_mem_results( 14, 6, 32'h7f7f7f7f, 32'h80000000, 32'h00000000, 32'h00000000, 32'h7f7f7f7f, 32'h7f7f7f7f ); // 2139062143/-2147483648   ,          0,          0, 2139062143, 2139062143
      check_mem_results( 14, 7, 32'h7f7f7f7f, 32'h80000001, 32'h00000000, 32'h00000000, 32'h7f7f7f7f, 32'h7f7f7f7f ); // 2139062143/-2147483647   ,          0,          0, 2139062143, 2139062143
      check_mem_results( 14, 8, 32'h7f7f7f7f, 32'h12345678, 32'h00000007, 32'h00000007, 32'h00112237, 32'h00112237 ); // 2139062143/305419896     ,          7,          7,    1122871,    1122871
      check_mem_results( 14, 9, 32'h7f7f7f7f, 32'h87654321, 32'hffffffff, 32'h00000000, 32'h06e4c2a0, 32'h7f7f7f7f ); // 2139062143/-2023406815   ,         -1,          0,  115655328, 2139062143
      check_mem_results( 14,10, 32'h7f7f7f7f, 32'h0000ffff, 32'h00007f7f, 32'h00007f7f, 32'h0000fefe, 32'h0000fefe ); // 2139062143/65535         ,      32639,      32639,      65278,      65278
      check_mem_results( 14,11, 32'h7f7f7f7f, 32'hffff0000, 32'hffff8081, 32'h00000000, 32'h00007f7f, 32'h7f7f7f7f ); // 2139062143/-65536        ,     -32639,          0,      32639, 2139062143
      check_mem_results( 14,12, 32'h7f7f7f7f, 32'h40000000, 32'h00000001, 32'h00000001, 32'h3f7f7f7f, 32'h3f7f7f7f ); // 2139062143/1073741824    ,          1,          1, 1065320319, 1065320319
      check_mem_results( 14,13, 32'h7f7f7f7f, 32'hc0000000, 32'hffffffff, 32'h00000000, 32'h3f7f7f7f, 32'h7f7f7f7f ); // 2139062143/-1073741824   ,         -1,          0, 1065320319, 2139062143
      check_mem_results( 14,14, 32'h7f7f7f7f, 32'h7f7f7f7f, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 2139062143/2139062143    ,          1,          1,          0,          0
      check_mem_results( 14,15, 32'h7f7f7f7f, 32'h80808080, 32'h00000000, 32'h00000000, 32'h7f7f7f7f, 32'h7f7f7f7f ); // 2139062143/-2139062144   ,          0,          0, 2139062143, 2139062143
      check_mem_results( 14,16, 32'h7f7f7f7f, 32'h13579bdf, 32'h00000006, 32'h00000006, 32'h0b71d845, 32'h0b71d845 ); // 2139062143/324508639     ,          6,          6,  192010309,  192010309
      check_mem_results( 14,17, 32'h7f7f7f7f, 32'h2468ace0, 32'h00000003, 32'h00000003, 32'h124578df, 32'h124578df ); // 2139062143/610839776     ,          3,          3,  306542815,  306542815
      check_mem_results( 14,18, 32'h7f7f7f7f, 32'h00007fff, 32'h0000ff00, 32'h0000ff00, 32'h00007e7f, 32'h00007e7f ); // 2139062143/32767         ,      65280,      65280,      32383,      32383
      check_mem_results( 14,19, 32'h7f7f7f7f, 32'hffff8000, 32'hffff0102, 32'h00000000, 32'h00007f7f, 32'h7f7f7f7f ); // 2139062143/-32768        ,     -65278,          0,      32639, 2139062143
      check_mem_results( 14,20, 32'h7f7f7f7f, 32'h01010101, 32'h0000007f, 32'h0000007f, 32'h00000000, 32'h00000000 ); // 2139062143/16843009      ,        127,        127,          0,          0
      check_mem_results( 14,21, 32'h7f7f7f7f, 32'hf0f0f0f0, 32'hfffffff8, 32'h00000000, 32'h070706ff, 32'h7f7f7f7f ); // 2139062143/-252645136    ,         -8,          0,  117901055, 2139062143
      check_mem_results( 14,22, 32'h7f7f7f7f, 32'hdeadbeef, 32'hfffffffd, 32'h00000000, 32'h1b88bc4c, 32'h7f7f7f7f ); // 2139062143/-559038737    ,         -3,          0,  461945932, 2139062143
      check_mem_results( 14,23, 32'h7f7f7f7f, 32'hcafebabe, 32'hfffffffe, 32'h00000000, 32'h157cf4fb, 32'h7f7f7f7f ); // 2139062143/-889275714    ,         -2,          0,  360510715, 2139062143

      check_mem_results( 15, 0, 32'h80808080, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h80808080, 32'h80808080 ); // -2139062144/0            ,         -1, 4294967295, -2139062144, 2155905152
      check_mem_results( 15, 1, 32'h80808080, 32'h00000001, 32'h80808080, 32'h80808080, 32'h00000000, 32'h00000000 ); // -2139062144/1            , -2139062144, 2155905152,          0,          0
      check_mem_results( 15, 2, 32'h80808080, 32'hffffffff, 32'h7f7f7f80, 32'h00000000, 32'h00000000, 32'h80808080 ); // -2139062144/-1           , 2139062144,          0,          0, 2155905152
      check_mem_results( 15, 3, 32'h80808080, 32'h00000002, 32'hc0404040, 32'h40404040, 32'h00000000, 32'h00000000 ); // -2139062144/2            , -1069531072, 1077952576,          0,          0
      check_mem_results( 15, 4, 32'h80808080, 32'hfffffffe, 32'h3fbfbfc0, 32'h00000000, 32'h00000000, 32'h80808080 ); // -2139062144/-2           , 1069531072,          0,          0, 2155905152
      check_mem_results( 15, 5, 32'h80808080, 32'h7fffffff, 32'h00000000, 32'h00000001, 32'h80808080, 32'h00808081 ); // -2139062144/2147483647   ,          0,          1, -2139062144,    8421505
      check_mem_results( 15, 6, 32'h80808080, 32'h80000000, 32'h00000000, 32'h00000001, 32'h80808080, 32'h00808080 ); // -2139062144/-2147483648  ,          0,          1, -2139062144,    8421504
      check_mem_results( 15, 7, 32'h80808080, 32'h80000001, 32'h00000000, 32'h00000001, 32'h80808080, 32'h0080807f ); // -2139062144/-2147483647  ,          0,          1, -2139062144,    8421503
      check_mem_results( 15, 8, 32'h80808080, 32'h12345678, 32'hfffffff9, 32'h00000007, 32'hffeeddc8, 32'h01122338 ); // -2139062144/305419896    ,         -7,          7,   -1122872,   17965880
      check_mem_results( 15, 9, 32'h80808080, 32'h87654321, 32'h00000001, 32'h00000000, 32'hf91b3d5f, 32'h80808080 ); // -2139062144/-2023406815  ,          1,          0, -115655329, 2155905152
      check_mem_results( 15,10, 32'h80808080, 32'h0000ffff, 32'hffff8081, 32'h00008081, 32'hffff0101, 32'h00000101 ); // -2139062144/65535        ,     -32639,      32897,     -65279,        257
      check_mem_results( 15,11, 32'h80808080, 32'hffff0000, 32'h00007f7f, 32'h00000000, 32'hffff8080, 32'h80808080 ); // -2139062144/-65536       ,      32639,          0,     -32640, 2155905152
      check_mem_results( 15,12, 32'h80808080, 32'h40000000, 32'hffffffff, 32'h00000002, 32'hc0808080, 32'h00808080 ); // -2139062144/1073741824   ,         -1,          2, -1065320320,    8421504
      check_mem_results( 15,13, 32'h80808080, 32'hc0000000, 32'h00000001, 32'h00000000, 32'hc0808080, 32'h80808080 ); // -2139062144/-1073741824  ,          1,          0, -1065320320, 2155905152
      check_mem_results( 15,14, 32'h80808080, 32'h7f7f7f7f, 32'hffffffff, 32'h00000001, 32'hffffffff, 32'h01010101 ); // -2139062144/2139062143   ,         -1,          1,         -1,   16843009
      check_mem_results( 15,15, 32'h80808080, 32'h80808080, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -2139062144/-2139062144  ,          1,          1,          0,          0
      check_mem_results( 15,16, 32'h80808080, 32'h13579bdf, 32'hfffffffa, 32'h00000006, 32'hf48e27ba, 32'h0c72d946 ); // -2139062144/324508639    ,         -6,          6, -192010310,  208853318
      check_mem_results( 15,17, 32'h80808080, 32'h2468ace0, 32'hfffffffd, 32'h00000003, 32'hedba8720, 32'h134679e0 ); // -2139062144/610839776    ,         -3,          3, -306542816,  323385824
      check_mem_results( 15,18, 32'h80808080, 32'h00007fff, 32'hffff0100, 32'h00010103, 32'hffff8180, 32'h00000183 ); // -2139062144/32767        ,     -65280,      65795,     -32384,        387
      check_mem_results( 15,19, 32'h80808080, 32'hffff8000, 32'h0000fefe, 32'h00000000, 32'hffff8080, 32'h80808080 ); // -2139062144/-32768       ,      65278,          0,     -32640, 2155905152
      check_mem_results( 15,20, 32'h80808080, 32'h01010101, 32'hffffff81, 32'h00000080, 32'hffffffff, 32'h00000000 ); // -2139062144/16843009     ,       -127,        128,         -1,          0
      check_mem_results( 15,21, 32'h80808080, 32'hf0f0f0f0, 32'h00000008, 32'h00000000, 32'hf8f8f900, 32'h80808080 ); // -2139062144/-252645136   ,          8,          0, -117901056, 2155905152
      check_mem_results( 15,22, 32'h80808080, 32'hdeadbeef, 32'h00000003, 32'h00000000, 32'he47743b3, 32'h80808080 ); // -2139062144/-559038737   ,          3,          0, -461945933, 2155905152
      check_mem_results( 15,23, 32'h80808080, 32'hcafebabe, 32'h00000002, 32'h00000000, 32'hea830b04, 32'h80808080 ); // -2139062144/-889275714   ,          2,          0, -360510716, 2155905152

      check_mem_results( 16, 0, 32'h13579bdf, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h13579bdf, 32'h13579bdf ); // 324508639/0              ,         -1, 4294967295,  324508639,  324508639
      check_mem_results( 16, 1, 32'h13579bdf, 32'h00000001, 32'h13579bdf, 32'h13579bdf, 32'h00000000, 32'h00000000 ); // 324508639/1              ,  324508639,  324508639,          0,          0
      check_mem_results( 16, 2, 32'h13579bdf, 32'hffffffff, 32'heca86421, 32'h00000000, 32'h00000000, 32'h13579bdf ); // 324508639/-1             , -324508639,          0,          0,  324508639
      check_mem_results( 16, 3, 32'h13579bdf, 32'h00000002, 32'h09abcdef, 32'h09abcdef, 32'h00000001, 32'h00000001 ); // 324508639/2              ,  162254319,  162254319,          1,          1
      check_mem_results( 16, 4, 32'h13579bdf, 32'hfffffffe, 32'hf6543211, 32'h00000000, 32'h00000001, 32'h13579bdf ); // 324508639/-2             , -162254319,          0,          1,  324508639
      check_mem_results( 16, 5, 32'h13579bdf, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/2147483647     ,          0,          0,  324508639,  324508639
      check_mem_results( 16, 6, 32'h13579bdf, 32'h80000000, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/-2147483648    ,          0,          0,  324508639,  324508639
      check_mem_results( 16, 7, 32'h13579bdf, 32'h80000001, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/-2147483647    ,          0,          0,  324508639,  324508639
      check_mem_results( 16, 8, 32'h13579bdf, 32'h12345678, 32'h00000001, 32'h00000001, 32'h01234567, 32'h01234567 ); // 324508639/305419896      ,          1,          1,   19088743,   19088743
      check_mem_results( 16, 9, 32'h13579bdf, 32'h87654321, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/-2023406815    ,          0,          0,  324508639,  324508639
      check_mem_results( 16,10, 32'h13579bdf, 32'h0000ffff, 32'h00001357, 32'h00001357, 32'h0000af36, 32'h0000af36 ); // 324508639/65535          ,       4951,       4951,      44854,      44854
      check_mem_results( 16,11, 32'h13579bdf, 32'hffff0000, 32'hffffeca9, 32'h00000000, 32'h00009bdf, 32'h13579bdf ); // 324508639/-65536         ,      -4951,          0,      39903,  324508639
      check_mem_results( 16,12, 32'h13579bdf, 32'h40000000, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/1073741824     ,          0,          0,  324508639,  324508639
      check_mem_results( 16,13, 32'h13579bdf, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/-1073741824    ,          0,          0,  324508639,  324508639
      check_mem_results( 16,14, 32'h13579bdf, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/2139062143     ,          0,          0,  324508639,  324508639
      check_mem_results( 16,15, 32'h13579bdf, 32'h80808080, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/-2139062144    ,          0,          0,  324508639,  324508639
      check_mem_results( 16,16, 32'h13579bdf, 32'h13579bdf, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 324508639/324508639      ,          1,          1,          0,          0
      check_mem_results( 16,17, 32'h13579bdf, 32'h2468ace0, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/610839776      ,          0,          0,  324508639,  324508639
      check_mem_results( 16,18, 32'h13579bdf, 32'h00007fff, 32'h000026af, 32'h000026af, 32'h0000428e, 32'h0000428e ); // 324508639/32767          ,       9903,       9903,      17038,      17038
      check_mem_results( 16,19, 32'h13579bdf, 32'hffff8000, 32'hffffd951, 32'h00000000, 32'h00001bdf, 32'h13579bdf ); // 324508639/-32768         ,      -9903,          0,       7135,  324508639
      check_mem_results( 16,20, 32'h13579bdf, 32'h01010101, 32'h00000013, 32'h00000013, 32'h004488cc, 32'h004488cc ); // 324508639/16843009       ,         19,         19,    4491468,    4491468
      check_mem_results( 16,21, 32'h13579bdf, 32'hf0f0f0f0, 32'hffffffff, 32'h00000000, 32'h04488ccf, 32'h13579bdf ); // 324508639/-252645136     ,         -1,          0,   71863503,  324508639
      check_mem_results( 16,22, 32'h13579bdf, 32'hdeadbeef, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/-559038737     ,          0,          0,  324508639,  324508639
      check_mem_results( 16,23, 32'h13579bdf, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h13579bdf, 32'h13579bdf ); // 324508639/-889275714     ,          0,          0,  324508639,  324508639

      check_mem_results( 17, 0, 32'h2468ace0, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h2468ace0, 32'h2468ace0 ); // 610839776/0              ,         -1, 4294967295,  610839776,  610839776
      check_mem_results( 17, 1, 32'h2468ace0, 32'h00000001, 32'h2468ace0, 32'h2468ace0, 32'h00000000, 32'h00000000 ); // 610839776/1              ,  610839776,  610839776,          0,          0
      check_mem_results( 17, 2, 32'h2468ace0, 32'hffffffff, 32'hdb975320, 32'h00000000, 32'h00000000, 32'h2468ace0 ); // 610839776/-1             , -610839776,          0,          0,  610839776
      check_mem_results( 17, 3, 32'h2468ace0, 32'h00000002, 32'h12345670, 32'h12345670, 32'h00000000, 32'h00000000 ); // 610839776/2              ,  305419888,  305419888,          0,          0
      check_mem_results( 17, 4, 32'h2468ace0, 32'hfffffffe, 32'hedcba990, 32'h00000000, 32'h00000000, 32'h2468ace0 ); // 610839776/-2             , -305419888,          0,          0,  610839776
      check_mem_results( 17, 5, 32'h2468ace0, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/2147483647     ,          0,          0,  610839776,  610839776
      check_mem_results( 17, 6, 32'h2468ace0, 32'h80000000, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/-2147483648    ,          0,          0,  610839776,  610839776
      check_mem_results( 17, 7, 32'h2468ace0, 32'h80000001, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/-2147483647    ,          0,          0,  610839776,  610839776
      check_mem_results( 17, 8, 32'h2468ace0, 32'h12345678, 32'h00000001, 32'h00000001, 32'h12345668, 32'h12345668 ); // 610839776/305419896      ,          1,          1,  305419880,  305419880
      check_mem_results( 17, 9, 32'h2468ace0, 32'h87654321, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/-2023406815    ,          0,          0,  610839776,  610839776
      check_mem_results( 17,10, 32'h2468ace0, 32'h0000ffff, 32'h00002468, 32'h00002468, 32'h0000d148, 32'h0000d148 ); // 610839776/65535          ,       9320,       9320,      53576,      53576
      check_mem_results( 17,11, 32'h2468ace0, 32'hffff0000, 32'hffffdb98, 32'h00000000, 32'h0000ace0, 32'h2468ace0 ); // 610839776/-65536         ,      -9320,          0,      44256,  610839776
      check_mem_results( 17,12, 32'h2468ace0, 32'h40000000, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/1073741824     ,          0,          0,  610839776,  610839776
      check_mem_results( 17,13, 32'h2468ace0, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/-1073741824    ,          0,          0,  610839776,  610839776
      check_mem_results( 17,14, 32'h2468ace0, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/2139062143     ,          0,          0,  610839776,  610839776
      check_mem_results( 17,15, 32'h2468ace0, 32'h80808080, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/-2139062144    ,          0,          0,  610839776,  610839776
      check_mem_results( 17,16, 32'h2468ace0, 32'h13579bdf, 32'h00000001, 32'h00000001, 32'h11111101, 32'h11111101 ); // 610839776/324508639      ,          1,          1,  286331137,  286331137
      check_mem_results( 17,17, 32'h2468ace0, 32'h2468ace0, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 610839776/610839776      ,          1,          1,          0,          0
      check_mem_results( 17,18, 32'h2468ace0, 32'h00007fff, 32'h000048d1, 32'h000048d1, 32'h000075b1, 32'h000075b1 ); // 610839776/32767          ,      18641,      18641,      30129,      30129
      check_mem_results( 17,19, 32'h2468ace0, 32'hffff8000, 32'hffffb72f, 32'h00000000, 32'h00002ce0, 32'h2468ace0 ); // 610839776/-32768         ,     -18641,          0,      11488,  610839776
      check_mem_results( 17,20, 32'h2468ace0, 32'h01010101, 32'h00000024, 32'h00000024, 32'h004488bc, 32'h004488bc ); // 610839776/16843009       ,         36,         36,    4491452,    4491452
      check_mem_results( 17,21, 32'h2468ace0, 32'hf0f0f0f0, 32'hfffffffe, 32'h00000000, 32'h064a8ec0, 32'h2468ace0 ); // 610839776/-252645136     ,         -2,          0,  105549504,  610839776
      check_mem_results( 17,22, 32'h2468ace0, 32'hdeadbeef, 32'hffffffff, 32'h00000000, 32'h03166bcf, 32'h2468ace0 ); // 610839776/-559038737     ,         -1,          0,   51801039,  610839776
      check_mem_results( 17,23, 32'h2468ace0, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h2468ace0, 32'h2468ace0 ); // 610839776/-889275714     ,          0,          0,  610839776,  610839776

      check_mem_results( 18, 0, 32'h00007fff, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h00007fff, 32'h00007fff ); // 32767/0                  ,         -1, 4294967295,      32767,      32767
      check_mem_results( 18, 1, 32'h00007fff, 32'h00000001, 32'h00007fff, 32'h00007fff, 32'h00000000, 32'h00000000 ); // 32767/1                  ,      32767,      32767,          0,          0
      check_mem_results( 18, 2, 32'h00007fff, 32'hffffffff, 32'hffff8001, 32'h00000000, 32'h00000000, 32'h00007fff ); // 32767/-1                 ,     -32767,          0,          0,      32767
      check_mem_results( 18, 3, 32'h00007fff, 32'h00000002, 32'h00003fff, 32'h00003fff, 32'h00000001, 32'h00000001 ); // 32767/2                  ,      16383,      16383,          1,          1
      check_mem_results( 18, 4, 32'h00007fff, 32'hfffffffe, 32'hffffc001, 32'h00000000, 32'h00000001, 32'h00007fff ); // 32767/-2                 ,     -16383,          0,          1,      32767
      check_mem_results( 18, 5, 32'h00007fff, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/2147483647         ,          0,          0,      32767,      32767
      check_mem_results( 18, 6, 32'h00007fff, 32'h80000000, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-2147483648        ,          0,          0,      32767,      32767
      check_mem_results( 18, 7, 32'h00007fff, 32'h80000001, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-2147483647        ,          0,          0,      32767,      32767
      check_mem_results( 18, 8, 32'h00007fff, 32'h12345678, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/305419896          ,          0,          0,      32767,      32767
      check_mem_results( 18, 9, 32'h00007fff, 32'h87654321, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-2023406815        ,          0,          0,      32767,      32767
      check_mem_results( 18,10, 32'h00007fff, 32'h0000ffff, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/65535              ,          0,          0,      32767,      32767
      check_mem_results( 18,11, 32'h00007fff, 32'hffff0000, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-65536             ,          0,          0,      32767,      32767
      check_mem_results( 18,12, 32'h00007fff, 32'h40000000, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/1073741824         ,          0,          0,      32767,      32767
      check_mem_results( 18,13, 32'h00007fff, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-1073741824        ,          0,          0,      32767,      32767
      check_mem_results( 18,14, 32'h00007fff, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/2139062143         ,          0,          0,      32767,      32767
      check_mem_results( 18,15, 32'h00007fff, 32'h80808080, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-2139062144        ,          0,          0,      32767,      32767
      check_mem_results( 18,16, 32'h00007fff, 32'h13579bdf, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/324508639          ,          0,          0,      32767,      32767
      check_mem_results( 18,17, 32'h00007fff, 32'h2468ace0, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/610839776          ,          0,          0,      32767,      32767
      check_mem_results( 18,18, 32'h00007fff, 32'h00007fff, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 32767/32767              ,          1,          1,          0,          0
      check_mem_results( 18,19, 32'h00007fff, 32'hffff8000, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-32768             ,          0,          0,      32767,      32767
      check_mem_results( 18,20, 32'h00007fff, 32'h01010101, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/16843009           ,          0,          0,      32767,      32767
      check_mem_results( 18,21, 32'h00007fff, 32'hf0f0f0f0, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-252645136         ,          0,          0,      32767,      32767
      check_mem_results( 18,22, 32'h00007fff, 32'hdeadbeef, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-559038737         ,          0,          0,      32767,      32767
      check_mem_results( 18,23, 32'h00007fff, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h00007fff, 32'h00007fff ); // 32767/-889275714         ,          0,          0,      32767,      32767

      check_mem_results( 19, 0, 32'hffff8000, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'hffff8000, 32'hffff8000 ); // -32768/0                 ,         -1, 4294967295,     -32768, 4294934528
      check_mem_results( 19, 1, 32'hffff8000, 32'h00000001, 32'hffff8000, 32'hffff8000, 32'h00000000, 32'h00000000 ); // -32768/1                 ,     -32768, 4294934528,          0,          0
      check_mem_results( 19, 2, 32'hffff8000, 32'hffffffff, 32'h00008000, 32'h00000000, 32'h00000000, 32'hffff8000 ); // -32768/-1                ,      32768,          0,          0, 4294934528
      check_mem_results( 19, 3, 32'hffff8000, 32'h00000002, 32'hffffc000, 32'h7fffc000, 32'h00000000, 32'h00000000 ); // -32768/2                 ,     -16384, 2147467264,          0,          0
      check_mem_results( 19, 4, 32'hffff8000, 32'hfffffffe, 32'h00004000, 32'h00000000, 32'h00000000, 32'hffff8000 ); // -32768/-2                ,      16384,          0,          0, 4294934528
      check_mem_results( 19, 5, 32'hffff8000, 32'h7fffffff, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h7fff8001 ); // -32768/2147483647        ,          0,          1,     -32768, 2147450881
      check_mem_results( 19, 6, 32'hffff8000, 32'h80000000, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h7fff8000 ); // -32768/-2147483648       ,          0,          1,     -32768, 2147450880
      check_mem_results( 19, 7, 32'hffff8000, 32'h80000001, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h7fff7fff ); // -32768/-2147483647       ,          0,          1,     -32768, 2147450879
      check_mem_results( 19, 8, 32'hffff8000, 32'h12345678, 32'h00000000, 32'h0000000e, 32'hffff8000, 32'h0122c570 ); // -32768/305419896         ,          0,         14,     -32768,   19055984
      check_mem_results( 19, 9, 32'hffff8000, 32'h87654321, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h789a3cdf ); // -32768/-2023406815       ,          0,          1,     -32768, 2023374047
      check_mem_results( 19,10, 32'hffff8000, 32'h0000ffff, 32'h00000000, 32'h00010000, 32'hffff8000, 32'h00008000 ); // -32768/65535             ,          0,      65536,     -32768,      32768
      check_mem_results( 19,11, 32'hffff8000, 32'hffff0000, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h00008000 ); // -32768/-65536            ,          0,          1,     -32768,      32768
      check_mem_results( 19,12, 32'hffff8000, 32'h40000000, 32'h00000000, 32'h00000003, 32'hffff8000, 32'h3fff8000 ); // -32768/1073741824        ,          0,          3,     -32768, 1073709056
      check_mem_results( 19,13, 32'hffff8000, 32'hc0000000, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h3fff8000 ); // -32768/-1073741824       ,          0,          1,     -32768, 1073709056
      check_mem_results( 19,14, 32'hffff8000, 32'h7f7f7f7f, 32'h00000000, 32'h00000002, 32'hffff8000, 32'h01008102 ); // -32768/2139062143        ,          0,          2,     -32768,   16810242
      check_mem_results( 19,15, 32'hffff8000, 32'h80808080, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h7f7eff80 ); // -32768/-2139062144       ,          0,          1,     -32768, 2139029376
      check_mem_results( 19,16, 32'hffff8000, 32'h13579bdf, 32'h00000000, 32'h0000000d, 32'hffff8000, 32'h048c95ad ); // -32768/324508639         ,          0,         13,     -32768,   76322221
      check_mem_results( 19,17, 32'hffff8000, 32'h2468ace0, 32'h00000000, 32'h00000007, 32'hffff8000, 32'h0122c5e0 ); // -32768/610839776         ,          0,          7,     -32768,   19056096
      check_mem_results( 19,18, 32'hffff8000, 32'h00007fff, 32'hffffffff, 32'h00020003, 32'hffffffff, 32'h00000003 ); // -32768/32767             ,         -1,     131075,         -1,          3
      check_mem_results( 19,19, 32'hffff8000, 32'hffff8000, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -32768/-32768            ,          1,          1,          0,          0
      check_mem_results( 19,20, 32'hffff8000, 32'h01010101, 32'h00000000, 32'h000000fe, 32'hffff8000, 32'h01008102 ); // -32768/16843009          ,          0,        254,     -32768,   16810242
      check_mem_results( 19,21, 32'hffff8000, 32'hf0f0f0f0, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h0f0e8f10 ); // -32768/-252645136        ,          0,          1,     -32768,  252612368
      check_mem_results( 19,22, 32'hffff8000, 32'hdeadbeef, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h2151c111 ); // -32768/-559038737        ,          0,          1,     -32768,  559005969
      check_mem_results( 19,23, 32'hffff8000, 32'hcafebabe, 32'h00000000, 32'h00000001, 32'hffff8000, 32'h3500c542 ); // -32768/-889275714        ,          0,          1,     -32768,  889242946

      check_mem_results( 20, 0, 32'h01010101, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'h01010101, 32'h01010101 ); // 16843009/0               ,         -1, 4294967295,   16843009,   16843009
      check_mem_results( 20, 1, 32'h01010101, 32'h00000001, 32'h01010101, 32'h01010101, 32'h00000000, 32'h00000000 ); // 16843009/1               ,   16843009,   16843009,          0,          0
      check_mem_results( 20, 2, 32'h01010101, 32'hffffffff, 32'hfefefeff, 32'h00000000, 32'h00000000, 32'h01010101 ); // 16843009/-1              ,  -16843009,          0,          0,   16843009
      check_mem_results( 20, 3, 32'h01010101, 32'h00000002, 32'h00808080, 32'h00808080, 32'h00000001, 32'h00000001 ); // 16843009/2               ,    8421504,    8421504,          1,          1
      check_mem_results( 20, 4, 32'h01010101, 32'hfffffffe, 32'hff7f7f80, 32'h00000000, 32'h00000001, 32'h01010101 ); // 16843009/-2              ,   -8421504,          0,          1,   16843009
      check_mem_results( 20, 5, 32'h01010101, 32'h7fffffff, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/2147483647      ,          0,          0,   16843009,   16843009
      check_mem_results( 20, 6, 32'h01010101, 32'h80000000, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/-2147483648     ,          0,          0,   16843009,   16843009
      check_mem_results( 20, 7, 32'h01010101, 32'h80000001, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/-2147483647     ,          0,          0,   16843009,   16843009
      check_mem_results( 20, 8, 32'h01010101, 32'h12345678, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/305419896       ,          0,          0,   16843009,   16843009
      check_mem_results( 20, 9, 32'h01010101, 32'h87654321, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/-2023406815     ,          0,          0,   16843009,   16843009
      check_mem_results( 20,10, 32'h01010101, 32'h0000ffff, 32'h00000101, 32'h00000101, 32'h00000202, 32'h00000202 ); // 16843009/65535           ,        257,        257,        514,        514
      check_mem_results( 20,11, 32'h01010101, 32'hffff0000, 32'hfffffeff, 32'h00000000, 32'h00000101, 32'h01010101 ); // 16843009/-65536          ,       -257,          0,        257,   16843009
      check_mem_results( 20,12, 32'h01010101, 32'h40000000, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/1073741824      ,          0,          0,   16843009,   16843009
      check_mem_results( 20,13, 32'h01010101, 32'hc0000000, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/-1073741824     ,          0,          0,   16843009,   16843009
      check_mem_results( 20,14, 32'h01010101, 32'h7f7f7f7f, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/2139062143      ,          0,          0,   16843009,   16843009
      check_mem_results( 20,15, 32'h01010101, 32'h80808080, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/-2139062144     ,          0,          0,   16843009,   16843009
      check_mem_results( 20,16, 32'h01010101, 32'h13579bdf, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/324508639       ,          0,          0,   16843009,   16843009
      check_mem_results( 20,17, 32'h01010101, 32'h2468ace0, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/610839776       ,          0,          0,   16843009,   16843009
      check_mem_results( 20,18, 32'h01010101, 32'h00007fff, 32'h00000202, 32'h00000202, 32'h00000303, 32'h00000303 ); // 16843009/32767           ,        514,        514,        771,        771
      check_mem_results( 20,19, 32'h01010101, 32'hffff8000, 32'hfffffdfe, 32'h00000000, 32'h00000101, 32'h01010101 ); // 16843009/-32768          ,       -514,          0,        257,   16843009
      check_mem_results( 20,20, 32'h01010101, 32'h01010101, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // 16843009/16843009        ,          1,          1,          0,          0
      check_mem_results( 20,21, 32'h01010101, 32'hf0f0f0f0, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/-252645136      ,          0,          0,   16843009,   16843009
      check_mem_results( 20,22, 32'h01010101, 32'hdeadbeef, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/-559038737      ,          0,          0,   16843009,   16843009
      check_mem_results( 20,23, 32'h01010101, 32'hcafebabe, 32'h00000000, 32'h00000000, 32'h01010101, 32'h01010101 ); // 16843009/-889275714      ,          0,          0,   16843009,   16843009

      check_mem_results( 21, 0, 32'hf0f0f0f0, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'hf0f0f0f0, 32'hf0f0f0f0 ); // -252645136/0             ,         -1, 4294967295, -252645136, 4042322160
      check_mem_results( 21, 1, 32'hf0f0f0f0, 32'h00000001, 32'hf0f0f0f0, 32'hf0f0f0f0, 32'h00000000, 32'h00000000 ); // -252645136/1             , -252645136, 4042322160,          0,          0
      check_mem_results( 21, 2, 32'hf0f0f0f0, 32'hffffffff, 32'h0f0f0f10, 32'h00000000, 32'h00000000, 32'hf0f0f0f0 ); // -252645136/-1            ,  252645136,          0,          0, 4042322160
      check_mem_results( 21, 3, 32'hf0f0f0f0, 32'h00000002, 32'hf8787878, 32'h78787878, 32'h00000000, 32'h00000000 ); // -252645136/2             , -126322568, 2021161080,          0,          0
      check_mem_results( 21, 4, 32'hf0f0f0f0, 32'hfffffffe, 32'h07878788, 32'h00000000, 32'h00000000, 32'hf0f0f0f0 ); // -252645136/-2            ,  126322568,          0,          0, 4042322160
      check_mem_results( 21, 5, 32'hf0f0f0f0, 32'h7fffffff, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h70f0f0f1 ); // -252645136/2147483647    ,          0,          1, -252645136, 1894838513
      check_mem_results( 21, 6, 32'hf0f0f0f0, 32'h80000000, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h70f0f0f0 ); // -252645136/-2147483648   ,          0,          1, -252645136, 1894838512
      check_mem_results( 21, 7, 32'hf0f0f0f0, 32'h80000001, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h70f0f0ef ); // -252645136/-2147483647   ,          0,          1, -252645136, 1894838511
      check_mem_results( 21, 8, 32'hf0f0f0f0, 32'h12345678, 32'h00000000, 32'h0000000d, 32'hf0f0f0f0, 32'h04488cd8 ); // -252645136/305419896     ,          0,         13, -252645136,   71863512
      check_mem_results( 21, 9, 32'hf0f0f0f0, 32'h87654321, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h698badcf ); // -252645136/-2023406815   ,          0,          1, -252645136, 1770761679
      check_mem_results( 21,10, 32'hf0f0f0f0, 32'h0000ffff, 32'hfffff0f1, 32'h0000f0f1, 32'hffffe1e1, 32'h0000e1e1 ); // -252645136/65535         ,      -3855,      61681,      -7711,      57825
      check_mem_results( 21,11, 32'hf0f0f0f0, 32'hffff0000, 32'h00000f0f, 32'h00000000, 32'hfffff0f0, 32'hf0f0f0f0 ); // -252645136/-65536        ,       3855,          0,      -3856, 4042322160
      check_mem_results( 21,12, 32'hf0f0f0f0, 32'h40000000, 32'h00000000, 32'h00000003, 32'hf0f0f0f0, 32'h30f0f0f0 ); // -252645136/1073741824    ,          0,          3, -252645136,  821096688
      check_mem_results( 21,13, 32'hf0f0f0f0, 32'hc0000000, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h30f0f0f0 ); // -252645136/-1073741824   ,          0,          1, -252645136,  821096688
      check_mem_results( 21,14, 32'hf0f0f0f0, 32'h7f7f7f7f, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h71717171 ); // -252645136/2139062143    ,          0,          1, -252645136, 1903260017
      check_mem_results( 21,15, 32'hf0f0f0f0, 32'h80808080, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h70707070 ); // -252645136/-2139062144   ,          0,          1, -252645136, 1886417008
      check_mem_results( 21,16, 32'hf0f0f0f0, 32'h13579bdf, 32'h00000000, 32'h0000000c, 32'hf0f0f0f0, 32'h08d5a27c ); // -252645136/324508639     ,          0,         12, -252645136,  148218492
      check_mem_results( 21,17, 32'hf0f0f0f0, 32'h2468ace0, 32'h00000000, 32'h00000006, 32'hf0f0f0f0, 32'h167ce3b0 ); // -252645136/610839776     ,          0,          6, -252645136,  377283504
      check_mem_results( 21,18, 32'hf0f0f0f0, 32'h00007fff, 32'hffffe1e2, 32'h0001e1e5, 32'hffffd2d2, 32'h000052d5 ); // -252645136/32767         ,      -7710,     123365,     -11566,      21205
      check_mem_results( 21,19, 32'hf0f0f0f0, 32'hffff8000, 32'h00001e1e, 32'h00000000, 32'hfffff0f0, 32'hf0f0f0f0 ); // -252645136/-32768        ,       7710,          0,      -3856, 4042322160
      check_mem_results( 21,20, 32'hf0f0f0f0, 32'h01010101, 32'hfffffff1, 32'h000000f0, 32'hffffffff, 32'h00000000 ); // -252645136/16843009      ,        -15,        240,         -1,          0
      check_mem_results( 21,21, 32'hf0f0f0f0, 32'hf0f0f0f0, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -252645136/-252645136    ,          1,          1,          0,          0
      check_mem_results( 21,22, 32'hf0f0f0f0, 32'hdeadbeef, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h12433201 ); // -252645136/-559038737    ,          0,          1, -252645136,  306393601
      check_mem_results( 21,23, 32'hf0f0f0f0, 32'hcafebabe, 32'h00000000, 32'h00000001, 32'hf0f0f0f0, 32'h25f23632 ); // -252645136/-889275714    ,          0,          1, -252645136,  636630578

      check_mem_results( 22, 0, 32'hdeadbeef, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'hdeadbeef, 32'hdeadbeef ); // -559038737/0             ,         -1, 4294967295, -559038737, 3735928559
      check_mem_results( 22, 1, 32'hdeadbeef, 32'h00000001, 32'hdeadbeef, 32'hdeadbeef, 32'h00000000, 32'h00000000 ); // -559038737/1             , -559038737, 3735928559,          0,          0
      check_mem_results( 22, 2, 32'hdeadbeef, 32'hffffffff, 32'h21524111, 32'h00000000, 32'h00000000, 32'hdeadbeef ); // -559038737/-1            ,  559038737,          0,          0, 3735928559
      check_mem_results( 22, 3, 32'hdeadbeef, 32'h00000002, 32'hef56df78, 32'h6f56df77, 32'hffffffff, 32'h00000001 ); // -559038737/2             , -279519368, 1867964279,         -1,          1
      check_mem_results( 22, 4, 32'hdeadbeef, 32'hfffffffe, 32'h10a92088, 32'h00000000, 32'hffffffff, 32'hdeadbeef ); // -559038737/-2            ,  279519368,          0,         -1, 3735928559
      check_mem_results( 22, 5, 32'hdeadbeef, 32'h7fffffff, 32'h00000000, 32'h00000001, 32'hdeadbeef, 32'h5eadbef0 ); // -559038737/2147483647    ,          0,          1, -559038737, 1588444912
      check_mem_results( 22, 6, 32'hdeadbeef, 32'h80000000, 32'h00000000, 32'h00000001, 32'hdeadbeef, 32'h5eadbeef ); // -559038737/-2147483648   ,          0,          1, -559038737, 1588444911
      check_mem_results( 22, 7, 32'hdeadbeef, 32'h80000001, 32'h00000000, 32'h00000001, 32'hdeadbeef, 32'h5eadbeee ); // -559038737/-2147483647   ,          0,          1, -559038737, 1588444910
      check_mem_results( 22, 8, 32'hdeadbeef, 32'h12345678, 32'hffffffff, 32'h0000000c, 32'hf0e21567, 32'h0439b14f ); // -559038737/305419896     ,         -1,         12, -253618841,   70889807
      check_mem_results( 22, 9, 32'hdeadbeef, 32'h87654321, 32'h00000000, 32'h00000001, 32'hdeadbeef, 32'h57487bce ); // -559038737/-2023406815   ,          0,          1, -559038737, 1464368078
      check_mem_results( 22,10, 32'hdeadbeef, 32'h0000ffff, 32'hffffdeae, 32'h0000deae, 32'hffff9d9d, 32'h00009d9d ); // -559038737/65535         ,      -8530,      57006,     -25187,      40349
      check_mem_results( 22,11, 32'hdeadbeef, 32'hffff0000, 32'h00002152, 32'h00000000, 32'hffffbeef, 32'hdeadbeef ); // -559038737/-65536        ,       8530,          0,     -16657, 3735928559
      check_mem_results( 22,12, 32'hdeadbeef, 32'h40000000, 32'h00000000, 32'h00000003, 32'hdeadbeef, 32'h1eadbeef ); // -559038737/1073741824    ,          0,          3, -559038737,  514703087
      check_mem_results( 22,13, 32'hdeadbeef, 32'hc0000000, 32'h00000000, 32'h00000001, 32'hdeadbeef, 32'h1eadbeef ); // -559038737/-1073741824   ,          0,          1, -559038737,  514703087
      check_mem_results( 22,14, 32'hdeadbeef, 32'h7f7f7f7f, 32'h00000000, 32'h00000001, 32'hdeadbeef, 32'h5f2e3f70 ); // -559038737/2139062143    ,          0,          1, -559038737, 1596866416
      check_mem_results( 22,15, 32'hdeadbeef, 32'h80808080, 32'h00000000, 32'h00000001, 32'hdeadbeef, 32'h5e2d3e6f ); // -559038737/-2139062144   ,          0,          1, -559038737, 1580023407
      check_mem_results( 22,16, 32'hdeadbeef, 32'h13579bdf, 32'hffffffff, 32'h0000000b, 32'hf2055ace, 32'h09ea0c5a ); // -559038737/324508639     ,         -1,         11, -234530098,  166333530
      check_mem_results( 22,17, 32'hdeadbeef, 32'h2468ace0, 32'h00000000, 32'h00000006, 32'hdeadbeef, 32'h0439b1af ); // -559038737/610839776     ,          0,          6, -559038737,   70889903
      check_mem_results( 22,18, 32'hdeadbeef, 32'h00007fff, 32'hffffbd5b, 32'h0001bd5e, 32'hfffffc4a, 32'h00007c4d ); // -559038737/32767         ,     -17061,     114014,       -950,      31821
      check_mem_results( 22,19, 32'hdeadbeef, 32'hffff8000, 32'h000042a4, 32'h00000000, 32'hffffbeef, 32'hdeadbeef ); // -559038737/-32768        ,      17060,          0,     -16657, 3735928559
      check_mem_results( 22,20, 32'hdeadbeef, 32'h01010101, 32'hffffffdf, 32'h000000dd, 32'hffcee010, 32'h00cfe112 ); // -559038737/16843009      ,        -33,        221,   -3219440,   13623570
      check_mem_results( 22,21, 32'hdeadbeef, 32'hf0f0f0f0, 32'h00000002, 32'h00000000, 32'hfccbdd0f, 32'hdeadbeef ); // -559038737/-252645136    ,          2,          0,  -53748465, 3735928559
      check_mem_results( 22,22, 32'hdeadbeef, 32'hdeadbeef, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -559038737/-559038737    ,          1,          1,          0,          0
      check_mem_results( 22,23, 32'hdeadbeef, 32'hcafebabe, 32'h00000000, 32'h00000001, 32'hdeadbeef, 32'h13af0431 ); // -559038737/-889275714    ,          0,          1, -559038737,  330236977

      check_mem_results( 23, 0, 32'hcafebabe, 32'h00000000, 32'hffffffff, 32'hffffffff, 32'hcafebabe, 32'hcafebabe ); // -889275714/0             ,         -1, 4294967295, -889275714, 3405691582
      check_mem_results( 23, 1, 32'hcafebabe, 32'h00000001, 32'hcafebabe, 32'hcafebabe, 32'h00000000, 32'h00000000 ); // -889275714/1             , -889275714, 3405691582,          0,          0
      check_mem_results( 23, 2, 32'hcafebabe, 32'hffffffff, 32'h35014542, 32'h00000000, 32'h00000000, 32'hcafebabe ); // -889275714/-1            ,  889275714,          0,          0, 3405691582
      check_mem_results( 23, 3, 32'hcafebabe, 32'h00000002, 32'he57f5d5f, 32'h657f5d5f, 32'h00000000, 32'h00000000 ); // -889275714/2             , -444637857, 1702845791,          0,          0
      check_mem_results( 23, 4, 32'hcafebabe, 32'hfffffffe, 32'h1a80a2a1, 32'h00000000, 32'h00000000, 32'hcafebabe ); // -889275714/-2            ,  444637857,          0,          0, 3405691582
      check_mem_results( 23, 5, 32'hcafebabe, 32'h7fffffff, 32'h00000000, 32'h00000001, 32'hcafebabe, 32'h4afebabf ); // -889275714/2147483647    ,          0,          1, -889275714, 1258207935
      check_mem_results( 23, 6, 32'hcafebabe, 32'h80000000, 32'h00000000, 32'h00000001, 32'hcafebabe, 32'h4afebabe ); // -889275714/-2147483648   ,          0,          1, -889275714, 1258207934
      check_mem_results( 23, 7, 32'hcafebabe, 32'h80000001, 32'h00000000, 32'h00000001, 32'hcafebabe, 32'h4afebabd ); // -889275714/-2147483647   ,          0,          1, -889275714, 1258207933
      check_mem_results( 23, 8, 32'hcafebabe, 32'h12345678, 32'hfffffffe, 32'h0000000b, 32'hef6767ae, 32'h02bf0396 ); // -889275714/305419896     ,         -2,         11, -278435922,   46072726
      check_mem_results( 23, 9, 32'hcafebabe, 32'h87654321, 32'h00000000, 32'h00000001, 32'hcafebabe, 32'h4399779d ); // -889275714/-2023406815   ,          0,          1, -889275714, 1134131101
      check_mem_results( 23,10, 32'hcafebabe, 32'h0000ffff, 32'hffffcaff, 32'h0000caff, 32'hffff85bd, 32'h000085bd ); // -889275714/65535         ,     -13569,      51967,     -31299,      34237
      check_mem_results( 23,11, 32'hcafebabe, 32'hffff0000, 32'h00003501, 32'h00000000, 32'hffffbabe, 32'hcafebabe ); // -889275714/-65536        ,      13569,          0,     -17730, 3405691582
      check_mem_results( 23,12, 32'hcafebabe, 32'h40000000, 32'h00000000, 32'h00000003, 32'hcafebabe, 32'h0afebabe ); // -889275714/1073741824    ,          0,          3, -889275714,  184466110
      check_mem_results( 23,13, 32'hcafebabe, 32'hc0000000, 32'h00000000, 32'h00000001, 32'hcafebabe, 32'h0afebabe ); // -889275714/-1073741824   ,          0,          1, -889275714,  184466110
      check_mem_results( 23,14, 32'hcafebabe, 32'h7f7f7f7f, 32'h00000000, 32'h00000001, 32'hcafebabe, 32'h4b7f3b3f ); // -889275714/2139062143    ,          0,          1, -889275714, 1266629439
      check_mem_results( 23,15, 32'hcafebabe, 32'h80808080, 32'h00000000, 32'h00000001, 32'hcafebabe, 32'h4a7e3a3e ); // -889275714/-2139062144   ,          0,          1, -889275714, 1249786430
      check_mem_results( 23,16, 32'hcafebabe, 32'h13579bdf, 32'hfffffffe, 32'h0000000a, 32'hf1adf27c, 32'h0992a408 ); // -889275714/324508639     ,         -2,         10, -240258436,  160605192
      check_mem_results( 23,17, 32'hcafebabe, 32'h2468ace0, 32'hffffffff, 32'h00000005, 32'hef67679e, 32'h14f35a5e ); // -889275714/610839776     ,         -1,          5, -278435938,  351492702
      check_mem_results( 23,18, 32'hcafebabe, 32'h00007fff, 32'hffff95fd, 32'h00019600, 32'hffffd0bb, 32'h000050be ); // -889275714/32767         ,     -27139,     103936,     -12101,      20670
      check_mem_results( 23,19, 32'hcafebabe, 32'hffff8000, 32'h00006a02, 32'h00000000, 32'hffffbabe, 32'hcafebabe ); // -889275714/-32768        ,      27138,          0,     -17730, 3405691582
      check_mem_results( 23,20, 32'hcafebabe, 32'h01010101, 32'hffffffcc, 32'h000000ca, 32'hff32eef2, 32'h0033eff4 ); // -889275714/16843009      ,        -52,        202,  -13439246,    3403764
      check_mem_results( 23,21, 32'hcafebabe, 32'hf0f0f0f0, 32'h00000003, 32'h00000000, 32'hf82be7ee, 32'hcafebabe ); // -889275714/-252645136    ,          3,          0, -131340306, 3405691582
      check_mem_results( 23,22, 32'hcafebabe, 32'hdeadbeef, 32'h00000001, 32'h00000000, 32'hec50fbcf, 32'hcafebabe ); // -889275714/-559038737    ,          1,          0, -330236977, 3405691582
      check_mem_results( 23,23, 32'hcafebabe, 32'hcafebabe, 32'h00000001, 32'h00000001, 32'h00000000, 32'h00000000 ); // -889275714/-889275714    ,          1,          1,          0,          0

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

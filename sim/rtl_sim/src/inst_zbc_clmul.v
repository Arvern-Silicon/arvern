//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zbc_clmul
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CLMUL/CLMULH/CLMULR (Zbc)
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Function to compute expected carry-less multiply (CLMUL)
function [31:0] clmul_expected;
   input [31:0] a;
   input [31:0] b;
   integer i;
   reg [31:0] result;
   begin
      result = 32'h0;
      for (i = 0; i < 32; i = i + 1) begin
         if (b[i])
            result = result ^ (a << i);
      end
      clmul_expected = result;
   end
endfunction

// Function to compute expected CLMULH
function [31:0] clmulh_expected;
   input [31:0] a;
   input [31:0] b;
   integer i;
   reg [31:0] result;
   begin
      result = 32'h0;
      for (i = 1; i < 32; i = i + 1) begin
         if (b[i])
            result = result ^ (a >> (32 - i));
      end
      clmulh_expected = result;
   end
endfunction

// Function to compute expected CLMULR
function [31:0] clmulr_expected;
   input [31:0] a;
   input [31:0] b;
   integer i;
   reg [31:0] result;
   begin
      result = 32'h0;
      for (i = 0; i < 32; i = i + 1) begin
         if (b[i])
            result = result ^ (a >> (31 - i));
      end
      clmulr_expected = result;
   end
endfunction

// Check carry-less multiply results for a given iteration
task check_mem_results;
   input integer i;
   input integer j;
   input integer exp_op1;
   input integer exp_op2;

   integer mem_op1;
   integer mem_op2;
   integer mem_result_clmul;
   integer mem_result_clmulh;
   integer mem_result_clmulr;
   integer exp_result_clmul;
   integer exp_result_clmulh;
   integer exp_result_clmulr;
   integer error_before;
   begin
      mem_op1           = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[5*(16*i+j) + 0];
      mem_op2           = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[5*(16*i+j) + 1];
      mem_result_clmul  = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[5*(16*i+j) + 2];
      mem_result_clmulh = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[5*(16*i+j) + 3];
      mem_result_clmulr = tb_arvern.ahb_bus_system_inst.sram_nx_inst.mem[5*(16*i+j) + 4];

      // Compute expected results
      exp_result_clmul  = clmul_expected(exp_op1, exp_op2);
      exp_result_clmulh = clmulh_expected(exp_op1, exp_op2);
      exp_result_clmulr = clmulr_expected(exp_op1, exp_op2);

      error_before = error;
      $display("========== i=%0d j=%0d ==========",i, j);
      $display("Expected --> %h*%h -- CLMUL=%h CLMULH=%h CLMULR=%h", exp_op1, exp_op2, exp_result_clmul, exp_result_clmulh, exp_result_clmulr);
      $display("Got      --> %h*%h -- CLMUL=%h CLMULH=%h CLMULR=%h", mem_op1, mem_op2, mem_result_clmul, mem_result_clmulh, mem_result_clmulr);

      if ((exp_op1!==mem_op1) || (exp_op2!==mem_op2)) begin
         $display("                                                                                            ERROR: Operands are not matching. Issue in testbench.");
         error = error+1;
      end
      if (exp_result_clmul!==mem_result_clmul) begin
         $display("                                                                                            ERROR: wrong CLMUL result");
         error = error+1;
      end
      if (exp_result_clmulh!==mem_result_clmulh) begin
         $display("                                                                                            ERROR: wrong CLMULH result");
         error = error+1;
      end
      if (exp_result_clmulr!==mem_result_clmulr) begin
         $display("                                                                                            ERROR: wrong CLMULR result");
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

      $display("");
      $display(" ================================================================================");
      $display("|      CHECK MEMORY VALUES AFTER THE CLMUL/CLMULH/CLMULR TESTS                   |");
      $display(" ================================================================================");

      // Check all 16x16 test combinations
      for (ii = 0; ii < 16; ii = ii + 1) begin
         for (jj = 0; jj < 16; jj = jj + 1) begin
            case (ii)
               0: case (jj)
                  0: check_mem_results(ii, jj, 32'h00000000, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h00000000, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h00000000, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h00000000, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h00000000, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h00000000, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h00000000, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h00000000, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h00000000, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h00000000, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h00000000, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h00000000, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h00000000, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h00000000, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h00000000, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h00000000, 32'habcdef01);
               endcase
               1: case (jj)
                  0: check_mem_results(ii, jj, 32'h00000001, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h00000001, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h00000001, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h00000001, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h00000001, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h00000001, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h00000001, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h00000001, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h00000001, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h00000001, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h00000001, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h00000001, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h00000001, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h00000001, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h00000001, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h00000001, 32'habcdef01);
               endcase
               2: case (jj)
                  0: check_mem_results(ii, jj, 32'hffffffff, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'hffffffff, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'hffffffff, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'hffffffff, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'hffffffff, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'hffffffff, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'hffffffff, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'hffffffff, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'hffffffff, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'hffffffff, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'hffffffff, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'hffffffff, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'hffffffff, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'hffffffff, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'hffffffff, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'hffffffff, 32'habcdef01);
               endcase
               3: case (jj)
                  0: check_mem_results(ii, jj, 32'h00000002, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h00000002, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h00000002, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h00000002, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h00000002, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h00000002, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h00000002, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h00000002, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h00000002, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h00000002, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h00000002, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h00000002, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h00000002, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h00000002, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h00000002, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h00000002, 32'habcdef01);
               endcase
               4: case (jj)
                  0: check_mem_results(ii, jj, 32'h00000003, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h00000003, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h00000003, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h00000003, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h00000003, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h00000003, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h00000003, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h00000003, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h00000003, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h00000003, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h00000003, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h00000003, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h00000003, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h00000003, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h00000003, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h00000003, 32'habcdef01);
               endcase
               5: case (jj)
                  0: check_mem_results(ii, jj, 32'h0000000f, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h0000000f, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h0000000f, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h0000000f, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h0000000f, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h0000000f, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h0000000f, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h0000000f, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h0000000f, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h0000000f, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h0000000f, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h0000000f, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h0000000f, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h0000000f, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h0000000f, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h0000000f, 32'habcdef01);
               endcase
               6: case (jj)
                  0: check_mem_results(ii, jj, 32'h80000000, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h80000000, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h80000000, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h80000000, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h80000000, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h80000000, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h80000000, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h80000000, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h80000000, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h80000000, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h80000000, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h80000000, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h80000000, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h80000000, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h80000000, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h80000000, 32'habcdef01);
               endcase
               7: case (jj)
                  0: check_mem_results(ii, jj, 32'h12345678, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h12345678, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h12345678, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h12345678, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h12345678, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h12345678, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h12345678, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h12345678, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h12345678, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h12345678, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h12345678, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h12345678, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h12345678, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h12345678, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h12345678, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h12345678, 32'habcdef01);
               endcase
               8: case (jj)
                  0: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'haaaaaaaa, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'haaaaaaaa, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'haaaaaaaa, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'haaaaaaaa, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'haaaaaaaa, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'haaaaaaaa, 32'habcdef01);
               endcase
               9: case (jj)
                  0: check_mem_results(ii, jj, 32'h55555555, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h55555555, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h55555555, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h55555555, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h55555555, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h55555555, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h55555555, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h55555555, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h55555555, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h55555555, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h55555555, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h55555555, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h55555555, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h55555555, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h55555555, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h55555555, 32'habcdef01);
               endcase
               10: case (jj)
                  0: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'hf0f0f0f0, 32'habcdef01);
               endcase
               11: case (jj)
                  0: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h0f0f0f0f, 32'habcdef01);
               endcase
               12: case (jj)
                  0: check_mem_results(ii, jj, 32'hdeadbeef, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'hdeadbeef, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'hdeadbeef, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'hdeadbeef, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'hdeadbeef, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'hdeadbeef, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'hdeadbeef, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'hdeadbeef, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'hdeadbeef, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'hdeadbeef, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'hdeadbeef, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'hdeadbeef, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'hdeadbeef, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'hdeadbeef, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'hdeadbeef, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'hdeadbeef, 32'habcdef01);
               endcase
               13: case (jj)
                  0: check_mem_results(ii, jj, 32'h00000010, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h00000010, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h00000010, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h00000010, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h00000010, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h00000010, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h00000010, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h00000010, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h00000010, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h00000010, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h00000010, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h00000010, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h00000010, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h00000010, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h00000010, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h00000010, 32'habcdef01);
               endcase
               14: case (jj)
                  0: check_mem_results(ii, jj, 32'h000000ff, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'h000000ff, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'h000000ff, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'h000000ff, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'h000000ff, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'h000000ff, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'h000000ff, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'h000000ff, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'h000000ff, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'h000000ff, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'h000000ff, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'h000000ff, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'h000000ff, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'h000000ff, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'h000000ff, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'h000000ff, 32'habcdef01);
               endcase
               15: case (jj)
                  0: check_mem_results(ii, jj, 32'habcdef01, 32'h00000000);
                  1: check_mem_results(ii, jj, 32'habcdef01, 32'h00000001);
                  2: check_mem_results(ii, jj, 32'habcdef01, 32'hffffffff);
                  3: check_mem_results(ii, jj, 32'habcdef01, 32'h00000002);
                  4: check_mem_results(ii, jj, 32'habcdef01, 32'h00000003);
                  5: check_mem_results(ii, jj, 32'habcdef01, 32'h0000000f);
                  6: check_mem_results(ii, jj, 32'habcdef01, 32'h80000000);
                  7: check_mem_results(ii, jj, 32'habcdef01, 32'h12345678);
                  8: check_mem_results(ii, jj, 32'habcdef01, 32'haaaaaaaa);
                  9: check_mem_results(ii, jj, 32'habcdef01, 32'h55555555);
                  10: check_mem_results(ii, jj, 32'habcdef01, 32'hf0f0f0f0);
                  11: check_mem_results(ii, jj, 32'habcdef01, 32'h0f0f0f0f);
                  12: check_mem_results(ii, jj, 32'habcdef01, 32'hdeadbeef);
                  13: check_mem_results(ii, jj, 32'habcdef01, 32'h00000010);
                  14: check_mem_results(ii, jj, 32'habcdef01, 32'h000000ff);
                  15: check_mem_results(ii, jj, 32'habcdef01, 32'habcdef01);
               endcase
            endcase
         end
      end

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

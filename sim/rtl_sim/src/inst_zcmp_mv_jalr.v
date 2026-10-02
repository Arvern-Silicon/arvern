//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcmp_mv_jalr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CM.MVSA01 / CM.MVA01S result used as the base of an
//              IMMEDIATELY following indirect jump (c.jr / jalr / c.jalr).
//
// Result encodings (N = case number), see the .s file:
//   0x1111000N  intended target reached
//   0x2222000N  the other move destination's target reached
//   0xBAD0000N  FAIL pad reached (stale preload value used as jump base)
//   0xBAD0F00N  fell through, no jump happened
//   ra check:   0x600D000N correct / 0xBADBAD0N wrong
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
      $display("|       CHECK INITIAL REGISTER VALUES (CM.MVxx -> JR HAZARD TEST)    |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for initial firmware setup...");

      @(probes_cpu.x31==32'hFFFFFFFF);

      check_cpu_reg(2,  32'h80001000);
      check_cpu_reg(12, 32'h00000000);
      check_cpu_reg(13, 32'h00000000);
      check_cpu_reg(24, 32'h00000000);
      check_cpu_reg(25, 32'h00000000);
      check_cpu_reg(26, 32'h00000000);
      check_cpu_reg(27, 32'h00000000);
      check_cpu_reg(28, 32'h00000000);
      check_cpu_reg(29, 32'h00000000);
      check_cpu_reg(30, 32'h00000000);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|     CHECK RESULTS: MOVE RESULT AS BASE OF BACK-TO-BACK JUMP        |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for test completion...");
      @(probes_cpu.x31==32'hDEADBEEF);

      random_irq_enable = 0;

      $display("");
      $display("Case 1: cm.mvsa01 s0,s1 ; c.jr s0");
      check_cpu_reg(24, 32'h11110001);

      $display("");
      $display("Case 2: cm.mvsa01 s0,s1 ; c.jr s1");
      check_cpu_reg(25, 32'h11110002);

      $display("");
      $display("Case 3: cm.mva01s s0,s1 ; c.jr a0");
      check_cpu_reg(26, 32'h11110003);

      $display("");
      $display("Case 4: cm.mva01s s0,s1 ; c.jr a1");
      check_cpu_reg(27, 32'h11110004);

      $display("");
      $display("Case 5: cm.mvsa01 s0,s1 ; jalr ra,0(s0) (32-bit) + ra check");
      check_cpu_reg(28, 32'h11110005);
      check_cpu_reg(12, 32'h600D0005);

      $display("");
      $display("Case 6: cm.mva01s s0,s1 ; c.jalr a0 + ra check");
      check_cpu_reg(29, 32'h11110006);
      check_cpu_reg(13, 32'h600D0006);

      $display("");
      $display("Case 7 (control): cm.mvsa01 s0,s1 ; addi ; c.jr s0");
      check_cpu_reg(30, 32'h11110007);
      check_cpu_reg(5,  32'h00000001);

      // sp must be untouched by all of the above
      check_cpu_reg(2,  32'h80001000);

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

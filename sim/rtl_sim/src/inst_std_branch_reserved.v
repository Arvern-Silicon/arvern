//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_branch_reserved
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: RESERVED BRANCH FUNCT3 -> ILLEGAL
//   Verifies BRANCH funct3=010 and funct3=011 each raise illegal-instruction
//   (mcause=2), while a correctly-encoded BEQ/BNE executes normally.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Two reserved BRANCH encodings are expected to trap.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init
      //=================================================================
      $display("");
      $display(" PHASE 1: init");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // illegal_count
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // other_count


      //=================================================================
      // PHASE 2: BRANCH funct3=010 reserved -> mcause=2
      //=================================================================
      $display("");
      $display(" PHASE 2: BRANCH funct3=010 (0x00202063)");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // illegal_count = 1
      check_mem_value(`SPAD(32'h08), 32'h00000002);   // MCAUSE = 2
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // no other trap


      //=================================================================
      // PHASE 3: BRANCH funct3=011 reserved -> mcause=2
      //=================================================================
      $display("");
      $display(" PHASE 3: BRANCH funct3=011 (0x00203063)");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // illegal_count = 2
      check_mem_value(`SPAD(32'h08), 32'h00000002);   // MCAUSE = 2
      check_mem_value(`SPAD(32'h04), 32'h00000000);


      //=================================================================
      // PHASE 4: POSITIVE CONTROL -- real BEQ taken
      //=================================================================
      $display("");
      $display(" PHASE 4: real BEQ taken (positive control)");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // still 2 (no new trap)
      check_cpu_reg(18, 32'h00000001);                // BEQ-taken proof


      //=================================================================
      // PHASE 5: POSITIVE CONTROL -- real BNE taken
      //=================================================================
      $display("");
      $display(" PHASE 5: real BNE taken (positive control)");
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // still 2
      check_cpu_reg(19, 32'h00000001);                // BNE-taken proof


      //=================================================================
      // PHASE 6: POSITIVE CONTROL -- real BEQ not taken (+ end)
      //=================================================================
      $display("");
      $display(" PHASE 6: real BEQ not taken (positive control)");
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // still 2
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // never any other trap
      check_cpu_reg(20, 32'h00000001);                // BEQ-not-taken proof


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_m_illegal_nom
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: M EXTENSION ABSENT -> ILLEGAL
//   Requires M_EXTENSION==0. Every M-extension OP-REG encoding (funct7=01,
//   funct3 in {000..111}) must trap as illegal instruction and leave rd
//   untouched.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

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

      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init
      //=================================================================
      $display("");
      $display(" PHASE 1: init");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // PHASE 2: MUL t0 -> illegal, t0 preserved
      //=================================================================
      $display("");
      $display(" PHASE 2: MUL (funct3=000)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000001);                  // trap_count
      check_mem_value(`SPAD(32'h04), 32'h00000002);                  // MCAUSE=2
      check_mem_value(`SPAD(32'h20), 32'hAAAAAAA1);                  // t0 preserved


      //=================================================================
      // PHASE 3: MULH t1
      //=================================================================
      $display("");
      $display(" PHASE 3: MULH (funct3=001)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000002);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h30), 32'hBBBBBBB2);


      //=================================================================
      // PHASE 4: MULHSU t2
      //=================================================================
      $display("");
      $display(" PHASE 4: MULHSU (funct3=010)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000003);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h40), 32'hCCCCCCC3);


      //=================================================================
      // PHASE 5: MULHU t3
      //=================================================================
      $display("");
      $display(" PHASE 5: MULHU (funct3=011)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000004);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h50), 32'hDDDDDDD4);


      //=================================================================
      // PHASE 6: DIV t4
      //=================================================================
      $display("");
      $display(" PHASE 6: DIV (funct3=100)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000005);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h60), 32'hEEEEEEE5);


      //=================================================================
      // PHASE 7: DIVU t5
      //=================================================================
      $display("");
      $display(" PHASE 7: DIVU (funct3=101)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000006);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h70), 32'hFFFFFFF6);


      //=================================================================
      // PHASE 8: REM t6
      //=================================================================
      $display("");
      $display(" PHASE 8: REM (funct3=110)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h88888888);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000007);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h80), 32'h11111117);


      //=================================================================
      // PHASE 9: REMU a2
      //=================================================================
      $display("");
      $display(" PHASE 9: REMU (funct3=111)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000008);
      check_mem_value(`SPAD(32'h04), 32'h00000002);
      check_mem_value(`SPAD(32'h90), 32'h22222228);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

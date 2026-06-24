//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ifault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IFAULT EXCEPTION
//   Instruction access fault triggered by IF-stage fetch to unmapped address:
//   - JAL to unmapped ROM address (MCAUSE = 1)
//   - JALR to unmapped address via register (MCAUSE = 1)
//   - Handler redirects MEPC to recovery label for each case
//   - Register preservation across exceptions
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
      // PHASE 1: Initialization
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: Instruction access fault via JALR to 0x30000000
      //          (MCAUSE = 1)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: INSTRUCTION ACCESS FAULT (JALR to 0x30000000, MCAUSE=1) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000001);

      $display("");
      $display("--- MEPC verification (expect unmapped target address 0x30000000) ---");
      check_mem_value(`SPAD(32'h24), 32'h30000000);

      $display("");
      $display("--- MTVAL verification (expect faulting address 0x30000000) ---");
      check_mem_value(`SPAD(32'h28), 32'h30000000);


      //=================================================================
      // PHASE 3: Instruction access fault via JALR to 0x40000000
      //          (MCAUSE = 1)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: INSTRUCTION ACCESS FAULT (JALR to 0x40000000, MCAUSE=1) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000001);

      $display("");
      $display("--- MEPC verification (expect unmapped target address 0x40000000) ---");
      check_mem_value(`SPAD(32'h34), 32'h40000000);

      $display("");
      $display("--- MTVAL verification (expect faulting address 0x40000000) ---");
      check_mem_value(`SPAD(32'h38), 32'h40000000);


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after 2 instruction access faults ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_inst_addr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: INST ADDR MISALIGNED
//   Synchronous exception verification:
//   - Instruction address misaligned (MCAUSE = 0)
//   - STD mode only (without C extension, non-4-byte-aligned PC faults)
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


      //=================================================================
      // PHASE 2: Instruction address misaligned via JALR to 0x20000002
      //          (MCAUSE = 0)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|    PHASE 2: INSTRUCTION ADDRESS MISALIGNED (addr 0x20000002)       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE verification (instruction address misaligned) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000000);

      $display("");
      $display("--- MEPC verification (= PC of the JALR, per RISC-V spec) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)], $time);
      end

      $display("");
      $display("--- MTVAL verification (= misaligned target 0x20000002) ---");
      check_mem_value(`SPAD(32'h2C), 32'h20000002);


      //=================================================================
      // PHASE 3: Instruction address misaligned via JALR to 0x20000006
      //          (MCAUSE = 0)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|    PHASE 3: INSTRUCTION ADDRESS MISALIGNED (addr 0x20000006)       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- MCAUSE verification (instruction address misaligned) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000000);

      $display("");
      $display("--- MEPC verification (= PC of the JALR, per RISC-V spec) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)], $time);
      end

      $display("");
      $display("--- MTVAL verification (= misaligned target 0x20000006) ---");
      check_mem_value(`SPAD(32'h3C), 32'h20000006);

      // Final register preservation
      $display("");
      $display("--- Register preservation after 2 exceptions ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

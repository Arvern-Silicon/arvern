//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_priority
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: EXCEPTION PRIORITY
//   Verify exception priority when multiple exceptions could fire:
//   - Misaligned load to valid addr       (MCAUSE=4)
//   - Misaligned load to unmapped addr    (MCAUSE=4, not 5)
//   - Aligned load to unmapped addr       (MCAUSE=5)
//   - Misaligned store to valid addr      (MCAUSE=6)
//   - Misaligned store to unmapped addr   (MCAUSE=6, not 7)
//   - Aligned store to unmapped addr      (MCAUSE=7)
//   - Illegal instruction                 (MCAUSE=2)
//
//   Key: misalignment (EX stage) has priority over access fault (WB stage)
//   because the EX exception kills the instruction before WB.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  (byte_off/4)

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

      // Disable error-on-exception (all tests trigger exceptions)
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
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

      // Verify scratchpad is zeroed (trap_count should be 0)
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      // Check callee-saved registers
      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: Load misaligned to valid address (MCAUSE=4)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 2: LOAD MISALIGNED TO VALID ADDRESS                   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 1
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // Check MCAUSE = 4 (load address misaligned)
      $display("");
      $display("--- MCAUSE verification (load misaligned, valid addr) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000004);

      // Check MTVAL = 0x80000001 (faulting misaligned address)
      $display("");
      $display("--- MTVAL verification (expect 0x80000001) ---");
      check_mem_value(`SPAD(32'h24), 32'h80000001);


      //=================================================================
      // PHASE 3: Load misaligned to unmapped address (MCAUSE=4, NOT 5)
      //          This is the key priority test: misalignment (EX) wins
      //          over access fault (WB).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: LOAD MISALIGNED TO UNMAPPED ADDR (PRIORITY: 4 not 5)    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 2
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      // Check MCAUSE = 4 (misaligned wins over access fault)
      $display("");
      $display("--- MCAUSE verification (expect 4=misaligned, NOT 5=access fault) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000004);

      // Check MTVAL = 0x10000001 (faulting address)
      $display("");
      $display("--- MTVAL verification (expect 0x10000001) ---");
      check_mem_value(`SPAD(32'h34), 32'h10000001);


      //=================================================================
      // PHASE 4: Load aligned to unmapped address (MCAUSE=5)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 4: LOAD ACCESS FAULT (ALIGNED, UNMAPPED)              |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 3
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      // Check MCAUSE = 5 (load access fault)
      $display("");
      $display("--- MCAUSE verification (load access fault) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000005);

      // Check MTVAL = 0x10000000 (faulting address)
      $display("");
      $display("--- MTVAL verification (expect 0x10000000) ---");
      check_mem_value(`SPAD(32'h44), 32'h10000000);


      //=================================================================
      // PHASE 5: Store misaligned to valid address (MCAUSE=6)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 5: STORE MISALIGNED TO VALID ADDRESS                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 4
      check_mem_value(`SPAD(32'h00), 32'h00000004);

      // Check MCAUSE = 6 (store address misaligned)
      $display("");
      $display("--- MCAUSE verification (store misaligned, valid addr) ---");
      check_mem_value(`SPAD(32'h50), 32'h00000006);

      // Check MTVAL = 0x80000003 (faulting misaligned address)
      $display("");
      $display("--- MTVAL verification (expect 0x80000003) ---");
      check_mem_value(`SPAD(32'h54), 32'h80000003);


      //=================================================================
      // PHASE 6: Store misaligned to unmapped address (MCAUSE=6, NOT 7)
      //          This is the key priority test: misalignment (EX) wins
      //          over access fault (WB).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("| PHASE 6: STORE MISALIGNED TO UNMAPPED ADDR (PRIORITY: 6 not 7)    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 5
      check_mem_value(`SPAD(32'h00), 32'h00000005);

      // Check MCAUSE = 6 (misaligned wins over access fault)
      $display("");
      $display("--- MCAUSE verification (expect 6=misaligned, NOT 7=access fault) ---");
      check_mem_value(`SPAD(32'h60), 32'h00000006);

      // Check MTVAL = 0x10000003 (faulting address)
      $display("");
      $display("--- MTVAL verification (expect 0x10000003) ---");
      check_mem_value(`SPAD(32'h64), 32'h10000003);


      //=================================================================
      // PHASE 7: Store aligned to unmapped address (MCAUSE=7)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 7: STORE ACCESS FAULT (ALIGNED, UNMAPPED)             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 6
      check_mem_value(`SPAD(32'h00), 32'h00000006);

      // Check MCAUSE = 7 (store access fault)
      $display("");
      $display("--- MCAUSE verification (store access fault) ---");
      check_mem_value(`SPAD(32'h70), 32'h00000007);

      // Check MTVAL = 0x00000000 (faulting address)
      $display("");
      $display("--- MTVAL verification (expect 0x00000000) ---");
      check_mem_value(`SPAD(32'h74), 32'h00000000);


      //=================================================================
      // PHASE 8: Illegal instruction (MCAUSE=2, MTVAL=0)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 8: ILLEGAL INSTRUCTION                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h88888888);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 7
      check_mem_value(`SPAD(32'h00), 32'h00000007);

      // Check MCAUSE = 2 (illegal instruction)
      $display("");
      $display("--- MCAUSE verification (illegal instruction) ---");
      check_mem_value(`SPAD(32'h80), 32'h00000002);

      // Check MTVAL = 0
      $display("");
      $display("--- MTVAL verification (expect 0) ---");
      check_mem_value(`SPAD(32'h84), 32'h00000000);


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after 7 exceptions ---");
      check_cpu_reg(18, 32'hAAAAAAAA);   // s2
      check_cpu_reg(19, 32'hBBBBBBBB);   // s3
      check_cpu_reg(20, 32'hCCCCCCCC);   // s4
      check_cpu_reg(21, 32'hDDDDDDDD);   // s5
      check_cpu_reg(22, 32'hEEEEEEEE);   // s6


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

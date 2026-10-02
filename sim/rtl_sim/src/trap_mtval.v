//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_mtval
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP MTVAL
//   Verify MTVAL contains the correct value for each exception type:
//   - Illegal instruction    (MCAUSE=2,  MTVAL=0)
//   - Load addr misaligned   (MCAUSE=4,  MTVAL=faulting address)
//   - Store addr misaligned  (MCAUSE=6,  MTVAL=faulting address)
//   - EBREAK                 (MCAUSE=3,  MTVAL=0)
//   - ECALL from M-mode      (MCAUSE=11, MTVAL=0)
//
//   All tests are synchronous exceptions -- no testbench-driven IRQ needed.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  ((byte_off)/4)

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
      // PHASE 2: Illegal instruction (MCAUSE=2, MTVAL=0)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: ILLEGAL INSTRUCTION                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 1
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // Check MCAUSE = 2
      $display("");
      $display("--- MCAUSE verification (illegal instruction) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);

      // Check MTVAL = 0
      $display("");
      $display("--- MTVAL verification (expect 0) ---");
      check_mem_value(`SPAD(32'h24), 32'h00000000);


      //=================================================================
      // PHASE 3: Load address misaligned (MCAUSE=4, MTVAL=0x80000001)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: LOAD ADDRESS MISALIGNED                   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 2
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      // Check MCAUSE = 4
      $display("");
      $display("--- MCAUSE verification (load misaligned) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000004);

      // Check MTVAL = 0x80000001 (faulting misaligned address)
      $display("");
      $display("--- MTVAL verification (expect faulting address 0x80000001) ---");
      check_mem_value(`SPAD(32'h34), 32'h80000001);


      //=================================================================
      // PHASE 4: Store address misaligned (MCAUSE=6, MTVAL=0x80000003)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: STORE ADDRESS MISALIGNED                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 3
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      // Check MCAUSE = 6
      $display("");
      $display("--- MCAUSE verification (store misaligned) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000006);

      // Check MTVAL = 0x80000003 (faulting misaligned address)
      $display("");
      $display("--- MTVAL verification (expect faulting address 0x80000003) ---");
      check_mem_value(`SPAD(32'h44), 32'h80000003);


      //=================================================================
      // PHASES 5 & 6 (load / store ACCESS FAULT) REMOVED -- see the .s.
      // Bus errors are RNMIs and write marv_eaddr, not mtval; covered by
      // trap_nmi_bus_error. mcause 5/7 are RESERVED.
      //=================================================================

      //=================================================================
      // PHASE 5: EBREAK (MCAUSE=3, MTVAL=0)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: EBREAK                                    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 6
      check_mem_value(`SPAD(32'h00), 32'h00000004);

      // Check MCAUSE = 3
      $display("");
      $display("--- MCAUSE verification (EBREAK) ---");
      check_mem_value(`SPAD(32'h70), 32'h00000003);

      // Check MTVAL = 0
      $display("");
      $display("--- MTVAL verification (expect 0) ---");
      check_mem_value(`SPAD(32'h74), 32'h00000000);


      //=================================================================
      // PHASE 6: ECALL from M-mode (MCAUSE=11, MTVAL=0)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 6: ECALL FROM M-MODE                         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 7
      check_mem_value(`SPAD(32'h00), 32'h00000005);

      // Check MCAUSE = 11 (0x0B)
      $display("");
      $display("--- MCAUSE verification (ECALL from M-mode) ---");
      check_mem_value(`SPAD(32'h80), 32'h0000000B);

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

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_drain
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP DRAIN
//   Pipeline drain correctness when a trap occurs during multi-cycle ops:
//   - Timer IRQ during long divide  (pipeline must drain before trap)
//   - Timer IRQ during back-to-back divides
//   - Timer IRQ during multiply
//   - Synchronous exception after divide (load misaligned)
//
//   Verifies that multi-cycle operation results are committed correctly
//   before the trap is taken, and that MCAUSE is set appropriately.
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

      // Disable error-on-exception (interrupts and exceptions trigger exception monitors)
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
      // PHASE 2: Timer IRQ during long divide
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: TIMER IRQ DURING DIVIDE                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      // Wait a couple clocks to catch the divide mid-execution
      repeat(2) @(posedge free_clk);

      // Assert timer interrupt
      irq_m_timer = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Deassert timer interrupt
      irq_m_timer = 1'b0;

      // Check MCAUSE = 0x80000007 (Machine Timer Interrupt)
      $display("");
      $display("--- MCAUSE verification (timer during divide) ---");
      check_mem_value(`SPAD(32'h20), 32'h80000007);

      // Check divide result = 1000 (0x3E8): pipeline drained correctly
      $display("");
      $display("--- Divide result verification (expect 0x3E8 = 1000) ---");
      check_mem_value(`SPAD(32'h24), 32'h000003E8);

      // Also verify via CPU register
      check_cpu_reg(23, 32'h000003E8);  // s7 = x23


      //=================================================================
      // PHASE 3: Timer IRQ during back-to-back divides
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: TIMER IRQ DURING BACK-TO-BACK DIVIDES    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      // Wait 1 clock to maximize overlap with first divide
      repeat(1) @(posedge free_clk);

      // Assert timer interrupt
      irq_m_timer = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Deassert timer interrupt
      irq_m_timer = 1'b0;

      // Check MCAUSE = 0x80000007 (Machine Timer Interrupt)
      $display("");
      $display("--- MCAUSE verification (timer during back-to-back divides) ---");
      check_mem_value(`SPAD(32'h30), 32'h80000007);

      // Check first divide result = 1000 (0x3E8)
      $display("");
      $display("--- First divide result verification (expect 0x3E8 = 1000) ---");
      check_mem_value(`SPAD(32'h34), 32'h000003E8);

      // Check second divide result = 1000 (0x3E8)
      $display("");
      $display("--- Second divide result verification (expect 0x3E8 = 1000) ---");
      check_mem_value(`SPAD(32'h38), 32'h000003E8);

      // Also verify via CPU registers
      check_cpu_reg(23, 32'h000003E8);  // s7 = x23
      check_cpu_reg(24, 32'h000003E8);  // s8 = x24


      //=================================================================
      // PHASE 4: Timer IRQ during multiply
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: TIMER IRQ DURING MULTIPLY                |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h41414141);
      // Wait 1 clock to try to catch multiply mid-execution
      repeat(1) @(posedge free_clk);

      // Assert timer interrupt
      irq_m_timer = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Deassert timer interrupt
      irq_m_timer = 1'b0;

      // Check MCAUSE = 0x80000007 (Machine Timer Interrupt)
      $display("");
      $display("--- MCAUSE verification (timer during multiply) ---");
      check_mem_value(`SPAD(32'h40), 32'h80000007);

      // Check multiply result: 1000000 * 1000 = 1000000000 = 0x3B9ACA00
      $display("");
      $display("--- Multiply result verification (expect 0x3B9ACA00 = 1000000000) ---");
      check_mem_value(`SPAD(32'h44), 32'h3B9ACA00);

      // Also verify via CPU register
      check_cpu_reg(23, 32'h3B9ACA00);  // s7 = x23


      //=================================================================
      // PHASE 5: Synchronous exception after DIV (load misaligned)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: EXCEPTION AFTER DIVIDE (MISALIGNED LOAD) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      // No IRQ needed -- this is a synchronous exception
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      // Check MCAUSE = 4 (Load address misaligned)
      $display("");
      $display("--- MCAUSE verification (load misaligned after divide) ---");
      check_mem_value(`SPAD(32'h50), 32'h00000004);

      // Check divide result = 1000 (0x3E8): divide completed before exception
      $display("");
      $display("--- Divide result verification (expect 0x3E8 = 1000) ---");
      check_mem_value(`SPAD(32'h54), 32'h000003E8);

      // Also verify via CPU register
      check_cpu_reg(23, 32'h000003E8);  // s7 = x23


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after all phases ---");
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

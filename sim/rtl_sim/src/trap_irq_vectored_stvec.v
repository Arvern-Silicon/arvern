//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_vectored_stvec
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IRQ VECTORED STVEC
//   Verify vectored interrupt mode on STVEC for delegated S-mode interrupts:
//   - S-mode vectored timer IRQ from U-mode (vector entry 5)
//   - S-mode exception goes to STVEC BASE (not vectored)
//
//   STIP is set from firmware (no testbench-driven IRQ needed).
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

      // Verify scratchpad is zeroed
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h18), 32'h00000000);

      // Check callee-saved registers
      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: S-mode vectored timer IRQ
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: S-MODE VECTORED TIMER IRQ                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Check SCAUSE = 0x80000005 (S-mode timer interrupt)
      $display("");
      $display("--- SCAUSE verification (S-mode timer interrupt) ---");
      check_mem_value(`SPAD(32'h30), 32'h80000005);

      // Check vector_entry_id = 5 (used vector table entry 5)
      $display("");
      $display("--- Vector entry ID (expect 5 for STI) ---");
      check_mem_value(`SPAD(32'h34), 32'h00000005);

      // Check s_trap_count = 1
      $display("");
      $display("--- S-mode trap count ---");
      check_mem_value(`SPAD(32'h18), 32'h00000001);


      //=================================================================
      // PHASE 3: S-mode exception (not vectored)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: S-MODE EXCEPTION (NOT VECTORED)           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Check SCAUSE = 2 (illegal instruction)
      $display("");
      $display("--- SCAUSE verification (illegal instruction) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000002);

      // Check vector_entry_id = 0 (exceptions go to base, not vectored)
      $display("");
      $display("--- Vector entry ID (expect 0 for exception at base) ---");
      check_mem_value(`SPAD(32'h44), 32'h00000000);

      // Check s_trap_count = 2
      $display("");
      $display("--- S-mode trap count ---");
      check_mem_value(`SPAD(32'h18), 32'h00000002);


      // Check callee-saved registers preserved
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

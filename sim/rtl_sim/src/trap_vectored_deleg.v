//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_vectored_deleg
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP VECTORED DELEG
//   Combined MTVEC + STVEC vectored mode with delegation:
//   - Delegated S-timer from U-mode -> STVEC vectored (cause 5)
//   - Non-delegated M-external from S-mode -> MTVEC vectored (cause 11)
//   - Exception in S-mode -> STVEC BASE (not vectored)
//
//   Phase 3 requires testbench-driven irq_m_external assertion.
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

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: Delegated S-timer from U-mode -> STVEC vectored
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: DELEGATED S-TIMER FROM U-MODE -> STVEC VECTORED         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (expect S-mode timer: 0x80000005) ---");
      check_mem_value(`SPAD(32'h30), 32'h80000005);

      $display("");
      $display("--- S-mode vector entry ID (expect 5 = timer vector) ---");
      check_mem_value(`SPAD(32'h34), 32'h00000005);


      //=================================================================
      // PHASE 3: Non-delegated M-external from S-mode -> MTVEC vectored
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: NON-DELEGATED M-EXTERNAL FROM S-MODE -> MTVEC VECTORED  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(5) @(posedge free_clk);

      // Assert external interrupt
      irq_m_external = 1'b1;

      // Wait for Phase 3 complete
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_external = 1'b0;

      $display("");
      $display("--- MCAUSE verification (expect M-mode external: 0x8000000B) ---");
      check_mem_value(`SPAD(32'h40), 32'h8000000B);

      $display("");
      $display("--- M-mode vector entry ID (expect 11 = external vector) ---");
      check_mem_value(`SPAD(32'h44), 32'h0000000B);


      //=================================================================
      // PHASE 4: Exception in S-mode -> STVEC BASE (not vectored)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: EXCEPTION IN S-MODE -> STVEC BASE (NOT VECTORED)        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (expect illegal instruction: 0x00000002) ---");
      check_mem_value(`SPAD(32'h50), 32'h00000002);

      $display("");
      $display("--- S-mode vector entry ID (expect 0 = base, not vectored) ---");
      check_mem_value(`SPAD(32'h54), 32'h00000000);


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after all phases ---");
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

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_seip
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP IRQ SEIP
//   Verifies that irq_s_external_i (SEIP hardware input) works correctly and
//   is independent from irq_m_external_i (MEIP):
//   - Phase 2: irq_s_external fires -> S-mode trap (delegated SEIP,
//   cause 9) via vectored STVEC
//   - Phase 3: irq_m_external fires -> M-mode trap (non-delegated MEIP,
//   cause 11) via vectored MTVEC; irq_s_external stays low
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
      // PHASE 2: irq_s_external fires -> S-mode trap (delegated SEIP)
      //          SCAUSE = 0x80000009, vector_entry_id = 9
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: IRQ_S_EXTERNAL -> DELEGATED SEIP -> STVEC VECTORED      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware to reach S-mode...");

      @(probes_cpu.x31==32'h21212121);
      repeat(5) @(posedge free_clk);

      // Assert S-mode external interrupt
      irq_s_external = 1'b1;

      // Wait for Phase 2 complete (firmware copies results and signals M-mode)
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_s_external = 1'b0;

      $display("");
      $display("--- SCAUSE verification (expect S-mode external: 0x80000009) ---");
      check_mem_value(`SPAD(32'h30), 32'h80000009);

      $display("");
      $display("--- S-mode vector entry ID (expect 9 = SEI vector) ---");
      check_mem_value(`SPAD(32'h34), 32'h00000009);


      //=================================================================
      // PHASE 3: irq_m_external fires -> M-mode trap (non-delegated MEIP)
      //          MCAUSE = 0x8000000B, vector_entry_id = 11
      //          irq_s_external is NOT asserted during this phase
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: IRQ_M_EXTERNAL -> NON-DELEGATED MEIP -> MTVEC VECTORED  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware to reach S-mode...");

      @(probes_cpu.x31==32'h31313131);
      repeat(5) @(posedge free_clk);

      // Verify irq_s_external is deasserted (independence check)
      if (irq_s_external !== 1'b0) begin
         $display("FAIL: irq_s_external should be 0 at start of Phase 3");
      end

      // Assert M-mode external interrupt only
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
      $display("--- M-mode vector entry ID (expect 11 = MEIP vector) ---");
      check_mem_value(`SPAD(32'h44), 32'h0000000B);


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
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

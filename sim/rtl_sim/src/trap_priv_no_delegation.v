//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_no_delegation
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SU_MODE PRIV - Trap delegation inert under SU_MODE_EN=0
//   Firmware writes mideleg with 0xFFFFFFFF (silently dropped); TB asserts
//   irq_m_timer; the M-mode handler at mtvec must run and mcause must equal
//   0x80000007 (Machine Timer Interrupt). stvec is RAZ/WI so the M-mode
//   handler running successfully (test reaches 0xdeadbeef) is itself proof
//   that no S-mode redirection occurred.
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

      // IRQs are exceptions from the TB monitor's point of view.
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

      @(probes_cpu.x15==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: Delegation attempt + timer IRQ
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 2: TIMER IRQ -> M-MODE HANDLER (no delegation)         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      // Wait for "ready for IRQ" sentinel, then drive irq_m_timer.
      @(probes_cpu.x15==32'h21212121);
      repeat(5) @(posedge free_clk);

      irq_m_timer = 1'b1;

      // Wait for firmware to finish (handler ran + flag observed + snapshots)
      @(probes_cpu.x15==32'hdeadbeef);
      irq_m_timer = 1'b0;
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- mideleg readback after write 0xFFFFFFFF (expect 0) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000000);

      $display("");
      $display("--- trap_count = 1 (handler at mtvec ran) ---");
      check_mem_value(`SPAD(32'h24), 32'h00000001);

      $display("");
      $display("--- MCAUSE = 0x80000007 (Machine Timer Interrupt) ---");
      check_mem_value(`SPAD(32'h28), 32'h80000007);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

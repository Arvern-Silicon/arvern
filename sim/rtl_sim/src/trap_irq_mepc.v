//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_mepc
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IRQ MEPC CORRECTNESS
//   Verifies that interrupts do not cause instruction replay.
//
//   Injects rapid IRQ pulses while the firmware executes cumulative
//   ADDI operations. If MEPC is correct, the ADDI chain produces
//   the expected sum. If instruction replay occurs, the sum is too high.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

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

      // Disable error-on-exception (interrupts trigger exception monitors)
      error_on_exception = 0;


      //=================================================================
      // Wait for initialization
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|               IRQ MEPC CORRECTNESS TEST                            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for initialization...");

      @(probes_cpu.x31==32'h11111111);

      $display("Initialization complete.");
      $display("");


      //=================================================================
      // PHASE 1: ADDI chain with rapid IRQ injection
      // Inject many short IRQ pulses during the ADDI chain.
      // Alternate between timer, software, and external IRQs.
      //=================================================================
      $display(" ====================================================================");
      $display("|               PHASE 1: ADDI CHAIN (100 cumulative adds)            |");
      $display(" ====================================================================");
      $display("");
      $display("Injecting rapid IRQ pulses during ADDI chain...");

      // Inject IRQs rapidly — short pulses with short gaps
      for (ii = 0; ii < 40; ii = ii + 1) begin
         // Random short gap (2-6 cycles)
         repeat(2 + ($urandom % 5)) @(posedge free_clk);

         // Cycle through IRQ types
         case (ii % 3)
            0: begin
               irq_m_timer = 1'b1;
               repeat(1 + ($urandom % 2)) @(posedge free_clk);
               irq_m_timer = 1'b0;
            end
            1: begin
               irq_m_software = 1'b1;
               repeat(1 + ($urandom % 2)) @(posedge free_clk);
               irq_m_software = 1'b0;
            end
            2: begin
               irq_m_external = 1'b1;
               repeat(1 + ($urandom % 2)) @(posedge free_clk);
               irq_m_external = 1'b0;
            end
         endcase
      end

      // Wait for Phase 1 complete marker
      @(probes_cpu.x31==32'h22222222);

      $display("");
      $display("--- Phase 1: ADDI chain result ---");

      // x10 should be exactly 100 (0x64)
      // If instruction replay bug exists, x10 > 100
      check_cpu_reg(10, 32'h00000064);

      $display("");


      //=================================================================
      // PHASE 2: LUI+ADDI pairs — test two-instruction sequences
      //=================================================================
      $display(" ====================================================================");
      $display("|               PHASE 2: LUI+ADDI PAIRS                              |");
      $display(" ====================================================================");
      $display("");

      @(probes_cpu.x31==32'h33333333);

      $display("--- Phase 2: Register value checks ---");

      check_cpu_reg(11, 32'h12345678);
      check_cpu_reg(12, 32'hDEADBEEF);
      check_cpu_reg(13, 32'hCAFEBABE);
      check_cpu_reg(14, 32'h01020304);
      check_cpu_reg(15, 32'hA5A5A5A5);

      $display("");


      //=================================================================
      // PHASE 3: Register preservation
      //=================================================================
      $display(" ====================================================================");
      $display("|               PHASE 3: REGISTER PRESERVATION                       |");
      $display(" ====================================================================");
      $display("");

      @(probes_cpu.x31==32'h44444444);

      $display("--- Phase 3: Callee-saved register checks ---");

      check_cpu_reg(18, 32'hAAAAAAAA);  // s2
      check_cpu_reg(19, 32'hBBBBBBBB);  // s3
      check_cpu_reg(20, 32'hCCCCCCCC);  // s4
      check_cpu_reg(21, 32'hDDDDDDDD);  // s5
      check_cpu_reg(22, 32'hEEEEEEEE);  // s6

      $display("");


      //=================================================================
      // Final summary
      //=================================================================

      @(probes_cpu.x31==32'hdeadbeef);

      stimulus_done = 1;
   end

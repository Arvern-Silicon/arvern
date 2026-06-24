//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_plic_basic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PLIC end-to-end (M-mode context)
//   Verifies the full aRVern -> ahb_plic -> aRVern external-IRQ loop:
//     - Firmware configures priorities, enables, threshold over AHB
//     - Testbench raises plic_irq_src[N] (level)
//     - Core takes MEI trap; handler reads claim/complete register
//     - Handler signals TB via scratchpad to drop the line, then writes
//       complete
//     - With two sources asserted together, the higher-priority source is
//       claimed first
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad byte->word index
`define SPAD(byte_off)  (byte_off/4)

//----------------------------------------------------------------------------
// PLIC source auto-drop:
//   Whenever the handler stores the claimed source ID into scratchpad[0x80],
//   this block drops the corresponding plic_irq_src line. Handler zeros 0x80
//   before MRET so no further dropping happens until the next claim.
//   This models a peripheral that lowers its IRQ line once the CPU has acked
//   the interrupt at the device level.
//----------------------------------------------------------------------------
always @(posedge free_clk) begin
   case (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h80)])
      32'd1   : plic_irq_src[1] <= 1'b0;
      32'd2   : plic_irq_src[2] <= 1'b0;
      32'd3   : plic_irq_src[3] <= 1'b0;
      default : ;
   endcase
end

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Reset peripherals (standard TB pattern)
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Interrupts trigger exception monitors; suppress their error report
      error_on_exception = 0;

      // Route PLIC outputs to the core (mux: use_plic=0 by default)
      use_plic = 1'b1;


      //=================================================================
      // PHASE 1: PLIC programmed
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: PLIC CONFIGURED                           |");
      $display(" ====================================================================");
      $display("Waiting for the firmware to program priorities / enable / threshold...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      $display("PASS:  Phase 1 - PLIC programmed by firmware %t ns", $time);


      //=================================================================
      // PHASE 2: single source 1
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: SOURCE 1 SINGLE-SHOT                      |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("Asserting plic_irq_src[1] (priority 3)...");
      plic_irq_src[1] = 1'b1;

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Trap count + last claim ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // trap_count = 1
      check_mem_value(`SPAD(32'h04), 32'h8000000B);   // MCAUSE = MEI
      check_mem_value(`SPAD(32'h0C), 32'h00000001);   // claimed ID = 1
      check_mem_value(`SPAD(32'h10), 32'h00000001);   // claim_log[0] = 1


      //=================================================================
      // PHASE 3: single source 2
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: SOURCE 2 SINGLE-SHOT                      |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("Asserting plic_irq_src[2] (priority 5)...");
      plic_irq_src[2] = 1'b1;

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Trap count + last claim ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // trap_count = 2
      check_mem_value(`SPAD(32'h04), 32'h8000000B);
      check_mem_value(`SPAD(32'h0C), 32'h00000002);   // claimed ID = 2
      check_mem_value(`SPAD(32'h14), 32'h00000002);   // claim_log[1] = 2


      //=================================================================
      // PHASE 4: two sources, priority arbitration
      //   src 3 (pri 7) + src 1 (pri 3) asserted simultaneously.
      //   PLIC must claim src 3 first, then src 1.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 4: TWO SOURCES, PRIORITY ARBITRATION                  |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("Asserting plic_irq_src[1] (pri 3) and plic_irq_src[3] (pri 7) together...");
      plic_irq_src[1] = 1'b1;
      plic_irq_src[3] = 1'b1;

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Two-source ordering ---");
      check_mem_value(`SPAD(32'h00), 32'h00000004);   // 1 + 1 + 2 = 4 total traps

      // claim_log[2] = first trap of phase 4, should be src 3 (higher priority)
      begin : check_priority_order
         reg [31:0] first_claim;
         reg [31:0] second_claim;
         first_claim  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         second_claim = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];

         if (first_claim !== 32'd3) begin
            $display("ERROR: Phase 4 first claim should be source 3 (pri 7) -- got %0d %t ns",
                     first_claim, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Phase 4 first claim = source 3 (priority 7) %t ns", $time);
         end

         if (second_claim !== 32'd1) begin
            $display("ERROR: Phase 4 second claim should be source 1 (pri 3) -- got %0d %t ns",
                     second_claim, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Phase 4 second claim = source 1 (priority 3) %t ns", $time);
         end
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      // No `@(x31 == deadbeef)` wait here: with no firmware stalls between
      // 0x44444444 and 0xdeadbeef, the deadbeef edge may fire before this
      // initial block resumes from the checks above, and `@()` is
      // edge-triggered. Phase 4's completion is sufficient evidence the
      // test ran to end; mirror trap_irq_basic and finish from here.
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

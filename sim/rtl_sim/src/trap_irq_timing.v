//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_timing
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP IRQ TIMING
//   Interrupt timing edge cases:
//   - MRET re-entry: IRQ still asserted, different source fires
//   - CSR enable race: CSRS MIE enables already-pending interrupt
//   - WFI immediate wakeup: interrupt pending when WFI executes
//   - IRQ during load/store sequence
//   - Rapid ECALL-MRET cycles (10 back-to-back)
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

      // Disable error-on-exception
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

      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: MRET re-entry (IRQ still asserted)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: MRET RE-ENTRY (IRQ STILL ASSERTED)       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      repeat(3) @(posedge free_clk);

      // Assert timer IRQ and keep it asserted
      irq_m_timer = 1'b1;

      // Wait for firmware to handle first timer IRQ and signal ready for external
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Now also assert external IRQ (timer still asserted but MIE.MTIE cleared by handler)
      irq_m_external = 1'b1;

      // Wait for Phase 2 complete
      @(probes_cpu.x31==32'h23232323);
      repeat(3) @(posedge free_clk);

      // Deassert both
      irq_m_timer    = 1'b0;
      irq_m_external = 1'b0;

      // Check: first trap count should be 1
      $display("");
      $display("--- Trap count after first IRQ ---");
      check_mem_value(`SPAD(32'h20), 32'h00000001);

      // Check: total trap count should be 2
      $display("");
      $display("--- Trap count after second IRQ ---");
      check_mem_value(`SPAD(32'h24), 32'h00000002);

      // Check: second interrupt was external (0x8000000B)
      $display("");
      $display("--- MCAUSE from second IRQ (expect external) ---");
      check_mem_value(`SPAD(32'h28), 32'h8000000B);


      //=================================================================
      // PHASE 3: CSR enable race
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: CSR ENABLE RACE                          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(2) @(posedge free_clk);

      // Assert timer IRQ (MIE.MTIE=0, so no trap yet)
      irq_m_timer = 1'b1;

      // Wait for Phase 3 complete (firmware enables MTIE, trap fires, handler returns)
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_timer = 1'b0;

      // Check: trap count incremented by 1
      $display("");
      $display("--- Trap count verification (CSR enable race) ---");
      begin : check_csr_race
         reg [31:0] before, after;
         before = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];
         after  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)];
         if (after !== before + 1) begin
            $display("ERROR: Trap count should have incremented by 1 -- before: %0d, after: %0d %t ns",
                     before, after, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Trap count incremented by 1 (CSR enable race worked) %t ns", $time);
         end
      end

      // Check MCAUSE = timer interrupt
      $display("");
      $display("--- MCAUSE verification (expect timer) ---");
      check_mem_value(`SPAD(32'h38), 32'h80000007);


      //=================================================================
      // PHASE 4: WFI immediate wakeup
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: WFI IMMEDIATE WAKEUP                     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h41414141);
      repeat(2) @(posedge free_clk);

      // Assert timer IRQ (MSTATUS.MIE=0, so no trap, but WFI should wake)
      irq_m_timer = 1'b1;

      // Wait for Phase 4 complete
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_timer = 1'b0;

      // Check: marker before WFI was written
      $display("");
      $display("--- WFI markers ---");
      check_mem_value(`SPAD(32'h40), 32'h0000AAAA);

      // Check: marker after WFI was written (proves WFI didn't stall)
      check_mem_value(`SPAD(32'h44), 32'h0000BBBB);

      // Check: interrupt was eventually taken after MSTATUS.MIE re-enabled
      $display("");
      $display("--- WFI trap count ---");
      begin : check_wfi_trap
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)];
         if (tc < 32'h1) begin
            $display("ERROR: Expected at least 1 trap after WFI -- trap_count: %0d %t ns", tc, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Trap taken after WFI + MIE re-enable -- trap_count: %0d %t ns", tc, $time);
         end
      end


      //=================================================================
      // PHASE 5: IRQ during load/store sequence
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: IRQ DURING LOAD/STORE SEQUENCE           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h51515151);
      // Ensure no stale IRQs, then assert timer for load/store phase
      irq_m_timer    = 1'b0;
      irq_m_external = 1'b0;
      repeat(3) @(posedge free_clk);

      // Assert timer IRQ (firmware will enable MTIE after delay)
      irq_m_timer = 1'b1;

      // Wait for Phase 5 complete
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_timer = 1'b0;

      // Check loaded values are correct despite interrupt
      $display("");
      $display("--- Load values after IRQ (should be unaffected) ---");
      check_mem_value(`SPAD(32'h50), 32'hDEADBEEF);
      check_mem_value(`SPAD(32'h54), 32'hCAFEBABE);
      check_mem_value(`SPAD(32'h58), 32'h12345678);

      // Check interrupt was taken
      $display("");
      $display("--- Load/store phase trap count ---");
      begin : check_ldst_trap
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h5C)];
         if (tc < 32'h1) begin
            $display("ERROR: Expected at least 1 trap during load/store -- trap_count: %0d %t ns", tc, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Trap taken during load/store sequence -- trap_count: %0d %t ns", tc, $time);
         end
      end


      //=================================================================
      // PHASE 6: Rapid ECALL-MRET cycles
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 6: RAPID ECALL-MRET CYCLES                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 5
      $display("");
      $display("--- Trap count after 5 rapid ECALLs ---");
      check_mem_value(`SPAD(32'h60), 32'h00000005);


      // Final register preservation check
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

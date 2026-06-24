//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_vectored
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IRQ VECTORED
//   MTVEC vectored interrupt mode (mode=01) verification:
//   - Timer interrupt vectored to BASE + 4*7  (MCAUSE = 0x80000007)
//   - Software interrupt vectored to BASE + 4*3 (MCAUSE = 0x80000003)
//   - External interrupt vectored to BASE + 4*11 (MCAUSE = 0x8000000B)
//   - Exception (ECALL) still goes to BASE (not vectored)
//   - Register preservation across interrupts
//
//   IRQ signals are driven directly by this testbench stimulus.
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

      // Disable error-on-exception (interrupts and ECALL trigger exception monitors)
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

      // Check MTVEC readback (mode should be 01 = vectored)
      $display("");
      $display("--- MTVEC readback ---");
      begin : check_mtvec
         reg [31:0] mtvec_val;
         mtvec_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];

         if (mtvec_val[1:0] !== 2'b01) begin
            $display("ERROR: MTVEC mode should be 01 (vectored) -- MTVEC: 0x%h %t ns", mtvec_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MTVEC mode = 01 (vectored) %t ns", $time);
         end

         if (mtvec_val[31:2] == 30'h0) begin
            $display("ERROR: MTVEC base should be non-zero -- MTVEC: 0x%h %t ns", mtvec_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MTVEC base = 0x%h %t ns", {mtvec_val[31:2], 2'b00}, $time);
         end
      end

      // Check callee-saved registers
      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: Timer interrupt (vectored)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: TIMER INTERRUPT (VECTORED)               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      repeat(5) @(posedge free_clk);

      // Assert timer interrupt
      irq_m_timer = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Deassert timer interrupt
      irq_m_timer = 1'b0;

      // Check trap_count = 1
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // Check MCAUSE = 0x80000007 (Machine Timer Interrupt)
      $display("");
      $display("--- MCAUSE verification (timer) ---");
      check_mem_value(`SPAD(32'h20), 32'h80000007);

      // Check vector_entry_id = 7 (vectored to entry 7)
      $display("");
      $display("--- Vector entry verification (timer) ---");
      check_mem_value(`SPAD(32'h24), 32'h00000007);


      //=================================================================
      // PHASE 3: Software interrupt (vectored)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: SOFTWARE INTERRUPT (VECTORED)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(5) @(posedge free_clk);

      // Assert software interrupt
      irq_m_software = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_software = 1'b0;

      // Check trap_count = 2
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      // Check MCAUSE = 0x80000003 (Machine Software Interrupt)
      $display("");
      $display("--- MCAUSE verification (software) ---");
      check_mem_value(`SPAD(32'h30), 32'h80000003);

      // Check vector_entry_id = 3 (vectored to entry 3)
      $display("");
      $display("--- Vector entry verification (software) ---");
      check_mem_value(`SPAD(32'h34), 32'h00000003);


      //=================================================================
      // PHASE 4: External interrupt (vectored)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: EXTERNAL INTERRUPT (VECTORED)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h41414141);
      repeat(5) @(posedge free_clk);

      // Assert external interrupt
      irq_m_external = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_external = 1'b0;

      // Check trap_count = 3
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      // Check MCAUSE = 0x8000000B (Machine External Interrupt)
      $display("");
      $display("--- MCAUSE verification (external) ---");
      check_mem_value(`SPAD(32'h40), 32'h8000000B);

      // Check vector_entry_id = 11 (vectored to entry 11)
      $display("");
      $display("--- Vector entry verification (external) ---");
      check_mem_value(`SPAD(32'h44), 32'h0000000B);


      //=================================================================
      // PHASE 5: Exception (ECALL) goes to BASE, not vectored
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: EXCEPTION GOES TO BASE                   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      // No interrupt to assert -- ECALL is synchronous
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      // Check trap_count = 4
      check_mem_value(`SPAD(32'h00), 32'h00000004);

      // Check MCAUSE = 11 (0x0000000B = Environment call from M-mode)
      $display("");
      $display("--- MCAUSE verification (ECALL) ---");
      check_mem_value(`SPAD(32'h50), 32'h0000000B);

      // Check vector_entry_id = 0 (went to BASE, not vectored)
      $display("");
      $display("--- Vector entry verification (exception at BASE) ---");
      check_mem_value(`SPAD(32'h54), 32'h00000000);


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 REGISTER PRESERVATION CHECK                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      // Check callee-saved registers preserved after interrupts + exception
      $display("");
      $display("--- Callee-saved registers after interrupts ---");
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

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_priv_modes
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IRQ PRIVILEGE MODES
//   Interrupt behavior across privilege modes:
//   - Machine timer IRQ while in S-mode  (traps to M-mode, MPP=01)
//   - Machine timer IRQ while in U-mode  (traps to M-mode, MPP=00)
//   - Delegated supervisor timer IRQ from U-mode (SCAUSE=0x80000005, SPP=0)
//   - Delegated supervisor timer IRQ from S-mode (SCAUSE=0x80000005, SPP=1)
//   - SSTATUS.SIE=0 blocks delegated supervisor IRQ in S-mode
//   - Register preservation across all mode transitions
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

      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: Machine timer IRQ while in S-mode
      //          Traps to M-mode, MCAUSE=0x80000007, MPP=01
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: MACHINE TIMER IRQ FROM S-MODE (MCAUSE=0x80000007,MPP=01)|");
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

      $display("");
      $display("--- MCAUSE verification (machine timer) ---");
      check_mem_value(`SPAD(32'h30), 32'h80000007);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 01 = S-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)][12:11] !== 2'b01) begin
         $display("ERROR: MPP mismatch -- expected: 01 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 01 (S-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 3: Machine timer IRQ while in U-mode
      //          Traps to M-mode, MCAUSE=0x80000007, MPP=00
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: MACHINE TIMER IRQ FROM U-MODE (MCAUSE=0x80000007,MPP=00)|");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(5) @(posedge free_clk);

      // Assert timer interrupt
      irq_m_timer = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Deassert timer interrupt
      irq_m_timer = 1'b0;

      $display("");
      $display("--- MCAUSE verification (machine timer) ---");
      check_mem_value(`SPAD(32'h40), 32'h80000007);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 00 = U-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][12:11] !== 2'b00) begin
         $display("ERROR: MPP mismatch -- expected: 00 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 00 (U-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 4: Delegated supervisor timer IRQ from U-mode
      //          MIP.STIP set by firmware, MIDELEG[5] enables delegation
      //          Traps to S-mode handler
      //          SCAUSE=0x80000005, SPP=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: DELEGATED S-TIMER IRQ FROM U-MODE (SCAUSE=0x80000005)   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (supervisor timer interrupt) ---");
      check_mem_value(`SPAD(32'h50), 32'h80000005);

      $display("");
      $display("--- SSTATUS.SPP verification (expect 0 = U-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)][8] !== 1'b0) begin
         $display("ERROR: SPP mismatch -- expected: 0 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)][8], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SPP = 0 (U-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 5: Delegated supervisor timer IRQ from S-mode
      //          Same setup but transition to S-mode first
      //          SCAUSE=0x80000005, SPP=1
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 5: DELEGATED S-TIMER IRQ FROM S-MODE (SCAUSE=0x80000005)   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (supervisor timer interrupt) ---");
      check_mem_value(`SPAD(32'h60), 32'h80000005);

      $display("");
      $display("--- SSTATUS.SPP verification (expect 1 = S-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)][8] !== 1'b1) begin
         $display("ERROR: SPP mismatch -- expected: 1 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)][8], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SPP = 1 (S-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 6: SSTATUS.SIE=0 blocks delegated supervisor IRQ
      //          MIP.STIP pending + MIDELEG[5] set, but SIE=0
      //          s_trap_count should NOT change
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 6: SSTATUS.SIE=0 BLOCKS DELEGATED S-MODE IRQ              |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- S-mode trap count unchanged (SIE=0 blocked IRQ) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h70)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)]) begin
         $display("ERROR: S-mode trap count changed with SIE=0 -- before: %0d / after: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h70)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  S-mode trap count unchanged (SIE=0 blocked interrupt) -- count: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h70)], $time);
      end


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after all mode transitions ---");
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

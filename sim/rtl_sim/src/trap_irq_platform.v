//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_platform
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PLATFORM INTERRUPTS
//   Platform-designated interrupts (MIP/MIE bits 31:16):
//   - Platform interrupt 0 in M-mode (MCAUSE = 0x80000010)
//   - Platform interrupt 0 delegated to S-mode (SCAUSE = 0x80000010)
//
//   Phases 2-3 use software-set MIP bits. Phases 4-5 use testbench-driven
//   irq_platform signals to test external hardware interrupt inputs.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)   // parens: callers pass expressions, e.g. 0x80 + ii*4

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
      // PHASE 2: Platform interrupt 0 in M-mode
      //          MCAUSE = 0x80000010 (interrupt, cause 16)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: PLATFORM IRQ 0 IN M-MODE (MCAUSE=0x80000010)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE verification (platform interrupt 0, cause 16) ---");
      check_mem_value(`SPAD(32'h30), 32'h80000010);


      //=================================================================
      // PHASE 3: Platform interrupt 0 delegated to S-mode
      //          SCAUSE = 0x80000010 (interrupt, cause 16)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: PLATFORM IRQ 0 DELEGATED TO S-MODE (SCAUSE=0x80000010) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (platform interrupt 0, cause 16) ---");
      check_mem_value(`SPAD(32'h40), 32'h80000010);


      //=================================================================
      // PHASE 4: Hardware-driven platform interrupt 0 in M-mode
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: HW-DRIVEN PLATFORM IRQ 0 IN M-MODE (MCAUSE=0x80000010) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h41414141);
      repeat(3) @(posedge free_clk);

      // Assert external platform interrupt 0
      irq_platform[0] = 1'b1;

      // Wait for Phase 4 complete
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_platform[0] = 1'b0;

      $display("");
      $display("--- MCAUSE verification (hw-driven platform IRQ 0, cause 16) ---");
      check_mem_value(`SPAD(32'h50), 32'h80000010);


      //=================================================================
      // PHASE 5: HW-driven platform interrupt 5 delegated to S-mode
      //          irq_platform[5] -> cause 21 -> SCAUSE = 0x80000015
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 5: HW-DRIVEN PLATFORM IRQ 5 DELEGATED (SCAUSE=0x80000015) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h51515151);
      repeat(3) @(posedge free_clk);

      // Assert external platform interrupt 5
      irq_platform[5] = 1'b1;

      // Wait for Phase 5 complete
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_platform[5] = 1'b0;


      $display("");
      $display("--- SCAUSE verification (hw-driven platform IRQ 5, cause 21) ---");
      check_mem_value(`SPAD(32'h60), 32'h80000015);


      //=================================================================
      // PHASE 6: Every platform line drives its own MCAUSE
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 6: ALL 16 PLATFORM LINES (MCAUSE = 0x80000010 + N)         |");
      $display(" ====================================================================");
      $display("");


      // Every line's IRQ interrupts the same polling instruction, so 16 MRETs in a
      // row carry the same MEPC and trip the livelock watchdog. That pattern is
      // intentional here (the loop does advance -- in a register, not the PC), so
      // suppress the checker for this phase only.
      irq_kill_checker_en = 0;

      // wait() rather than @(): the firmware advances as soon as the handler runs,
      // so an edge-triggered wait can miss a value that is already present. Each
      // target encodes the line index, so no stale value can match.
      for (ii = 0; ii < 16; ii = ii + 1)
         begin
            wait (probes_cpu.x31 == (32'h60000000 | ii));
            repeat(2) @(posedge free_clk);
            irq_platform[ii] = 1'b1;

            wait (probes_cpu.x31 == (32'h61000000 | ii));
            repeat(2) @(posedge free_clk);
            irq_platform[ii] = 1'b0;
         end

      wait (probes_cpu.x31 == 32'h66666666);
      repeat(3) @(posedge free_clk);
      irq_kill_checker_en = 1;

      $display("");
      $display("--- MCAUSE per platform line ---");
      for (ii = 0; ii < 16; ii = ii + 1)
         check_mem_value(`SPAD(32'h80 + ii*4), 32'h80000010 + ii);


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after platform interrupt tests ---");
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

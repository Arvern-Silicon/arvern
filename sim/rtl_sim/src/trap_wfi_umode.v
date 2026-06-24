//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_wfi_umode
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP WFI U-MODE
//   WFI behavior in U-mode:
//   - TW=1: WFI in U-mode raises illegal instruction (MCAUSE=2, MPP=00)
//   - TW=0: WFI in U-mode stalls until timer interrupt (no trap from WFI)
//   - Register preservation across all mode transitions
//
//   Phase 3 requires testbench-driven irq_m_timer assertion.
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
      // PHASE 2: TW=1, WFI in U-mode -> illegal instruction
      //          MCAUSE = 2, MPP = 00 (from U-mode)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: TW=1, WFI IN U-MODE -> ILLEGAL INST (MCAUSE=2, MPP=00) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (illegal instruction from WFI) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 00 = U-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)][12:11] !== 2'b00) begin
         $display("ERROR: MPP mismatch -- expected: 00 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 00 (U-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 3: TW=0, WFI in U-mode -> stalls until timer interrupt
      //          WFI should NOT trap. Testbench asserts irq_m_timer.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: TW=0, WFI IN U-MODE -> STALLS UNTIL TIMER IRQ (NO TRAP)|");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);

      // Wait for WFI to actually be executing (stalling the pipeline)
      // before asserting the timer. This avoids the race where the timer
      // fires before WFI is reached.
      @(posedge dut.arv_decode_inst.wfi_active);
      // 30 cycles is plenty of time for the AHB masters to drain and
      // wfi_sleep_safe_r to latch -- core should be clock-gated by then.
      repeat(30) @(posedge free_clk);

      // Verify clock-gating during U-mode WFI sleep
      if (dut_hclk_en !== 1'b0) begin
         $display("ERROR: dut_hclk_en=%b during U-mode WFI sleep -- clock not gated %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=0 during U-mode WFI sleep %t ns", $time);
      end

      // Assert timer interrupt to wake WFI
      irq_m_timer = 1'b1;
      @(posedge free_clk);

      // Verify wakeup ungates the clock combinatorially
      if (dut_hclk_en !== 1'b1) begin
         $display("ERROR: dut_hclk_en=%b after IRQ -- wakeup ungating broken %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=1 after IRQ wakeup (U-mode WFI) %t ns", $time);
      end

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Deassert timer interrupt
      irq_m_timer = 1'b0;

      $display("");
      $display("--- WFI completed flag ---");
      check_mem_value(`SPAD(32'h38), 32'h00000001);

      $display("");
      $display("--- M-mode trap count check (only timer IRQ, no illegal instruction from WFI) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)] !==
          (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)] + 1)) begin
         $display("ERROR: Expected trap count = before+1 (timer only) -- before: %0d / after: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  Trap count incremented by 1 (timer IRQ only, WFI did not trap) %t ns", $time);
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

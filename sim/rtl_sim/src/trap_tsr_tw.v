//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_tsr_tw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP TSR / TW
//   MSTATUS.TSR and MSTATUS.TW bit verification:
//   - TSR=1: SRET in S-mode raises illegal instruction (MCAUSE=2)
//   - TSR=0: SRET in S-mode works normally
//   - TW=1:  WFI in S-mode raises illegal instruction (MCAUSE=2)
//   - TW=0:  WFI in S-mode stalls until interrupt (no trap)
//   - Register preservation across all mode transitions
//
//   Phase 5 requires testbench-driven irq_m_timer assertion.
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
      // PHASE 2: TSR=1, SRET in S-mode -> illegal instruction
      //          MCAUSE = 2, MPP = 01 (from S-mode)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: TSR=1, SRET IN S-MODE -> ILLEGAL INST (MCAUSE=2,MPP=01)|");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (illegal instruction from SRET) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 01 = S-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)][12:11] !== 2'b01) begin
         $display("ERROR: MPP mismatch -- expected: 01 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 01 (S-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 3: TSR=0, SRET in S-mode -> works normally
      //          m_trap_count should NOT change (no illegal instruction)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: TSR=0, SRET IN S-MODE -> WORKS NORMALLY (NO TRAP)      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- M-mode trap count unchanged (SRET did not trap) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)]) begin
         $display("ERROR: M-mode trap count changed with TSR=0 -- before: %0d / after: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  M-mode trap count unchanged (SRET worked normally) -- count: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)], $time);
      end


      //=================================================================
      // PHASE 4: TW=1, WFI in S-mode -> illegal instruction
      //          MCAUSE = 2, MPP = 01 (from S-mode)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: TW=1, WFI IN S-MODE -> ILLEGAL INST (MCAUSE=2, MPP=01) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (illegal instruction from WFI) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000002);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 01 = S-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][12:11] !== 2'b01) begin
         $display("ERROR: MPP mismatch -- expected: 01 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 01 (S-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 5: TW=0, WFI in S-mode -> stalls until timer interrupt
      //          WFI should NOT trap. Testbench asserts irq_m_timer.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 5: TW=0, WFI IN S-MODE -> STALLS UNTIL TIMER IRQ (NO TRAP)|");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h51515151);

      // Wait for WFI to actually be executing (stalling the pipeline)
      // before asserting the timer. Without this, with -rwsrom the timer
      // fires before WFI is reached, the handler clears MTIE, and WFI
      // stalls forever.
      @(posedge dut.arv_decode_inst.wfi_active);
      repeat(3) @(posedge free_clk);

      // Assert timer interrupt to wake WFI
      irq_m_timer = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      // Deassert timer interrupt
      irq_m_timer = 1'b0;

      $display("");
      $display("--- WFI completed flag ---");
      check_mem_value(`SPAD(32'h58), 32'h00000001);

      $display("");
      $display("--- M-mode trap count check (only timer IRQ, no illegal instruction from WFI) ---");
      // m_trap_count_after should be m_trap_count_before + 1 (timer IRQ only)
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)] !==
          (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)] + 1)) begin
         $display("ERROR: Expected trap count = before+1 (timer only) -- before: %0d / after: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)], $time);
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

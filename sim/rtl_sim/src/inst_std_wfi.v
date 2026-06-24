//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_wfi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: WFI
//   Wait For Interrupt verification:
//   - WFI stall + interrupt wakeup + handler + MRET resume
//   - WFI wakeup with MIE=0 (no trap, just resume)
//   - MEPC/MCAUSE/MSTATUS verification
//   - Register preservation
//----------------------------------------------------------------------------

`define VERY_LONG_TIMEOUT

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
      // PHASE 2: WFI + timer interrupt
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: WFI + TIMER INTERRUPT                     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      repeat(100) @(posedge free_clk);

      // Verify the core is actually clock-gated during WFI sleep.
      // After 100 cycles of waiting, hclk_en_o must be low (bus has long
      // since drained and wfi_sleep_safe_r has latched).
      if (dut_hclk_en !== 1'b0) begin
         $display("ERROR: dut_hclk_en=%b during WFI sleep (Phase 2) -- clock not gated %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=0 during WFI sleep (Phase 2) %t ns", $time);
      end

      // Assert timer interrupt to wake WFI
      irq_m_timer = 1'b1;
      @(posedge free_clk);

      // Verify wakeup ungates the clock combinatorially via wfi_wakeup_live.
      if (dut_hclk_en !== 1'b1) begin
         $display("ERROR: dut_hclk_en=%b after IRQ (Phase 2) -- wakeup ungating broken %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=1 after IRQ wakeup (Phase 2) %t ns", $time);
      end

      // Wait for firmware to resume and complete phase
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      irq_m_timer = 1'b0;

      // Check trap_count = 1
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // Check MCAUSE = 0x80000007 (Machine Timer Interrupt)
      $display("");
      $display("--- MCAUSE verification ---");
      check_mem_value(`SPAD(32'h20), 32'h80000007);

      // Check MEPC matches expected (should point to instruction after WFI)
      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected (after WFI) -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)], $time);
      end

      // Check firmware resumed (confirmation value)
      $display("");
      $display("--- Post-WFI resume confirmation ---");
      check_mem_value(`SPAD(32'h30), 32'hDEADBEEF);

      // Check MSTATUS in handler
      $display("");
      $display("--- MSTATUS on trap entry ---");
      begin : check_mstatus_wfi
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];

         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 in handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 in handler %t ns", $time);
         end

         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 in handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 in handler %t ns", $time);
         end

         if (mstatus_val[12:11] !== 2'b11) begin
            $display("ERROR: MSTATUS.MPP should be 11 in handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = 11 in handler %t ns", $time);
         end
      end

      // Check MSTATUS after MRET
      $display("");
      $display("--- MSTATUS after MRET ---");
      begin : check_mstatus_mret
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)];

         if (mstatus_val[3] !== 1'b1) begin
            $display("ERROR: MSTATUS.MIE should be 1 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 1 after MRET %t ns", $time);
         end
      end


      //=================================================================
      // PHASE 3: WFI with MIE=0 (wakeup without trap)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: WFI WITH MIE=0 (WAKEUP, NO TRAP)         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(100) @(posedge free_clk);

      // Verify clock-gating during MIE=0 WFI sleep
      if (dut_hclk_en !== 1'b0) begin
         $display("ERROR: dut_hclk_en=%b during WFI sleep (Phase 3) -- clock not gated %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=0 during WFI sleep (Phase 3) %t ns", $time);
      end

      // Assert timer interrupt to wake WFI
      irq_m_timer = 1'b1;
      @(posedge free_clk);

      if (dut_hclk_en !== 1'b1) begin
         $display("ERROR: dut_hclk_en=%b after IRQ (Phase 3) -- wakeup ungating broken %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=1 after IRQ wakeup (Phase 3) %t ns", $time);
      end

      // Wait for firmware to resume (no trap, just continues past WFI)
      @(probes_cpu.x31==32'h33333333);

      irq_m_timer = 1'b0;
      repeat(3) @(posedge free_clk);

      // Check trap_count unchanged
      $display("");
      $display("--- Trap count unchanged (MIE=0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)]) begin
         $display("ERROR: Trap count changed with MIE=0 -- before: %0d / after: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  Trap count unchanged (WFI woke without trap) -- count: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)], $time);
      end

      // Check firmware resumed confirmation
      $display("");
      $display("--- Post-WFI resume confirmation ---");
      check_mem_value(`SPAD(32'h48), 32'hCAFEBABE);

      // Final register preservation
      $display("");
      $display("--- Register preservation ---");
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

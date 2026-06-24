//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_wfi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI WFI
//   NMI wakes WFI verification:
//   - Processor executes WFI and stalls
//   - NMI fires -> wfi_wakeup asserted -> NMI handler entered
//   - mnepc = address of WFI instruction (saved to scratchpad)
//   - Handler advances mnepc by 4 so mnret returns past WFI
//   - mnret resumes at lw after WFI; nmi_count > 0 so loop exits
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

      // Disable error-on-exception (NMI entry will look like a trap)
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete — configure nmi_vector
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: INIT + CONFIGURE NMI VECTOR               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Read nmi_handler address from scratchpad[0x08] and drive nmi_vector
      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         $display("NMI handler address from scratchpad: 0x%h %t ns", handler_addr, $time);

         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler_addr in scratchpad is 0 -- firmware did not store it %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_handler_addr stored by firmware: 0x%h %t ns", handler_addr, $time);
         end

         nmi_vector = handler_addr;
      end

      // Verify scratchpad is otherwise zeroed (no NMI yet)
      $display("");
      $display("--- Pre-NMI state check ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // nmi_count = 0
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // mnepc_wfi = 0


      //=================================================================
      // PHASE 2: Wait for WFI to stall, then assert NMI
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: WAIT FOR WFI, THEN ASSERT NMI             |");
      $display(" ====================================================================");
      $display("");

      // Give the processor a few cycles to reach the WFI instruction
      repeat(10) @(posedge free_clk);

      // Wait for WFI to actually be stalling the pipeline (level-sensitive)
      // Use wait() not @(posedge): wfi_active goes high ~2 cycles after WFI,
      // before testbench reaches here — edge would be missed with @(posedge).
      wait(dut.arv_decode_inst.wfi_active === 1'b1);
      // 30 cycles is plenty of time for the AHB masters to drain and
      // wfi_sleep_safe_r to latch (worst case ~15 cycles even under wait states).
      repeat(30) @(posedge free_clk);

      // Verify the core is clock-gated while WFI sleeps
      if (dut_hclk_en !== 1'b0) begin
         $display("ERROR: dut_hclk_en=%b during WFI sleep -- clock not gated %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=0 during WFI sleep (NMI test) %t ns", $time);
      end

      $display("WFI active detected, asserting NMI %t ns", $time);

      // Assert NMI for 3 cycles then deassert (level-sensitive, one shot)
      nmi = 1'b1;
      @(posedge free_clk);

      // Verify NMI ungates the clock combinatorially via wfi_wakeup_live
      if (dut_hclk_en !== 1'b1) begin
         $display("ERROR: dut_hclk_en=%b after NMI assert -- wakeup ungating broken %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=1 after NMI wakeup %t ns", $time);
      end

      repeat(2) @(posedge free_clk);
      nmi = 1'b0;

      $display("NMI asserted and deasserted %t ns", $time);


      //=================================================================
      // PHASE 3: End of test — verify NMI woke WFI correctly
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: VERIFY NMI WOKE WFI                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      // Check nmi_count = 1
      $display("");
      $display("--- NMI count (expect 1) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // Check mnepc_wfi is in ROM range (WFI instruction is in ROM)
      $display("");
      $display("--- MNEPC range check (WFI instruction address) ---");
      begin : check_mnepc_wfi
         reg [31:0] mnepc_val;
         mnepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

         $display("MNEPC (WFI address): 0x%h %t ns", mnepc_val, $time);

         // WFI instruction is in ROM (0x2xxxxxxx)
         if (mnepc_val[31:28] !== 4'h2) begin
            $display("ERROR: MNEPC should be in ROM range (0x2xxxxxxx) -- MNEPC: 0x%h %t ns", mnepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC in ROM range -- value: 0x%h %t ns", mnepc_val, $time);
         end

         // MNEPC bit[0] must be 0 (PC is always at least 2-byte aligned)
         if (mnepc_val[0] !== 1'b0) begin
            $display("ERROR: MNEPC bit[0] should be 0 (alignment) -- MNEPC: 0x%h %t ns", mnepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC bit[0] = 0 (aligned) %t ns", $time);
         end
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

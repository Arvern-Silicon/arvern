//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_livelock
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI LIVELOCK SUPPRESSION
//   Verifies that after mnret, nmi_detect is suppressed for one instruction
//   cycle even if nmi_i stays asserted.  Without the fix, mnret immediately
//   re-enables NMIE and the handler is re-entered before any instruction
//   executes, causing infinite livelock.
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

      // Disable error-on-exception (NMI entries look like exceptions)
      error_on_exception = 0;


      //=================================================================
      // INIT: Configure nmi_vector from scratchpad, verify counters zero
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|          NMI LIVELOCK SUPPRESSION TEST                             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware init...");

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

      // Verify scratchpad counters are zeroed before NMI fires
      $display("");
      $display("--- Initial counter values (all should be 0) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // nmi_count      = 0
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // progress_count = 0


      //=================================================================
      // PHASE 1: NMI livelock suppression (positive test)
      //
      // Wait for firmware to signal it is about to enter the progress
      // loop, then assert nmi and hold it high.  The firmware loops
      // until nmi_count >= 3 and signals 0x22222222.
      //
      // With the livelock-suppression fix: each mnret allows at least
      // one loop instruction to execute before NMI re-fires, so
      // progress_count increments alongside nmi_count.
      //
      // Without the fix: the handler would be re-entered immediately
      // on every mnret and the firmware would never advance, hanging
      // forever (caught by LONG_TIMEOUT watchdog).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|          PHASE 1: NMI LIVELOCK SUPPRESSION (nmi held high)         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware to enter phase 1 loop...");

      // Level-sensitive wait: x31 may already be 0x12121212 by the time the
      // testbench arrives here (only one instruction between the two syncs).
      if (probes_cpu.x31 !== 32'h12121212) @(probes_cpu.x31==32'h12121212);
      repeat(3) @(posedge free_clk);

      // Assert nmi and hold it high — firmware loop will accumulate entries
      nmi = 1'b1;
      $display("NMI asserted and held high %t ns", $time);

      // Wait for firmware to confirm nmi_count >= 3 (forward progress was made)
      @(probes_cpu.x31==32'h22222222);

      // Deassert nmi now that the firmware has confirmed re-entry happened
      nmi = 1'b0;
      $display("NMI deasserted (firmware confirmed nmi_count >= 3) %t ns", $time);
      repeat(3) @(posedge free_clk);

      // Verify nmi_count >= 3: handler was entered multiple times (re-entry occurred)
      $display("");
      $display("--- Phase 1 results ---");
      begin : check_phase1
         reg [31:0] nmi_cnt;
         reg [31:0] prog_cnt;
         nmi_cnt  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         prog_cnt = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

         $display("nmi_count      = %0d %t ns", nmi_cnt,  $time);
         $display("progress_count = %0d %t ns", prog_cnt, $time);

         // nmi_count must be >= 3 (loop exit condition in firmware)
         if (nmi_cnt < 3) begin
            $display("ERROR: nmi_count should be >= 3 -- got %0d %t ns", nmi_cnt, $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_count >= 3 (handler re-entered multiple times): %0d %t ns", nmi_cnt, $time);
         end

         // progress_count must be > 0: at least one loop body executed between NMI entries,
         // proving no infinite livelock (forward progress was made)
         if (prog_cnt == 0) begin
            $display("ERROR: progress_count is 0 -- no forward progress between NMI entries (livelock?) %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  progress_count > 0 (forward progress confirmed): %0d %t ns", prog_cnt, $time);
         end

      end


      //=================================================================
      // END OF TEST
      //=================================================================
      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- End of test ---");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

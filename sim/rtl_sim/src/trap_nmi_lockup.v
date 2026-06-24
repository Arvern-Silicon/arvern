//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_lockup
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI LOCKUP
//   NMI lockup escape test -- two phases:
//
//   Phase 1 (positive): NMI escapes lockup
//   - irqkill_cfg[3]=1 (escape enabled)
//   - Wait for lockup_o to assert, then assert nmi
//   - Verify CPU escapes: lockup_o deasserts, x31=0x12121212
//   - Verify: nmi_count=1, m_trap_count=1
//
//   Phase 2 (negative): NMI does NOT escape lockup
//   - irqkill_cfg[3]=0 (escape disabled)
//   - Wait for lockup_o to assert again, then assert nmi
//   - Verify CPU stays locked: lockup_o remains 1
//   - Verify: nmi_count still 1 (NMI handler never ran in Phase 2)
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

      // Disable error-on-exception (NMI entry and M-mode traps will look like exceptions)
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization -- configure nmi_vector, enable escape
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|          PHASE 1: INIT + CONFIGURE NMI VECTOR (ESCAPE ENABLED)    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware (x31=0x11111111)...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Read nmi_handler address from scratchpad[0x08] and configure nmi_vector
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

      // Verify scratchpad counters zeroed before lockup
      $display("");
      $display("--- Scratchpad zeroed before lockup ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // nmi_count = 0
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // m_trap_count = 0


      //=================================================================
      // PHASE 2: Wait for lockup, then fire NMI -- expect escape
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: WAIT FOR LOCKUP THEN FIRE NMI (EXPECT ESCAPE)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for lockup_o to assert (CPU entering lockup)...");

      @(posedge lockup);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- lockup_o asserted ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o not asserted after double M-mode exception %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o asserted -- CPU entered lockup state %t ns", $time);
      end

      // Assert NMI: irqkill_cfg[3]=1 so NMI should escape lockup
      $display("");
      $display("Asserting NMI (escape enabled -- expect CPU to escape lockup)...");
      nmi = 1'b1;
      repeat(5) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI asserted and deasserted %t ns", $time);


      //=================================================================
      // PHASE 3: Verify CPU escaped lockup (x31=0x12121212)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 3: VERIFY LOCKUP ESCAPE (PHASE 1 POSITIVE CHECK)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for escape confirmation (x31=0x12121212)...");

      @(probes_cpu.x31==32'h12121212);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- lockup_o deasserted after escape ---");
      if (lockup !== 1'b0) begin
         $display("ERROR: lockup_o still asserted after NMI escape -- CPU should have recovered %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o deasserted -- CPU successfully escaped lockup %t ns", $time);
      end

      $display("");
      $display("--- NMI count (expect 1: NMI handler entered once) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- M-mode trap count (expect 1: M-trap handler entered once before lockup) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000001);


      //=================================================================
      // PHASE 4: Wait for Phase 2 ready, enter lockup with escape disabled
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 4: WAIT FOR PHASE 2 LOCKUP (ESCAPE DISABLED)              |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for Phase 2 ready (x31=0x22222222)...");

      @(probes_cpu.x31==32'h22222222);
      repeat(5) @(posedge free_clk);

      $display("Waiting for lockup_o to assert again (Phase 2 lockup)...");

      @(posedge lockup);
      repeat(5) @(posedge free_clk);

      $display("");
      $display("--- Phase 2: lockup_o asserted ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o not asserted in Phase 2 %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o asserted -- CPU entered Phase 2 lockup %t ns", $time);
      end

      // Assert NMI: irqkill_cfg[3]=0 so NMI should NOT escape lockup
      $display("");
      $display("Asserting NMI (escape disabled -- CPU should stay locked)...");
      nmi = 1'b1;
      repeat(10) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI asserted and deasserted %t ns", $time);

      // Wait N cycles after NMI -- CPU must remain locked
      repeat(50) @(posedge free_clk);


      //=================================================================
      // PHASE 5: Verify CPU did NOT escape lockup (negative check)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 5: VERIFY NO ESCAPE (PHASE 2 NEGATIVE CHECK)              |");
      $display(" ====================================================================");
      $display("");

      $display("--- lockup_o persistence (NMI fired but escape disabled) ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o deasserted unexpectedly -- NMI should NOT escape lockup when irqkill_cfg[3]=0 %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o remains asserted -- NMI did not escape lockup (escape disabled) %t ns", $time);
      end

      $display("");
      $display("--- NMI count (expect still 1: NMI handler never ran in Phase 2) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- M-mode trap count (expect 1: m_trap_handler ran once before Phase 2 lockup) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000001);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

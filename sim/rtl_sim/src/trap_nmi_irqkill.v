//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_irqkill
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI IRQKILL
//   NMI irqkill verification (2 phases):
//   Phase 1: irqkill enabled (default 0x7). NMI fires during a 33-cycle
//   radix-2 DIV — operation killed immediately, NMI handler
//   entered without waiting. After mnret, DIV restarts and
//   completes with the correct result.
//   Phase 2: irqkill disabled (irqkill_cfg=0x0). NMI fires during another
//   33-cycle DIV — NMI is held off until completion, then taken.
//   DIV result is still correct.
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

      // Disable error-on-exception (NMI entry looks like an exception)
      error_on_exception = 0;


      //=================================================================
      // INIT: Read nmi_handler address and configure nmi_vector
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|              NMI IRQKILL TEST — INIT                               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware init...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Read nmi_handler address from scratchpad[0x0C] and drive nmi_vector
      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         $display("NMI handler address from scratchpad: 0x%h %t ns", handler_addr, $time);

         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler_addr in scratchpad is 0 -- firmware did not store it %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_handler_addr stored by firmware: 0x%h %t ns", handler_addr, $time);
         end

         nmi_vector = handler_addr;
      end

      // Verify scratchpad counters are zeroed before any NMI fires
      $display("");
      $display("--- Initial counter values (all should be 0) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // nmi_count = 0
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // div_result_p1 = 0
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // div_result_p2 = 0


      //=================================================================
      // PHASE 1: NMI kills in-progress DIV (irqkill enabled, default)
      // irqkill_cfg = 0x7 (default): bit[0]=1 => muldiv kill active.
      // Firmware signals 0x12121212 immediately before the div.
      // Testbench asserts NMI for 3 cycles — the hardware should abort
      // the running division and enter the NMI handler without waiting
      // for the 33-cycle radix-2 completion.  After mnret, the div
      // restarts and produces the correct result (0x2AAAAAAB).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|     PHASE 1: NMI KILLS IN-PROGRESS DIV (irqkill enabled)           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware phase 1 ready sync...");

      @(probes_cpu.x31==32'h12121212);

      // Assert NMI immediately — div has just started (or is about to start)
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI asserted (3 cycles) during DIV — irqkill should kill div %t ns", $time);

      // Wait for firmware to complete phase 1 (div restarted and done)
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Verify phase 1 results
      $display("");
      $display("--- Phase 1 results ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // nmi_count = 1
      check_mem_value(`SPAD(32'h04), 32'h2AAAAAAB);   // div_result_p1 = 0x80000001/3


      //=================================================================
      // PHASE 2: NMI deferred until DIV completes (irqkill disabled)
      // Firmware wrote 0x0 to irqkill_cfg before this phase.
      // Firmware signals 0x23232323 immediately before the div.
      // Testbench asserts NMI for 3 cycles — the hardware must NOT kill
      // the division; the NMI is held pending until the div result is
      // written, then the handler runs (nmi_count => 2).
      // Div result is still 0x2AAAAAAB (no restart; completes normally).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|     PHASE 2: NMI DEFERRED UNTIL DIV DONE (irqkill disabled)        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware phase 2 ready sync...");

      @(probes_cpu.x31==32'h23232323);

      // Assert NMI immediately — div has just started (or is about to start)
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI asserted (3 cycles) during DIV — irqkill disabled, NMI deferred %t ns", $time);

      // Wait for firmware to complete phase 2 and reach final sync
      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      // Verify phase 2 results
      $display("");
      $display("--- Phase 2 results ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // nmi_count = 2
      check_mem_value(`SPAD(32'h08), 32'h2AAAAAAB);   // div_result_p2 = 0x80000001/3


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

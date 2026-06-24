//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_aclint_msip
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ACLINT MSWI end-to-end (self-IPI)
//   Selects the ACLINT outputs for MSIP/MTIP/SSIP via use_aclint=1, then
//   waits for the firmware to:
//     - Configure MIE.MSIE + MSTATUS.MIE
//     - Write MSIP[0]=1 to issue a self-MSI through the ACLINT
//     - Take exactly one MSI trap (mcause = 0x80000003)
//     - Clear MSIP[0] in the handler and MRET
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad byte->word index
`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Reset peripherals (standard TB pattern)
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Interrupts trigger exception monitors; suppress their error report
      error_on_exception = 0;

      // Route ACLINT outputs to the core (mux: use_aclint=0 by default)
      use_aclint = 1'b1;


      //=================================================================
      // PHASE 1: firmware configures ACLINT MSWI
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: ACLINT MSWI CONFIGURED                    |");
      $display(" ====================================================================");
      $display("Waiting for the firmware to enable MIE.MSIE...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      $display("PASS:  Phase 1 - firmware configured ACLINT MSWI %t ns", $time);


      //=================================================================
      // PHASE 2: firmware writes MSIP[0]=1 -> MSI taken -> handler clears
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: MSI SELF-IPI VIA ACLINT                   |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Trap count + last MCAUSE ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);    // trap_count = 1
      check_mem_value(`SPAD(32'h04), 32'h80000003);    // MCAUSE = MSI

      stimulus_done = 1;
   end

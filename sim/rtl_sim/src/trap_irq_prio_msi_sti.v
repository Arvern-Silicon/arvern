//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_prio_msi_sti
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: INTERRUPT PRIORITY -- MSI vs STI
//   MIDELEG=0, both MSI and STI pending and enabled, both targeting M-mode.
//   The ISA order MEI > MSI > MTI > SEI > SSI > STI requires MSI first.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

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
      use_aclint         = 1;   // MSIP is driven through the ACLINT MSWI

      $display("");
      $display(" ====================================================================");
      $display("|            PHASE 1: CONFIGURED, INTERRUPTS STILL MASKED            |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: MSI MUST BE TAKEN BEFORE STI (both pending)             |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- CSR state captured just before unmasking ---");
      $display("     mie     = 0x%08h  (expect MSIE|STIE = 0x00000028)",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)]);
      $display("     mip     = 0x%08h  (expect MSIP|STIP  set)",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)]);
      $display("     mstatus = 0x%08h",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)]);

      $display("");
      $display("--- Interrupt count (expect 2: both serviced) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- First interrupt (expect MSI = 0x80000003) ---");
      check_mem_value(`SPAD(32'h04), 32'h80000003);

      $display("");
      $display("--- Second interrupt (expect STI = 0x80000005) ---");
      check_mem_value(`SPAD(32'h08), 32'h80000005);

      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(10) @(posedge free_clk);
      stimulus_done = 1;
   end

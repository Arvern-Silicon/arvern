//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_prio_mdest_wins
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: INTERRUPT PRIORITY -- DESTINED PRIVILEGE OUTRANKS CAUSE ORDER
//   MIDELEG=SSI only. In S-mode with SSIP and STIP both pending and enabled,
//   the M-destined STI must be taken before the S-destined SSI, even though
//   SSI has the lower cause number.
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

      $display("");
      $display(" ====================================================================");
      $display("|            PHASE 1: CONFIGURED, STILL IN M-MODE                    |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: M-DESTINED STI MUST BEAT S-DESTINED SSI                 |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- CSR state captured just before entering S-mode ---");
      $display("     mie = 0x%08h  (expect SSIE|STIE = 0x00000022)",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)]);
      $display("     mip = 0x%08h  (expect SSIP|STIP  set)",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)]);

      $display("");
      $display("--- Interrupt count (expect 2: both serviced) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- First interrupt: cause (expect STI = 0x80000005) ---");
      check_mem_value(`SPAD(32'h04), 32'h80000005);

      $display("");
      $display("--- First interrupt: handler mode (expect 3 = M-mode) ---");
      check_mem_value(`SPAD(32'h08), 32'h00000003);

      $display("");
      $display("--- mstatus.SIE seen by the M handler (expect 1, untouched) ---");
      check_mem_value(`SPAD(32'h14), 32'h00000001);

      $display("");
      $display("--- Second interrupt: cause (expect SSI = 0x80000001) ---");
      check_mem_value(`SPAD(32'h0C), 32'h80000001);

      $display("");
      $display("--- Second interrupt: handler mode (expect 1 = S-mode) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000001);

      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(10) @(posedge free_clk);
      stimulus_done = 1;
   end

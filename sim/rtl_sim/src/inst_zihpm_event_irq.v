//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_irq
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT IRQ
//   Verifies that the interrupt-taken event (mhpmevent3 = 0x0A) causes
//   mhpmcounter3 to increment once per interrupt taken.
//
//   Testbench injects 4 software IRQs (one at a time, waiting for
//   trap_taken each time). Firmware polls the trap counter at 0x8000FFF0,
//   then reads mhpmcounter3 and stores it to scratchpad[0x00].
//   Expected result: irq_hpm_count == 4.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] irq_hpm_count;

`define SPAD(byte_off) (byte_off/4)

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

      $display("");
      $display(" ==================================================================");
      $display("|            ZIHPM EVENT IRQ: INTERRUPT TAKEN TEST                 |");
      $display(" ==================================================================");
      $display("");

      //=================================================================
      // Wait for firmware to set up event selector and zero counter
      //=================================================================
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("Firmware ready: mhpmevent3=0x0A, mhpmcounter3=0. Injecting 4 IRQs...");

      //=================================================================
      // Inject 4 software IRQs one at a time, waiting for each to be taken
      //=================================================================
      for (ii = 0; ii < 4; ii = ii + 1) begin
         irq_m_software = 1'b1;
         // Sample trap_taken at clock edges to avoid combinatorial glitches:
         // @(posedge trap_taken) fires on delta-cycle pulses that never persist
         // to a full clock edge; checking in the active region (after each
         // posedge, before NBA updates) only detects stable, settled assertions.
         begin : wait_trap
            forever begin
               @(posedge free_clk);
               if (dut.arv_csr_top_inst.arv_csr_traps_inst.trap_taken) disable wait_trap;
            end
         end
         @(posedge free_clk);
         irq_m_software = 1'b0;
         repeat(10) @(posedge free_clk);   // wait for mret to complete + safe gap
         $display("  IRQ %0d taken  %t ns", ii+1, $time);
      end

      $display("All 4 IRQs injected. Waiting for firmware to finish...");

      //=================================================================
      // Wait for firmware to finish polling, inhibit counter, and signal done
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;               // disable random IRQs before reading results
      repeat(3) @(posedge free_clk);

      //=================================================================
      // Check HPM counter result
      //=================================================================
      irq_hpm_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("");
      $display("HPM interrupt-taken counter result:");
      if (irq_hpm_count === 32'd4)
         $display("  PASS  interrupt event count = 4 (4 IRQs taken)  %t ns", $time);
      else begin
         $display("  ERROR interrupt event count = %0d, expected 4  %t ns",
                  irq_hpm_count, $time);
         error = error + 1;
      end

      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

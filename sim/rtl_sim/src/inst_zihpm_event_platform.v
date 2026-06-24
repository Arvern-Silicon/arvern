//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_platform
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT PLATFORM
//   Verifies that platform events 0x0B-0x12 (hpm_platform_events_i[0:7])
//   cause mhpmcounter3 to increment while the corresponding bit is asserted.
//
//   For each event i (0..7): testbench waits for firmware sync, then asserts
//   hpm_platform_events_i[i] for exactly 4 clock cycles. Firmware runs a
//   ~30-iteration delay loop, then inhibits and reads the counter.
//   Expected result: each platform counter == 4.
//
//   Note: hpm_platform_events_i is not connected in the testbench harness;
//   this file uses force/release to drive it.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] plat_count;
reg [31:0] plat_sync_vals [0:7];

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

      // No random IRQs — exact pulse counting requires a clean environment
      random_irq_enable = 0;

      // Force platform events to 0 initially (port may be unconnected / X)
      force dut.hpm_platform_events_i = 8'h00;

      // Initialize sync value lookup table
      plat_sync_vals[0] = 32'h11111111;
      plat_sync_vals[1] = 32'h22222222;
      plat_sync_vals[2] = 32'h33333333;
      plat_sync_vals[3] = 32'h44444444;
      plat_sync_vals[4] = 32'h55555555;
      plat_sync_vals[5] = 32'h66666666;
      plat_sync_vals[6] = 32'h77777777;
      plat_sync_vals[7] = 32'h88888888;

      $display("");
      $display(" ==================================================================");
      $display("|          ZIHPM EVENT PLATFORM: PLATFORM EVENTS 0-7 TEST         |");
      $display(" ==================================================================");
      $display("");

      //=================================================================
      // For each platform event: wait for firmware ready, inject 4 pulses
      //=================================================================
      for (ii = 0; ii < 8; ii = ii + 1) begin

         // Wait for firmware to configure mhpmevent3 and zero the counter
         @(probes_cpu.x31 == plat_sync_vals[ii]);
         repeat(3) @(posedge free_clk);

         $display("Platform event %0d: asserting hpm_platform_events_i[%0d] for 4 cycles  %t ns",
                  ii, ii, $time);

         // Assert platform event bit ii for exactly 4 clock cycles
         force dut.hpm_platform_events_i = (8'h01 << ii);
         repeat(4) @(posedge free_clk);
         force dut.hpm_platform_events_i = 8'h00;

         // Firmware delay loop is ~30 iterations — no need to wait here;
         // it will inhibit and write to scratchpad before asserting next sync.

      end

      //=================================================================
      // Wait for end of test
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      // Release force on platform events
      release dut.hpm_platform_events_i;

      //=================================================================
      // Check all 8 platform event counter results
      // Scratchpad word index == event index (0x00 -> word 0, 0x04 -> word 1, ...)
      //=================================================================
      $display("");
      $display("Platform event counter results:");
      for (ii = 0; ii < 8; ii = ii + 1) begin
         plat_count = ahb_bus_system_inst.sram_x_inst.mem[ii];
         if (plat_count === 32'd4)
            $display("  PASS  platform event %0d (0x%02h): count = 4  %t ns",
                     ii, 8'h0B + ii, $time);
         else begin
            $display("  ERROR platform event %0d (0x%02h): count = %0d, expected 4  %t ns",
                     ii, 8'h0B + ii, plat_count, $time);
            error = error + 1;
         end
      end

      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_fetch
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT FETCH
//   Verifies the fetch-stall HPM event counter (event selector 0x01).
//
//   Injects 3 fixed ROM wait states (s_rom_number_ws = 3) to guarantee that
//   each taken-branch backward redirect empties the decode stage for >= 3
//   cycles (~id_instruction_valid_o = 1) while the branch target instruction
//   is being fetched from ROM.
//
//   Checks that mhpmcounter3 >= 7 after executing 7 taken branches.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] fetch_count;

`define SPAD(byte_off) (byte_off/4)

initial
   begin
      random_irq_enable = 0;

      @(posedge free_clk);
      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Inject 3 fixed ROM wait states so each branch redirect creates >= 3
      // fetch stall cycles (branch target arrives 3 cycles late).
      s_rom_number_ws = 3;

      random_irq_enable = 1;

      $display("");
      $display(" ====================================================================");
      $display("|              ZIHPM EVENT FETCH: FETCH STALL COUNTER TEST           |");
      $display(" ====================================================================");
      $display("");

      // Wait for end of test
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;        // disable random IRQs before reading results
      repeat(3) @(posedge free_clk);

      //=================================================================
      // Read and verify fetch-stall counter
      //=================================================================
      fetch_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("  fetch stall count = %0d (after 7 taken branches with 3-WS ROM)", fetch_count);

      // >= 7: each of 7 backward branch redirects creates >= 3 stall cycles with 3-WS ROM
      if (fetch_count >= 32'd7)
         $display("  PASS  fetch stall count=%0d >= 7 (fetch stall event functional)  %t ns",
                  fetch_count, $time);
      else begin
         $display("  ERROR fetch stall count=%0d, expected >= 7 (fetch stall event 0x01 not counting)  %t ns",
                  fetch_count, $time);
         error = error + 1;
      end

      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      s_rom_number_ws = 0;          // Restore ROM wait states
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

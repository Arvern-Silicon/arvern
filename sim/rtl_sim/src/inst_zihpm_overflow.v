//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_overflow
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM OVERFLOW
//   Zihpm HPM counter 64-bit overflow and CSR write/readback verification:
//   Phase 1 — mhpmcounterh3 write and readback
//   Phase 2 — hpmcounterh3 (shadow) reflects mhpmcounterh3 when inhibited
//   Phase 3 — 64-bit counter overflow: lo wraps to 0, hi increments to 1
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] hi_rb;
reg [31:0] shadow_rb;
reg [31:0] hi_after;
reg [31:0] lo_after;

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

      // Disable random IRQs immediately — exact counting test
      random_irq_enable = 0;


      $display("");
      $display(" ====================================================================");
      $display("|             ZIHPM OVERFLOW: HPM 64-BIT OVERFLOW TEST               |");
      $display(" ====================================================================");
      $display("");


      //=================================================================
      // PHASE 1: mhpmcounterh3 write and readback
      // Expect: mhpmcounterh3 == 0xABCDEF12
      //=================================================================
      $display("Waiting for Phase 1 sync (0x11111111)...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      hi_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

      $display("");
      $display(" ----------------------------------------------------");
      $display("  Phase 1: mhpmcounterh3 write/readback");
      $display(" ----------------------------------------------------");
      $display("  mhpmcounterh3 readback (expect 0xABCDEF12): 0x%h  %t ns", hi_rb, $time);

      if (hi_rb === 32'hABCDEF12)
         $display("  PASS  phase1: mhpmcounterh3 readback = 0xABCDEF12  %t ns", $time);
      else begin
         $display("  ERROR phase1: mhpmcounterh3 readback = 0x%h, expected 0xABCDEF12  %t ns",
                  hi_rb, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 2: hpmcounterh3 shadow readback
      // Expect: hpmcounterh3 == 0x12345678 (matches mhpmcounterh3 when inhibited)
      //=================================================================
      $display("");
      $display("Waiting for Phase 2 sync (0x22222222)...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      shadow_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

      $display("");
      $display(" ----------------------------------------------------");
      $display("  Phase 2: hpmcounterh3 shadow readback");
      $display(" ----------------------------------------------------");
      $display("  hpmcounterh3 shadow readback (expect 0x12345678): 0x%h  %t ns", shadow_rb, $time);

      if (shadow_rb === 32'h12345678)
         $display("  PASS  phase2: hpmcounterh3 shadow = 0x12345678 (matches mhpmcounterh3)  %t ns",
                  $time);
      else begin
         $display("  ERROR phase2: hpmcounterh3 shadow = 0x%h, expected 0x12345678  %t ns",
                  shadow_rb, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 3: 64-bit overflow
      // Expect: hi_after == 1 (carry from lo overflow), lo_after == 0
      //=================================================================
      $display("");
      $display("Waiting for Phase 3 sync (0xdeadbeef)...");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      hi_after = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
      lo_after = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

      $display("");
      $display(" ----------------------------------------------------");
      $display("  Phase 3: 64-bit overflow");
      $display(" ----------------------------------------------------");
      $display("  mhpmcounterh3 after overflow (expect 0x00000001): 0x%h  %t ns", hi_after, $time);
      $display("  mhpmcounter3  after overflow (expect 0x00000000): 0x%h  %t ns", lo_after, $time);

      if (hi_after === 32'h1)
         $display("  PASS  phase3: 64-bit carry: hi incremented to 1  %t ns", $time);
      else begin
         $display("  ERROR phase3: mhpmcounterh3 = 0x%h, expected 0x1 (no carry propagated)  %t ns",
                  hi_after, $time);
         error = error + 1;
      end

      if (lo_after === 32'h0)
         $display("  PASS  phase3: 64-bit carry: lo wrapped to 0  %t ns", $time);
      else begin
         $display("  ERROR phase3: mhpmcounter3 = 0x%h, expected 0x0 (lo did not wrap)  %t ns",
                  lo_after, $time);
         error = error + 1;
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

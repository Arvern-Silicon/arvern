//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_cycle
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR CYCLE
//   Zicntr mcycle/cycleh CSR deep verification:
//   - mcycle write/readback (preset >= written value)
//   - mcycleh write/readback (exact match)
//   - mcountinhibit[0] (CY bit) freezes mcycle: two reads identical
//   - cycle (0xC00) shadow == mcycle while inhibited (same window)
//   - WFI: cycle counter is FROZEN while processor sleeps (clock-gated)
//   - 64-bit carry: mcycle lo-to-hi carry propagation (hi increments by 1)
//----------------------------------------------------------------------------

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


      //=================================================================
      // PHASE 1: mcycle write/readback
      // Write 0xDEAD1000, read back immediately.
      // Readback must be >= written value (counter keeps running).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: MCYCLE WRITE/READBACK                         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : check_phase1_preset
         reg [31:0] preset_rb;
         preset_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

         $display("mcycle readback after writing 0xDEAD1000: 0x%h  %t ns", preset_rb, $time);

         if (preset_rb >= 32'hDEAD1000) begin
            $display("PASS:  mcycle readback 0x%h >= preset 0xDEAD1000 %t ns", preset_rb, $time);
         end else begin
            $display("ERROR: mcycle readback 0x%h < preset 0xDEAD1000 %t ns", preset_rb, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 2: mcycleh write/readback
      // Write 0xABCD0000 to mcycleh; readback must match exactly.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 2: MCYCLEH WRITE/READBACK                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      begin : check_phase2_cycleh
         reg [31:0] cycleh_rb;
         cycleh_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

         $display("mcycleh readback after writing 0xABCD0000: 0x%h  %t ns", cycleh_rb, $time);

         if (cycleh_rb === 32'hABCD0000) begin
            $display("PASS:  mcycleh readback 0x%h matches preset 0xABCD0000 %t ns", cycleh_rb, $time);
         end else begin
            $display("ERROR: mcycleh readback 0x%h != preset 0xABCD0000 %t ns", cycleh_rb, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 3: mcountinhibit[0] (CY bit) freezes mcycle
      // Two consecutive csrr of mcycle while inhibited must be equal.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 3: MCOUNTINHIBIT[0] FREEZES MCYCLE               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      begin : check_phase3_inhibit
         reg [31:0] rd1;
         reg [31:0] rd2;
         rd1 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         rd2 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

         $display("mcycle read 1 (CY inhibited): 0x%h  %t ns", rd1, $time);
         $display("mcycle read 2 (CY inhibited): 0x%h  %t ns", rd2, $time);

         if (rd1 === rd2) begin
            $display("PASS:  mcycle frozen while CY inhibited (both reads = 0x%h) %t ns", rd1, $time);
         end else begin
            $display("ERROR: mcycle advanced while CY inhibited -- rd1=0x%h rd2=0x%h %t ns", rd1, rd2, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 4: cycle shadow (0xC00) == mcycle (0xB00) while CY inhibited
      // Both reads in the same inhibit window must be identical.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 4: CYCLE SHADOW == MCYCLE WHILE INHIBITED        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      begin : check_phase4_shadow
         reg [31:0] cycle_shadow;
         reg [31:0] mcycle_direct;
         cycle_shadow   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
         mcycle_direct  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];

         $display("cycle  shadow (0xC00) while inhibited: 0x%h  %t ns", cycle_shadow,  $time);
         $display("mcycle direct (0xB00) while inhibited: 0x%h  %t ns", mcycle_direct, $time);

         if (cycle_shadow === mcycle_direct) begin
            $display("PASS:  cycle shadow == mcycle direct while CY inhibited (0x%h) %t ns",
                     cycle_shadow, $time);
         end else begin
            $display("ERROR: cycle shadow (0x%h) != mcycle direct (0x%h) while inhibited %t ns",
                     cycle_shadow, mcycle_direct, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 5: WFI — cycle counter is FROZEN while sleeping (clock-gated)
      // Testbench waits 200 cycles after sync 0x55555555 then asserts
      // irq_m_timer.  Because hclk_en_o drops during WFI sleep, the SoC-level
      // ICG gates hclk and mcycle stops ticking.  After WFI returns,
      // cycle_after - cycle_before must be SMALL (entry+exit overhead only:
      // ~25 cycles nominal, ~100 worst-case under -gahb + triple random
      // wait states) -- NOT the full ~200-cycle wait window.  Threshold 175.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 5: WFI — CYCLE FROZEN DURING CLOCK-GATED SLEEP       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);    // firmware about to execute WFI
      random_irq_enable = 0;              // disable random IRQs: WFI uses mstatus.MIE=1
                                          // and a pending random IRQ would wake WFI
                                          // immediately (giving delta<150) or cause an
                                          // infinite IRQ loop if the IRQ stays asserted

      repeat(200) @(posedge free_clk);    // wait 200 cycles to ensure WFI is executing
      irq_m_timer = 1'b1;                   // assert timer IRQ to wake processor
      repeat(5)   @(posedge free_clk);

      wait(probes_cpu.x31==32'h66666666); // use wait() in case already past
      irq_m_timer = 1'b0;                   // deassert timer IRQ (phase 5 done)
      repeat(3) @(posedge free_clk);

      begin : check_phase5_wfi
         reg [31:0] cycle_before;
         reg [31:0] cycle_after;
         reg [31:0] delta;
         cycle_before = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         cycle_after  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];
         delta        = cycle_after - cycle_before;

         $display("mcycle before WFI: 0x%h  %t ns", cycle_before, $time);
         $display("mcycle after  WFI: 0x%h  %t ns", cycle_after,  $time);
         $display("delta             : %0d cycles", delta);

         // Expect SMALL delta: only the clocked WFI entry/exit overhead
         // (WFI decode + AHB-drain-to-sleep_safe + wakeup pipeline refill +
         // IRQ entry/handler/mret) contributes.  The PHASE-5 forced idle
         // window is ~200 cycles (repeat(200) above); a correct clock-gated
         // freeze => delta << 200 because the ~186-cycle gated sleep window
         // adds ZERO.  A genuine gating break (mcycle ticking through sleep)
         // => delta ~= overhead + ~186 ~= ~286.  Nominal entry/exit overhead
         // is ~25 cycles; worst-case *legitimate* overhead under -gahb (deep
         // AHB interconnect) + -rwsrom -rwsram -rwsper (random wait states on
         // every memory) reaches ~100.  Threshold 175 leaves ~75-cycle margin
         // above worst-case legitimate overhead while staying far below the
         // ~286 a real regression produces (and below the ~186-cycle real
         // gated window), so any leak of the sleep window into mcycle still
         // trips this check.
         if (delta < 32'd175) begin
            $display("PASS:  mcycle frozen during WFI sleep (delta=%0d cycles, < 175) %t ns", delta, $time);
         end else begin
            $display("ERROR: cycle delta=%0d >= 175 -- mcycle kept counting during WFI (clock-gating broken?) %t ns",
                     delta, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 6: 64-bit carry — mcycle lo-to-hi carry propagation
      // Preset lo=0xFFFFFFFE hi=0x12345678 with inhibit, then free-run.
      // After carry: carry_hi must be exactly 0x12345679.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 6: 64-BIT CARRY (mcycle lo to hi)               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      begin : check_phase6_carry
         reg [31:0] carry_lo;
         reg [31:0] carry_hi;
         carry_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         carry_hi = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];

         $display("mcycle lo after carry: 0x%h  %t ns", carry_lo, $time);
         $display("mcycle hi after carry: 0x%h  %t ns", carry_hi, $time);

         if (carry_hi === 32'h12345679)
            $display("PASS:  mcycle hi = 0x12345679 (exactly one carry from lo) %t ns", $time);
         else begin
            $display("ERROR: mcycle hi = 0x%h, expected 0x12345679 %t ns", carry_hi, $time);
            error = error + 1;
         end

         if (carry_lo < 32'hFFFFFFFE)
            $display("PASS:  mcycle lo = 0x%h < 0xFFFFFFFE (lo overflowed) %t ns",
                     carry_lo, $time);
         else begin
            $display("ERROR: mcycle lo = 0x%h >= 0xFFFFFFFE (overflow may not have happened) %t ns",
                     carry_lo, $time);
            error = error + 1;
         end
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

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_basic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR BASIC
//   Zicntr counter CSR verification:
//   - mcycle / mcycleh   (0xB00 / 0xB80): R/W, increments each cycle
//   - minstret / minstreth (0xB02 / 0xB82): R/W, increments per retired
//   - mcountinhibit (0x320): bits[2:0] stop counting when set
//   - time / timeh (0xC01 / 0xC81): read-only, external mtime
//   - cycle / cycleh / instret / instreth: read-only shadows
//   - mcounteren (0x306): write/readback of bits [2:0]
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
      // PHASE 1: mcycle increments across a delay loop
      // Verify that the cycle counter value after the loop is strictly
      // greater than the value sampled before the loop.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: MCYCLE INCREMENTS ACROSS DELAY LOOP           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : check_phase1_cycle
         reg [31:0] cycle_before;
         reg [31:0] cycle_after;
         cycle_before = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         cycle_after  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

         $display("mcycle before delay loop : 0x%h  %t ns", cycle_before, $time);
         $display("mcycle after  delay loop : 0x%h  %t ns", cycle_after,  $time);

         if (cycle_after > cycle_before) begin
            $display("PASS:  mcycle advanced across the delay loop (after=0x%h > before=0x%h) %t ns",
                     cycle_after, cycle_before, $time);
         end else begin
            $display("ERROR: mcycle did NOT advance -- before=0x%h after=0x%h %t ns",
                     cycle_before, cycle_after, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 2: minstret counts retired instructions
      // Verify that the delta between after and before is at least 5
      // (we executed exactly 5 ADDI instructions plus overhead).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 2: MINSTRET COUNTS RETIRED INSTRUCTIONS          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      begin : check_phase2_instret
         reg [31:0] instret_before;
         reg [31:0] instret_after;
         reg [31:0] delta;
         instret_before = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         instret_after  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         delta          = instret_after - instret_before;

         $display("minstret before 5-ADDI sequence : 0x%h  %t ns", instret_before, $time);
         $display("minstret after  5-ADDI sequence : 0x%h  %t ns", instret_after,  $time);
         $display("delta                           : %0d  %t ns",   delta,          $time);

         if (delta >= 32'd5) begin
            $display("PASS:  minstret delta=%0d >= 5 (5 ADDIs plus overhead) %t ns", delta, $time);
         end else begin
            $display("ERROR: minstret delta=%0d < 5 -- expected at least 5 retirements %t ns",
                     delta, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 3: mcountinhibit stops cycle and instret counting
      //
      // 3a. Preset mcycle to 0x12345600: readback must be >= 0x12345600
      //     (counter may have advanced a few cycles by the time of the read).
      // 3b. While CY inhibit active: two consecutive csrr of mcycle must
      //     read the same value (stored at 0x14 and 0x18).
      // 3c. While IR inhibit active: minstret must not advance across the
      //     5 ADDI block — checked via register probes t4(x28) and t5(x29).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 3: MCOUNTINHIBIT STOPS COUNTING                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // 3a: preset readback
      begin : check_phase3a_preset
         reg [31:0] preset_rb;
         preset_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];

         $display("");
         $display("--- 3a: mcycle preset readback (written 0x12345600, may have advanced a few) ---");
         $display("mcycle preset readback: 0x%h  %t ns", preset_rb, $time);

         if (preset_rb >= 32'h12345600) begin
            $display("PASS:  mcycle readback 0x%h >= preset 0x12345600 %t ns", preset_rb, $time);
         end else begin
            $display("ERROR: mcycle readback 0x%h < preset 0x12345600 %t ns", preset_rb, $time);
            error = error + 1;
         end
      end

      // 3b: cycle inhibit — two consecutive csrr must give identical values
      begin : check_phase3b_inhibit_cycle
         reg [31:0] cyc_rd1;
         reg [31:0] cyc_rd2;
         cyc_rd1 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];
         cyc_rd2 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];

         $display("");
         $display("--- 3b: mcycle reads while CY inhibited (expect identical values) ---");
         $display("mcycle read 1 (inhibited): 0x%h  %t ns", cyc_rd1, $time);
         $display("mcycle read 2 (inhibited): 0x%h  %t ns", cyc_rd2, $time);

         if (cyc_rd1 === cyc_rd2) begin
            $display("PASS:  mcycle did not advance while inhibited (both reads = 0x%h) %t ns",
                     cyc_rd1, $time);
         end else begin
            $display("ERROR: mcycle advanced while CY inhibit was set -- rd1=0x%h rd2=0x%h %t ns",
                     cyc_rd1, cyc_rd2, $time);
            error = error + 1;
         end
      end

      // 3c: instret inhibit — t4(x29) before and t5(x30) after must be equal
      begin : check_phase3c_inhibit_instret
         reg [31:0] instret_inh_before;
         reg [31:0] instret_inh_after;
         instret_inh_before = probes_cpu.x29;   // t4: sampled before 5 ADDIs
         instret_inh_after  = probes_cpu.x30;   // t5: sampled after  5 ADDIs

         $display("");
         $display("--- 3c: minstret while IR inhibited (expect no advance across 5 ADDIs) ---");
         $display("minstret before 5 ADDIs (inhibited): 0x%h  %t ns", instret_inh_before, $time);
         $display("minstret after  5 ADDIs (inhibited): 0x%h  %t ns", instret_inh_after,  $time);

         if (instret_inh_before === instret_inh_after) begin
            $display("PASS:  minstret did not advance while IR inhibit was set %t ns", $time);
         end else begin
            $display("ERROR: minstret advanced while IR inhibit was set -- before=0x%h after=0x%h %t ns",
                     instret_inh_before, instret_inh_after, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 4: time and timeh read-only CSRs
      // time_lo (0xC01) should be non-zero (many cycles have elapsed).
      // time_hi (0xC81) should be zero (simulation not long enough to overflow).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 4: TIME AND TIMEH READ-ONLY CSRs                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      begin : check_phase4_time
         reg [31:0] time_lo;
         reg [31:0] time_hi;
         time_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];
         time_hi = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];

         $display("time  (0xC01): 0x%h  %t ns", time_lo, $time);
         $display("timeh (0xC81): 0x%h  %t ns", time_hi, $time);

         if (time_lo !== 32'h0) begin
            $display("PASS:  time_lo is non-zero (0x%h) — mtime is running %t ns", time_lo, $time);
         end else begin
            $display("ERROR: time_lo is 0x0 — mtime does not appear to be running %t ns", $time);
            error = error + 1;
         end

         if (time_hi === 32'h0) begin
            $display("PASS:  time_hi is 0x0 (simulation too short to overflow) %t ns", $time);
         end else begin
            $display("INFO:  time_hi is non-zero (0x%h) — simulation ran a very long time %t ns",
                     time_hi, $time);
         end
      end


      //=================================================================
      // PHASE 5: cycle / cycleh / instret / instreth read-only shadow CSRs
      // cycle (0xC00) and instret (0xC02) must be non-zero.
      // cycleh (0xC80) and instreth (0xC82) must be zero (no overflow yet).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 5: CYCLE/CYCLEH/INSTRET/INSTRETH SHADOWS         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      begin : check_phase5_shadows
         reg [31:0] cycle_shadow;
         reg [31:0] instret_shadow;
         reg [31:0] cycleh_shadow;
         reg [31:0] instreth_shadow;
         cycle_shadow    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];
         instret_shadow  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];
         cycleh_shadow   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)];
         instreth_shadow = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];

         $display("cycle   (0xC00) shadow: 0x%h  %t ns", cycle_shadow,    $time);
         $display("instret (0xC02) shadow: 0x%h  %t ns", instret_shadow,  $time);
         $display("cycleh  (0xC80) shadow: 0x%h  %t ns", cycleh_shadow,   $time);
         $display("instreth(0xC82) shadow: 0x%h  %t ns", instreth_shadow, $time);

         if (cycle_shadow !== 32'h0)
            $display("PASS:  cycle shadow is non-zero (0x%h) %t ns", cycle_shadow, $time);
         else begin
            $display("ERROR: cycle shadow reads 0x0 %t ns", $time);
            error = error + 1;
         end

         if (instret_shadow !== 32'h0)
            $display("PASS:  instret shadow is non-zero (0x%h) %t ns", instret_shadow, $time);
         else begin
            $display("ERROR: instret shadow reads 0x0 %t ns", $time);
            error = error + 1;
         end

         if (cycleh_shadow === 32'h0)
            $display("PASS:  cycleh shadow is 0x0 (no overflow at test duration) %t ns", $time);
         else begin
            $display("ERROR: cycleh shadow is 0x%h, expected 0x0 %t ns", cycleh_shadow, $time);
            error = error + 1;
         end

         if (instreth_shadow === 32'h0)
            $display("PASS:  instreth shadow is 0x0 (no overflow at test duration) %t ns", $time);
         else begin
            $display("ERROR: instreth shadow is 0x%h, expected 0x0 %t ns", instreth_shadow, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 6: mcounteren write/readback
      // Write 0x7 (all bits), read back (expect 0x7).
      // Write 0x0 (all cleared), read back (expect 0x0).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 6: MCOUNTEREN WRITE/READBACK                     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      begin : check_phase6_mcounteren
         reg [31:0] mcounteren_7;
         reg [31:0] mcounteren_0;
         mcounteren_7 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)];
         mcounteren_0 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)];

         $display("mcounteren after writing 0x7: 0x%h  %t ns", mcounteren_7, $time);
         $display("mcounteren after writing 0x0: 0x%h  %t ns", mcounteren_0, $time);

         if (mcounteren_7[2:0] === 3'h7)
            $display("PASS:  mcounteren[2:0] = 0x7 after writing 0x7 %t ns", $time);
         else begin
            $display("ERROR: mcounteren readback 0x%h[2:0] != 0x7 after writing 0x7 %t ns",
                     mcounteren_7, $time);
            error = error + 1;
         end

         if (mcounteren_0[2:0] === 3'h0)
            $display("PASS:  mcounteren[2:0] = 0x0 after writing 0x0 %t ns", $time);
         else begin
            $display("ERROR: mcounteren readback 0x%h[2:0] != 0x0 after writing 0x0 %t ns",
                     mcounteren_0, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 7: mcountinhibit[1] (TM bit) WARL — must always read 0
      // Write 0x7 to mcountinhibit; readback must be 0x5 (bit 1 = 0).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 7: MCOUNTINHIBIT[1] (TM BIT) WARL               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);

      begin : check_phase7_mcountinhibit_warl
         reg [31:0] inh_rb;
         inh_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h3C)];

         $display("mcountinhibit readback after writing 0x7: 0x%h  %t ns", inh_rb, $time);

         if (inh_rb === 32'h5)
            $display("PASS:  mcountinhibit = 0x5 (bit1/TM hardwired to 0 per WARL) %t ns", $time);
         else begin
            $display("ERROR: mcountinhibit = 0x%h, expected 0x5 (bit1 should be 0) %t ns",
                     inh_rb, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 8: mcounteren upper bits WARL — bits[31:11] must read 0
      // Write 0xFFFFFFFF; readback bits[31:11] must be 0 (unimplemented
      // HPM counters above 10 are WARL hardwired to 0).
      // Bits[10:0] may be non-zero depending on ZIHPM_NR config.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 8: MCOUNTEREN UPPER BITS WARL (bits[31:11]=0)   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;       // Disable random IRQs before final checks
      repeat(3) @(posedge free_clk);

      begin : check_phase8_mcounteren_warl
         reg [31:0] cen_rb;
         cen_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)];

         $display("mcounteren readback after writing 0xFFFFFFFF: 0x%h  %t ns", cen_rb, $time);

         if (cen_rb[31:11] === 21'h0)
            $display("PASS:  mcounteren[31:11] = 0 (WARL: unimplemented bits hardwired to 0), full=0x%h %t ns",
                     cen_rb, $time);
         else begin
            $display("ERROR: mcounteren[31:11] = 0x%h, expected 0 (upper WARL bits not zeroed) %t ns",
                     cen_rb[31:11], $time);
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

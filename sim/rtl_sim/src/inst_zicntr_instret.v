//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_instret
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR INSTRET
//   Zicntr minstret/instreth CSR deep verification:
//   - minstret write/readback (preset >= written value)
//   - minstreth write/readback (exact match)
//   - mcountinhibit[2] (IR bit) freezes minstret: two reads identical
//   - instret (0xC02) shadow == minstret while inhibited (same window)
//   - Exact instruction count in inhibit-gated window: 7
//   - Hazard instruction count (load-use, branch, CSR hazards): 16
//   - WFI counts as exactly 1 instruction: window total = 3
//   - 64-bit carry: minstret lo-to-hi carry propagation
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
      // PHASE 1: minstret write/readback
      // Write 0xBEEF0000, read back immediately.
      // Readback must be >= written value (counter keeps running).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: MINSTRET WRITE/READBACK                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : check_phase1_preset
         reg [31:0] preset_rb;
         preset_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];

         $display("minstret readback after writing 0xBEEF0000: 0x%h  %t ns", preset_rb, $time);

         if (preset_rb >= 32'hBEEF0000) begin
            $display("PASS:  minstret readback 0x%h >= preset 0xBEEF0000 %t ns", preset_rb, $time);
         end else begin
            $display("ERROR: minstret readback 0x%h < preset 0xBEEF0000 %t ns", preset_rb, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 2: minstreth write/readback
      // Write 0xCAFE0000 to minstreth; readback must match exactly.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 2: MINSTRETH WRITE/READBACK                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      begin : check_phase2_instreth
         reg [31:0] instreth_rb;
         instreth_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

         $display("minstreth readback after writing 0xCAFE0000: 0x%h  %t ns", instreth_rb, $time);

         if (instreth_rb === 32'hCAFE0000) begin
            $display("PASS:  minstreth readback 0x%h matches preset 0xCAFE0000 %t ns", instreth_rb, $time);
         end else begin
            $display("ERROR: minstreth readback 0x%h != preset 0xCAFE0000 %t ns", instreth_rb, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 3: mcountinhibit[2] (IR bit) freezes minstret
      // Two consecutive csrr of minstret while inhibited must be equal.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 3: MCOUNTINHIBIT[2] FREEZES MINSTRET             |");
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

         $display("minstret read 1 (IR inhibited): 0x%h  %t ns", rd1, $time);
         $display("minstret read 2 (IR inhibited): 0x%h  %t ns", rd2, $time);

         if (rd1 === rd2) begin
            $display("PASS:  minstret frozen while IR inhibited (both reads = 0x%h) %t ns", rd1, $time);
         end else begin
            $display("ERROR: minstret advanced while IR inhibited -- rd1=0x%h rd2=0x%h %t ns",
                     rd1, rd2, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 4: instret shadow (0xC02) == minstret (0xB02) while IR inhibited
      // Both reads in the same inhibit window must be identical.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 4: INSTRET SHADOW == MINSTRET WHILE INHIBITED    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      begin : check_phase4_shadow
         reg [31:0] shadow;
         reg [31:0] direct;
         shadow = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
         direct = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];

         $display("instret shadow (0xC02) while inhibited: 0x%h  %t ns", shadow, $time);
         $display("minstret direct (0xB02) while inhibited: 0x%h  %t ns", direct, $time);

         if (shadow === direct) begin
            $display("PASS:  instret shadow == minstret direct while IR inhibited (0x%h) %t ns",
                     shadow, $time);
         end else begin
            $display("ERROR: instret shadow (0x%h) != minstret direct (0x%h) while inhibited %t ns",
                     shadow, direct, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 5: EXACT instruction count in inhibit-gated window
      // 5 ADDIs + li + csrrs = 7 instructions total in window.
      // Expected: exact_count == 7
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 5: EXACT INSTRUCTION COUNT (expect 7)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      begin : check_phase5_exact
         reg [31:0] exact_count;
         exact_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];

         $display("minstret exact count (window): %0d  %t ns", exact_count, $time);

         if (exact_count === 32'd7) begin
            $display("PASS:  exact instruction count = %0d (expected 7) %t ns", exact_count, $time);
         end else begin
            $display("ERROR: exact count = %0d, expected 7 %t ns", exact_count, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 6: HAZARD instruction count in inhibit-gated window
      // Load-use stalls, branch loop, CSR hazard: all count retirements.
      // Expected: hazard_count == 16
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 6: HAZARD INSTRUCTION COUNT (expect 16)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      begin : check_phase6_hazard
         reg [31:0] hazard_count;
         hazard_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];

         $display("minstret hazard count (window): %0d  %t ns", hazard_count, $time);

         if (hazard_count === 32'd16) begin
            $display("PASS:  hazard instruction count = %0d (expected 16) %t ns",
                     hazard_count, $time);
         end else begin
            $display("ERROR: hazard count = %0d, expected 16 %t ns", hazard_count, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 7: WFI counts as exactly 1 instruction
      // Firmware sets mie.MTIE=1 (mstatus.MIE stays 0).
      // irq_m_timer is asserted by testbench; mip.MTIP & mie.MTIE != 0
      // causes WFI to wake without taking an interrupt (MIE=0).
      // Window: WFI(1) + li(2) + csrrs(3) = 3 total.
      // Expected: wfi_count == 3
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 7: WFI COUNTS AS 1 INSTRUCTION (expect 3)        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h77777777);    // firmware enabled mie.MTIE and is about to enter WFI
      repeat(3) @(posedge free_clk);
      irq_m_timer = 1'b1;                   // assert timer IRQ; keep asserted until test completes
                                          // mstatus.MIE=0 so WFI wakes but no ISR is taken

      wait(probes_cpu.x31==32'h88888888); // phase 7 done
      irq_m_timer = 1'b0;                   // deassert after WFI completes
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      begin : check_phase7_wfi
         reg [31:0] wfi_count;
         wfi_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];

         $display("minstret WFI window count: %0d  %t ns", wfi_count, $time);

         if (wfi_count === 32'd3) begin
            $display("PASS:  WFI window count = %0d (expected 3: WFI+li+csrrs) %t ns",
                     wfi_count, $time);
         end else begin
            $display("ERROR: WFI window count = %0d, expected 3 %t ns", wfi_count, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 8: 64-bit carry — minstret lo-to-hi carry propagation
      // Preset lo=0xFFFFFFFE hi=0xABCD5678 with inhibit, then free-run.
      // 12 retirements total between clear and re-inhibit.
      // Expected: carry_lo == 0x0000000A, carry_hi == 0xABCD5679.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 8: 64-BIT CARRY (minstret lo to hi)             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      begin : check_phase8_carry
         reg [31:0] carry_lo;
         reg [31:0] carry_hi;
         carry_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];
         carry_hi = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];

         $display("minstret lo after carry: 0x%h  %t ns", carry_lo, $time);
         $display("minstret hi after carry: 0x%h  %t ns", carry_hi, $time);

         if (carry_hi === 32'hABCD5679)
            $display("PASS:  minstret hi = 0xABCD5679 (exactly one carry from lo) %t ns", $time);
         else begin
            $display("ERROR: minstret hi = 0x%h, expected 0xABCD5679 %t ns", carry_hi, $time);
            error = error + 1;
         end

         if (carry_lo === 32'h0000000A)
            $display("PASS:  minstret lo = 0x0000000A (0xFFFFFFFE + 12 retirements, overflow at +2) %t ns",
                     $time);
         else begin
            $display("ERROR: minstret lo = 0x%h, expected 0x0000000A %t ns", carry_lo, $time);
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

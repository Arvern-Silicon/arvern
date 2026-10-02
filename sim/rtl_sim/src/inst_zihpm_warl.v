//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM WARL
//   Verifies WARL properties of mhpmevent and mcountinhibit.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] p1_event_12;
reg [31:0] p1_event_ff12;
reg [31:0] p2_event_13;
reg [31:0] p2_event_1f;
reg [31:0] p3_inhibit_ff;

`define SPAD(byte_off) ((byte_off)/4)

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

      $display("");
      $display(" ====================================================================");
      $display("|           ZIHPM WARL: HPM CSR WARL PROPERTY TEST                   |");
      $display(" ====================================================================");
      $display("");


      //=================================================================
      // PHASE 1: mhpmevent3 — 5-bit WARL
      //=================================================================
      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      p1_event_12   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      p1_event_ff12 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
      $display("  Phase 1: mhpmevent3 WARL");
      $display("    write 0x00000012 → readback = 0x%h  %t ns", p1_event_12, $time);
      $display("    write 0xFFFFFF12 → readback = 0x%h  %t ns", p1_event_ff12, $time);

      if (p1_event_12 === 32'h00000012)
         $display("  PASS  phase1a: implemented selector 0x12 stored verbatim, bits[31:5]=0  %t ns", $time);
      else begin
         $display("  ERROR phase1a: write 0x12 → got 0x%h, expected 0x00000012  %t ns",
                  p1_event_12, $time);
         error = error + 1;
      end

      if (p1_event_ff12 === 32'h00000000)
         $display("  PASS  phase1b: write with bits above [4:0] set folds to 0 (strict WARL)  %t ns", $time);
      else begin
         $display("  ERROR phase1b: write 0xFFFFFF12 → got 0x%h, expected 0x00000000 (unimplemented value folds to 0)  %t ns",
                  p1_event_ff12, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 2: mhpmevent3 unimplemented selector write/readback
      //=================================================================
      @(probes_cpu.x31 == 32'h22222222);
      repeat(3) @(posedge free_clk);

      p2_event_13 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
      p2_event_1f = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

      $display("");
      $display("  Phase 2: mhpmevent3 unimplemented selector readback");
      $display("    write 0x13 → readback = 0x%h  %t ns", p2_event_13, $time);
      $display("    write 0x1F → readback = 0x%h  %t ns", p2_event_1f, $time);

      if (p2_event_13 === 32'h00000000)
         $display("  PASS  phase2a: unimplemented selector 0x13 folds to 0 (strict WARL)  %t ns", $time);
      else begin
         $display("  ERROR phase2a: write 0x13 → got 0x%h, expected 0x00000000 (unimplemented selector folds to 0)  %t ns",
                  p2_event_13, $time);
         error = error + 1;
      end

      if (p2_event_1f === 32'h00000000)
         $display("  PASS  phase2b: unimplemented selector 0x1F folds to 0 (strict WARL)  %t ns", $time);
      else begin
         $display("  ERROR phase2b: write 0x1F → got 0x%h, expected 0x00000000 (unimplemented selector folds to 0)  %t ns",
                  p2_event_1f, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 3: mcountinhibit WARL mask per ZIHPM_NR
      //=================================================================
      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      p3_inhibit_ff = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];

      $display("");
      $display("  Phase 3: mcountinhibit WARL (write 0xFFFFFFFF, ZIHPM_NR=%0d)", ZIHPM_NR);
      $display("    readback = 0x%h  %t ns", p3_inhibit_ff, $time);

      // Bits [31:11] must always be 0; bit 1 (TM) must be 0 (WARL hardwired to 0,
      // since mtime is memory-mapped and cannot be inhibited via mcountinhibit).
      // Bits 0 (CY) and 2 (IR) are valid writable inhibit bits for mcycle/minstret.
      if (p3_inhibit_ff[31:11] !== 21'h0 || p3_inhibit_ff[1] !== 1'b0) begin
         $display("  ERROR phase3: mcountinhibit reserved bits non-zero: 0x%h  %t ns",
                  p3_inhibit_ff, $time);
         $display("    (expected bits[31:11]=0, bit[1]=0)");
         error = error + 1;
      end else begin
         // Bits [10:3] must equal HPM_WARL_MASK for the configured ZIHPM_NR
         begin : inhibit_warl_check
            reg [7:0] hpm_warl_mask;
            hpm_warl_mask = (ZIHPM_NR == 0) ? 8'h00 :
                            (ZIHPM_NR == 1) ? 8'h01 :
                            (ZIHPM_NR == 2) ? 8'h03 :
                            (ZIHPM_NR == 3) ? 8'h07 :
                            (ZIHPM_NR == 4) ? 8'h0F :
                            (ZIHPM_NR == 5) ? 8'h1F :
                            (ZIHPM_NR == 6) ? 8'h3F :
                            (ZIHPM_NR == 7) ? 8'h7F : 8'hFF;
            if (p3_inhibit_ff[10:3] === hpm_warl_mask)
               $display("  PASS  phase3: mcountinhibit[10:3]=0x%h == HPM_WARL_MASK for ZIHPM_NR=%0d  %t ns",
                        hpm_warl_mask, ZIHPM_NR, $time);
            else begin
               $display("  ERROR phase3: mcountinhibit[10:3]=0x%h, expected 0x%h for ZIHPM_NR=%0d  %t ns",
                        p3_inhibit_ff[10:3], hpm_warl_mask, ZIHPM_NR, $time);
               error = error + 1;
            end
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

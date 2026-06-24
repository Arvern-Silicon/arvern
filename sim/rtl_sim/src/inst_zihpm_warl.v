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

reg [31:0] p1_event_ff;
reg [31:0] p2_event_13;
reg [31:0] p2_event_1f;
reg [31:0] p3_inhibit_ff;

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

      p1_event_ff = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      $display("  Phase 1: mhpmevent3 WARL (write 0xFFFFFFFF)");
      $display("    readback = 0x%h  %t ns", p1_event_ff, $time);

      if (p1_event_ff[4:0] === 5'h1F && p1_event_ff[31:5] === 27'h0)
         $display("  PASS  phase1: mhpmevent3[4:0]=0x1F, bits[31:5]=0 (5-bit WARL correct)  %t ns", $time);
      else begin
         $display("  ERROR phase1: mhpmevent3=0x%h, expected 0x0000001F  %t ns",
                  p1_event_ff, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 2: mhpmevent3 reserved code write/readback
      //=================================================================
      @(probes_cpu.x31 == 32'h22222222);
      repeat(3) @(posedge free_clk);

      p2_event_13 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
      p2_event_1f = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];

      $display("");
      $display("  Phase 2: mhpmevent3 reserved code readback");
      $display("    write 0x13 → readback = 0x%h  %t ns", p2_event_13, $time);
      $display("    write 0x1F → readback = 0x%h  %t ns", p2_event_1f, $time);

      if (p2_event_13[4:0] === 5'h13 && p2_event_13[31:5] === 27'h0)
         $display("  PASS  phase2a: reserved 0x13 stored/read back correctly  %t ns", $time);
      else begin
         $display("  ERROR phase2a: write 0x13 → got 0x%h, expected 0x00000013  %t ns",
                  p2_event_13, $time);
         error = error + 1;
      end

      if (p2_event_1f[4:0] === 5'h1F && p2_event_1f[31:5] === 27'h0)
         $display("  PASS  phase2b: reserved 0x1F stored/read back correctly  %t ns", $time);
      else begin
         $display("  ERROR phase2b: write 0x1F → got 0x%h, expected 0x0000001F  %t ns",
                  p2_event_1f, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 3: mcountinhibit WARL mask per ZIHPM_NR
      //=================================================================
      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      p3_inhibit_ff = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

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

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_event_selector_rw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM EVENT SELECTOR READ/WRITE
//   Verifies mhpmevent3 write/readback for all 32 event codes (0x00-0x1F).
//   Expected readback (strict WARL):
//     - implemented codes 0x00-0x12: read back verbatim (bits[31:5] zero)
//     - unimplemented codes 0x13-0x1F: fold to 0x00000000 on write
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] rb;
reg [31:0] exp;

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
      $display("|       ZIHPM EVENT SELECTOR RW: mhpmevent3 WRITE/READBACK ALL      |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // Wait for end of sweep
      //=================================================================
      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      //=================================================================
      // Verify all 32 event codes (0x00-0x1F)
      //=================================================================
      $display("  Verifying mhpmevent3 write/readback for codes 0x00-0x1F:");
      $display("  (implemented codes 0x00-0x12 read back verbatim;");
      $display("   unimplemented selectors fold to 0 (strict WARL))");
      $display("");

      for (ii = 0; ii < 32; ii = ii + 1) begin
         rb  = ahb_bus_system_inst.sram_x_inst.mem[ii];
         exp = (ii <= 32'h12) ? ii : 32'h0;

         if (rb !== exp) begin
            if (ii <= 32'h12)
               $display("  ERROR code 0x%02h: readback=0x%h, expected 0x%h (implemented, verbatim)  %t ns",
                        ii, rb, exp, $time);
            else
               $display("  ERROR code 0x%02h: readback=0x%h, expected 0x00000000 (unimplemented selector folds to 0, strict WARL)  %t ns",
                        ii, rb, $time);
            error = error + 1;
         end else begin
            if (ii <= 32'h12)
               $display("  PASS  code 0x%02h: readback=0x%h (implemented, verbatim)  %t ns", ii, rb, $time);
            else
               $display("  PASS  code 0x%02h: readback=0x%h (unimplemented selector folds to 0)  %t ns", ii, rb, $time);
         end
      end

      //=================================================================
      // Every selector mhpmevent3..10: 0x0F/0x10/0x12 verbatim, 0x13 and
      // 0x80000001 fold to 0; unprovided selectors (n >= ZIHPM_NR) read 0
      //=================================================================
      repeat(40) @(posedge free_clk);
      $display("");
      $display("  Verifying every selector mhpmevent3..10 (ZIHPM_NR=%0d):", ZIHPM_NR);
      for (jj = 0; jj < 8; jj = jj + 1)
         for (kk = 0; kk < 6; kk = kk + 1) begin
            case (kk)
               0: exp = 32'h0F;
               1: exp = 32'h10;
               2: exp = 32'h12;
               default: exp = 32'h0;
            endcase
            if (jj >= ZIHPM_NR) exp = 32'h0;
            $display("  mhpmevent%0d step %0d:", jj+3, kk);
            check_mem_value(`SPAD(32'h100 + jj*32 + kk*4), exp);
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

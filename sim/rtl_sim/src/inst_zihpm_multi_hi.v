//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_multi_hi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM MULTI-HI
//   Verifies mhpmcounterh write/readback for all implemented HPM counters
//   (3 through 2+ZIHPM_NR).  Each counter is written with 0xA0000000|(3+i)
//   and read back; exact equality is required.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;
integer zihpm_nr_found;

reg [31:0] hi_rb;
reg [31:0] expected_hi;

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
      $display("|       ZIHPM MULTI-HI: mhpmcounterh WRITE/READBACK FOR ALL CTRs    |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // Wait for mimpid sync, learn ZIHPM_NR
      //=================================================================
      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : read_mimpid
         reg [31:0] mimpid_rb;
         mimpid_rb      = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         zihpm_nr_found = mimpid_rb[23:20];
         $display("ZIHPM_NR = %0d  %t ns", zihpm_nr_found, $time);
      end

      if (zihpm_nr_found == 0)
         $display("ZIHPM_NR=0: no HPM counters, skipping");
      else begin

         //=================================================================
         // Wait for all writes to complete
         //=================================================================
         wait(probes_cpu.x31 == 32'hAAAAAAAA);
         repeat(3) @(posedge free_clk);

         //=================================================================
         // Verify each counter's hi-word readback
         // Scratchpad word (1 + i): hi readback for counter (3+i)
         //=================================================================
         $display("");
         for (ii = 0; ii < zihpm_nr_found; ii = ii + 1) begin
            hi_rb       = ahb_bus_system_inst.sram_x_inst.mem[1 + ii];
            expected_hi = 32'hA0000000 | (32'd3 + ii);

            $display("  mhpmcounterh%0d: readback=0x%h  expected=0x%h  %t ns",
                     ii+3, hi_rb, expected_hi, $time);

            if (hi_rb === expected_hi)
               $display("  PASS  mhpmcounterh%0d write/readback correct  %t ns", ii+3, $time);
            else begin
               $display("  ERROR mhpmcounterh%0d = 0x%h, expected 0x%h  %t ns",
                        ii+3, hi_rb, expected_hi, $time);
               error = error + 1;
            end
         end

      end

      //=================================================================
      // Wait for end of test
      //=================================================================
      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

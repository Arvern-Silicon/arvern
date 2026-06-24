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
//   Expected readback: code[4:0] only (bits[31:5] must be zero).
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] rb;

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
      $display("");

      for (ii = 0; ii < 32; ii = ii + 1) begin
         rb = ahb_bus_system_inst.sram_x_inst.mem[ii];

         // Upper bits [31:5] must be zero
         if (rb[31:5] !== 27'h0) begin
            $display("  ERROR code 0x%02h: readback=0x%h, bits[31:5] non-zero  %t ns",
                     ii, rb, $time);
            error = error + 1;
         end else if (rb[4:0] !== ii[4:0]) begin
            $display("  ERROR code 0x%02h: readback[4:0]=0x%h, expected 0x%02h  %t ns",
                     ii, rb[4:0], ii[4:0], $time);
            error = error + 1;
         end else begin
            $display("  PASS  code 0x%02h: readback=0x%h  %t ns", ii, rb, $time);
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

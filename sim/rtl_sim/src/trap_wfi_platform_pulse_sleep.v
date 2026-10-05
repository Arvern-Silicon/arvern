//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_wfi_platform_pulse_sleep
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: one-cycle platform IRQ pulses while the core clock is gated
// in WFI must latch mip[16+n] and, when enabled, wake the hart (see the .s).
//----------------------------------------------------------------------------
`define SPAD(byte_off)  ((byte_off)/4)

integer wait_cnt;
reg     woke;

task wait_gated;
   begin
      wait_cnt = 0;
      while (dut_hclk_en && (wait_cnt < 2000)) begin
         @(posedge free_clk);
         wait_cnt = wait_cnt + 1;
      end
      if (dut_hclk_en) begin
         $display("ERROR: the core never gated its clock in WFI %t ns", $time);
         error = error + 1;
      end
      repeat(5) @(posedge free_clk);
   end
endtask

task wait_marker(input [31:0] value);
   begin
      woke = 1'b0;
      begin : bounded
         for (wait_cnt = 0; wait_cnt < 2000; wait_cnt = wait_cnt + 1) begin
            @(posedge free_clk);
            if (probes_cpu.x31 == value) begin
               woke = 1'b1;
               disable bounded;
            end
         end
      end
   end
endtask

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|   ONE-CYCLE PLATFORM IRQ PULSE WHILE THE CLOCK IS GATED IN WFI     |");
      $display(" ====================================================================");

      //------------------------------------------------------------------
      // Phase 1: enabled pulse wakes the hart
      //------------------------------------------------------------------
      @(probes_cpu.x31==32'h11111111);
      wait_gated;
      @(negedge free_clk) irq_platform[0] = 1'b1;
      @(negedge free_clk) irq_platform[0] = 1'b0;
      wait_marker(32'h22222222);
      if (!woke) begin
         $display("ERROR: phase 1 -- the hart did not resume after an enabled one-cycle pulse %t ns", $time);
         error = error + 1;
         $display("       (dut_hclk_en=%b)", dut_hclk_en);
         irq_platform[0] = 1'b1;                       // unblock the firmware (enabled source)
         repeat(3) @(posedge free_clk);
         irq_platform[0] = 1'b0;
         wait (probes_cpu.x31 == 32'h22222222);
      end else
         $display("PASS:  phase 1 -- enabled one-cycle pulse woke the hart");

      //------------------------------------------------------------------
      // Phase 2: masked pulse must latch; another source wakes the hart
      //------------------------------------------------------------------
      @(probes_cpu.x31==32'h33333333);
      wait_gated;
      @(negedge free_clk) irq_platform[0] = 1'b1;
      @(negedge free_clk) irq_platform[0] = 1'b0;
      repeat(50) @(posedge free_clk);
      @(negedge free_clk) irq_platform[1] = 1'b1;
      repeat(3) @(negedge free_clk);
      irq_platform[1] = 1'b0;
      wait_marker(32'hdeadbeef);
      if (!woke) begin
         $display("ERROR: phase 2 -- the hart did not resume after the enabled source %t ns", $time);
         error = error + 1;
      end
      repeat(40) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00010000);   // phase 1: mip[16]
      check_mem_value(`SPAD(32'h04), 32'h00030000);   // phase 2: mip[16] latched while masked, mip[17]

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

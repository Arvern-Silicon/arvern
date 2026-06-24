//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_wfi_platform_hang
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: WFI wake on a latched platform interrupt (externally triggered).
//
//   The TB pulses irq_platform[0] for a few cycles then drops it, arming the
//   sticky ip_pip[0] inside the core. The firmware polls mip[16] to confirm
//   the latch, then WFI. Because wfi_wakeup_live_o reads the (now-low) raw
//   pin rather than the sticky register, a spec-correct wake may not occur
//   and the core can gate its clock forever -> HANG. free_clk runs even when
//   the DUT clock is gated, so the bounded wait detects the hang cleanly.
//----------------------------------------------------------------------------

`define VERY_LONG_TIMEOUT

`define SPAD(byte_off)  (byte_off/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

integer wait_cnt;
reg     woke;
reg     bad_trap;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|     WFI WAKE ON LATCHED PLATFORM IRQ (edge-pulsed, then dropped)   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware to enable mie[16] and request the pulse...");

      // Firmware enabled mie[16] and is ready; pulse irq_platform[0] as a
      // short EDGE, then drop it (models an ACLINT-style edge source).
      @(probes_cpu.x31==32'h21212121);
      irq_platform[0] = 1'b1;
      repeat(3) @(posedge free_clk);
      irq_platform[0] = 1'b0;

      // Firmware polls mip[16] until ip_pip[0] latches, then WFIs. Give the
      // bus time to drain and the sleep state to settle.
      repeat(200) @(posedge free_clk);

      $display("");
      $display("--- Latched-pending + WFI sleep state ---");
      $display("INFO:  mip latch (sram 0x04) = 0x%h",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)]);
      $display("INFO:  dut_hclk_en=%b after WFI (0 => core has gated its clock) %t ns",
               dut_hclk_en, $time);

      woke     = 1'b0;
      bad_trap = 1'b0;
      begin : wfi_wait
         for (wait_cnt = 0; wait_cnt < 10000; wait_cnt = wait_cnt + 1) begin
            @(posedge free_clk);
            if ((probes_cpu.x31 == 32'h22222222) || (probes_cpu.x31 == 32'hdeadbeef)) begin
               woke = 1'b1;
               disable wfi_wait;
            end
            if (probes_cpu.x31 == 32'hbadbad00) begin
               bad_trap = 1'b1;
               disable wfi_wait;
            end
         end
      end

      $display("");
      $display("--- Result ---");
      if (woke) begin
         $display("PASS:  core resumed past WFI on latched platform IRQ (woke=1) %t ns", $time);
         check_mem_value(`SPAD(32'h00), 32'hCAFEBABE);
      end else if (bad_trap) begin
         $display("ERROR: unexpected trap during MIE=0 WFI (x31=0xbadbad00) %t ns", $time);
         error = error + 1;
      end else begin
         $display("ERROR: HANG -- core never resumed past WFI within 10000 cycles.");
         $display("       dut_hclk_en=%b (0 => clock gated; live wake reads the now-low pin). %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end

      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

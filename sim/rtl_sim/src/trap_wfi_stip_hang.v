//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_wfi_stip_hang
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: WFI wake on software-set supervisor-timer pending (STIP).
//
//   Spec: WFI must wake on any enabled+pending interrupt regardless of the
//   global mstatus.MIE. STIP (mip[5]) is software-set only (no input pin),
//   so the pin-sourced combinational live-wakeup (wfi_wakeup_live_o, which
//   ungates hclk during sleep) may not cover it. If so, the core gates its
//   clock at WFI and never wakes -> HANG.
//
//   The firmware arms mie.STIE + mip.STIP with MIE=0, then WFI. This TB
//   confirms the wake was armed, observes the sleep, then bounded-waits for
//   the firmware to resume past WFI (x31 -> 0x22222222 / 0xdeadbeef).
//   free_clk runs even when the DUT clock is gated, so the wait loop makes
//   progress and a hang is detected deterministically (not via watchdog).
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
      $display("|        WFI WAKE ON SOFTWARE-SET SUPERVISOR-TIMER (STIP)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware to arm STIP/STIE and enter WFI...");

      // Firmware armed mie.STIE + mip.STIP (MIE=0) and is about to WFI.
      @(probes_cpu.x31==32'h21212121);

      // Confirm the wake condition was actually armed (mip[5] and mie[5] set).
      repeat(5) @(posedge free_clk);
      $display("");
      $display("--- Wake condition armed check ---");
      begin : check_armed
         reg [31:0] mip_val;
         reg [31:0] mie_val;
         mip_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
         mie_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         if (mip_val[5] !== 1'b1) begin
            $display("ERROR: mip[5] (STIP) not set after setup -- mip=0x%h %t ns", mip_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  mip[5] (STIP) set -- mip=0x%h %t ns", mip_val, $time);
         end
         if (mie_val[5] !== 1'b1) begin
            $display("ERROR: mie[5] (STIE) not set after setup -- mie=0x%h %t ns", mie_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  mie[5] (STIE) set -- mie=0x%h %t ns", mie_val, $time);
         end
      end

      // Allow the bus to drain and the sleep state to settle.
      repeat(200) @(posedge free_clk);

      $display("");
      $display("--- WFI sleep state ---");
      $display("INFO:  dut_hclk_en=%b after WFI (0 => core has gated its clock) %t ns",
               dut_hclk_en, $time);

      // Bounded wait for resume. NOTE: no IRQ pin is asserted by this TB -- a
      // spec-correct core must wake from the already-pending STIP&STIE alone.
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
         $display("PASS:  core resumed past WFI on enabled+pending STIP (woke=1) %t ns", $time);
         check_mem_value(`SPAD(32'h00), 32'hCAFEBABE);
      end else if (bad_trap) begin
         $display("ERROR: unexpected trap during MIE=0 WFI (x31=0xbadbad00) %t ns", $time);
         error = error + 1;
      end else begin
         $display("ERROR: HANG -- core never resumed past WFI within 10000 cycles.");
         $display("       dut_hclk_en=%b (0 => clock gated with no live wake for STIP). %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end

      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

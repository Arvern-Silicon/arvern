//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_aclint_wfi_wake
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ACLINT MTIMER -> WFI -> LF wake -> MTI trap
//   Exercises the LF wake aggregator end-to-end including main-osc deep
//   sleep: allow_deep_sleep=1 lets the master oscillator actually pause
//   when all hclk_en advisories drop during WFI. The always-on LF MTIP
//   fires when mtime crosses mtimecmp, aclint_mtimer_wake_lf
//   asynchronously restarts the main osc via u_free_osc.wake_i AND
//   un-gates hclk via the dut wake aggregator, the hclk_aon-clocked
//   MTIP synchronizer propagates the level, and the CPU wakes and takes
//   the trap.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Watchdog for deep-sleep verification: latches the first time the main
// oscillator's en_q goes low (i.e. the main osc actually paused while
// the CPU was in WFI). Checked at the end of the test.
reg     osc_gated_seen = 1'b0;
always @(u_free_osc.en_q)
  if ((u_free_osc.en_q === 1'b0) && !osc_gated_seen)
    begin
       $display("INFO:  Main osc entered deep sleep (u_free_osc.en_q -> 0) %t ns", $time);
       osc_gated_seen = 1'b1;
    end

`define SPAD(byte_off)  (byte_off/4)

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
      use_aclint         = 1'b1;
      allow_deep_sleep   = 1'b1;   // let the main osc actually pause when all hclk_en drop during WFI


      //=================================================================
      // PHASE 1: firmware programs MTIMECMP and enters WFI
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|         PHASE 1: ACLINT MTIMER PROGRAMMED, ENTERING WFI            |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      $display("PASS:  Phase 1 - firmware programmed MTIMECMP, entering WFI %t ns", $time);


      //=================================================================
      // PHASE 2: wait for the LF wake -> MTI trap -> WFI return
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 2: LF WAKE -> MTI -> WFI RETURN                  |");
      $display(" ====================================================================");
      $display("Waiting for LF MTIP to fire and propagate through the wake path...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      $display("PASS:  Phase 2 - WFI returned via LF wake -> MTI trap %t ns", $time);


      //=================================================================
      // PHASE 3: final checks
      //=================================================================
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Trap count + last MCAUSE ---");
      // trap_count = 1 (no race) or 2 (race observed and recovered by handler rearm)
      #1;
      if      (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)] === 32'h00000001)
        $display("PASS:  trap_count = 1 (no MTI race) %t ns", $time);
      else if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)] === 32'h00000002)
        $display("PASS:  trap_count = 2 (early-MTI race recovered) %t ns", $time);
      else
        begin
           $display("ERROR: trap_count = 0x%h (expected 1 or 2) %t ns",
                    ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)], $time);
           error = error+1;
        end
      check_mem_value(`SPAD(32'h04), 32'h80000007);   // MCAUSE = MTI

      $display("");
      $display("--- Deep-sleep verification ---");
      if (osc_gated_seen)
        $display("PASS:  Main osc actually entered deep sleep during WFI %t ns", $time);
      else
        begin
           $display("ERROR: Main osc never gated -- deep-sleep path not exercised %t ns", $time);
           error = error+1;
        end

      stimulus_done = 1;
   end

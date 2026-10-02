//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_tdata2_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: tdata2 bit walk and NAPOT size sweep on every trigger
//
//   The firmware self-checks (see the .s) and counts checks and failures. The
//   counts are recomputed here from DM_TRIGGER_NR and the kmax the firmware
//   discovered (s11), so a skipped trigger or size cannot pass:
//     checks = 2 + NT * (68 + 2 + sum_{k=0..kmax} (2 + 2*P_k))
//       P_k = 4 probes for k < 30, 3 for k = 30
//     load fires = store fires = NT * (kmax + 1) * 2
//   debug_interface.md states no NAPOT size limit, so kmax is expected to be
//   30 (every legal M > 0); a smaller value is reported as a NOTE.
//
//   The executable-SRAM alias is armed for the whole test so that non-firing
//   probes outside the bench memories complete without a bus error.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define LONG_TIMEOUT

integer kmax;
integer exp_checks;
integer exp_fires;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      ahb_bus_system_inst.sram_x_alias_en = 1'b1;
      error_on_exception = 0;            // breakpoint exceptions are the stimulus

      $display("");
      $display(" ====================================================================");
      $display("|        TRIGGER tdata2 WALK + NAPOT SIZE SWEEP -- %0d triggers        |",
               DM_TRIGGER_NR);
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);
      $display("--- PART A: tdata2 bit walk ---");

      wait(probes_cpu.x31==32'h22222222);
      $display("--- PART B: NAPOT size sweep ---");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(40) @(posedge free_clk);
      ahb_bus_system_inst.sram_x_alias_en = 1'b0;

      kmax = probes_cpu.x27;
      $display("--- tdata2 all-ones read-back with match=1: 0x%h, kmax = %0d ---",
               probes_cpu.x11, kmax);
      if (kmax != 30)
         $display("NOTE:  maskmax6 limits the NAPOT sweep to k <= %0d", kmax);

      exp_checks = 0;
      for (ii = 0; ii <= kmax; ii = ii + 1)
         exp_checks = exp_checks + 2 + 2 * ((ii < 30) ? 4 : 3);
      exp_checks = 2 + DM_TRIGGER_NR * (70 + exp_checks);
      exp_fires  = DM_TRIGGER_NR * (kmax + 1) * 2;

      check_cpu_reg(21, exp_checks);     // s5: checks performed
      check_cpu_reg(22, 32'd0);          // s6: failures
      check_cpu_reg(23, 32'd0);          // s7: first failing progress code
      check_cpu_reg(26, 32'd0);          // s10: handler mtval/hit0/mepc mismatches, unexpected causes
      check_cpu_reg(13, exp_fires);      // a3: load watchpoint fires
      check_cpu_reg(14, exp_fires);      // a4: store watchpoint fires
      check_cpu_reg(17, 32'd0);          // a7: data-bus RNMIs

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

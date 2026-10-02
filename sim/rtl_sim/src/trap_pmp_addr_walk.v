//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_addr_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP address-register walk and NAPOT size sweep on every entry
//
//   The firmware self-checks (see the .s) and counts checks and failures. The
//   counts are recomputed here from PMP_NR and SU_MODE_EN so a skipped entry,
//   size or phase cannot pass:
//     checks = NE*66 + (16 - NE) + (NE - 2)*(93 + 31*SU) + 2*(331 + 269*SU)
//       part A 66 per entry (0xFFFFFFFF, 0, 32 walking ones, 32 walking zeros)
//       part B per entry and k = 0..30: 1 (pmpaddr) + SU*1 (U cfg) + 2 (M cfg,
//       clear); the probes (2 checks each, P = 4 / 3 / 2 for k <= 27 / 28 /
//       >= 29, sum P = 119) run on entries 0 and NE-1 only: + SU*2P + 2P
//     load faults = store faults = 2 * (62 + 57*SU)
//   NE = 16 / 8 / 4 for PMP_NR >= 16 / >= 8 / otherwise.
//
//   The executable-SRAM alias is armed for the whole test so that allowed
//   probes outside the bench memories complete without a bus error.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

integer ne;
integer su;
integer exp_checks;
integer exp_faults;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      ahb_bus_system_inst.sram_x_alias_en = 1'b1;
      error_on_exception = 0;            // PMP faults and ECALLs are the stimulus

      ne         = (PMP_NR >= 16) ? 16 : ((PMP_NR >= 8) ? 8 : 4);
      su         = (SU_MODE_EN != 0) ? 1 : 0;
      exp_checks = ne * 66 + (16 - ne) + (ne - 2) * (93 + 31 * su) + 2 * (331 + 269 * su);
      exp_faults = 2 * (62 + 57 * su);

      $display("");
      $display(" ====================================================================");
      $display("|        PMP ADDRESS WALK + NAPOT SIZE SWEEP -- %0d entries, S/U %0s   |",
               ne, (su != 0) ? "on " : "off");
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);
      $display("--- PART A: pmpaddr bit walk ---");

      wait(probes_cpu.x31==32'h22222222);
      $display("--- PART B: NAPOT size sweep ---");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(40) @(posedge free_clk);
      ahb_bus_system_inst.sram_x_alias_en = 1'b0;

      check_cpu_reg(21, exp_checks);     // s5: checks performed
      check_cpu_reg(22, 32'd0);          // s6: failures
      check_cpu_reg(23, 32'd0);          // s7: first failing progress code
      check_cpu_reg(26, 32'd0);          // s10: handler mtval/mepc mismatches, unexpected causes
      check_cpu_reg(13, exp_faults);     // a3: load access faults
      check_cpu_reg(14, exp_faults);     // a4: store access faults
      check_cpu_reg(17, 32'd0);          // a7: data-bus RNMIs

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

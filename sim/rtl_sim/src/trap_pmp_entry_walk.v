//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_entry_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP entry walk -- every writable entry, every permission pattern,
//              M and U, unlocked and locked, then lock and read back
//
//   The firmware self-checks (Priv 3.7.1 permission / lock rules, see the .s)
//   and counts checks and failures. The check count is recomputed here from
//   PMP_NR and SU_MODE_EN so a skipped entry or phase cannot pass:
//     1 (RLB settable) + NE * (6 patterns * (6 + 4*SU) + 3 lock checks)
//     + 4 (final pmpcfg words) + 1 (RLB stuck)
//   NE = 16 / 8 / 4 for PMP_NR >= 16 / >= 8 / otherwise.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

integer ne;
integer exp_checks;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;            // PMP faults and ECALLs are the stimulus

      ne = (PMP_NR >= 16) ? 16 : ((PMP_NR >= 8) ? 8 : 4);
      exp_checks = 1 + ne * (6 * (6 + 4 * ((SU_MODE_EN != 0) ? 1 : 0)) + 3) + 4 + 1;

      $display("");
      $display(" ====================================================================");
      $display("|        PMP ENTRY WALK -- %0d entries, S/U %0s                        |",
               ne, (SU_MODE_EN != 0) ? "on " : "off");
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);
      $display("--- PART A: permission walk ---");

      wait(probes_cpu.x31==32'h22222222);
      $display("--- PART B: lock and read back ---");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(40) @(posedge free_clk);

      $display("--- final pmpcfg0..3: 0x%h 0x%h 0x%h 0x%h ---",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h200)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h204)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h208)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20C)]);

      check_cpu_reg(21, exp_checks);     // s5: checks performed
      check_cpu_reg(22, 32'd0);          // s6: failures
      check_cpu_reg(23, 32'd0);          // s7: first failure (entry<<8 | step<<4 | perm)
      check_cpu_reg(26, 32'd0);          // s10: handler mtval/mepc mismatches, unexpected causes

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

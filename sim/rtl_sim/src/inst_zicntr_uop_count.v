//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_uop_count
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR + UOP RETIRE COUNT
//   Reproducer for RTL review #15 (id_inst_retired_o over-counts on UOP
//   branch shadow cycle for CM.POPRET / CM.POPRETZ).
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

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

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 1: init complete                                    |");
      $display(" ============================================================");

      wait(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("Waiting for end-of-test sentinel...");

      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(5) @(posedge free_clk);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 2: minstret window-count verification               |");
      $display(" ============================================================");

      // Expected post-fix:
      //   jal (1) + cm.push (1) + li (1) + add (1) + cm.popret (1)
      //   + li t0 (1) + csrrs (1) = 7
      // Pre-fix: cm.popret over-counts by 1 -> 8
      $display("--- minstret window count (expect 7 post-fix; 8 pre-fix) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000007);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

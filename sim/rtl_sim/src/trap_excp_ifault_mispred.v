//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ifault_mispred
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IFAULT EXCEPTION (MISPREDICT)
//   A conditional branch resolved NOT-TAKEN sits just upstream of a
//   SEQUENTIAL fall-off instruction access fault (last valid word
//   0x8000FFFC, faulting fetch 0x80010000). The core speculatively takes the
//   detected branch then cancels it (not-taken); that speculative detect
//   clears fetch_fault_freeze. This test asserts the pending fault is still
//   reported PRECISELY and is NOT dropped by the speculate/cancel: for
//   mcause=1 (instruction access fault) MEPC and MTVAL must BOTH equal the
//   exact faulting PC 0x80010000, with exactly ONE trap per phase.
//
//   Phase A: branch near the boundary (fetch buffer ~empty at the fault).
//   Phase B: branch earlier with a long NOP run after it; under -rsalu the
//   buffer fills ahead so the speculative prefetch of 0x80010000
//   errors while the cancelled branch is still in flight.
//
//   A dropped fault would surface here as trap_count!=1, MCAUSE!=1, a
//   zero/skewed MEPC/MTVAL, or (if the pipeline livelocks) the harness
//   watchdog aborting the run.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

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

      // The sequential fall-off into 0x80010000 is an INTENTIONAL fault;
      // do not let the harness flag it. The MCAUSE / MEPC / MTVAL
      // check_mem_value oracles below stay strict and individually
      // reported, so a dropped or skewed fault still fails the test.
      error_on_exception = 0;

      //=================================================================
      // PHASE 1: Initialization
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);

      //=================================================================
      // PHASE A: not-taken branch near the boundary, buffer ~empty.
      //          Expect exactly ONE trap: MCAUSE=1, MEPC=MTVAL=0x80010000.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("| PHASE A: NOT-TAKEN BRANCH NEAR FAULT  (fault @ 0x80010000, c=1)    |");
      $display(" ====================================================================");
      $display("");
      $display("[mispred] The branch is speculatively taken then cancelled (not-");
      $display("[mispred] taken); the fall-through fetch of 0x80010000 must still");
      $display("[mispred] raise a precise instruction access fault. A correct core");
      $display("[mispred] advances x31 to 0x22222222 with one trap and exact PCs.");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Trap count (exactly one fault expected) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000001);

      $display("");
      $display("--- MEPC verification (expect exact faulting PC 0x80010000) ---");
      check_mem_value(`SPAD(32'h24), 32'h80010000);

      $display("");
      $display("--- MTVAL verification (expect exact faulting PC 0x80010000) ---");
      check_mem_value(`SPAD(32'h28), 32'h80010000);

      //=================================================================
      // PHASE B: not-taken branch earlier + long NOP run; buffer non-
      //          empty under -rsalu (speculative 0x80010000 prefetch
      //          errors while the cancelled branch is in flight).
      //          Expect exactly ONE trap: MCAUSE=1, MEPC=MTVAL=0x80010000.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("| PHASE B: NOT-TAKEN BRANCH + BUFFER FILL (fault @ 0x80010000, c=1)  |");
      $display(" ====================================================================");
      $display("");
      $display("[mispred] Same shape with a long pre-fault run; -rsalu fills the");
      $display("[mispred] fetch buffer so the speculative prefetch of 0x80010000");
      $display("[mispred] errors while the cancelled branch is still in flight.");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Trap count (exactly one fault expected) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000001);

      $display("");
      $display("--- MEPC verification (expect exact faulting PC 0x80010000) ---");
      check_mem_value(`SPAD(32'h34), 32'h80010000);

      $display("");
      $display("--- MTVAL verification (expect exact faulting PC 0x80010000) ---");
      check_mem_value(`SPAD(32'h38), 32'h80010000);

      //=================================================================
      // Register preservation across the 2 faults
      //=================================================================
      $display("");
      $display("--- Register preservation after 2 mispredict ifaults ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);

      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

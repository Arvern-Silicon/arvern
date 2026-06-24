//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ifault_straddle
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IFAULT EXCEPTION (STRADDLE)
//   A 32-bit (NON-compressed) instruction whose two 16-bit parcels STRADDLE
//   the SRAM_X / unmapped-region boundary:
//   lower parcel @ A     = 0x8000FFFE  (last valid SRAM_X halfword)
//   upper parcel @ A+2   = 0x80010000  (first word PAST SRAM_X, unmapped)
//   Fetching the upper parcel raises an instruction access fault for the
//   instruction AS A WHOLE.  Spec (RISC-V Privileged 3.1.16 / 12.1.9):
//   mcause = 1
//   mepc   = A    = 0x8000FFFE  (lower-parcel addr = the instr's own PC)
//   mtval  = A+2  = 0x80010000  (addr of the faulting upper parcel)
//   (mepc != mtval here, unlike the simple non-straddle IAF.)
//
//   PHASE A -- BENIGN STRADDLE CONTROL: the SAME straddle construction placed
//   wholly inside valid SRAM_X.  The straddling 32-bit ADDI must reassemble
//   across two words and execute -> x5 == 0x55, archived to SPAD 0x20.  This
//   proves the straddle construction is sound and isolates "straddle+fault"
//   as the failing condition.
//
//   PHASE B -- STRADDLE + FAULT (the discriminator):
//   CORRECT core : takes the IAF; SPAD 0x30/0x34/0x38 =
//   mcause=1 / mepc=0x8000FFFE / mtval=0x80010000.
//   BUGGY core   : the incomplete head parcel @0x8000FFFE is stuck in the
//   fetch buffer and can never retire, so a "defer the IAF
//   until the buffer empties" implementation NEVER fires the
//   fault -> the core LIVELOCKS.  x31 never reaches
//   0x33333333, this .v blocks at the wait below, and the
//   harness LONG_TIMEOUT fires -> "SIMULATION FAILED
//   (simulation Timeout)".  THAT TIMEOUT IS THE BUG SIGNAL
//   (never a false PASS).
//
//   BUG DISCRIMINATOR: the Phase-B wait `@(x31==0x33333333)` either completes
//   (correct core -> strict mcause/mepc/mtval checks then run) or never
//   completes (buggy core -> LONG_TIMEOUT FAIL).  An off-by-parcel skew
//   instead shows MEPC/MTVAL mismatches in the Phase-B check_mem_value calls.
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

      // The straddle upper-parcel fetch into 0x80010000 is an INTENTIONAL
      // fault; do not let the harness flag it. The MCAUSE / MEPC / MTVAL
      // check_mem_value oracles below stay strict and individually
      // reported, so a wrong cause or a skewed PC still fails the test.
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
      // PHASE A: BENIGN STRADDLE CONTROL (no fault).
      //          The same 32-bit instruction straddling two SRAM_X words
      //          (0x80008002/0x80008004) must reassemble and execute:
      //          x5 == 0x00000055, archived at SPAD 0x20. Proves the
      //          straddle construction is sound; no trap is taken yet.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("| PHASE A: BENIGN STRADDLE CONTROL  (straddled 32-bit ADDI executes) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // No trap yet: trap_count must still be 0.
      $display("");
      $display("--- No trap taken by the benign straddle (trap_count == 0) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Benign straddled 32-bit ADDI result (expect x5 == 0x55) ---");
      $display("    [proves the straddle construction reassembles & executes]");
      check_mem_value(`SPAD(32'h20), 32'h00000055);


      //=================================================================
      // PHASE B: STRADDLE + FAULT (the discriminator).
      //          A 32-bit instruction with lower parcel @ 0x8000FFFE and
      //          upper parcel @ 0x80010000 (unmapped). The IAF must be
      //          taken: mcause=1, mepc=0x8000FFFE (==A), mtval=0x80010000.
      //
      //          The current (buggy) core is EXPECTED TO LIVELOCK here:
      //          the incomplete head parcel @0x8000FFFE is stuck in the
      //          fetch buffer and can never retire, so a "defer IAF until
      //          the buffer empties" implementation never fires the fault.
      //          x31 never reaches 0x33333333 -> the wait below blocks
      //          forever -> LONG_TIMEOUT -> SIMULATION FAILED (Timeout).
      //          That timeout IS the confirmed bug -- NOT a false PASS.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("| PHASE B: STRADDLE + FAULT  (lower parcel @0x8000FFFE, IAF @0x80010000)|");
      $display(" ====================================================================");
      $display("");
      $display("[straddle] A correct core takes the IAF and advances x31 to");
      $display("[straddle] 0x33333333.  A pre-fix core instead LIVELOCKS:");
      $display("[straddle] the incomplete head parcel @0x8000FFFE never drains");
      $display("[straddle] the fetch buffer, so the deferred IAF never fires");
      $display("[straddle] and x31 never advances -- the harness watchdog then");
      $display("[straddle] aborts the run.  That hang is the straddle-at-fault livelock");
      $display("[straddle] signature (not a false pass).  A correct core");
      $display("[straddle] proceeds to the strict mcause/mepc/mtval checks below.");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Exactly one trap (the straddle IAF) must have been taken.
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000001);

      $display("");
      $display("--- MEPC verification (expect A = lower-parcel PC 0x8000FFFE) ---");
      $display("    [spec: mepc points at the BEGINNING of the instruction]");
      $display("    [BUG DISCRIMINATOR: a skew shows 0x80010000 or 0x8000FFFC]");
      check_mem_value(`SPAD(32'h34), 32'h8000FFFE);

      $display("");
      $display("--- MTVAL verification (expect A+2 = faulting parcel 0x80010000) ---");
      $display("    [spec: mtval = addr of the portion that caused the fault]");
      $display("    [NOTE: mepc != mtval for a straddling-instruction IAF]");
      check_mem_value(`SPAD(32'h38), 32'h80010000);


      //=================================================================
      // Register preservation check (across the straddle ifault)
      //=================================================================
      $display("");
      $display("--- Register preservation after the straddle ifault ---");
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

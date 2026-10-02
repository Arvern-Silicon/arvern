//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ifault_err_straddle
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IFAULT EXCEPTION (ERROR RESPONSE STRADDLES BRANCH DISPATCH, E-1b)
//
//   *** REQUIRES the err_word TB extension -- see doc/verification_guide.md §6 ***
//   (adds err_word_addr / err_word_ws / err_word_en to
//    bench/verilog/ahb_waitstate_inserter.v; this test cannot compile-run
//    meaningfully until that patch is applied. Base variant only:
//    register with "no_variants": true -- -fahb removes the hooked
//    instance and -rwsram/-wssram conflict with the hook.)
//
//   Word X = 0x8000E004 is the SEQUENTIAL SUCCESSOR of an ALWAYS-TAKEN
//   branch at 0x8000E000. The fetch unit prefetches X, the branch redirect
//   ABANDONS that prefetch, and the armed TB hook delays X's 2-cycle AHB
//   ERROR response by a DETERMINISTIC err_word_ws OKAY wait cycles. The .v
//   sweeps err_word_ws = 0..7 across 8 firmware rounds so the ERROR lands
//   on every alignment around the branch's detect/confirm cycles
//   (random wait states almost never produce these alignments).
//
//   CORRECT (fixed arv_fetch.v), EVERY round: the abandoned-prefetch fault
//   is DISCARDED -- no trap, execution continues at the branch target.
//   Final: trap_count==0, landing counter s10(x26)==8, poisons 0.
//
//   BUGGY-LEGACY signature locked out: for the straddling alignments the
//   abandoned fault was latched and reported as a SPURIOUS IAF after the
//   valid redirect -- trap_count!=0, MCAUSE=1, s10<8 (the failing round's
//   landing never happened; the .s bails out through e1b_fail).
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

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

      // The abandoned-prefetch fetch of X is an INTENTIONAL AHB error on a
      // discarded path; do not let the harness flag it. The trap_count /
      // MCAUSE / MEPC / MTVAL oracles below stay strict.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);


      //=================================================================
      // WAIT-STATE SWEEP: 8 rounds, err_word_ws = 0..7. Each firmware
      // round syncs x31 = 0x51000001+i BEFORE entering the branch block;
      // arming happens in zero sim time at the x31 writeback, several
      // cycles before the jalr can reach the armed region.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("| ABANDONED-PREFETCH ERROR SWEEP  X=0x8000E004, ws=0..7              |");
      $display("| (2-cycle ERROR must straddle every branch detect/confirm           |");
      $display("|  alignment and be DISCARDED every round: trap_count stays 0)       |");
      $display(" ====================================================================");
      $display("");

      for (ii = 0; ii < 8; ii = ii + 1)
        begin
          @(probes_cpu.x31 == (32'h51000001 + ii));
          @(negedge free_clk);
          ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_addr = 32'h8000E004;
          ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_ws   = ii;
          ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_en   = 1'b1;
          $display("[err_word] round %0d armed: addr=0x8000E004 ws=%0d", ii, ii);
        end


      //=================================================================
      // FINAL CHECKS
      //=================================================================
      @(probes_cpu.x31==32'hDEADBEEF);
      random_irq_enable = 0;
      repeat(30) @(posedge free_clk);   // drain final writebacks

      // Disarm the hook before checking (leave the TB pristine)
      ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_en   = 1'b0;

      $display("");
      $display("--- Discriminator: trap_count must be 0 across ALL 8 alignments ---");
      $display("    [non-zero = a straddling ERROR alignment latched the abandoned");
      $display("     prefetch fault -> spurious IAF after a valid taken branch]");
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // trap_count

      $display("");
      $display("--- All 8 rounds landed at the branch target (x26 == 8) ---");
      check_cpu_reg(26, 32'h00000008);   // s10 landing counter

      $display("");
      $display("--- Escape/fail markers (must be 0) ---");
      check_mem_value(`SPAD(32'h18), 32'h00000000);   // escape/fail marker

      $display("");
      $display("--- Captured trap context (all 0 on a correct core) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // MCAUSE
      check_mem_value(`SPAD(32'h0C), 32'h00000000);   // MEPC
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // MTVAL

      $display("");
      $display("--- Poison registers (must be 0: X / X+4 never executed) ---");
      check_cpu_reg(23, 32'h00000000);   // s7 (X content)
      check_cpu_reg(24, 32'h00000000);   // s8 (X+4 pad content)

      $display("");
      $display("--- Trap signature registers (all 0 on a correct core) ---");
      check_cpu_reg(28, 32'h00000000);   // t3 = trap_count
      check_cpu_reg(29, 32'h00000000);   // t4 = MCAUSE (1 if buggy)
      check_cpu_reg(30, 32'h00000000);   // t5 = MEPC
      check_cpu_reg( 7, 32'h00000000);   // t2 = MTVAL

      $display("");
      $display("--- Register preservation across the sweep ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

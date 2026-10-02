//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ifault_wrongpath_tgt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IFAULT EXCEPTION (WRONG-PATH BRANCH TARGET)
//   A conditional branch at 0x8000FFF0 is resolved NOT-TAKEN, but its
//   TARGET is 0x80010000 -- the first unmapped word past SRAM_X. The core
//   speculatively takes the detected branch and fetches the target; that
//   wrong-path fetch gets an AHB error; the branch is then cancelled
//   (not-taken). The wrong-path fault MUST be DISCARDED: the architectural
//   fall-through path (jr t2 at 0x8000FFF4 -> escape_land) is valid, so a
//   correct core delivers NO trap.
//
//   DISCRIMINATOR: trap_count (SPAD 0x00) MUST be 0. The wrong-path-target
//   bug (fails deterministically on the BASE variant) shows up as
//   trap_count=1 with a spurious instruction-access-fault at the VALID
//   fall-through PC: MCAUSE=1, MEPC=MTVAL=0x8000FFF4. Both the clean path
//   and the spurious-trap path converge on the x31=0xDEADBEEF sentinel, so
//   the run always terminates -- the bug is a non-zero trap_count, never a
//   timeout.
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

      // The wrong-path speculative fetch of 0x80010000 is an INTENTIONAL
      // AHB error on a cancelled path; do not let the harness flag it.
      // The trap_count / MCAUSE / MEPC / MTVAL oracles below stay strict.
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
      // DISCRIMINATOR: the not-taken branch's unmapped TARGET fault must
      // be discarded on cancel -> NO trap on the fall-through path.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("| WRONG-PATH BRANCH-TARGET IAF discard  (trap_count must stay 0)     |");
      $display(" ====================================================================");
      $display("");
      $display("[wrongpath] beq @0x8000FFF0 is NOT taken; its target 0x80010000 is");
      $display("[wrongpath] unmapped. The speculative target fetch errors, the branch");
      $display("[wrongpath] is cancelled, and the fault must be DISCARDED. The buggy");
      $display("[wrongpath] core reports a spurious IAF at the valid fall-through PC:");
      $display("[wrongpath] trap_count=1, mcause=1, mepc=mtval=0x8000FFF4.");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);
      random_irq_enable = 0;
      repeat(30) @(posedge free_clk);   // drain: the final lw writebacks can land well after the sentinel under random wait states

      $display("");
      $display("--- Spurious-IAF discriminator: trap_count must be 0 ---");
      $display("    [non-zero trap_count = the wrong-path-target spurious IAF bug]");
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Fall-through escape landed (escape_land marker must be 1) ---");
      check_mem_value(`SPAD(32'h1C), 32'h00000001);

      // If a spurious trap fired, surface its context for diagnosis. These
      // are 0/0/0 on a correct core (no trap taken). On the buggy core:
      // MCAUSE=1, MEPC=MTVAL=0x8000FFF4.
      $display("");
      $display("--- Captured trap context (all 0 on a correct core) ---");
      $display("    MCAUSE (SPAD 0x20), MEPC (SPAD 0x24), MTVAL (SPAD 0x28):");
      check_mem_value(`SPAD(32'h20), 32'h00000000);   // MCAUSE
      check_mem_value(`SPAD(32'h24), 32'h00000000);   // MEPC
      check_mem_value(`SPAD(32'h28), 32'h00000000);   // MTVAL

      // Same signature lifted into registers so a failure is directly
      // visible in the register-check report.
      $display("");
      $display("--- Trap signature registers (all 0 on a correct core) ---");
      check_cpu_reg(28, 32'h00000000);   // t3 = trap_count
      check_cpu_reg(29, 32'h00000000);   // t4 = MCAUSE  (1          if buggy)
      check_cpu_reg(30, 32'h00000000);   // t5 = MEPC    (0x8000FFF4 if buggy)
      check_cpu_reg( 7, 32'h00000000);   // t2 = MTVAL   (0x8000FFF4 if buggy)


      //=================================================================
      // Register preservation
      //=================================================================
      $display("");
      $display("--- Register preservation across the wrong-path fetch ---");
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

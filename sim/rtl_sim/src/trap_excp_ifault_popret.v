//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ifault_popret
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IFAULT EXCEPTION (UOP-FINAL BRANCH / CM.POPRET)
//   A CM.POPRET sits at 0x8000FFFE with its abandoned sequential-prefetch
//   successor at 0x80010000 (unmapped). The popret pops ra -> popret_land
//   (a VALID, mapped address) and redirects there. The abandoned-path AHB
//   error MUST be discarded -- a correct core delivers NO trap.
//
//   DISCRIMINATOR: trap_count (SPAD 0x00) MUST be 0. A spurious
//   instruction-access-fault (the documented UOP-final-branch race) shows up
//   as trap_count >= 1 with mcause=1 at a MAPPED mepc (popret_land or +2).
//   Both the clean path and the spurious-trap path converge on the
//   x31=0xDEADBEEF sentinel, so the run always terminates -- the bug is a
//   non-zero trap_count, never a timeout.
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

      // The abandoned-path prefetch of 0x80010000 is an INTENTIONAL AHB
      // error on a discarded path; do not let the harness flag it. The
      // trap_count oracle below stays strict.
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
      // DISCRIMINATOR: CM.POPRET redirects to a valid target; the
      // abandoned-path fault must be discarded -> NO trap.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("| CM.POPRET abandoned-path IAF discard  (trap_count must stay 0)     |");
      $display(" ====================================================================");
      $display("");
      $display("[popret] A correct core discards the abandoned 0x80010000 prefetch");
      $display("[popret] fault and returns cleanly via the popret. A SPURIOUS IAF at");
      $display("[popret] the (mapped) return target is the documented UOP-final-branch");
      $display("[popret] race -> shows as trap_count>=1, mcause=1 at a mapped mepc.");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hDEADBEEF);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Spurious-IAF discriminator: trap_count must be 0 ---");
      $display("    [non-zero trap_count = the spurious UOP-final-branch IAF bug]");
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      // If a spurious trap fired, surface its context for diagnosis. These
      // are 0/0/0 on a correct core (no trap taken).
      $display("");
      $display("--- Captured trap context (all 0 on a correct core) ---");
      $display("    MCAUSE (SPAD 0x20), MEPC (SPAD 0x24), MTVAL (SPAD 0x28):");
      check_mem_value(`SPAD(32'h20), 32'h00000000);   // MCAUSE
      check_mem_value(`SPAD(32'h24), 32'h00000000);   // MEPC
      check_mem_value(`SPAD(32'h28), 32'h00000000);   // MTVAL


      //=================================================================
      // Register preservation
      //=================================================================
      $display("");
      $display("--- Register preservation across the popret ---");
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

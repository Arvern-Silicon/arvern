//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ifault_isolated_word
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IFAULT EXCEPTION (ISOLATED ERRORING WORD, E-2)
//
//   *** REQUIRES the err_word TB extension -- see doc/verification_guide.md §6 ***
//   (adds err_word_addr / err_word_ws / err_word_en to
//    bench/verilog/ahb_waitstate_inserter.v; this test cannot compile-run
//    meaningfully until that patch is applied. Base variant only:
//    register with "no_variants": true -- -fahb removes the hooked
//    instance and -rwsram/-wssram conflict with the hook.)
//
//   A single instruction word X = 0x8000F004 INSIDE valid SRAM_X is armed
//   to return an AHB ERROR; its successor X+4 is VALID (impossible with
//   the region-based error model, where everything past SRAM_X errors).
//   A conditional branch at X-4 is resolved NOT-TAKEN, so the core
//   speculatively takes it and then cancels, resuming the fall-through
//   INTO X while X's error is pending/in flight.
//
//   CORRECT (fixed freeze-clear-on-confirmed arv_fetch.v), per round:
//     exactly one trap, MCAUSE=1, MEPC=MTVAL=0x8000F004; handler redirects
//     to the round's recovery label; the poison at X+4 NEVER executes.
//   BUGGY-LEGACY signature locked out: ZERO traps and X+4's instruction
//     data executed at PC=X -> trap_count=0 and s7(x23)=0xBAD04000.
//
//   Three rounds sweep the deterministic pre-error wait-state count
//   err_word_ws = {0, 1, 3} to move the 2-cycle ERROR response across
//   the speculate/cancel alignment.
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

      // Each round INTENTIONALLY takes one instruction-access-fault on the
      // armed word; do not let the harness flag it. The trap_count /
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
      // ROUND ARMING: re-arm the err_word hook at each firmware sync.
      // The word X = 0x8000F004 (inside valid SRAM_X) errors; everything
      // else -- including X+4 -- stays valid. Arming happens in zero sim
      // time at the x31 writeback, several cycles before the firmware
      // can jump into the armed region.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("| ISOLATED ERRORING WORD X=0x8000F004 (valid X+4) -- ws = {0,1,3}    |");
      $display(" ====================================================================");
      $display("");

      // Round 0: minimum 2-cycle ERROR (no extra wait states)
      @(probes_cpu.x31==32'h52000001);
      @(negedge free_clk);
      ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_addr = 32'h8000F004;
      ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_ws   = 32'd0;
      ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_en   = 1'b1;
      $display("[err_word] round 0 armed: addr=0x8000F004 ws=0");

      // Round 1: one OKAY wait cycle before the ERROR
      @(probes_cpu.x31==32'h52000002);
      @(negedge free_clk);
      ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_ws   = 32'd1;
      $display("[err_word] round 1 armed: addr=0x8000F004 ws=1");

      // Round 2: three OKAY wait cycles before the ERROR
      @(probes_cpu.x31==32'h52000003);
      @(negedge free_clk);
      ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_ws   = 32'd3;
      $display("[err_word] round 2 armed: addr=0x8000F004 ws=3");


      //=================================================================
      // FINAL CHECKS
      //=================================================================
      @(probes_cpu.x31==32'hDEADBEEF);
      random_irq_enable = 0;
      repeat(30) @(posedge free_clk);   // drain final writebacks

      // Disarm the hook before checking (leave the TB pristine)
      ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_en   = 1'b0;

      $display("");
      $display("--- Discriminator: exactly one IAF per round (trap_count == 3) ---");
      $display("    [trap_count==0 + x23=0xBAD04000 = legacy isolated-word bug:");
      $display("     fault dropped, X+4's data executed at PC=X]");
      check_mem_value(`SPAD(32'h00), 32'h00000003);   // trap_count
      check_mem_value(`SPAD(32'h1C), 32'h00000003);   // rounds_done

      $display("");
      $display("--- Escape marker (0 = flow never continued past X untrapped) ---");
      check_mem_value(`SPAD(32'h18), 32'h00000000);

      $display("");
      $display("--- Round 0 (ws=0): MCAUSE=1, MEPC=MTVAL=0x8000F004 ---");
      check_mem_value(`SPAD(32'h50), 32'h00000001);   // MCAUSE
      check_mem_value(`SPAD(32'h54), 32'h8000F004);   // MEPC
      check_mem_value(`SPAD(32'h58), 32'h8000F004);   // MTVAL

      $display("");
      $display("--- Round 1 (ws=1): MCAUSE=1, MEPC=MTVAL=0x8000F004 ---");
      check_mem_value(`SPAD(32'h60), 32'h00000001);
      check_mem_value(`SPAD(32'h64), 32'h8000F004);
      check_mem_value(`SPAD(32'h68), 32'h8000F004);

      $display("");
      $display("--- Round 2 (ws=3): MCAUSE=1, MEPC=MTVAL=0x8000F004 ---");
      check_mem_value(`SPAD(32'h70), 32'h00000001);
      check_mem_value(`SPAD(32'h74), 32'h8000F004);
      check_mem_value(`SPAD(32'h78), 32'h8000F004);

      $display("");
      $display("--- Poison registers (must ALL be 0) ---");
      $display("    x23=X+4 data executed at PC=X (THE isolated-word poison)");
      $display("    x24=X executed normally; x25=wrong-path target executed");
      check_cpu_reg(23, 32'h00000000);   // s7 (0xBAD04000 if buggy-legacy)
      check_cpu_reg(24, 32'h00000000);   // s8
      check_cpu_reg(25, 32'h00000000);   // s9

      $display("");
      $display("--- Trap signature lifted into registers (round 0) ---");
      check_cpu_reg(28, 32'h00000003);   // t3 = trap_count
      check_cpu_reg(29, 32'h00000001);   // t4 = r0 MCAUSE
      check_cpu_reg(30, 32'h8000F004);   // t5 = r0 MEPC
      check_cpu_reg( 7, 32'h8000F004);   // t2 = r0 MTVAL

      $display("");
      $display("--- Register preservation across the rounds ---");
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

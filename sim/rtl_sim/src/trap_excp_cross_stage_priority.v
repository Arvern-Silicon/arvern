//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_cross_stage_priority
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CROSS-STAGE EXCEPTION PRIORITY (WB load-acf vs EX-illegal)
//   Discriminator: the FIRST trap's mcause MUST be 5 (load access fault, the
//   OLDER instruction LW), NOT 2 (illegal, the YOUNGER instruction CSRW).
//
//   Pre-fix : first_mcause = 2  → FAIL
//   Post-fix: first_mcause = 5  → PASS
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // The race intentionally triggers load access faults and a write-RO
      // illegal — silence the testbench's bus-error-on-exception default so
      // the run can proceed.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: CHECK INITIALIZATION                          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Scratchpad should be zeroed
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h04), 32'h00000000);


      //=================================================================
      // PHASE 2: VERIFY THE RACE WAS PROPERLY HANDLED
      //
      // The firmware executes:
      //   lw   t0, 0(t1)          (t1 = 0x10000000 unmapped → WB load-acf)
      //   addi x0, x0, 0          (NOP filler — non-trapping)
      //   csrw mhartid, t2        (write to RO CSR → EX illegal)
      //
      // Pipeline timing aligns wb_excp_load_access_fault_o and
      // ex_excp_illegal_inst_i on the SAME cycle (the cycle that dph_error
      // registers high AND csrw enters EX).
      //
      // Spec (precise-exception): the OLDER (LW) fault must be reported
      // FIRST:
      //   first_mcause = 5 (LD access fault)
      //
      // Pre-fix bug: the cause encoder picks bit 3 (EX-illegal) → mcause=2
      // even though wb_excp_load_access_fault_i is also asserted on the
      // same cycle.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: CROSS-STAGE WB-LDACF × EX-ILLEGAL PRIORITY               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Both traps must have been taken — count should be 2.
      $display("");
      $display("--- trap_count (expect 2) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      // *** PRIMARY DISCRIMINATOR ***
      // FIRST trap's mcause must be 5 (LD access fault), NOT 2 (illegal).
      $display("");
      $display("--- FIRST trap mcause (expect 5 = LD acf — NOT 2 = illegal) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000005);

      // SECOND trap (sanity): the retried CSRW → illegal (cause 2).
      $display("");
      $display("--- SECOND trap mcause (expect 2 = illegal write to RO) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000002);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

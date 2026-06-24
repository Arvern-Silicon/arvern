//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_mret_priv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MRET FROM LOWER PRIVILEGE -> ILLEGAL
//   Verifies that MRET executed in U-mode or S-mode raises an illegal-
//   instruction exception (mcause=2) and does NOT escape to M-mode, while a
//   legitimate M-mode MRET still works (positive control: the U/S-mode code
//   runs at all only because the descending M-mode MRET succeeded).
//
//   Verdict (scratchpad, SRAM base 0x80000000):
//   0x00 trap_count       == 2     (U-mode MRET + S-mode MRET)
//   0x04 unexpected_count == 0     (no non-illegal trap entries)
//   0x20 u_mret_mcause    == 2
//   0x24 u_trap_mpp[12:11]== 00    (trap entered from U-mode)
//   0x28 u_ran_marker     == 0xC0FFEE01 (U-mode code executed: pos. ctrl)
//   0x30 s_mret_mcause    == 2
//   0x34 s_trap_mpp[12:11]== 01    (trap entered from S-mode)
//   0x38 s_ran_marker     == 0xC0FFEE02 (S-mode code executed: pos. ctrl)
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

      // Two illegal-instruction traps (U-mode MRET, S-mode MRET) are
      // expected by design.
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

      check_mem_value(`SPAD(32'h00), 32'h00000000);   // trap_count        = 0
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // unexpected_count  = 0

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);


      //=================================================================
      // PHASE 2: Positive control (M-mode MRET -> U) + U-mode MRET illegal
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|     PHASE 2: M->U via MRET (pos. ctrl) + U-mode MRET illegal       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Positive control: U-mode code ran (M-mode MRET worked) ---");
      check_mem_value(`SPAD(32'h28), 32'hC0FFEE01);   // u_ran_marker

      $display("");
      $display("--- U-mode MRET raised illegal-instruction (MCAUSE=2) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);   // u_mret_mcause

      $display("");
      $display("--- Trap entered from U-mode (MSTATUS.MPP = 00) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)][12:11] !== 2'b00) begin
         $display("ERROR: MPP mismatch -- expected: 00 (U-mode) / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 00 (U-mode MRET trapped, did not escape) %t ns", $time);
      end

      $display("");
      $display("--- One trap so far, none unexpected ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // trap_count       = 1
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // unexpected_count = 0


      //=================================================================
      // PHASE 3: Positive control (M-mode MRET -> S) + S-mode MRET illegal
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|     PHASE 3: M->S via MRET (pos. ctrl) + S-mode MRET illegal       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Positive control: S-mode code ran (M-mode MRET worked) ---");
      check_mem_value(`SPAD(32'h38), 32'hC0FFEE02);   // s_ran_marker

      $display("");
      $display("--- S-mode MRET raised illegal-instruction (MCAUSE=2) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000002);   // s_mret_mcause

      $display("");
      $display("--- Trap entered from S-mode (MSTATUS.MPP = 01) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)][12:11] !== 2'b01) begin
         $display("ERROR: MPP mismatch -- expected: 01 (S-mode) / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 01 (S-mode MRET trapped, did not escape) %t ns", $time);
      end


      //=================================================================
      // FINAL VERDICT (level wait on the end-of-test sentinel, per the
      // project convention for short trap-test paths -- avoids the
      // all-PASS + Timeout edge-vs-level race).
      //=================================================================
      $display("");
      $display(" Waiting for end-of-test sentinel");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(10) @(posedge free_clk);

      $display("");
      $display("--- Final trap accounting ---");
      // Exactly two illegal-instruction traps: U-mode MRET + S-mode MRET.
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // trap_count       = 2
      // No unexpected (non-illegal / wrong-MPP) trap entries.
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // unexpected_count = 0

      $display("");
      $display("--- Captured causes are both illegal-instruction (MCAUSE=2) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);   // u_mret_mcause
      check_mem_value(`SPAD(32'h30), 32'h00000002);   // s_mret_mcause

      $display("");
      $display("--- Positive-control markers (M-mode MRET descents worked) ---");
      check_mem_value(`SPAD(32'h28), 32'hC0FFEE01);   // u_ran_marker
      check_mem_value(`SPAD(32'h38), 32'hC0FFEE02);   // s_ran_marker

      $display("");
      $display("--- Register preservation across all mode transitions ---");
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

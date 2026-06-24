//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_nested
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NESTED EXCEPTIONS
//   Nested exception verification:
//   - Normal delegation: U-mode ECALL delegated to S-mode via MEDELEG
//   - Nested exception in S-mode exception handler -> M-mode
//   (in_s_excp_trap blocks re-delegation while sepc/scause are live)
//   - Delegation still works normally after nested trap clears
//
//   Nested exception inside an S-mode IRQ handler is covered by
//   trap_s_nested_excp.{s,v} (delegation is permitted there).
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
      // PHASE 2: Normal delegation (U-mode ECALL -> S-mode handler)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: NORMAL DELEGATION (U-mode ECALL -> S-mode, SCAUSE=8)   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (ECALL from U-mode, delegated to S-mode) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000008);

      $display("");
      $display("--- S-mode trap count verification (expect 1) ---");
      check_mem_value(`SPAD(32'h34), 32'h00000001);


      //=================================================================
      // PHASE 3: Nested exception (illegal inst in S-mode handler -> M-mode)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 3: NESTED EXCEPTION (S-mode handler -> M-mode, MCAUSE=2)  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (illegal instruction in S-mode handler) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000002);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 01 = S-mode, not U-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][12:11] !== 2'b01) begin
         $display("ERROR: MPP mismatch -- expected: 01 (S-mode) / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][12:11], $time);
         $display("       This means the exception was NOT handled by M-mode from S-mode context");
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 01 (S-mode) -- nested exception correctly trapped to M-mode %t ns", $time);
      end

      $display("");
      $display("--- S-mode trap count verification (expect 1 = only original ECALL) ---");
      check_mem_value(`SPAD(32'h48), 32'h00000001);


      //=================================================================
      // PHASE 4: Delegation still works after nested trap clears
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 4: DELEGATION WORKS AFTER NESTED TRAP (SCAUSE=8)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (ECALL from U-mode, delegated to S-mode) ---");
      check_mem_value(`SPAD(32'h50), 32'h00000008);

      $display("");
      $display("--- S-mode trap count verification (expect 1) ---");
      check_mem_value(`SPAD(32'h54), 32'h00000001);


      //=================================================================
      // END-OF-TEST sentinel
      //=================================================================
      $display("");
      $display("Waiting for end-of-test sentinel...");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after all mode transitions ---");
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

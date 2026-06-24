//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_s_nested_excp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP S NESTED EXCP (IRQ then EXCP)
//   Reproducer for RTL review #7 -- delegation of nested exception inside an
//   S-mode IRQ handler.
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

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 1: setup complete (M-mode -> S-mode transition)    |");
      $display(" ============================================================");

      wait(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("Waiting for end of test...");

      wait((probes_cpu.x31 == 32'hdeadbeef) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(5) @(posedge free_clk);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 2: nested-trap delegation verification              |");
      $display(" ============================================================");

      $display("--- S-mode IRQ handler must have run exactly once ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000001);

      $display("--- IRQ handler returned past the illegal instruction ---");
      check_mem_value(`SPAD(32'h18), 32'h000000AA);

      $display("--- Nested exception must have been delegated to S-mode ---");
      check_mem_value(`SPAD(32'h10), 32'h00000001);   // s_trap_count_excp
      check_mem_value(`SPAD(32'h14), 32'h00000002);   // SCAUSE == 2 (illegal)

      $display("--- No M-mode trap must have been taken ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // m_trap_count

      $display("--- Firmware result code (0xAA = S-path) ---");
      check_mem_value(`SPAD(32'h1C), 32'h000000AA);

      $display("--- x31 PASS sentinel ---");
      check_cpu_reg(31, 32'hdeadbeef);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_s_dbltrp_sdt_clear
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP S DBLTRP SDT CLEAR (Ssdbltrp re-entrancy contract)
//   Requires SU_MODE_EN==1. S handler clears sstatus.SDT -> nested delegated
//   illegal is taken horizontally in S (scause=2), which sets SDT again.
//   SRET clears SDT (verified after both the nested and the outer sret).
//   No trap may ever reach M-mode in this test.
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

      error_on_exception = 0;
      random_irq_enable  = 0;

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 1: M-mode setup complete (medeleg[2]=1, MPP=S)      |");
      $display(" ============================================================");

      wait(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      wait(probes_cpu.x31 == 32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 2: outer trap + nested horizontal trap              |");
      $display(" ============================================================");

      wait((probes_cpu.x31 == 32'h33333333) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(3) @(posedge free_clk);

      $display("--- Outer entry: SDT set by hardware ---");
      check_mem_value(`SPAD(32'h08), 32'h01000000);

      $display("--- Outer handler: software csrc cleared SDT ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000000);

      $display("--- Nested trap taken horizontally in S (scause=2) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000002);

      $display("--- Nested SEPC == &illegal2 ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)]) begin
         $display("ERROR: SEPC mismatch -- SEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)], $time);
      end

      $display("--- Nested entry set SDT=1 again ---");
      check_mem_value(`SPAD(32'h1C), 32'h01000000);

      $display("--- Outer handler resumed past illegal2 ---");
      check_mem_value(`SPAD(32'h20), 32'h000000AA);

      $display("--- Nested SRET cleared SDT ---");
      check_mem_value(`SPAD(32'h24), 32'h00000000);

      $display("--- Outer SRET cleared SDT (read back in s_main) ---");
      check_mem_value(`SPAD(32'h2C), 32'h00000000);

      $display("Waiting for end of test...");

      wait((probes_cpu.x31 == 32'hdeadbeef) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(5) @(posedge free_clk);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 3: third horizontal trap + final state              |");
      $display(" ============================================================");

      $display("--- Third trap taken horizontally in S (scause=2) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000002);

      $display("--- Third entry set SDT=1 (by hardware) ---");
      check_mem_value(`SPAD(32'h34), 32'h01000000);

      $display("--- Exactly 3 S handler entries ---");
      check_mem_value(`SPAD(32'h04), 32'h00000003);

      $display("--- No trap must have reached M-mode ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("--- s_main resumed after full unwind ---");
      check_mem_value(`SPAD(32'h38), 32'h000000BB);

      $display("--- x31 PASS sentinel ---");
      check_cpu_reg(31, 32'hdeadbeef);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

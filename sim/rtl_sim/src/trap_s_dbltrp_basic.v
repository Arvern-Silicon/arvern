//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_s_dbltrp_basic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP S DBLTRP BASIC (Ssdbltrp happy path)
//   Requires SU_MODE_EN==1. A second delegated illegal instruction inside an
//   active S handler (SDT=1) must be redirected to M-mode as a double trap:
//   mcause=16, mtval2 (0x34B) = 2 (original cause), mepc = &illegal2.
//   MRET back to S keeps SDT=1 (only a return to U clears it); the S
//   handler's SRET then clears it unconditionally.
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

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 2: S-mode entered, SDT pre-trap value recorded      |");
      $display(" ============================================================");

      wait(probes_cpu.x31 == 32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- SDT must read 0 before any trap into S ---");
      check_mem_value(`SPAD(32'h28), 32'h00000000);

      $display("Waiting for end of test...");

      wait((probes_cpu.x31 == 32'hdeadbeef) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(5) @(posedge free_clk);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 3: double trap verification                         |");
      $display(" ============================================================");

      $display("--- S handler entered exactly once (first trap only) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000001);   // s_trap_count
      check_mem_value(`SPAD(32'h14), 32'h00000002);   // SCAUSE == 2 (illegal)

      $display("--- sstatus.SDT set by hardware on S trap entry ---");
      check_mem_value(`SPAD(32'h18), 32'h01000000);

      $display("--- Double trap arrived in M-mode: mcause = 16 ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // m_trap_count
      check_mem_value(`SPAD(32'h04), 32'h00000010);   // MCAUSE == 16

      $display("--- mtval2 (0x34B) holds the original cause (2) ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000002);

      $display("--- MEPC of the double trap == &illegal2 ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)], $time);
      end

      $display("--- M handler unwound cleanly past illegal2 ---");
      check_mem_value(`SPAD(32'h20), 32'h000000AA);

      $display("--- MRET back to S keeps SDT=1 (only a return to U clears it) ---");
      check_mem_value(`SPAD(32'h24), 32'h01000000);

      $display("--- SRET cleared SDT ---");
      check_mem_value(`SPAD(32'h30), 32'h00000000);

      $display("--- s_main resumed after full unwind ---");
      check_mem_value(`SPAD(32'h2C), 32'h000000BB);

      $display("--- x31 PASS sentinel ---");
      check_cpu_reg(31, 32'hdeadbeef);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_s_dbltrp_dte_off
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP S DBLTRP DTE OFF (Ssdbltrp opt-out via menvcfgh.DTE)
//   Requires SU_MODE_EN==1. With menvcfgh.DTE (bit 27) cleared the hart
//   behaves as if Ssdbltrp were absent (SDT RAZ/WI, nested delegated traps
//   horizontal in S). After DTE is set back to 1 the double-trap redirect
//   (mcause=16, mtval2=orig cause) must return.
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
      $display("|  PHASE 1: M-mode setup, menvcfgh.DTE cleared               |");
      $display(" ============================================================");

      wait(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- DTE readback after clear (write-0-read-0) ---");
      check_mem_value(`SPAD(32'h14), 32'h00000000);

      wait(probes_cpu.x31 == 32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 2: DTE=0 -- Ssdbltrp behaves as absent              |");
      $display(" ============================================================");

      wait((probes_cpu.x31 == 32'h33333333) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(3) @(posedge free_clk);

      $display("--- SDT reads 0 immediately after trap into S (RAZ) ---");
      check_mem_value(`SPAD(32'h18), 32'h00000000);

      $display("--- SDT write ignored while DTE=0 (WI) ---");
      check_mem_value(`SPAD(32'h1C), 32'h00000000);

      $display("--- Nested illegal taken horizontally in S (scause=2) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);

      $display("--- SDT still 0 in the nested entry ---");
      check_mem_value(`SPAD(32'h44), 32'h00000000);

      $display("--- Phase 1 handler unwound cleanly ---");
      check_mem_value(`SPAD(32'h2C), 32'h000000AA);

      // Note: "no M trap in phase 1" is proven by the final counters
      // (m_trap_count==2 with ecall==1 and dbl==1); checking m_trap_count
      // here would race with the ECALL issued right after this sync point.

      $display("Waiting for end of test...");

      wait((probes_cpu.x31 == 32'hdeadbeef) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(5) @(posedge free_clk);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 3: DTE re-enabled -- double trap behavior returns   |");
      $display(" ============================================================");

      $display("--- ECALL reached M and DTE readback is 1 again ---");
      check_mem_value(`SPAD(32'h04), 32'h00000001);   // m_ecall_count
      check_mem_value(`SPAD(32'h38), 32'h08000000);   // DTE after re-set

      $display("--- SDT set by hardware on S trap entry (DTE=1) ---");
      check_mem_value(`SPAD(32'h28), 32'h01000000);

      $display("--- Double trap redirected to M: mcause = 16 ---");
      check_mem_value(`SPAD(32'h08), 32'h00000001);   // m_dbl_count
      check_mem_value(`SPAD(32'h0C), 32'h00000010);   // last MCAUSE == 16

      $display("--- mtval2 (0x34B) holds the original cause (2) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000002);

      $display("--- MEPC of the double trap == &illegal4 ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h3C)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h3C)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)], $time);
      end

      $display("--- Exactly 2 M traps total (ECALL + double trap) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("--- Exactly 3 S handler entries ---");
      check_mem_value(`SPAD(32'h24), 32'h00000003);

      $display("--- Phase 3 handler and s_main unwound cleanly ---");
      check_mem_value(`SPAD(32'h30), 32'h000000BB);
      check_mem_value(`SPAD(32'h48), 32'h000000CC);

      $display("--- x31 PASS sentinel ---");
      check_cpu_reg(31, 32'hdeadbeef);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

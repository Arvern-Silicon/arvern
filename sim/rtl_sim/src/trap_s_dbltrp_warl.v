//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_s_dbltrp_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP S DBLTRP WARL (Ssdbltrp CSR surface)
//   Requires SU_MODE_EN==1. menvcfgh.DTE resets to 1 and is WARL both ways;
//   sstatus.SDT is software-writable and honored regardless of origin
//   (SW-set SDT with no prior trap still forces a double trap, mcause=16,
//   mtval2=2); MRET back to S keeps SDT=1 (only a return to U clears it);
//   mtval2 readable from M, illegal from S.
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
      $display("|  PHASE 1: menvcfgh.DTE reset value + WARL + mtval2 from M  |");
      $display(" ============================================================");

      wait(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- menvcfgh.DTE (bit 27) resets to 1 ---");
      check_mem_value(`SPAD(32'h00), 32'h08000000);

      $display("--- DTE write-0-read-0 ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      $display("--- DTE write-1-read-1 ---");
      check_mem_value(`SPAD(32'h08), 32'h08000000);

      $display("--- mtval2 (0x34B) readable from M without trapping ---");
      check_mem_value(`SPAD(32'h40), 32'h00000000);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 2: sstatus.SDT software-writable from S-mode        |");
      $display(" ============================================================");

      wait((probes_cpu.x31 == 32'h22222222) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(3) @(posedge free_clk);

      $display("--- SDT set by software (csrs) reads 1 ---");
      check_mem_value(`SPAD(32'h0C), 32'h01000000);

      $display("--- SDT cleared by software (csrc) reads 0 ---");
      check_mem_value(`SPAD(32'h10), 32'h00000000);

      $display("--- SDT re-set by software reads 1 ---");
      check_mem_value(`SPAD(32'h14), 32'h01000000);

      $display("Waiting for end of test...");

      wait((probes_cpu.x31 == 32'hdeadbeef) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(5) @(posedge free_clk);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 3: SW-set SDT forces double trap + mtval2 from S    |");
      $display(" ============================================================");

      $display("--- Double trap reached M exactly once: mcause = 16 ---");
      check_mem_value(`SPAD(32'h38), 32'h00000001);   // m_trap_count
      check_mem_value(`SPAD(32'h18), 32'h00000010);   // MCAUSE == 16

      $display("--- mtval2 holds the original cause (2) ---");
      check_mem_value(`SPAD(32'h1C), 32'h00000002);

      $display("--- MEPC of the double trap == &illegal_dbl ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)], $time);
      end

      $display("--- MRET back to S keeps SDT=1 (only a return to U clears it) ---");
      check_mem_value(`SPAD(32'h28), 32'h01000000);

      $display("--- explicit csrc cleared SDT ---");
      check_mem_value(`SPAD(32'h48), 32'h00000000);

      $display("--- mtval2 access from S raised illegal-instruction ---");
      check_mem_value(`SPAD(32'h3C), 32'h00000001);   // s_trap_count
      check_mem_value(`SPAD(32'h2C), 32'h00000002);   // SCAUSE == 2

      $display("--- SEPC == &mtval2_read ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)]) begin
         $display("ERROR: SEPC mismatch -- SEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)], $time);
      end

      $display("--- s_main resumed after full unwind ---");
      check_mem_value(`SPAD(32'h44), 32'h000000AA);

      $display("--- x31 PASS sentinel ---");
      check_cpu_reg(31, 32'hdeadbeef);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

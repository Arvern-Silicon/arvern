//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_mepc_align
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP MEPC ALIGNMENT
//   Verify MEPC[0] is always forced to 0 for all exception types:
//   - EBREAK (4-byte instruction)
//   - C.EBREAK (2-byte compressed instruction)
//   - ECALL (4-byte instruction)
//   - Illegal instruction at 2-byte aligned address
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
      // PHASE 2: EBREAK (4-byte instruction)
      //          Check MEPC[1:0] == 00
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|            PHASE 2: EBREAK - MEPC ALIGNMENT CHECK                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MEPC bit 0 check (EBREAK, expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)][0] !== 1'b0) begin
         $display("ERROR: MEPC[0] is not 0 for EBREAK -- MEPC: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC[0] = 0 for EBREAK -- MEPC: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)], $time);
      end


      //=================================================================
      // PHASE 3: C.EBREAK (2-byte compressed instruction)
      //          Check MEPC[0] == 0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 3: C.EBREAK - MEPC ALIGNMENT CHECK                |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- MEPC bit 0 check (C.EBREAK, expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)][0] !== 1'b0) begin
         $display("ERROR: MEPC[0] is not 0 for C.EBREAK -- MEPC: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC[0] = 0 for C.EBREAK -- MEPC: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)], $time);
      end


      //=================================================================
      // PHASE 4: ECALL (4-byte instruction)
      //          Check MEPC[0] == 0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|            PHASE 4: ECALL - MEPC ALIGNMENT CHECK                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000003);

      $display("");
      $display("--- MEPC bit 0 check (ECALL, expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)][0] !== 1'b0) begin
         $display("ERROR: MEPC[0] is not 0 for ECALL -- MEPC: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC[0] = 0 for ECALL -- MEPC: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)], $time);
      end


      //=================================================================
      // PHASE 5: Illegal instruction at 2-byte aligned address
      //          Check MEPC[0] == 0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 5: ILLEGAL INST (2-BYTE ALIGNED) - MEPC ALIGN CHECK   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000004);

      $display("");
      $display("--- MEPC bit 0 check (illegal inst at 2-byte aligned, expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)][0] !== 1'b0) begin
         $display("ERROR: MEPC[0] is not 0 for illegal inst -- MEPC: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC[0] = 0 for illegal inst -- MEPC: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)], $time);
      end


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after 4 exceptions ---");
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

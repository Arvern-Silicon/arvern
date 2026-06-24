//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_basic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: EXCEPTIONS
//   Synchronous exception verification:
//   - Instruction access fault (MCAUSE = 1)
//   - Illegal instruction (MCAUSE = 2)
//   - Load address misaligned (MCAUSE = 4)
//   - Store address misaligned (MCAUSE = 6)
//   - Load access fault (MCAUSE = 5)
//   - Store access fault (MCAUSE = 7)
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


      //=================================================================
      // PHASE 2: Illegal instruction (MCAUSE = 2)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: ILLEGAL INSTRUCTION                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE verification (illegal instruction) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);

      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)], $time);
      end


      //=================================================================
      // PHASE 3: Load address misaligned (MCAUSE = 4)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: LOAD ADDRESS MISALIGNED                   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- MCAUSE verification (load misaligned) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000004);

      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)], $time);
      end


      //=================================================================
      // PHASE 4: Store address misaligned (MCAUSE = 6)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: STORE ADDRESS MISALIGNED                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000003);

      $display("");
      $display("--- MCAUSE verification (store misaligned) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000006);

      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)], $time);
      end


      //=================================================================
      // PHASE 5: Load access fault (MCAUSE = 5)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: LOAD ACCESS FAULT                         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000004);

      $display("");
      $display("--- MCAUSE verification (load access fault) ---");
      check_mem_value(`SPAD(32'h50), 32'h00000005);

      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h58)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h58)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)], $time);
      end


      //=================================================================
      // PHASE 6: Store access fault (MCAUSE = 7)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 6: STORE ACCESS FAULT                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000005);

      $display("");
      $display("--- MCAUSE verification (store access fault) ---");
      check_mem_value(`SPAD(32'h60), 32'h00000007);

      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h68)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h68)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)], $time);
      end



      //=================================================================
      // PHASE 7: Instruction access fault via JALR to 0x00000000
      //          (MCAUSE = 1)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 7: INSTRUCTION ACCESS FAULT (addr 0x00000000)         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000006);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h70), 32'h00000001);

      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h78)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h78)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)], $time);
      end


      //=================================================================
      // PHASE 8: Instruction access fault via JALR to 0x40000000
      //          (MCAUSE = 1)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 8: INSTRUCTION ACCESS FAULT (addr 0x40000000)         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h88888888);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000007);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h80), 32'h00000001);

      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h84)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h88)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h84)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h88)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h84)], $time);
      end

      // Final register preservation
      $display("");
      $display("--- Register preservation after 7 exceptions ---");
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

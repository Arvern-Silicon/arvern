//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_priv_modes
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PRIVILEGE MODES
//   Privilege mode transition verification:
//   - M-mode to S-mode via MRET (ECALL from S → MCAUSE = 9)
//   - M-mode to U-mode via MRET (ECALL from U → MCAUSE = 8)
//   - S-mode to U-mode via SRET (ECALL from U → MCAUSE = 8)
//   - Trap delegation via MEDELEG (U-mode ECALL → S-mode handler)
//   - CSR access violations from U-mode and S-mode
//   - MSTATUS.MPP / SSTATUS.SPP verification
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
      // PHASE 2: M-mode -> S-mode -> M-mode (ECALL from S-mode)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 2: M -> S -> M  (ECALL from S-mode, MCAUSE=9)        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (ECALL from S-mode) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000009);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 01 = S-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)][12:11] !== 2'b01) begin
         $display("ERROR: MPP mismatch -- expected: 01 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 01 (S-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 3: M-mode -> U-mode -> M-mode (ECALL from U-mode)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 3: M -> U -> M  (ECALL from U-mode, MCAUSE=8)        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (ECALL from U-mode) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000008);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 00 = U-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)][12:11] !== 2'b00) begin
         $display("ERROR: MPP mismatch -- expected: 00 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 00 (U-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 4: M-mode -> S-mode -> U-mode -> M-mode (SRET chain)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|     PHASE 4: M -> S -> U -> M  (SRET to U, ECALL, MCAUSE=8)      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (ECALL from U-mode) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000008);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 00 = U-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][12:11] !== 2'b00) begin
         $display("ERROR: MPP mismatch -- expected: 00 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 00 (U-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 5: Trap delegation (ECALL from U-mode → S-mode handler)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 5: DELEGATION (U-mode ECALL -> S-mode, SCAUSE=8)         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (ECALL from U-mode, delegated to S-mode) ---");
      check_mem_value(`SPAD(32'h50), 32'h00000008);

      $display("");
      $display("--- SSTATUS.SPP verification (expect 0 = U-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)][8] !== 1'b0) begin
         $display("ERROR: SPP mismatch -- expected: 0 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)][8], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SPP = 0 (U-mode) %t ns", $time);
      end

      $display("");
      $display("--- S-mode trap count verification (expect >= 1) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)] < 32'h00000001) begin
         $display("ERROR: S-mode trap count = 0, expected >= 1 %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  S-mode trap count = %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)], $time);
      end


      //=================================================================
      // PHASE 6: CSR access violation from U-mode
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 6: CSR ACCESS VIOLATION FROM U-MODE (MCAUSE=2)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (illegal instruction) ---");
      check_mem_value(`SPAD(32'h60), 32'h00000002);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 00 = U-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)][12:11] !== 2'b00) begin
         $display("ERROR: MPP mismatch -- expected: 00 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 00 (U-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 7: CSR access violation from S-mode
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 7: CSR ACCESS VIOLATION FROM S-MODE (MCAUSE=2)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MCAUSE verification (illegal instruction) ---");
      check_mem_value(`SPAD(32'h70), 32'h00000002);

      $display("");
      $display("--- MSTATUS.MPP verification (expect 01 = S-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)][12:11] !== 2'b01) begin
         $display("ERROR: MPP mismatch -- expected: 01 / actual: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 01 (S-mode) %t ns", $time);
      end


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

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_csr_reserved
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CSR RESERVED VALUES
//   Verify reserved CSR field handling:
//   Phase 2: MTVEC MODE=2 (reserved) -> masked to MODE=0
//   Phase 3: MTVEC MODE=3 (reserved) -> masked to MODE=1
//   Phase 4: STVEC MODE=2 (reserved) -> masked to MODE=0
//   Phase 5: STVEC MODE=3 (reserved) -> masked to MODE=1
//   Phase 6: MSTATUS.MPP=2'b10 (reserved) -> keeps old value
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

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: MTVEC MODE=2 (reserved) -> should read back MODE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: MTVEC MODE=2 (RESERVED) -> MASKED TO MODE=0            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MTVEC MODE after writing MODE=2 (expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)][1:0] !== 2'b00) begin
         $display("ERROR: MTVEC MODE=2 not masked -- read: %b (expected: 00) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)][1:0], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MTVEC MODE=2 correctly masked to 00 %t ns", $time);
      end


      //=================================================================
      // PHASE 3: MTVEC MODE=3 (reserved) -> should read back MODE=1
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: MTVEC MODE=3 (RESERVED) -> MASKED TO MODE=1            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MTVEC MODE after writing MODE=3 (expect 1) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)][1:0] !== 2'b01) begin
         $display("ERROR: MTVEC MODE=3 not masked -- read: %b (expected: 01) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)][1:0], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MTVEC MODE=3 correctly masked to 01 %t ns", $time);
      end


      //=================================================================
      // PHASE 4: STVEC MODE=2 (reserved) -> should read back MODE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: STVEC MODE=2 (RESERVED) -> MASKED TO MODE=0            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- STVEC MODE after writing MODE=2 (expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)][1:0] !== 2'b00) begin
         $display("ERROR: STVEC MODE=2 not masked -- read: %b (expected: 00) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)][1:0], $time);
         error = error + 1;
      end else begin
         $display("PASS:  STVEC MODE=2 correctly masked to 00 %t ns", $time);
      end


      //=================================================================
      // PHASE 5: STVEC MODE=3 (reserved) -> should read back MODE=1
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 5: STVEC MODE=3 (RESERVED) -> MASKED TO MODE=1            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- STVEC MODE after writing MODE=3 (expect 1) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)][1:0] !== 2'b01) begin
         $display("ERROR: STVEC MODE=3 not masked -- read: %b (expected: 01) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)][1:0], $time);
         error = error + 1;
      end else begin
         $display("PASS:  STVEC MODE=3 correctly masked to 01 %t ns", $time);
      end


      //=================================================================
      // PHASE 6: MSTATUS.MPP = 2'b10 (reserved) -> keeps old value
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 6: MSTATUS.MPP=10 (RESERVED) -> KEEPS OLD VALUE           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS.MPP before write (expect 11 = M-mode) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)][12:11] !== 2'b11) begin
         $display("ERROR: MPP before test not as expected -- read: %b (expected: 11) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP = 11 (M-mode) before test %t ns", $time);
      end

      $display("");
      $display("--- MSTATUS.MPP after writing 2'b10 (expect old value kept) ---");
      // After clearing MPP to 00 then trying to set bit 12 only (= 2'b10),
      // the reserved value should be rejected. Since we cleared to 00 first,
      // the old value at the point of the reserved write is 00.
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)][12:11] == 2'b10) begin
         $display("ERROR: MPP accepted reserved value 2'b10 -- read: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPP rejected reserved value 2'b10 -- read: %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)][12:11], $time);
      end


      //=================================================================
      // Final register preservation check
      //=================================================================
      $display("");
      $display("--- Callee-saved registers preserved ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);

      stimulus_done = 1;
   end

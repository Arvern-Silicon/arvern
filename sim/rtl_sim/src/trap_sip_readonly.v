//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_sip_readonly
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SIP READ-ONLY BITS
//   Verify SIP.STIP and SIP.SEIP are read-only per RISC-V spec:
//   Phase 2: M-mode writes STIP via MIP -> visible in SIP
//   Phase 3: S-mode tries to set STIP via SIP -> stays 0 (read-only)
//   Phase 4: S-mode tries to set SEIP via SIP -> stays 0 (read-only)
//   Phase 5: S-mode writes SSIP via SIP -> succeeds (writable)
//   Phase 6: M-mode writes SEIP via MIP -> visible in SIP
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

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: M-mode writes MIP.STIP -> verify visible in SIP
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: M-MODE WRITES MIP.STIP -> VISIBLE IN SIP               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SIP after M-mode sets MIP.STIP (expect bit 5 set) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)][5] !== 1'b1) begin
         $display("ERROR: SIP.STIP not visible after M-mode write to MIP -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SIP.STIP visible after M-mode MIP write -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)], $time);
      end


      //=================================================================
      // PHASE 3: S-mode tries to set SIP.STIP (should fail)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: S-MODE WRITES SIP.STIP -> STAYS 0 (READ-ONLY)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SIP.STIP before S-mode write (expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)][5] !== 1'b0) begin
         $display("ERROR: SIP.STIP unexpectedly set before test -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SIP.STIP clear before test -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)], $time);
      end

      $display("");
      $display("--- SIP.STIP after S-mode CSRS attempt (expect still 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)][5] !== 1'b0) begin
         $display("ERROR: SIP.STIP was written by S-mode (should be read-only) -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SIP.STIP unchanged after S-mode write (read-only) -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)], $time);
      end


      //=================================================================
      // PHASE 4: S-mode tries to set SIP.SEIP (should fail)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: S-MODE WRITES SIP.SEIP -> STAYS 0 (READ-ONLY)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SIP.SEIP before S-mode write (expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)][9] !== 1'b0) begin
         $display("ERROR: SIP.SEIP unexpectedly set before test -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SIP.SEIP clear before test -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)], $time);
      end

      $display("");
      $display("--- SIP.SEIP after S-mode CSRS attempt (expect still 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)][9] !== 1'b0) begin
         $display("ERROR: SIP.SEIP was written by S-mode (should be read-only) -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SIP.SEIP unchanged after S-mode write (read-only) -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)], $time);
      end


      //=================================================================
      // PHASE 5: S-mode writes SIP.SSIP (should succeed)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 5: S-MODE WRITES SIP.SSIP -> SUCCEEDS (WRITABLE)           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SIP.SSIP before S-mode write (expect 0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)][1] !== 1'b0) begin
         $display("ERROR: SIP.SSIP unexpectedly set before test -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SIP.SSIP clear before test -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)], $time);
      end

      $display("");
      $display("--- SIP.SSIP after S-mode CSRS (expect bit 1 set) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)][1] !== 1'b1) begin
         $display("ERROR: SIP.SSIP not writable by S-mode -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SIP.SSIP set by S-mode write (writable) -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)], $time);
      end


      //=================================================================
      // PHASE 6: M-mode writes MIP.SEIP -> verify visible in SIP
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 6: M-MODE WRITES MIP.SEIP -> VISIBLE IN SIP               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SIP after M-mode sets MIP.SEIP (expect bit 9 set) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)][9] !== 1'b1) begin
         $display("ERROR: SIP.SEIP not visible after M-mode write to MIP -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SIP.SEIP visible after M-mode MIP write -- SIP: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)], $time);
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

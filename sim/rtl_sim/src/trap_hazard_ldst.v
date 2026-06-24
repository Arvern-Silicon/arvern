//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_hazard_ldst
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP HAZARD LDST
//   Load/store pipeline hazard stress across trap boundaries.
//   - CSR read + store same register after MRET (hazard_store_rs2 pattern)
//   - Load + store same register across trap boundary
//   - Handler stack restore + immediate use after MRET
//   - Interleaved load-store-trap checksum computation
//
//   Random SRAM wait states (-all flag) are critical for this test.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Disable error-on-exception
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
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
      // PHASE 2: CSR read + store same register after MRET
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: CSR READ + STORE AFTER MRET              |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Check stored MSTATUS matches expected
      $display("");
      $display("--- MSTATUS stored vs expected ---");
      begin : check_csrr_store
         reg [31:0] stored, expected;
         stored   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         expected = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];

         if (stored !== expected) begin
            $display("ERROR: Stored MSTATUS (0x%h) != expected (0x%h) -- stale forwarding? %t ns",
                     stored, expected, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Stored MSTATUS matches expected (0x%h) %t ns", stored, $time);
         end
      end


      //=================================================================
      // PHASE 3: Load + store same register across trap boundary
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: LOAD + STORE SAME REG ACROSS TRAP        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Values should be from SRAM data area, not stale stack restores
      $display("");
      $display("--- Load-store across trap boundary ---");
      check_mem_value(`SPAD(32'h30), 32'h11111111);
      check_mem_value(`SPAD(32'h34), 32'h22222222);
      check_mem_value(`SPAD(32'h38), 32'h33333333);


      //=================================================================
      // PHASE 4: Handler restore + immediate use after MRET
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: HANDLER RESTORE + IMMEDIATE USE          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Values should match what was loaded before ECALL
      $display("");
      $display("--- Register values after handler restore ---");
      check_mem_value(`SPAD(32'h40), 32'hFACE0001);
      check_mem_value(`SPAD(32'h44), 32'hFACE0002);
      check_mem_value(`SPAD(32'h48), 32'hFACE0003);


      //=================================================================
      // PHASE 5: Interleaved load-store-trap checksum
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: INTERLEAVED LOAD-STORE-TRAP CHECKSUM     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Checksum verification ---");
      begin : check_checksum
         reg [31:0] actual, expected;
         actual   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];
         expected = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)];

         if (actual !== expected) begin
            $display("ERROR: Checksum mismatch -- actual: 0x%h, expected: 0x%h %t ns",
                     actual, expected, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Checksum correct (0x%h) %t ns", actual, $time);
         end
      end

      // Verify the expected checksum value itself
      check_mem_value(`SPAD(32'h54), 32'hFFFFFFFF);


      // Final register preservation check
      $display("");
      $display("--- Register preservation after all phases ---");
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

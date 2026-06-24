//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_mret_edge
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP MRET EDGE
//   Verify MRET/SRET behavior with unusual MPIE/SPIE pre-states:
//   - MRET with MPIE=0: MIE restored to 0, MPIE set to 1
//   - MRET to U-mode: MPP=00 visible in handler
//   - SRET with SPIE=0: SIE restored to 0, SPIE set to 1
//   - Double MRET: MRET -> ECALL -> MRET chain
//
//   All tests are synchronous -- no testbench-driven IRQ needed.
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

      // Disable error-on-exception (all tests trigger exceptions)
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

      // Verify scratchpad is zeroed
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      // Check callee-saved registers
      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: MRET with MPIE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: MRET WITH MPIE=0                          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS after MRET (MPIE was 0) ---");
      begin : check_mstatus_p2
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];

         // MIE should be 0 (restored from MPIE which was 0)
         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 after MRET (MPIE was 0) -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 after MRET (restored from MPIE=0) %t ns", $time);
         end

         // MPIE should be 1 (set to 1 by MRET per spec)
         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 after MRET (set by MRET) %t ns", $time);
         end

         // MPP should be 00 (reset by MRET)
         if (mstatus_val[12:11] !== 2'b00) begin
            $display("ERROR: MSTATUS.MPP should be 00 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = 00 after MRET (reset by MRET) %t ns", $time);
         end
      end


      //=================================================================
      // PHASE 3: MRET to U-mode with MPIE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: MRET TO U-MODE (MPIE=0)                   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS in ECALL handler (trapped from U-mode) ---");
      begin : check_mstatus_p3
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];

         // MPP should be 00 (trapped from U-mode)
         if (mstatus_val[12:11] !== 2'b00) begin
            $display("ERROR: MSTATUS.MPP should be 00 (trapped from U-mode) -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = 00 (trapped from U-mode) %t ns", $time);
         end
      end

      // Check MCAUSE = 8 (ECALL from U-mode)
      $display("");
      $display("--- MCAUSE verification (ECALL from U-mode) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000008);


      //=================================================================
      // PHASE 4: SRET with SPIE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: SRET WITH SPIE=0                          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS after SRET+ECALL (SPIE was 0) ---");
      begin : check_mstatus_p4
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)];

         // SIE should be 0 (restored from SPIE which was 0)
         if (mstatus_val[1] !== 1'b0) begin
            $display("ERROR: MSTATUS.SIE should be 0 after SRET (SPIE was 0) -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.SIE = 0 after SRET (restored from SPIE=0) %t ns", $time);
         end

         // SPIE should be 1 (set to 1 by SRET per spec)
         if (mstatus_val[5] !== 1'b1) begin
            $display("ERROR: MSTATUS.SPIE should be 1 after SRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.SPIE = 1 after SRET (set by SRET) %t ns", $time);
         end
      end


      //=================================================================
      // PHASE 5: Double MRET
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: DOUBLE MRET CHAIN                         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Double MRET success ---");
      begin : check_double_mret
         reg [31:0] success;
         success = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];

         if (success !== 32'h00000001) begin
            $display("ERROR: Double MRET chain did not complete -- flag: 0x%h %t ns", success, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Double MRET chain completed successfully %t ns", $time);
         end
      end


      // Check callee-saved registers preserved
      $display("");
      $display("--- Register preservation after all phases ---");
      check_cpu_reg(18, 32'hAAAAAAAA);   // s2
      check_cpu_reg(19, 32'hBBBBBBBB);   // s3
      check_cpu_reg(20, 32'hCCCCCCCC);   // s4
      check_cpu_reg(21, 32'hDDDDDDDD);   // s5
      check_cpu_reg(22, 32'hEEEEEEEE);   // s6


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_mprv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MPRV
//   MSTATUS.MPRV verification:
//   - MPRV=0: stores use current privilege (M-mode → privileged AHB)
//   - MPRV=1, MPP=U: stores use U-mode privilege (HPROT[1]=0)
//   - MPRV=1, MPP=S: stores use S-mode privilege (HPROT[1]=1, HSMODE=1)
//   - MPRV=1, MPP=M: stores use M-mode privilege (HPROT[1]=1, HSMODE=0)
//   - MPRV cleared on MRET when MPP != M
//   - MPRV NOT cleared on MRET when MPP == M
//   - Back-to-back CSR write + store timing
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

//=========================================================================
// AHB HPROT/HSMODE capture logic
//
// Monitor data AHB bus for stores to probe addresses (0x80000100-0x80000114).
// Capture HPROT[1] (privileged bit) and HSMODE at AHB address phase.
//=========================================================================

reg        captured_hprot_p1, captured_hsmode_p1, captured_valid_p1;
reg        captured_hprot_p2, captured_hsmode_p2, captured_valid_p2;
reg        captured_hprot_p3, captured_hsmode_p3, captured_valid_p3;
reg        captured_hprot_p4, captured_hsmode_p4, captured_valid_p4;
reg        captured_hprot_p5, captured_hsmode_p5, captured_valid_p5;
reg        captured_hprot_p7, captured_hsmode_p7, captured_valid_p7;

initial begin
   captured_valid_p1 = 0;
   captured_valid_p2 = 0;
   captured_valid_p3 = 0;
   captured_valid_p4 = 0;
   captured_valid_p5 = 0;
   captured_valid_p7 = 0;
end

always @(posedge free_clk) begin
   // Capture on AHB address phase (htrans=NONSEQ, hwrite=1)
   if (data_htrans == 2'b10 && data_hwrite == 1'b1) begin
      case (data_haddr)
         32'h80000100: begin captured_hprot_p1 <= data_hprot[1]; captured_hsmode_p1 <= data_hsmode; captured_valid_p1 <= 1; end
         32'h80000104: begin captured_hprot_p2 <= data_hprot[1]; captured_hsmode_p2 <= data_hsmode; captured_valid_p2 <= 1; end
         32'h80000108: begin captured_hprot_p3 <= data_hprot[1]; captured_hsmode_p3 <= data_hsmode; captured_valid_p3 <= 1; end
         32'h8000010C: begin captured_hprot_p4 <= data_hprot[1]; captured_hsmode_p4 <= data_hsmode; captured_valid_p4 <= 1; end
         32'h80000110: begin captured_hprot_p5 <= data_hprot[1]; captured_hsmode_p5 <= data_hsmode; captured_valid_p5 <= 1; end
         32'h80000114: begin captured_hprot_p7 <= data_hprot[1]; captured_hsmode_p7 <= data_hsmode; captured_valid_p7 <= 1; end
      endcase
   end
end


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
      // PHASE 1: M-mode store with MPRV=0
      //          Expected: HPROT[1]=1 (privileged), HSMODE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 1: M-MODE STORE, MPRV=0 (NORMAL PRIVILEGED)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS verification (MPRV=0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h200)][17] !== 1'b0) begin
         $display("ERROR: MSTATUS.MPRV should be 0, got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h200)][17], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPRV = 0 %t ns", $time);
      end

      $display("");
      $display("--- AHB HPROT capture (expect: privileged=1, hsmode=0) ---");
      if (!captured_valid_p1) begin
         $display("ERROR: No AHB capture for Phase 1 probe store %t ns", $time);
         error = error + 1;
      end else if (captured_hprot_p1 !== 1'b1 || captured_hsmode_p1 !== 1'b0) begin
         $display("ERROR: HPROT[1]=%b (exp 1), HSMODE=%b (exp 0) %t ns",
                  captured_hprot_p1, captured_hsmode_p1, $time);
         error = error + 1;
      end else begin
         $display("PASS:  HPROT[1]=1 (privileged), HSMODE=0 %t ns", $time);
      end


      //=================================================================
      // PHASE 2: M-mode store with MPRV=1, MPP=U-mode
      //          Expected: HPROT[1]=0 (user), HSMODE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 2: MPRV=1, MPP=U-MODE (USER ACCESS ON AHB)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS verification (MPRV=1, MPP=00) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h204)][17] !== 1'b1) begin
         $display("ERROR: MSTATUS.MPRV should be 1, got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h204)][17], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPRV = 1 %t ns", $time);
      end
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h204)][12:11] !== 2'b00) begin
         $display("ERROR: MSTATUS.MPP should be 00, got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h204)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPP = 00 (U-mode) %t ns", $time);
      end

      $display("");
      $display("--- AHB HPROT capture (expect: privileged=0, hsmode=0) ---");
      if (!captured_valid_p2) begin
         $display("ERROR: No AHB capture for Phase 2 probe store %t ns", $time);
         error = error + 1;
      end else if (captured_hprot_p2 !== 1'b0 || captured_hsmode_p2 !== 1'b0) begin
         $display("ERROR: HPROT[1]=%b (exp 0), HSMODE=%b (exp 0) %t ns",
                  captured_hprot_p2, captured_hsmode_p2, $time);
         error = error + 1;
      end else begin
         $display("PASS:  HPROT[1]=0 (user), HSMODE=0 %t ns", $time);
      end


      //=================================================================
      // PHASE 3: M-mode store with MPRV=1, MPP=S-mode
      //          Expected: HPROT[1]=1 (privileged), HSMODE=1
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 3: MPRV=1, MPP=S-MODE (SUPERVISOR ACCESS ON AHB)    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS verification (MPRV=1, MPP=01) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h208)][17] !== 1'b1) begin
         $display("ERROR: MSTATUS.MPRV should be 1, got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h208)][17], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPRV = 1 %t ns", $time);
      end
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h208)][12:11] !== 2'b01) begin
         $display("ERROR: MSTATUS.MPP should be 01, got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h208)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPP = 01 (S-mode) %t ns", $time);
      end

      $display("");
      $display("--- AHB HPROT capture (expect: privileged=1, hsmode=1) ---");
      if (!captured_valid_p3) begin
         $display("ERROR: No AHB capture for Phase 3 probe store %t ns", $time);
         error = error + 1;
      end else if (captured_hprot_p3 !== 1'b1 || captured_hsmode_p3 !== 1'b1) begin
         $display("ERROR: HPROT[1]=%b (exp 1), HSMODE=%b (exp 1) %t ns",
                  captured_hprot_p3, captured_hsmode_p3, $time);
         error = error + 1;
      end else begin
         $display("PASS:  HPROT[1]=1 (privileged), HSMODE=1 (supervisor) %t ns", $time);
      end


      //=================================================================
      // PHASE 4: M-mode store with MPRV=1, MPP=M-mode
      //          Expected: HPROT[1]=1 (privileged), HSMODE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 4: MPRV=1, MPP=M-MODE (MACHINE ACCESS ON AHB)       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS verification (MPRV=1, MPP=11) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20C)][17] !== 1'b1) begin
         $display("ERROR: MSTATUS.MPRV should be 1, got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20C)][17], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPRV = 1 %t ns", $time);
      end
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20C)][12:11] !== 2'b11) begin
         $display("ERROR: MSTATUS.MPP should be 11, got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20C)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPP = 11 (M-mode) %t ns", $time);
      end

      $display("");
      $display("--- AHB HPROT capture (expect: privileged=1, hsmode=0) ---");
      if (!captured_valid_p4) begin
         $display("ERROR: No AHB capture for Phase 4 probe store %t ns", $time);
         error = error + 1;
      end else if (captured_hprot_p4 !== 1'b1 || captured_hsmode_p4 !== 1'b0) begin
         $display("ERROR: HPROT[1]=%b (exp 1), HSMODE=%b (exp 0) %t ns",
                  captured_hprot_p4, captured_hsmode_p4, $time);
         error = error + 1;
      end else begin
         $display("PASS:  HPROT[1]=1 (privileged), HSMODE=0 %t ns", $time);
      end


      //=================================================================
      // PHASE 5: MPRV cleared on MRET to S-mode (MPP != M)
      //          After returning to M-mode via ECALL, MPRV should be 0
      //          Expected: HPROT[1]=1 (privileged, M-mode), HSMODE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 5: MPRV CLEARED ON MRET TO S-MODE (MPP!=M)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS verification (MPRV should be 0 after MRET to S) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h210)][17] !== 1'b0) begin
         $display("ERROR: MSTATUS.MPRV should be 0 after MRET (MPP=S), got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h210)][17], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPRV = 0 (cleared by MRET to S-mode) %t ns", $time);
      end

      $display("");
      $display("--- AHB HPROT capture (expect: privileged=1, hsmode=0) ---");
      if (!captured_valid_p5) begin
         $display("ERROR: No AHB capture for Phase 5 probe store %t ns", $time);
         error = error + 1;
      end else if (captured_hprot_p5 !== 1'b1 || captured_hsmode_p5 !== 1'b0) begin
         $display("ERROR: HPROT[1]=%b (exp 1), HSMODE=%b (exp 0) %t ns",
                  captured_hprot_p5, captured_hsmode_p5, $time);
         error = error + 1;
      end else begin
         $display("PASS:  HPROT[1]=1 (privileged), HSMODE=0 %t ns", $time);
      end


      //=================================================================
      // PHASE 6: MPRV NOT cleared on MRET when MPP=M
      //          Verify MPRV is preserved
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 6: MPRV PRESERVED ON MRET TO M-MODE (MPP=M)         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MSTATUS verification (MPRV should still be 1 after MRET to M) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h214)][17] !== 1'b1) begin
         $display("ERROR: MSTATUS.MPRV should be 1 after MRET (MPP=M), got %b %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h214)][17], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MSTATUS.MPRV = 1 (preserved by MRET to M-mode) %t ns", $time);
      end


      //=================================================================
      // PHASE 7: Back-to-back CSR write + store timing
      //          Set MPRV=1 (MPP=U) then immediately store
      //          Expected: HPROT[1]=0 (user), HSMODE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 7: BACK-TO-BACK CSR WRITE + STORE (TIMING)           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- AHB HPROT capture (expect: privileged=0, hsmode=0) ---");
      if (!captured_valid_p7) begin
         $display("ERROR: No AHB capture for Phase 7 probe store %t ns", $time);
         error = error + 1;
      end else if (captured_hprot_p7 !== 1'b0 || captured_hsmode_p7 !== 1'b0) begin
         $display("ERROR: HPROT[1]=%b (exp 0), HSMODE=%b (exp 0) %t ns",
                  captured_hprot_p7, captured_hsmode_p7, $time);
         error = error + 1;
      end else begin
         $display("PASS:  HPROT[1]=0 (user), HSMODE=0 (back-to-back timing OK) %t ns", $time);
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

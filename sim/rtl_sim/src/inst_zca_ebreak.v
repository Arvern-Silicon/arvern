//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_ebreak
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.EBREAK
//   Comprehensive C.EBREAK trap handling verification:
//   - MCAUSE correctness (cause 3 = Breakpoint)
//   - MEPC save (points to C.EBREAK, 2-byte aligned)
//   - MSTATUS save/restore (MIE, MPIE, MPP)
//   - MTVAL verification (should be 0 for EBREAK)
//   - MTVEC configuration
//   - MRET return to correct PC (MEPC+2 for compressed)
//   - Multiple consecutive C.EBREAKs
//   - Back-to-back C.EBREAKs with MEPC verification
//   - Pipeline stress (load/store/ALU before C.EBREAK)
//   - Register preservation across trap entry/exit
//   - C.EBREAK with MIE=0 (synchronous exceptions ignore MIE)
//   - Mixed C.EBREAK and standard EBREAK (instruction size detection)
//   - Stack pointer integrity across multiple traps
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

      // Disable error-on-exception for this test (EBREAK is intentional)
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

      // Verify scratchpad is zeroed (trap_count should be 0)
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      // Check MTVEC readback
      $display("");
      $display("--- MTVEC readback ---");
      begin : check_mtvec
         reg [31:0] mtvec_val;
         mtvec_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h3C)];

         // MTVEC should have mode=00 (direct) in bits [1:0]
         if (mtvec_val[1:0] !== 2'b00) begin
            $display("ERROR: MTVEC mode should be 00 (direct) -- MTVEC: 0x%h %t ns", mtvec_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MTVEC mode = 00 (direct) %t ns", $time);
         end

         // MTVEC base should be non-zero (trap handler address)
         if (mtvec_val[31:2] == 30'h0) begin
            $display("ERROR: MTVEC base should be non-zero -- MTVEC: 0x%h %t ns", mtvec_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MTVEC base = 0x%h %t ns", {mtvec_val[31:2], 2'b00}, $time);
         end
      end


      //=================================================================
      // PHASE 2: First C.EBREAK - basic trap entry/exit
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: FIRST C.EBREAK - BASIC TRAP ENTRY/EXIT    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Check trap count = 1
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // Check MCAUSE = 3 (Breakpoint)
      $display("");
      $display("--- MCAUSE verification ---");
      check_mem_value(`SPAD(32'h04), 32'h00000003);

      // Check MEPC matches expected (firmware stored the c.ebreak PC)
      $display("");
      $display("--- MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)], $time);
      end

      // Verify MEPC is 2-byte aligned (C.EBREAK is a compressed instruction)
      $display("");
      $display("--- MEPC alignment check ---");
      begin : check_mepc_align
         reg [31:0] mepc_val;
         mepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         // Bit 0 should be 0 (at least halfword aligned)
         if (mepc_val[0] !== 1'b0) begin
            $display("ERROR: MEPC should be halfword-aligned -- MEPC: 0x%h %t ns", mepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MEPC is halfword-aligned -- value: 0x%h %t ns", mepc_val, $time);
         end
      end

      // Check MTVAL = 0
      $display("");
      $display("--- MTVAL verification ---");
      check_mem_value(`SPAD(32'h44), 32'h00000000);

      // Check MSTATUS inside trap handler:
      //   - MIE (bit 3) should be 0 (disabled on trap entry)
      //   - MPIE (bit 7) should be 1 (saved from MIE which was 1)
      //   - MPP (bits 12:11) should be 11 (trapped from M-mode)
      $display("");
      $display("--- MSTATUS on trap entry ---");
      begin : check_mstatus_trap1
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

         // MIE = 0
         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 in trap handler %t ns", $time);
         end

         // MPIE = 1
         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 in trap handler %t ns", $time);
         end

         // MPP = 11
         if (mstatus_val[12:11] !== 2'b11) begin
            $display("ERROR: MSTATUS.MPP should be 11 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = 11 in trap handler %t ns", $time);
         end
      end

      // Check MSTATUS after MRET:
      //   - MIE (bit 3) should be 1 (restored from MPIE)
      //   - MPIE (bit 7) should be 1 (set to 1 by MRET)
      $display("");
      $display("--- MSTATUS after MRET ---");
      begin : check_mstatus_mret1
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];

         // MIE = 1 (restored)
         if (mstatus_val[3] !== 1'b1) begin
            $display("ERROR: MSTATUS.MIE should be 1 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 1 after MRET %t ns", $time);
         end

         // MPIE = 1
         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 after MRET %t ns", $time);
         end
      end

      // Check callee-saved registers preserved across trap
      $display("");
      $display("--- Register preservation ---");
      check_cpu_reg(18, 32'hAAAAAAAA);   // s2
      check_cpu_reg(19, 32'hBBBBBBBB);   // s3
      check_cpu_reg(20, 32'hCCCCCCCC);   // s4
      check_cpu_reg(21, 32'hDDDDDDDD);   // s5
      check_cpu_reg(22, 32'hEEEEEEEE);   // s6


      //=================================================================
      // PHASE 3: Second C.EBREAK - consecutive traps with ALU stress
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: SECOND C.EBREAK - CONSECUTIVE TRAPS       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Check trap count = 2
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      // Check MCAUSE = 3 again
      $display("");
      $display("--- MCAUSE verification (2nd C.EBREAK) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000003);

      // Check MEPC matches expected
      $display("");
      $display("--- MEPC verification (2nd C.EBREAK) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)], $time);
      end

      // Check MSTATUS inside 2nd trap handler
      $display("");
      $display("--- MSTATUS on 2nd trap entry ---");
      begin : check_mstatus_trap2
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];

         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 in 2nd trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 in 2nd trap handler %t ns", $time);
         end

         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 in 2nd trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 in 2nd trap handler %t ns", $time);
         end
      end

      // Check ALU results survived the C.EBREAK
      $display("");
      $display("--- ALU results after C.EBREAK ---");
      check_cpu_reg(12, 32'hACF13568);   // a2 = add
      check_cpu_reg(13, 32'h88888888);   // a3 = xor
      check_cpu_reg(14, 32'h12345670);   // a4 = and
      check_cpu_reg(15, 32'h9ABCDEF8);   // a5 = or

      // Check callee-saved registers still preserved
      $display("");
      $display("--- Register preservation (after 2nd C.EBREAK) ---");
      check_cpu_reg(18, 32'hAAAAAAAA);   // s2
      check_cpu_reg(19, 32'hBBBBBBBB);   // s3
      check_cpu_reg(20, 32'hCCCCCCCC);   // s4
      check_cpu_reg(21, 32'hDDDDDDDD);   // s5
      check_cpu_reg(22, 32'hEEEEEEEE);   // s6


      //=================================================================
      // PHASE 4: Back-to-back C.EBREAKs
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: BACK-TO-BACK C.EBREAKS                    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Check trap count = 4
      check_mem_value(`SPAD(32'h00), 32'h00000004);

      // Check MCAUSE for both back-to-back traps
      $display("");
      $display("--- MCAUSE verification (back-to-back) ---");
      check_mem_value(`SPAD(32'h28), 32'h00000003);   // trap3
      check_mem_value(`SPAD(32'h30), 32'h00000003);   // trap4

      // Check MEPC for back-to-back trap #3
      $display("");
      $display("--- MEPC verification (3rd C.EBREAK) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h68)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h68)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)], $time);
      end

      // Check MEPC for back-to-back trap #4
      $display("");
      $display("--- MEPC verification (4th C.EBREAK) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h6C)]) begin
         $display("ERROR: MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h6C)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)], $time);
      end


      //=================================================================
      // PHASE 5: Pipeline stress + register preservation
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: PIPELINE STRESS + REGISTER PRESERVATION   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      // Check trap count = 5
      check_mem_value(`SPAD(32'h00), 32'h00000005);

      // Check s0 preserved through load+ALU+C.EBREAK
      $display("");
      $display("--- Pipeline register preservation ---");
      check_mem_value(`SPAD(32'h40), 32'hBD5B7DDE);


      //=================================================================
      // PHASE 6: C.EBREAK with MIE=0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 6: C.EBREAK WITH MIE=0                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);

      // Check trap count = 6
      check_mem_value(`SPAD(32'h00), 32'h00000006);

      // Check MCAUSE = 3
      $display("");
      $display("--- MCAUSE with MIE=0 ---");
      check_mem_value(`SPAD(32'h48), 32'h00000003);

      // Check MSTATUS inside handler when MIE was 0 before trap
      $display("");
      $display("--- MSTATUS on trap entry (MIE was 0) ---");
      begin : check_mstatus_mie0
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h4C)];

         // MIE = 0
         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 in handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 in handler %t ns", $time);
         end

         // MPIE = 0 (MIE was 0 when trap was taken)
         if (mstatus_val[7] !== 1'b0) begin
            $display("ERROR: MSTATUS.MPIE should be 0 (MIE was 0 before trap) -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 0 (MIE was 0 before trap) %t ns", $time);
         end

         // MPP = 11
         if (mstatus_val[12:11] !== 2'b11) begin
            $display("ERROR: MSTATUS.MPP should be 11 -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = 11 %t ns", $time);
         end
      end

      // Check MSTATUS after MRET from MIE=0 trap
      $display("");
      $display("--- MSTATUS after MRET (MIE was 0) ---");
      begin : check_mstatus_mret_mie0
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h70)];

         // MIE = 0 (restored from MPIE=0)
         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 after MRET (restored from MPIE=0) %t ns", $time);
         end

         // MPIE = 1 (set to 1 by MRET)
         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 after MRET %t ns", $time);
         end
      end


      //=================================================================
      // PHASE 7: Mixed C.EBREAK/standard EBREAK + SP integrity
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 7: MIXED C.EBREAK/STD EBREAK + SP INTEGRITY  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);

      // Check trap count = 8 (6 previous + std EBREAK + C.EBREAK)
      check_mem_value(`SPAD(32'h00), 32'h00000008);

      // Check standard EBREAK: MCAUSE = 3
      $display("");
      $display("--- Standard EBREAK cause ---");
      check_mem_value(`SPAD(32'h50), 32'h00000003);

      // Check standard EBREAK MEPC
      $display("");
      $display("--- Standard EBREAK MEPC verification ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)]) begin
         $display("ERROR: Std EBREAK MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  Std EBREAK MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)], $time);
      end

      // Check C.EBREAK after std EBREAK: MCAUSE = 3
      $display("");
      $display("--- C.EBREAK cause after std EBREAK ---");
      check_mem_value(`SPAD(32'h58), 32'h00000003);

      // Check C.EBREAK MEPC
      $display("");
      $display("--- C.EBREAK MEPC verification (after std EBREAK) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h5C)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h78)]) begin
         $display("ERROR: C.EBREAK MEPC mismatch -- MEPC: 0x%h / expected: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h5C)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h78)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  C.EBREAK MEPC matches expected -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h5C)], $time);
      end

      // Check stack pointer integrity
      $display("");
      $display("--- Stack pointer integrity ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)]) begin
         $display("ERROR: SP mismatch -- before: 0x%h / after: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  SP preserved across traps -- value: 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)], $time);
      end

      // Final MSTATUS check
      $display("");
      $display("--- Final MSTATUS ---");
      begin : check_mstatus_final
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)];

         if (mstatus_val[3] !== 1'b1) begin
            $display("ERROR: Final MSTATUS.MIE should be 1 -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Final MSTATUS.MIE = 1 %t ns", $time);
         end
      end

      // Final register check
      $display("");
      $display("--- Final register preservation (after 8 traps) ---");
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

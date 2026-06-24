//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_lui_addi16sp_reserved
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.LUI / C.ADDI16SP RESERVED nzimm=0 (illegal trap)
//   Every nzimm=0 cell in the Q1 funct3=011 truth table must raise mcause=2.
//
//   Pre-fix : Phase 2 (C.ADDI16SP), Phase 3, Phase 4 (C.LUI) silently
//   NOP/write-zero → 3 missing traps → FAIL
//   Post-fix: all 4 nzimm=0 cells trap → 4 traps total → PASS
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset
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

      // Test deliberately raises illegal-inst traps
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: CHECK INITIALIZATION                          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // PHASE 2: C.ADDI16SP imm=0 (0x6101) must trap as mcause=2
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: C.ADDI16SP imm=0  (encoding 0x6101)  → expect mcause=2  |");
      $display(" ====================================================================");
      $display("");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // trap_count should be 1
      $display("");
      $display("--- trap_count after Phase 2 (expect 1) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);
      $display("--- Phase 2 mcause (expect 2 = illegal) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000002);


      //=================================================================
      // PHASE 3: C.LUI x1, imm=0 (0x6081) must trap; canary 0xCAFEBABE
      // must survive (no silent write of 0 to x1).
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 3: C.LUI x1, imm=0   (encoding 0x6081)  → expect mcause=2  |");
      $display(" ====================================================================");
      $display("");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count after Phase 3 (expect 2) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);
      $display("--- Phase 3 mcause (expect 2 = illegal) ---");
      check_mem_value(`SPAD(32'h08), 32'h00000002);
      $display("--- x1 canary preserved (expect 0xCAFEBABE — proves no silent lui rd,0) ---");
      check_cpu_reg(1, 32'hCAFEBABE);


      //=================================================================
      // PHASE 4: C.LUI x5, imm=0 (0x6281) must trap; canary 0xDEAD0000
      // must survive.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 4: C.LUI x5, imm=0   (encoding 0x6281)  → expect mcause=2  |");
      $display(" ====================================================================");
      $display("");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count after Phase 4 (expect 3) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000003);
      $display("--- Phase 4 mcause (expect 2 = illegal) ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000002);
      $display("--- x5 canary preserved (expect 0xDEAD0000) ---");
      check_cpu_reg(5, 32'hDEAD0000);


      //=================================================================
      // PHASE 4b: C.LUI x0, imm=0 (0x6001) — Cell A0 sanity (always trapped)
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 4b: C.LUI x0, imm=0  (encoding 0x6001)  → expect mcause=2  |");
      $display(" ====================================================================");
      $display("");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count after Phase 4b (expect 4) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000004);
      $display("--- Phase 4b mcause (expect 2 = illegal) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000002);


      // Positive C.LUI / C.ADDI16SP execution coverage lives in
      // inst_zca_lui.{s,v} and inst_zca_addi16sp.{s,v} — not duplicated here.

      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

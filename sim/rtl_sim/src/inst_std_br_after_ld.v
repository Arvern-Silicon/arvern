//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_br_after_ld
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: BRANCH/JAL/JALR AFTER LOAD/STORE
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

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

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|          BRANCH/JAL/JALR AFTER LOAD/STORE TEST                    |");
      $display(" ====================================================================");
      $display("|  NO-HAZARD: branch ops use regs != load dest (ex_ldst_busy bubble) |");
      $display("|  DATA-HAZARD: branch/JALR src reg = load dest (load-use stall)    |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");

      // -------------------------------------------------------
      // Section 1: JAL immediately after SW
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h11111111);
      $display("Section 1 PASS: JAL immediately after SW - link register correct");
      // x10 link register value is PC-relative; self-checked in .s via BNE to test_fail

      // -------------------------------------------------------
      // Section 2: JAL immediately after LW (load to x2, no dep)
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h22222222);
      $display("Section 2 PASS: JAL immediately after LW - link register correct");

      // -------------------------------------------------------
      // Section 3: BNE immediately after LW (load to x4, BNE uses x3/x5)
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h33333333);
      $display("Section 3 PASS: BNE immediately after LW - branch taken correctly");
      check_cpu_reg(3,  32'hAAAAAAAA);   // x3 must be preserved
      check_cpu_reg(5,  32'hBBBBBBBB);  // x5 must be preserved

      // -------------------------------------------------------
      // Section 4: JALR immediately after LW (load to x8, JALR uses x6)
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h44444444);
      $display("Section 4 PASS: JALR immediately after LW - link register correct");
      check_cpu_reg(8,  32'hCCCCCCCC);  // x8 must have the loaded value

      // -------------------------------------------------------
      // Section 5: BEQ immediately after SW
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h55555555);
      $display("Section 5 PASS: BEQ immediately after SW - branch taken correctly");

      // -------------------------------------------------------
      // Section 6: LW -> BNE -> SW -> JAL back-to-back chain
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h66666666);
      $display("Section 6 PASS: Back-to-back LW/BNE/SW/JAL chain correct");
      check_cpu_reg(16, 32'hDEAD0000);  // x16 = loaded value from LW

      // -------------------------------------------------------
      // Section 7: BNE immediately after LW, RS1 = load dest
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h77777777);
      $display("Section 7 PASS: BNE after LW (RS1=load dest) - stall + branch taken");
      check_cpu_reg(2,  32'h11111111);  // x2 must have the loaded value

      // -------------------------------------------------------
      // Section 8: BNE immediately after LW, RS2 = load dest
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h88888888);
      $display("Section 8 PASS: BNE after LW (RS2=load dest) - stall + branch taken");
      check_cpu_reg(5,  32'h33333333);  // x5 must have the loaded value

      // -------------------------------------------------------
      // Section 9: JALR immediately after LW, RS1 = load dest
      // -------------------------------------------------------
      @(probes_cpu.x31==32'h99999999);
      $display("Section 9 PASS: JALR after LW (RS1=load dest) - stall + jump correct");
      // x8 = loaded target address (PC-relative); self-checked in .s via BNE to test_fail

      // -------------------------------------------------------
      // Section 10: BEQ immediately after LW, RS1 = load dest
      // -------------------------------------------------------
      @(probes_cpu.x31==32'hA0A0A0A0);
      $display("Section 10 PASS: BEQ after LW (RS1=load dest) - stall + branch taken");
      check_cpu_reg(11, 32'h55555555); // x11 must have the loaded value

      // -------------------------------------------------------
      // Final: all sections passed
      // -------------------------------------------------------
      @(probes_cpu.x31==32'hDEADBEEF || probes_cpu.x31==32'hBADC0DE0);

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;
      repeat(30) @(posedge free_clk);

      if (probes_cpu.x31 == 32'hBADC0DE0) begin
         $display("");
         $display("======================================================================");
         $display("ERROR: Test FAILED - x31 = 0xBADC0DE0");
         $display("----------------------------------------------------------------------");
         $display("Error Code  (x30): 0x%08h", probes_cpu.x30);
         $display("  Test Number:     0x%02h", (probes_cpu.x30 >> 8) & 8'hFF);
         $display("  Check Number:    0x%02h", probes_cpu.x30 & 8'hFF);
         $display("======================================================================");
         $display("");
         stimulus_done = 1;
         $finish;
      end

      $display("");
      $display("Test PASSED - All branch-after-load/store operations completed successfully");
      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

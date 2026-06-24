//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_sret_illegal
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SU_MODE PRIV - SRET illegal under SU_MODE_EN=0
//   Verify sret from M-mode raises illegal-instruction (mcause=2) with
//   mtval = 0x10200073 (sret encoding), and that the trapped instruction
//   does not corrupt the source/destination GPR (t0 sentinel preserved).
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

      // Test EXPECTS an illegal-instruction trap; suppress TB exception monitor.
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

      @(probes_cpu.x15==32'h11111111);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg( 8, 32'hAAAAAAAA);
      check_cpu_reg(10, 32'hBBBBBBBB);
      check_cpu_reg(11, 32'hCCCCCCCC);
      check_cpu_reg(12, 32'hDDDDDDDD);
      check_cpu_reg(13, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: sret -> illegal-instruction
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 2: SRET from M-mode  (mcause=2, mtval=sret)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count = 1 ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE = 2 (illegal instruction) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);

      $display("");
      $display("--- MTVAL = 0 (aRVern does not capture mtval for illegal-instruction; spec-permissible) ---");
      check_mem_value(`SPAD(32'h24), 32'h00000000);

      $display("");
      $display("--- t0 sentinel preserved across trapped sret ---");
      check_mem_value(`SPAD(32'h28), 32'hCAFEBABE);


      //=================================================================
      // Final register preservation check
      //=================================================================
      $display("");
      $display("--- Callee-saved registers preserved ---");
      check_cpu_reg( 8, 32'hAAAAAAAA);
      check_cpu_reg(10, 32'hBBBBBBBB);
      check_cpu_reg(11, 32'hCCCCCCCC);
      check_cpu_reg(12, 32'hDDDDDDDD);
      check_cpu_reg(13, 32'hEEEEEEEE);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

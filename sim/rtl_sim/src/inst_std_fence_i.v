//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_fence_i
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: FENCE.I
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
      $display("|           FENCE.I TEST: INIT (all regs = 0xFFFFFFFF)              |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware...");

      @(probes_cpu.x31==32'hFFFFFFFF);

      check_cpu_reg( 1, 32'hFFFFFFFF);
      check_cpu_reg( 2, 32'hFFFFFFFF);
      check_cpu_reg( 3, 32'hFFFFFFFF);
      check_cpu_reg( 4, 32'hFFFFFFFF);
      check_cpu_reg( 5, 32'hFFFFFFFF);
      check_cpu_reg( 6, 32'hFFFFFFFF);
      check_cpu_reg( 7, 32'hFFFFFFFF);
      check_cpu_reg( 8, 32'hFFFFFFFF);
      check_cpu_reg( 9, 32'hFFFFFFFF);
      check_cpu_reg(10, 32'hFFFFFFFF);
      check_cpu_reg(11, 32'hFFFFFFFF);
      check_cpu_reg(12, 32'hFFFFFFFF);
      check_cpu_reg(13, 32'hFFFFFFFF);
      check_cpu_reg(14, 32'hFFFFFFFF);
      check_cpu_reg(15, 32'hFFFFFFFF);
      check_cpu_reg(16, 32'hFFFFFFFF);
      check_cpu_reg(17, 32'hFFFFFFFF);
      check_cpu_reg(18, 32'hFFFFFFFF);
      check_cpu_reg(19, 32'hFFFFFFFF);
      check_cpu_reg(20, 32'hFFFFFFFF);
      check_cpu_reg(21, 32'hFFFFFFFF);
      check_cpu_reg(22, 32'hFFFFFFFF);
      check_cpu_reg(23, 32'hFFFFFFFF);
      check_cpu_reg(24, 32'hFFFFFFFF);
      check_cpu_reg(25, 32'hFFFFFFFF);
      check_cpu_reg(26, 32'hFFFFFFFF);
      check_cpu_reg(27, 32'hFFFFFFFF);
      check_cpu_reg(28, 32'hFFFFFFFF);
      check_cpu_reg(29, 32'hFFFFFFFF);
      check_cpu_reg(30, 32'hFFFFFFFF);
      check_cpu_reg(31, 32'hFFFFFFFF);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       FENCE.I TEST PHASE 1: Smoke (no pending ops)               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware...");

      @(probes_cpu.x31==32'h11111111);

      // x1..x4 set around back-to-back FENCE.I instructions
      check_cpu_reg( 1, 32'hA1A1A1A1);
      check_cpu_reg( 2, 32'hB2B2B2B2);
      check_cpu_reg( 3, 32'hC3C3C3C3);
      check_cpu_reg( 4, 32'hD4D4D4D4);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       FENCE.I TEST PHASE 2: Store-drain stall                    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware...");

      @(probes_cpu.x31==32'h22222222);

      // Values stored before FENCE.I, loaded back after — verifies store completion
      check_cpu_reg( 5, 32'hABCD1234);
      check_cpu_reg( 6, 32'h5678EF01);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       FENCE.I TEST PHASE 3: Self-modifying code (SRAM_X)         |");
      $display("|                                                                    |");
      $display("|  Patches patch_buf in SRAM_X with:                                |");
      $display("|    [0] ADDI x10, x0, 0x555  (0x55500513)                          |");
      $display("|    [4] JALR x0, x1, 0       (0x00008067)                          |");
      $display("|  FENCE.I flushes the instruction buffer, then jumps there.        |");
      $display("|  x10==0x555 confirms correct execution of patched instructions.   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware...");

      @(probes_cpu.x31==32'hdeadbeef);

      // Disable random IRQ injection before final checks
      random_irq_enable = 0;

      // x10 must hold 0x555 — set by the patched ADDI instruction in SRAM_X.
      // Any other value (e.g. 0xDEAD0000) means the patched code was not reached.
      check_cpu_reg(10, 32'h00000555);


      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_msip_clear_mret
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: a level IRQ cleared by the store right before mret / MIE set
// is taken exactly once (see the .s).
//----------------------------------------------------------------------------
initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      use_aclint = 1'b1;
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|   LEVEL IRQ CLEARED BY THE STORE RIGHT BEFORE MRET / MIE SET        |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h22222222);
      $display("INFO:  phase 1 (livelock_prot_en=1): %0d handler entries for 8 IPIs", probes_cpu.x08);
      check_cpu_reg(8, 32'd8);

      @(probes_cpu.x31==32'h33333333);
      $display("INFO:  phase 2 (livelock_prot_en=0): %0d handler entries for 8 IPIs", probes_cpu.x08 - 8);
      check_cpu_reg(8, 32'd16);

      @(probes_cpu.x31==32'hdeadbeef);
      $display("INFO:  phase 3 (clear, then MIE=1): %0d handler entries (expected 0)", probes_cpu.x08 - 16);   // entries beyond phase 2
      check_cpu_reg(8, 32'd16);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

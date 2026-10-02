//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_ldst_base_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Load/store base-register walk -- every GPR x1..x31 as rs1
//
//   Unpriv 2.6: "The effective address is obtained by adding register rs1 to
//   the sign-extended 12-bit offset." Each xN stores V_N = 0xC0DE0000 + N to
//   its own word and loads it back twice (into another register and into
//   itself). The three words per N must all hold V_N.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      $display("");
      $display(" ====================================================================");
      $display("|        LOAD/STORE BASE-REGISTER WALK (x1..x31 as rs1)              |");
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);

      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      for (ii = 1; ii < 32; ii = ii + 1) begin
         $display("--- base x%0d ---", ii);
         check_mem_value(`SPAD(32'h200 + ii*4), 32'hC0DE0000 + ii);   // W_N
         check_mem_value(`SPAD(32'h300 + ii*4), 32'hC0DE0000 + ii);   // lw xL
         check_mem_value(`SPAD(32'h380 + ii*4), 32'hC0DE0000 + ii);   // lw xN, off(xN)
      end

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

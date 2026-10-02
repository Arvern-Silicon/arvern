//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcmt_jt_bit0
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CM.JT / CM.JALT through a table entry with bit 0 set
//
//   Unpriv Zcmt: "j target_address[XLEN-1:0]&~0x1;" and
//   "jal ra, target_address[XLEN-1:0]&~0x1;". Four jumps through entries
//   L|1 (4- and 2-byte aligned L, cm.jt and cm.jalt) must all land on L with
//   no trap; cm.jalt links ra = its own address + 2.
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

      $display("");
      $display(" ====================================================================");
      $display("|        CM.JT / CM.JALT -- TABLE ENTRY BIT 0 IS IGNORED             |");
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);

      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(10) @(posedge free_clk);

      check_cpu_reg(18, 32'h0000000F);   // s2: all four landing sites reached
      check_cpu_reg(19, 32'h00000000);   // s3: error count
      check_cpu_reg(20, 32'h00000000);   // s4: first error code

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcmt_jvt_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: jvt base walk -- CM.JT through tables at many 64-byte bases
//
//   Unpriv Zcmt: "table_address = jvt.base + (index<<2)"; jvt BASE[31:6]
//   writable, MODE[5:0] read-only 0 (doc/arvern_instructions.md). 19 bases
//   (walking ones and zeros over the SRAM_X address bits), one cm.jt each;
//   every jvt read-back must equal the base with MODE = 0.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

reg [31:0] jvt_base [0:18];

initial
   begin
      jvt_base[ 0] = 32'h80000040;  jvt_base[ 1] = 32'h80000080;
      jvt_base[ 2] = 32'h80000100;  jvt_base[ 3] = 32'h80000200;
      jvt_base[ 4] = 32'h80000400;  jvt_base[ 5] = 32'h80000800;
      jvt_base[ 6] = 32'h80001000;  jvt_base[ 7] = 32'h80002000;
      jvt_base[ 8] = 32'h80004000;  jvt_base[ 9] = 32'h80008000;
      jvt_base[10] = 32'h80007F80;  jvt_base[11] = 32'h80007F40;
      jvt_base[12] = 32'h80007EC0;  jvt_base[13] = 32'h80007DC0;
      jvt_base[14] = 32'h80007BC0;  jvt_base[15] = 32'h800077C0;
      jvt_base[16] = 32'h80006FC0;  jvt_base[17] = 32'h80005FC0;
      jvt_base[18] = 32'h80003FC0;

      @(posedge free_clk);
      @(posedge hresetn);

      $display("");
      $display(" ====================================================================");
      $display("|        JVT BASE WALK -- CM.JT THROUGH 19 TABLE BASES               |");
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);

      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      check_cpu_reg(18, 32'd19);         // s2: every step landed
      check_cpu_reg(19, 32'h00000000);   // s3: error count
      check_cpu_reg(20, 32'h00000000);   // s4: first error code

      for (ii = 0; ii < 19; ii = ii + 1)
         check_mem_value(`SPAD(32'hA000 + ii*4), jvt_base[ii]);   // jvt read-back

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_mml_cfg_write
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Smepmp MML write restriction on every unlocked pmpcfg byte --
//   see trap_pmp_mml_cfg_write.s. Expected read-backs derived from PMP_NR:
//   words below PMP_NR/4 take the L=0 bytes only, the last word keeps its
//   locked ROM rule (0x9D) in byte 3, words at or beyond PMP_NR read 0.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] seq_val [0:4];
reg [31:0] expct;
integer    nwords;
integer    ww;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    seq_val[0] = 32'h00000000;   // 0x9C9A9E9D: every byte refused, stays OFF
    seq_val[1] = 32'h19191919;
    seq_val[2] = 32'h18181818;
    seq_val[3] = 32'h18191819;   // 0x9C199C19: only the 0x19 bytes land
    seq_val[4] = 32'h19181918;   // 0x199C199C
    nwords     = PMP_NR / 4;

    wait(probes_cpu.x31 == 32'h11111111);
    $display("MML set, ROM rule locked in entry %0d %t ns", PMP_NR-1, $time);
    if ((probes_cpu.x24 & 32'h5) !== 32'h1) begin      // s8 = mseccfg
       $display("ERROR: mseccfg 0x%h: expected MML=1, RLB=0 %t ns", probes_cpu.x24, $time);
       error = error + 1;
    end

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    for (ww = 0; ww < 4; ww = ww + 1)
       for (kk = 0; kk < 5; kk = kk + 1) begin
          if (ww >= nwords)
             expct = 32'h00000000;
          else if (ww == nwords - 1)
             expct = (seq_val[kk] & 32'h00FFFFFF) | 32'h9D000000;
          else
             expct = seq_val[kk];
          $display("--- pmpcfg%0d step %0d ---", ww, kk);
          check_mem_value(`SPAD(32'h100 + ww*32 + kk*4), expct);
       end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_rv32i_waw_load_alu
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: write-after-write between a slow load and a younger writer
//   63 rounds (3 sources x 7 kinds x 0/1/2 NOPs). For each round the final
//   x5/x6/x7 and the DST word must hold the values of the YOUNGER writer, as
//   laid out in inst_rv32i_waw_load_alu.s. Meant to be run with -all.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;
integer id, src, kind, nops;
reg [31:0] ld_k, exp_a, exp_b, exp_c, exp_d;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      $display("");
      $display(" ====================================================================");
      $display("|        WAW: SLOW LOAD FOLLOWED BY A YOUNGER WRITER OF THE SAME rd  |");
      $display(" ====================================================================");

      wait (probes_cpu.x31 === 32'h11111111);
      wait (probes_cpu.x31 === 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      for (id = 0; id < 63; id = id + 1)
        begin
           src  = id / 21;
           kind = (id % 21) / 3;
           nops = id % 3;
           ld_k = (src == 2) ? 32'hA5A5C3C3 : (32'h5A5A0000 + id);

           exp_b = 32'h66600000 + id;
           exp_c = 32'h77700000 + id;
           exp_d = 32'hDEAD0000 + id;
           case (kind)
             0: exp_a = 32'h00000001;
             1: begin exp_a = 32'h00000001; exp_d = 32'h00000001; end
             2: begin exp_a = 32'h00000001; exp_b = 32'h00000011; end
             3: exp_a = 32'h00000002;
             4: begin exp_a = 32'h00000001; exp_c = ld_k; exp_d = 32'h00000001; end
             5: begin exp_a = 32'h80000000; exp_c = 32'h66600000 + id; exp_d = 32'h66600000 + id; end
             default: exp_a = 32'h8000FF00;
           endcase

           $display("--- round %0d: src=%0d (0=SRAM_X 1=SRAM_NX 2=ROM) kind=%0d nops=%0d ---", id, src, kind, nops);
           $display("    x5 (RESA), expected the younger value 0x%h (the load returned 0x%h)", exp_a, ld_k);
           check_mem_value((32'h100 + id*4)/4, exp_a);
           $display("    x6 (RESB)");
           check_mem_value((32'h200 + id*4)/4, exp_b);
           $display("    x7 (RESC)");
           check_mem_value((32'h300 + id*4)/4, exp_c);
           $display("    DST");
           check_mem_value((32'h400 + id*4)/4, exp_d);
        end

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

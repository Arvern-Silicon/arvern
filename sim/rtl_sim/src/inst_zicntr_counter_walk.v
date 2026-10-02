//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_counter_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Counter data-path walk and minstret carry/borrow boundaries
//
//   PART A: the firmware walks 64 patterns through every counter half (read
//   back, user shadow, other half untouched) and every unprovided HPM counter
//   (reads 0); it counts checks and failures. The check count is recomputed
//   here from ZIHPM_NR so a skipped walk cannot pass.
//
//   PART B1: ECALL at minstreth:minstret = 0x123:FFFFFFFF. Priv 3.3.1: ECALL
//   is "not considered to retire". Handler reads minstret first (expect
//   0xFFFFFFFF), then minstreth (expect 0x124 -- that first read retired and
//   carried; a missed borrow of the un-retired ECALL reads 0x125).
//
//   PART B2: minstret = 0xFFFFFFFE, csrw minstreth 0x456, four NOPs, freeze.
//   The wrap happens after the high-half write, so minstreth = 0x457. The low
//   half is a window: whether the csrw minstreth itself and the freezing
//   csrs are counted is not pinned down by the documentation, so the low half
//   can be 2..4; the window below is 1..6.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define LONG_TIMEOUT

integer    exp_checks;
reg [31:0] v;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;            // B1 takes an ECALL on purpose

      exp_checks = 4 * 64 * 3;
      if (ZIHPM_NR > 0)
         exp_checks = exp_checks + (2 * ZIHPM_NR) * 64 * 3 + (8 - ZIHPM_NR) * 64 * 4;

      $display("");
      $display(" ====================================================================");
      $display("|        COUNTER WALK (mcycle / minstret / mhpmcounterN)             |");
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- mcountinhibit after writing all ones ---");
      v = probes_cpu.x24;
      if (v[2:0] !== 3'b101) begin
         $display("ERROR: mcountinhibit[2:0] = %b, expected 101 (CY, IR set; bit 1 hardwired 0)", v[2:0]);
         error = error + 1;
      end else
         $display("PASS:  mcountinhibit[2:0] = 101");
      for (ii = 0; ii < ZIHPM_NR; ii = ii + 1)
         if (v[3+ii] !== 1'b1) begin
            $display("ERROR: mcountinhibit.HPM%0d reads 0 after writing 1", 3+ii);
            error = error + 1;
         end

      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- PART A: walk (expected %0d checks) ---", exp_checks);
      check_cpu_reg(21, exp_checks);     // s5: checks performed
      check_cpu_reg(22, 32'h00000000);   // s6: failures
      check_cpu_reg(23, 32'h00000000);   // s7: first failure code
      if (probes_cpu.x22 != 0)
         $display("       first failing pattern: 0x%h", probes_cpu.x20);

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      $display("--- PART B1: ECALL at minstret = 0x123:FFFFFFFF ---");
      check_cpu_reg(25, 32'd11);         // s9: mcause = ECALL from M
      check_cpu_reg(16, 32'hFFFFFFFF);   // a6: minstret, ECALL un-retired
      check_cpu_reg(17, 32'h00000124);   // a7: minstreth, borrow then carry

      $display("--- PART B2: csrw minstreth at minstret = 0xFFFFFFFE ---");
      check_cpu_reg(13, 32'h00000457);   // a3: carry landed in the written high half
      v = probes_cpu.x12;
      if (v < 32'd1 || v > 32'd6) begin
         $display("ERROR: B2 minstret = 0x%h, expected a small post-wrap count (1..6)", v);
         error = error + 1;
      end else
         $display("PASS:  B2 minstret = 0x%h (post-wrap window 1..6)", v);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

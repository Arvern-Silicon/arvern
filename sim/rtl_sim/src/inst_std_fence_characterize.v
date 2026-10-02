//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_fence_characterize
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: FENCE characterization -- what each encoding actually holds
//
//   Timestamps three events per trial and prints the relationship:
//     T_aph   the store's accepted address phase on the data bus
//     T_done  its data phase completing (hready) -- the slave has taken it
//     T_mark  the first instruction after the fence becoming visible
//
//   The observers are INDEPENDENT always-blocks, deliberately. A sequential
//   "wait for T_done, then wait for the marker" cannot report a marker that
//   already happened -- Verilog's wait() returns immediately when its condition
//   is already true, so the gap floors at zero and the one interesting outcome,
//   the marker preceding the store's completion, becomes unmeasurable. Each
//   event is therefore latched the cycle it occurs, by a block watching only
//   for it.
//
//   gap = T_mark - T_done, and it is SIGNED: negative means the instruction
//   after the fence became visible while the store was still on the bus.
//
//   Read part A in pairs (even = no fence, odd = fence, same gap) and part B
//   against trial 2. This test measures and prints; it asserts only that the
//   measurement is self-consistent.
//----------------------------------------------------------------------------

`define TARGET   32'h80000100
`define NTRIAL   18

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

integer cyc;
integer t_aph  [0:17];
integer t_done [0:17];
integer t_mark [0:17];
integer trial;
integer cur;
integer gap;
integer delta;
integer measured;
reg     aph_seen;

reg [8*12-1:0] tname [0:17];

initial cyc = 0;
always @(posedge free_clk) cyc <= cyc + 1;

//--------------------------------------------------------------------
// Observer 1: which trial is currently armed
//--------------------------------------------------------------------
initial cur = -1;
always @(posedge free_clk)
   if (probes_cpu.x31 >= 32'h00000300 && probes_cpu.x31 < 32'h00000312)
      cur <= probes_cpu.x31 - 32'h00000300;

//--------------------------------------------------------------------
// Observer 2: the data bus, for the active trial
//--------------------------------------------------------------------
initial aph_seen = 1'b0;
always @(posedge free_clk)
   if (cur >= 0) begin
      if (!aph_seen) begin
         if (data_htrans != 2'b00 && data_haddr == `TARGET && data_hready &&
             t_aph[cur] < 0) begin
            t_aph[cur] <= cyc;
            aph_seen   <= 1'b1;
         end
      end
      else if (data_hready && t_done[cur] < 0) begin
         t_done[cur] <= cyc;
         aph_seen    <= 1'b0;
      end
   end

//--------------------------------------------------------------------
// Observer 3: the marker, latched the cycle it appears -- independent of
// the bus observer, so it can legitimately land BEFORE T_done
//--------------------------------------------------------------------
always @(posedge free_clk)
   for (kk = 0; kk < 18; kk = kk + 1)
      if (probes_cpu.x31 == 32'h00000400 + kk && t_mark[kk] < 0)
         t_mark[kk] <= cyc;

initial
   begin
      for (ii = 0; ii < 18; ii = ii + 1) begin
         t_aph[ii]  = -1;
         t_done[ii] = -1;
         t_mark[ii] = -1;
      end

      tname[0]  = "gap0 none";   tname[1]  = "gap0 iorw";
      tname[2]  = "gap2 none";   tname[3]  = "gap2 iorw";
      tname[4]  = "gap4 none";   tname[5]  = "gap4 iorw";
      tname[6]  = "gap8 none";   tname[7]  = "gap8 iorw";
      tname[8]  = "g2 rw,rw";    tname[9]  = "g2 r,r";
      tname[10] = "g2 w,w";      tname[11] = "g2 i,i";
      tname[12] = "g2 o,o";      tname[13] = "g2 tso";
      tname[14] = "g2 pause";    tname[15] = "gap2 none#2";
      tname[16] = "LD g2 none";  tname[17] = "LD g2 iorw";

      @(posedge free_clk);
      @(posedge hresetn);

      // Pin the bus latency so the store is slow and the measurement does not
      // depend on which timing variant is running. Done before any trial arms.
      @(negedge free_clk);
      s_sram_x_random_ws_en = 0;
      s_sram_x_number_ws    = 6;
      s_rom_random_ws_en    = 0;
      s_rom_number_ws       = 0;

      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(5) @(posedge free_clk);

      $display("");
      $display(" ============================================================================");
      $display("|  FENCE characterization -- store -> <gap> -> <encoding> -> marker, ws = 6  |");
      $display(" ============================================================================");
      $display("");
      $display("   gap = T_mark - T_done, SIGNED.");
      $display("   negative => the instruction after the fence ran while the store was");
      $display("               still on the bus.  >= 0 => it was held to completion.");
      $display("");
      $display("   #   trial         T_aph   T_done   T_mark     gap   vs ctl");
      $display("   -----------------------------------------------------------");

      measured = 0;
      for (trial = 0; trial < 18; trial = trial + 1) begin
         if (t_mark[trial] >= 0 && t_done[trial] >= 0) begin
            gap = t_mark[trial] - t_done[trial];
            // part A pairs with the even (no-fence) trial beside it;
            // part B compares against trial 2 (gap2, no fence)
            // part A pairs with the even trial beside it; part B against trial 2
            // (store, gap2, no fence); part C against trial 16 (LOAD, gap2, no fence)
            if      (trial < 8)   delta = gap - (t_mark[trial & 32'hFFFFFFFE] - t_done[trial & 32'hFFFFFFFE]);
            else if (trial < 16)  delta = gap - (t_mark[2]  - t_done[2]);
            else                  delta = gap - (t_mark[16] - t_done[16]);
            $display("   %2d  %-12s %6d  %6d   %6d  %6d   %6d",
                     trial, tname[trial],
                     t_aph[trial], t_done[trial], t_mark[trial], gap, delta);
            measured = measured + 1;
         end
         else
            $display("   %2d  %-12s -- NOT MEASURED --", trial, tname[trial]);
      end
      $display("   -----------------------------------------------------------");
      $display("");
      $display("   part A: read even/odd pairs -- same gap, fence vs no fence.");
      $display("   part B: 'vs ctl' is against trial 2 (gap2, no fence).");
      $display("   part C: preceding access is a LOAD; 'vs ctl' is against trial 16.");
      $display("");

      // Every measured transfer must see the latency the stimulus pinned, so
      // T_done - T_aph has to be identical across all trials. This is the check
      // that the wait-state model's one-transfer lag defeated: the FIRST SRAM_X
      // transfer runs at the count latched at reset, not the pinned one, and
      // showed 1 cycle where every other trial showed 7. Without a guard the bad
      // value silently became the calibration baseline and every delta was wrong.
      for (trial = 1; trial < 18; trial = trial + 1)
         if (t_aph[trial] >= 0 && t_done[trial] >= 0 &&
             (t_done[trial] - t_aph[trial]) !== (t_done[0] - t_aph[0])) begin
            $display("ERROR: trial %0d data phase is %0d cycles, trial 0 is %0d -- the pinned",
                     trial, t_done[trial] - t_aph[trial], t_done[0] - t_aph[0]);
            $display("       bus latency did not apply to every transfer, so the deltas are");
            $display("       not comparable %t ns", $time);
            error = error + 1;
         end

      for (trial = 0; trial < 18; trial = trial + 1)
         if (t_done[trial] >= 0 && t_done[trial] <= t_aph[trial]) begin
            $display("ERROR: trial %0d has T_done(%0d) <= T_aph(%0d) -- a data phase cannot",
                     trial, t_done[trial], t_aph[trial]);
            $display("       complete in its own address-phase cycle: measurement broken %t ns", $time);
            error = error + 1;
         end

      if (measured !== 18) begin
         $display("ERROR: only %0d of 18 trials produced a measurement %t ns", measured, $time);
         error = error + 1;
      end
      else
         $display("PASS:  all 18 trials measured %t ns", $time);

      //=================================================================
      // END OF TEST
      //=================================================================
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

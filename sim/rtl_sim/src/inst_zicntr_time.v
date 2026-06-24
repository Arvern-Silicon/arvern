//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_time
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR TIME
//   Zicntr time/timeh CSR verification:
//   - time (0xC01) and timeh (0xC81) are non-zero (random mtime_init)
//   - time is strictly increasing between two reads
//   - 64-bit coherence guard: double-read of timeh brackets time read
//   - time != cycle (distinct values due to random mtime_init offset)
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      // Set mtime_init to a large random 64-bit value so mtime starts clearly
      // different from cycle (which starts near 0).
      tb_arvern.mtime_init = {$random, $random};
      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;


      //=================================================================
      // PHASE 1: time and timeh are non-zero
      // mtime_init set to a random 64-bit value, so {time_hi, time_lo}
      // must be non-zero.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: TIME/TIMEH ARE NON-ZERO (random mtime_init)   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : check_phase1_nonzero
         reg [31:0] time_lo;
         reg [31:0] time_hi;
         reg [63:0] time_full;
         time_lo   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         time_hi   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
         time_full = {time_hi, time_lo};

         $display("time  (0xC01): 0x%h  %t ns", time_lo, $time);
         $display("timeh (0xC81): 0x%h  %t ns", time_hi, $time);
         $display("mtime_init was set to a random 64-bit value before reset");

         if (time_full !== 64'h0) begin
            $display("PASS:  {time_hi, time_lo} = 0x%h_%h is non-zero (mtime_init active) %t ns",
                     time_hi, time_lo, $time);
         end else begin
            $display("ERROR: {time_hi, time_lo} is zero -- mtime_init may not be working %t ns", $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 2: time is strictly increasing
      // Compare second time read against first; must be strictly greater.
      // Several instructions elapsed between phase 1 and phase 2, so
      // time must have advanced.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 2: TIME IS STRICTLY INCREASING                   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      begin : check_phase2_increasing
         reg [31:0] time1_lo;
         reg [31:0] time2_lo;
         reg [31:0] delta;
         time1_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         time2_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         delta    = time2_lo - time1_lo;

         $display("time read 1: 0x%h  %t ns", time1_lo, $time);
         $display("time read 2: 0x%h  %t ns", time2_lo, $time);
         $display("delta      : %0d   %t ns", delta,    $time);

         if (delta > 32'd0 && delta < 32'd10000) begin
            $display("PASS:  time advanced by %0d cycles between reads (strictly increasing) %t ns",
                     delta, $time);
         end else if (delta == 32'd0) begin
            $display("ERROR: time did not advance between reads -- delta=0 %t ns", $time);
            error = error + 1;
         end else begin
            $display("ERROR: time delta=%0d is unexpectedly large (possible wrap or bug) %t ns",
                     delta, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 3: 64-bit coherence guard
      // Read timeh, time, timeh again.
      // Second timeh must equal first, or be exactly first+1 (overflow
      // of time_lo during the read is the only valid case for hi+1).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 3: 64-BIT COHERENCE GUARD                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      begin : check_phase3_coherence
         reg [31:0] coh_hi1;
         reg [31:0] coh_lo;
         reg [31:0] coh_hi2;
         coh_hi1 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         coh_lo  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
         coh_hi2 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];

         $display("timeh before time read (hi1): 0x%h  %t ns", coh_hi1, $time);
         $display("time  between reads    (lo) : 0x%h  %t ns", coh_lo,  $time);
         $display("timeh after  time read (hi2): 0x%h  %t ns", coh_hi2, $time);

         if (coh_hi2 === coh_hi1) begin
            $display("PASS:  hi2 == hi1 (0x%h) — no carry during read %t ns", coh_hi1, $time);
         end else if (coh_hi2 === (coh_hi1 + 32'd1)) begin
            $display("PASS:  hi2 == hi1+1 (0x%h->0x%h) — carry during read is valid %t ns",
                     coh_hi1, coh_hi2, $time);
         end else begin
            $display("ERROR: hi2=0x%h is not hi1=0x%h or hi1+1=0x%h -- coherence violation %t ns",
                     coh_hi2, coh_hi1, coh_hi1+1, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 4: time != cycle
      // Due to random mtime_init, time starts from a large random value
      // while cycle starts from 0.  They must differ.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 4: TIME != CYCLE (distinct counters)             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      wait(probes_cpu.x31==32'hdeadbeef); // use wait() in case already past
      random_irq_enable = 0;              // disable random IRQs before final checks
      repeat(3) @(posedge free_clk);

      begin : check_phase4_distinct
         reg [31:0] time_lo;
         reg [31:0] cycle_lo;
         time_lo  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         cycle_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];

         $display("time  (0xC01): 0x%h  %t ns", time_lo,  $time);
         $display("cycle (0xC00): 0x%h  %t ns", cycle_lo, $time);

         if (time_lo !== cycle_lo) begin
            $display("PASS:  time (0x%h) != cycle (0x%h) -- distinct counters confirmed %t ns",
                     time_lo, cycle_lo, $time);
         end else begin
            $display("ERROR: time (0x%h) == cycle (0x%h) -- counters should differ due to mtime_init %t ns",
                     time_lo, cycle_lo, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

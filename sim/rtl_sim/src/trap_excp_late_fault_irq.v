//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_late_fault_irq
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Late load fault (load-use hazard) racing an M-mode IRQ
//   A level machine-timer interrupt is asserted kk cycles after each of 40
//   per-iteration sync markers, sweeping it across a back-to-back
//   `lw a0,0(a1)` / `lw a2,0(a0)` pair whose second load is misaligned and
//   whose base register comes straight from the first load. Expected per
//   iteration, whatever the IRQ ordering (Priv 3.1.11):
//     - exactly ONE synchronous exception (mcause=4, mtval=0x80000101,
//       mepc=&crit_lw) -- the interrupt may precede or follow it, never
//       replace it
//     - a2 keeps its sentinel (the faulting load never writes rd)
//     - a0 holds 0x80000101 (the first load completed)
//   Per-iteration before/at/after landing is displayed as a diagnostic.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] taken_before, before_before, at_before, after_before;
reg [31:0] lost_before, rd_before, a0_before;
integer    hit_before, hit_at, hit_after;
integer    to;

localparam [31:0] ITERATIONS      = 32'd40;
localparam [31:0] SENTINEL        = 32'hDEAD0000;
localparam [31:0] MISALIGNED_ADDR = 32'h80000101;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;   // 40 exceptions + 40 interrupts are the point
      hit_before = 0;
      hit_at     = 0;
      hit_after  = 0;

      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|  LATE FAULT vs IRQ: load-use-hazard misaligned lw swept by a timer IRQ  |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // SWEEP: one held timer IRQ per iteration, at offset kk
      //=================================================================
      for (kk = 0; kk < ITERATIONS; kk = kk + 1) begin
         wait (probes_cpu.x31 == (32'h51000000 + kk));
         repeat (kk) @(posedge free_clk);

         taken_before  = probes_cpu.x19;
         before_before = probes_cpu.x28;
         at_before     = probes_cpu.x29;
         after_before  = probes_cpu.x30;
         lost_before   = probes_cpu.x14;
         rd_before     = probes_cpu.x15;
         a0_before     = probes_cpu.x09;

         @(negedge free_clk);
         irq_m_timer = 1'b1;

         // Hold the line until the M handler has counted the interrupt
         to = 0;
         while ((probes_cpu.x19 === taken_before) && (to < 2000)) begin
            @(posedge free_clk);
            to = to + 1;
         end
         @(negedge free_clk);
         irq_m_timer = 1'b0;
         if (probes_cpu.x19 === taken_before) begin
            $display("ERROR: offset %0d: IRQ never taken (hart hung?) %t ns", kk, $time);
            error = error + 1;
         end

         // Firmware verdict for this iteration
         to = 0;
         while ((probes_cpu.x31 !== (32'h52000000 + kk)) && (to < 2000)) begin
            @(posedge free_clk);
            to = to + 1;
         end
         if (probes_cpu.x31 !== (32'h52000000 + kk)) begin
            $display("ERROR: offset %0d: end-of-iteration marker never reached %t ns", kk, $time);
            error = error + 1;
         end

         if      (probes_cpu.x28 !== before_before) hit_before = hit_before + 1;
         else if (probes_cpu.x29 !== at_before)     hit_at     = hit_at     + 1;
         else if (probes_cpu.x30 !== after_before)  hit_after  = hit_after  + 1;

         if (probes_cpu.x14 !== lost_before) begin
            $display("ERROR: offset %0d: synchronous exception count %0d (expected 1) -- fault %s, IRQ landed %s %t ns",
                     kk, probes_cpu.x21, (probes_cpu.x21 == 0) ? "LOST" : "DOUBLED",
                     (probes_cpu.x28 !== before_before) ? "before crit_lw" :
                     (probes_cpu.x29 !== at_before)     ? "AT crit_lw"     : "after crit_lw", $time);
            error = error + 1;
         end else if (probes_cpu.x15 !== rd_before) begin
            $display("ERROR: offset %0d: faulting lw wrote rd (a2=%h, expected sentinel %h) %t ns",
                     kk, probes_cpu.x12, SENTINEL, $time);
            error = error + 1;
         end else if (probes_cpu.x09 !== a0_before) begin
            $display("ERROR: offset %0d: first lw did not deliver (a0=%h, expected %h) %t ns",
                     kk, probes_cpu.x10, MISALIGNED_ADDR, $time);
            error = error + 1;
         end else begin
            $display("offset %2d: exception reported once, a2 intact, IRQ landed %s %t ns", kk,
                     (probes_cpu.x28 !== before_before) ? "before crit_lw" :
                     (probes_cpu.x29 !== at_before)     ? "AT crit_lw"     : "after crit_lw", $time);
         end
      end

      //=================================================================
      // FINAL CHECKS
      //=================================================================
      wait (probes_cpu.x31 === 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);

      $display("");
      $display("Sweep coverage: %0d landed before crit_lw, %0d at crit_lw, %0d after crit_lw",
               hit_before, hit_at, hit_after);
      if (hit_before == 0 || hit_after == 0) begin
         $display("ERROR: sweep did not straddle the critical pair -- window never exercised %t ns", $time);
         error = error + 1;
      end

      $display("");
      $display("--- iteration counter s2 (expect 40) ---");
      check_cpu_reg(18, ITERATIONS);
      $display("--- total IRQs taken s3 (expect 40) ---");
      check_cpu_reg(19, ITERATIONS);
      $display("--- total synchronous exceptions s4 (expect 40) ---");
      check_cpu_reg(20, ITERATIONS);
      $display("--- exceptions with mcause != 4 s9 (expect 0) ---");
      check_cpu_reg(25, 32'h00000000);
      $display("--- exceptions with mepc != &crit_lw s11 (expect 0) ---");
      check_cpu_reg(27, 32'h00000000);
      $display("--- last mtval s8 (expect 0x80000101) ---");
      check_cpu_reg(24, MISALIGNED_ADDR);
      $display("--- after-pair counter a3 (expect 40) ---");
      check_cpu_reg(13, ITERATIONS);
      $display("--- iterations with exception count != 1 a4 (expect 0) ---");
      check_cpu_reg(14, 32'h00000000);
      $display("--- iterations where the faulting lw wrote rd a5 (expect 0) ---");
      check_cpu_reg(15, 32'h00000000);
      $display("--- iterations where the first lw did not deliver s1 (expect 0) ---");
      check_cpu_reg(9,  32'h00000000);

      $display("");
      $display("--- lockup_o must be LOW ---");
      if (lockup !== 1'b0) begin
         $display("ERROR: lockup_o asserted %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o low %t ns", $time);
      end

      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_m_dbltrp_mdt_irq_race
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Smdbltrp -- M-mode IRQ racing an explicit MDT set
//   A level machine-timer interrupt is asserted kk cycles after each of 32
//   per-iteration sync markers, sweeping it across the `csrs mstatush, MDT`
//   that must clear mstatus.MIE atomically (Priv 3.1.6.2). Expected:
//     - the RNMI handler is never entered (no bogus double-trap divert)
//     - no interrupt is taken with mepc inside the MIE=0 window
//     - mstatus.MIE reads 0 after every csrs
//     - exactly 32 interrupts are taken, one per iteration
//   Per-iteration before/after-csrs landing is displayed as a diagnostic.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] taken_before, rnmi_before, bug_before, early_before, late_before;
integer    hit_before, hit_after;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;   // interrupt entries look like exceptions to the monitor
      hit_before = 0;
      hit_after  = 0;

      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|  Smdbltrp: M IRQ swept across an explicit MDT set (MIE must clear)  |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // SWEEP: one held timer IRQ per iteration, at offset kk
      //=================================================================
      for (kk = 0; kk < 32; kk = kk + 1) begin
         wait (probes_cpu.x31 == (32'h51000000 + kk));
         repeat (kk) @(posedge free_clk);

         taken_before = probes_cpu.x21;
         rnmi_before  = probes_cpu.x19;
         bug_before   = probes_cpu.x20;
         early_before = probes_cpu.x29;
         late_before  = probes_cpu.x30;

         @(negedge free_clk);
         irq_m_timer = 1'b1;

         // Hold the line until the M handler has counted the interrupt
         wait (probes_cpu.x21 !== taken_before);
         @(negedge free_clk);
         irq_m_timer = 1'b0;
         repeat (4) @(posedge free_clk);

         if (probes_cpu.x19 !== rnmi_before) begin
            $display("ERROR: offset %0d: RNMI handler entered (bogus double trap, mncause=0x%h) %t ns",
                     kk, probes_cpu.x28, $time);
            error = error + 1;
         end else if (probes_cpu.x20 !== bug_before) begin
            $display("ERROR: offset %0d: IRQ taken with MIE=0 (mepc inside csrs..reenable window) %t ns",
                     kk, $time);
            error = error + 1;
         end else if (probes_cpu.x29 !== early_before) begin
            hit_before = hit_before + 1;
            $display("offset %2d: IRQ taken before the csrs retired (legal) %t ns", kk, $time);
         end else if (probes_cpu.x30 !== late_before) begin
            hit_after = hit_after + 1;
            $display("offset %2d: IRQ taken after the MIE re-enable (legal) %t ns", kk, $time);
         end else begin
            $display("ERROR: offset %0d: IRQ counted but not classified %t ns", kk, $time);
            error = error + 1;
         end
      end

      //=================================================================
      // FINAL CHECKS
      //=================================================================
      wait (probes_cpu.x31 === 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);

      $display("");
      $display("Sweep coverage: %0d landed before the csrs, %0d after the re-enable", hit_before, hit_after);
      if (hit_before == 0 || hit_after == 0) begin
         $display("ERROR: sweep did not straddle the csrs mstatush -- window never exercised %t ns", $time);
         error = error + 1;
      end

      $display("");
      $display("--- iteration counter s2 (expect 32) ---");
      check_cpu_reg(18, 32'h00000020);
      $display("--- RNMI handler entries s3 (expect 0) ---");
      check_cpu_reg(19, 32'h00000000);
      $display("--- IRQs taken inside the MIE=0 window s4 (expect 0) ---");
      check_cpu_reg(20, 32'h00000000);
      $display("--- total IRQs taken s5 (expect 32) ---");
      check_cpu_reg(21, 32'h00000020);
      $display("--- OR of mstatus.MIE after csrs mstatush s6 (expect 0) ---");
      check_cpu_reg(22, 32'h00000000);
      $display("--- last mcause s7 (expect 0x80000007) ---");
      check_cpu_reg(23, 32'h80000007);
      $display("--- unexpected exceptions s9 (expect 0) ---");
      check_cpu_reg(25, 32'h00000000);

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

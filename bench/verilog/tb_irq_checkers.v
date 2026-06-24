//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    tb_irq_checkers
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : tb_irq_checkers.v
// Module Description : IRQ-related checker tasks used by the testbench.
//----------------------------------------------------------------------------

integer irq_trap_log_count;
initial
  begin
    irq_trap_log_count = 0;
    forever begin
      @(posedge free_clk);
      if (dut.arv_csr_top_inst.arv_csr_traps_inst.trap_taken &
          dut.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq &
          (irq_trap_log_count < 30)) begin
        irq_trap_log_count = irq_trap_log_count + 1;
        $display("[IRQ-TRAP #%0d @%0t] MEPC=0x%08x  ex_alu_ready=%b  kill_muldiv=%b  is_killable=%b  suppress=%b",
                 irq_trap_log_count, $time,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.mepc_save_latched,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.ex_alu_ready_i,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.trap_kill_muldiv_o,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.ex_alu_is_killable_i,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_suppress);
      end
    end
  end

// Kill-restarted logger: fires when muldiv_kill_restarted fires (wait_done about to set).
integer kill_restarted_log_count;
initial
  begin
    kill_restarted_log_count = 0;
    forever begin
      @(posedge free_clk);
      if (dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_restarted &
          (kill_restarted_log_count < 30)) begin
        kill_restarted_log_count = kill_restarted_log_count + 1;
        $display("[KILL-RESTARTED #%0d @%0t] suppress=%b  wait_done=%b  is_killable=%b  muldiv_mode_en=%b  ex_pc=0x%08x",
                 kill_restarted_log_count, $time,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_suppress,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_wait_done,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.ex_alu_is_killable_i,
                 dut.arv_alu_inst.muldiv_mode_en,
                 dut.ex_pc);
      end
    end
  end

// Suppress clear logger: fires when muldiv_kill_suppress is about to clear.
integer suppress_clr_log_count;
initial
  begin
    suppress_clr_log_count = 0;
    forever begin
      @(posedge free_clk);
      if (dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_suppress &
          dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_completed &
          (suppress_clr_log_count < 30)) begin
        suppress_clr_log_count = suppress_clr_log_count + 1;
        $display("[SUPPRESS-CLR #%0d @%0t] wait_done=%b  is_killable=%b  trap_pending=%b  trap_taken=%b  kill_muldiv=%b  muldiv_mode_en=%b  ex_alu_ready=%b",
                 suppress_clr_log_count, $time,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_wait_done,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.ex_alu_is_killable_i,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.trap_pending_o,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.trap_taken,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.trap_kill_muldiv_o,
                 dut.arv_alu_inst.muldiv_mode_en,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.ex_alu_ready_i);
      end
    end
  end

// MRET logger: shows every MRET and where it returns.
integer mret_log_count;
initial
  begin
    mret_log_count = 0;
    forever begin
      @(posedge free_clk);
      if (dut.arv_csr_top_inst.arv_csr_traps_inst.mret_taken &
          (mret_log_count < 50)) begin
        mret_log_count = mret_log_count + 1;
        $display("[MRET #%0d @%0t] returning_to=0x%08x  suppress=%b  wait_done=%b  ex_pc=0x%08x",
                 mret_log_count, $time,
                 {dut.arv_csr_top_inst.arv_csr_traps_inst.mepc_mepc, 1'b0},
                 dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_suppress,
                 dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_wait_done,
                 dut.ex_pc);
      end
    end
  end

// ================================================================
// irq_kill_checker_en: set to 0 by test stimulus to suppress the
// livelock and re-execution checkers during phases where IRQ kill
// is intentionally disabled (e.g. no-kill latency measurement phases).
// Disabling resets accumulated checker state so re-enable is clean.
// ================================================================
integer irq_kill_checker_en;

// ================================================================
// Livelock watchdog: detect when MRET repeatedly returns to the same PC.
// The livelock pattern is: instruction at PC X is killed by IRQ → IRQ handler
// runs → MRET returns to PC X → killed again → repeat indefinitely.
// Trigger: the same MEPC value seen across 10 consecutive MRETs.
// Normal code won't trigger this: WFI returns to PC+4, exception handlers
// return to varying PCs, and healthy IRQs on a loop eventually let it advance.
// ================================================================
reg  [31:0] livelock_last_mepc;
integer     livelock_mret_repeat_count;
initial
  begin
    livelock_last_mepc        = 32'hffffffff;
    livelock_mret_repeat_count = 0;
    irq_kill_checker_en       = 1;
    forever begin
      @(posedge free_clk);
      if (!irq_kill_checker_en) begin
        // Reset state while disabled so re-enable starts clean
        livelock_mret_repeat_count = 0;
        livelock_last_mepc         = 32'hffffffff;
      end
      else if (dut.arv_csr_top_inst.arv_csr_traps_inst.mret_taken) begin
        if ({dut.arv_csr_top_inst.arv_csr_traps_inst.mepc_mepc, 1'b0} === livelock_last_mepc)
          livelock_mret_repeat_count = livelock_mret_repeat_count + 1;
        else begin
          livelock_mret_repeat_count = 1;
          livelock_last_mepc = {dut.arv_csr_top_inst.arv_csr_traps_inst.mepc_mepc, 1'b0};
        end
        if (livelock_mret_repeat_count >= 10) begin
          $display("");
          $display(" ===============================================");
          $display("|               SIMULATION FAILED               |");
          $display("|    [Livelock] MRET returning to same PC        |");
          $display("|    MEPC=0x%08x repeated %0d times   |",
                   livelock_last_mepc, livelock_mret_repeat_count);
          $display("|  trap_is_irq:          %b", dut.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq);
          $display("|  ex_alu_is_killable:   %b", dut.arv_csr_top_inst.arv_csr_traps_inst.ex_alu_is_killable_i);
          $display("|  muldiv_kill_suppress: %b", dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_suppress);
          $display("|  muldiv_kill_wait_done:%b", dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_wait_done);
          $display("|  ex_uop_is_killable:   %b", dut.arv_csr_top_inst.arv_csr_traps_inst.ex_uop_is_killable_i);
          $display("|  uop_kill_suppress:    %b", dut.arv_csr_top_inst.arv_csr_traps_inst.uop_kill_suppress);
          $display("|  uop_kill_wait_done:   %b", dut.arv_csr_top_inst.arv_csr_traps_inst.uop_kill_wait_done);
          $display(" ===============================================");
          $display("");
          error = error + 1;
          tb_extra_report;
          $finish;
        end
      end
    end
  end

// ================================================================
// Checker: re-execution-without-kill
// Rule: if an IRQ trap fires while a muldiv/uop is killable (and not
// already in the suppress window), and MRET returns to the same PC as
// the previous MRET, a kill must have occurred. This catches the bug
// where a killed muldiv re-executes without a kill on the next IRQ.
//
// Exclusions:
//   - Non-IRQ traps (synchronous exception retry is intentional)
//   - Traps taken while kill-suppress is already active (the muldiv is
//     completing its restart; another kill is intentionally suppressed)
//   - Traps where no killable operation was in flight (no kill expected)
// ================================================================
reg  [31:0] reexec_prev_mret_pc;
integer     reexec_kill_seen;
integer     reexec_was_irq;
integer     reexec_was_killable;
integer     reexec_was_suppress;
initial
  begin
    reexec_prev_mret_pc  = 32'hFFFFFFFF;
    reexec_kill_seen     = 0;
    reexec_was_irq       = 0;
    reexec_was_killable  = 0;
    reexec_was_suppress  = 0;
    forever begin
      @(posedge free_clk);
      if (!irq_kill_checker_en) begin
        // Reset state while disabled so re-enable starts clean
        reexec_prev_mret_pc = 32'hFFFFFFFF;
        reexec_kill_seen    = 0;
      end
      if (dut.arv_csr_top_inst.arv_csr_traps_inst.trap_taken) begin
        reexec_kill_seen    = 0;
        reexec_was_irq      = dut.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq;
        reexec_was_killable = dut.arv_csr_top_inst.arv_csr_traps_inst.ex_alu_is_killable_i |
                              dut.arv_csr_top_inst.arv_csr_traps_inst.ex_uop_is_killable_i;
        reexec_was_suppress = dut.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_suppress  |
                              dut.arv_csr_top_inst.arv_csr_traps_inst.uop_kill_suppress;
      end
      if (dut.arv_csr_top_inst.arv_csr_traps_inst.trap_kill_muldiv_o |
          dut.arv_csr_top_inst.arv_csr_traps_inst.trap_kill_uop_o)
        reexec_kill_seen = 1;
      if (dut.arv_csr_top_inst.arv_csr_traps_inst.mret_taken) begin
        if (irq_kill_checker_en &
            reexec_was_irq      &
            reexec_was_killable &
            ~reexec_was_suppress &
            ({dut.arv_csr_top_inst.arv_csr_traps_inst.mepc_mepc, 1'b0} == reexec_prev_mret_pc) &
            ~reexec_kill_seen) begin
          $display(" ===============================================");
          $display("|               SIMULATION FAILED               |");
          $display("|  [Re-exec] MRET to 0x%08x without kill      |",
                   reexec_prev_mret_pc);
          $display("|  Killable op trapped by IRQ, no kill in trap  |");
          $display(" ===============================================");
          error         = error + 1;
          stimulus_done = 1;
        end
        reexec_prev_mret_pc = {dut.arv_csr_top_inst.arv_csr_traps_inst.mepc_mepc, 1'b0};
      end
    end
  end

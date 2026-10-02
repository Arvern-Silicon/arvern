#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    waivers.tcl
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : waivers.tcl
# Module Description : Design-specific VC Static lint waivers for arvern.
#----------------------------------------------------------------------------
# Sourced by vc_lint.tcl after elaboration and before check_hdl, so waived
# violations are classified as they are found.
#
# Waived items still appear in results/report.lint_waived.txt
#----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# arvern uses an explicit `*_unused` sink-wire convention to document
# signals that are intentionally not consumed in a given configuration (e.g.
# muldiv state when M_EXTENSION=0, HPM regs when ZIHPM_NR=0). Those wires are
# unloaded BY DESIGN -- that is the whole point of the convention -- so the
# resulting unloaded-net violations are noise rather than findings.
#
# Scope note: this waives by signal name only, so it applies to every tag that
# can fire on such a net (CONN_NET_UNLOADED, CONN_INTERNAL_NET_UNLOADED, ...).
# It does NOT waive anything whose name lacks the suffix.
# ---------------------------------------------------------------------------
waive_hdl -add unused_sink_wires \
          -comment "Deliberate *_unused sink wires: unloaded by design (arvern convention)" \
          -filter {Signal=~*_unused*}


# ---------------------------------------------------------------------------
# arv_dff / arv_dff_sinit with a non-zero RST_VAL: bits that reset to 1 infer an
# async SET and bits that reset to 0 an async RESET, both driven from the same
# hresetn_i. That is exactly what the rule describes, and it is the normal and
# correct implementation of a flop with a non-zero reset value
# (u_shadow_sel RST_VAL=5'd13, u_sbaccess RST_VAL=3'd2).
# ---------------------------------------------------------------------------
waive_hdl -add dff_nonzero_rstval_setreset \
          -comment "arv_dff with non-zero RST_VAL: mixed set/reset from one reset is by design" \
          -tag CODING_TREE_SETRST_ORIG \
          -filter {Module=~arv_dff*}

# ---------------------------------------------------------------------------
# Deliberate post-reset one-shot flops: en_i(1'b1) with a tied d_i, so the flop
# loads its constant on the first clock and holds it. The tied input IS the
# mechanism. Four such flops exist:
#   arv_fetch.v:269      u_init_pc         RST_VAL 1, d_i 0  -- one-cycle init pulse
#   arv_debug_dm.v:262   u_hart_alive      RST_VAL 0, d_i 1  -- hart left reset
#   arv_csr_cntr.v:214                     d_i 1
#   arv_csr_debug.v:151  reset_halt_arm_q  d_i 0
#
# Waived by tag rather than per-instance: compression reports only one at a
# time, so an instance-scoped waiver just promotes the next one into view.
# ---------------------------------------------------------------------------
# Deliberately NOT config-gated, and it will report stale in some configs.
# Two independent populations feed this tag and no parameter predicts both:
#   - the four one-shot flops above, which stop reporting under ASYNC_RST_EN=0
#     (the reset folds into the data path, so the input is no longer constant)
#   - flops tied off by parameter folding, e.g. arv_decode u_ex_alu_mode[4:2]
#     with B_EXTENSION=0, which report in corner-LO even with a sync reset
# Gating on ASYNC_RST_EN silences the first and un-waives the second (3 errors
# in corner-LO). One stale report in ofat:ASYNC_RST_EN=0 is the cheaper trade.
waive_hdl -add tied_input_oneshot_ff \
          -comment "Post-reset one-shot flops: tied d_i with en_i=1 is the intended mechanism" \
          -tag SYN_FF_CONST_INP


# ---------------------------------------------------------------------------
# arv_dff_sinit carries BOTH a reset (rst_n_i) and a synchronous init (sinit_i),
# and for the Debug Module both are necessarily live signals:
#   rst_n_i = dbgresetn_i          -- physical debug-domain reset
#   sinit_i = dm_sinit = ~dmactive -- the debugger's software reset
# The RISC-V Debug spec requires the debugger to be able to clear DM-side state
# via dmactive without a physical reset, so neither input can be tied off.
# Priority is explicit in the RTL (rst_n_i, then sinit_i, then en_i), so the
# race the rule guards against cannot occur here.
#
# CONDITIONAL: the rule only fires at ASYNC_RST_EN=0. With an async reset the
# tool sees one async control plus ordinary clock-sampled logic; with a sync
# reset both collapse into set/reset terms on the same flop. Registering the
# waiver only in sync builds keeps `waive_hdl -not_applied` meaningful as a
# stale-waiver signal in async builds.
#
# Also gated on DEBUG_EN: every arv_dff_sinit instance lives in the debug
# modules, so with the debug subsystem absent there is nothing to match and the
# waiver would report as stale.
# ---------------------------------------------------------------------------
if {[info exists RTL_PARAM_ASYNC_RST_EN] && $RTL_PARAM_ASYNC_RST_EN == 0
    && [info exists RTL_PARAM_DEBUG_EN] && $RTL_PARAM_DEBUG_EN != 0} {
    waive_hdl -add dff_sinit_dual_force \
              -comment "arv_dff_sinit: reset and sync-init are both live by Debug-spec requirement" \
              -tag SEQ_RST_CONST_CONN \
              -filter {Module=~arv_dff_sinit*}
    puts "\[vc_lint\] sync-reset build: SEQ_RST_CONST_CONN waiver registered for arv_dff_sinit"
}

# ---------------------------------------------------------------------------
# arv_dff_sinit has two synchronous reset sources in a sync-reset build:
# rst_n_i and sinit_i both load RST_VAL. That is the primitive's whole purpose
# -- the Debug spec needs a flop that can be forced back to its reset value
# without asserting system reset. The rule stays enabled so a SECOND such flop
# appearing anywhere else is still reported.
#
# Triple-gated. LANGUAGE_CHECK, so it needs $DO_LANG. It only fires when the
# sync generate branch is elaborated (ASYNC_RST_EN=0) and only when the module
# is instantiated at all (DEBUG_EN!=0) -- corner-LO(all-min) sets both to 0,
# and an ungated waiver would report stale there.
# ---------------------------------------------------------------------------
if {$DO_LANG eq "1"
    && [info exists RTL_PARAM_ASYNC_RST_EN] && $RTL_PARAM_ASYNC_RST_EN == 0
    && [info exists RTL_PARAM_DEBUG_EN] && $RTL_PARAM_DEBUG_EN != 0} {
    waive_hdl -add dff_sinit_dual_sync_reset \
              -comment "arv_dff_sinit: rst_n_i and sinit_i both load RST_VAL by design" \
              -tag CODING_RST_MULTIPLE_SYNC_RST \
              -filter {Module=~arv_dff_sinit*}
    puts "\[vc_lint\] sync-reset build: CODING_RST_MULTIPLE_SYNC_RST waiver registered for arv_dff_sinit"
}

# ---------------------------------------------------------------------------
# 64x64 product truncated to 64 bits (arv_alu_muldiv).
#
#   assign mpy_result_full = mpy_operand1 * mpy_operand2;   // both [63:0]
#
# RV32 MUL/MULH is built by sign/zero-extending the 32-bit operands to 64 and
# keeping the low 64 bits of the product; the upper half carries no information.
# Five rules report this single line, so they are waived together -- if the
# multiplier is ever restructured this waiver goes stale as a unit and shows up
# in `waive_hdl -not_applied`.
# ---------------------------------------------------------------------------
# CONDITIONAL: these rules live in the LANGUAGE_CHECK stage, so without -lang
# they never fire and the waiver would report as stale in every structural run.
if {[info exists DO_LANG] && $DO_LANG eq "1"} {
# Gated: arv_alu_muldiv is not elaborated at M_EXTENSION=0, so an ungated
# waiver reports stale in corner-LO.
if {![info exists RTL_PARAM_M_EXTENSION] || $RTL_PARAM_M_EXTENSION != 0} {
    waive_hdl -add mul_product_truncation \
              -comment "RV32 MUL/MULH: low 64 bits of the 64x64 product are the result by construction" \
              -tag {CODING_WIDTH_UNEQ_SIZE CODING_WIDTH_UNEQ_SIG_ASSIGN CODING_EXPR_PRECISION_LOSS
                    SIMSYN_STMT_OPERAND_SIZE CODING_OPERAND_WIDTH}
}

# ---------------------------------------------------------------------------
# Fixed-width arithmetic. These three rules fire on Verilog's own width rules
# rather than on defects, in three idioms, all verified against the RTL:
#
#   carry-drop      an N-bit +/- yields N+1 bits; assigning to N drops the carry
#                   deliberately -- counter increments (mcycle_lo + 1, carry to
#                   mcycleh), address arithmetic that wraps mod 2^32 per the
#                   RISC-V spec (JALR target), the isolate-lowest-set-bit idiom
#                   (prio & ~(prio - 1)), and counter decrements
#   shift-by-var    a 32-bit value shifted by a 5-bit amount is reported as
#                   Lhs=32 Rhs=5 -- the barrel shifter and the one-hot register
#                   decoders. Nothing is truncated; the rule measures the shift
#                   amount as the RHS
#   ternary arm     a mux whose other arm is an increment inherits 33 bits
#
# Complying would mean explicit truncation slices on every adder in the core,
# including the parallel branch-target adders on the documented critical path,
# generating identical hardware. Waived rather than disabled so the findings
# stay inspectable in report.lint_waived.txt.
# ---------------------------------------------------------------------------
waive_hdl -add fixed_width_arithmetic \
          -comment "Verilog fixed-width arithmetic: carry-drop, shift-by-variable and ternary-arm width" \
          -tag {CONN_STMT_UNEQ_SIZE1 CODING_ASSIGN_UNEQUAL_LENGTH CODING_WIDTH_UNEQ_OPRND4}
}

# ---------------------------------------------------------------------------
# LANGUAGE_CHECK-only waivers: gated on DO_LANG for the same reason as the width
# waivers above -- these rules do not run without -lang, so an ungated waiver
# reports as stale in every structural run and erodes the stale signal.
# ---------------------------------------------------------------------------
if {[info exists DO_LANG] && $DO_LANG eq "1"} {

# ---------------------------------------------------------------------------
# arv_alu count_leading_zeros / count_trailing_zeros: the rule wants the
# function-name assignment to be the LAST statement in the function body. Both
# functions assign it unconditionally BEFORE the search loop
# (count_leading_zeros = 6'd32) and refine it inside, so the return value is
# always defined; the last statement is the loop's own bookkeeping
# (found = 1'b1 / cnt = cnt + 1). Satisfying the rule would mean restructuring
# two working search loops to suit statement ordering.
# ---------------------------------------------------------------------------
waive_hdl -add alu_count_fn_stmt_order \
          -comment "arv_alu CLZ/CTZ: return value assigned unconditionally before the loop, not last" \
          -tag CODING_FUNC_RET_STMT


}

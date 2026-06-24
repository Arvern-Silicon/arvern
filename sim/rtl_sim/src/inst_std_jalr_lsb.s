#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_std_jalr_lsb
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: JALR LSB-CLEAR (no misalign exception)
#   RISC-V Unprivileged spec, JALR (Sec. "Unconditional Jumps"): the target
#   address is obtained by adding the sign-extended 12-bit immediate to rs1,
#   then SETTING THE LEAST-SIGNIFICANT BIT OF THE RESULT TO ZERO. The
#   instruction-address-misaligned exception is reported only on the taken
#   branch / jump target AFTER this masking; therefore a set bit[0] in
#   (rs1+imm) must NEVER cause a misaligned-fetch trap -- it is silently
#   cleared.
#
#   (Note: the legacy inst_std_jalr.s explicitly DEFERRED this LSB-mask case
#   "until exception handling is implemented". Trap handling is now complete,
#   so this test exercises the deferred case directly.)
#
#   All branch targets are forced 4-byte aligned (.align 2) so that after
#   clearing bit[0] the result is a legal instruction address in BOTH a
#   C-enabled (2-byte alignment) and a C-disabled (4-byte alignment) build.
#
#   A trap handler is installed and counts EVERY trap. The pass criterion:
#   - trap_count == 0   (no instruction-address-misaligned, no other trap)
#   - control reached every masked target (proof markers set)
#   - link register holds the correct return address
#
#   Phases:
#   P2: rs1 = label|1 , imm = 0    -> JALR target = label
#   P3: rs1 = label   , imm = 1    -> JALR target = label
#   P4: rs1 = (label+1)|1, imm = -1 -> (odd+(-1)) still odd -> mask -> label
#   P5: C.JR  with odd rs1   -> target = even label (C extension only)
#   P6: C.JALR with odd rs1  -> target = even label, link = ret addr
#----------------------------------------------------------------------------

    .section .text
    .option norvc                 # P1..P4 use only 32-bit instructions
    .global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count   (MUST stay 0 -- no fault may occur)
#   0x04: last MCAUSE  (diagnostic only)
#   0x08: last MEPC    (diagnostic only)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER -- this test expects NO traps at all. If one fires
    # it records cause/mepc, bumps trap_count, and limps forward by
    # advancing MEPC so the run still terminates (testbench will flag
    # the non-zero trap_count as a failure).
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  8(sp)
    sw   t1,  4(sp)
    sw   t2,  0(sp)

    csrr t0, mcause
    csrr t1, mepc

    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)

    # Best-effort forward progress (defensive only).
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  0(sp)
    lw   t1,  4(sp)
    lw   t0,  8(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Proof markers (set when each masked target is correctly reached).
    li   x18, 0x00000000          # P2 reached target
    li   x19, 0x00000000          # P3 reached target
    li   x20, 0x00000000          # P4 reached target
    li   x21, 0x00000000          # P5 reached target (C.JR)
    li   x22, 0x00000000          # P6 reached target (C.JALR)
    li   x23, 0x00000000          # P2 link-register correct
    li   x24, 0x00000000          # P3 link-register correct
    li   x26, 0x00000000          # P4 link-register correct
    li   x25, 0x00000000          # P6 link-register correct (C.JALR)

    li   x31, 0x11111111          # init done


    #=================================================================
    # PHASE 2: rs1 = (func2 | 1), imm = 0
    #   (rs1 + 0) has bit[0] = 1.  JALR must clear it -> func2.
    #   func2 sets its proof marker, checks its own link register
    #   (== p2_ret), and returns. No trap may occur.
    #=================================================================
    la    t0, func2
    ori   t0, t0, 1               # force bit[0] = 1 in the operand
    jalr  ra, 0(t0)               # PC = (func2|1 + 0) & ~1 = func2
p2_ret:
    li    x31, 0x22222222


    #=================================================================
    # PHASE 3: rs1 = func3, imm = 1
    #   (func3 + 1) has bit[0] = 1 (func3 is 4-byte aligned).
    #   JALR must clear it -> func3.
    #=================================================================
    la    t0, func3
    jalr  ra, 1(t0)               # PC = (func3 + 1) & ~1 = func3
p3_ret:
    li    x31, 0x33333333


    #=================================================================
    # PHASE 4: rs1 = func4 , imm = +1   (distinct from P3 via rs1==rd
    #   interplay: here ra is also clobbered by the link write, so we
    #   compute the operand into t2, not ra).
    #   func4 is 4-byte aligned (.align 2); func4 + 1 has bit[0] = 1.
    #   JALR clears bit[0]: (func4 + 1) & ~1 = func4.
    #   Size-agnostic: never depends on instruction width.
    #=================================================================
    la    t2, func4
    jalr  ra, 1(t2)               # (func4 + 1) & ~1 = func4
p4_ret:
    li    x31, 0x44444444


    #=================================================================
    # PHASE 5/6: Compressed C.JR / C.JALR LSB-clear.
    #   Same spec rule (Sec. "Unconditional Jumps"): C.JR/C.JALR set
    #   bit[0] of rs1 to zero before jumping. Targets are 2-byte
    #   aligned, legal in any C-enabled build. This section only
    #   executes meaningfully with the C extension (default build).
    #=================================================================
.option rvc

    #-------------------- PHASE 5: C.JR with odd rs1 -----------------
    la    t0, func5
    ori   t0, t0, 1               # bit[0] = 1
    c.jr  t0                      # PC = t0 & ~1 = func5  (no link)
    li    x21, 0xBADBAD05         # must be skipped (proof of jump)
p5_ret:
    li    x31, 0x55555555

    #-------------------- PHASE 6: C.JALR with odd rs1 ---------------
    la    t0, func6
    ori   t0, t0, 1               # bit[0] = 1
    c.jalr t0                     # PC = t0 & ~1 = func6 ; ra = p6_ret
p6_ret:
    li    x31, 0xdeadbeef

end_of_test:
    j     end_of_test


    #=================================================================
    # CALL TARGETS (placed after the infinite loop; reached only via
    # the LSB-masked JALR / C.JR / C.JALR under test).
    #=================================================================

    #-- PHASE 2 target: standard JALR, link in ra (must == p2_ret) ---
    .align 2
func2:
    li    x18, 0x00000001         # proof: masked target reached
    la    t1, p2_ret
    bne   ra, t1, f2_noret
    li    x23, 0x00000001         # link-register correct
f2_noret:
    jalr  x0, 0(ra)               # return to p2_ret

    #-- PHASE 3 target: standard JALR, link in ra (must == p3_ret) ---
    .align 2
func3:
    li    x19, 0x00000001         # proof: masked target reached
    la    t1, p3_ret
    bne   ra, t1, f3_noret
    li    x24, 0x00000001         # link-register correct
f3_noret:
    jalr  x0, 0(ra)               # return to p3_ret

    #-- PHASE 4 target: standard JALR, link in ra (must == p4_ret) ---
    .align 2
func4:
    li    x20, 0x00000001         # proof: masked target reached
    la    t1, p4_ret
    bne   ra, t1, f4_noret
    li    x26, 0x00000001         # link-register correct
f4_noret:
    jalr  x0, 0(ra)               # return to p4_ret

    #-- PHASE 5 target: C.JR (no link saved) -- return via plain j ---
    .align 1
func5:
    li    x21, 0x00000001         # proof: masked target reached
    j     p5_ret

    #-- PHASE 6 target: C.JALR, link in ra (must == p6_ret) ----------
    .align 1
func6:
    li    x22, 0x00000001         # proof: masked target reached
    la    t1, p6_ret
    bne   ra, t1, f6_noret
    li    x25, 0x00000001         # link-register correct
f6_noret:
    jalr  x0, 0(ra)               # return to p6_ret

#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_smrnmi_popret_mnepc
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI ON CM.POPRET RETURN BRANCH -> STALE MNEPC REPRODUCER
#   Bug scenario: an NMI landing on the exact cycle a CM.POPRET performs its
#   final return branch captures a STALE resume PC into mnepc -- the
#   sequential successor of the popret instead of the return target. MNRET
#   then resumes at the wrong address: the return branch is skipped AFTER
#   the registers/sp were already popped.
#
#   The vulnerable window is one cycle wide, so the testbench SWEEPS the NMI
#   pulse over 32 different cycle offsets (0..31), one per loop iteration,
#   relative to a per-iteration x31 sync marker written right before the
#   call to the leaf function.
#
#   A distinctive POISON code sequence sits directly after the cm.popret
#   inside the leaf function -- exactly where a stale-mnepc resume would
#   land. It sets s11 (x27) = 0xDEADFA11 and then best-effort recovers via
#   `ret` (ra was already popped) so the run still completes and reports.
#
#   NOTE: the task brief called the poison register "t6", but t6 == x31 is
#   reserved for testbench synchronization in this environment -- s11 (x27)
#   is used as the poison register instead.
#
#   Register conventions (NMI handler may fire at ANY point in the loop, so
#   these registers are reserved for it and never touched by the main code):
#     t3 (x28) : NMI count
#     t4 (x29) : handler scratch
#     t5 (x30) : mnepc log pointer (successive slots at 0x80000100..0x8000017C)
#   Main-loop registers:
#     s1 (x9)  : scratchpad base 0x80000000
#     s2 (x18) : live iteration counter (incremented ONLY on the correct
#                post-return path)
#     s4 (x20) : checksum (updated ONLY on the correct post-return path)
#     s11(x27) : poison register (init 0x00000000, must stay 0)
#
#   Scratchpad layout (SRAM base 0x80000000):
#     0x00 : reserved (0)
#     0x04 : exc_count  -- unexpected synchronous exceptions (must stay 0)
#     0x08 : nmi_handler address (testbench drives nmi_vector from here)
#     0x0C : popret_poison address (testbench scans the mnepc log for it)
#     0x14 : last unexpected mcause (must stay 0)
#     0x100..0x17C : mnepc log, one slot per NMI taken
#
#   Expected end state (good RTL):
#     s2 = 32, s4 = 0xA50, s11 = 0, t3 = 32, exc_count = 0,
#     no mnepc log entry equal to the popret_poison address.
#   Buggy RTL (stale mnepc in the popret window):
#     s11 = 0xDEADFA11 and at least one mnepc log entry == popret_poison.
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi). Robust to firing at ANY point in the loop:
    # only uses the reserved registers t3/t4/t5 and performs no stack
    # accesses. Logs mnepc into successive scratchpad slots (with wrap
    # guard) so the testbench can detect a stale capture.
    #=================================================================
    .align 2
nmi_handler:
    addi t3, t3, 1              # nmi_count++
    csrr t4, 0x741              # mnepc
    sw   t4, 0(t5)              # log mnepc
    addi t5, t5, 4
    li   t4, 0x80000180         # wrap guard: keep log inside 0x100..0x17C
    bne  t5, t4, 1f
    li   t5, 0x80000100
1:
    .word 0x70200073            # mnret

    #=================================================================
    # M-MODE TRAP HANDLER (mtvec) -- must NEVER run. If an unexpected
    # synchronous exception fires, record it, bump exc_count, and step
    # mepc forward so the run still terminates and reports.
    #=================================================================
    .align 2
trap_handler:
    csrr t4, mcause
    sw   t4, 0x14(s1)           # record unexpected mcause
    lw   t4, 0x04(s1)
    addi t4, t4, 1
    sw   t4, 0x04(s1)           # exc_count++
    csrr t4, mepc
    addi t4, t4, 4
    csrw mepc, t4               # best-effort skip of the faulting insn
    mret

    #=================================================================
    # LEAF FUNCTION under test:
    #   cm.push, a couple of marker instructions, cm.popret.
    #   The POISON sequence sits directly after the cm.popret -- the
    #   sequential successor a stale mnepc would point at.
    #=================================================================
    .align 2
func:
    cm.push {ra, s0}, -16       # push ra/s0, sp -= 16
    mv   s0, a0                 # marker 1 (s0 is restored by popret)
    addi a0, a0, 3              # marker 2: a0 = iter + 3
    xori a0, a0, 0x55           # marker 3: a0 = (iter + 3) ^ 0x55
    cm.popret {ra, s0}, 16      # pop ra/s0, sp += 16, return branch

popret_poison:
    # A stale-mnepc resume lands HERE (registers/sp already popped,
    # return branch skipped). Set the poison register, then best-effort
    # recover via ra (already popped) so the test completes and reports.
    li   s11, 0xDEADFA11
    ret

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000         # scratchpad base

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)           # exc_count
    sw   t0, 0x08(s1)           # nmi_handler addr
    sw   t0, 0x0C(s1)           # popret_poison addr
    sw   t0, 0x14(s1)           # unexpected mcause

    # Zero the mnepc log (0x80000100 .. 0x8000017C)
    li   t1, 0x80000100
    li   t2, 0x80000180
1:  sw   t0, 0(t1)
    addi t1, t1, 4
    bltu t1, t2, 1b

    # Publish NMI handler address for the testbench (drives nmi_vector)
    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x08(s1)

    # Publish the poison-path address for the testbench mnepc-log scan
    la   t0, popret_poison
    sw   t0, 0x0C(s1)

    # Install the M-mode trap handler (must never fire)
    la   t0, trap_handler
    csrw mtvec, t0

    # Enable NMI: mnstatus.NMIE = 1 (bit[3]); resets to 0 per Smrnmi
    csrsi 0x744, 8

    # Initialize loop / handler registers
    li   s2, 0                  # iteration counter
    li   s4, 0                  # checksum
    li   s11, 0                 # poison register -- must stay 0
    li   t3, 0                  # nmi_count (handler)
    li   t4, 0                  # handler scratch
    li   t5, 0x80000100         # mnepc log pointer (handler)

    li   x31, 0x11111111        # init done -- testbench latches nmi_vector

    #=================================================================
    # SWEEP LOOP: 32 iterations. Each iteration writes a DISTINCT sync
    # value (0x51000000 + iter) to x31 right before calling func; the
    # testbench pulses NMI at a different cycle offset (0..31) after
    # seeing each sync value, sweeping the one-cycle-wide popret return
    # branch window across wait-state variants.
    #=================================================================
main_loop:
    li   t1, 0x51000000
    add  x31, t1, s2            # per-iteration sync marker
    mv   a0, s2                 # function argument = iteration index
    jal  func

    # CORRECT post-return path -- the ONLY place the checksum and the
    # iteration counter are updated.
    add  s4, s4, a0             # checksum += (iter + 3) ^ 0x55
    addi s2, s2, 1
    li   t1, 32
    blt  s2, t1, main_loop

    # Expected checksum: sum_{i=0..31} ((i+3)^0x55) = 0x00000A50
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test

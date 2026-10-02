#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_zcmt_jt_nmi_kill
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI DURING CM.JT JVT-LOAD PHASE -> ORPHAN DATA-PHASE / PHANTOM
#              FAULT / POST-MNRET RESTART CORRUPTION REPRODUCER
#   Bug scenario: an NMI arriving while a CM.JT (table jump) is in its
#   JVT-load phase can leave an orphan bus data-phase; if that orphan
#   errors it raises a phantom load-access-fault (mcause=5) during NMI
#   entry. Even without a bus error, the state perturbation can corrupt
#   the post-mnret restart of the killed CM.JT.
#
#   (A table jump is no longer killable: the NMI now waits for it to
#   complete. The sweep still checks the exact landing and the absence of any
#   phantom fault.)
#   The vulnerable window is narrow, so the testbench SWEEPS the NMI pulse
#   over 32 different cycle offsets (0..31), one per loop iteration,
#   relative to a per-iteration x31 sync marker written right before the
#   cm.jt dispatch.
#
#   A regular M-mode trap handler is installed to CATCH any UNEXPECTED
#   synchronous exception (e.g. phantom mcause=5): it records mcause/mepc,
#   sets the poison register, then redirects mepc to a recovery point so
#   the test still finishes and reports.
#
#   Register conventions (NMI handler may fire at ANY point in the loop,
#   so these registers are reserved for it and never touched by the main
#   code):
#     t3 (x28) : NMI count
#     t4 (x29) : handler scratch
#     t5 (x30) : mncause log pointer (slots at 0x80000100..0x8000017C)
#   Main-loop registers:
#     s1 (x9)  : scratchpad base 0x80000000
#     s2 (x18) : live iteration counter
#     s4 (x20) : checksum (updated ONLY at the correct landing pads)
#     s11(x27) : poison register (init 0x00000000, must stay 0)
#
#   Scratchpad layout (SRAM base 0x80000000):
#     0x00 : reserved (0)
#     0x04 : exc_count  -- unexpected synchronous exceptions (must stay 0)
#     0x08 : nmi_handler address (testbench drives nmi_vector from here)
#     0x0C : recovery address for the mtvec handler (loop_recover)
#     0x14 : last unexpected mcause  (must stay 0; ==5 -> phantom fault)
#     0x18 : last unexpected mepc    (diagnostic)
#     0x100..0x17C : mncause log, one slot per NMI taken
#     0x180..0x18C : JVT (64-byte-aligned base, 4 entries)
#
#   JVT setup (copied from the inst_zcmt pattern):
#     jvt CSR (0x017) = 0x80000180 (64-byte aligned, within SRAM)
#     JVT[0..3] -> landing pads pad0..pad3
#
#   Loop: 32 iterations of cm.jt (index = iter & 3). Each landing pad adds
#   (index+1) to the checksum and jumps back. Expected checksum:
#   8 groups x (1+2+3+4) = 0x50.
#
#   Expected end state (good RTL):
#     s2 = 32, s4 = 0x50, s11 = 0, t3 = 32, exc_count = 0.
#   Buggy RTL:
#     - phantom load-access-fault: exc_count > 0, mcause slot == 5,
#       s11 = 0xDEADFA11
#     - corrupted post-mnret restart: wrong pad / fall-through ->
#       checksum != 0x50 and/or s11 = 0xDEADFA11
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi). Robust to firing at ANY point in the loop:
    # only uses the reserved registers t3/t4/t5, no stack accesses.
    # Records mncause into successive scratchpad slots (with wrap
    # guard), then mnret.
    #=================================================================
    .align 2
nmi_handler:
    addi t3, t3, 1              # nmi_count++
    csrr t4, 0x742              # mncause
    sw   t4, 0(t5)              # log mncause
    addi t5, t5, 4
    li   t4, 0x80000180         # wrap guard: keep log inside 0x100..0x17C
    bne  t5, t4, 1f
    li   t5, 0x80000100
1:
    .word 0x70200073            # mnret

    #=================================================================
    # M-MODE TRAP HANDLER (mtvec) -- phantom-fault catcher. Must NEVER
    # run on good RTL. Records mcause/mepc, bumps exc_count, sets the
    # poison register, then redirects mepc to the recovery point
    # (stashed at scratchpad 0x0C) so the test can finish and report.
    #=================================================================
    .align 2
trap_handler:
    csrr t4, mcause
    sw   t4, 0x14(s1)           # record unexpected mcause (5 = phantom LAF)
    csrr t4, mepc
    sw   t4, 0x18(s1)           # record unexpected mepc
    lw   t4, 0x04(s1)
    addi t4, t4, 1
    sw   t4, 0x04(s1)           # exc_count++
    li   s11, 0xDEADFA11        # poison: unexpected synchronous trap seen
    lw   t4, 0x0C(s1)
    csrw mepc, t4               # recover at loop_recover
    mret

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
    sw   t0, 0x0C(s1)           # recovery addr
    sw   t0, 0x14(s1)           # unexpected mcause
    sw   t0, 0x18(s1)           # unexpected mepc

    # Zero the mncause log (0x80000100 .. 0x8000017C)
    li   t1, 0x80000100
    li   t2, 0x80000180
1:  sw   t0, 0(t1)
    addi t1, t1, 4
    bltu t1, t2, 1b

    # Publish NMI handler address for the testbench (drives nmi_vector)
    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x08(s1)

    # Publish the recovery address for the mtvec handler
    la   t0, loop_recover
    sw   t0, 0x0C(s1)

    # Install the phantom-fault catcher (must never fire)
    la   t0, trap_handler
    csrw mtvec, t0

    #-----------------------------------------------------------------
    # SETUP JVT: base = 0x80000180 (64-byte aligned, within SRAM)
    # JVT[0..3] -> pad0..pad3
    #-----------------------------------------------------------------
    li   t0, 0x80000180
    csrw 0x017, t0              # jvt.base = 0x80000180
    la   t1, pad0
    sw   t1, 0(t0)              # JVT[0] = pad0
    la   t1, pad1
    sw   t1, 4(t0)              # JVT[1] = pad1
    la   t1, pad2
    sw   t1, 8(t0)              # JVT[2] = pad2
    la   t1, pad3
    sw   t1, 12(t0)             # JVT[3] = pad3

    # Enable NMI: mnstatus.NMIE = 1 (bit[3]); resets to 0 per Smrnmi
    csrsi 0x744, 8

    # Initialize loop / handler registers
    li   s2, 0                  # iteration counter
    li   s4, 0                  # checksum
    li   s11, 0                 # poison register -- must stay 0
    li   t3, 0                  # nmi_count (handler)
    li   t4, 0                  # handler scratch
    li   t5, 0x80000100         # mncause log pointer (handler)

    li   x31, 0x11111111        # init done -- testbench latches nmi_vector

    #=================================================================
    # SWEEP LOOP: 32 iterations of cm.jt (index = iter & 3). Each
    # iteration writes a DISTINCT sync value (0x52000000 + iter) to x31
    # right before the cm.jt dispatch; the testbench pulses NMI at a
    # different cycle offset (0..31) after seeing each sync value,
    # sweeping the JVT-load phase of the cm.jt across wait-state
    # variants.
    #=================================================================
jt_loop:
    li   t1, 0x52000000
    add  x31, t1, s2            # per-iteration sync marker

    # Dispatch to cm.jt <iter & 3>
    andi t1, s2, 3
    beqz t1, do_jt0
    addi t1, t1, -1
    beqz t1, do_jt1
    addi t1, t1, -1
    beqz t1, do_jt2

do_jt3:
    cm.jt 3
    j    jt_fallthrough
do_jt2:
    cm.jt 2
    j    jt_fallthrough
do_jt1:
    cm.jt 1
    j    jt_fallthrough
do_jt0:
    cm.jt 0
    j    jt_fallthrough

    # Landing pads: the ONLY places the checksum is updated.
pad0:
    addi s4, s4, 1
    j    loop_recover
pad1:
    addi s4, s4, 2
    j    loop_recover
pad2:
    addi s4, s4, 3
    j    loop_recover
pad3:
    addi s4, s4, 4
    j    loop_recover

jt_fallthrough:
    # cm.jt fell through instead of jumping (corrupted restart) --
    # poison, then continue so the test still finishes and reports.
    li   s11, 0xDEADFA11

loop_recover:
    addi s2, s2, 1
    li   t1, 32
    blt  s2, t1, jt_loop

    # Expected checksum: 8 x (1+2+3+4) = 0x00000050
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test

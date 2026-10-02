#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dret_clears_mprv_sdt
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DEBUG DRET clears MPRV / sstatus.SDT (Debug Spec 4.8 Resume)
#   Debug 4.8 (dret): "4. If the new privilege mode is less privileged than
#   M-mode, MPRV in mstatus is cleared. 5. If Smdbltrp is implemented and
#   the new privilege mode is not M, then the MDT bit is set to 0. 6. If
#   Ssdbltrp is implemented and the new privilege mode is U, VS, or VU, then
#   sstatus.SDT is set to 0."
#
#   PHASE 1  M-mode arms mstatus.MPRV=1 and sstatus.SDT=1, then spins. The
#            testbench halts the hart (dcsr.prv=3), rewrites dcsr.prv=U and
#            resumes. Now in U-mode, the firmware ecalls (cause 8) to M; the
#            handler samples mstatus: MPRV and SDT must both read 0 (a trap
#            into M never touches SDT, so this is the post-dret value).
#   PHASE 2  The handler re-arms MPRV=1 / SDT=1 and spins. The testbench
#            halts (dcsr.prv=3), rewrites dcsr.prv=S and resumes. Now in
#            S-mode, the firmware reads sstatus.SDT (must still be 1: only a
#            resume into U clears it) and ecalls (cause 9) to M; the handler
#            samples mstatus: MPRV must be 0 (S < M), SDT still 1, MPP=S.
#
#   Registers:
#     x18 : sentinel marker                            (expect 0xA5A5A5A5)
#     x19 : phase flag (0 -> 1 after the first trap)
#     x20 : mstatus & (SDT|MPRV) armed before halt 1   (expect 0x01020000)
#     x21 : phase-1 mcause                             (expect 8: ecall from U)
#     x22 : phase-1 mstatus & (SDT|MPRV)               (expect 0)
#     x23 : phase-2 sstatus & SDT read in S-mode       (expect 0x01000000)
#     x24 : phase-2 mcause                             (expect 9: ecall from S)
#     x25 : phase-2 mstatus & MPRV                     (expect 0)
#     x26 : phase-2 mstatus & SDT                      (expect 0x01000000)
#     x27 : phase-2 mstatus.MPP                        (expect 1: S)
#     x31 : sync (11111111=armed/spinning, 22222222=re-armed/spinning,
#                 deadbeef=done)
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.equ MNSTATUS, 0x744
.equ SDT,      0x01000000
.equ MPRV,     0x00020000
.equ SDT_MPRV, 0x01020000

.section .text
.global main
main:
    PMP_ALLOW_ALL               # grant the address space before leaving M-mode
    li   x18, 0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x19, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0
    li   x25, 0
    li   x26, 0
    li   x27, 0

    la   t0, m_handler          # M-mode trap vector, direct mode
    csrw mtvec, t0

    csrsi MNSTATUS, 8           # arm NMIE first ...
    csrw  mstatush, x0          # ... then clear MDT (Smdbltrp boot order)

    #-------------------------------------------------------------
    # PHASE 1: arm MPRV=1 and SDT=1 in M-mode, spin for the halt.
    #-------------------------------------------------------------
    li   t2, SDT_MPRV
    csrs mstatus, t2
    csrr t0, mstatus
    and  x20, t0, t2            # expect 0x01020000 (both armed)

    li   x31, 0x11111111        # sync: armed, ready to be halted (in M)
    li   t1, 2000
spin1:
    addi t1, t1, -1
    bnez t1, spin1

    # Resumed here with dcsr.prv=U -> now in U-mode. Go to M to sample.
    .option push
    .option norvc
    ecall                       # cause 8 (ecall from U) -> m_handler
    .option pop
hang1:
    j    hang1

    #-------------------------------------------------------------
    # M-mode handler: phase 1 samples and re-arms, phase 2 samples
    # and finishes.
    #-------------------------------------------------------------
    .align 2
    .option push
    .option norvc
m_handler:
    csrw mstatush, x0           # clear MDT on entry
    csrr t0, mcause
    csrr t1, mstatus
    bnez x19, phase2

    mv   x21, t0                # expect 8 (trapped from U: prv restored)
    li   t2, SDT_MPRV
    and  x22, t1, t2            # expect 0 (dret to U cleared MPRV and SDT)
    li   x19, 1

    # PHASE 2: re-arm MPRV=1 and SDT=1, spin for the second halt.
    csrs mstatus, t2
    li   x31, 0x22222222        # sync: re-armed, ready to be halted (in M)
    li   t1, 2000
spin2:
    addi t1, t1, -1
    bnez t1, spin2

    # Resumed here with dcsr.prv=S -> now in S-mode.
    csrr t0, sstatus
    li   t1, SDT
    and  x23, t0, t1            # expect 0x01000000 (dret to S keeps SDT)
    ecall                       # cause 9 (ecall from S) -> m_handler
hang2:
    j    hang2

phase2:
    mv   x24, t0                # expect 9 (trapped from S)
    li   t2, MPRV
    and  x25, t1, t2            # expect 0 (dret to S < M cleared MPRV)
    li   t2, SDT
    and  x26, t1, t2            # expect 0x01000000 (SDT survived dret to S)
    srli t2, t1, 11
    andi x27, t2, 3             # expect 1 (MPP = S)
    li   x31, 0xdeadbeef        # final sync: test done
hang3:
    j    hang3
    .option pop

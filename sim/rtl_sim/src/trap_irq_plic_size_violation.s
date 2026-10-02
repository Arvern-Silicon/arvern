#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_irq_plic_size_violation
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PLIC AHB size-check ERROR response
#   The PLIC 1.0 spec (ch.3) mandates LW/SW (32-bit word) access to every
#   memory-mapped register. ahb_plic returns a two-cycle AHB ERROR on any
#   non-word access; the core reports it as a resumable data-bus-error RNMI
#   (mncause = 0x80000003, faulting address in marv_eaddr), for reads and
#   writes alike -- never mcause 5/7.
#
#   Phases (all from M-mode -- size check is independent of PRIV_CHECK_EN
#   and of privilege mode):
#     1. Word SW to priority[1]               -> succeeds (legit)
#     2. Byte SB to priority[1]               -> AHB ERROR -> RNMI
#     3. Halfword LH from threshold[ctx0]     -> AHB ERROR -> RNMI
#     4. Word LW from priority[1]             -> succeeds, returns the
#        value written in phase 1 (verifies the bad-size accesses did NOT
#        commit garbage to the register file)
#----------------------------------------------------------------------------

.section .text
.global main

.equ PLIC_PRI1,      0x0C000004        # priority[1]
.equ PLIC_TH_M,      0x0C200000        # threshold[ctx0=M]

#=========================================================================
# Scratchpad (base 0x80000000)
#   0x00: trap_count
#   0x04: 1st mncause    (expect 0x80000003 = data-bus error)
#   0x08: 1st marv_eaddr (expect 0x0C000004)
#   0x0C: 2nd mncause    (expect 0x80000003)
#   0x10: 2nd marv_eaddr (expect 0x0C200000)
#   0x14: word read-back of priority[1] (expect 0x55)
#=========================================================================

main:
    j _start

    .align 2
# Sub-word PLIC accesses AHB-ERROR, which is a data-bus error: an RNMI, not
# mcause 5/7. mnepc is already the resume point, so nothing is advanced here.
nmi_handler:
    addi sp, sp, -20
    sw   t0, 16(sp)
    sw   t1, 12(sp)
    sw   t2,  8(sp)
    sw   t3,  4(sp)
    sw   t4,  0(sp)

    csrr t0, 0x742                  # mncause
    csrr t1, 0xFFC                  # marv_epc
    csrr t2, 0xFFD                  # marv_eaddr

    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    li   t4, 1
    beq  t3, t4, log_first
    j    log_second

log_first:
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    j    nmi_done

log_second:
    sw   t0, 0x0C(s1)
    sw   t2, 0x10(s1)

nmi_done:
    li   t0, 0x5
    csrw 0x7FE, t0                  # W1C valid|overrun: next fault captures its own

    lw   t4,  0(sp)
    lw   t3,  4(sp)
    lw   t2,  8(sp)
    lw   t1, 12(sp)
    lw   t0, 16(sp)
    addi sp, sp, 20
    .word 0x70200073                # mnret

    .align 2
# NEGATIVE CONTROL: mcause 5/7 are RESERVED, so mtvec must
# never be entered. Counts separately at 0x1C.
m_trap_handler:
    addi sp, sp, -8
    sw   t0, 4(sp)
    sw   t1, 0(sp)
    lw   t0, 0x1C(s1)
    addi t0, t0, 1
    sw   t0, 0x1C(s1)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    lw   t1, 0(sp)
    lw   t0, 4(sp)
    addi sp, sp, 8
    mret


_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x10(s1)
    sw   zero, 0x14(s1)

    la   t0, m_trap_handler
    csrw mtvec, t0

    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x18(s1)
    sw   zero, 0x1C(s1)
    lw   zero, 0x18(s1)

    li   x31, 0x1E1E1E1E            # tb programs nmi_vector here

    li   t0, 20
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    csrsi 0x744, 8                  # mnstatus.NMIE = 1

    #---------------------------------------------------------------
    # PHASE 1: legit word write to priority[1]
    #---------------------------------------------------------------
    li   t0, 0x55
    li   t1, PLIC_PRI1
    sw   t0, 0(t1)                  # word access -- succeeds

    li   x31, 0x11111111


    #---------------------------------------------------------------
    # PHASE 2: byte write to priority[1] -> AHB ERROR -> RNMI
    # The aRVern pipeline retires the next instruction while the AHB
    # ERROR walks back, so poll trap_count BEFORE advancing x31.
    #---------------------------------------------------------------
    li   t0, 0xAA
    li   t1, PLIC_PRI1
    sb   t0, 0(t1)                  # byte access -- AHB ERROR -> RNMI

poll_trap_1:
    lw   t2, 0x00(s1)
    li   t3, 1
    bne  t2, t3, poll_trap_1

    li   x31, 0x22222222


    #---------------------------------------------------------------
    # PHASE 3: halfword read from threshold[ctx0] -> AHB ERROR -> RNMI
    #---------------------------------------------------------------
    li   t1, PLIC_TH_M
    lh   t0, 0(t1)                  # halfword access -- AHB ERROR -> RNMI

poll_trap_2:
    lw   t2, 0x00(s1)
    li   t3, 2
    bne  t2, t3, poll_trap_2

    li   x31, 0x33333333


    #---------------------------------------------------------------
    # PHASE 4: word read of priority[1] -- verify the failed byte
    # write of phase 2 did NOT corrupt the register (still 0x55).
    #---------------------------------------------------------------
    li   t1, PLIC_PRI1
    lw   t0, 0(t1)
    sw   t0, 0x14(s1)

    # Poll the stored value before signalling: under -rwsram the SRAM
    # store is still posted on the AHB when x31 would otherwise change,
    # and the bench reads sram_x_inst.mem[] directly. The load
    # serialises after the prior store on AHB so the value is visible
    # before x31 transitions.
poll_phase4:
    lw   t2, 0x14(s1)
    beqz t2, poll_phase4

    li   x31, 0x44444444

end_of_test:
    j    end_of_test

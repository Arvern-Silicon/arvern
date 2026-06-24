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
#   non-word access; the core reports a load-access-fault (cause 5) for a
#   sub-word read and a store-access-fault (cause 7) for a sub-word write.
#
#   Phases (all from M-mode -- size check is independent of PRIV_CHECK_EN
#   and of privilege mode):
#     1. Word SW to priority[1]               -> succeeds (legit)
#     2. Byte SB to priority[1]               -> store access fault
#     3. Halfword LH from threshold[ctx0]     -> load access fault
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
#   0x04: 1st MCAUSE   (expect 7  = store access fault)
#   0x08: 1st MTVAL    (expect 0x0C000004)
#   0x0C: 2nd MCAUSE   (expect 5  = load  access fault)
#   0x10: 2nd MTVAL    (expect 0x0C200000)
#   0x14: word read-back of priority[1] (expect 0x55)
#=========================================================================

main:
    j _start

    .align 2
m_trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval

    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    li   t4, 1
    beq  t3, t4, log_first
    li   t4, 2
    beq  t3, t4, log_second
    j    advance_pc

log_first:
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    j    advance_pc

log_second:
    sw   t0, 0x0C(s1)
    sw   t2, 0x10(s1)

advance_pc:
    # Both faulting accesses (sb / lh) are 4-byte instructions.
    addi t1, t1, 4
    csrw mepc, t1

    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24
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

    #---------------------------------------------------------------
    # PHASE 1: legit word write to priority[1]
    #---------------------------------------------------------------
    li   t0, 0x55
    li   t1, PLIC_PRI1
    sw   t0, 0(t1)                  # word access -- succeeds

    li   x31, 0x11111111


    #---------------------------------------------------------------
    # PHASE 2: byte write to priority[1] -> store access fault
    # The aRVern pipeline retires the next instruction while the AHB
    # ERROR walks back, so poll trap_count BEFORE advancing x31.
    #---------------------------------------------------------------
    li   t0, 0xAA
    li   t1, PLIC_PRI1
    sb   t0, 0(t1)                  # byte access -- AHB ERROR -> SAF

poll_trap_1:
    lw   t2, 0x00(s1)
    li   t3, 1
    bne  t2, t3, poll_trap_1

    li   x31, 0x22222222


    #---------------------------------------------------------------
    # PHASE 3: halfword read from threshold[ctx0] -> load access fault
    #---------------------------------------------------------------
    li   t1, PLIC_TH_M
    lh   t0, 0(t1)                  # halfword access -- AHB ERROR -> LAF

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

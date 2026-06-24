#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_zcmp_push_fault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: cm.push with first store hitting an unmapped address
#   Probes whether a Zcmp pushpop UOP sequence can leak a trailing AHB
#   transfer (next register's store) after the first store takes an
#   access fault. If the per-cycle aph_ongoing gates close cleanly, no
#   trailing transfer should reach the slave; the only observable AHB store
#   is the (faulting) first one.
#
#   Test method:
#   - Pre-init a counter at 0x80000020 = 0xC0FFEE00 sentinel.
#   - Point sp to an UNMAPPED address (0xA0000000) so the first store
#   attempt faults.
#   - Pre-init two SRAM addresses that the *trailing* push would target
#   (one offset higher than sp, but in mapped SRAM at 0x80000040/0x44)
#   with sentinels.
#   - Execute `cm.push {ra,s0-s2}, -16` (rlist=6: ra,s0,s1,s2; stack_adj=16)
#   with sp pointing into the unmapped region.
#   - Trap handler skips the cm.push.
#   - After return, check that none of the SRAM sentinel addresses were
#   touched (i.e., no trailing-store leak).
#----------------------------------------------------------------------------

.equ FAULT_SP_BASE,  0xA0000000
.equ CANARY_A,       0x80000040
.equ CANARY_B,       0x80000044
.equ CANARY_C,       0x80000048
.equ SENTINEL_A,     0xC0FFEE00
.equ SENTINEL_B,     0xC0FFEE01
.equ SENTINEL_C,     0xC0FFEE02

.section .text
.global main
main:
    li   sp, 0x80010000

    /* Trap handler advances mepc past the cm.push (2 bytes for compressed) */
    la   t0, h_skip2
    csrw mtvec, t0

    /* Seed canaries -- if a trailing store leaks, one of these will be      */
    /* overwritten with a register value (s0/s1/s2 below).                   */
    li   t0, CANARY_A
    li   t1, SENTINEL_A
    sw   t1, 0(t0)
    li   t0, CANARY_B
    li   t1, SENTINEL_B
    sw   t1, 0(t0)
    li   t0, CANARY_C
    li   t1, SENTINEL_C
    sw   t1, 0(t0)

    /* Load distinctive values into the registers cm.push would store. If    */
    /* any leak as a trailing store, we'll see them in the canary memory.    */
    li   ra, 0xAAAAAAAA
    li   s0, 0xBBBBBBBB
    li   s1, 0xCCCCCCCC
    li   s2, 0xDDDDDDDD

    fence rw, rw

    /* Now redirect sp into the unmapped fault region. */
    li   sp, FAULT_SP_BASE

    li   x31, 0xFFFFFFFF

    /* The cm.push instruction. First store attempts at sp-4 (= 0x9FFFFFFC)  */
    /* in the unmapped region, which faults. */
    cm.push {ra, s0-s2}, -16

    /* Handler skips past cm.push. Now restore a valid sp and check canaries. */
    li   sp, 0x80010000

    /* Read each canary back into x10/x11/x12. They should still be the      */
    /* SENTINEL values if no trailing store leaked.                          */
    fence rw, rw

    li   t0, CANARY_A
    lw   x10, 0(t0)
    add  x10, x10, x0
    li   x31, 0x11111111

    li   t0, CANARY_B
    lw   x10, 0(t0)
    add  x10, x10, x0
    li   x31, 0x22222222

    li   t0, CANARY_C
    lw   x10, 0(t0)
    add  x10, x10, x0
    li   x31, 0x33333333

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test


/*===========================================================================*/
/* Trap handler -- advances mepc past the faulting cm.push (16-bit C insn).  */
/* No stack use: this handler runs while sp points into the faulting region, */
/* so any AHB store from the handler itself would cause a nested fault. t0   */
/* is trashed (caller-saved) -- main re-assigns it after the trap returns.   */
/*===========================================================================*/
.align 2
h_skip2:
    csrr t0, mepc
    addi t0, t0, 2
    csrw mepc, t0
    mret

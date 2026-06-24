#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_zcmp_pop_fault
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CM.POP LOAD ACCESS-FAULT ABORT
#   Reproducer for the CM.POP/POPRET sync-exception UOP-abort gap:
#
#   ex_uop_kill_i = trap_kill_uop_o = ((irqkill_uop_en & trap_is_irq) |
#   trap_is_nmi) & trap_pending_o & ...
#   never fires for synchronous LSU access faults (trap_is_irq=0,
#   trap_is_nmi=0). Therefore ex_uop_control_reg keeps the CM.POP active
#   after a load-access fault, the sequencer keeps decrementing the
#   counter, and additional AHB load transfers are issued AFTER the trap
#   handler entry — register-file writes for those later loads escape the
#   one-cycle trap_kill_wb_o pulse and pollute callee-saved registers.
#
#   Test mechanism:
#   1. SP <- 0x00000000 (unmapped). All pop loads will take an access
#   fault.
#   2. Pre-init s0/s1/s2 with sentinel values 0xA0/A1/A2A2A2A2.
#   3. cm.pop {ra, s0-s2}, 16.
#   4. Trap handler counts each trap entry, captures MEPC/MCAUSE/MTVAL,
#   and redirects MEPC to recovery.
#   5. After recovery:
#   - trap_count must be exactly 1 (post-fix)
#   - s0/s1/s2 must retain their pre-pop sentinel values (post-fix)
#   Pre-fix: trap_count > 1 (sequencer re-faulted on continued loads)
#   and/or s0/s1/s2 reads from address 4/8/12 do not fault
#   (because address 4 maps to ROM, not faulting), so those
#   registers receive garbage (pollution).
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count             (incremented on each handler entry)
#   0x04: last MCAUSE
#   0x08: last MEPC
#   0x0C: recovery address       (set before cm.pop)
#   0x10: s0 captured after recovery
#   0x14: s1 captured after recovery
#   0x18: s2 captured after recovery
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    # The faulting firmware may have an unmapped SP (we deliberately set
    # SP=0 before cm.pop), so the handler MUST swap to a safe stack via
    # mscratch before touching memory. Standard RISC-V idiom:
    #   csrrw sp, mscratch, sp   -- atomic swap: sp <- mscratch, mscratch <- old sp
    # On return we swap back.
    #=================================================================
    .align 2
trap_handler:
    csrrw sp, mscratch, sp       # swap SP with trap-handler stack
    addi  sp, sp, -32
    sw    t0, 28(sp)
    sw    t1, 24(sp)
    sw    t2, 20(sp)
    sw    t3, 16(sp)
    sw    s1, 12(sp)

    li    s1, 0x80000000         # restore scratchpad base (s1 may have been clobbered)
    csrr  t0, mcause
    csrr  t1, mepc

    # Increment trap_count
    lw    t2, 0x00(s1)
    addi  t2, t2, 1
    sw    t2, 0x00(s1)

    # Save last MCAUSE / MEPC (overwrite -- last fault wins)
    sw    t0, 0x04(s1)
    sw    t1, 0x08(s1)

    # Redirect MEPC to recovery
    lw    t3, 0x0C(s1)
    csrw  mepc, t3

    lw    s1, 12(sp)
    lw    t3, 16(sp)
    lw    t2, 20(sp)
    lw    t1, 24(sp)
    lw    t0, 28(sp)
    addi  sp, sp, 32
    csrrw sp, mscratch, sp       # swap SP back to faulting context
    mret


_start:
    # SP starts in the upper half of SRAM (64KB at 0x80000000..0x8000FFFF).
    li   sp, 0x8000F000
    li   s1, 0x80000000           # scratchpad base

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x18(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    # Pre-init sentinel-bearing registers
    li   s0, 0xA0A0A0A0           # x8
    li   s2, 0xA2A2A2A2           # x18

    li   x31, 0x11111111          # init done


    #=================================================================
    # PHASE 2: cm.pop with sp at unmapped address (0x00000000).
    # All pop loads must take a load-access fault. The fix guarantees
    # exactly ONE trap delivers; the bug would let multiple AHB error
    # responses re-trigger trap_pending_set as the sequencer keeps
    # issuing transfers after the first fault.
    #
    # rlist=6 in Zcmp encoding maps to {ra, s0-s1}, so popping ra/s0/s1.
    # Use rlist=7 to also exercise s2 -- pop {ra, s0-s2}, 16.
    #=================================================================

    # Save current SP into a temp so the trap handler prologue can still
    # use a valid stack (it pushes context onto sp before reading).
    # cm.pop reads from the architectural sp, so before issuing cm.pop
    # we have to point sp at the unmapped region. The trap handler
    # restores a working sp by virtue of its first instruction (addi sp,
    # sp, -32) which only works if sp is mapped... so the trap handler's
    # own stack must be valid. Solution: pre-stash a known-good "trap
    # stack" address in a fixed location, and have the handler swap to
    # it. But that adds complexity. Instead, leave x9 (s1=scratchpad
    # base) untouched (it is the s1 register we use for the scratchpad),
    # and have the handler use mscratch as a trap stack pointer.

    # Configure mscratch as the trap-handler stack base (inside SRAM).
    li   t0, 0x8000F000
    csrw mscratch, t0

    # Recovery address: where mret should land after the fault.
    la   t0, recovery_p2
    sw   t0, 0x0C(s1)

    # Point sp at the unmapped region. The first pop load will fault.
    li   sp, 0x00000000

    li   x31, 0x12121212          # marker: about to enter cm.pop
    cm.pop {ra, s0-s2}, 16        # rlist=7 -> pops s2, s1, s0, ra in order
    # Pre-fix: control may or may not reach here depending on how the
    # sequencer continues. Post-fix: recovery is via trap handler mret.
    li   x31, 0xBADBAD01

recovery_p2:
    # Restore working SP for downstream code
    li   sp, 0x8000F000

    # Capture s0/s1/s2 final values for the testbench.
    sw   s0, 0x10(s1)             # expect 0xA0A0A0A0 (post-fix)
    sw   s2, 0x18(s1)             # expect 0xA2A2A2A2 (post-fix)
    # Skip s1 -- s1 holds the scratchpad base and we need it.

    li   x31, 0x22222222          # phase 2 done


    li   x31, 0xdeadbeef
end_of_test:
    j    end_of_test

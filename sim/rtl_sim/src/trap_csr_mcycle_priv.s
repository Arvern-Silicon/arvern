#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_csr_mcycle_priv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: M-MODE COUNTERS U-MODE PRIVILEGE TRAP
#   mcycle (0xB00) / minstret (0xB02) / mcycleh (0xB80) are M-only per
#   Privileged spec §3.1.11 / Table 2.5. Their encoded addresses have
#   bits[9:8]=00 (the standard "user-RW" privilege encoding), so the existing
#   `acc_priv_is_machine = (addr[9:8]==2'b11)` check at arv_csr_top.v doesn't
#   catch them. From U-mode any read of these CSRs slipped through pre-fix
#   (privilege leak / cycle-counter side channel).
#
#   The U-mode shadows (cycle/instret/cycleh at 0xC00/0xC02/0xC80) are
#   correctly gated by mcounteren -- that path is not exercised by this test.
#
#   Phase 2: csrr t0, mcycle    from U-mode -> expect MCAUSE=2.
#   Phase 3: csrr t0, minstret  from U-mode -> expect MCAUSE=2.
#   Phase 4: csrr t0, mcycleh   from U-mode -> expect MCAUSE=2.
#
#   Pre-fix: 0 traps. Post-fix: 3 traps, each MCAUSE=2.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MEPC
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    # Counts illegal-instruction traps from U-mode, advances MEPC by 4
    # (each CSRR encoding is 32 bits), returns to U-mode. ECALL handling
    # is also included so the test can ECALL back to M-mode at end.
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  8(sp)
    sw   t1,  4(sp)
    sw   t2,  0(sp)

    csrr t0, mcause
    csrr t1, mepc

    # ECALL from U-mode -> mcause=8. We use this to escape back to M-mode
    # at end of test by setting MSTATUS.MPP=11 before mret. No advance.
    li   t2, 8
    beq  t0, t2, _ecall_from_umode

    # Illegal-instruction (mcause=2) path: increment trap_count, save
    # mcause/mepc, advance mepc by 4 to skip the CSRR, return to U-mode.
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    sw   t0, 0x04(s1)
    sw   t1, 0x08(s1)

    addi t1, t1, 4
    csrw mepc, t1
    j _trap_return

_ecall_from_umode:
    # Set MPP=11 (M-mode), then mret -- next instruction will run in M-mode.
    li   t2, 0x1800
    csrs mstatus, t2
    addi t1, t1, 4                 # skip past ECALL
    csrw mepc, t1
    j _trap_return

_trap_return:
    lw   t2,  0(sp)
    lw   t1,  4(sp)
    lw   t0,  8(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000           # safe SP inside 64KB SRAM
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    li   x31, 0x11111111          # init done


    #=================================================================
    # Switch to U-mode: MPP=00, then mret to u_mode_entry
    #=================================================================
    la   t0, u_mode_entry
    csrw mepc, t0

    li   t0, 0x1800
    csrc mstatus, t0              # Clear MPP -> 00 (U-mode)

    li   t0, 0x80
    csrc mstatus, t0              # Clear MPIE

    mret                          # -> U-mode at u_mode_entry


u_mode_entry:
    # =======================================================================
    # Now executing in U-mode.
    # Each of the following CSRR accesses to an M-only counter must trap
    # with mcause=2. The handler advances mepc past the CSRR so the next
    # one runs.
    # =======================================================================

    # PHASE 2: mcycle (0xB00)
    csrr t0, 0xB00

    # PHASE 3: minstret (0xB02)
    csrr t0, 0xB02

    # PHASE 4: mcycleh (0xB80)
    csrr t0, 0xB80

    # PHASE 5: escape back to M-mode via ECALL
    ecall

    # Back in M-mode (handler set MPP=11, advanced mepc past ECALL).
    li   x31, 0xdeadbeef

end_of_test:
    j    end_of_test

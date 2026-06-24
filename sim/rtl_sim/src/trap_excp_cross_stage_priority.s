#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_cross_stage_priority
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CROSS-STAGE EXCEPTION PRIORITY (WB vs EX)
#   Verify precise-exception semantics when a WB-stage load access fault from
#   instruction N co-fires with an EX-stage illegal-instruction trap from a
#   DIFFERENT, YOUNGER instruction N+2.
#
#   PIPELINE-TIMING REQUIREMENT for the race:
#
#   dph_error is REGISTERED in arv_load_store.v (line 190-191):
#   dph_error <= dph_error1st  (one-cycle delay).
#
#   So wb_excp_load_access_fault_o is high ONE cycle AFTER HRESP=ERROR.
#   The race needs an EX-illegal to fire on the SAME cycle dph_error is
#   already registered — that means the EX-illegal instruction must be
#   N+2, not N+1, with a non-trapping filler in between.
#
#   T-2 : LW in EX (address phase issued)
#   T-1 : LW in WB (HRESP=ERROR, dph_error1st combinational)
#   filler in EX (NOP — no trap)
#   T   : LW past WB, dph_error registered → wb_excp_load_access_fault_o=1
#   filler in WB
#   csrw mhartid in EX → ex_excp_illegal_inst_i=1
#
#   Both signals fire on cycle T — but they belong to DIFFERENT
#   instructions (LW from older, CSRW from younger). Precise-exception
#   requires reporting the OLDER (LW) fault.
#
#   RACE TRIGGER CODE:
#   lw   t0, 0(t1)        ; t1 = 0x10000000 (unmapped) → WB load-acf
#   nop                   ; non-trapping filler
#   csrw mhartid, t2      ; write to RO CSR → EX illegal
#
#   Expected (spec-correct, fix in place):
#   First trap : mcause=5 (LD acf), mepc=lw_pc, mtval=0x10000000
#   Second trap: mcause=2 (illegal), mepc=csrw_pc, mtval=0
#
#   Pre-fix bug:
#   First trap : mcause=2 (illegal — WRONG, from CSRW)
#   mepc=wb_pc_i (whatever instruction was in WB on cycle T —
#   NOT the LW, since LW was in WB on T-1, NOT T)
#
#   Discriminator: first_mcause == 5 (PASS) vs first_mcause == 2 (FAIL).
#
#   The test runs entirely in M-mode (CSRW to mhartid traps "write to RO"
#   regardless of privilege — no U-mode setup needed).
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: trap_count
#   0x04: FIRST trap mcause   (the discriminator)
#   0x08: FIRST trap mepc
#   0x0C: FIRST trap mtval
#   0x10: SECOND trap mcause  (sanity)
#   0x14: SECOND trap mepc
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER (M-mode direct, mtvec mode=0)
    # Saves first two traps' mcause/mepc/mtval, advances mepc by 4
    # (all faulting insts are 32-bit non-compressed).
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -24
    sw   t0, 16(sp)
    sw   t1, 12(sp)
    sw   t2,  8(sp)
    sw   t3,  4(sp)
    sw   t4,  0(sp)

    csrr t0, mcause                # t0 = mcause
    csrr t1, mepc                  # t1 = mepc
    csrr t2, mtval                 # t2 = mtval

    # Read current trap_count
    lw   t3, 0x00(s1)              # t3 = trap_count (pre-increment)

    # trap_count == 0 → FIRST trap: record at 0x04/0x08/0x0C
    li   t4, 0
    bne  t3, t4, _check_second
    sw   t0, 0x04(s1)              # FIRST mcause
    sw   t1, 0x08(s1)              # FIRST mepc
    sw   t2, 0x0C(s1)              # FIRST mtval
    j    _adv_and_count

_check_second:
    # trap_count == 1 → SECOND trap: record at 0x10/0x14
    li   t4, 1
    bne  t3, t4, _adv_and_count
    sw   t0, 0x10(s1)              # SECOND mcause
    sw   t1, 0x14(s1)              # SECOND mepc

_adv_and_count:
    # Increment trap_count
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Advance mepc by 4 (all faulting insts are 32-bit non-compressed)
    addi t1, t1, 4
    csrw mepc, t1

_trap_return:
    lw   t4,  0(sp)
    lw   t3,  4(sp)
    lw   t2,  8(sp)
    lw   t1, 12(sp)
    lw   t0, 16(sp)
    addi sp, sp, 24
    mret


_start:
    li   sp, 0x8000F000           # safe SP inside SRAM
    li   s1, 0x80000000           # scratchpad base

    # Zero scratchpad slots
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)

    # Install trap handler (direct mode)
    la   t0, trap_handler
    csrw mtvec, t0

    # Load address operand BEFORE the race so the LW has no EX stall
    li   t1, 0x10000000           # unmapped address → HRESP=ERROR
    li   t2, 0xDEADBEEF           # CSRW source operand (value irrelevant)

    li   x31, 0x11111111          # init complete

    # =================================================================
    # RACE TRIGGER (the three instructions MUST stay back-to-back)
    # =================================================================
    # Align to 4-byte to ensure stable PC encoding under -c_mode (this
    # test only runs under STD mode but alignment is harmless).
    .align 2
race_site:
    lw   t0, 0(t1)                # T-1: WB, HRESP=ERROR (dph_error1st)
    addi x0, x0, 0                # T-1: ID, T: EX (NOP — explicit zero-encoded)
    csrw mhartid, t2              # T:   EX, write to RO mhartid → illegal

    # First trap returns here after handler advances mepc:
    #   - From LW(0)   trap: mepc += 4 → returns to NOP. NOP retires. CSRW retries → illegal.
    #   - From NOP(?)  trap: shouldn't happen (NOP doesn't trap).
    #   - From CSRW    trap: mepc += 4 → returns past CSRW.
    #
    # So we expect 2 traps total:
    #   spec-correct path: trap_count=2 (LW-acf first, then CSRW-illegal)
    #   bug path:          trap_count=2 (CSRW-illegal first, then CSRW-illegal again)

    li   x31, 0x22222222          # both traps taken

end_of_test:
    j    end_of_test

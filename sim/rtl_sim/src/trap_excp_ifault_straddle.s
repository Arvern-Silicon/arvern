#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_excp_ifault_straddle
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: IFAULT EXCEPTION (STRADDLE)
#   Instruction access fault on a 32-bit (NON-compressed) instruction whose
#   two 16-bit parcels STRADDLE the SRAM_X / unmapped-region boundary:
#
#   SRAM_X = 0x80000000 .. 0x8000FFFF (64 KiB, executable).
#   Last SRAM_X word @ 0x8000FFFC -> bytes 0xFFFC..0xFFFF:
#   halfword @ 0x8000FFFC  (parcel-aligned)
#   halfword @ 0x8000FFFE  (parcel-aligned, last valid halfword)
#   0x80010000 = first address PAST SRAM_X -> unmapped -> AHB error -> IAF.
#
#   Construction (runtime-written, COMP_MODE only -- a 32-bit instruction at
#   a 2-byte-but-not-4-byte-aligned address only exists with 16-bit fetch
#   granularity, i.e. the C extension):
#   word @ 0x8000FFFC = 0x00130001  (little-endian)
#   parcel @ 0x8000FFFC = 0x0001  bits[1:0]=01 -> COMPRESSED  (C.NOP)
#   parcel @ 0x8000FFFE = 0x0013  bits[1:0]=11 -> LOWER PARCEL of a real
#   32-bit instruction (0x00000013 ADDI
#   x0,x0,0); it is NOT a C parcel.
#   The fetcher consumes C.NOP @ 0x8000FFFC, then needs the UPPER parcel of
#   the straddling 32-bit instruction from 0x80010000 -> unmapped -> IAF.
#
#   Why a STRADDLE differs from the sibling sequential fall-off test:
#   The head (lower) parcel @ 0x8000FFFE is ALREADY in the fetch buffer when
#   the completing upper-parcel fetch faults; that head parcel can NEVER
#   retire (the 32-bit instr is incomplete) so the fetch buffer can never
#   drain. A "defer the IAF until the buffer empties" implementation will
#   therefore NEVER fire the fault -> the core LIVELOCKS.  Because the head-
#   parcel-in-buffer condition is INTRINSIC to the straddle (not a timing
#   artefact like an artificial -rsalu fill), the hang reproduces on the
#   BASE variant; the timing matrix only adds breadth.
#
#   Spec (RISC-V Privileged 3.1.16 / 12.1.9), instruction access fault on a
#   straddling 32-bit instruction:
#   mcause = 1   (instruction access fault, reported for the instr as whole)
#   mepc   = A          = 0x8000FFFE  (lower-parcel addr = the instr's PC,
#   "the beginning of the instruction")
#   mtval  = A+2         = 0x80010000 (addr of the faulting upper parcel)
#   NOTE: mepc != mtval here (unlike the simple non-straddle IAF, where the
#   faulting portion IS the instruction start so they coincide).
#
#   Phases:
#   PHASE A (benign straddle control): the SAME straddle construction placed
#   wholly inside valid SRAM_X. The straddling 32-bit ADDI must
#   reassemble across two words and execute correctly (x5 = 0x55).
#   Proves the straddle construction itself is sound and isolates
#   "straddle + fault" as the failing condition.
#   PHASE B (straddle + fault): the discriminator. A correct core takes the
#   IAF (mcause=1, mepc=0x8000FFFE, mtval=0x80010000). The current
#   (buggy) core LIVELOCKS: recovery_pB is never reached, x31 never
#   advances to 0x33333333, the .v hits LONG_TIMEOUT -> SIMULATION
#   FAILED (Timeout).  That timeout IS the bug signal.
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000) -- low addresses only.  The
# benign-straddle code lives mid-SRAM_X (0x80008000 region); the fault
# straddle word is the very last SRAM_X word (0x8000FFFC).
#
# Handler working area:
#   0x00: trap_count
#   0x04: last MCAUSE
#   0x08: last MTVAL
#   0x0C: last MEPC
#   0x10: trap_handled flag
#   0x14: recovery address (set before triggering IF exception)
#
# Phase A (BENIGN straddle control -- no fault):
#   0x20: benign result (x5, expect 0x00000055)
#
# Phase B (STRADDLE + FAULT past 0x8000FFFE):
#   0x30: MCAUSE             (expect 1)
#   0x34: MEPC               (expect 0x8000FFFE  == A, lower-parcel addr)
#   0x38: MTVAL             (expect 0x80010000  == A+2, faulting parcel)
#=========================================================================

.equ FAULT_LO_PC,   0x8000FFFE    # A: lower-parcel addr of the straddling
                                  #    32-bit instr  (== its own PC / MEPC)
.equ FAULT_HI_PC,   0x80010000    # A+2: upper (faulting) parcel addr (MTVAL)
                                  #      = first word past SRAM_X (unmapped)
.equ FAULT_WORD_AD, 0x8000FFFC    # last SRAM_X word (holds both fault parcels)
.equ FAULT_WORD,    0x00130001    # LE: [FFFC]=0x0001 C.NOP ; [FFFE]=0x0013
                                  #     (lower parcel of 0x00000013 ADDI x0,x0,0)

.equ BEN_BASE,      0x80008000    # benign straddle code base (in valid SRAM_X)
.equ BEN_WORD0,     0x02930001    # @0x80008000 LE: [8000]=0x0001 C.NOP ;
                                  #   [8002]=0x0293 = LOW half of
                                  #   0x05500293 = addi x5, x0, 0x55
.equ BEN_WORD1,     0x80820550    # @0x80008004 LE: [8004]=0x0550 = HIGH half
                                  #   of 0x05500293 (completes the straddle) ;
                                  #   [8006]=0x8082 = C.JR x1  (ret)

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -24
    sw   t0, 20(sp)
    sw   t1, 16(sp)
    sw   t2, 12(sp)
    sw   t3,  8(sp)
    sw   t4,  4(sp)

    csrr t0, mcause
    csrr t1, mepc
    csrr t2, mtval

    # Increment trap_count
    lw   t3, 0x00(s1)
    addi t3, t3, 1
    sw   t3, 0x00(s1)

    # Save to working area
    sw   t0, 0x04(s1)
    sw   t2, 0x08(s1)
    sw   t1, 0x0C(s1)

    # Set trap_handled flag
    li   t4, 1
    sw   t4, 0x10(s1)

    # Check if interrupt (MSB = 1)
    bltz t0, handle_interrupt

    # Instruction-fetch exceptions (cause 0 or 1): MEPC points at an
    # invalid/unmapped (or un-fetchable straddle) address, so we cannot
    # read or resume the instruction there. Redirect to the known-good
    # recovery label set up by the test code (cannot MRET to A: the
    # straddle would re-fault forever).
    beqz t0, use_recovery_addr     # cause 0: inst addr misaligned
    li   t3, 1
    beq  t0, t3, use_recovery_addr # cause 1: inst access fault

    # For other exceptions: advance MEPC past faulting instruction
    lhu  t4, 0(t1)
    andi t4, t4, 0x3
    li   t3, 0x3
    beq  t4, t3, advance_4
    addi t1, t1, 2
    j    exc_done
advance_4:
    addi t1, t1, 4
    j    exc_done

use_recovery_addr:
    lw   t1, 0x14(s1)             # load recovery address from scratchpad

exc_done:
    csrw mepc, t1
    j    handler_done

handle_interrupt:
    andi t3, t0, 0x1F
    li   t4, 7
    beq  t3, t4, disable_mtie
    j    handler_done
disable_mtie:
    li   t4, 0x80
    csrc mie, t4

handler_done:
    lw   t4,  4(sp)
    lw   t3,  8(sp)
    lw   t2, 12(sp)
    lw   t1, 16(sp)
    lw   t0, 20(sp)
    addi sp, sp, 24

    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
 _start:
    li   sp, 0x80004000          # stack well below the benign / tail regions
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)
    sw   t0, 0x14(s1)
    sw   t0, 0x20(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x34(s1)
    sw   t0, 0x38(s1)

    #=================================================================
    # PHASE 1: Install trap handler, init regs
    #=================================================================

    la   t0, trap_handler
    csrw mtvec, t0

    # Enable MSTATUS.MIE
    li   t0, 0x8
    csrs mstatus, t0

    # Initialize callee-saved registers (preservation check)
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE A: BENIGN STRADDLE CONTROL (no fault).
    #
    # Build, in valid SRAM_X @ 0x80008000:
    #   0x80008000: C.NOP                              (0x0001)
    #   0x80008002: addi x5, x0, 0x55  (32-bit, STRADDLES 0x80008002/4)
    #   0x80008006: C.JR x1            (return)        (0x8082)
    # Land at 0x80008000 via JALR with ra -> ben_ret. The straddling
    # 32-bit ADDI must reassemble across the two words and execute, so
    # x5 == 0x55. Proves the straddle construction is sound; the only
    # difference vs Phase B is that here the upper parcel is in MAPPED
    # memory (no fault).
    #=================================================================

    li   t0, BEN_WORD0
    li   t1, BEN_BASE            # 0x80008000
    sw   t0, 0(t1)               # [0x80008000] = 0x02930001
    li   t0, BEN_WORD1
    sw   t0, 4(t1)               # [0x80008004] = 0x80820550
    # Load-back the last written word so both stores have drained over
    # AHB before we jump into the just-written code (no I-cache; ensures
    # the fetch path sees the new bytes).
    lw   t2, 4(t1)

    li   x5, 0xDEADBEEF          # poison: must be overwritten to 0x55

    # ra = return target after the benign straddle's C.JR x1
    la   ra, ben_ret
    li   t0, BEN_BASE            # 0x80008000
    jalr x0, t0, 0               # enter benign straddle block

ben_ret:
    sw   x5, 0x20(s1)            # archive benign result (expect 0x55)
    lw   t1, 0x20(s1)            # load-back: sentinel-race guard so the
                                 # x31 below is set only AFTER the store
                                 # is visible to the testbench.

    li   x31, 0x22222222


    #=================================================================
    # PHASE B: STRADDLE + FAULT.
    #
    # Build the last SRAM_X word:
    #   0x8000FFFC: C.NOP                                   (0x0001)
    #   0x8000FFFE: LOWER parcel of 0x00000013 ADDI x0,x0,0 (0x0013)
    # The upper parcel of that 32-bit instr would come from 0x80010000
    # (first word past SRAM_X -> unmapped -> AHB error -> IAF).
    #
    # Land at 0x8000FFFC via JALR: C.NOP retires, then the straddling
    # 32-bit instruction's completing fetch (0x80010000) faults.
    #
    # CORRECT core : mcause=1, mepc=0x8000FFFE (==A), mtval=0x80010000.
    # BUGGY core   : the head parcel @0x8000FFFE sits in the fetch buffer
    #                and can never retire (incomplete 32-bit instr), so a
    #                "defer IAF until buffer empties" gate never fires ->
    #                LIVELOCK. recovery_pB is never reached, x31 stays at
    #                0x22222222, the .v hits LONG_TIMEOUT -> FAIL(Timeout).
    #=================================================================

    li   t0, FAULT_WORD          # 0x00130001
    li   t1, FAULT_WORD_AD       # 0x8000FFFC
    sw   t0, 0(t1)               # [0x8000FFFC] = 0x00130001
    lw   t2, 0(t1)               # drain the store before the jump

    # Store recovery address (handler returns here; cannot resume at A)
    la   t0, recovery_pB
    sw   t0, 0x14(s1)

    # Land directly on the C.NOP at 0x8000FFFC. The very next fetch is
    # the straddling 32-bit instruction whose upper parcel faults.
    li   t0, FAULT_WORD_AD       # 0x8000FFFC
    jalr x0, t0, 0

recovery_pB:
    lw   t0, 0x04(s1)
    sw   t0, 0x30(s1)            # MCAUSE  (expect 1)
    lw   t0, 0x0C(s1)
    sw   t0, 0x34(s1)            # MEPC    (expect 0x8000FFFE == A)
    lw   t0, 0x08(s1)
    sw   t0, 0x38(s1)            # MTVAL   (expect 0x80010000 == A+2)
    lw   t1, 0x38(s1)            # load-back: same wait-state sentinel
                                 # race guard -- x31 below is set only
                                 # after all three slots are visible.

    li   x31, 0x33333333


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test

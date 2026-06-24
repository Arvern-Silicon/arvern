#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_no_c_misencoded
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MISA-ADAPTIVE C MIS-ENCODING / VALID-RVC
#   This test is SELF-ADAPTING on the C (compressed) extension. At runtime
#   it reads CSR misa (0x301) and inspects bit 2 ("C"):
#
#   misa.C == 1  (DEFAULT build, C_EXTENSION>=1)
#   A halfword whose bits[1:0] != 0b11 is a *valid* 16-bit compressed
#   instruction, NOT an illegal parcel. This branch is a regression
#   guard for the unified compressed decoder: it executes a well-defined
#   Zca instruction (C.LI t3,0x15 -> bits[1:0]=01) and asserts that
#   (a) NO illegal-instruction trap was raised (illegal_count == 0),
#   (b) the architectural effect occurred (t3 == 0x00000015).
#   The instruction is emitted under ".option rvc" so the assembler
#   produces a genuine 2-byte parcel and the golden objdump ".lst" the
#   harness Instruction/PC Checker scoreboard derives also classifies it
#   as a 2-byte compressed instruction => NO scoreboard width mismatch.
#
#   misa.C == 0  (manual sweep build, C_EXTENSION==0)
#   RISC-V Unprivileged ISA, "Expanded Instruction-Length Encoding": a
#   32-bit base instruction is identified by bits[1:0]==0b11. With C NOT
#   implemented, any parcel whose bits[1:0]!=0b11 is not a valid
#   instruction and the hart must raise illegal-instruction (mcause=2).
#   This branch keeps the original contract: three mis-encoded .word
#   parcels each trap (mcause=2) and a following valid 32-bit ADDI does
#   not trap.
#
#   KNOWN HARNESS LIMITATION (C=0 branch only): the testbench
#   Instruction/PC Checker scoreboard is built from a golden objdump
#   ".lst" produced by a C-enabled toolchain, which always classifies a
#   bits[1:0]=10 word as a 2-byte compressed parcel. Against a C=0 DUT
#   (which correctly consumes it as a 4-byte illegal parcel) this emits
#   a benign width-classification mismatch for the deliberately-malformed
#   parcels. There is no per-test knob to disable that scoreboard. In
#   C=0 mode the AUTHORITATIVE verdict of this test is its own check_*
#   / scratchpad assertions (illegal_count, MCAUSE), NOT the scoreboard.
#   (In the DEFAULT C=1 build there is no such mismatch -- DUT and golden
#   both see a real compressed instruction.)
#
#   Registered in run_config.json as "mode":"STD", "no_random_irq":true and
#   NO "requires" constraint -- it runs in the default C-enabled regression.
#----------------------------------------------------------------------------

    .section .text
    .option norvc                 # never let the assembler emit compressed
                                  # code around the manually-placed parcels
    .global main

.equ MISA, 0x301

#=========================================================================
# Scratchpad layout (SRAM base 0x80000000)
#
#   0x00: illegal_count   (number of mcause=2 traps)
#   0x04: other_count     (any non-illegal trap cause - must stay 0)
#   0x08: last MCAUSE
#   0x0C: positive-control result
#           C=1 path: C.LI t3 result, must be 0x00000015
#           C=0 path: ADDI x5 result, must be 0x00000042
#   0x10: misa.C captured at init (1 => C enabled, 0 => C disabled)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER
    #   mcause=2 -> illegal_count++ ; advance MEPC +4 (32-bit .word)
    #   else     -> other_count++   ; advance MEPC +4 (defensive)
    #
    # Only ever exercised on the C=0 path. On the C=1 path no parcel
    # under test traps; if it did, illegal_count would be != 0 and the
    # testbench scratchpad check would (correctly) fail the test.
    #=================================================================
    .align 2
trap_handler:
    addi sp, sp, -16
    sw   t0,  8(sp)
    sw   t1,  4(sp)
    sw   t2,  0(sp)

    csrr t0, mcause
    csrr t1, mepc
    sw   t0, 0x08(s1)             # last MCAUSE

    li   t2, 2
    beq  t0, t2, hc_illegal

    lw   t2, 0x04(s1)
    addi t2, t2, 1
    sw   t2, 0x04(s1)
    j    hc_advance

hc_illegal:
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

hc_advance:
    # Each mis-encoded parcel is stored as a 32-bit .word; with C
    # disabled the fetch unit consumes 4 bytes, so step MEPC by 4.
    addi t1, t1, 4
    csrw mepc, t1

    lw   t2,  0(sp)
    lw   t1,  4(sp)
    lw   t0,  8(sp)
    addi sp, sp, 16
    mret


_start:
    li   sp, 0x8000F000
    li   s1, 0x80000000

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)
    sw   t0, 0x04(s1)
    sw   t0, 0x08(s1)
    sw   t0, 0x0C(s1)
    sw   t0, 0x10(s1)

    # Install trap handler
    la   t0, trap_handler
    csrw mtvec, t0

    #=================================================================
    # Read misa, isolate the "C" bit (bit 2 -> mask 0x4), publish the
    # runtime decision to the scratchpad BEFORE the first x31 sync so
    # the testbench can read it deterministically at the init point.
    #=================================================================
    csrr t0, MISA
    andi t0, t0, 0x4              # t0 = misa.C ? 4 : 0
    beqz t0, c_disabled_setup

    li   t0, 1
    sw   t0, 0x10(s1)             # misa.C = 1  (C enabled)
    lw   t0, 0x10(s1)             # drain: RAW same-word read forces the
                                  # publish store to fully retire on the
                                  # single-outstanding AHB-Lite bus before
                                  # the x31 sentinel, so the testbench can
                                  # never read scratchpad 0x10 stale under
                                  # -rwsram/-rwsper random wait states.
    li   x31, 0x11111111          # init done
    j    c_enabled_path

c_disabled_setup:
    li   t0, 0
    sw   t0, 0x10(s1)             # misa.C = 0  (C disabled)
    lw   t0, 0x10(s1)             # drain (see c_enabled_setup): same-word
                                  # RAW retires the publish store before
                                  # the x31 sentinel under random WS.
    li   x31, 0x11111111          # init done
    j    c_disabled_path


#=============================================================================
#  C-ENABLED PATH  (misa.C == 1, DEFAULT build)
#
#  A bits[1:0]=01 parcel is a legal compressed instruction. Execute a
#  genuine Zca C.LI and prove it (a) did not trap and (b) took effect.
#=============================================================================
    .align 2
c_enabled_path:

    #-----------------------------------------------------------------
    # PHASE 2: valid compressed instruction (regression guard).
    #          C.LI t3, 0x15  -> encoding bits[1:0] = 01.
    #          Emitted under ".option rvc" so the assembler produces a
    #          real 2-byte parcel and the golden objdump agrees.
    #-----------------------------------------------------------------
    li   t3, 0                    # clear t3 first (32-bit, .option norvc)
.option rvc
    c.li t3, 0x15                 # t3 = 0x00000015 ; MUST NOT trap
.option norvc
    sw   t3, 0x0C(s1)             # park result for the testbench
    lw   t0, 0x0C(s1)             # drain: same-word RAW retires the C.LI
                                  # result store before the 0x22222222
                                  # sentinel, so PHASE 2's scratchpad
                                  # check cannot read 0x0C stale under
                                  # -rwsram/-rwsper random wait states.
    li   x31, 0x22222222


    #-----------------------------------------------------------------
    # PHASE 5 (C=1): positive control already covered by C.LI itself.
    #                Confirm no trap was ever taken and finish.
    #-----------------------------------------------------------------
    li   x31, 0xdeadbeef
    j    end_of_test


#=============================================================================
#  C-DISABLED PATH  (misa.C == 0, manual C_EXTENSION==0 sweep build)
#
#  Original contract: bits[1:0]!=0b11 32-bit parcels raise illegal.
#  Each mis-encoded word is emitted with .word at a 4-byte-aligned
#  address, preceded and followed by valid 32-bit instructions, so the
#  test proves the handler resumed correctly after stepping over it.
#=============================================================================
    .align 2
c_disabled_path:

    #=================================================================
    # PHASE 2: mis-encoded word, [1:0] = 01  -> illegal (mcause=2)
    #=================================================================
    .align 2
    .word 0x12345671
    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: mis-encoded word, [1:0] = 10  -> illegal (mcause=2)
    #=================================================================
    .align 2
    .word 0x0000A002
    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: mis-encoded word, [1:0] = 00  -> illegal (mcause=2)
    #=================================================================
    .align 2
    .word 0xFFFF0000
    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: POSITIVE CONTROL -- a valid 32-bit ADDI ([1:0]=11).
    #          Must execute normally; must NOT trap.
    #=================================================================
    .align 2
    li   x5, 0
    addi x5, x5, 0x42             # x5 = 0x00000042 (valid 32-bit insn)
    sw   x5, 0x0C(s1)             # park result for the testbench

    li   x31, 0xdeadbeef


end_of_test:
    j    end_of_test

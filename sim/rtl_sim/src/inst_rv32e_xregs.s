#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_rv32e_xregs
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: RV32E UPPER-REGISTER BEHAVIOUR
#   This is a CONTRACT TEST. It locks in arvern's EMPIRICALLY-VERIFIED
#   (waveform-traced) handling of a SPEC-PERMITTED case -- it is NOT a spec
#   deviation.
#
#   Spec basis (RISC-V Unprivileged ISA, RV32E/RV64E section): all encodings
#   specifying registers x16..x31 are *reserved*. Reserved-encoding behaviour
#   is UNSPECIFIED -- the base ISA does NOT mandate an illegal-instruction
#   exception (it applies identically to rd/rs1/rs2 -- no source/dest
#   distinction). arvern's choice below is therefore permitted, the same
#   class as the reserved-OP/OP-IMM-funct7 case (see CLAUDE.md Known Spec
#   Deviations). A platform or profile MAY mandate trapping these
#   encodings; if arvern ever targets such a profile this contract flips
#   and param-gated decode-side trapping of x16..x31 must be added.
#
#   VERIFIED THREE-PART arvern RV32E CONTRACT (what this test asserts):
#
#   (1) PRIMARY GUARANTEE -- referencing x16..x31 (as rd, rs1 or rs2)
#   NEVER raises an illegal-instruction exception. trap_count MUST
#   remain 0. (Spec-permitted: reserved => UNSPECIFIED, no trap
#   mandated by the base ISA.)
#
#   (2) The architectural register file IS RV32E-aware: a read of an
#   upper register x16..x31 that is NOT satisfied by pipeline
#   forwarding yields 0 (there is no architectural storage for it).
#
#   (3) The decoder/forwarding network is NOT RV32E-aware: a write to an
#   upper register x_n (16<=n<=31) IMMEDIATELY followed by a read of
#   THE SAME x_n forwards the just-written value through the bypass
#   path. The value is a pure forwarding artefact -- it is NOT
#   persisted anywhere (no architectural x_n). Once the write leaves
#   the forwarding window, a later read of the same x_n reads 0.
#
#   In one line: regfile is RV32E-aware (non-forwarded read = 0) but
#   decode/forwarding is NOT (adjacent write->read of the same upper reg
#   forwards the written value; the value is not persisted).
#
#   Because the rv32e/ilp32e assembler REJECTS any mnemonic naming x16..x31
#   ("Error: illegal operands"), every instruction that names an upper
#   register is hand-encoded with a raw  .word  and a decoded comment.
#
#   HAND-ENCODED INSTRUCTION TABLE (ADDI is I-type: opcode=0x13, funct3=000;
#   layout = imm[11:0]<<20 | rs1<<15 | 000<<12 | rd<<7 | 0010011):
#
#   .word 0x12300813  addi x16, x0,  0x123  ; write -> non-existent x16
#   .word 0x00080293  addi x5,  x16, 0      ; read x16 immediately after
#   ;   -> FORWARDED -> x5=0x123
#   .word 0x000C0313  addi x6,  x24, 0      ; read x24, no in-flight write
#   ;   -> regfile -> x6=0
#   .word 0x000F8393  addi x7,  x31, 0      ; read x31 before any write
#   ;   -> regfile -> x7=0
#   .word 0x45600F93  addi x31, x0,  0x456  ; write -> non-existent x31
#   .word 0x000F8413  addi x8,  x31, 0      ; read x31 immediately after
#   ;   -> FORWARDED -> x8=0x456
#   <several x0..x15 NOPs -- push the x16 write out of the fwd window>
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#   0x00: trap_count   (MUST stay 0 -- no illegal-instruction trap)
#   0x04: last MCAUSE  (diagnostic only)
#=========================================================================

main:
    j _start

    #=================================================================
    # TRAP HANDLER  (only x0..x15; s1/x9 = scratchpad base)
    #
    # Saves t0/t1/t2 (x5/x6/x7) on the stack -- the main code's probe
    # results also land in x5..x9, so the handler must not clobber them.
    # Increments trap_count, records mcause, advances mepc past the
    # faulting instruction (2 or 4 bytes), then mret.
    #
    # NOTE on s1/x9: the discriminator probe writes x9, aliasing the
    # scratchpad-base register s1. Ordering guarantees this is safe:
    # all scratchpad I/O (zeroing, SYNC A) completes BEFORE the probe
    # sequence; in the contract-PASS case no trap fires after x9 is
    # clobbered so the handler never re-runs; in a contract-FAIL case
    # the trap is taken ON the faulting instruction (before x9 would be
    # written), so s1 still holds 0x80000000 and the handler works.
    #=================================================================
    .align 2

trap_handler:
    addi sp, sp, -12
    sw   t0,  8(sp)
    sw   t1,  4(sp)
    sw   t2,  0(sp)

    csrr t0, mcause
    csrr t1, mepc

    # trap_count++
    lw   t2, 0x00(s1)
    addi t2, t2, 1
    sw   t2, 0x00(s1)

    # record last mcause (diagnostic)
    sw   t0, 0x04(s1)

    # Advance mepc past the faulting instruction. All faulting
    # encodings here are 32-bit, but detect length generically:
    # if instr[1:0]==2'b11 -> 4-byte, else 2-byte.
    lhu  t2, 0(t1)
    andi t2, t2, 0x3
    li   t0, 0x3
    beq  t2, t0, advance_4
    addi t1, t1, 2
    j    exc_done
advance_4:
    addi t1, t1, 4
exc_done:
    csrw mepc, t1

    lw   t2,  0(sp)
    lw   t1,  4(sp)
    lw   t0,  8(sp)
    addi sp, sp, 12
    mret


    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000        # stack top (within SRAM)
    li   s1, 0x80000000        # x9 = scratchpad base

    # Zero scratchpad working area
    li   t0, 0
    sw   t0, 0x00(s1)          # trap_count = 0
    sw   t0, 0x04(s1)          # last mcause = 0

    # Install trap handler, enable MSTATUS.MIE
    la   t0, trap_handler
    csrw mtvec, t0
    li   t0, 0x8
    csrs mstatus, t0

    li   x15, 0x11111111       # <-- SYNC A: handler installed,
                               #     scratchpad trap_count zeroed.
                               #     (.v checks trap_count==0 only;
                               #      no result registers sampled here
                               #      -- that was the old race.)


    #=================================================================
    # PROBE SEQUENCE: hand-encoded upper-register accesses.
    # None of these may trap (trap_count stays 0).
    #
    # x5..x9 final values are FULLY determined by these instructions
    # (no pre-poison, no intermediate sync) so there is no sampling
    # race -- the .v reads them only at the FINAL sentinel.
    #=================================================================

    # (1) write 0x123 to non-existent x16 -> dropped, no trap
    .word 0x12300813           # addi x16, x0, 0x123

    # (2) read x16 IMMEDIATELY after the write -> value is FORWARDED
    #     through the bypass path: x5 == 0x00000123
    .word 0x00080293           # addi x5,  x16, 0

    # (3) read x24 -- NO in-flight write to x24 -> regfile yields 0:
    #     x6 == 0
    .word 0x000C0313           # addi x6,  x24, 0

    # (4) read x31 BEFORE any write to x31 -> regfile yields 0:
    #     x7 == 0
    .word 0x000F8393           # addi x7,  x31, 0

    # (5) write 0x456 to non-existent x31 -> dropped, no trap
    .word 0x45600F93           # addi x31, x0, 0x456

    # (6) read x31 IMMEDIATELY after its write -> value is FORWARDED:
    #     x8 == 0x00000456
    .word 0x000F8413           # addi x8,  x31, 0

    # (7) DISCRIMINATOR proving non-persistence. Several x0..x15-only
    #     NOPs (none touch x16) push the (1) write to x16 well out of
    #     the forwarding window. With NO intervening write to x16, the
    #     subsequent read of x16 must come from the (RV32E-aware)
    #     register file -> x9 == 0, even though step (2) saw 0x123.
    #     This cleanly separates "forwarded" from "persisted".
    nop                        # addi x0,x0,0  (0x00000013)
    nop
    nop
    nop

    .word 0x00080493           # addi x9,  x16, 0   -> x9 == 0

    li   x15, 0xdeadbeef       # <-- FINAL SYNC (level wait in .v)


end_of_test:
    nop
    j end_of_test              # infinite loop (testbench ends simulation)

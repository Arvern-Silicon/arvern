#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_haltreq_zcmp
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DEBUG HALTREQ during a Zcmp UOP sequence (Sdext)
#   A cm.push/cm.pop UOP is driven from DECODE (the micro-op sequencer), unlike a
#   DIV which vacates ID. While the sequence is in flight the decode stage can
#   present a STALE id_pc with id_instruction_valid high. If dpc latches that
#   stale PC on an async halt, resume RE-EXECUTES the whole cm.push -> a second
#   stack decrement and a doubled loop-body pass. This test makes that double-
#   execution observable TWO independent ways:
#
#     * SP balance:  every iteration is cm.push(-16) ... cm.pop(+16) == net 0, so
#                    the final SP must equal the initial SP. A replayed push
#                    leaves SP off by -16 (or a replayed pop, +16).
#     * Loop sum:    x14 = sum(i=1..64) = 0x820. The accumulator x14 and counter
#                    x13 are NOT in the push reglist {ra,s0,s1}, so cm.pop does
#                    not restore them; any replayed body pass corrupts the sum.
#
#   The async halt is applied several times at different offsets so at least one
#   lands mid-UOP across the timing variants.
#
#   Registers:
#     x14 : loop accumulator sum   (expect 0x00000820)
#     x11 : final SP - initial SP  (expect 0x00000000)
#     x5  : sentinel marker        (expect 0xA5A5A5A5)
#     x31 : sync (55555555=in loop C, 66666666=C done, deadbeef=test done)
#   Reglist {ra=x1, s0=x8, s1=x9} are saved/restored by the UOP; not checked.
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x5,  0xA5A5A5A5        # sentinel marker, must survive untouched
    li   x2,  0x80008000        # SP into SRAM (writable stack region)
    mv   x10, x2                # snapshot the initial SP
    li   x14, 0                 # accumulator sum
    li   x13, 1                 # counter i
    li   x15, 0x41             # N+1 = 65

    li   x31, 0x55555555        # sync C: halt me during the push/pop loop
loopC:
    cm.push {ra, s0-s1}, -16    # UOP: SP -= 16, store ra,s0,s1 (driven from decode)
    add  x14, x14, x13         # off-by-one detector (not in reglist -> not restored)
    addi x13, x13, 1
    cm.pop  {ra, s0-s1}, 16     # UOP: restore ra,s0,s1, SP += 16
    blt  x13, x15, loopC

    sub  x11, x2, x10          # SP delta: 0 unless a push/pop was replayed/skipped

    li   x31, 0x66666666        # sync: phase C complete

    li   x31, 0xdeadbeef        # final sync: test done

end_of_test:
    nop
    j    end_of_test           # infinite loop (testbench ends the simulation)

#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_haltreq_popret
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: debug entry across CM.POPRET must land on the RETURN target
#   cm.popret {ra}, 16 ends with a `ret`. Debug 1.0 sets dpc to "the next
#   instruction that should be executed", which after the popret is `ra`, never
#   the instruction physically behind it. The instruction behind every popret
#   here is a distinctive PAD (sets x16 to a failure marker, then `ret` so the
#   test still terminates) that must NEVER execute and must NEVER be named by
#   dpc / mepc.
#
#   PHASE 1  haltreq sweep: the leaf is called in a 200-iteration loop; each
#            iteration publishes a marker (x31=0x11111111) just before the
#            call and the testbench asserts haltreq a swept number of cycles
#            later, so the halt lands at every point of the iteration
#            including inside the popret. Per halt: dpc is either inside the
#            leaf (up to and including the popret) or inside the loop, never
#            the pad. Loop must complete: x13=200, x14=body count, SP balanced.
#   PHASE 2  single-step: the hart spins on spin2; the TB redirects it to
#            step_entry and steps {jalr, call, cm.push, addi, cm.popret}. The
#            dpc after the popret step must be step_ret (the return target).
#   PHASE 3a hart-side execute trigger (action=0, breakpoint) on &pad; four
#            calls of the leaf must raise NO breakpoint (x22 stays 0).
#   PHASE 3b debugger-armed execute trigger (action=1) on the return target
#            p3b_ret of a call: fires with dpc == &p3b_ret before the li runs.
#   PHASE 3c debugger-armed execute trigger (action=1) on &pad: two calls of
#            the leaf must NOT enter Debug Mode.
#
#   Registers (labels published for the testbench):
#     x2  sp (0x80008000)   x10 initial sp   x11 sp delta (expect 0, end)
#     x5  sentinel 0xA5A5A5A5              x16 pad failure marker (expect 0)
#     x13 loop iterations (expect 200)     x14 leaf body count (expect 208)
#     x15 loop bound (200)                 x22 unexpected-trap count (expect 0)
#     x12 spin base (rewritten by the TB)  x29 3b side effect (expect 0x3B3B3B3B)
#     x17 &leaf   x18 &pad   x19 &pad_end   x20 &loop   x21 &loop_end
#     x23 &spin2  x24 &step_entry  x25 &leaf_body  x26 &popret_pc  x27 &step_ret
#     x6  &spin3  x8  &p3b_entry   x28 &p3b_ret   x7 &spin4   x9 &p3c_entry
#     x3/x4 scratch for CSR setup
#     x31 sync: 55555555 setup done, 11111111 per-iteration marker (cleared to
#         0 after each return), 66666666 loop done (spin2), 77777777 step phase
#         done, 88888888 3a done (spin3), 99999999 3b done (spin4),
#         AAAAAAAA 3c done, deadbeef done
#----------------------------------------------------------------------------

.section .text
.global main
main:
    j    _start

    #---------------------------------------------------------------
    # Unexpected M-mode trap (phase 3a: a breakpoint on the pad that
    # must never fire). Count, disarm trigger 0, return (mepc unchanged).
    #---------------------------------------------------------------
    .align 2
handler_unexpected:
    addi x22, x22, 1
    csrw 0x7a1, x0              # disarm trigger 0 (tselect is 0)
    mret

    #---------------------------------------------------------------
    # The leaf under test. The pad behind the popret must never run.
    #---------------------------------------------------------------
    .align 2
leaf:
    cm.push {ra}, -16
leaf_body:
    addi x14, x14, 1            # body side effect (counted by the TB)
popret_pc:
    cm.popret {ra}, 16          # ends with ret -> the caller's return target
pad:
    li   x16, 0xBAD0BAD0        # FALL-THROUGH PAD: only reached if the return is dropped
    ret                         # (ra was reloaded by the pop) keep the test terminating
pad_end:

_start:
    csrsi 0x744, 8              # mnstatus.NMIE = 1 (then clear MDT: M-mode traps expected)
    csrw mstatush, x0           # Smdbltrp: MDT resets to 1
    li   x2,  0x80008000        # SP into SRAM
    mv   x10, x2                # snapshot the initial SP
    li   x5,  0xA5A5A5A5        # sentinel
    li   x13, 0                 # iteration counter
    li   x14, 0                 # leaf body count
    li   x15, 200               # iterations (the sweep's later halts consume several each)
    li   x16, 0                 # pad failure marker
    li   x22, 0                 # unexpected-trap count
    li   x29, 0                 # 3b side-effect target
    la   x17, leaf
    la   x18, pad
    la   x19, pad_end
    la   x20, loop
    la   x21, loop_end
    la   x23, spin2
    la   x24, step_entry
    la   x25, leaf_body
    la   x26, popret_pc
    la   x27, step_ret
    la   x6,  spin3
    la   x8,  p3b_entry
    la   x28, p3b_ret
    la   x7,  spin4
    la   x9,  p3c_entry
    la   x3,  handler_unexpected
    csrw mtvec, x3
    li   x3,  0x08
    csrw 0x7a5, x3              # tcontrol.mte = 1: M-mode triggers may fire
    li   x3,  0
    csrw 0x7a0, x3              # tselect = 0
    csrw 0x7a1, x0              # trigger 0 disabled

    li   x31, 0x55555555        # sync: setup done

    #=================================================================
    # PHASE 1: haltreq sweep across the call / popret loop
    #=================================================================
loop:
    li   x31, 0x11111111        # per-iteration marker: TB asserts haltreq N cycles later
    call leaf
ret_tgt:
    li   x31, 0
    addi x13, x13, 1
    blt  x13, x15, loop
loop_end:
    sub  x11, x2, x10           # SP delta after the loop (expect 0)

    #=================================================================
    # PHASE 2: single-step through the leaf
    #=================================================================
    la   x12, spin2
    li   x31, 0x66666666        # sync: loop done, spinning (TB halts us here)
spin2:
    jalr x0, 0(x12)             # TB rewrites x12 = &step_entry, sets dcsr.step
step_entry:
    call leaf                   # stepped: call, cm.push, addi, cm.popret
step_ret:
    li   x31, 0x77777777        # sync: step phase done (free run after step cleared)

    #=================================================================
    # PHASE 3a: hart-side breakpoint trigger on &pad must never fire
    #=================================================================
    li   x3,  0
    csrw 0x7a0, x3              # tselect = 0
    csrw 0x7a1, x0
    csrw 0x7a2, x18             # tdata2 = &pad
    li   x3,  0x60000044        # type6 | m | execute | match=0 | action=0
    csrw 0x7a1, x3              # ENABLE
    nop
    nop
    nop
    nop
    call leaf
    call leaf
    call leaf
    call leaf
    csrw 0x7a1, x0              # disarm
    la   x12, spin3
    li   x31, 0x88888888        # sync: 3a done, spinning (TB halts, arms 3b)
spin3:
    jalr x0, 0(x12)             # TB rewrites x12 = &p3b_entry

    #=================================================================
    # PHASE 3b: debugger-armed enter-Debug trigger on the return target
    #=================================================================
p3b_entry:
    call leaf
p3b_ret:
    li   x29, 0x3B3B3B3B        # fires BEFORE this executes (dpc == &p3b_ret)
    la   x12, spin4
    li   x31, 0x99999999        # sync: 3b done, spinning (TB halts, arms 3c)
spin4:
    jalr x0, 0(x12)             # TB rewrites x12 = &p3c_entry

    #=================================================================
    # PHASE 3c: debugger-armed enter-Debug trigger on &pad must never fire
    #=================================================================
p3c_entry:
    call leaf
    call leaf
    li   x31, 0xAAAAAAAA        # sync: 3c done (no Debug entry)

    sub  x11, x2, x10           # final SP delta (expect 0)
    li   x31, 0xdeadbeef        # final sync: test done
end_of_test:
    nop
    j    end_of_test

#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_trigger_ldst
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sdtrig LOAD/STORE DATA-ADDRESS watchpoint FIRING (Debug 1.0)
#   FIRING test for type=6 (mcontrol6) load/store data-address watchpoints
#   (select=0 ADDRESS match; data-VALUE match select=1 is out of scope). A
#   load/store watchpoint fires JUST BEFORE the matching access completes:
#     - a STORE does NOT modify memory at fire time
#     - a LOAD  does NOT update its destination register at fire time
#   Every firing phase proves this with a distinct sentinel: the watched word
#   still holds its PRE sentinel (store) / the dest reg still holds its PRE
#   sentinel (load) at the instant the trigger fires.
#
#   mcontrol6 (type=6) tdata1 bit layout used here:
#     [31:28]=type(6) [27]=dmode [19:16]=size [15:12]=action [10:7]=match
#     [6]=m [4]=s [3]=u [2]=execute [1]=store [0]=load   (select=0 => addr match)
#   size field {0=any,1=8b,2=16b,3=32b}; size=word => bits[19:16]=3 => 0x00030000.
#   Trigger CSRs: tselect 0x7a0, tdata1 0x7a1, tdata2 0x7a2, tcontrol 0x7a5.
#   tcontrol.mte (bit3) gates M-mode triggers (set =1). Hardware auto-clears mte
#   on M-trap entry and RESTORES it from mpte on mret -> M-mode triggers stay
#   live across phases without re-setting, but do NOT re-fire inside a handler.
#
#   tdata2 is the DATA address (not the instruction PC). dpc/mepc point at the
#   load/store INSTRUCTION; mtval = the accessed DATA address. The two are
#   distinct addresses -> the dpc/mepc==&instr check is a strong discriminator.
#
#   PHASES (single trigger, index 0, re-armed each phase):
#     1  (task B) LOAD watchpoint, action=1 (ENTER DEBUG), match=0 (equal),
#        size=any. Armed by the DEBUGGER while halted (action=1 needs dmode=1).
#        Firmware pre-loads tdata2=&B_DATA and x6=&b_lw, x5=PRE(0xBEEF0000), then
#        spins. On fire: hart auto-enters Debug, dcsr.cause=2, dpc=&b_lw, x5 still
#        PRE (load NOT taken). The .v disarms+resumes; b_lw then runs -> x5 loads
#        B_DATA (0x0B0B0B0B) -> scratch 0x50.
#     A  (task A) STORE watchpoint, action=0 (BREAKPOINT), match=0 (equal),
#        size=word. Fires -> mcause=3, mepc=&sw_A, mtval=&A_DATA; handler captures
#        A_DATA AT FIRE == sentinel 0x5A5A5A5A (store NOT taken), counts 1 trap,
#        disarms, mret -> the sw then runs (A_DATA=0xA5A5A5A5).
#     C  (task C) STORE watchpoint, action=0, match=1 (NAPOT 8B), size=any.
#        tdata2=base|0x3. Access base+4 (in range, addr != base) -> fires;
#        mtval=&c_word1(base+4) != base discriminates NAPOT from equal. mem@fire
#        == sentinel 0xC0C0C0C0 (store NOT taken).
#     D  (task D) SIZE negative. size=WORD store watchpoint must NOT fire on a
#        BYTE (sb) store to the SAME base address -> the byte store DID modify
#        memory (D_DATA low byte = 0x11). Only the access SIZE differs.
#     E  (task E) PRIV-GATING negative. m=0 (u=1) store watchpoint must NOT fire
#        on an M-mode store -> the store DID happen (E_DATA = 0xEEEE1111).
#     F  (task F) DISABLED/wrong-type negative. An execute-only trigger
#        (load=store=0) must NOT fire on a data STORE -> the store DID happen
#        (F_DATA = 0xFFFF2222).
#
#   Watched data lives at fixed SRAM addresses (well clear of the scratchpad and
#   the trap stack); handler scratch stores never touch a watched address.
#     B_DATA 0x80001000=0x0B0B0B0B  A_DATA 0x80001010=0x5A5A5A5A
#     c_blk  0x80001020 (NAPOT base) c_word1 0x80001024=0xC0C0C0C0
#     D_DATA 0x80001030=0xD0D0D0D0  E_DATA 0x80001040=0xE0E0E0E0
#     F_DATA 0x80001050=0xFFFF0000
#
#   Scratchpad (byte offsets from SRAM base 0x80000000):
#     0x00 A mcause(3)  0x04 A mepc      0x08 A mtval(&A_DATA) 0x0C A mem@fire(sent)
#     0x10 A counter(1) 0x14 &sw_A
#     0x18 C mcause(3)  0x1C C mepc      0x20 C mtval(&c_word1) 0x24 C mem@fire(sent)
#     0x28 C counter(1) 0x2C &sw_C
#     0x30 unexpected-trap counter (D/E/F, expect 0)
#     0x50 B x5 final (loaded B_DATA == 0x0B0B0B0B)
#
#   Registers:
#     s1 (x9)  scratchpad base      sp (x2) trap-handler stack
#     x5 (t0)  B load dest (PRE 0xBEEF0000 -> 0x0B0B0B0B; read by .v in Debug)
#     x6 (t1)  &b_lw (read by .v, compared to dpc)
#     a1 (x11) data pointer (survives traps)  a2 (x12) store value (survives traps)
#     a3 (x13) B load data pointer (&B_DATA)
#     x31 sync (11111111=phase-1 armed/spinning, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #---------------------------------------------------------------
    # Phase A handler: STORE watchpoint, action=0 (mcause=3). Captures
    # cause/epc/tval + watched word AT FIRE (must be PRE sentinel -> store
    # not taken), counts exactly 1 trap, disarms, mret -> the sw then runs.
    #---------------------------------------------------------------
    .align 2
handler_A:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    csrr t0, mcause
    sw   t0, 0x00(s1)          # expect 3 (breakpoint)
    csrr t0, mepc
    sw   t0, 0x04(s1)          # expect &sw_A (== 0x14 slot)
    csrr t0, mtval
    sw   t0, 0x08(s1)          # expect &A_DATA (= 0x80001010)
    li   t1, 0x80001010        # &A_DATA
    lw   t0, 0(t1)
    sw   t0, 0x0C(s1)          # A_DATA AT FIRE -> must be 0x5A5A5A5A (NOT 0xA5..)
    lw   t0, 0x10(s1)
    addi t0, t0, 1
    sw   t0, 0x10(s1)          # A trap counter (must end == 1)
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # disarm trigger 0
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #---------------------------------------------------------------
    # Phase C handler: STORE watchpoint, action=0, NAPOT match.
    #---------------------------------------------------------------
    .align 2
handler_C:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    csrr t0, mcause
    sw   t0, 0x18(s1)          # expect 3
    csrr t0, mepc
    sw   t0, 0x1C(s1)          # expect &sw_C (== 0x2C slot)
    csrr t0, mtval
    sw   t0, 0x20(s1)          # expect &c_word1 (= 0x80001024 = base+4, != base)
    li   t1, 0x80001024        # &c_word1
    lw   t0, 0(t1)
    sw   t0, 0x24(s1)          # c_word1 AT FIRE -> must be 0xC0C0C0C0 (NOT 0xC5..)
    lw   t0, 0x28(s1)
    addi t0, t0, 1
    sw   t0, 0x28(s1)          # C trap counter (must end == 1)
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0             # disarm
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret

    #---------------------------------------------------------------
    # Shared UNEXPECTED-trap handler for phases D/E/F. A watchpoint that
    # WRONGLY fires lands here; bump 0x30 (must end 0), disarm, and skip the
    # offending instruction so the test still terminates.
    #---------------------------------------------------------------
    .align 2
handler_unexpected:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    lw   t0, 0x30(s1)
    addi t0, t0, 1
    sw   t0, 0x30(s1)          # unexpected-trap counter (must end == 0)
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0             # disarm to avoid an infinite re-trap
    csrr t0, mepc
    addi t0, t0, 4             # skip offending (32-bit) instruction
    csrw mepc, t0
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16
    mret


_start:
    csrsi 0x744, 8            # Smdbltrp: a trap in M-mode with NMIE=0 is an unexpected trap
    csrw mstatush, x0        # MDT resets to 1; clear it or the first trap is an Smdbltrp double trap
    li   sp, 0x8000F000        # trap-handler stack
    li   s1, 0x80000000        # SRAM scratchpad base

    # Clear the counter slots the handlers accumulate into.
    li   t0, 0
    sw   t0, 0x10(s1)          # A counter
    sw   t0, 0x28(s1)          # C counter
    sw   t0, 0x30(s1)          # D/E/F unexpected counter

    # Initialise the watched data words with distinct sentinels.
    li   t0, 0x0B0B0B0B
    li   t1, 0x80001000
    sw   t0, 0(t1)             # B_DATA  (load source)
    li   t0, 0x5A5A5A5A
    li   t1, 0x80001010
    sw   t0, 0(t1)             # A_DATA  (store target sentinel)
    li   t0, 0xC0C0C0C0
    li   t1, 0x80001024
    sw   t0, 0(t1)             # c_word1 (NAPOT in-range sentinel)
    li   t0, 0xD0D0D0D0
    li   t1, 0x80001030
    sw   t0, 0(t1)             # D_DATA  (size-negative sentinel)
    li   t0, 0xE0E0E0E0
    li   t1, 0x80001040
    sw   t0, 0(t1)             # E_DATA  (priv-negative sentinel)
    li   t0, 0xFFFF0000
    li   t1, 0x80001050
    sw   t0, 0(t1)             # F_DATA  (exec-only-negative sentinel)

    # tcontrol.mte = 1 : enable M-mode triggers. Auto-cleared on each M-trap
    # entry and restored from mpte on mret (so it survives phases A and C).
    li   t0, 0x08
    csrw 0x7a5, t0


    #=================================================================
    # PHASE 1 (task B) : LOAD watchpoint, action=1 (ENTER DEBUG), equal.
    #   Firmware pre-loads tdata2=&B_DATA + x6=&b_lw + x5=PRE; the DEBUGGER
    #   (the .v) arms tdata1 (load|action=1|dmode=1|size=any) while halted.
    #=================================================================
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # tdata1 = 0 (disabled until debugger arms it)
    li   t1, 0x80001000
    csrw 0x7a2, t1             # tdata2 = &B_DATA (load DATA address)
    la   x6, b_lw              # x6 = &b_lw (debugger reads it, compares dpc)
    li   x5, 0xBEEF0000        # PRE load-dest sentinel (load not taken)
    li   a3, 0x80001000        # a3 = &B_DATA (load base pointer, survives)

    li   x31, 0x11111111       # sync: phase-1 pre-loaded; spin so debugger arms

    li   a0, 0
    li   a1, 0x00001000
spin1:
    addi a0, a0, 1
    blt  a0, a1, spin1
    # fall through to b_lw. With the debugger-armed action=1 load watchpoint,
    # the hart AUTO-ENTERS Debug Mode here BEFORE the lw updates x5.
    .align 2
b_lw:
    lw   x5, 0(a3)             # load B_DATA; fires BEFORE -> x5 stays PRE
    sw   x5, 0x50(s1)          # B x5 final (after disarm+resume == 0x0B0B0B0B)


    #=================================================================
    # PHASE A (task A) : STORE watchpoint, action=0 (BREAKPOINT), equal,
    #   size=WORD. Hart-side. Fires before the sw modifies A_DATA.
    #=================================================================
    la   t0, handler_A
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0             # tselect = 0
    csrw 0x7a1, x0             # disable while configuring
    li   t1, 0x80001010
    csrw 0x7a2, t1             # tdata2 = &A_DATA
    la   t1, sw_A
    sw   t1, 0x14(s1)          # &sw_A for .v mepc compare
    li   a1, 0x80001010        # a1 = &A_DATA  (survives the trap)
    li   a2, 0xA5A5A5A5        # a2 = store value (survives the trap)
    li   t0, 0x60030042        # type6 | store | size=word(3) | m | match=0 | action=0
    csrw 0x7a1, t0             # ENABLE -> live
    # Arming latency: a software-written (csrw) trigger does NOT affect the
    # immediately-following access -- give the enable a few instr of slack.
    nop
    nop
    nop
    nop
    .align 2
sw_A:
    sw   a2, 0(a1)             # fires BEFORE this store; A_DATA stays sentinel
    nop                        # (handler disarms + mret -> the sw runs now)


    #=================================================================
    # PHASE C (task C) : STORE watchpoint, action=0, NAPOT (8-byte range).
    #   tdata2 = base | 0x3 => range [base, base+7]. Access base+4 so the
    #   fire address (mtval) differs from base (discriminates NAPOT vs equal).
    #=================================================================
    la   t0, handler_C
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    li   t1, 0x80001023        # base 0x80001020 | 0x3 (NAPOT 8-byte)
    csrw 0x7a2, t1
    la   t1, sw_C
    sw   t1, 0x2C(s1)          # &sw_C for .v mepc compare
    li   a1, 0x80001024        # a1 = &c_word1 (= base+4, in range)
    li   a2, 0xC5C5C5C5        # a2 = store value
    li   t0, 0x600000C2        # type6 | store | size=any | m | match=1 (NAPOT) | action=0
    csrw 0x7a1, t0             # ENABLE
    nop
    nop
    nop
    nop
    .align 2
sw_C:
    sw   a2, 0(a1)             # access base+4: in range, addr != base
    nop                        # (handler disarms + mret -> the sw runs now)


    #=================================================================
    # PHASE D (task D) : SIZE negative. size=WORD store watchpoint must NOT
    #   fire on a BYTE store to the SAME base address -> sb DID modify memory.
    #=================================================================
    la   t0, handler_unexpected
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    li   t1, 0x80001030
    csrw 0x7a2, t1             # tdata2 = &D_DATA
    li   a1, 0x80001030        # same base address as tdata2 (only size differs)
    li   a2, 0x11
    li   t0, 0x60030042        # type6 | store | size=WORD | m | match=0 | action=0
    csrw 0x7a1, t0             # ENABLE
    nop
    nop
    nop
    nop
    sb   a2, 0(a1)             # BYTE store: size != word -> NO fire -> mem modified
    csrw 0x7a1, x0             # disarm


    #=================================================================
    # PHASE E (task E) : PRIV-GATING negative. m=0 (u=1) store watchpoint
    #   must NOT fire on an M-mode store -> the store DID happen.
    #=================================================================
    la   t0, handler_unexpected
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    li   t1, 0x80001040
    csrw 0x7a2, t1             # tdata2 = &E_DATA
    li   a1, 0x80001040
    li   a2, 0xEEEE1111
    li   t0, 0x6003000A        # type6 | store | size=word | u (m=0) | match=0 | action=0
    csrw 0x7a1, t0             # ENABLE (but m=0 -> no M-mode fire)
    nop
    nop
    nop
    nop
    sw   a2, 0(a1)             # M-mode store: m=0 -> NO fire -> mem modified
    csrw 0x7a1, x0             # disarm


    #=================================================================
    # PHASE F (task F) : DISABLED/wrong-type negative. An execute-only
    #   (load=store=0) trigger must NOT fire on a data STORE -> store happens.
    #=================================================================
    la   t0, handler_unexpected
    csrw mtvec, t0
    li   t0, 0
    csrw 0x7a0, t0
    csrw 0x7a1, x0
    li   t1, 0x80001050
    csrw 0x7a2, t1             # tdata2 = &F_DATA (a data addr, never an instr PC)
    li   a1, 0x80001050
    li   a2, 0xFFFF2222
    li   t0, 0x60000044        # type6 | m | execute (load=store=0)
    csrw 0x7a1, t0             # ENABLE (execute trigger -> no data-access match)
    nop
    nop
    nop
    nop
    sw   a2, 0(a1)             # data store: execute trigger ignores -> mem modified
    csrw 0x7a1, x0             # disarm


    li   x31, 0xdeadbeef       # final sync: test done

end_of_test:
    nop
    j    end_of_test

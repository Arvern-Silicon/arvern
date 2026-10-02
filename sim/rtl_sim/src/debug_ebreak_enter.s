#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_ebreak_enter
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: EBREAK enters Debug Mode when dcsr.ebreakm=1 (RISC-V Sdext)
#   The hart spins in a counted loop in M-mode. The testbench halts it over the
#   DMI bus (frozen-hart), abstract read-modify-writes dcsr (0x7b0) to SET
#   dcsr.ebreakm (bit 15) while PRESERVING dcsr.prv[1:0] (so the hart resumes in
#   M-mode), then resumes. After resume the firmware finishes the loop and
#   executes a forced 32-bit EBREAK in M-mode. With dcsr.ebreakm=1 that EBREAK
#   must ENTER Debug Mode (re-halt) rather than take the normal M-mode breakpoint
#   exception, and dpc must equal the address of the EBREAK instruction.
#
#   The EBREAK is emitted as a literal 32-bit word (.word 0x00100073) inside a
#   `.option norvc` block so it is NEVER compressed to c.ebreak — that keeps the
#   dpc-advance (dpc+4 to step over it) deterministic in both std and -c_mode
#   builds. Immediately before it, auipc+addi capture the EBREAK's own address
#   into x6 so the testbench can assert dpc == x6 precisely (auipc=4, addi=4, so
#   the EBREAK sits at capture_pc + 8).
#
#   x20 carries a GOOD sentinel (0x600D600D) set BEFORE the EBREAK. The mtvec
#   handler — only reachable if the EBREAK WRONGLY took the M-mode exception —
#   overwrites x20 with a poison value (0xBADBADBA) and terminates, so a broken
#   "ebreakm ignored" core fails the testbench's x20 check loudly.
#
#   Registers:
#     x5  : loop counter (frozen while halted)                 (t0)
#     x6  : address of the 32-bit EBREAK word (== dpc on re-halt)
#     x7  : loop bound
#     x18 : sentinel marker, must survive untouched (expect 0xA5A5A5A5)
#     x20 : ebreak-path witness (expect GOOD 0x600D600D; poison 0xBADBADBA = fail)
#     x31 : sync (11111111=spinning, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5         # sentinel marker, must survive untouched
    li   x20, 0x600D600D         # GOOD witness: the EBREAK must NOT reach mtvec

    la   x5,  mtrap_handler      # install M-mode trap vector (direct mode)
    csrw mtvec, x5

    li   x5,  0                  # loop counter (frozen while halted)
    li   x7,  0x00000200         # loop bound (halt lands mid-loop; short enough
                                 #   that the post-resume tail re-halts well inside
                                 #   the TB watchdog even under -rsalu/-rwsrom/-gahb)

    li   x31, 0x11111111         # sync: about to spin (TB halts us here)
spin:
    addi x5,  x5, 1
    blt  x5,  x7, spin           # count up to the bound (paused while halted)

    #-------------------------------------------------------------------
    # after resume: forced 32-bit EBREAK in M-mode. dcsr.ebreakm was set
    # by the TB while halted, so this EBREAK must ENTER Debug Mode (re-halt)
    # and park dpc AT the EBREAK address (captured in x6 just below).
    #-------------------------------------------------------------------
    .option push
    .option norvc                # force 4-byte auipc/addi so capture_pc+8 is exact
capture_pc:
    auipc x6, 0                  # x6 = address of this auipc (capture_pc)
    addi  x6, x6, 8              # x6 = capture_pc + 8 = address of the EBREAK word
the_ebreak:
    .word 0x00100073             # 32-bit EBREAK (never c.ebreak)
after_ebreak:
    .option pop

    # reached only on a clean resume past the EBREAK (TB wrote dpc = dpc + 4)
    li   x31, 0xdeadbeef         # final sync: test done
end_of_test:
    nop
    j    end_of_test             # infinite loop (testbench ends the simulation)

    #-------------------------------------------------------------------
    # M-mode trap handler: ONLY reached if the EBREAK wrongly took the
    # normal M-mode breakpoint exception (dcsr.ebreakm not honored).
    # Poison x20 and terminate so check_cpu_reg(20, GOOD) fails loudly.
    #-------------------------------------------------------------------
    .align 2
mtrap_handler:
    li   x20, 0xBADBADBA         # poison: EBREAK reached the M-mode handler
    li   x31, 0xdeadbeef         # terminate so the testbench flags the failure
mhang:
    j    mhang

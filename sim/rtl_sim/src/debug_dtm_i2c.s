#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dtm_i2c
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: END-TO-END external debug over a real I2C transport.
#   Unlike the debug_dmi_* tests (which drive the DMI APB bus directly), here the
#   testbench talks to the core's Debug Module through the arv_dtm I2C DTM over a
#   live two-wire link (shipping arv_dtm wrapper, DTM_TYPE=2 (I2C)). This firmware
#   is the debug TARGET: it seeds known state, then spins so the debugger can halt
#   it, poke GPRs/CSRs/memory, and resume.
#
#   The hart spins until released. Over the I2C link the TB:
#     - halts it (frozen hart);
#     - abstract-READs x18 (sentinel 0xA5A5A5A5);
#     - abstract-WRITEs x20 <- 0xCAFE0000;
#     - abstract-READs mscratch (0xC5A17E5C), then abstract-WRITEs mscratch <- 0x0BADF00D;
#     - SBA-writes 0x5BA00001 to [0x80004020] and reads it back;
#     - resumes.
#   After resume the firmware proves each write landed:
#     x20 += 0x123           -> 0xCAFE0123 (GPR write survived + hart resumed)
#     x21 = csrr mscratch    -> 0x0BADF00D (CSR write reached the CSR)
#     x22 = [0x80004020]     -> 0x5BA00001 (SBA write reached real memory)
#
#   Registers:
#     x7  : mscratch seed value                                (t2)
#     x10 : SBA scratch address 0x80004020                     (a0)
#     x18 : GPR-read sentinel        (expect 0xA5A5A5A5)
#     x20 : GPR-write target         (expect 0xCAFE0123)
#     x21 : mscratch read-back       (expect 0x0BADF00D)
#     x22 : SBA word read-back       (expect 0x5BA00001)
#     x31 : sync (11111111=spinning, deadbeef=done)
#----------------------------------------------------------------------------

.section .text
.global main
main:
    li   x18, 0xA5A5A5A5        # GPR-read sentinel (abstract read must return this)
    li   x20, 0                 # GPR-write target (TB injects 0xCAFE0000, fw += 0x123)
    li   x7,  0xC5A17E5C        # mscratch seed (abstract CSR read must return this)
    csrw mscratch, x7
    li   x10, 0x80004020        # SBA scratch address (TB SBA-writes here while halted)
    li   x21, 0                 # mscratch read-back slot
    li   x22, 0                 # SBA read-back slot

    li   x31, 0x11111111        # sync: about to spin (TB halts us here)
spin:
    # Spin until the debugger's abstract GPR write releases us. x20 starts 0; the
    # TB halts the (frozen) hart mid-spin, abstract-writes x20=0xCAFE0000, then
    # resumes -- so the loop falls through exactly once, on resume. This is
    # transport-timing-independent: the hart stays here no matter how slow the DTM
    # link is (a counted loop could finish before a slow debugger even halts it).
    beqz x20, spin

    # --- after resume: prove each debugger write actually landed ---
    addi x20, x20, 0x123        # -> final x20 = injected 0xCAFE0000 + 0x123 = 0xCAFE0123
    csrr x21, mscratch          # -> 0x0BADF00D (the abstract CSR write reached mscratch)
    lw   x22, 0(x10)            # -> 0x5BA00001 (the SBA write reached real memory)

    # Order the done-sentinel AFTER the (possibly wait-stated) load writeback.
    # x31 has no data dependency on x22, so without a barrier the pipeline can
    # retire "li x31,deadbeef" before a wait-stated "lw x22" commits, letting the
    # TB sample x22 too early (fails only under SRAM wait states). Deriving x31
    # from x22 forces the load-use interlock to hold the sentinel until x22 is
    # valid, and makes x31==0xdeadbeef *iff* the SBA word read back correctly.
    li   x31, 0x850DBEEE
    xor  x31, x31, x22          # 0x850DBEEE ^ 0x5BA00001 = 0xDEADBEEF (final sync: done)
end_of_test:
    nop
    j    end_of_test            # infinite loop (testbench ends the simulation)

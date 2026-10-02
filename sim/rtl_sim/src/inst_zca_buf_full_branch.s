#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_buf_full_branch
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
# Description: Taken branch while the fetch buffer is full.
#
#   arv_fetch stops fetching once the buffer will hold 5+ halfwords
#   (buf_will_be_full), EXCEPT while a branch is detected or pending. The arms
#   handling "new data arrives AND an instruction is consumed" in states 011111
#   (5 halfwords) and 111111 (6) sit inside that window.
#
#   Dense compressed code alone does not get there: the decoder keeps up, so the
#   buffer never runs more than 5 halfwords ahead. A multi-cycle divide does --
#   it stalls dispatch for ~33 cycles (DIV_TYPE=3, radix-2) while fetch keeps
#   filling, so the buffer saturates at six halfwords. The block then drains into
#   a taken branch, which is what re-opens fetch at that fill level.
#
#   The padding length varies per block so the branch is reached at several
#   different fill levels and 16-bit alignments rather than a single one.
#----------------------------------------------------------------------------
    .section .text
	.option norvc        # disable all compressed instructions in this section
    .global main

main:
	jal t0, _random_irq_init
	li  t0, 0

    #-------------------------------------------------
    # INITIAL REGISTER SETUP
    #-------------------------------------------------
    li  x5,  0           # blocks completed
    li  x6,  0           # accumulator, proves the padding actually executed
    li  x7,  0xCAFE0000  # sentinel that must survive every branch
    li  x28, 0           # count of taken branches

    li  x10, 0x0F0F0F0F  # divide operands: no early-out, full 33-cycle latency
    li  x11, 3

    li  x31, 0x11111111  # sync: setup done

.option rvc              # ---- compressed from here: 16-bit instruction stream ----

    #-------------------------------------------------
    # BLOCKS: stall dispatch on a divide so fetch fills the buffer, then drain N
    # compressed instructions into a taken branch.
    #-------------------------------------------------

    .macro PADBLK n, lbl
    div    x9, x10, x11           # ~33-cycle dispatch stall: fetch fills the buffer
    .rept \n
    c.addi x6, 1                  # 2-byte filler that also proves execution
    .endr
    c.addi x5, 1                  # block counter
    c.addi x28, 1                 # branch counter (branch below is always taken)
    c.j    \lbl                   # TAKEN branch with the buffer full
    .endm

    PADBLK 1, blk1
blk1:
    PADBLK 2, blk2
blk2:
    PADBLK 3, blk3
blk3:
    PADBLK 4, blk4
blk4:
    PADBLK 5, blk5
blk5:
    PADBLK 6, blk6
blk6:
    PADBLK 7, blk7
blk7:
    PADBLK 8, blk8
blk8:

    #-------------------------------------------------
    # Same again with a CONDITIONAL taken branch: c.beqz resolves in the decoder
    # rather than being an unconditional redirect, so the branch-pending window
    # differs from c.j above.
    #-------------------------------------------------
    .macro CBLK n, lbl
    div    x9, x10, x11
    .rept \n
    c.addi x6, 1
    .endr
    c.li   x8, 0                  # force the branch taken
    c.addi x5, 1
    c.addi x28, 1
    c.beqz x8, \lbl
    .endm

    CBLK 1, cbk1
cbk1:
    CBLK 3, cbk2
cbk2:
    CBLK 5, cbk3
cbk3:
    CBLK 7, cbk4
cbk4:

.option norvc            # ---- back to 32-bit instructions ----

    #-------------------------------------------------
    # BACKUP RESULTS
    #-------------------------------------------------
    addi x18, x5,  0     # blocks completed (expect 12)
    addi x19, x6,  0     # padding executed (expect 52)
    addi x20, x7,  0     # sentinel (expect 0xCAFE0000)
    addi x21, x28, 0     # taken branches (expect 12)

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop

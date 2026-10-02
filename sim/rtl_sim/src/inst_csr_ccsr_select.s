#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_csr_ccsr_select
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: custom-CSR select is zero outside a custom-CSR access
#
#   Mixes standard CSR accesses (mstatus, misa, mtval, mcycle, marv_ctl --
#   the core-owned 0x7FF inside custom bank 8) with custom-CSR writes and
#   reads (0x7C0, 0x7C1, 0x800). The testbench checks, every cycle, that
#   ccsr_reg_sel_o is zero whenever ccsr_bank_o is zero, so |ccsr_reg_sel_o
#   is a valid transaction qualifier, and that the custom accesses were seen.
#----------------------------------------------------------------------------

.section .text
.global main
main:
    jal   t0, _random_irq_init

    li    x31, 0xFFFFFFFF          # sync: init done

    csrr  x1, mstatus
    csrr  x16, misa
    li    x3, 0x5A5A0001
    csrw  mtval, x3                # mscratch is the IRQ handler's stack swap
    csrr  x4, mtval
    csrr  x5, mcycle
    csrr  x6, 0x7FF                # marv_ctl: core-owned, inside custom bank 8

    li    x7, 0x13572468
    csrw  0x7C0, x7
    li    x8, 0x0F0F0F0F
    csrw  0x7C1, x8
    li    x9, 0x00C0FFEE
    csrw  0x800, x9
    csrr  x10, 0x7C0
    csrr  x11, 0x7C1
    csrr  x12, 0x800
    csrs  0x7C1, x3                # read-modify-write through the IP
    csrr  x13, 0x7C1
    csrr  x14, mstatus

    li    x31, 0xdeadbeef
end_loop:
    j     end_loop

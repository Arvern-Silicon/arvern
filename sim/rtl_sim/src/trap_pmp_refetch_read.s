#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_refetch_read
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: the PMP-CSR refetch fires on writes only (see the .v)
#   Phase 1 (x31=0x11111111..0x22222222): 6 PMP CSR reads -- csrr, csrrs/csrrc
#   with rs1=x0, csrrsi/csrrci with uimm=0 -- no refetch.
#   Phase 2 (x31=0x22222222..0x33333333): 4 PMP CSR writes -- 4 refetches.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main
main:
    j    _start

_start:
    li   x31, 0x11111111        # phase 1: reads
    csrr   t0, pmpcfg0
    csrr   t0, pmpaddr0
    csrrs  t0, pmpaddr1, x0
    csrrc  t0, pmpaddr1, x0
    csrrsi t0, pmpcfg0, 0
    csrrci t0, 0x747, 0          # mseccfg
    nop
    nop
    li   x31, 0x22222222        # phase 2: writes
    csrw   pmpaddr3, x0
    csrrs  t0, pmpaddr3, x0
    li   t1, 0
    csrrs  t0, pmpaddr3, t1     # rs1 = t1 (value 0) still counts as a write
    csrrsi t0, pmpaddr3, 0
    csrrwi t0, pmpaddr3, 0
    csrrc  t0, pmpaddr3, t1
    nop
    nop
    li   x31, 0x33333333
    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test

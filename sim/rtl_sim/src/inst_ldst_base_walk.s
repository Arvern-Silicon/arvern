#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_ldst_base_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Load/store base-register walk -- every GPR x1..x31 as rs1
#
#   Unpriv 2.6: "Load and store instructions transfer a value between the
#   registers and memory. [...] The effective address is obtained by adding
#   register rs1 to the sign-extended 12-bit offset."
#
#   For each N in 1..31, xN alone is the base register of three accesses to
#   its own word W_N = 0x80000200 + 4N (value V_N = 0xC0DE0000 + N):
#     sw  xD, off(xN)        store V_N
#     lw  xL, off(xN)        load it back into another register
#     lw  xN, off(xN)        load it back into the base register itself
#   Both loaded values are copied to result words RES1_N / RES2_N through a
#   third register, so the bench checks memory only.
#
#   Offsets span the whole 12-bit range (-2048 .. +2044), negative and
#   positive. For sp and x8..x15 the offsets are small non-negative multiples
#   of 4 and the data registers are in x8..x15, so the -c_mode build emits
#   C.SWSP / C.LWSP / C.SW / C.LW for those bases.
#
#   x31 is the sync register: every value it takes during its own step is an
#   SRAM address or 0xC0DE001F, never a sync value.
#
#   Scratchpad (0x80000000):
#     0x200 + 4N   W_N    (expect V_N)
#     0x300 + 4N   RES1_N (xL, expect V_N)
#     0x380 + 4N   RES2_N (xN after lw xN, off(xN), expect V_N)
#----------------------------------------------------------------------------

.section .text
.global main

.equ W_BASE,    0x80000200
.equ RES1_BASE, 0x80000300
.equ RES2_OFF,  0x80

# n = base register, off = offset, d/l/r = data, load and result-pointer
# registers (all distinct from n).
.macro BASE_WALK n, off, d, l, r
    li   x\n, (W_BASE + (\n) * 4) - (\off)
    li   x\d, 0xC0DE0000 + (\n)
    li   x\l, 0x0BAD0000 + (\n)
    sw   x\d, \off(x\n)
    lw   x\l, \off(x\n)
    li   x\r, RES1_BASE + (\n) * 4
    sw   x\l, 0(x\r)
    lw   x\n, \off(x\n)
    sw   x\n, RES2_OFF(x\r)
.endm

main:
    jal  t0, _random_irq_init
    li   t0, 0

    # Clear the target and result words so a skipped access cannot pass.
    li   t0, W_BASE
    li   t1, 0x80000400
clr_loop:
    sw   zero, 0(t0)
    addi t0, t0, 4
    bne  t0, t1, clr_loop

    li   x31, 0x11111111            # Sync: start

    BASE_WALK  1,  -2048,  5,  6,  7
    BASE_WALK  2,      8,  5,  6,  7
    BASE_WALK  3,   2044,  5,  6,  7
    BASE_WALK  4,     -4,  5,  6,  7
    BASE_WALK  5,      0, 28, 29, 30
    BASE_WALK  6,     12, 28, 29, 30
    BASE_WALK  7,  -2048, 28, 29, 30
    BASE_WALK  8,      0,  9, 10,  5
    BASE_WALK  9,      4, 10, 11,  5
    BASE_WALK 10,      8, 11, 12,  5
    BASE_WALK 11,     16, 12, 13,  5
    BASE_WALK 12,     32, 13, 14,  5
    BASE_WALK 13,     64, 14, 15,  5
    BASE_WALK 14,    124, 15,  8,  5
    BASE_WALK 15,     60,  8,  9,  5
    BASE_WALK 16,   2044,  5,  6,  7
    BASE_WALK 17,    -12,  5,  6,  7
    BASE_WALK 18,      0,  5,  6,  7
    BASE_WALK 19,  -2048,  5,  6,  7
    BASE_WALK 20,   2044,  5,  6,  7
    BASE_WALK 21,      4,  5,  6,  7
    BASE_WALK 22,     -8,  5,  6,  7
    BASE_WALK 23,    100,  5,  6,  7
    BASE_WALK 24,   -100,  5,  6,  7
    BASE_WALK 25,      0,  5,  6,  7
    BASE_WALK 26,   2040,  5,  6,  7
    BASE_WALK 27,  -2044,  5,  6,  7
    BASE_WALK 28,      8,  5,  6,  7
    BASE_WALK 29,    -16,  5,  6,  7
    BASE_WALK 30,   1024,  5,  6,  7
    BASE_WALK 31,  -1024,  5,  6,  7

    li   t0, RES1_BASE
    lw   zero, RES2_OFF + 31 * 4(t0)    # last result store has landed
    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test

#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zihpm_multi_hi
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: ZIHPM MULTI-HI
#   Verifies mhpmcounterh (high-word) write and readback for all
#   implemented HPM counters (3 through 2+ZIHPM_NR).
#
#   Each counter's high word is written with a distinct pattern:
#   mhpmcounterh(3+i) = 0xA0000000 | (3+i)
#
#   ZIHPM_NR is discovered at runtime from mimpid[23:20].
#
#   Requires: ZIHPM_NR >= 1
#   no_random_irq: true
#
#   Scratchpad layout (base 0x80000000):
#   0x00: mimpid readback (bits[23:20] = ZIHPM_NR)
#   Per counter i (i=0 → counter3, i=7 → counter10):
#   0x04 + i*4: hi_readback_i — mhpmcounterh(3+i) readback
#   (expect 0xA0000000|(3+i) if implemented)
#----------------------------------------------------------------------------

.section .text
.global main

# CSR addresses
.equ MCOUNTINHIBIT, 0x320
.equ MIMPID,        0xF13

# mcountinhibit: all HPM counters inhibited simultaneously
.equ INH_ALL_HPM,   0x7F8   # bits [10:3]


main:
    jal  t0, _random_irq_init        # enable random IRQ injection

    li   sp, 0x80010000
    li   s1, 0x80000000              # s1 = scratchpad base
    li   s2, 0x80000004              # s2 = first counter result word

    # Zero 9 words of scratchpad (mimpid + 8 counter hi results)
    li   t0, 9
    li   t2, 0x80000000
zero_loop:
    sw   x0, 0(t2)
    addi t2, t2, 4
    addi t0, t0, -1
    bnez t0, zero_loop

    # Inhibit all HPM counters to prevent counting during writes
    li   t0, INH_ALL_HPM
    csrrs x0, MCOUNTINHIBIT, t0

    # Read mimpid; extract ZIHPM_NR from bits[23:20]
    csrr t0, MIMPID
    sw   t0, 0x00(s1)                # mimpid readback
    lw   t3, 0x00(s1)                # AHB fence
    srli s3, t0, 20
    andi s3, s3, 0xF                 # s3 = ZIHPM_NR (0-8)

    li   x31, 0x11111111             # Sync: mimpid written
    beqz s3, skip_to_done            # ZIHPM_NR=0: nothing to test


    #=================================================================
    # Counter 3  (ZIHPM_NR >= 1, guaranteed here)
    #=================================================================
    li   t0, 0xA0000003
    csrw 0xB83, t0                   # mhpmcounterh3
    csrr t0, 0xB83
    sw   t0, 0x04(s1)
    lw   t3, 0x04(s1)                # AHB fence

    #=================================================================
    # Counter 4  (ZIHPM_NR >= 2)
    #=================================================================
    li   t0, 2
    blt  s3, t0, write_done
    li   t0, 0xA0000004
    csrw 0xB84, t0                   # mhpmcounterh4
    csrr t0, 0xB84
    sw   t0, 0x08(s1)
    lw   t3, 0x08(s1)

    #=================================================================
    # Counter 5  (ZIHPM_NR >= 3)
    #=================================================================
    li   t0, 3
    blt  s3, t0, write_done
    li   t0, 0xA0000005
    csrw 0xB85, t0                   # mhpmcounterh5
    csrr t0, 0xB85
    sw   t0, 0x0C(s1)
    lw   t3, 0x0C(s1)

    #=================================================================
    # Counter 6  (ZIHPM_NR >= 4)
    #=================================================================
    li   t0, 4
    blt  s3, t0, write_done
    li   t0, 0xA0000006
    csrw 0xB86, t0                   # mhpmcounterh6
    csrr t0, 0xB86
    sw   t0, 0x10(s1)
    lw   t3, 0x10(s1)

    #=================================================================
    # Counter 7  (ZIHPM_NR >= 5)
    #=================================================================
    li   t0, 5
    blt  s3, t0, write_done
    li   t0, 0xA0000007
    csrw 0xB87, t0                   # mhpmcounterh7
    csrr t0, 0xB87
    sw   t0, 0x14(s1)
    lw   t3, 0x14(s1)

    #=================================================================
    # Counter 8  (ZIHPM_NR >= 6)
    #=================================================================
    li   t0, 6
    blt  s3, t0, write_done
    li   t0, 0xA0000008
    csrw 0xB88, t0                   # mhpmcounterh8
    csrr t0, 0xB88
    sw   t0, 0x18(s1)
    lw   t3, 0x18(s1)

    #=================================================================
    # Counter 9  (ZIHPM_NR >= 7)
    #=================================================================
    li   t0, 7
    blt  s3, t0, write_done
    li   t0, 0xA0000009
    csrw 0xB89, t0                   # mhpmcounterh9
    csrr t0, 0xB89
    sw   t0, 0x1C(s1)
    lw   t3, 0x1C(s1)

    #=================================================================
    # Counter 10  (ZIHPM_NR >= 8)
    #=================================================================
    li   t0, 8
    blt  s3, t0, write_done
    li   t0, 0xA000000A
    csrw 0xB8A, t0                   # mhpmcounterh10
    csrr t0, 0xB8A
    sw   t0, 0x20(s1)
    lw   t3, 0x20(s1)

write_done:
    # Restore all hi counters to 0 and clear inhibit
    csrw 0xB83, x0
    csrw 0xB84, x0
    csrw 0xB85, x0
    csrw 0xB86, x0
    csrw 0xB87, x0
    csrw 0xB88, x0
    csrw 0xB89, x0
    csrw 0xB8A, x0

    li   t0, INH_ALL_HPM
    csrrc x0, MCOUNTINHIBIT, t0     # clear inhibit on all HPM counters

    li   x31, 0xAAAAAAAA             # Sync: all write/readback done

skip_to_done:
    li   x31, 0xdeadbeef             # Sync: all done

end_of_test:
    j    end_of_test

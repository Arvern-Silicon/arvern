#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      debug_dm_reset_midrun
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Debug Module reset (dbgresetn) asserted while the hart runs
#   and an SBA transfer is in flight
#   debug_interface.md §4: "dbgresetn_i resets the Debug Module only
#   (dmcontrol/dmstatus/abstract engine/SBA/APB bus)"; "hresetn_i resets the
#   hart".
#
#   The firmware runs a load/increment/store loop over a 16-word SRAM_X array
#   (so the hart contends with SBA for the shared data port) until the
#   debugger sets a release flag over SBA. Every iteration adds 1 to one
#   word and to x21, so on exit sum(array) must equal x21 (x20 = sum): a
#   lost, duplicated or corrupted hart access breaks the equality.
#   The RNMI vector (reset_vector+4) and the trap vector count unexpected
#   events; both counts must stay 0.
#
#   SRAM (0x80000000): 0x100 release flag, 0x104 RNMI count, 0x108 trap
#   count, 0x200..0x23F the array.
#   Registers: s1 SRAM base, x20 array sum, x21 iteration count, x28 handler
#   scratch, x31 sync (11111111 = looping, deadbeef = done).
#----------------------------------------------------------------------------

.section .text
.global main

.option norvc

main:
    j    _start                    # reset_vector
    j    nmi_handler               # reset_vector+4: marv_nmvec reset value
    j    trap_handler              # reset_vector+8: mtvec reset value

nmi_handler:
    lw   x28, 0x104(s1)
    addi x28, x28, 1
    sw   x28, 0x104(s1)
    .word 0x70200073               # mnret

trap_handler:
    lw   x28, 0x108(s1)
    addi x28, x28, 1
    sw   x28, 0x108(s1)
    csrr x28, mepc
    addi x28, x28, 4
    csrw mepc, x28
    mret

_start:
    la   t0, trap_handler
    csrw mtvec, t0
    csrsi 0x744, 8                 # Smdbltrp boot: mnstatus.NMIE = 1 ...
    csrw mstatush, x0              # ... then mstatush.MDT = 0
    li   s1, 0x80000000
    sw   zero, 0x100(s1)
    sw   zero, 0x104(s1)
    sw   zero, 0x108(s1)
    li   t0, 0
clr:
    add  t1, s1, t0
    sw   zero, 0x200(t1)
    addi t0, t0, 4
    li   t2, 64
    blt  t0, t2, clr

    li   x20, 0
    li   x21, 0
    li   x31, 0x11111111
loop:
    andi t0, x21, 15
    slli t0, t0, 2
    add  t0, t0, s1
    lw   t1, 0x200(t0)
    addi t1, t1, 1
    sw   t1, 0x200(t0)
    addi x21, x21, 1
    lw   t2, 0x100(s1)
    beq  t2, x0, loop

    li   t0, 0
sum:
    add  t1, s1, t0
    lw   t2, 0x200(t1)
    add  x20, x20, t2
    addi t0, t0, 4
    li   t3, 64
    blt  t0, t3, sum

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test

#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_bus_error
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: data-bus error is reported as an RNMI (mncause=3), not mcause=5/7
#   THE CORE S4 TEST. A load to an unmapped address used to raise a synchronous
#   load access fault (mcause=5). It now raises a RESUMABLE NMI with
#   mncause = 0x80000003, and the marv_e* registers carry the evidence.
#
#   mcause 5/7 are RESERVED and must NOT be raised here.
#
#   Checks:
#     - the NMI fires exactly once for one faulting access
#     - mncause  = 0x80000003 (bit31 interrupt, cause 3 = bus error)
#     - marv_epc = PC of the faulting load  (WHAT faulted)
#     - mnepc   != marv_epc                 (WHERE to resume -- the load retired)
#     - marv_eaddr = the faulting address
#     - marv_estat = 0x01: valid, load, not uop-sourced, not restartable
#     - mtvec is never entered (no synchronous exception at all)
#
#   NMIE resets to 0 and masks every interrupt, so boot code must set it before
#   any of this can be delivered. A bus error raised before that is not lost --
#   it stays in the pending flop and fires when NMIE is set.
#
#   Scratchpad (base 0x80000000):
#   0x00 nmi_handler_addr   0x04 nmi_count     0x08 mncause     0x0C mnepc
#   0x10 marv_epc           0x14 marv_eaddr    0x18 marv_estat  0x1C pc of the lw
#   0x20 mcause seen by mtvec (must stay 0 -- mtvec must never be entered)
#   0x24 estat after 2nd fault  0x28 marv_epc after 2nd (== 0x10)
#   0x2C estat after W1C        0x30 estat after a STORE fault
#----------------------------------------------------------------------------

.equ MARV_ESTAT,     0x7FE
.equ MARV_EPC,       0xFFC
.equ MARV_EADDR,     0xFFD
.equ MNSTATUS,       0x744
.equ MNEPC,          0x741
.equ MNCAUSE,        0x742

.equ FAULT_ADDR,     0x00000000      # unmapped in the tb AHB decoder
.equ FAULT_ADDR_B,   0x00000010      # unmapped, distinct from FAULT_ADDR

.include "firmware_config.inc"

.section .text
.global main

main:
    j _start

    #=================================================================
    # RNMI handler -- records the evidence and resumes via mnret.
    #=================================================================
    .align 2
nmi_handler:
    li   s1, 0x80000000

    lw   t0, 0x04(s1)               # nmi_count++
    addi t0, t0, 1
    sw   t0, 0x04(s1)

    csrr t0, MNCAUSE
    sw   t0, 0x08(s1)
    csrr t0, MNEPC
    sw   t0, 0x0C(s1)

    csrr t0, MARV_EPC
    sw   t0, 0x10(s1)
    csrr t0, MARV_EADDR
    sw   t0, 0x14(s1)
    csrr t0, MARV_ESTAT
    sw   t0, 0x18(s1)
    lw   zero, 0x18(s1)             # read-back: force the stores to land

    .word 0x70200073                # mnret

    #=================================================================
    # mtvec handler -- must NEVER be entered. Records mcause if it is.
    #=================================================================
    .align 4
mtvec_handler:
    li   s1, 0x80000000
    csrr t0, mcause
    sw   t0, 0x20(s1)
    lw   zero, 0x20(s1)
    csrr t0, mepc                   # skip the offending instruction and carry on
    addi t0, t0, 4
    csrw mepc, t0
    mret

_start:
    li   sp, 0x80010000
    li   s1, 0x80000000

    sw   zero, 0x00(s1)
    sw   zero, 0x04(s1)
    sw   zero, 0x08(s1)
    sw   zero, 0x0C(s1)
    sw   zero, 0x10(s1)
    sw   zero, 0x14(s1)
    sw   zero, 0x18(s1)
    sw   zero, 0x1C(s1)
    sw   zero, 0x20(s1)
    sw   zero, 0x24(s1)
    sw   zero, 0x28(s1)
    sw   zero, 0x2C(s1)
    sw   zero, 0x30(s1)

    la   t0, mtvec_handler
    csrw mtvec, t0

    # Publish the RNMI handler address; the testbench drives nmi_vector from it.
    la   t0, nmi_handler
    csrw 0x7FD, t0            # marv_nmvec = RNMI handler (firmware places its own vector)
    sw   t0, 0x00(s1)
    lw   zero, 0x00(s1)

    li   x31, 0x11111111            # Sync: handler address published

    # Wait for the testbench to program nmi_vector before arming NMIE.
    li   t0, 20
wait_vec:
    addi t0, t0, -1
    bnez t0, wait_vec

    csrsi MNSTATUS, 8               # mnstatus.NMIE = 1

    li   x31, 0x22222222            # Sync: NMIE armed

    #---------------------------------------------------------------
    # The faulting access. Under S4 this raises an RNMI, NOT mcause=5.
    #---------------------------------------------------------------
    la   t2, fault_lw
    sw   t2, 0x1C(s1)               # the PC marv_epc must report
    lw   zero, 0x1C(s1)

    li   t0, FAULT_ADDR
fault_lw:
    lw   t1, 0(t0)                  # bus error -> RNMI (mncause=3)

    # Give the asynchronous report time to be delivered and handled.
    li   t0, 40
settle:
    addi t0, t0, -1
    bnez t0, settle

    li   x31, 0x33333333            # Sync: fault delivered

    #---------------------------------------------------------------
    # PHASE 2: a SECOND fault while marv_estat.valid is still set.
    #          FIRST-FAULT-WINS: overrun sets, marv_epc must NOT move.
    #---------------------------------------------------------------
    li   t0, FAULT_ADDR_B
fault_lw2:
    lw   t1, 0(t0)

    li   t0, 40
settle2:
    addi t0, t0, -1
    bnez t0, settle2

    csrr t3, MARV_ESTAT
    sw   t3, 0x24(s1)
    csrr t4, MARV_EPC               # must still be fault_lw, not fault_lw2
    sw   t4, 0x28(s1)
    lw   zero, 0x28(s1)

    li   x31, 0x44444444            # Sync: overrun captured

    #---------------------------------------------------------------
    # PHASE 3: W1C -- clear valid and overrun, estat must read 0
    #---------------------------------------------------------------
    li   t0, 0x5                    # bit0 valid | bit2 overrun
    csrw MARV_ESTAT, t0
    csrr t3, MARV_ESTAT
    sw   t3, 0x2C(s1)
    lw   zero, 0x2C(s1)

    li   x31, 0x55555555            # Sync: W1C done

    #---------------------------------------------------------------
    # PHASE 4: a STORE bus error -- the store bit must be 1
    #---------------------------------------------------------------
    li   t0, FAULT_ADDR
fault_sw:
    sw   zero, 0(t0)

    li   t0, 40
settle3:
    addi t0, t0, -1
    bnez t0, settle3

    csrr t3, MARV_ESTAT
    sw   t3, 0x30(s1)
    lw   zero, 0x30(s1)

    li   x31, 0x66666666            # Sync: store fault captured

    li   x31, 0xdeadbeef

end_of_test:
    nop
    j    end_of_test

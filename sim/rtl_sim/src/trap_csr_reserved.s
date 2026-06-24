#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_csr_reserved
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: CSR RESERVED VALUES
#   Verify reserved CSR field handling:
#   Phase 2: MTVEC MODE=2 (reserved) -> masked to MODE=0
#   Phase 3: MTVEC MODE=3 (reserved) -> masked to MODE=1
#   Phase 4: STVEC MODE=2 (reserved) -> masked to MODE=0
#   Phase 5: STVEC MODE=3 (reserved) -> masked to MODE=1
#   Phase 6: MSTATUS.MPP=2'b10 (reserved) -> keeps old value
#----------------------------------------------------------------------------

.section .text
.global main

#=========================================================================
# SRAM scratchpad layout (base 0x80000000)
#
#   Phase 2: MTVEC MODE=2
#     0x020: MTVEC after writing MODE=2
#
#   Phase 3: MTVEC MODE=3
#     0x030: MTVEC after writing MODE=3
#
#   Phase 4: STVEC MODE=2
#     0x040: STVEC after writing MODE=2
#
#   Phase 5: STVEC MODE=3
#     0x050: STVEC after writing MODE=3
#
#   Phase 6: MPP reserved value
#     0x060: MSTATUS before (MPP should be current value)
#     0x064: MSTATUS after writing MPP=2'b10
#=========================================================================

main:
    j _start

 _start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x20(s1)
    sw   t0, 0x30(s1)
    sw   t0, 0x40(s1)
    sw   t0, 0x50(s1)
    sw   t0, 0x60(s1)
    sw   t0, 0x64(s1)

    # Initialize callee-saved registers
    li   s2, 0xAAAAAAAA
    li   s3, 0xBBBBBBBB
    li   s4, 0xCCCCCCCC
    li   s5, 0xDDDDDDDD
    li   s6, 0xEEEEEEEE

    li   x31, 0x11111111


    #=================================================================
    # PHASE 2: MTVEC MODE=2 (reserved) -> should read back as MODE=0
    #=================================================================

    # Save current MTVEC base, then write with MODE=2
    csrr t0, mtvec
    li   t1, ~0x3
    and  t0, t0, t1            # Keep BASE, clear MODE
    ori  t0, t0, 0x2           # Set MODE=2 (reserved)
    csrw mtvec, t0

    # Read back
    csrr t0, mtvec
    sw   t0, 0x20(s1)

    # Restore MTVEC to direct mode for safety
    li   t1, ~0x3
    and  t0, t0, t1
    csrw mtvec, t0

    li   x31, 0x22222222


    #=================================================================
    # PHASE 3: MTVEC MODE=3 (reserved) -> should read back as MODE=1
    #=================================================================

    csrr t0, mtvec
    li   t1, ~0x3
    and  t0, t0, t1
    ori  t0, t0, 0x3           # Set MODE=3 (reserved)
    csrw mtvec, t0

    csrr t0, mtvec
    sw   t0, 0x30(s1)

    # Restore
    li   t1, ~0x3
    and  t0, t0, t1
    csrw mtvec, t0

    li   x31, 0x33333333


    #=================================================================
    # PHASE 4: STVEC MODE=2 (reserved) -> should read back as MODE=0
    #=================================================================

    csrr t0, stvec
    li   t1, ~0x3
    and  t0, t0, t1
    ori  t0, t0, 0x2
    csrw stvec, t0

    csrr t0, stvec
    sw   t0, 0x40(s1)

    # Restore
    li   t1, ~0x3
    and  t0, t0, t1
    csrw stvec, t0

    li   x31, 0x44444444


    #=================================================================
    # PHASE 5: STVEC MODE=3 (reserved) -> should read back as MODE=1
    #=================================================================

    csrr t0, stvec
    li   t1, ~0x3
    and  t0, t0, t1
    ori  t0, t0, 0x3
    csrw stvec, t0

    csrr t0, stvec
    sw   t0, 0x50(s1)

    # Restore
    li   t1, ~0x3
    and  t0, t0, t1
    csrw stvec, t0

    li   x31, 0x55555555


    #=================================================================
    # PHASE 6: MSTATUS.MPP = 2'b10 (reserved) -> should keep old value
    #=================================================================

    # First set MPP to a known value (M-mode = 2'b11)
    li   t0, 0x1800
    csrs mstatus, t0

    # Read MSTATUS before
    csrr t0, mstatus
    sw   t0, 0x60(s1)

    # Try to write MPP = 2'b10 (reserved)
    # Clear MPP first, then set bit 12 only (= 2'b10)
    li   t0, 0x1800
    csrc mstatus, t0           # Clear MPP to 00
    li   t0, 0x1000
    csrs mstatus, t0           # Set bit 12 -> MPP = 2'b10

    # Read MSTATUS after
    csrr t0, mstatus
    sw   t0, 0x64(s1)

    # Restore MPP to M-mode
    li   t0, 0x1800
    csrs mstatus, t0

    li   x31, 0x66666666


    #=================================================================
    # END OF TEST
    #=================================================================
end_of_test:
    j    end_of_test

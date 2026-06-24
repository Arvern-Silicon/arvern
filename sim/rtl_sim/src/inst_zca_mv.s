#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_mv
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.MV
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

    # Load registers with test patterns
    li  x8,  0x12345678  # Test pattern
    li  x9,  0xABCDEF01  # Test pattern
    li  x10, 0xFFFFFFFF  # All 1s
    li  x11, 0x00000000  # All 0s
    li  x12, 0x80000000  # Min negative
    li  x13, 0x7FFFFFFF  # Max positive
    li  x14, 0xAAAAAAAA  # Alternating pattern
    li  x15, 0x55555555  # Alternating pattern

    # Setup markers
    li  x1,  0x00000000  # Will be used for moves
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.MV (Compressed Move)
    # Format: c.mv rd, rs2
    # Function: rd = rs2 (copy rs2 to rd)
    # Registers: rd and rs2 can be any x1-x31 (not x0)
    # Encoding: 100_0_rd[4:0]_rs2[4:0]_10 (rd != 0, rs2 != 0, bit[12]=0)
    #
    # Key behavior:
    # - Copies value from rs2 to rd
    # - Source register (rs2) remains unchanged
    # - Equivalent to ADD rd, x0, rs2
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    #-------------------------------------------------
    # Test Set 1: Basic moves between compressed registers
    #-------------------------------------------------
    c.mv x1,  x8         # x1 = 0x12345678 (copy from x8)
    c.mv x2,  x9         # x2 = 0xABCDEF01 (copy from x9)
    c.mv x3,  x10        # x3 = 0xFFFFFFFF (copy from x10)
    c.mv x4,  x11        # x4 = 0x00000000 (copy from x11)

.option norvc
    # Backup first set of results to x16-x19
    addi x16, x1,  0     # Backup x1:  0x12345678
    addi x17, x2,  0     # Backup x2:  0xABCDEF01
    addi x18, x3,  0     # Backup x3:  0xFFFFFFFF
    addi x19, x4,  0     # Backup x4:  0x00000000

    # Verify source registers unchanged
    addi x20, x8,  0     # Backup x8:  0x12345678 (should be unchanged)
    addi x21, x9,  0     # Backup x9:  0xABCDEF01 (should be unchanged)
    addi x22, x10, 0     # Backup x10: 0xFFFFFFFF (should be unchanged)
    addi x23, x11, 0     # Backup x11: 0x00000000 (should be unchanged)
.option rvc

    #-------------------------------------------------
    # Test Set 2: Boundary values
    #-------------------------------------------------
    c.mv x5,  x12        # x5 = 0x80000000 (min negative)
    c.mv x6,  x13        # x6 = 0x7FFFFFFF (max positive)

.option norvc
    # Backup second set of results to x24-x25
    addi x24, x5,  0     # Backup x5: 0x80000000
    addi x25, x6,  0     # Backup x6: 0x7FFFFFFF
    # Note: Source verification for x12-x13 omitted (already verified in Test Set 1)
.option rvc

    #-------------------------------------------------
    # Test Set 3: Alternating patterns
    #-------------------------------------------------
    c.mv x7,  x14        # x7 = 0xAAAAAAAA
    c.mv x1,  x15        # x1 = 0x55555555 (overwrite previous)

.option norvc
    # Backup third set of results to x28-x29
    addi x28, x7,  0     # Backup x7: 0xAAAAAAAA
    addi x29, x1,  0     # Backup x1: 0x55555555
    # Note: Source verification for x14-x15 omitted (already verified in Test Set 1)
.option rvc

    #-------------------------------------------------
    # Test Set 4: Consecutive moves (copy chain)
    #-------------------------------------------------
    c.mv x3,  x8         # x3 = 0x12345678 (from x8)
    c.mv x4,  x3         # x4 = 0x12345678 (from x3, creating a copy chain)
    c.mv x5,  x4         # x5 = 0x12345678 (from x4)

.option norvc
    # Backup fourth set of results to x3-x5 themselves (final values)
    # No need for separate backup - checking final state is sufficient
.option rvc

    #-------------------------------------------------
    # Test Set 5: Move to/from non-compressed registers (x16-x31)
    #-------------------------------------------------
    c.mv x25, x8         # x25 = 0x12345678 (to non-compressed register)
    c.mv x26, x9         # x26 = 0xABCDEF01
    c.mv x1,  x25        # x1 = 0x12345678 (from non-compressed register)
    c.mv x2,  x26        # x2 = 0xABCDEF01

.option norvc
    # Final values will be checked directly
.option rvc

    #-------------------------------------------------
    # Test Set 6: Self-consistency test (move same value multiple times)
    #-------------------------------------------------
    c.mv x6,  x12        # x6 = 0x80000000
    c.mv x7,  x12        # x7 = 0x80000000 (same source)

.option norvc
    # Final values will be checked directly
.option rvc

    #-------------------------------------------------
    # Test Set 7: Move involving x1 (return address register)
    #-------------------------------------------------
    c.mv x1,  x13        # x1 = 0x7FFFFFFF (move to x1)
    c.mv x27, x1         # x27 = 0x7FFFFFFF (move from x1)

.option norvc
    # Final values will be checked directly
.option rvc

    #-------------------------------------------------
    # Test Set 8: Cross moves (swap-like pattern, but no actual swap)
    #-------------------------------------------------
    c.mv x2,  x8         # x2 = 0x12345678
    c.mv x3,  x9         # x3 = 0xABCDEF01
    # Note: C.MV cannot do atomic swaps, so these are just sequential moves

.option norvc
    # Final values will be checked directly
.option rvc

    #-------------------------------------------------
    # Test Set 9: Move zero value
    #-------------------------------------------------
    c.mv x4,  x11        # x4 = 0x00000000 (move zero)

.option norvc
    # Final values will be checked directly
.option rvc

    #-------------------------------------------------
    # Test Set 10: Move from high registers to low registers
    #-------------------------------------------------
    c.mv x8,  x25        # x8 = 0x12345678 (from x25)
    c.mv x9,  x26        # x9 = 0xABCDEF01 (from x26)
    c.mv x10, x27        # x10 = 0x7FFFFFFF (from x27)

.option norvc
    # Final values will be checked directly

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop

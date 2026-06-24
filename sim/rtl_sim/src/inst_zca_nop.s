#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_nop
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.NOP
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

    li  x1,  0x12345678
    li  x2,  0xDEADBEEF
    li  x3,  0xCAFEBABE
    li  x4,  0xABCDEF01
    li  x5,  0x11223344
    li  x6,  0x55667788
    li  x7,  0x99AABBCC
    li  x8,  0xDDEEFF00
    li  x9,  0x12341234
    li  x10, 0x56785678
    li  x11, 0x9ABC9ABC
    li  x12, 0xDEF0DEF0
    li  x13, 0x13571357
    li  x14, 0x24682468
    li  x15, 0x369C369C
    li  x16, 0x48D048D0
    li  x17, 0x5A5A5A5A
    li  x18, 0x6B6B6B6B
    li  x19, 0x7C7C7C7C
    li  x20, 0x8D8D8D8D
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.NOP (Compressed No Operation)
    # Format: c.nop
    # Encoding: c.addi x0, 0 (000_0_00000_00000_01)
    # Function: No operation - does not modify any state
    # This is a HINT instruction
    #-------------------------------------------------
.option rvc          # enable compressed instructions

    # Execute multiple C.NOP instructions
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop

    # Signal checkpoint 1
.option norvc
    li  x31, 0xBBBBBBBB
.option rvc

    # Mix C.NOP with actual operations to ensure they don't interfere
    c.nop
    c.li  x21, 10        # x21 = 10
    c.nop
    c.nop
    c.addi x21, 5        # x21 = 15
    c.nop
    c.nop
    c.li  x22, -7        # x22 = -7
    c.nop
    c.nop

    # More NOPs in sequence
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop

    # Signal checkpoint 2
.option norvc
    li  x31, 0xCCCCCCCC
.option rvc

    # Test C.NOP between memory operations
.option norvc
    li  x29, 0x80000010  # SRAM base
.option rvc
    c.nop
    c.li  x23, 21        # x23 = 21 (within C.LI range: -32 to +31)
    c.nop
.option norvc
    sw   x23, 0(x29)     # Store to SRAM
.option rvc
    c.nop
    c.nop
.option norvc
    lw   x24, 0(x29)     # Load from SRAM
.option rvc
    c.nop

    # Final sequence of NOPs
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop
    c.nop

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31, 0xDEADBEEF

end_of_test:
    nop
    j end_of_test     # infinite loop

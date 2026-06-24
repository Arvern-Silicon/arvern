#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_zca_addi4spn
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: C.ADDI4SPN
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

    li  x1,  0xDEADBEEF  # marker value
    li  x2,  0x20000000  # sp - stack pointer base
    nop

    # Signal initial setup complete
    li  x31, 0xAAAAAAAA
    nop

    #-------------------------------------------------
    # TEST C.ADDI4SPN (Compressed Add Immediate 4*SP Non-zero)
    # Format: c.addi4spn rd', uimm
    # Function: rd' = sp + zero_extended(uimm)
    # Immediate range: 4 to 1020 (10-bit unsigned, multiple of 4)
    # rd' restricted to x8-x15 (compressed registers)
    #-------------------------------------------------
.option rvc          # re-enable compressed instructions

    # Test all compressed destination registers (x8-x15) with various immediates
    c.addi4spn  x8,  sp, 4      # x8  = sp + 4
    c.addi4spn  x9,  sp, 8      # x9  = sp + 8
    c.addi4spn  x10, sp, 12     # x10 = sp + 12
    c.addi4spn  x11, sp, 16     # x11 = sp + 16
    c.addi4spn  x12, sp, 20     # x12 = sp + 20
    c.addi4spn  x13, sp, 24     # x13 = sp + 24
    c.addi4spn  x14, sp, 28     # x14 = sp + 28
    c.addi4spn  x15, sp, 32     # x15 = sp + 32

.option norvc
    # Backup first set of values to x16-x23
    addi x16, x8,  0            # Backup x8
    addi x17, x9,  0            # Backup x9
    addi x18, x10, 0            # Backup x10
    addi x19, x11, 0            # Backup x11
    addi x20, x12, 0            # Backup x12
    addi x21, x13, 0            # Backup x13
    addi x22, x14, 0            # Backup x14
    addi x23, x15, 0            # Backup x15
.option rvc

    # Test various immediate values (must be multiples of 4)
    c.addi4spn  x8,  sp, 64     # x8  = sp + 64
    c.addi4spn  x9,  sp, 128    # x9  = sp + 128
    c.addi4spn  x10, sp, 256    # x10 = sp + 256
    c.addi4spn  x11, sp, 512    # x11 = sp + 512

    # Boundary value tests
    c.addi4spn  x12, sp, 4      # Minimum non-zero immediate (4)
    c.addi4spn  x13, sp, 1020   # Maximum immediate (1020)

    # Additional alignment test
    c.addi4spn  x14, sp, 100    # x14 = sp + 100

.option norvc

    #-------------------------------------------------
    # END OF TEST
    #-------------------------------------------------

    li  x31,  0xdeadbeef

end_of_test:
    nop
    j end_of_test     # infinite loop


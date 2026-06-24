#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      sandbox
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Sandbox playground for ad-hoc experimentation (no automated check; intended for interactive use).
#----------------------------------------------------------------------------

.section .text
.global main

main:


    li  x1, 0xcafebabe    # Dividend
    li  x2, 0x01010101    # Divisor

    #li  x1, 753    # Dividend
    #li  x2, 234    # Divisor

    li  x3, 0
    li  x4, 0
    li  x5, 0
    li  x6, 0
    nop
    div    x3, x1, x2
    divu   x4, x1, x2
    rem    x5, x1, x2
    remu   x6, x1, x2
    nop

#Expected --> cafebabe/01010101 -- DIV=ffffffcc DIVU=000000ca REM=ff32eef2 REMU=0033eff4


    /* Base operands */
    #li     x5,  0xcafebabe   # op1:  3
    #li     x6,  0xcafebabe   # op2: -2

    /* First group */
    #div    x10, x5, x6       # res: 0xFFFFFFFA  (OP1_signed   * OP2_signed  )
    #divu   x11, x5, x6       # res: 0xFFFFFFFF  (OP1_signed   * OP2_signed  )
    #rem    x12, x5, x6       # res: 0x00000002  (OP1_signed   * OP2_unsigned)
    #remu   x13, x5, x6       # res: 0x00000002  (OP1_unsigned * OP2_unsigned)
    #li     x1,  1


	#-------------------------------------------------
	# END OF TEST 
	#-------------------------------------------------

 	li  x31,  0xdeadbeef

end_of_test:
	nop
    j end_of_test   # infinite loop



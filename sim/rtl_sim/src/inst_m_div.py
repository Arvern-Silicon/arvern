#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_m_div
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: DIV, DIVU, REM, REMU
#----------------------------------------------------------------------------

test_values = [
                0x00000000,  # 0
                0x00000001,  # 1
                0xffffffff,  # -1
                0x00000002,  # 2
                0xfffffffe,  # -2
                0x7fffffff,  # INT32_MAX
                0x80000000,  # INT32_MIN
                0x80000001,  # INT32_MIN+1
                0x12345678,  # random
                0x87654321,  # random large
                0x0000ffff,  # small
                0xffff0000,  # negative pattern
                0x40000000,  # large positive power-of-two
                0xc0000000,  # large negative power-of-two
                0x7f7f7f7f,  # pattern
                0x80808080,  # pattern
                0x13579bdf,  # random odd
                0x2468ace0,  # random even
                0x00007fff,  # near 32k
                0xffff8000,  # near -32k
                0x01010101,  # small repetitive
                0xf0f0f0f0,  # alternating
                0xdeadbeef,  # classic test
                0xcafebabe,  # classic test
]

INT_MIN = -2**31
INT_MAX =  2**31 - 1

#=======================================================================================
#
# UTILITY FUNCTIONS
#
#=======================================================================================

def to_signed32(x):
    x &= 0xFFFFFFFF
    return x if x < 0x80000000 else x - 0x100000000

def to_unsigned32(x):
    return x & 0xFFFFFFFF

def div_signed(a, b):
    if b == 0:
        return -1
    if a == INT_MIN and b == -1:
        return INT_MIN
    return int(a / b)  # Python truncates toward 0

def rem_signed(a, b):
    if b == 0:
        return a
    if a == INT_MIN and b == -1:
        return 0
    return a - b * int(a / b)

def div_unsigned(a, b):
    ua = to_unsigned32(a)
    ub = to_unsigned32(b)
    if ub == 0:
        return 0xFFFFFFFF
    return ua // ub

def rem_unsigned(a, b):
    ua = to_unsigned32(a)
    ub = to_unsigned32(b)
    if ub == 0:
        return ua
    return ua % ub


#=======================================================================================
#
# MAIN
#
#=======================================================================================
def main():
    for i, va in enumerate(test_values):
        for j, vb in enumerate(test_values):
            a_s = to_signed32(va)
            b_s = to_signed32(vb)

            divres  = div_signed(a_s, b_s)
            divures = div_unsigned(va, vb)
            remres  = rem_signed(a_s, b_s)
            remures = rem_unsigned(va, vb)

            operation     = "{0}/{1}".format(a_s, b_s)

            operation_hex = "32'h{0:08x}, 32'h{1:08x}".format(a_s & 0xFFFFFFFF, b_s & 0xFFFFFFFF)
            divres_hex    = "32'h{0:08x}".format(divres  & 0xFFFFFFFF)
            divures_hex   = "32'h{0:08x}".format(divures & 0xFFFFFFFF)
            remres_hex    = "32'h{0:08x}".format(remres  & 0xFFFFFFFF)
            remures_hex   = "32'h{0:08x}".format(remures & 0xFFFFFFFF)

            line = "      check_mem_results( {0:2d},{1:2d}, {2}, {3}, {4}, {5}, {6} ); // {7:25}, {8:10}, {9:10}, {10:10}, {11:10}".format(i, j, operation_hex, divres_hex, divures_hex, remres_hex, remures_hex, operation, divres, divures, remres, remures)
            print(line)
        print()


if __name__ == "__main__":
    main()

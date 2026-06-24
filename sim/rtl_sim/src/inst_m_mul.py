#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      inst_m_mul
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MUL/MULH/MULHSU/MULHU
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

MASK32 = 0xFFFFFFFF
INT_SIZE = 2**32

#=======================================================================================
#
# UTILITY FUNCTIONS
#
#=======================================================================================

def to_signed32(x):
    """Converts a 32-bit unsigned integer (as seen in memory) to a Python signed integer."""
    x &= MASK32
    return x if x < 0x80000000 else x - INT_SIZE

def to_unsigned32(x):
    """Ensures the value is treated as a 32-bit unsigned integer."""
    return x & MASK32

def mul_signed(a_s, b_s):
    """Calculates the full 64-bit signed product of two 32-bit signed numbers."""
    return a_s * b_s

def mul_unsigned(a_u, b_u):
    """Calculates the full 64-bit unsigned product of two 32-bit unsigned numbers."""
    return a_u * b_u

def mul_signed_unsigned(a_s, b_u):
    """Calculates the full 64-bit product of a 32-bit signed (A) and 32-bit unsigned (B)."""
    return a_s * b_u


#=======================================================================================
#
# MAIN
#
#=======================================================================================
def main():
    print("// Expected results for RISC-V 32x32 Multiplication (MUL, MULH, MULHSU, MULHU)")
    print("//----------------------------------------------------------------------------------------------------------------------------------------------------------------")
    print("// Index  | Op1(hex) | Op2(hex) | MUL (Low)  | MULH (High S*S) | MULHSU (High S*U) | MULHU (High U*U) | Operation (Signed/Unsigned)")
    print("//----------------------------------------------------------------------------------------------------------------------------------------------------------------")

    for i, va in enumerate(test_values):
        for j, vb in enumerate(test_values):
            # 32-bit representations needed for calculation
            a_s = to_signed32(va)
            b_s = to_signed32(vb)
            a_u = va # Already unsigned 32-bit
            b_u = vb # Already unsigned 32-bit

            # --- Signed * Signed (MUL, MULH) ---
            full_signed = mul_signed(a_s, b_s)
            
            # MUL: Low 32 bits of signed product
            mul_low_res = full_signed & MASK32
            
            # MULH: High 32 bits of signed product
            mulh_high_res = (full_signed >> 32) & MASK32

            # --- Signed * Unsigned (MULHSU) ---
            full_signed_unsigned = mul_signed_unsigned(a_s, b_u)
            
            # MULHSU: High 32 bits of (Signed A * Unsigned B)
            mulhsu_high_res = (full_signed_unsigned >> 32) & MASK32
            
            # --- Unsigned * Unsigned (MULHU) ---
            full_unsigned = mul_unsigned(a_u, b_u)

            # MULHU: High 32 bits of unsigned product
            mulhu_high_res = (full_unsigned >> 32) & MASK32

            # Output Formatting
            op1_hex_str   = "32'h{0:08x}".format(va)
            op2_hex_str   = "32'h{0:08x}".format(vb)
            mul_res_hex   = "32'h{0:08x}".format(mul_low_res)
            mulh_res_hex  = "32'h{0:08x}".format(mulh_high_res)
            mulhsu_res_hex= "32'h{0:08x}".format(mulhsu_high_res)
            mulhu_res_hex = "32'h{0:08x}".format(mulhu_high_res)

            operation_str = "{0:11} * {1:11} || {2:11} * {3:11} || {4:11} * {5:11}".format(a_s, b_s, a_s, b_u, a_u, b_u)

            # Example check function format for verification purposes
            line = "      check_mem_results( {0:2d}, {1:2d}, {2}, {3}, {4}, {5}, {6}, {7} ); // {8:25}".format(
                i, j, 
                op1_hex_str, op2_hex_str, 
                mul_res_hex, mulh_res_hex, mulhsu_res_hex, mulhu_res_hex, 
                operation_str
            )
            print(line)
        print()


if __name__ == "__main__":
    main()

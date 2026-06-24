#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      TEST_TEMPLATE
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: Skeleton template for new tests (intentionally NOT registered in run_config.json so it never runs in regression).
#----------------------------------------------------------------------------

.section .text
.global main
main:
    jal t0, _random_irq_init    # Enable random IRQ injection (omit for trap_* tests)
    li  t0, 0

    # Initialize all registers to known values (e.g., 0xFFFFFFFF)
    li  x1, 0xFFFFFFFF
    ...
    li  x31, 0xFFFFFFFF         # <-- First sync point: "init done"

    # Perform test operations, store results in registers
    li    x1, 10
    li    x2, 20
    add   x3, x1, x2            # Result in x3

    # For complex tests, add intermediate sync points with distinct values
    # (0x11111111, 0x22222222, ...) to check results between sections.

    li  x31, 0xdeadbeef         # <-- Final sync: "test done"

end_of_test:
    nop
    j end_of_test               # Infinite loop (testbench ends simulation)

#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    setup_lib_example
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : setup_lib_example.tcl
# Module Description : Library setup: example/reference library configuration.
#----------------------------------------------------------------------------

namespace eval lib_example {

    # Worst case library
    variable LIB_WC_FILE   "<YOUR WORST CASE LIBRARY FILE>.db"
    variable LIB_WC_NAME   "<YOUR WORST CASE LIBRARY NAME>"

    # Best case library
    variable LIB_BC_FILE   "<YOUR BEST CASE LIBRARY FILE>.db"
    variable LIB_BC_NAME   "<YOUR BEST CASE LIBRARY NAME>"

    # Operating conditions
    variable LIB_WC_OPCON  "<YOUR WORST CASE OP-CON>"
    variable LIB_BC_OPCON  "<YOUR BEST CASE OP-CON>"

    # Wire-load model
    variable LIB_WIRE_LOAD "<YOUR WIRELOAD MODEL>"

    # Nand2 gate name for area size calculation
    variable NAND2_NAME    "<YOUR SMALLEST NAND2 CELL NAME>"

    # Clock period (ns) — overrides constraints.tcl value
    variable CLOCK_PERIOD  <YOU TARGET CLOCK PERIOD IN NS>;  # e.g., 10.0 for 100 MHz
}

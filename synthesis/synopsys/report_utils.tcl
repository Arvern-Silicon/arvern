#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    report_utils
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : report_utils.tcl
# Module Description : Shared TCL helpers used by the report_* scripts.
#----------------------------------------------------------------------------

##############################################################################
#                                                                            #
#                        REPORT UTILITIES LIBRARY                            #
#                                                                            #
#  Common utility procedures for generating formatted synthesis reports     #
#                                                                            #
##############################################################################

##############################################################################
# Procedure: combine_reports_side_by_side
#
# Description:
#   Combines two text blocks (reports) side by side with specified spacing.
#   Both text blocks are split into lines, padded to equal length, and
#   concatenated horizontally.
#
# Arguments:
#   left_text    - The text block to appear on the left side
#   right_text   - The text block to appear on the right side
#   left_width   - Width to pad the left column (default: 85 characters)
#   spacing      - Number of spaces between left and right columns (default: 3)
#
# Returns:
#   Combined text with left and right blocks side by side
#
# Example:
#   set combined [combine_reports_side_by_side $TIMING_ANALYSIS $TIMING_HISTOGRAM 85 3]
#
##############################################################################
proc combine_reports_side_by_side {left_text right_text {left_width 85} {spacing 3}} {
    # Split both text blocks into lines
    set left_lines [split $left_text "\n"]
    set right_lines [split $right_text "\n"]

    # Pad both to the same length
    set max_len [expr max([llength $left_lines], [llength $right_lines])]
    while {[llength $left_lines] < $max_len} {
        lappend left_lines ""
    }
    while {[llength $right_lines] < $max_len} {
        lappend right_lines ""
    }

    # Combine side by side with spacing
    set combined ""
    set space_str [string repeat " " $spacing]

    for {set i 0} {$i < $max_len} {incr i} {
        set left_line [lindex $left_lines $i]
        set right_line [lindex $right_lines $i]

        # Pad left line to fixed width
        set left_padded [format "%-${left_width}s" $left_line]

        append combined "$left_padded$space_str$right_line\n"
    }

    return $combined
}

#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    read
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : read.tcl
# Module Description : Read, analyze, elaborate and link the RTL design (top = arvern).
#----------------------------------------------------------------------------

##############################################################################
#                                                                            #
#                               READ DESING RTL                              #
#                                                                            #
##############################################################################

set DESIGN_NAME      "arvern"

if {[info exists ::env(DESIGN_NAME)]} {
    set DESIGN_NAME $::env(DESIGN_NAME)
}

# RTL_SOURCE_FILES (+ RTL_INCDIRS) come from submit_syn.tcl, auto-generated
# by `flatten_filelist.py --format tcl` from rtl/verilog/filelist.f (the
# single source of truth shared with the simulation flow).
source ./submit_syn.tcl

set_svf ./results/$DESIGN_NAME.svf
define_design_lib WORK -path ./WORK
analyze -format verilog $RTL_SOURCE_FILES

# Source RTL parameters (auto-generated from run_config.json)
if {[file exists ./rtl_params.tcl]} {
    puts "Loading RTL parameters from rtl_params.tcl..."
    source ./rtl_params.tcl
    # Elaborate with parameters - build command string for proper expansion
    puts "Elaborating with parameters:"
    puts "  $ELABORATE_PARAMS"
    set elab_cmd "elaborate $DESIGN_NAME $ELABORATE_PARAMS"
    eval $elab_cmd

    # DC appends parameters to design name - rename it back to original
    set elaborated_design [get_object_name [current_design]]
    puts "Design elaborated as: $elaborated_design"
    if {$elaborated_design != $DESIGN_NAME} {
        puts "Renaming design from $elaborated_design to $DESIGN_NAME"
        rename_design $elaborated_design $DESIGN_NAME
    }
} else {
    puts "WARNING: rtl_params.tcl not found - elaborating with default parameters"
    puts "Run 'python3 gen_rtl_params.py' to generate from run_config.json"
    elaborate $DESIGN_NAME
}

link


# Check design structure after reading verilog
current_design $DESIGN_NAME
redirect ./results/report.check {check_design}

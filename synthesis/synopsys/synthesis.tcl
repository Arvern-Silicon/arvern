#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    synthesis
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : synthesis.tcl
# Module Description : Top-level Design Compiler synthesis flow: read RTL, compile, DFT insertion, reports, netlist dump.
#----------------------------------------------------------------------------

#=============================================================================#
#                                Configuration                                #
#=============================================================================#

# Enable/Disable DC_ULTRA option
set WITH_DC_ULTRA 1

# Enable/Disable DFT insertion
set WITH_DFT      1


#=============================================================================#
#                           Read technology library                           #
#=============================================================================#
source -echo -verbose ./library.tcl


#=============================================================================#
#                               Read design RTL                               #
#=============================================================================#
source -echo -verbose ./read.tcl

# Dissolve the arv_dff register-primitive wrappers up front
#
# Why this matters (measured): every flop in the design is an arv_dff instance whose
# body is "else if (en_i) q<=d_i". If arv_dff is left as a boundary and only ungrouped
# DURING compile (set_ungroup), DC maps each one to the larger native load-enable scan
# cell before merging context which will unnecessarily increase area.
# Flattening here instead lets DC pick the best cell per flop from the full library.
# See doc/synthesis_guide.md.
current_design $DESIGN_NAME
set _dff_cells [get_cells -quiet -hierarchical -filter "ref_name =~ arv_dff*"]
set _n_dff     [sizeof_collection $_dff_cells]
ungroup -flatten $_dff_cells
puts "arv_dff: early-ungrouped $_n_dff register-primitive instances (pre-compile)."


#=============================================================================#
#                           Set design constraints                            #
#=============================================================================#
source -echo -verbose ./constraints.tcl


#=============================================================================#
#              Set operating conditions & wire-load models                    #
#=============================================================================#

# Set operating conditions
set_operating_conditions -max $LIB_WC_OPCON -max_library $LIB_WC_NAME \
	                     -min $LIB_BC_OPCON -min_library $LIB_BC_NAME

# Set wire-load models
set_wire_load_mode top
set_wire_load_model -name $LIB_WIRE_LOAD -max -library $LIB_WC_NAME
set_wire_load_model -name $LIB_WIRE_LOAD -min -library $LIB_BC_NAME


#=============================================================================#
#                                Synthesize                                   #
#=============================================================================#

# Prevent assignment statements in the Verilog netlist.
set_fix_multiple_port_nets -all -buffer_constants

# Configuration
current_design $DESIGN_NAME
uniquify
set_max_area  0.0
set_flatten false
set_structure true -timing true -boolean true

# Verify constraints before synthesis
redirect -tee -file ./results/report.check_timing_pre {check_timing}

# Synthesis
if {$WITH_DC_ULTRA} {
    if {$WITH_DFT} {
        compile_ultra -scan -no_autoungroup
    } else {
        compile_ultra       -no_autoungroup
    }

    # Area optimization (run after compile)
    optimize_netlist -area

    # Check if timing met after area optimization
    if {[sizeof_collection [get_timing_paths -slack_lesser_than 0.0 -max_paths 1]] > 0} {
        puts "WARNING: Timing violated after area optimization. Re-optimizing for timing..."
        compile_ultra -incremental
    }

} else {
    if {$WITH_DFT} {
        compile -scan -map_effort high -area_effort high
    } else {
        compile       -map_effort high -area_effort high
    }
}


#=============================================================================#
#                                DFT Insertion                                #
#=============================================================================#
if {$WITH_DFT} {

    # DFT Signal Type Definitions
    #set_dft_signal -view spec         -type ScanEnable  -port scan_enable_i -active_state 1
    #set_dft_signal -view existing_dft -type ScanEnable  -port scan_enable_i -active_state 1
    #set_dft_signal -view spec         -type Constant    -port scan_mode_i   -active_state 1
    #set_dft_signal -view existing_dft -type Constant    -port scan_mode_i   -active_state 1
    set_dft_signal -view existing_dft -type ScanClock   -port hclk_i        -timing [list 45 55]

    # hresetn_i is only an ASYNCHRONOUS reset when ASYNC_RST_EN=1. Declare it as a
    # DFT Reset (a control held inactive during scan shift) ONLY in that case. With
    # synchronous reset (ASYNC_RST_EN=0) hresetn_i is an ordinary data-path signal:
    # the scan mux bypasses it during shift, so it needs no async-reset DFT handling,
    # and declaring it as one is wrong (it steers scan/incremental-compile toward
    # async-reset cells -> a few stray async flops in an otherwise-sync netlist).
    # RTL_PARAM_ASYNC_RST_EN comes from rtl_params.tcl via read.tcl; default async.
    set _dft_arst 1
    if {[info exists RTL_PARAM_ASYNC_RST_EN]} { set _dft_arst $RTL_PARAM_ASYNC_RST_EN }
    if {$_dft_arst} {
        set_dft_signal -view existing_dft -type Reset   -port hresetn_i     -active 0
    } else {
        puts "DFT: synchronous reset (ASYNC_RST_EN=0) -- hresetn_i NOT declared as an async Reset."
    }

    # DFT Configuration
    set_dft_insertion_configuration -preserve_design_name true
    set_scan_configuration -style multiplexed_flip_flop
    set_scan_configuration -clock_mixing mix_clocks
    set_scan_configuration -chain_count 3

    # DFT Test Protocol Creation
    create_test_protocol

    # DFT Design Rule Check
    redirect -tee -file ./results/report.dft_drc           {dft_drc}
    redirect      -file ./results/report.dft_drc_verbose   {dft_drc -verbose}
    redirect      -file ./results/report.dft_drc_coverage  {dft_drc -coverage_estimate}
    redirect      -file ./results/report.dft_scan_config   {report_scan_configuration}
    redirect      -file ./results/report.dft_insert_config {report_dft_insertion_configuration}

    # Preview DFT insertion
    redirect -tee -file ./results/report.dft_preview       {preview_dft}
    redirect      -file ./results/report.dft_preview_all   {preview_dft -show all -test_points all}

    # DFT insertion
    insert_dft

    # DFT Incremental Compile
    if {$WITH_DC_ULTRA} {
	    compile_ultra -scan -incremental
    } else {
	    compile       -scan -incremental
    }

    # DFT Coverage estimate
    redirect      -file ./results/report.dft_drc_coverage  {dft_drc -coverage_estimate}
}

#=============================================================================#
#                            Reports generation                               #
#=============================================================================#


redirect -file ./results/report.timing         {check_timing}
redirect -file ./results/report.constraints    {report_constraints -all_violators -verbose}
redirect -file ./results/report.paths.min      {report_timing -path_type end  -delay_type min -max_paths 200 -nworst 2}
redirect -file ./results/report.full_paths.min {report_timing -path_type full -delay_type min -max_paths 5   -nworst 2}

foreach grp {FEEDTHROUGH_INST2INST FEEDTHROUGH_DATA2INST FEEDTHROUGH_OTHER REGIN REGOUT hclk} {
    redirect -file ./results/report.paths.max.$grp      {report_timing -path_type end  -delay_type max -max_paths 200 -nworst 2 -group $grp}
    redirect -file ./results/report.full_paths.max.$grp {report_timing -path_type full -delay_type max -max_paths 5   -nworst 2 -group $grp}
}

redirect -file ./results/report.refs           {report_reference}
redirect -file ./results/report.area           {report_area}
redirect -file ./results/report.full_area      {report_area -hierarchy}

# Generate RTL configuration report
source ./report_rtl_config.tcl

# Run custom timing analysis
source ./report_timing.tcl

# Run custom area analysis
source ./report_area.tcl


#=============================================================================#
#          Dump gate level netlist, final DDC file and Test protocol          #
#=============================================================================#
current_design $DESIGN_NAME

change_name -rules verilog -hierarchy

write -hierarchy -format verilog -output "./results/$DESIGN_NAME.gate.v"
write -hierarchy -format ddc     -output "./results/$DESIGN_NAME.ddc"

if {$WITH_DFT} {
    write_test_protocol          -output "./results/$DESIGN_NAME.spf"
}


#=============================================================================#
#                          Final Summary Display                              #
#=============================================================================#

# Display timing and area analysis summaries
# (RTL_CONFIG is combined with AREA_ANALYSIS, TIMING_HISTOGRAM is combined with TIMING_ANALYSIS)
puts $TIMING_ANALYSIS$AREA_ANALYSIS

if {$::env(NO_QUIT) == 0} {
    quit
}

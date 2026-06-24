#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    report_timing
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : report_timing.tcl
# Module Description : Reporting helper: setup / hold timing summary.
#----------------------------------------------------------------------------

##############################################################################
#                                                                            #
#                      CUSTOM TIMING ANALYSIS SCRIPT                         #
#                                                                            #
#  This script generates comprehensive timing analysis reports including:    #
#    - Format 1: Module-centric critical path summary                        #
#    - Format 3: Top N critical paths with details                           #
#    - Format 4: Slack distribution histogram                                #
#    - Format 5: Pipeline stage timing analysis                              #
#                                                                            #
#  Usage: source report_timing.tcl                                           #
#                                                                            #
##############################################################################

##############################################################################
#                            CONFIGURATION                                   #
##############################################################################

# Number of critical paths to show in detailed report (Format 3)
set NUM_CRITICAL_PATHS 20

# Number of paths to analyze per category
set NUM_PATHS_PER_CATEGORY 1000

# Output file
set TIMING_REPORT_FILE "./results/report.timing_analysis.txt"

# Pipeline stage module mappings (customize for your design)
array set PIPELINE_STAGES {
    "FETCH"     "arv_fetch_inst"
    "DECODE"    "arv_decode_inst"
    "EXECUTE"   "arv_alu_inst"
    "MEMORY"    "arv_load_store_inst"
    "WRITEBACK" "arv_int_registers_inst"
    "CSR"       "arv_csr_top_inst"
}

# Slack histogram bin settings (in nanoseconds)
set HISTOGRAM_BINS {-1.50 -1.20 -1.00 -0.80 -0.60 -0.40 -0.30 -0.20 -0.10 0.00 0.10 0.20 0.50 1.00}


##############################################################################
#                          HELPER PROCEDURES                                 #
##############################################################################

# Create a histogram bar
proc create_bar {value max_value max_width} {
    if {$max_value == 0} {
        return ""
    }
    set bar_length [expr int(($value * 1.0 / $max_value) * $max_width)]

    # If value is non-zero but bar_length is 0 due to rounding, use a thinner character
    if {$value > 0 && $bar_length == 0} {
        return [format "%-64s" ":"]
    }

    return [format "%-64s" [string repeat "#" $bar_length]]
}

# Get clock period from design
proc get_clock_period {} {
    set clocks [all_clocks]
    if {[sizeof_collection $clocks] > 0} {
        set clk [get_attribute [index_collection $clocks 0] period]
        return $clk
    }
    return "N/A"
}

# Get clock frequency in MHz
proc get_clock_frequency {} {
    set period [get_clock_period]
    if {$period != "N/A"} {
        return [format "%.1f" [expr 1000.0 / $period]]
    }
    return "N/A"
}

# Calculate statistics from a list of numbers
proc calculate_stats {numbers} {
    if {[llength $numbers] == 0} {
        return [list "N/A" "N/A" "N/A" "N/A" "N/A"]
    }

    set sorted [lsort -real $numbers]
    set count [llength $sorted]
    set min_val [lindex $sorted 0]
    set max_val [lindex $sorted end]

    # Calculate average
    set sum 0.0
    foreach num $sorted {
        set sum [expr $sum + $num]
    }
    set avg [expr $sum / $count]

    # Calculate median
    set mid [expr $count / 2]
    if {$count % 2 == 0} {
        set median [expr ([lindex $sorted [expr $mid - 1]] + [lindex $sorted $mid]) / 2.0]
    } else {
        set median [lindex $sorted $mid]
    }

    # Calculate standard deviation
    set sum_sq_diff 0.0
    foreach num $sorted {
        set diff [expr $num - $avg]
        set sum_sq_diff [expr $sum_sq_diff + ($diff * $diff)]
    }

    # Protect against floating point errors that might make this slightly negative
    set variance [expr $sum_sq_diff / $count]
    if {$variance < 0} {
        set variance 0
    }
    set std_dev [expr sqrt($variance)]

    return [list $min_val $max_val $avg $median $std_dev]
}

# Extract module name from a hierarchical path string
proc extract_module_from_string {path_str} {
    # Look for module pattern: module_name/...
    if {[regexp {([^/\s]+_inst)/} $path_str match module_name]} {
        # Strip any generate-block prefix (e.g. "WITH_UOP_SEQUENCER.arv_uop_sequencer_inst" -> "arv_uop_sequencer_inst")
        regsub {^.*\.} $module_name {} module_name
        return $module_name
    }
    # If no _inst pattern, try first level hierarchy
    if {[regexp {^([^/\s]+)/} $path_str match module_name]} {
        regsub {^.*\.} $module_name {} module_name
        return $module_name
    }
    return "TOP_LEVEL"
}

# Print a critical-paths section in compact single-line format with auto column widths
proc print_critical_paths_section {fp title path_list num_paths} {
    set sorted [lsort -real -index 0 $path_list]
    set n [expr min($num_paths, [llength $sorted])]

    # First pass: compute actual max widths from content
    set SP_W [string length "Startpoint"]
    set EP_W [string length "Endpoint"]
    for {set i 0} {$i < $n} {incr i} {
        set info [lindex $sorted $i]
        set sp_len [string length [lindex $info 1]]
        set ep_len [string length [lindex $info 2]]
        if {$sp_len > $SP_W} { set SP_W $sp_len }
        if {$ep_len > $EP_W} { set EP_W $ep_len }
    }

    set sep_width [expr 4 + 2 + 10 + 2 + $SP_W + 2 + $EP_W]

    puts $fp "================================================================================"
    puts $fp [format "  TOP %d CRITICAL PATHS -- %s" $num_paths $title]
    puts $fp "================================================================================"
    puts $fp [format "%-4s  %-10s  %-${SP_W}s  %s" "#" "Slack" "Startpoint" "Endpoint"]
    puts $fp [string repeat "-" $sep_width]

    if {$n == 0} {
        puts $fp "  (no paths found)"
    } else {
        for {set i 0} {$i < $n} {incr i} {
            set info  [lindex $sorted $i]
            set slack [lindex $info 0]
            set sp    [lindex $info 1]
            set ep    [lindex $info 2]
            puts $fp [format "#%-3d  %7.2f ns  %-${SP_W}s  %s" [expr $i+1] $slack $sp $ep]
        }
    }
    puts $fp ""
    puts $fp ""
}


##############################################################################
#                          DATA COLLECTION                                   #
##############################################################################

puts "Collecting timing data..."

# Get all timing paths
set all_paths [get_timing_paths -max_paths $NUM_PATHS_PER_CATEGORY -nworst 1]

# Get per-group timing paths for separate sections
array set group_path_details_arr {}
foreach grp {REGIN REGOUT hclk FEEDTHROUGH_INST2INST FEEDTHROUGH_DATA2INST FEEDTHROUGH_OTHER} {
    set grp_list {}
    catch {
        set grp_paths [get_timing_paths -max_paths $NUM_PATHS_PER_CATEGORY -nworst 1 -group $grp]
        foreach_in_collection path $grp_paths {
            set slack [get_attribute $path slack]
            set sp_obj [get_attribute $path startpoint]
            set ep_obj [get_attribute $path endpoint]
            set sp ""
            set ep ""
            if {$sp_obj != ""} { catch {set sp [get_attribute $sp_obj full_name]} }
            if {$ep_obj != ""} { catch {set ep [get_attribute $ep_obj full_name]} }
            lappend grp_list [list $slack $sp $ep]
        }
    }
    set group_path_details_arr($grp) $grp_list
}

# Collect slack values and path information
set slack_list {}
set failing_paths 0
set total_paths 0

# Initialize module statistics
array set module_stats {}
array set module_path_count {}
array set module_slack_sum {}
array set module_logic_depth_sum {}

# Path details for Format 3
set path_details_list {}

# Process each path
foreach_in_collection path $all_paths {
    incr total_paths

    # Get slack - this always works
    set slack [get_attribute $path slack]
    lappend slack_list $slack

    if {$slack < 0} {
        incr failing_paths
    }

    # Get startpoint and endpoint names
    set startpoint_obj [get_attribute $path startpoint]
    set endpoint_obj [get_attribute $path endpoint]

    set startpoint_name ""
    set endpoint_name ""

    # Use full_name attribute which should always exist
    if {$startpoint_obj != ""} {
        catch {set startpoint_name [get_attribute $startpoint_obj full_name]}
    }
    if {$endpoint_obj != ""} {
        catch {set endpoint_name [get_attribute $endpoint_obj full_name]}
    }

    # Store path details for Format 3
    lappend path_details_list [list $slack $startpoint_name $endpoint_name]

    # Extract module information from path
    set module_name "TOP_LEVEL"

    # Try endpoint first
    if {$endpoint_name != ""} {
        set module_name [extract_module_from_string $endpoint_name]
    }

    # If still TOP_LEVEL, try startpoint
    if {$module_name == "TOP_LEVEL" && $startpoint_name != ""} {
        set module_name [extract_module_from_string $startpoint_name]
    }

    # If still TOP_LEVEL, look through path points
    if {$module_name == "TOP_LEVEL"} {
        set points [get_attribute $path points]
        foreach_in_collection point $points {
            set point_obj [get_attribute $point object]
            if {$point_obj != ""} {
                catch {
                    set point_name [get_attribute $point_obj full_name]
                    set extracted [extract_module_from_string $point_name]
                    if {$extracted != "TOP_LEVEL"} {
                        set module_name $extracted
                        break
                    }
                }
            }
        }
    }

    # Initialize module if not exists
    if {![info exists module_stats($module_name)]} {
        set module_stats($module_name) $slack
        set module_path_count($module_name) 0
        set module_slack_sum($module_name) 0.0
        set module_logic_depth_sum($module_name) 0
    }

    # Update statistics
    if {$slack < $module_stats($module_name)} {
        set module_stats($module_name) $slack
    }
    incr module_path_count($module_name)
    set module_slack_sum($module_name) [expr $module_slack_sum($module_name) + $slack]
}

# Calculate derived statistics for modules
array set module_avg_slack {}

foreach module [array names module_stats] {
    if {$module_path_count($module) > 0} {
        set module_avg_slack($module) [expr $module_slack_sum($module) / $module_path_count($module)]
    }
}

puts "Collected data for $total_paths paths ($failing_paths failing)"


##############################################################################
#                          REPORT GENERATION                                 #
##############################################################################

set fp [open $TIMING_REPORT_FILE w]

set clock_period [get_clock_period]
set clock_freq [get_clock_frequency]

puts $fp "================================================================================"
puts $fp "                      COMPREHENSIVE TIMING ANALYSIS"
puts $fp "================================================================================"
puts $fp "Design:              $DESIGN_NAME"
puts $fp "Target Clock Period: $clock_period ns ($clock_freq MHz)"
puts $fp "Analysis Date:       [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fp "================================================================================"
puts $fp ""
puts $fp ""


##############################################################################
#                    FORMAT 1: MODULE-CENTRIC ANALYSIS                       #
##############################################################################

# Store console output in global variable and write to file
set ::TIMING_ANALYSIS ""
append ::TIMING_ANALYSIS "\n"
append ::TIMING_ANALYSIS "     +===============================================================================+\n"
append ::TIMING_ANALYSIS "     |                          CRITICAL PATH ANALYSIS BY MODULE                     |\n"
append ::TIMING_ANALYSIS "     |===============================================================================|\n"

puts $fp "================================================================================"
puts $fp "                    CRITICAL PATH ANALYSIS BY MODULE"
puts $fp "================================================================================"

if {$clock_period != "N/A"} {
    append ::TIMING_ANALYSIS [format "     | Target Clock Period: %-15s (%-39s |\n"   "$clock_period ns" "$clock_freq MHz)"]
    puts $fp "Target Clock Period: $clock_period ns ($clock_freq MHz)"
} else {
    append ::TIMING_ANALYSIS "     | Target Clock Period: Not specified                                            |\n"
    puts $fp "Target Clock Period: Not specified"
}
append ::TIMING_ANALYSIS "     |===============================================================================|\n"
append ::TIMING_ANALYSIS "     |                                                                               |\n"

puts $fp ""

# Create sorted list of modules by worst slack
set sorted_modules {}
foreach module [array names module_stats] {
    lappend sorted_modules [list $module $module_stats($module)]
}
set sorted_modules [lsort -real -index 1 $sorted_modules]

# Print header
set header1   "         Module         |     Worst   |     Avg    |   Path   |    % of      "
set header2   "                        |     Slack   |    Slack   |   Count  |    Total     "
set separator "------------------------+-------------+------------+----------+--------------"

append ::TIMING_ANALYSIS "     | $header1 |\n"
append ::TIMING_ANALYSIS "     | $header2 |\n"
append ::TIMING_ANALYSIS "     |-$separator-|\n"
puts $fp $header1
puts $fp $header2
puts $fp $separator

# Print module statistics
foreach module_data $sorted_modules {
    set module [lindex $module_data 0]
    set worst_slack $module_stats($module)
    set avg_slack $module_avg_slack($module)
    set path_count $module_path_count($module)
    set percent [expr $total_paths > 0 ? ($path_count * 100.0 / $total_paths) : 0.0]

    set line [format "%-23s | %8.2f ns | %7.2f ns | %7d  |   %6.1f%%" \
        $module $worst_slack $avg_slack $path_count $percent]

    append ::TIMING_ANALYSIS "     | $line     |\n"
    puts $fp $line
}

append ::TIMING_ANALYSIS "     |-$separator-|\n"
puts $fp $separator

# Overall statistics
if {[llength $slack_list] > 0} {
    set stats [calculate_stats $slack_list]
    set worst_overall [lindex $stats 0]
    set avg_overall [lindex $stats 2]

    set overall_line [format "%-23s | %8.2f ns | %7.2f ns | %7d  |   %6.1f%%" \
        "OVERALL" $worst_overall $avg_overall $total_paths 100.0]

    append ::TIMING_ANALYSIS "     | $overall_line     |\n"
    puts $fp $overall_line
}

append ::TIMING_ANALYSIS "     +===============================================================================+\n"

# Add top 3 critical paths to console output (side by side)
append ::TIMING_ANALYSIS "     |                                TOP 2 CRITICAL PATHS                           |\n"
append ::TIMING_ANALYSIS "     +===============================================================================+\n"

# Sort path details by slack (most negative first)
set sorted_paths_for_console [lsort -real -index 0 $path_details_list]
set num_console_paths [expr min(3, [llength $sorted_paths_for_console])]

if {$num_console_paths > 0} {
    # Collect the 3 paths
    set path1_slack ""
    set path1_start ""
    set path1_end ""
    set path2_slack ""
    set path2_start ""
    set path2_end ""

    for {set i 0} {$i < $num_console_paths} {incr i} {
        set path_info [lindex $sorted_paths_for_console $i]
        set slack [lindex $path_info 0]
        set startpoint [lindex $path_info 1]
        set endpoint [lindex $path_info 2]

        if {$i == 0} {
            set path1_slack [format "%7.2f ns" $slack]
            set path1_start $startpoint
            set path1_end $endpoint
        } elseif {$i == 1} {
            set path2_slack [format "%7.2f ns" $slack]
            set path2_start $startpoint
            set path2_end $endpoint
        }
    }

    # Truncate paths if too long (max 28 chars per column to fit in box)
    proc truncate_path {path max_len} {
        if {[string length $path] > $max_len} {
            return "[string range $path 0 [expr $max_len - 4]]..."
        }
        return $path
    }

    set path1_start_trunc [truncate_path $path1_start 28]
    set path1_end_trunc [truncate_path $path1_end 28]
    set path2_start_trunc [truncate_path $path2_start 28]
    set path2_end_trunc [truncate_path $path2_end 28]

    # Print in 3 columns
    if {$num_console_paths == 1} {
        append ::TIMING_ANALYSIS [format "     | #1 Slack: %-27s | #2 N/A    %-27s |\n" $path1_slack       " "]
        append ::TIMING_ANALYSIS [format "     |    Start: %-27s |           %-27s |\n" $path1_start_trunc " "]
        append ::TIMING_ANALYSIS [format "     |    End:   %-27s |           %-27s |\n" $path1_end_trunc   " "]
    } else {
        append ::TIMING_ANALYSIS [format "     | #1 Slack: %-27s | #2 Slack: %-27s |\n" $path1_slack       $path2_slack]
        append ::TIMING_ANALYSIS [format "     |    Start: %-27s |    Start: %-27s |\n" $path1_start_trunc $path2_start_trunc]
        append ::TIMING_ANALYSIS [format "     |    End:   %-27s |    End:   %-27s |\n" $path1_end_trunc   $path2_end_trunc]
    }
} else {
    append ::TIMING_ANALYSIS "     |      No paths found.                                                          |\n"
}

append ::TIMING_ANALYSIS "     +===============================================================================+\n"

puts $fp "================================================================================"
puts $fp ""
puts $fp "CRITICAL FINDINGS:"

# Find worst module
if {[llength $sorted_modules] > 0} {
    set worst_module [lindex [lindex $sorted_modules 0] 0]
    set worst_count $module_path_count($worst_module)
    set worst_percent [expr $total_paths > 0 ? ($worst_count * 100.0 / $total_paths) : 0.0]
    puts $fp [format "  - %s has %d critical paths (%.1f%% of total)" \
        $worst_module $worst_count $worst_percent]
}

# Report worst slack and TNS
if {[llength $slack_list] > 0} {
    set stats [calculate_stats $slack_list]
    set worst_slack [lindex $stats 0]
    puts $fp [format "  - Worst path slack: %.2f ns" $worst_slack]
    set tns_early 0.0
    foreach s $slack_list {
        if {$s < 0} { set tns_early [expr $tns_early + $s] }
    }
    puts $fp [format "  - Total Negative Slack (TNS): %.2f ns" $tns_early]
}

# Report failing path percentage
if {$total_paths > 0} {
    set fail_percent [expr $failing_paths * 100.0 / $total_paths]
    puts $fp [format "  - Failing paths: %d of %d (%.1f%%)" \
        $failing_paths $total_paths $fail_percent]
}

puts $fp "================================================================================"
puts $fp ""
puts $fp ""


##############################################################################
#                    FORMAT 3b: FEEDTHROUGH CONNECTIVITY                     #
##############################################################################

puts $fp "================================================================================"
puts $fp "                    FEEDTHROUGH CONNECTIVITY ANALYSIS"
puts $fp "================================================================================"

# Helper: strip bit index to get bus name  (e.g. "inst_hrdata_i[17]" → "inst_hrdata_i")
proc ft_bus_name {port_name} {
    regsub {\[.*\]$} $port_name {} result
    return $result
}

set ft_inputs_coll [remove_from_collection [all_inputs] [get_ports hclk_i]]

# Build maps: bus_name -> list of individual port full_names, for inputs and outputs.
array set ft_in_bus_ports  {}
array set ft_out_bus_ports {}
foreach_in_collection port $ft_inputs_coll {
    set pname [get_attribute $port full_name]
    set bus   [ft_bus_name $pname]
    if {![info exists ft_in_bus_ports($bus)]} { set ft_in_bus_ports($bus) {} }
    lappend ft_in_bus_ports($bus) $pname
}
foreach_in_collection port [all_outputs] {
    set pname [get_attribute $port full_name]
    set bus   [ft_bus_name $pname]
    if {![info exists ft_out_bus_ports($bus)]} { set ft_out_bus_ports($bus) {} }
    lappend ft_out_bus_ports($bus) $pname
}

# Query each (in_bus, out_bus) pair directly.
# Querying per pair avoids one input shadowing another (no dependence on -nworst value).
# -nworst 1 returns the worst path to each output-bit endpoint; -max_paths 64 is
# enough for any single output bus (no bus has more than 64 bits).
array set ft_pair_slack {}   ;# key = "in_bus|out_bus"  value = worst slack
array set ft_pair_count {}   ;# key = "in_bus|out_bus"  value = bit-path count

foreach in_bus [lsort [array names ft_in_bus_ports]] {
    set in_ports [get_ports $ft_in_bus_ports($in_bus)]
    foreach out_bus [lsort [array names ft_out_bus_ports]] {
        set out_ports [get_ports $ft_out_bus_ports($out_bus)]
        catch {
            set paths [get_timing_paths -from $in_ports \
                                        -to   $out_ports \
                                        -max_paths 64    \
                                        -nworst    1     ]
            if {[sizeof_collection $paths] > 0} {
                set key "${in_bus}|${out_bus}"
                set ft_pair_count($key) [sizeof_collection $paths]
                set worst 1e9
                foreach_in_collection path $paths {
                    set s [get_attribute $path slack]
                    if {$s < $worst} { set worst $s }
                }
                set ft_pair_slack($key) $worst
            }
        }
    }
}

# Sort pairs by worst slack (most negative first)
set ft_pair_list {}
foreach key [array names ft_pair_slack] {
    set parts   [split $key "|"]
    set in_bus  [lindex $parts 0]
    set out_bus [lindex $parts 1]
    lappend ft_pair_list [list $ft_pair_slack($key) $in_bus $out_bus $ft_pair_count($key)]
}
set ft_pair_list [lsort -real -index 0 $ft_pair_list]

# Compute column widths from content
set W_IN  [string length "Input"]
set W_OUT [string length "Output"]
foreach entry $ft_pair_list {
    set w [string length [lindex $entry 1]]; if {$w > $W_IN } { set W_IN  $w }
    set w [string length [lindex $entry 2]]; if {$w > $W_OUT} { set W_OUT $w }
}

set ft_hdr [format "%-${W_IN}s  %-${W_OUT}s  %6s  %10s  %s" \
    "Input" "Output" "Paths" "Worst Slack" "Status"]
set ft_sep [string repeat "-" [string length $ft_hdr]]
puts $fp $ft_hdr
puts $fp $ft_sep

set ft_fail_count 0
set ft_pass_count 0
foreach entry $ft_pair_list {
    set slack   [lindex $entry 0]
    set in_bus  [lindex $entry 1]
    set out_bus [lindex $entry 2]
    set count   [lindex $entry 3]
    if {$slack < 0} {
        set status "FAIL"
        incr ft_fail_count
    } else {
        set status "pass"
        incr ft_pass_count
    }
    puts $fp [format "%-${W_IN}s  %-${W_OUT}s  %6d  %8.2f ns  %s" \
        $in_bus $out_bus $count $slack $status]
}
puts $fp $ft_sep
puts $fp [format "  %d feedthrough bus pairs  (%d failing, %d passing)" \
    [llength $ft_pair_list] $ft_fail_count $ft_pass_count]
puts $fp ""

# Report inputs with no feedthrough path to any output (fully registered at boundary)
set ft_in_buses_used {}
foreach key [array names ft_pair_slack] {
    set in_bus [lindex [split $key "|"] 0]
    if {[lsearch $ft_in_buses_used $in_bus] == -1} {
        lappend ft_in_buses_used $in_bus
    }
}

set all_in_buses [array names ft_in_bus_ports]

set no_ft_buses {}
foreach bus $all_in_buses {
    if {[lsearch $ft_in_buses_used $bus] == -1} { lappend no_ft_buses $bus }
}

#if {[llength $no_ft_buses] > 0} {
#    puts $fp "Inputs with no feedthrough path (fully registered at boundary):"
#    foreach bus [lsort $no_ft_buses] { puts $fp "  $bus" }
#} else {
#    puts $fp "All inputs have at least one feedthrough path to an output."
#}

puts $fp ""
puts $fp ""

##############################################################################
#                    FORMAT 3: TOP N CRITICAL PATHS                          #
##############################################################################

# Per-group sections
foreach grp {FEEDTHROUGH_INST2INST FEEDTHROUGH_DATA2INST FEEDTHROUGH_OTHER REGIN REGOUT hclk} {
    print_critical_paths_section $fp $grp $group_path_details_arr($grp) $NUM_CRITICAL_PATHS
}


##############################################################################
#                    FORMAT 4: SLACK DISTRIBUTION                            #
##############################################################################

# Initialize histogram global variable
set ::TIMING_HISTOGRAM ""
append ::TIMING_HISTOGRAM "\n"
append ::TIMING_HISTOGRAM "     +===================================================================================================+\n"
append ::TIMING_HISTOGRAM "     |                                       SLACK DISTRIBUTION                                          |\n"
append ::TIMING_HISTOGRAM "     |===================================================================================================|\n"

puts $fp "================================================================================"
puts $fp "                         SLACK DISTRIBUTION"
puts $fp "================================================================================"

if {$clock_period != "N/A"} {
    puts $fp "Target: $clock_period ns @ $clock_freq MHz"
} else {
    puts $fp "Target: Not specified"
}
puts $fp ""

# Create histogram bins
set bin_labels {}
set bin_counts {}

# First bin: < first threshold
set first_threshold [lindex $HISTOGRAM_BINS 0]
lappend bin_labels "< [format %.2f $first_threshold] ns"
set count_below 0
foreach slack $slack_list {
    if {$slack < $first_threshold} {
        incr count_below
    }
}
lappend bin_counts $count_below

# Middle bins: between thresholds
for {set i 0} {$i < [expr [llength $HISTOGRAM_BINS] - 1]} {incr i} {
    set low [lindex $HISTOGRAM_BINS $i]
    set high [lindex $HISTOGRAM_BINS [expr $i + 1]]
    set label "[format %.2f $low] to [format %.2f $high]"
    lappend bin_labels $label

    set count_in_range 0
    foreach slack $slack_list {
        if {$slack >= $low && $slack < $high} {
            incr count_in_range
        }
    }
    lappend bin_counts $count_in_range
}

# Last bin: >= last threshold
set last_threshold [lindex $HISTOGRAM_BINS end]
lappend bin_labels "> [format %.2f $last_threshold] ns"
set count_above 0
foreach slack $slack_list {
    if {$slack >= $last_threshold} {
        incr count_above
    }
}
lappend bin_counts $count_above

# Find max count for scaling
set max_count 0
foreach count $bin_counts {
    if {$count > $max_count} {
        set max_count $count
    }
}

# Print histogram
set header    "Slack Range          | Count   | Histogram                                                       "
set separator "---------------------+---------+-----------------------------------------------------------------"

append ::TIMING_HISTOGRAM "     | $header |\n"
append ::TIMING_HISTOGRAM "     |-$separator-|\n"
puts $fp $header
puts $fp $separator

for {set i 0} {$i < [llength $bin_labels]} {incr i} {
    set label [lindex $bin_labels $i]
    set count [lindex $bin_counts $i]
    set bar [create_bar $count $max_count 50]

    # Add annotation for critical bins (first 4 bins are most critical)
    set annotation ""
    if {$i < 4 && $count > 0} {
        set annotation " (CRITICAL)"
    }

    set line [format "%-20s | %7d | %s" $label $count $bar]
    append ::TIMING_HISTOGRAM "     | $line | $annotation\n"
    puts $fp $line
}
append ::TIMING_HISTOGRAM "     |===================================================================================================|\n"
puts $fp $separator
puts $fp ""

# Statistics
if {[llength $slack_list] > 0} {
    set stats [calculate_stats $slack_list]
    set min_slack [lindex $stats 0]
    set max_slack [lindex $stats 1]
    set avg_slack [lindex $stats 2]
    set median_slack [lindex $stats 3]
    set std_dev [lindex $stats 4]

    # Calculate Total Negative Slack (TNS) - sum of all negative slacks
    set tns 0.0
    foreach slack $slack_list {
        if {$slack < 0} {
            set tns [expr $tns + $slack]
        }
    }

    # Worst Negative Slack (WNS) - most negative slack value
    set wns [expr $min_slack < 0 ? $min_slack : 0.0]

    append ::TIMING_HISTOGRAM [format "     |   Paths analyzed:       %7d                 |   Worst Negative Slack:  %7.2f ns %11s |\n" $total_paths $wns " "]
    append ::TIMING_HISTOGRAM [format "     |   Paths failing:        %7d (%4.1f%%)         |   Total Negative Slack:  %7.2f ns %12s|\n" \
        $failing_paths [expr $total_paths > 0 ? ($failing_paths * 100.0 / $total_paths) : 0.0] $tns " "]

    puts $fp "Statistics:"
    puts $fp [format "  Paths analyzed:     %d" $total_paths]
    puts $fp [format "  Paths failing:      %d (%.1f%%)" \
        $failing_paths [expr $total_paths > 0 ? ($failing_paths * 100.0 / $total_paths) : 0.0]]
    puts $fp [format "  Total Negative Slack: %.2f ns" $tns]
    puts $fp [format "  Worst slack:        %.2f ns" $min_slack]
    puts $fp [format "  Best slack:         %.2f ns" $max_slack]
    puts $fp [format "  Average slack:      %.2f ns" $avg_slack]
    puts $fp [format "  Median slack:       %.2f ns" $median_slack]
    puts $fp [format "  Std deviation:      %.2f ns" $std_dev]
}

append ::TIMING_HISTOGRAM "     +===================================================================================================+\n"

puts $fp "================================================================================"
puts $fp ""
puts $fp ""


##############################################################################
#                    FORMAT 5: PIPELINE STAGE ANALYSIS                       #
##############################################################################

puts $fp "================================================================================"
puts $fp "                    PIPELINE STAGE TIMING ANALYSIS"
puts $fp "================================================================================"
puts $fp ""

# Collect timing data for each pipeline stage
array set stage_worst_slack {}
array set stage_avg_slack {}
array set stage_path_count {}
array set stage_slack_sum {}

# Initialize stages
foreach {stage_name module_name} [array get PIPELINE_STAGES] {
    set stage_worst_slack($stage_name) "N/A"
    set stage_path_count($stage_name) 0
    set stage_slack_sum($stage_name) 0.0
}

# Analyze paths for each stage
foreach_in_collection path $all_paths {
    set slack [get_attribute $path slack]

    # Collect all module names this path goes through
    set modules_in_path {}

    # Check startpoint
    set startpoint_obj [get_attribute $path startpoint]
    if {$startpoint_obj != ""} {
        catch {
            set sp_name [get_attribute $startpoint_obj full_name]
            set mod [extract_module_from_string $sp_name]
            if {$mod != "TOP_LEVEL"} {
                lappend modules_in_path $mod
            }
        }
    }

    # Check endpoint
    set endpoint_obj [get_attribute $path endpoint]
    if {$endpoint_obj != ""} {
        catch {
            set ep_name [get_attribute $endpoint_obj full_name]
            set mod [extract_module_from_string $ep_name]
            if {$mod != "TOP_LEVEL"} {
                lappend modules_in_path $mod
            }
        }
    }

    # Check all points in the path (this catches paths through modules)
    set points [get_attribute $path points]
    foreach_in_collection point $points {
        set point_obj [get_attribute $point object]
        if {$point_obj != ""} {
            catch {
                set point_name [get_attribute $point_obj full_name]
                set mod [extract_module_from_string $point_name]
                if {$mod != "TOP_LEVEL"} {
                    lappend modules_in_path $mod
                }
            }
        }
    }

    # Remove duplicates from modules_in_path
    set modules_in_path [lsort -unique $modules_in_path]

    # Update statistics for each stage this path goes through
    foreach {stage_name module_name} [array get PIPELINE_STAGES] {
        if {[lsearch $modules_in_path $module_name] != -1} {
            if {$stage_worst_slack($stage_name) == "N/A" || $slack < $stage_worst_slack($stage_name)} {
                set stage_worst_slack($stage_name) $slack
            }
            incr stage_path_count($stage_name)
            set stage_slack_sum($stage_name) [expr $stage_slack_sum($stage_name) + $slack]
        }
    }
}

# Calculate averages
foreach {stage_name module_name} [array get PIPELINE_STAGES] {
    if {$stage_path_count($stage_name) > 0} {
        set stage_avg_slack($stage_name) [expr $stage_slack_sum($stage_name) / $stage_path_count($stage_name)]
    } else {
        set stage_avg_slack($stage_name) "N/A"
    }
}

# Print table header
puts $fp [format "%-12s | %-9s | %-8s | %-7s | %s" \
    "Stage" "Worst" "Avg" "Paths" "Module"]
puts $fp [format "%-12s | %-9s | %-8s | %-7s | %s" \
    "" "Slack" "Slack" "" ""]
puts $fp [string repeat "-" 87]

# Define stage order for printing
set stage_order {FETCH DECODE EXECUTE MEMORY WRITEBACK CSR}

# Print each stage
foreach stage_name $stage_order {
    if {[info exists PIPELINE_STAGES($stage_name)]} {
        set module_name $PIPELINE_STAGES($stage_name)
        set worst $stage_worst_slack($stage_name)
        set avg $stage_avg_slack($stage_name)
        set count $stage_path_count($stage_name)

        if {$worst == "N/A"} {
            set worst_str "    N/A"
        } else {
            set worst_str [format "%7.2f ns" $worst]
        }

        if {$avg == "N/A"} {
            set avg_str "   N/A"
        } else {
            set avg_str [format "%6.2f ns" $avg]
        }

        puts $fp [format "%-12s | %9s | %8s | %7d | %s" \
            $stage_name $worst_str $avg_str $count $module_name]
    }
}

puts $fp [string repeat "-" 87]
puts $fp ""

# Bottleneck analysis
puts $fp "BOTTLENECK ANALYSIS:"

# Find stages with negative slack
set critical_stages {}
foreach stage_name $stage_order {
    if {[info exists stage_worst_slack($stage_name)]} {
        if {$stage_worst_slack($stage_name) != "N/A" && $stage_worst_slack($stage_name) < 0} {
            lappend critical_stages [list $stage_name $stage_worst_slack($stage_name)]
        }
    }
}

if {[llength $critical_stages] > 0} {
    # Sort by worst slack
    set critical_stages [lsort -real -index 1 $critical_stages]

    set rank 1
    foreach stage_data $critical_stages {
        set stage_name [lindex $stage_data 0]
        set slack [lindex $stage_data 1]
        puts $fp [format "  %d. %s stage (%.2f ns slack)" $rank $stage_name $slack]
        incr rank
    }
} else {
    puts $fp "  No critical bottlenecks detected - all stages meet timing"
}

puts $fp "================================================================================"
puts $fp ""

close $fp

##############################################################################
#                    COMBINE TIMING_ANALYSIS AND TIMING_HISTOGRAM            #
##############################################################################

# Source report utilities
source ./report_utils.tcl

# Combine TIMING_ANALYSIS and TIMING_HISTOGRAM side by side
set ::TIMING_ANALYSIS [combine_reports_side_by_side $::TIMING_ANALYSIS $::TIMING_HISTOGRAM 85 3]

puts ""
puts "================================================================================"
puts "Timing analysis complete!"
puts "Report saved to: $TIMING_REPORT_FILE"
puts "================================================================================"
puts ""

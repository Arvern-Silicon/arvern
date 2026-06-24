#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    report_area
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : report_area.tcl
# Module Description : Reporting helper: area breakdown by hierarchy.
#----------------------------------------------------------------------------

##############################################################################
#                                                                            #
#                         CUSTOM AREA ANALYSIS SCRIPT                        #
#                                                                            #
#  This script generates a detailed area breakdown with NAND2 equivalents   #
#  for each major module in the design.                                     #
#                                                                            #
#  Usage: source report_area.tcl                                            #
#         (after synthesis and standard area reports are generated)         #
#                                                                            #
##############################################################################

##############################################################################
#                            CONFIGURATION                                   #
##############################################################################

# Output file
set AREA_REPORT_FILE "./results/report.area_analysis.txt"


##############################################################################
#                          AREA ANALYSIS                                     #
##############################################################################

# Add NAND2 size equivalent report to the area report file
if {[info exists NAND2_NAME]} {

    set nand2_area [get_attribute [get_lib_cell $LIB_WC_NAME/$NAND2_NAME] area]

    current_design $DESIGN_NAME
    redirect -variable arv_area {report_area}

    current_design $DESIGN_NAME
    current_design [get_attribute [get_cells arv_fetch_inst] ref_name]
    redirect -variable fetch_area {report_area}

    current_design $DESIGN_NAME
    current_design [get_attribute [get_cells arv_decode_inst] ref_name]
    redirect -variable decode_area {report_area}

    current_design $DESIGN_NAME
    current_design [get_attribute [get_cells arv_int_registers_inst] ref_name]
    redirect -variable int_reg_area {report_area}

    current_design $DESIGN_NAME
    current_design [get_attribute [get_cells arv_csr_top_inst] ref_name]
    redirect -variable csr_top_area {report_area}

    # Zicntr (cycle/instret) and Zihpm (mhpmcounterN) live inside arv_csr_top
    # under `if (ZICNTR_EN)` / `if (ZIHPM_NR > 0)` generate guards. Reported
    # separately and subtracted from the parent CSR number so the per-row
    # totals still sum to TOTAL — same pattern as MUL/DIV vs ALU below.
    set has_csr_cntr 0
    current_design $DESIGN_NAME
    set csr_cntr_cells [get_cells -hier -filter "ref_name =~ *arv_csr_cntr*" -quiet]
    if {[sizeof_collection $csr_cntr_cells] > 0} {
        set has_csr_cntr 1
        current_design [get_attribute [index_collection $csr_cntr_cells 0] ref_name]
        redirect -variable csr_cntr_area {report_area}
    }

    set has_csr_hpm 0
    current_design $DESIGN_NAME
    set csr_hpm_cells [get_cells -hier -filter "ref_name =~ *arv_csr_hpm*" -quiet]
    if {[sizeof_collection $csr_hpm_cells] > 0} {
        set has_csr_hpm 1
        current_design [get_attribute [index_collection $csr_hpm_cells 0] ref_name]
        redirect -variable csr_hpm_area {report_area}
    }

    current_design $DESIGN_NAME
    current_design [get_attribute [get_cells arv_alu_inst] ref_name]
    redirect -variable alu_area {report_area}

    # MUL/DIV (arv_alu_muldiv_inst) is instantiated INSIDE arv_alu_inst under a
    # `if (MUL_EN) begin : WITH_MULDIV` generate guard. To produce the same split
    # as `characterization_guide.md` §2.2 (ALU and MUL/DIV as separate rows),
    # we have to report muldiv separately and subtract it from the parent ALU
    # number so the rows sum to the same TOTAL. Absent under M_EXTENSION=0.
    set has_muldiv 0
    current_design $DESIGN_NAME
    set muldiv_cells [get_cells -hier -filter "ref_name =~ *arv_alu_muldiv*" -quiet]
    if {[sizeof_collection $muldiv_cells] > 0} {
        set has_muldiv 1
        current_design [get_attribute [index_collection $muldiv_cells 0] ref_name]
        redirect -variable muldiv_area {report_area}
    }

    current_design $DESIGN_NAME
    current_design [get_attribute [get_cells arv_load_store_inst] ref_name]
    redirect -variable ldst_area {report_area}

    # UOP sequencer lives inside a generate block — search by module ref_name for robustness
    set has_uop_seq 0
    current_design $DESIGN_NAME
    set uop_cells [get_cells -hier -filter "ref_name =~ *arv_uop_sequencer*" -quiet]
    if {[sizeof_collection $uop_cells] > 0} {
        set has_uop_seq 1
        current_design [get_attribute [index_collection $uop_cells 0] ref_name]
        redirect -variable uop_area {report_area}
    }

    # Sequential-cell count (flop population) for the §11.6 'Sequential cells'
    # row. `all_registers -cells` is the canonical dc_shell way to enumerate
    # every flop in the design.
    current_design $DESIGN_NAME
    set seq_cells_count [sizeof_collection [all_registers -cells]]

    regexp {Total cell area:\s+([^\n]+)\n} $arv_area      whole_match arv_area
    regexp {Total cell area:\s+([^\n]+)\n} $fetch_area    whole_match fetch_area
    regexp {Total cell area:\s+([^\n]+)\n} $decode_area   whole_match decode_area
    regexp {Total cell area:\s+([^\n]+)\n} $int_reg_area  whole_match int_reg_area
    regexp {Total cell area:\s+([^\n]+)\n} $csr_top_area  whole_match csr_top_area
    regexp {Total cell area:\s+([^\n]+)\n} $alu_area      whole_match alu_area
    regexp {Total cell area:\s+([^\n]+)\n} $ldst_area     whole_match ldst_area

    if {$has_muldiv} {
        regexp {Total cell area:\s+([^\n]+)\n} $muldiv_area whole_match muldiv_area
    } else {
        set muldiv_area 0
    }
    if {$has_uop_seq} {
        regexp {Total cell area:\s+([^\n]+)\n} $uop_area whole_match uop_area
    } else {
        set uop_area 0
    }
    if {$has_csr_cntr} {
        regexp {Total cell area:\s+([^\n]+)\n} $csr_cntr_area whole_match csr_cntr_area
    } else {
        set csr_cntr_area 0
    }
    if {$has_csr_hpm} {
        regexp {Total cell area:\s+([^\n]+)\n} $csr_hpm_area whole_match csr_hpm_area
    } else {
        set csr_hpm_area 0
    }

    # MUL/DIV is reported as its own row; subtract it from the parent ALU
    # number so the per-row totals still sum to the design TOTAL. Without
    # this the MUL/DIV gates would be double-counted (once under ALU,
    # once under MUL/DIV).
    set alu_area [expr $alu_area - $muldiv_area]

    # Same trick for the CSR subsystem: subtract Zicntr + Zihpm from the
    # arv_csr_top hierarchical area so the remaining csr_top_area represents
    # the "CSR core" (mtraps + ids + decode + read-mux) only — and the three
    # CSR rows sum to the full subsystem.
    set csr_top_area [expr $csr_top_area - $csr_cntr_area - $csr_hpm_area]

    set arv_nand2_eq      [expr round($arv_area/$nand2_area)]
    set fetch_nand2_eq    [expr round($fetch_area/$nand2_area)]
    set decode_nand2_eq   [expr round($decode_area/$nand2_area)]
    set int_reg_nand2_eq  [expr round($int_reg_area/$nand2_area)]
    set csr_top_nand2_eq  [expr round($csr_top_area/$nand2_area)]
    set csr_cntr_nand2_eq [expr round($csr_cntr_area/$nand2_area)]
    set csr_hpm_nand2_eq  [expr round($csr_hpm_area/$nand2_area)]
    set alu_nand2_eq      [expr round($alu_area/$nand2_area)]
    set muldiv_nand2_eq   [expr round($muldiv_area/$nand2_area)]
    set ldst_nand2_eq     [expr round($ldst_area/$nand2_area)]

    set uop_nand2_eq [expr round($uop_area/$nand2_area)]

    set arv_area         [expr round($arv_area)]
    set fetch_area       [expr round($fetch_area)]
    set decode_area      [expr round($decode_area)]
    set int_reg_area     [expr round($int_reg_area)]
    set csr_top_area     [expr round($csr_top_area)]
    set csr_cntr_area    [expr round($csr_cntr_area)]
    set csr_hpm_area     [expr round($csr_hpm_area)]
    set alu_area         [expr round($alu_area)]
    set muldiv_area      [expr round($muldiv_area)]
    set ldst_area        [expr round($ldst_area)]

    set arv_per          [format "%.1f%%" [expr 100.0*$arv_area/$arv_area]]
    set fetch_per        [format "%.1f%%" [expr 100.0*$fetch_area/$arv_area]]
    set decode_per       [format "%.1f%%" [expr 100.0*$decode_area/$arv_area]]
    set int_reg_per      [format "%.1f%%" [expr 100.0*$int_reg_area/$arv_area]]
    set csr_top_per      [format "%.1f%%" [expr 100.0*$csr_top_area/$arv_area]]
    set csr_cntr_per     [format "%.1f%%" [expr 100.0*$csr_cntr_area/$arv_area]]
    set csr_hpm_per      [format "%.1f%%" [expr 100.0*$csr_hpm_area/$arv_area]]
    set alu_per          [format "%.1f%%" [expr 100.0*$alu_area/$arv_area]]
    set muldiv_per       [format "%.1f%%" [expr 100.0*$muldiv_area/$arv_area]]
    set ldst_per         [format "%.1f%%" [expr 100.0*$ldst_area/$arv_area]]

    set uop_area     [expr round($uop_area)]
    set uop_per      [format "%.1f%%" [expr 100.0*$uop_area/$arv_area]]

    ##########################################################################
    #                    WRITE TO DEDICATED REPORT FILE                     #
    ##########################################################################

    set fp [open $AREA_REPORT_FILE w]

    puts $fp "================================================================================"
    puts $fp "                         COMPREHENSIVE AREA ANALYSIS"
    puts $fp "================================================================================"
    puts $fp "Design:              $DESIGN_NAME"
    puts $fp "Analysis Date:       [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fp "Reference Gate:      $NAND2_NAME (area: $nand2_area)"
    puts $fp "================================================================================"
    puts $fp ""
    puts $fp ""

    puts $fp "================================================================================"
    puts $fp "                              AREA BREAKDOWN BY MODULE"
    puts $fp "================================================================================"
    puts $fp ""

    puts $fp [format "%-25s | %-12s | %-12s | %-10s" "Module" "Area" "NAND2 Equiv" "Percent"]
    puts $fp [string repeat "-" 80]
    puts $fp [format "%-25s | %12d | %12d | %10s" "Instruction Fetch"     $fetch_area    $fetch_nand2_eq    $fetch_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "Instruction Decode"    $decode_area   $decode_nand2_eq   $decode_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "Integer Register File" $int_reg_area  $int_reg_nand2_eq  $int_reg_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "ALU"                   $alu_area      $alu_nand2_eq      $alu_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "MUL / DIV"             $muldiv_area   $muldiv_nand2_eq   $muldiv_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "Load-Store Unit"       $ldst_area     $ldst_nand2_eq     $ldst_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "CSR core"              $csr_top_area  $csr_top_nand2_eq  $csr_top_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "CSR Zicntr"            $csr_cntr_area $csr_cntr_nand2_eq $csr_cntr_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "CSR Zihpm"             $csr_hpm_area  $csr_hpm_nand2_eq  $csr_hpm_per]
    puts $fp [format "%-25s | %12d | %12d | %10s" "UOP Sequencer"         $uop_area      $uop_nand2_eq      $uop_per]
    puts $fp [string repeat "-" 80]
    puts $fp [format "%-25s | %12d | %12d | %10s" "TOTAL (arvern)"        $arv_area      $arv_nand2_eq      $arv_per]
    puts $fp "================================================================================"
    puts $fp ""

    puts $fp "AREA SUMMARY:"
    puts $fp [format "  - Total area:              %d" $arv_area]
    puts $fp [format "  - Total NAND2 equivalent:  %d gates" $arv_nand2_eq]
    puts $fp [format "  - Sequential cells (flops):%d" $seq_cells_count]
    puts $fp [format "  - Reference gate:          %s" $NAND2_NAME]
    puts $fp [format "  - Reference gate area:     %.6f" $nand2_area]
    puts $fp ""

    puts $fp "LARGEST MODULES:"
    puts $fp [format "  1. Integer Register File: %d NAND2 (%s)" $int_reg_nand2_eq $int_reg_per]
    puts $fp [format "  2. ALU:                   %d NAND2 (%s)" $alu_nand2_eq     $alu_per]
    puts $fp [format "  3. CSR subsystem:         %d NAND2 (%s)" $csr_top_nand2_eq $csr_top_per]
    puts $fp [format "  4. MUL / DIV:             %d NAND2 (%s)" $muldiv_nand2_eq  $muldiv_per]
    puts $fp ""

    puts $fp "================================================================================"

    close $fp

    ##########################################################################
    #                  APPEND TO STANDARD AREA REPORT                       #
    ##########################################################################

    set fp [open "./results/report.area" a]
    puts $fp ""
    puts $fp "NAND2 equivalent cell area: arvern                --> $arv_nand2_eq"
    puts $fp "NAND2 equivalent cell area: Instruction Fetch     --> $fetch_nand2_eq"
    puts $fp "NAND2 equivalent cell area: Instruction Decode    --> $decode_nand2_eq"
    puts $fp "NAND2 equivalent cell area: Integer Register File --> $int_reg_nand2_eq"
    puts $fp "NAND2 equivalent cell area: ALU                   --> $alu_nand2_eq"
    puts $fp "NAND2 equivalent cell area: MUL / DIV             --> $muldiv_nand2_eq"
    puts $fp "NAND2 equivalent cell area: Load-Store Unit       --> $ldst_nand2_eq"
    puts $fp "NAND2 equivalent cell area: CSR core              --> $csr_top_nand2_eq"
    puts $fp "NAND2 equivalent cell area: CSR Zicntr            --> $csr_cntr_nand2_eq"
    puts $fp "NAND2 equivalent cell area: CSR Zihpm             --> $csr_hpm_nand2_eq"
    puts $fp "NAND2 equivalent cell area: UOP Sequencer         --> $uop_nand2_eq"
    puts $fp "Sequential cells (flop count)                     --> $seq_cells_count"
    close $fp

    ##########################################################################
    #                 STORE CONSOLE OUTPUT IN VARIABLE                     #
    ##########################################################################

    set ::AREA_ANALYSIS ""
    append ::AREA_ANALYSIS "     +===============================================================================+\n"
    append ::AREA_ANALYSIS "     |                               AREA BREAKDOWN BY MODULE                        |\n"
    append ::AREA_ANALYSIS "     |===============================================================================|\n"
    append ::AREA_ANALYSIS [format "     | Design:              %-56s |\n" $DESIGN_NAME]
    append ::AREA_ANALYSIS [format "     | Reference Gate:      %-12s (area: %-36s |\n" $NAND2_NAME $nand2_area)]
    append ::AREA_ANALYSIS "     |===============================================================================|\n"
    append ::AREA_ANALYSIS "     |                                                                               |\n"
    append ::AREA_ANALYSIS "     |           Module          |     Area     |  NAND2 Equiv |    Percent          |\n"
    append ::AREA_ANALYSIS "     |---------------------------+--------------+--------------+---------------------|\n"
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "Instruction Fetch"     $fetch_area    $fetch_nand2_eq    $fetch_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "Instruction Decode"    $decode_area   $decode_nand2_eq   $decode_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "Integer Register File" $int_reg_area  $int_reg_nand2_eq  $int_reg_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "ALU"                   $alu_area      $alu_nand2_eq      $alu_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "MUL / DIV"             $muldiv_area   $muldiv_nand2_eq   $muldiv_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "Load-Store Unit"       $ldst_area     $ldst_nand2_eq     $ldst_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "CSR core"              $csr_top_area  $csr_top_nand2_eq  $csr_top_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "CSR Zicntr"            $csr_cntr_area $csr_cntr_nand2_eq $csr_cntr_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "CSR Zihpm"             $csr_hpm_area  $csr_hpm_nand2_eq  $csr_hpm_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "UOP Sequencer"         $uop_area      $uop_nand2_eq      $uop_per]
    append ::AREA_ANALYSIS "     |---------------------------+--------------+--------------+---------------------|\n"
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %12d | %10s          |\n" "TOTAL (arvern)"        $arv_area      $arv_nand2_eq      $arv_per]
    append ::AREA_ANALYSIS [format "     | %-25s | %12d | %-12s | %10s          |\n" "Sequential cells"      $seq_cells_count "(flops)"        "n/a"]
    append ::AREA_ANALYSIS "     +===============================================================================+\n"

    ##########################################################################
    #                 COMBINE AREA_ANALYSIS AND RTL_CONFIG                  #
    ##########################################################################

    # Source report utilities
     source ./report_utils.tcl

    # Combine AREA_ANALYSIS and RTL_CONFIG side by side
    set ::AREA_ANALYSIS [combine_reports_side_by_side $::AREA_ANALYSIS $::RTL_CONFIG 86 3]

    puts ""
    puts "      ================================================================================"
    puts "      Area analysis complete!"
    puts "      Report saved to: $AREA_REPORT_FILE"
    puts "      ================================================================================"
    puts ""
}

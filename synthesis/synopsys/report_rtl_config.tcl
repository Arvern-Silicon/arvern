#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    report_rtl_config
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : report_rtl_config.tcl
# Module Description : Reporting helper: echo the active RTL parameter configuration.
#----------------------------------------------------------------------------

##############################################################################
#                                                                            #
#                      RTL CONFIGURATION REPORT SCRIPT                       #
#                                                                            #
#  This script generates a formatted report of the RTL parameters used      #
#  during synthesis.                                                         #
#                                                                            #
#  Usage: source report_rtl_config.tcl                                      #
#         (after rtl_params.tcl has been sourced)                           #
#                                                                            #
##############################################################################

# Check if rtl_params.tcl was sourced
if {![info exists RTL_PARAM_M_EXTENSION] || ![info exists RTL_PARAM_ZICNTR_EN] ||
    ![info exists RTL_PARAM_ZIHPM_NR]   || ![info exists RTL_PARAM_SINGLE_CYCLE_BRANCH]} {
    puts "Warning: RTL parameters not loaded - skipping configuration report"
    set ::RTL_CONFIG ""
    return
}

# Build RTL configuration report
set ::RTL_CONFIG ""
append ::RTL_CONFIG "     +===================================================================================================+\n"
append ::RTL_CONFIG "     |                                            RTL CONFIGURATION                                      |\n"
append ::RTL_CONFIG "     |===================================================================================================|\n"
append ::RTL_CONFIG [format "     | Design:              %-75s  |\n" $DESIGN_NAME]
append ::RTL_CONFIG "     | Source:              run_config.json                                                              |\n"
append ::RTL_CONFIG "     |===================================================================================================|\n"
append ::RTL_CONFIG "     |                                                                                                   |\n"

# Parameter descriptions
array set param_desc {
    C_EXTENSION         "Compressed Instructions"
    M_EXTENSION         "Multiply/Divide Extension"
    B_EXTENSION         "Bit Manipulation Extension"
    MUL_TYPE            "Multiplier Implementation"
    DIV_TYPE            "Divider Implementation"
    CCSR_EN             "Custom CSR Interface"
    SU_MODE_EN          "S+U Privilege Modes"
    PMP_NR              "Physical Memory Protection"
    ZICNTR_EN           "Zicntr Counters"
    ZIHPM_NR            "Zihpm Counters"
    RV32E_EN            "Embedded ISA"
    SINGLE_CYCLE_BRANCH "Taken-branch latency"
    ASYNC_RST_EN        "Reset architecture"
    DEBUG_EN            "External Debug (Sdext)"
    DM_TRIGGER_NR       "Sdtrig HW Triggers"
}

# M_EXTENSION value descriptions
array set m_ext_desc {
    0 "Disabled"
    1 "Zmmul (multiply only)"
    2 "M extension (multiply + divide)"
}

# Value descriptions
array set mul_type_desc {
    1 "Single-cycle (1 cycle)"
    2 "Fast (4 cycles)"
    3 "Area-optimized (16 cycles)"
}

array set div_type_desc {
    1 "Radix-8 (12 cycles)"
    2 "Radix-4 (17 cycles)"
    3 "Radix-2 (33 cycles)"
}

array set b_ext_desc {
    0 "Disabled"
    1 "Zbb"
    2 "Zbb + Zba"
    3 "Zbb + Zba + Zbs"
    4 "Zbb + Zba + Zbs + Zbc"
}

array set c_ext_desc {
    0 "Disabled"
    1 "Zca"
    2 "Zca + Zcb"
    3 "Zca + Zcb + Zcmp"
    4 "Zca + Zcb + Zcmp + Zcmt"
}

# ISA Extensions section
append ::RTL_CONFIG "     | ISA EXTENSIONS:                                                                                   |\n"

set b_ext_val $RTL_PARAM_B_EXTENSION
set b_ext_str [expr {[info exists b_ext_desc($b_ext_val)] ? $b_ext_desc($b_ext_val) : "Unknown ($b_ext_val)"}]
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(B_EXTENSION) $b_ext_str]

set c_ext_val $RTL_PARAM_C_EXTENSION
set c_ext_str [expr {[info exists c_ext_desc($c_ext_val)] ? $c_ext_desc($c_ext_val) : "Unknown ($c_ext_val)"}]
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(C_EXTENSION) $c_ext_str]

set m_ext_val $RTL_PARAM_M_EXTENSION
set m_ext_str [expr {[info exists m_ext_desc($m_ext_val)] ? $m_ext_desc($m_ext_val) : "Unknown ($m_ext_val)"}]
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(M_EXTENSION) $m_ext_str]

set zicntr_val $RTL_PARAM_ZICNTR_EN
set zicntr_str [expr {$zicntr_val == 1 ? "Enabled (cycle, time, instret)" : "Disabled"}]
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(ZICNTR_EN) $zicntr_str]

set zihpm_val $RTL_PARAM_ZIHPM_NR
if {$zihpm_val == 0} {
    set zihpm_str "Disabled"
} elseif {$zihpm_val == 1} {
    set zihpm_str "1 counter: mhpmcounter3"
} else {
    set zihpm_str "$zihpm_val counters: mhpmcounter3..mhpmcounter[expr {$zihpm_val + 2}]"
}
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(ZIHPM_NR) $zihpm_str]

set sumode_val $RTL_PARAM_SU_MODE_EN
set sumode_str [expr {$sumode_val == 1 ? "Enabled (M + S + U modes)" : "Disabled (M-mode only)"}]
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(SU_MODE_EN) $sumode_str]

# PMP_NR: writable entries (0/4/8/16); Smepmp (mseccfg) is included whenever non-zero.
if {[info exists RTL_PARAM_PMP_NR]} {
    set pmp_val $RTL_PARAM_PMP_NR
    set pmp_str [expr {$pmp_val == 0 ? "Disabled" : "$pmp_val writable entries + Smepmp"}]
    append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(PMP_NR) $pmp_str]
}

# External Debug section (Sdext / Sdtrig). Guarded by [info exists] so an older
# rtl_params.tcl without the debug parameters still produces a valid report.
if {[info exists RTL_PARAM_DEBUG_EN]} {
    append ::RTL_CONFIG "     | EXTERNAL DEBUG:                                                                                   |\n"

    set debug_val $RTL_PARAM_DEBUG_EN
    set debug_str [expr {$debug_val == 1 ? "Enabled (DM + abstract access + SBA)" : "Disabled"}]
    append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(DEBUG_EN) $debug_str]

    # DM_TRIGGER_NR is gated by DEBUG_EN in the RTL (no triggers when debug is absent).
    if {[info exists RTL_PARAM_DM_TRIGGER_NR]} {
        if {$debug_val != 1} {
            set trig_str "Not present"
        } elseif {$RTL_PARAM_DM_TRIGGER_NR == 0} {
            set trig_str "None"
        } elseif {$RTL_PARAM_DM_TRIGGER_NR == 1} {
            set trig_str "1 mcontrol6 trigger"
        } else {
            set trig_str "$RTL_PARAM_DM_TRIGGER_NR mcontrol6 triggers"
        }
        append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(DM_TRIGGER_NR) $trig_str]
    }
}

# Arithmetic Units section
append ::RTL_CONFIG "     | ARITHMETIC UNITS:                                                                                 |\n"

if {$RTL_PARAM_M_EXTENSION >= 1} {
    set mul_desc $mul_type_desc($RTL_PARAM_MUL_TYPE)
    append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(MUL_TYPE) $mul_desc]
} else {
    append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(MUL_TYPE) "Not present"]
}

if {$RTL_PARAM_M_EXTENSION == 2} {
    set div_desc $div_type_desc($RTL_PARAM_DIV_TYPE)
    append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(DIV_TYPE) $div_desc]
} else {
    append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(DIV_TYPE) "Not present"]
}

# Other Configuration section
append ::RTL_CONFIG "     | OTHER CONFIGURATION:                                                                              |\n"

set rv32e_val $RTL_PARAM_RV32E_EN
set rv32e_str [expr {$rv32e_val == 1 ? "Enabled (16 integer registers)" : "Disabled (32 integer registers)"}]
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(RV32E_EN) $rv32e_str]

set scb_val $RTL_PARAM_SINGLE_CYCLE_BRANCH
set scb_str [expr {$scb_val == 1 ? "Single-cycle (zero-bubble, max IPC)" : "One-bubble (lower IPC, max Fmax)"}]
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(SINGLE_CYCLE_BRANCH) $scb_str]

set ccsr_val $RTL_PARAM_CCSR_EN
set ccsr_str [expr {$ccsr_val == 1 ? "Enabled " : "Disabled"}]
append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(CCSR_EN) $ccsr_str]

if {[info exists RTL_PARAM_ASYNC_RST_EN]} {
    set arst_str [expr {$RTL_PARAM_ASYNC_RST_EN == 1 ? "Asynchronous (active-low)" : "Synchronous"}]
    append ::RTL_CONFIG [format "     |                      %-27s : %-46s |\n" $param_desc(ASYNC_RST_EN) $arst_str]
}

append ::RTL_CONFIG "     +===================================================================================================+\n"

puts ""
puts "================================================================================"
puts "RTL configuration report generated"
puts "================================================================================"
puts ""

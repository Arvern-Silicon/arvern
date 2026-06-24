#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Module:    constraints_ports
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# File Name          : constraints_ports.tcl
# Module Description : Per-port input delay / output delay / load constraints for the arvern CPU.
#----------------------------------------------------------------------------

##############################################################################
#                                                                            #
#           BOUNDARY TIMINGS FOR THE GENERIC INTERCONNECT                    #
#                                                                            #
##############################################################################

#==================================#
#    INSTRUCTION AHB INTERFACES    #
#==================================#

# Inputs
set INST_HRDATA_DLY       [expr ($CLOCK_PERIOD/100) * 50]
set INST_HREADY_DLY       [expr ($CLOCK_PERIOD/100) * 50]
set INST_HRESP_DLY        [expr ($CLOCK_PERIOD/100) * 50]

# Outputs
set INST_HADDR_DLY        [expr ($CLOCK_PERIOD/100) * 30]
set INST_HBURST_DLY       [expr ($CLOCK_PERIOD/100) * 30]
set INST_HMASTLOCK_DLY    [expr ($CLOCK_PERIOD/100) * 30]
set INST_HPROT_DLY        [expr ($CLOCK_PERIOD/100) * 30]
set INST_HSIZE_DLY        [expr ($CLOCK_PERIOD/100) * 30]
set INST_HSMODE_DLY       [expr ($CLOCK_PERIOD/100) * 30]
set INST_HTRANS_DLY       [expr ($CLOCK_PERIOD/100) * 30]
set INST_HWDATA_DLY       [expr ($CLOCK_PERIOD/100) * 30]
set INST_HWRITE_DLY       [expr ($CLOCK_PERIOD/100) * 30]


set_input_delay $INST_HRDATA_DLY                 -max -clock "hclk"   [get_ports inst_hrdata_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports inst_hrdata_i]

set_input_delay $INST_HREADY_DLY                 -max -clock "hclk"   [get_ports inst_hready_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports inst_hready_i]

set_input_delay $INST_HRESP_DLY                  -max -clock "hclk"   [get_ports inst_hresp_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports inst_hresp_i]


set_output_delay $INST_HADDR_DLY      -add_delay -max -clock "hclk"   [get_ports inst_haddr_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_haddr_o]

set_output_delay $INST_HBURST_DLY     -add_delay -max -clock "hclk"   [get_ports inst_hburst_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_hburst_o]

set_output_delay $INST_HMASTLOCK_DLY  -add_delay -max -clock "hclk"   [get_ports inst_hmastlock_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_hmastlock_o]

set_output_delay $INST_HPROT_DLY      -add_delay -max -clock "hclk"   [get_ports inst_hprot_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_hprot_o]

set_output_delay $INST_HSIZE_DLY      -add_delay -max -clock "hclk"   [get_ports inst_hsize_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_hsize_o]

set_output_delay $INST_HSMODE_DLY     -add_delay -max -clock "hclk"   [get_ports inst_hsmode_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_hsmode_o]

set_output_delay $INST_HTRANS_DLY     -add_delay -max -clock "hclk"   [get_ports inst_htrans_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_htrans_o]

set_output_delay $INST_HWDATA_DLY     -add_delay -max -clock "hclk"   [get_ports inst_hwdata_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_hwdata_o]

set_output_delay $INST_HWRITE_DLY     -add_delay -max -clock "hclk"   [get_ports inst_hwrite_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports inst_hwrite_o]


#==================================#
#       DATA AHB INTERFACES        #
#==================================#

# Inputs
set DATA_HRDATA_DLY       [expr ($CLOCK_PERIOD/100) * 55]
set DATA_HREADY_DLY       [expr ($CLOCK_PERIOD/100) * 55]
set DATA_HRESP_DLY        [expr ($CLOCK_PERIOD/100) * 55]

# Outputs
set DATA_HADDR_DLY        [expr ($CLOCK_PERIOD/100) * 30]
set DATA_HBURST_DLY       [expr ($CLOCK_PERIOD/100) * 30]
set DATA_HMASTLOCK_DLY    [expr ($CLOCK_PERIOD/100) * 30]
set DATA_HPROT_DLY        [expr ($CLOCK_PERIOD/100) * 30]
set DATA_HSIZE_DLY        [expr ($CLOCK_PERIOD/100) * 30]
set DATA_HSMODE_DLY       [expr ($CLOCK_PERIOD/100) * 30]
set DATA_HTRANS_DLY       [expr ($CLOCK_PERIOD/100) * 30]
set DATA_HWDATA_DLY       [expr ($CLOCK_PERIOD/100) * 30]
set DATA_HWRITE_DLY       [expr ($CLOCK_PERIOD/100) * 30]


set_input_delay $DATA_HRDATA_DLY                 -max -clock "hclk"   [get_ports data_hrdata_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports data_hrdata_i]

set_input_delay $DATA_HREADY_DLY                 -max -clock "hclk"   [get_ports data_hready_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports data_hready_i]

set_input_delay $DATA_HRESP_DLY                  -max -clock "hclk"   [get_ports data_hresp_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports data_hresp_i]


set_output_delay $DATA_HADDR_DLY      -add_delay -max -clock "hclk"   [get_ports data_haddr_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_haddr_o]

set_output_delay $DATA_HBURST_DLY     -add_delay -max -clock "hclk"   [get_ports data_hburst_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_hburst_o]

set_output_delay $DATA_HMASTLOCK_DLY  -add_delay -max -clock "hclk"   [get_ports data_hmastlock_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_hmastlock_o]

set_output_delay $DATA_HPROT_DLY      -add_delay -max -clock "hclk"   [get_ports data_hprot_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_hprot_o]

set_output_delay $DATA_HSIZE_DLY      -add_delay -max -clock "hclk"   [get_ports data_hsize_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_hsize_o]

set_output_delay $DATA_HSMODE_DLY     -add_delay -max -clock "hclk"   [get_ports data_hsmode_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_hsmode_o]

set_output_delay $DATA_HTRANS_DLY     -add_delay -max -clock "hclk"   [get_ports data_htrans_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_htrans_o]

set_output_delay $DATA_HWDATA_DLY     -add_delay -max -clock "hclk"   [get_ports data_hwdata_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_hwdata_o]

set_output_delay $DATA_HWRITE_DLY     -add_delay -max -clock "hclk"   [get_ports data_hwrite_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports data_hwrite_o]


#====================================#
# INTERFACE TO CUSTOM CSR REGISTERS  #
#====================================#

# Inputs
set CCSR_RDATA_DLY      [expr ($CLOCK_PERIOD/100) * 60]

# Outputs
set CCSR_BANK_DLY       [expr ($CLOCK_PERIOD/100) * 40]
set CCSR_REG_SEL_DLY    [expr ($CLOCK_PERIOD/100) * 40]
set CCSR_WDATA_DLY      [expr ($CLOCK_PERIOD/100) * 30]
set CCSR_WEN_DLY        [expr ($CLOCK_PERIOD/100) * 40]


set_input_delay $CCSR_RDATA_DLY                  -max -clock "hclk"   [get_ports ccsr_rdata_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports ccsr_rdata_i]


set_output_delay $CCSR_BANK_DLY       -add_delay -max -clock "hclk"   [get_ports ccsr_bank_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports ccsr_bank_o]

set_output_delay $CCSR_REG_SEL_DLY    -add_delay -max -clock "hclk"   [get_ports ccsr_reg_sel_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports ccsr_reg_sel_o]

set_output_delay $CCSR_WDATA_DLY      -add_delay -max -clock "hclk"   [get_ports ccsr_wdata_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports ccsr_wdata_o]

set_output_delay $CCSR_WEN_DLY        -add_delay -max -clock "hclk"   [get_ports ccsr_wen_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports ccsr_wen_o]


#=========================#
# REMAINING PORTS         #
#=========================#

set HCLK_EN_DLY         [expr ($CLOCK_PERIOD/100) * 50]

set RESET_VECTOR_DLY    [expr ($CLOCK_PERIOD/100) * 20]

# CLOCK ENABLE
set_output_delay $HCLK_EN_DLY         -add_delay -max -clock "hclk"   [get_ports hclk_en_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports hclk_en_o]

# ARBITER INTERFACES
set_input_delay $RESET_VECTOR_DLY                -max -clock "hclk"   [get_ports reset_vector_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports reset_vector_i]


#=========================#
# INTERRUPT INPUTS        #
#=========================#

set IRQ_DLY             [expr ($CLOCK_PERIOD/100) * 40]

set_input_delay $IRQ_DLY                         -max -clock "hclk"   [get_ports irq_m_software_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports irq_m_software_i]

set_input_delay $IRQ_DLY                         -max -clock "hclk"   [get_ports irq_s_software_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports irq_s_software_i]

set_input_delay $IRQ_DLY                         -max -clock "hclk"   [get_ports irq_m_timer_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports irq_m_timer_i]

set_input_delay $IRQ_DLY                         -max -clock "hclk"   [get_ports irq_m_external_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports irq_m_external_i]

set_input_delay $IRQ_DLY                         -max -clock "hclk"   [get_ports irq_s_external_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports irq_s_external_i]

set_input_delay $IRQ_DLY                         -max -clock "hclk"   [get_ports irq_platform_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports irq_platform_i]

set_input_delay $IRQ_DLY                         -max -clock "hclk"   [get_ports nmi_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports nmi_i]


#=================================#
# STATIC CONFIGURATION INPUTS     #
#=================================#

set STATIC_CFG_DLY      [expr ($CLOCK_PERIOD/100) * 40]

set_input_delay $STATIC_CFG_DLY                  -max -clock "hclk"   [get_ports hartid_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports hartid_i]

set_input_delay $STATIC_CFG_DLY                  -max -clock "hclk"   [get_ports nmi_vector_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports nmi_vector_i]


#=================================#
# TIME INTERFACE                  #
#=================================#

set TIME_DLY            [expr ($CLOCK_PERIOD/100) * 60]

set_input_delay $TIME_DLY                        -max -clock "hclk"   [get_ports time_gnt_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports time_gnt_i]

set_input_delay $TIME_DLY                        -max -clock "hclk"   [get_ports time_val_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports time_val_i]

set TIME_REQ_DLY        [expr ($CLOCK_PERIOD/100) * 35]

set_output_delay $TIME_REQ_DLY        -add_delay -max -clock "hclk"   [get_ports time_req_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports time_req_o]


#=================================#
# HPM PLATFORM EVENTS             #
#=================================#

set HPM_EVT_DLY         [expr ($CLOCK_PERIOD/100) * 40]

set_input_delay $HPM_EVT_DLY                     -max -clock "hclk"   [get_ports hpm_platform_events_i]
set_input_delay 0                                -min -clock "hclk"   [get_ports hpm_platform_events_i]


#=================================#
# STATUS OUTPUTS                  #
#=================================#

set STATUS_DLY          [expr ($CLOCK_PERIOD/100) * 60]

set_output_delay $STATUS_DLY          -add_delay -max -clock "hclk"   [get_ports lockup_o]
set_output_delay 0                               -min -clock "hclk"   [get_ports lockup_o]


#========================#
# FEEDTHROUGH EXCEPTIONS #
#========================#

#set_max_delay [expr 2.0 + $DMEM_DOUT_DLY + $DMEM_ADDR_DLY] \
#              -from       [get_ports dmem_dout]            \
#              -to         [get_ports dmem_addr]            \
#              -group_path FEEDTHROUGH_OTHER


#=========================#
# RESET PATH (hresetn_i)   #
#=========================#
# How hresetn_i is timed depends on the reset architecture (ASYNC_RST_EN, set in
# rtl_params.tcl and sourced via read.tcl; defaults to async if not present):
#   1 = asynchronous reset -> drives the flops' async clear/preset directly; its
#       assertion isn't timed against hclk and its deassertion is synchronized
#       outside the core, so it stays a false path.
#   0 = synchronous reset  -> sampled on the hclk edge like any other synchronous
#       input, so constrain it with an input delay and let STA time it.
set HRESETN_ASYNC 1
if {[info exists RTL_PARAM_ASYNC_RST_EN]} { set HRESETN_ASYNC $RTL_PARAM_ASYNC_RST_EN }

if {$HRESETN_ASYNC} {
    set_false_path -from [get_ports hresetn_i]
} else {
    set HRESETN_DLY [expr ($CLOCK_PERIOD/100) * 40]
    set_input_delay $HRESETN_DLY                 -max -clock "hclk"   [get_ports hresetn_i]
    set_input_delay 0                            -min -clock "hclk"   [get_ports hresetn_i]
}

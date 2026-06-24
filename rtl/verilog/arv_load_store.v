//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_load_store
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_load_store.v
// Module Description : RISC-V load/store unit
//                      (data AHB master, alignment + access-fault detection, write-back of load data)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_load_store (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// DATA AHB BUS
    input  wire    [31:0] data_hrdata_i,
    input  wire           data_hready_i,
    input  wire           data_hresp_i,

    output wire    [31:0] data_haddr_o,
    output wire     [2:0] data_hburst_o,
    output wire           data_hmastlock_o,
    output wire     [3:0] data_hprot_o,
    output wire     [2:0] data_hsize_o,
    output wire           data_hsmode_o,
    output wire     [1:0] data_htrans_o,
    output wire    [31:0] data_hwdata_o,
    output wire           data_hwrite_o,

// OPERANDS (FROM REGISTER AND DECODER)
    input  wire    [31:0] ex_ldst_reg_addr_i,
    input  wire     [4:0] ex_ldst_reg_addr_sel_i,
    input  wire    [31:0] ex_store_reg_wdata_i,
    input  wire     [4:0] ex_store_reg_wdata_sel_i,
    input  wire    [31:0] ex_ldst_op_immediate_i,

// REGISTER WRITE DATA
    output wire           wb_load_busy_o,
    output wire           wb_load_reg_dest_wr_o,
    output wire    [31:0] wb_load_reg_dest_wdata_o,
    output wire     [4:0] wb_reg_dest_sel_o,

// INTERFACE TO DECODER
    input  wire     [4:0] ex_dec_ldst_control_i,
    input  wire     [1:0] priv_mode_ldst_i,
    input  wire     [4:0] ex_reg_dest_sel_i,
    input  wire     [4:0] ex_reg_dest_sel_mux_i,
    output wire           ex_ldst_ready_o,
    output wire           wb_ldst_ready_o,

// INTERFACE TO UOP SEQUENCER
    output wire           wb_dph_ongoing_o,
    input  wire           ex_uop_enable_i,
    input  wire     [4:0] ex_uop_ldst_control_i,
    input  wire    [31:0] ex_uop_ldst_immediate_i,
    input  wire     [4:0] ex_uop_ld_dest_sel_i,
    input  wire    [31:0] ex_uop_jt_base_i,

// ERROR DETECTION
    output wire           ex_excp_load_address_misaligned_o,
    output wire           ex_excp_store_address_misaligned_o,
    output wire           wb_excp_load_access_fault_o,
    output wire           wb_excp_store_access_fault_o,

// WAW HAZARD DETECTION
    input  wire           ex_alu_reg_dest_wr_i,
    input  wire           ex_csr_reg_dest_wr_i,

// PC PIPELINE FOR MEPC SAVE
    input  wire    [31:0] ex_pc_i,
    output wire    [31:0] wb_pc_o,

// DATA ADDRESS PIPELINE FOR MTVAL SAVE
    output wire    [31:0] wb_data_addr_o

);

// USER PARAMETERs
//========================================
parameter                 ARST_EN = 1'b1;


//////======================================================================================================================//////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////======================================================================================================================//////

wire                [4:0] ex_ldst_control;
wire                      ex_is_store;
wire                      ex_is_load_std;
wire                      ex_is_load_uop;
wire                      ex_is_load;
wire                [2:0] ex_size;
wire                      ex_load_type;
wire                      aph_ongoing;
wire                      aph_valid;
wire                      aph_wait;
wire                      dph_ongoing;
wire                      dph_ongoing_nxt;
wire                      dph_last;
wire                      dph_wait;
wire                      dph_valid;
wire                      dph_error1st;
wire                      dph_error;
wire                [1:0] dph_size;
wire                [1:0] dph_alsb;
wire               [31:0] data_hwdata_nxt;
wire                      hazard_store_rs2;
wire                      hazard_ldst_rs1;
wire               [31:0] ex_ldst_addr;
wire               [31:0] ex_ldst_imm;
wire               [31:0] ex_store_wdata;
wire                      dph_is_load;
wire                      dph_load_type;
wire                [7:0] ldst_reg_dest_wbyte;
wire               [15:0] ldst_reg_dest_whalf;
wire                      ex_excp_address_misaligned;
wire                      wb_excp_access_fault;
wire                      waw_conflict_detected;
wire                      waw_conflict;

//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                              DATA LOAD-STORE CONTROL                                                 //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
//////
////// The ADDRESS PHASE of the AHB transfer happens during the EX phase of the CPU pipeline
////// The DATA PHASE of the AHB transfer happens during the WB phase of the CPU pipeline
//////

// Control
assign ex_ldst_control  = (ex_dec_ldst_control_i | ex_uop_ldst_control_i);

assign ex_is_store      =        ex_ldst_control[0];
assign ex_is_load       =        ex_ldst_control[1];
assign ex_is_load_std   =        ex_dec_ldst_control_i[1];
assign ex_is_load_uop   =        ex_uop_ldst_control_i[1];
assign ex_size          = {1'b0, ex_ldst_control[3:2]};
assign ex_load_type     =        ex_ldst_control[4];

// AHB Interface: Address Phase state
assign aph_ongoing      = (ex_is_store | ex_is_load) & !ex_excp_address_misaligned & !hazard_ldst_rs1 & !dph_error;
assign aph_wait         = (aph_ongoing & !data_hready_i);
assign aph_valid        = (aph_ongoing &  data_hready_i);

// AHB Interface: Data Phase state
assign dph_last         = (dph_ongoing &  data_hready_i);
assign dph_wait         = (dph_ongoing & !data_hready_i);
assign dph_valid        = (dph_last    & !data_hresp_i );
assign dph_error1st     = (dph_wait    &  data_hresp_i );
assign dph_ongoing_nxt  =  aph_valid   ? 1'b1 :
                           dph_last    ? 1'b0 : dph_ongoing;

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_dph_ongoing (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(dph_ongoing_nxt), .q_o(dph_ongoing));

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_dph_error (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(dph_error1st),    .q_o(dph_error));

// Address and transfer control
assign ex_ldst_addr     =  ex_ldst_reg_addr_i | ex_uop_jt_base_i; // OR-mux (not a 2:1 mux) possible because these are guaranteed to be mutually exclusive by the decoder/uop sequencer
assign ex_ldst_imm      =  ({32{~ex_uop_enable_i}} & ex_ldst_op_immediate_i) | ex_uop_ldst_immediate_i;
assign data_haddr_o     =  ex_ldst_addr + ex_ldst_imm;
assign data_htrans_o    =  2'b10 & {2{aph_ongoing}};   // NONSEQ
assign data_hsize_o     =  ex_size;                    // 8/16/32-bit access
assign data_hwrite_o    =  ex_is_store;                // Read/Write access

// Format the data based on the transfer size
assign ex_store_wdata   =  hazard_store_rs2 ?    wb_load_reg_dest_wdata_o :  // In case STORE uses the data being currently loaded, we loop back HRDATA
                                                 ex_store_reg_wdata_i     ;
assign data_hwdata_nxt  = (ex_size==3'b000) ? {4{ex_store_wdata[ 7:0]}}   :
                          (ex_size==3'b001) ? {2{ex_store_wdata[15:0]}}   :
                                                 ex_store_wdata           ;

wire        data_hwdata_en  = (aph_valid & ex_is_store) | dph_last;
wire [31:0] data_hwdata_d   = (aph_valid & ex_is_store) ? data_hwdata_nxt :
                              dph_last                   ? 32'h00000000    : data_hwdata_o;

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_data_hwdata (
                   .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(data_hwdata_en), .d_i(data_hwdata_d), .q_o(data_hwdata_o));

// Detect special case if there is a STORE or LOAD in EX phase and a LOAD in WB with the same registers
//        + LOAD in WB and LOAD  in EX  -->  RS1 (addr) is consumed during EX phase.
//        + LOAD in WB and STORE in EX  -->  RS1 (addr) and RS2 (data) are consumed during EX phase.
// Note: hazard_store_rs2 is suppressed when a WAW conflict was detected (waw_conflict), meaning a newer
// EX-stage instruction already wrote to the same register. In that case, the register file already
// has the correct (newer) value and the stale WB load result must NOT be forwarded.
assign hazard_ldst_rs1          = (ex_is_store | ex_is_load) & (wb_reg_dest_sel_o != 0) & (ex_ldst_reg_addr_sel_i   == wb_reg_dest_sel_o) ;
assign hazard_store_rs2         =  ex_is_store               & (wb_reg_dest_sel_o != 0) & (ex_store_reg_wdata_sel_i == wb_reg_dest_sel_o) & ~waw_conflict;


// Static signals on the data bus
assign data_hburst_o            =  3'b000;                              // Single transfer burst
assign data_hmastlock_o         =  1'b0;                                // Unlocked sequence

assign data_hprot_o             = {1'b0, 1'b0, |priv_mode_ldst_i, 1'b1}; // {Non-cacheable; Non-bufferable; Privileged/User access; Data-access} (MPRV-aware)
assign data_hsmode_o            = (priv_mode_ldst_i==2'b01);             // Supervisor mode (MPRV-aware)

assign wb_load_reg_dest_wr_o    =  dph_valid & dph_is_load & ~waw_conflict;

assign ldst_reg_dest_wbyte      = (dph_alsb==2'b00)   ?  data_hrdata_i[ 7: 0] :
                                  (dph_alsb==2'b01)   ?  data_hrdata_i[15: 8] :
                                  (dph_alsb==2'b10)   ?  data_hrdata_i[23:16] :
                                                         data_hrdata_i[31:24] ;

assign ldst_reg_dest_whalf      = (dph_alsb[1]==1'b0) ?  data_hrdata_i[15: 0] :
                                                         data_hrdata_i[31:16] ;

assign wb_load_reg_dest_wdata_o = (dph_size==2'b00)   ? {{24{~dph_load_type & ldst_reg_dest_wbyte[ 7]}}, ldst_reg_dest_wbyte} :
                                  (dph_size==2'b01)   ? {{16{~dph_load_type & ldst_reg_dest_whalf[15]}}, ldst_reg_dest_whalf} :
                                                                                                         data_hrdata_i        ;

// We move from EX to WB at the end of the address phase
wire       wb_reg_dest_sel_en = (aph_valid & ex_is_load_std) | (aph_valid & ex_is_load_uop) | dph_last;
wire [4:0] wb_reg_dest_sel_d  = (aph_valid & ex_is_load_std) ? ex_reg_dest_sel_i     :
                                (aph_valid & ex_is_load_uop) ? ex_uop_ld_dest_sel_i  :
                                dph_last                     ? 5'h00                 : wb_reg_dest_sel_o;

arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_wb_reg_dest_sel (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(wb_reg_dest_sel_en), .d_i(wb_reg_dest_sel_d), .q_o(wb_reg_dest_sel_o));

// Detect when there is an ongoing LOAD
wire dph_is_load_en = (aph_valid & ex_is_load) | dph_last;
wire dph_is_load_d  = (aph_valid & ex_is_load) ? 1'b1 :
                      dph_last                 ? 1'b0 : dph_is_load;

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_dph_is_load (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dph_is_load_en),         .d_i(dph_is_load_d),     .q_o(dph_is_load));

arv_dff #(.WIDTH(2), .ARST_EN(ARST_EN)) u_dph_size (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(aph_valid & ex_is_load), .d_i(ex_size[1:0]),      .q_o(dph_size));

arv_dff #(.WIDTH(2), .ARST_EN(ARST_EN)) u_dph_alsb (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(aph_valid & ex_is_load), .d_i(data_haddr_o[1:0]), .q_o(dph_alsb));

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_dph_load_type (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(aph_valid & ex_is_load), .d_i(ex_load_type),      .q_o(dph_load_type));

// Business of load-store unit
assign wb_load_busy_o   =  dph_is_load;

// Detect wait states during address (EX) and data (WB) phases
assign ex_ldst_ready_o  = !aph_wait & !hazard_ldst_rs1;
assign wb_ldst_ready_o  = !dph_wait;
assign wb_dph_ongoing_o =  dph_ongoing;

// Error detection
assign wb_excp_access_fault               =   dph_error;
assign ex_excp_address_misaligned         =  (ex_size==3'b011)                               |
                                            ((ex_size==3'b010) & (data_haddr_o[1:0]!=2'b00)) |
                                            ((ex_size==3'b001) & (data_haddr_o[0]  !=1'b0 )) ;

assign ex_excp_load_address_misaligned_o  = ex_excp_address_misaligned &  ex_is_load & !hazard_ldst_rs1;
assign ex_excp_store_address_misaligned_o = ex_excp_address_misaligned & !ex_is_load & !hazard_ldst_rs1;

assign wb_excp_load_access_fault_o        = wb_excp_access_fault       &  dph_is_load;
assign wb_excp_store_access_fault_o       = wb_excp_access_fault       & !dph_is_load;


//////======================================================================================================================//////
//////                                              WAW HAZARD DETECTION                                                    //////
//////======================================================================================================================//////
//////
////// Detect when a newer EX-stage write (ALU or CSR) targets the same register as a pending
////// WB-stage load. If detected, suppress the stale load write to avoid overwriting the newer value.
//////

assign waw_conflict_detected = (ex_alu_reg_dest_wr_i | ex_csr_reg_dest_wr_i) &
                               (wb_reg_dest_sel_o != 5'h00) & (ex_reg_dest_sel_mux_i == wb_reg_dest_sel_o);

wire waw_conflict_en = (aph_valid & ex_is_load) | dph_last | (dph_ongoing & waw_conflict_detected);
wire waw_conflict_d  = (aph_valid & ex_is_load)            ? 1'b0 :
                       dph_last                            ? 1'b0 :
                       (dph_ongoing & waw_conflict_detected) ? 1'b1 : waw_conflict;

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_waw_conflict (
                   .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(waw_conflict_en), .d_i(waw_conflict_d), .q_o(waw_conflict));


//////======================================================================================================================//////
//////                                              WB-STAGE PC PIPELINE                                                    //////
//////======================================================================================================================//////

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_wb_pc (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(aph_valid), .d_i(ex_pc_i),      .q_o(wb_pc_o));

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_wb_data_addr (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(aph_valid), .d_i(data_haddr_o), .q_o(wb_data_addr_o));


endmodule // arv_load_store

`default_nettype wire

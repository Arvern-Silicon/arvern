//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_int_registers
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_int_registers.v
// Module Description : RISC-V integer register file
//                      (32x32 RV32I or 16x32 RV32E; multiple read ports with bypass for decode + execute)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_int_registers (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// DESTINATION REGISTER CONTROL (FOR ALU, LOAD UNIT AND CSR INTERFACE)
    input  wire     [4:0] ex_reg_dest_sel_i,
    input  wire     [4:0] wb_reg_dest_sel_i,

// REGISTER WRITE DATA FROM ALU
    input  wire           ex_alu_reg_dest_wr_i,
    input  wire    [31:0] ex_alu_reg_dest_wdata_i,

// REGISTER WRITE DATA FROM LOAD-STORE UNIT
    input  wire           wb_load_reg_dest_wr_i,
    input  wire    [31:0] wb_load_reg_dest_wdata_i,

// REGISTER WRITE DATA FROM CSR REGISTERS
    input  wire           ex_csr_reg_dest_wr_i,
    input  wire    [31:0] ex_csr_reg_dest_wdata_i,

// REGISTER READ DURING DECODE PHASE (FOR ALU & BRANCHES)
    input  wire     [4:0] id_reg_src1_sel_i,
    input  wire     [4:0] id_reg_src2_sel_i,
    input  wire     [4:0] id_branch_rs1_fast_sel_i,
    input  wire     [4:0] id_branch_rs2_fast_sel_i,
    output wire    [31:0] id_reg_src1_rdata_w_fwd_o,
    output wire    [31:0] id_reg_src2_rdata_w_fwd_o,
    output wire    [31:0] id_branch_rs1_rdata_w_fwd_o,
    output wire    [31:0] id_branch_rs2_rdata_w_fwd_o,

// REGISTER READ DURING EXECUTION PHASE (FOR LOAD-STORE AND UOP SEQUENCER)
    input  wire    [31:0] ex_uop_src1_sel_i,
    input  wire    [31:0] id_uop_src1_sel_i,
    input  wire    [31:0] ex_uop_src2_sel_i,
    input  wire     [4:0] ex_reg_src1_sel_i,
    input  wire     [4:0] ex_reg_src2_sel_i,
    output wire    [31:0] ex_reg_src1_rdata_wo_fwd_o,
    output wire    [31:0] ex_reg_src2_rdata_wo_fwd_o,

// UOP WRITE CONTROLS
    input  wire           ex_uop_a0_zero_en_i,
    input  wire           ex_uop_mv_dest_ctrl_i,
    input  wire     [4:0] ex_uop_mv_dest1_i,

// TRAP WRITE-BACK SUPPRESSION
    input  wire           trap_kill_ex_i,
    input  wire           trap_kill_wb_i,

// JALR SHADOW REGISTER
    input  wire           id_opcode_jalr_i,
    input  wire           ex_uop_ret_branch_i,
    output wire    [31:0] id_jalr_shadow_rdata_o,
    output wire     [4:0] id_jalr_shadow_sel_o,

// EX DESTINATION REGISTER (MUX OF DECODER AND UOP OVERRIDE, FOR WAW DETECTION)
    output wire     [4:0] ex_reg_dest_sel_mux_o

);

// USER PARAMETERs
//=========================================================================
parameter                 ARST_EN       = 1'b1;
parameter                 RV32I_EN      = 1'b1;
parameter                 C_EXT_EN      = 1'b0;


//////======================================================================================================================//////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////======================================================================================================================//////

wire                      ex_reg_dest_wr;
wire               [31:0] ex_reg_dest_sel_1hot;
wire               [31:0] ex_reg_dest_wdata;
wire                [4:0] ex_reg_dest_sel_mux;

wire                      wb_reg_dest_wr;
wire               [31:0] wb_reg_dest_sel_1hot;
wire               [31:0] wb_reg_dest_wdata;

wire                      ex_reg_src1_eq_dest;
wire                      ex_reg_src2_eq_dest;
wire                      ex_branch_rs1_eq_dest;
wire                      ex_branch_rs2_eq_dest;
wire                      wb_reg_src1_eq_dest;
wire                      wb_reg_src2_eq_dest;
wire                      wb_branch_rs1_eq_dest;
wire                      wb_branch_rs2_eq_dest;

wire               [33:0] id_reg_src1_sel_1hot;
wire               [33:0] id_reg_src2_sel_1hot;
wire               [33:0] id_branch_rs1_sel_1hot;
wire               [33:0] id_branch_rs2_sel_1hot;
wire               [31:0] ex_reg_src1_sel_1hot;
wire               [31:0] ex_reg_src2_sel_1hot;

wire               [31:0] reg_x00_zero_read;
wire               [31:0] reg_x01_ra_read;
wire               [31:0] reg_x02_sp_read;
wire               [31:0] reg_x03_gp_read;
wire               [31:0] reg_x04_tp_read;
wire               [31:0] reg_x05_t0_read;
wire               [31:0] reg_x06_t1_read;
wire               [31:0] reg_x07_t2_read;
wire               [31:0] reg_x08_s0_read;
wire               [31:0] reg_x09_s1_read;
wire               [31:0] reg_x10_a0_read;
wire               [31:0] reg_x11_a1_read;
wire               [31:0] reg_x12_a2_read;
wire               [31:0] reg_x13_a3_read;
wire               [31:0] reg_x14_a4_read;
wire               [31:0] reg_x15_a5_read;
wire               [31:0] reg_x16_a6_read;
wire               [31:0] reg_x17_a7_read;
wire               [31:0] reg_x18_s2_read;
wire               [31:0] reg_x19_s3_read;
wire               [31:0] reg_x20_s4_read;
wire               [31:0] reg_x21_s5_read;
wire               [31:0] reg_x22_s6_read;
wire               [31:0] reg_x23_s7_read;
wire               [31:0] reg_x24_s8_read;
wire               [31:0] reg_x25_s9_read;
wire               [31:0] reg_x26_s10_read;
wire               [31:0] reg_x27_s11_read;
wire               [31:0] reg_x28_t3_read;
wire               [31:0] reg_x29_t4_read;
wire               [31:0] reg_x30_t5_read;
wire               [31:0] reg_x31_t6_read;

wire               [31:0] id_reg_src1_rdata_wo_fwd;
wire               [31:0] id_reg_src2_rdata_wo_fwd;
wire               [31:0] id_branch_rs1_rdata_wo_fwd;
wire               [31:0] id_branch_rs2_rdata_wo_fwd;

wire                      ex_uop_ret_shadow_valid;
wire                [4:0] shadow_sel;
wire                      shadow_wr_from_ex;
wire                      shadow_wr_from_wb;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                 REGISTERS                                                            //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Trap write-back suppression: gate write enables internally
wire   ex_alu_wr_gated       = ex_alu_reg_dest_wr_i  & ~trap_kill_ex_i;
wire   ex_csr_wr_gated       = ex_csr_reg_dest_wr_i  & ~trap_kill_ex_i;
wire   wb_load_wr_gated      = wb_load_reg_dest_wr_i & ~trap_kill_wb_i;
wire   ex_uop_a0_gated       = ex_uop_a0_zero_en_i   & ~trap_kill_ex_i;
wire   ex_uop_mv_gated       = ex_uop_mv_dest_ctrl_i & ~trap_kill_ex_i;

// Destination Register selector EX phase
assign ex_reg_dest_wr        = (ex_alu_wr_gated | ex_csr_wr_gated);
assign ex_reg_dest_wdata     = ({32{ex_alu_wr_gated}} & ex_alu_reg_dest_wdata_i ) |
                               ({32{ex_csr_wr_gated}} & ex_csr_reg_dest_wdata_i ) ;
assign ex_reg_dest_sel_mux   = ex_uop_mv_gated ? ex_uop_mv_dest1_i : ex_reg_dest_sel_i;
assign ex_reg_dest_sel_mux_o = ex_reg_dest_sel_mux;

assign ex_reg_dest_sel_1hot  = ({31'h00000000, ex_reg_dest_wr} << ex_reg_dest_sel_mux);

// Destination Register selector WB phase
assign wb_reg_dest_wr        =  wb_load_wr_gated         ;
assign wb_reg_dest_wdata     =  wb_load_reg_dest_wdata_i ;
assign wb_reg_dest_sel_1hot  = ({31'h00000000, wb_reg_dest_wr} << wb_reg_dest_sel_i);


// X0 (zero)
//-----------------------------------------------
assign reg_x00_zero_read     = 32'h00000000;

// X1 (ra: return address for jumps)
//-----------------------------------------------
wire [31:0] reg_x01_ra;
assign      reg_x01_ra_read = reg_x01_ra;
wire        reg_x01_ra_en   =  ex_reg_dest_sel_1hot[1] | wb_reg_dest_sel_1hot[1];
wire [31:0] reg_x01_ra_nxt  =  ex_reg_dest_sel_1hot[1] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x01_ra (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x01_ra_en), .d_i(reg_x01_ra_nxt), .q_o(reg_x01_ra));

// X2 (sp: stack pointer)
//-----------------------------------------------
wire [31:0] reg_x02_sp;
assign      reg_x02_sp_read = reg_x02_sp;
wire        reg_x02_sp_en   =  ex_reg_dest_sel_1hot[2] | wb_reg_dest_sel_1hot[2];
wire [31:0] reg_x02_sp_nxt  =  ex_reg_dest_sel_1hot[2] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x02_sp (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x02_sp_en), .d_i(reg_x02_sp_nxt), .q_o(reg_x02_sp));

// X3  (gp: global pointer)
//-----------------------------------------------
wire [31:0] reg_x03_gp;
assign      reg_x03_gp_read = reg_x03_gp;
wire        reg_x03_gp_en   =  ex_reg_dest_sel_1hot[3] | wb_reg_dest_sel_1hot[3];
wire [31:0] reg_x03_gp_nxt  =  ex_reg_dest_sel_1hot[3] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x03_gp (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x03_gp_en), .d_i(reg_x03_gp_nxt), .q_o(reg_x03_gp));

// X4  (tp: thread pointer)
//-----------------------------------------------
wire [31:0] reg_x04_tp;
assign      reg_x04_tp_read = reg_x04_tp;
wire        reg_x04_tp_en   =  ex_reg_dest_sel_1hot[4] | wb_reg_dest_sel_1hot[4];
wire [31:0] reg_x04_tp_nxt  =  ex_reg_dest_sel_1hot[4] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x04_tp (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x04_tp_en), .d_i(reg_x04_tp_nxt), .q_o(reg_x04_tp));

// X5  (t0: temporary register 0)
//-----------------------------------------------
wire [31:0] reg_x05_t0;
assign      reg_x05_t0_read = reg_x05_t0;
wire        reg_x05_t0_en   =  ex_reg_dest_sel_1hot[5] | wb_reg_dest_sel_1hot[5];
wire [31:0] reg_x05_t0_nxt  =  ex_reg_dest_sel_1hot[5] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x05_t0 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x05_t0_en), .d_i(reg_x05_t0_nxt), .q_o(reg_x05_t0));

// X6  (t1: temporary register 1)
//-----------------------------------------------
wire [31:0] reg_x06_t1;
assign      reg_x06_t1_read = reg_x06_t1;
wire        reg_x06_t1_en   =  ex_reg_dest_sel_1hot[6] | wb_reg_dest_sel_1hot[6];
wire [31:0] reg_x06_t1_nxt  =  ex_reg_dest_sel_1hot[6] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x06_t1 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x06_t1_en), .d_i(reg_x06_t1_nxt), .q_o(reg_x06_t1));

// X7  (t2: temporary register 2)
//-----------------------------------------------
wire [31:0] reg_x07_t2;
assign      reg_x07_t2_read = reg_x07_t2;
wire        reg_x07_t2_en   =  ex_reg_dest_sel_1hot[7] | wb_reg_dest_sel_1hot[7];
wire [31:0] reg_x07_t2_nxt  =  ex_reg_dest_sel_1hot[7] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x07_t2 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x07_t2_en), .d_i(reg_x07_t2_nxt), .q_o(reg_x07_t2));

// X8  (s0: saved register 0)
//-----------------------------------------------
wire [31:0] reg_x08_s0;
assign      reg_x08_s0_read = reg_x08_s0;
wire        reg_x08_s0_en   =  ex_reg_dest_sel_1hot[8] | wb_reg_dest_sel_1hot[8];
wire [31:0] reg_x08_s0_nxt  =  ex_reg_dest_sel_1hot[8] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x08_s0 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x08_s0_en), .d_i(reg_x08_s0_nxt), .q_o(reg_x08_s0));

// X9  (s1: saved register 1)
//-----------------------------------------------
wire [31:0] reg_x09_s1;
assign      reg_x09_s1_read = reg_x09_s1;
wire        reg_x09_s1_en   =  ex_reg_dest_sel_1hot[9] | wb_reg_dest_sel_1hot[9];
wire [31:0] reg_x09_s1_nxt  =  ex_reg_dest_sel_1hot[9] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x09_s1 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x09_s1_en), .d_i(reg_x09_s1_nxt), .q_o(reg_x09_s1));

// X10 (a0: return value or function argument 0)
//-----------------------------------------------
// CM.POPRETZ semantics: zero a0/x10 on the final branch cycle (uop_counter==0).
wire [31:0] reg_x10_a0;
assign      reg_x10_a0_read = reg_x10_a0;
wire        reg_x10_a0_en   =  ex_uop_a0_gated | ex_reg_dest_sel_1hot[10] | wb_reg_dest_sel_1hot[10];
wire [31:0] reg_x10_a0_nxt  =  ex_uop_a0_gated          ? 32'h00000000      :
                               ex_reg_dest_sel_1hot[10] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x10_a0 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x10_a0_en), .d_i(reg_x10_a0_nxt), .q_o(reg_x10_a0));

// X11 (a1: return value or function argument 1)
//-----------------------------------------------
wire [31:0] reg_x11_a1;
assign      reg_x11_a1_read = reg_x11_a1;
wire        reg_x11_a1_en   =  ex_reg_dest_sel_1hot[11] | wb_reg_dest_sel_1hot[11];
wire [31:0] reg_x11_a1_nxt  =  ex_reg_dest_sel_1hot[11] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x11_a1 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x11_a1_en), .d_i(reg_x11_a1_nxt), .q_o(reg_x11_a1));

// X12 (a2: function argument 2)
//-----------------------------------------------
wire [31:0] reg_x12_a2;
assign      reg_x12_a2_read = reg_x12_a2;
wire        reg_x12_a2_en   =  ex_reg_dest_sel_1hot[12] | wb_reg_dest_sel_1hot[12];
wire [31:0] reg_x12_a2_nxt  =  ex_reg_dest_sel_1hot[12] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x12_a2 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x12_a2_en), .d_i(reg_x12_a2_nxt), .q_o(reg_x12_a2));

// X13 (a3: function argument 3)
//-----------------------------------------------
wire [31:0] reg_x13_a3;
assign      reg_x13_a3_read = reg_x13_a3;
wire        reg_x13_a3_en   =  ex_reg_dest_sel_1hot[13] | wb_reg_dest_sel_1hot[13];
wire [31:0] reg_x13_a3_nxt  =  ex_reg_dest_sel_1hot[13] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x13_a3 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x13_a3_en), .d_i(reg_x13_a3_nxt), .q_o(reg_x13_a3));

// X14 (a4: function argument 4)
//-----------------------------------------------
wire [31:0] reg_x14_a4;
assign      reg_x14_a4_read = reg_x14_a4;
wire        reg_x14_a4_en   =  ex_reg_dest_sel_1hot[14] | wb_reg_dest_sel_1hot[14];
wire [31:0] reg_x14_a4_nxt  =  ex_reg_dest_sel_1hot[14] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x14_a4 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x14_a4_en), .d_i(reg_x14_a4_nxt), .q_o(reg_x14_a4));

// X15 (a5: function argument 5)
//-----------------------------------------------
wire [31:0] reg_x15_a5;
assign      reg_x15_a5_read = reg_x15_a5;
wire        reg_x15_a5_en   =  ex_reg_dest_sel_1hot[15] | wb_reg_dest_sel_1hot[15];
wire [31:0] reg_x15_a5_nxt  =  ex_reg_dest_sel_1hot[15] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x15_a5 (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x15_a5_en), .d_i(reg_x15_a5_nxt), .q_o(reg_x15_a5));

generate
    if (RV32I_EN) begin : RV32I_MODE

        // X16 (a6: function argument 6)
        //-----------------------------------------------
        wire [31:0] reg_x16_a6;
        assign      reg_x16_a6_read = reg_x16_a6;
        wire        reg_x16_a6_en   =  ex_reg_dest_sel_1hot[16] | wb_reg_dest_sel_1hot[16];
        wire [31:0] reg_x16_a6_nxt  =  ex_reg_dest_sel_1hot[16] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x16_a6 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x16_a6_en), .d_i(reg_x16_a6_nxt), .q_o(reg_x16_a6));

        // X17 (a7: function argument 7)
        //-----------------------------------------------
        wire [31:0] reg_x17_a7;
        assign      reg_x17_a7_read = reg_x17_a7;
        wire        reg_x17_a7_en   =  ex_reg_dest_sel_1hot[17] | wb_reg_dest_sel_1hot[17];
        wire [31:0] reg_x17_a7_nxt  =  ex_reg_dest_sel_1hot[17] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x17_a7 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x17_a7_en), .d_i(reg_x17_a7_nxt), .q_o(reg_x17_a7));

        // X18 (s2: saved register 2)
        //-----------------------------------------------
        wire [31:0] reg_x18_s2;
        assign      reg_x18_s2_read = reg_x18_s2;
        wire        reg_x18_s2_en   =  ex_reg_dest_sel_1hot[18] | wb_reg_dest_sel_1hot[18];
        wire [31:0] reg_x18_s2_nxt  =  ex_reg_dest_sel_1hot[18] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x18_s2 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x18_s2_en), .d_i(reg_x18_s2_nxt), .q_o(reg_x18_s2));

        // X19 (s3: saved register 3)
        //-----------------------------------------------
        wire [31:0] reg_x19_s3;
        assign      reg_x19_s3_read = reg_x19_s3;
        wire        reg_x19_s3_en   =  ex_reg_dest_sel_1hot[19] | wb_reg_dest_sel_1hot[19];
        wire [31:0] reg_x19_s3_nxt  =  ex_reg_dest_sel_1hot[19] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x19_s3 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x19_s3_en), .d_i(reg_x19_s3_nxt), .q_o(reg_x19_s3));

        // X20 (s4: saved register 4)
        //-----------------------------------------------
        wire [31:0] reg_x20_s4;
        assign      reg_x20_s4_read = reg_x20_s4;
        wire        reg_x20_s4_en   =  ex_reg_dest_sel_1hot[20] | wb_reg_dest_sel_1hot[20];
        wire [31:0] reg_x20_s4_nxt  =  ex_reg_dest_sel_1hot[20] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x20_s4 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x20_s4_en), .d_i(reg_x20_s4_nxt), .q_o(reg_x20_s4));

        // X21 (s5: saved register 5)
        //-----------------------------------------------
        wire [31:0] reg_x21_s5;
        assign      reg_x21_s5_read = reg_x21_s5;
        wire        reg_x21_s5_en   =  ex_reg_dest_sel_1hot[21] | wb_reg_dest_sel_1hot[21];
        wire [31:0] reg_x21_s5_nxt  =  ex_reg_dest_sel_1hot[21] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x21_s5 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x21_s5_en), .d_i(reg_x21_s5_nxt), .q_o(reg_x21_s5));

        // X22 (s6: saved register 6)
        //-----------------------------------------------
        wire [31:0] reg_x22_s6;
        assign      reg_x22_s6_read = reg_x22_s6;
        wire        reg_x22_s6_en   =  ex_reg_dest_sel_1hot[22] | wb_reg_dest_sel_1hot[22];
        wire [31:0] reg_x22_s6_nxt  =  ex_reg_dest_sel_1hot[22] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x22_s6 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x22_s6_en), .d_i(reg_x22_s6_nxt), .q_o(reg_x22_s6));

        // X23 (s7: saved register 7)
        //-----------------------------------------------
        wire [31:0] reg_x23_s7;
        assign      reg_x23_s7_read = reg_x23_s7;
        wire        reg_x23_s7_en   =  ex_reg_dest_sel_1hot[23] | wb_reg_dest_sel_1hot[23];
        wire [31:0] reg_x23_s7_nxt  =  ex_reg_dest_sel_1hot[23] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x23_s7 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x23_s7_en), .d_i(reg_x23_s7_nxt), .q_o(reg_x23_s7));

        // X24 (s8: saved register 8)
        //-----------------------------------------------
        wire [31:0] reg_x24_s8;
        assign      reg_x24_s8_read = reg_x24_s8;
        wire        reg_x24_s8_en   =  ex_reg_dest_sel_1hot[24] | wb_reg_dest_sel_1hot[24];
        wire [31:0] reg_x24_s8_nxt  =  ex_reg_dest_sel_1hot[24] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x24_s8 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x24_s8_en), .d_i(reg_x24_s8_nxt), .q_o(reg_x24_s8));

        // X25 (s9: saved register 9)
        //-----------------------------------------------
        wire [31:0] reg_x25_s9;
        assign      reg_x25_s9_read = reg_x25_s9;
        wire        reg_x25_s9_en   =  ex_reg_dest_sel_1hot[25] | wb_reg_dest_sel_1hot[25];
        wire [31:0] reg_x25_s9_nxt  =  ex_reg_dest_sel_1hot[25] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x25_s9 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x25_s9_en), .d_i(reg_x25_s9_nxt), .q_o(reg_x25_s9));

        // X26 (s10: saved register 10)
        //-----------------------------------------------
        wire [31:0] reg_x26_s10;
        assign      reg_x26_s10_read = reg_x26_s10;
        wire        reg_x26_s10_en   =  ex_reg_dest_sel_1hot[26] | wb_reg_dest_sel_1hot[26];
        wire [31:0] reg_x26_s10_nxt  =  ex_reg_dest_sel_1hot[26] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x26_s10 (
                           .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x26_s10_en), .d_i(reg_x26_s10_nxt), .q_o(reg_x26_s10));

        // X27 (s11: saved register 11)
        //-----------------------------------------------
        wire [31:0] reg_x27_s11;
        assign      reg_x27_s11_read = reg_x27_s11;
        wire        reg_x27_s11_en   =  ex_reg_dest_sel_1hot[27] | wb_reg_dest_sel_1hot[27];
        wire [31:0] reg_x27_s11_nxt  =  ex_reg_dest_sel_1hot[27] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x27_s11 (
                           .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x27_s11_en), .d_i(reg_x27_s11_nxt), .q_o(reg_x27_s11));

        // X28 (t3: temporary register 3)
        //-----------------------------------------------
        wire [31:0] reg_x28_t3;
        assign      reg_x28_t3_read = reg_x28_t3;
        wire        reg_x28_t3_en   =  ex_reg_dest_sel_1hot[28] | wb_reg_dest_sel_1hot[28];
        wire [31:0] reg_x28_t3_nxt  =  ex_reg_dest_sel_1hot[28] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x28_t3 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x28_t3_en), .d_i(reg_x28_t3_nxt), .q_o(reg_x28_t3));

        // X29 (t4: temporary register 4)
        //-----------------------------------------------
        wire [31:0] reg_x29_t4;
        assign      reg_x29_t4_read = reg_x29_t4;
        wire        reg_x29_t4_en   =  ex_reg_dest_sel_1hot[29] | wb_reg_dest_sel_1hot[29];
        wire [31:0] reg_x29_t4_nxt  =  ex_reg_dest_sel_1hot[29] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x29_t4 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x29_t4_en), .d_i(reg_x29_t4_nxt), .q_o(reg_x29_t4));

        // X30 (t5: temporary register 5)
        //-----------------------------------------------
        wire [31:0] reg_x30_t5;
        assign      reg_x30_t5_read = reg_x30_t5;
        wire        reg_x30_t5_en   =  ex_reg_dest_sel_1hot[30] | wb_reg_dest_sel_1hot[30];
        wire [31:0] reg_x30_t5_nxt  =  ex_reg_dest_sel_1hot[30] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x30_t5 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x30_t5_en), .d_i(reg_x30_t5_nxt), .q_o(reg_x30_t5));

        // X31 (t6: temporary register 6)
        //-----------------------------------------------
        wire [31:0] reg_x31_t6;
        assign      reg_x31_t6_read = reg_x31_t6;
        wire        reg_x31_t6_en   =  ex_reg_dest_sel_1hot[31] | wb_reg_dest_sel_1hot[31];
        wire [31:0] reg_x31_t6_nxt  =  ex_reg_dest_sel_1hot[31] ? ex_reg_dest_wdata : wb_reg_dest_wdata;
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_reg_x31_t6 (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reg_x31_t6_en), .d_i(reg_x31_t6_nxt), .q_o(reg_x31_t6));

    end else begin         : RV32E_MODE

        // RV32E contract (RV32E_EN=1): x16..x31 do not exist. No flops are instantiated for
        // them; their read ports are hardwired 0 and any write whose destination decodes to
        // x16..x31 is silently dropped (no FF to update).
        assign reg_x16_a6_read  = 32'h00000000;
        assign reg_x17_a7_read  = 32'h00000000;
        assign reg_x18_s2_read  = 32'h00000000;
        assign reg_x19_s3_read  = 32'h00000000;
        assign reg_x20_s4_read  = 32'h00000000;
        assign reg_x21_s5_read  = 32'h00000000;
        assign reg_x22_s6_read  = 32'h00000000;
        assign reg_x23_s7_read  = 32'h00000000;
        assign reg_x24_s8_read  = 32'h00000000;
        assign reg_x25_s9_read  = 32'h00000000;
        assign reg_x26_s10_read = 32'h00000000;
        assign reg_x27_s11_read = 32'h00000000;
        assign reg_x28_t3_read  = 32'h00000000;
        assign reg_x29_t4_read  = 32'h00000000;
        assign reg_x30_t5_read  = 32'h00000000;
        assign reg_x31_t6_read  = 32'h00000000;

        // Lint: with x16..x31 absent, the upper one-hot select bits [31:16]
        // have no flop to drive. Full-width reads keep the select buses
        // clean in RV32E (they are fully consumed in RV32I).
        wire [15:0] ex_reg_dest_sel_1hot_unused = ex_reg_dest_sel_1hot[31:16];
        wire [15:0] wb_reg_dest_sel_1hot_unused = wb_reg_dest_sel_1hot[31:16];
    end
endgenerate

//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                           JALR SHADOW REGISTER                                                       //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Shadow register mirrors the RS1 register of the last JALR instruction.
// When a JALR uses the same RS1 as the previous one, the shadow value is
// immediately available without going through the 32:1 register read mux.
// When the RS1 changes, a 1-cycle stall is inserted to update the shadow.

// Validity: shadow tag matches current RS1 selector (used for JALR stall)
wire   id_jalr_shadow_valid       = (shadow_sel == id_reg_src1_sel_i);
assign id_jalr_shadow_sel_o       =  shadow_sel;
assign ex_uop_ret_shadow_valid    = (shadow_sel == 5'd1);

// RV32E narrowing for the shadow sub-system.
wire   rv32e_shadow_sel_upper     = ~RV32I_EN & shadow_sel[4];          // post-load: shadow points to non-existent upper reg
wire   rv32e_load_zero            = ~RV32I_EN & id_reg_src1_sel_i[4];   // active JALR: rs1 is in the non-existent upper half

// Shadow write tracking: update when the mirrored register is written.
// Under RV32E, suppress when shadow_sel addresses x16..x31 so a non-
// conforming write to an upper dest can't leak its wdata into the shadow.
assign shadow_wr_from_ex          =  ex_reg_dest_wr & (ex_reg_dest_sel_mux == shadow_sel) & (shadow_sel != 5'd0) & ~rv32e_shadow_sel_upper;
assign shadow_wr_from_wb          =  wb_reg_dest_wr & (wb_reg_dest_sel_i   == shadow_sel) & (shadow_sel != 5'd0) & ~rv32e_shadow_sel_upper;

// Shadow selector update: switch to new RS1 on JALR miss, or to x1 (ra) on UOP branch.
// Reset value rationale: in compressed mode compilers typically use x13 as the JALR
// base register, whereas in standard (non-compressed) mode they use x1 (ra); seeding
// shadow_sel with the most likely base avoids an initial JALR shadow-miss stall.
wire       shadow_sel_jalr_load = id_opcode_jalr_i    & ~id_jalr_shadow_valid;
wire       shadow_sel_ret_load  = ex_uop_ret_branch_i & ~ex_uop_ret_shadow_valid;
wire       shadow_sel_en        = shadow_sel_jalr_load | shadow_sel_ret_load;
wire [4:0] shadow_sel_nxt       = shadow_sel_jalr_load ? id_reg_src1_sel_i :
                                  shadow_sel_ret_load  ? 5'd1              : shadow_sel;

arv_dff #(.WIDTH(5), .RST_VAL(C_EXT_EN ? 5'd13 : 5'd1), .ARST_EN(ARST_EN)) u_shadow_sel (
                                                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(shadow_sel_en),
                                                                                         .d_i (shadow_sel_nxt),
                                                                                         .q_o (shadow_sel));

// Shadow data update: load on miss, then track writes.
// For UOP branch (CM.POPRET/POPRETZ), use reg_x01_ra_read directly (no 32:1 mux
// needed). x1 will be updated by the pop sequence before the branch at counter=0.
// On a JALR miss with rs1 in the RV32E-absent upper half, force the load to 0.
wire        shadow_rdata_en  = shadow_sel_jalr_load | shadow_sel_ret_load | shadow_wr_from_ex | shadow_wr_from_wb;
wire [31:0] shadow_rdata_nxt = shadow_sel_jalr_load ? (rv32e_load_zero ? 32'h00000000 : id_reg_src1_rdata_w_fwd_o) :
                               shadow_sel_ret_load  ?  reg_x01_ra_read   :
                               shadow_wr_from_ex     ?  ex_reg_dest_wdata :
                               shadow_wr_from_wb     ?  wb_reg_dest_wdata : id_jalr_shadow_rdata_o;

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_shadow_rdata (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(shadow_rdata_en),
                                                         .d_i (shadow_rdata_nxt),
                                                         .q_o (id_jalr_shadow_rdata_o));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                      READ PATHS FOR THE ALU AND BRANCHES                                             //////
//////                                (THESE PATHS ARE ACTIVE DURING THE DECODE PHASE)                                      //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Detect when the source and destination are the same (EX has priority over WB)
//
// Note on `ex_reg_dest_sel_i` vs `ex_reg_dest_sel_mux`: the actual write target
// during CM.MVA01S/MVSA01 phase-0 is `ex_reg_dest_sel_mux` (= ex_uop_mv_dest1_i),
// not `ex_reg_dest_sel_i`. The forwarding comparators below use `_i`, not `_mux`.
// Safety invariant: the UOP sequencer stalls decode during MV phase-0 (the
// `_mux != _i` window), so no new decode-stage rs1/rs2 comparison fires while
// the asymmetry is active. Phase-0's dest is committed before the next decode
// dispatch - see arv_uop_sequencer.v's uop_in_kill_window / stall logic.
assign ex_reg_src1_eq_dest        =  (id_reg_src1_sel_i==ex_reg_dest_sel_i) & ~ex_reg_dest_sel_1hot[0] & ex_reg_dest_wr ;
assign ex_reg_src2_eq_dest        =  (id_reg_src2_sel_i==ex_reg_dest_sel_i) & ~ex_reg_dest_sel_1hot[0] & ex_reg_dest_wr ;

assign wb_reg_src1_eq_dest        =  (id_reg_src1_sel_i==wb_reg_dest_sel_i) & ~wb_reg_dest_sel_1hot[0] & wb_reg_dest_wr & ~ex_reg_src1_eq_dest;
assign wb_reg_src2_eq_dest        =  (id_reg_src2_sel_i==wb_reg_dest_sel_i) & ~wb_reg_dest_sel_1hot[0] & wb_reg_dest_wr & ~ex_reg_src2_eq_dest;

// Forwarding comparators for fast-path branch rs1 & rs2 - same `_i` vs `_mux` rationale and
// UOP-stall invariant as above.
assign ex_branch_rs1_eq_dest      =  (id_branch_rs1_fast_sel_i==ex_reg_dest_sel_i) & ~ex_reg_dest_sel_1hot[0] & ex_reg_dest_wr;
assign ex_branch_rs2_eq_dest      =  (id_branch_rs2_fast_sel_i==ex_reg_dest_sel_i) & ~ex_reg_dest_sel_1hot[0] & ex_reg_dest_wr;

assign wb_branch_rs1_eq_dest      =  (id_branch_rs1_fast_sel_i==wb_reg_dest_sel_i) & ~wb_reg_dest_sel_1hot[0] & wb_reg_dest_wr & ~ex_branch_rs1_eq_dest;
assign wb_branch_rs2_eq_dest      =  (id_branch_rs2_fast_sel_i==wb_reg_dest_sel_i) & ~wb_reg_dest_sel_1hot[0] & wb_reg_dest_wr & ~ex_branch_rs2_eq_dest;

// Destination Register selector.
//
// id_uop_src1_sel_i ORs one extra register select into the low-32 field for UOP
// sequences. The ONLY bit it can ever set is x1/ra, and ONLY during the
// CM.POPRET/POPRETZ state-0 return micro-op (uop_ret_active in
// arv_uop_sequencer.v). It does NOT cleanly deliver x1/ra through this mux (see
// case (b)); the POPRET return value comes from the shadow register, not here.
// (No UOP sequence needs a 2nd decode-stage source, so id_reg_src2_sel_1hot has
// no UOP term - intentional asymmetry.)
//
// SELECT-FIELD CONTRACT (read-mux correctness) - the low-32 field is NOT
// guaranteed one-hot. Two multi-hot cases occur and are safe by construction:
//
//  (a) bit0/x0 is a harmless OR-identity: reg_x00_zero_read is hardwired 0, so
//      bit0 may co-assert with a real-register bit and contributes nothing.
//
//  (b) Genuinely 2-hot among TWO REAL regs (x2/sp | x1/ra) for exactly the
//      state-0 branch cycle of every CM.POPRET/POPRETZ: the decoder holds
//      id_reg_src1_sel = x2/sp for the whole sequence (Zcmp pop is in
//      id_c_class_rs1_sp, arv_decode.v) and the overlay adds x1/ra in that
//      cycle, so the mux output is reg_x02_sp | reg_x01_ra (corrupted). Safe
//      ONLY because nothing architecturally consumes it that cycle:
//        - the ALU is not enabled (ex_alu_mode/control = 0; the sp-restore add
//          ran the PREVIOUS micro-op in state-1 uop_sp_upd_active, where the
//          overlay is off so ex_operand1 was the CLEAN 1-hot x2/sp read, and
//          arv_uop_sequencer.v stalls in state-1 until that add retires so no
//          writeback bleeds into state-0); and
//        - the POPRET return PC is taken from the JALR shadow register, loaded
//          from reg_x01_ra_read DIRECTLY (shadow block below), never this mux.
//      Invariant a future editor MUST preserve: at most one real-register read
//      from this mux is ever architecturally consumed; the x2|x1 overlap is
//      allowed only while that POPRET state-0 ex_operand1 stays unconsumed AND
//      the return target stays shadow-sourced. Retiming the UOP sp-restore /
//      branch or the shadow path requires re-establishing this, else make the
//      field strictly one-hot among real regs.
// Forwarding tags [33:32] ({wb,ex}_reg_src1_eq_dest) are separate/orthogonal.
assign id_reg_src1_sel_1hot       = {wb_reg_src1_eq_dest, ex_reg_src1_eq_dest, (32'h00000001 << id_reg_src1_sel_i) | id_uop_src1_sel_i};
assign id_reg_src2_sel_1hot       = {wb_reg_src2_eq_dest, ex_reg_src2_eq_dest, (32'h00000001 << id_reg_src2_sel_i)};

// Source register 1 read mux
assign id_reg_src1_rdata_wo_fwd   = (reg_x00_zero_read    & {32{id_reg_src1_sel_1hot[ 0]}})   |
                                    (reg_x01_ra_read      & {32{id_reg_src1_sel_1hot[ 1]}})   |
                                    (reg_x02_sp_read      & {32{id_reg_src1_sel_1hot[ 2]}})   |
                                    (reg_x03_gp_read      & {32{id_reg_src1_sel_1hot[ 3]}})   |
                                    (reg_x04_tp_read      & {32{id_reg_src1_sel_1hot[ 4]}})   |
                                    (reg_x05_t0_read      & {32{id_reg_src1_sel_1hot[ 5]}})   |
                                    (reg_x06_t1_read      & {32{id_reg_src1_sel_1hot[ 6]}})   |
                                    (reg_x07_t2_read      & {32{id_reg_src1_sel_1hot[ 7]}})   |
                                    (reg_x08_s0_read      & {32{id_reg_src1_sel_1hot[ 8]}})   |
                                    (reg_x09_s1_read      & {32{id_reg_src1_sel_1hot[ 9]}})   |
                                    (reg_x10_a0_read      & {32{id_reg_src1_sel_1hot[10]}})   |
                                    (reg_x11_a1_read      & {32{id_reg_src1_sel_1hot[11]}})   |
                                    (reg_x12_a2_read      & {32{id_reg_src1_sel_1hot[12]}})   |
                                    (reg_x13_a3_read      & {32{id_reg_src1_sel_1hot[13]}})   |
                                    (reg_x14_a4_read      & {32{id_reg_src1_sel_1hot[14]}})   |
                                    (reg_x15_a5_read      & {32{id_reg_src1_sel_1hot[15]}})   |
                                    (reg_x16_a6_read      & {32{id_reg_src1_sel_1hot[16]}})   |
                                    (reg_x17_a7_read      & {32{id_reg_src1_sel_1hot[17]}})   |
                                    (reg_x18_s2_read      & {32{id_reg_src1_sel_1hot[18]}})   |
                                    (reg_x19_s3_read      & {32{id_reg_src1_sel_1hot[19]}})   |
                                    (reg_x20_s4_read      & {32{id_reg_src1_sel_1hot[20]}})   |
                                    (reg_x21_s5_read      & {32{id_reg_src1_sel_1hot[21]}})   |
                                    (reg_x22_s6_read      & {32{id_reg_src1_sel_1hot[22]}})   |
                                    (reg_x23_s7_read      & {32{id_reg_src1_sel_1hot[23]}})   |
                                    (reg_x24_s8_read      & {32{id_reg_src1_sel_1hot[24]}})   |
                                    (reg_x25_s9_read      & {32{id_reg_src1_sel_1hot[25]}})   |
                                    (reg_x26_s10_read     & {32{id_reg_src1_sel_1hot[26]}})   |
                                    (reg_x27_s11_read     & {32{id_reg_src1_sel_1hot[27]}})   |
                                    (reg_x28_t3_read      & {32{id_reg_src1_sel_1hot[28]}})   |
                                    (reg_x29_t4_read      & {32{id_reg_src1_sel_1hot[29]}})   |
                                    (reg_x30_t5_read      & {32{id_reg_src1_sel_1hot[30]}})   |
                                    (reg_x31_t6_read      & {32{id_reg_src1_sel_1hot[31]}})   ;

// Source register 1 including ongoing-writes
assign id_reg_src1_rdata_w_fwd_o  =  id_reg_src1_rdata_wo_fwd & {32{~(wb_reg_src1_eq_dest | ex_reg_src1_eq_dest)}} |
                                    (ex_reg_dest_wdata        & {32{id_reg_src1_sel_1hot[32]}})                    |
                                    (wb_reg_dest_wdata        & {32{id_reg_src1_sel_1hot[33]}})                    ;

// Branch Source register 1 read mux (fast-path branch rs1 read - uses id_branch_rs1_fast_sel_i (2-way mux, ~0.2ns vs 1.36ns for id_reg_src1_sel_i)
assign id_branch_rs1_sel_1hot     = {wb_branch_rs1_eq_dest, ex_branch_rs1_eq_dest, (32'h00000001 << id_branch_rs1_fast_sel_i)};
assign id_branch_rs1_rdata_wo_fwd = (reg_x00_zero_read    & {32{id_branch_rs1_sel_1hot[ 0]}})   |
                                    (reg_x01_ra_read      & {32{id_branch_rs1_sel_1hot[ 1]}})   |
                                    (reg_x02_sp_read      & {32{id_branch_rs1_sel_1hot[ 2]}})   |
                                    (reg_x03_gp_read      & {32{id_branch_rs1_sel_1hot[ 3]}})   |
                                    (reg_x04_tp_read      & {32{id_branch_rs1_sel_1hot[ 4]}})   |
                                    (reg_x05_t0_read      & {32{id_branch_rs1_sel_1hot[ 5]}})   |
                                    (reg_x06_t1_read      & {32{id_branch_rs1_sel_1hot[ 6]}})   |
                                    (reg_x07_t2_read      & {32{id_branch_rs1_sel_1hot[ 7]}})   |
                                    (reg_x08_s0_read      & {32{id_branch_rs1_sel_1hot[ 8]}})   |
                                    (reg_x09_s1_read      & {32{id_branch_rs1_sel_1hot[ 9]}})   |
                                    (reg_x10_a0_read      & {32{id_branch_rs1_sel_1hot[10]}})   |
                                    (reg_x11_a1_read      & {32{id_branch_rs1_sel_1hot[11]}})   |
                                    (reg_x12_a2_read      & {32{id_branch_rs1_sel_1hot[12]}})   |
                                    (reg_x13_a3_read      & {32{id_branch_rs1_sel_1hot[13]}})   |
                                    (reg_x14_a4_read      & {32{id_branch_rs1_sel_1hot[14]}})   |
                                    (reg_x15_a5_read      & {32{id_branch_rs1_sel_1hot[15]}})   |
                                    (reg_x16_a6_read      & {32{id_branch_rs1_sel_1hot[16]}})   |
                                    (reg_x17_a7_read      & {32{id_branch_rs1_sel_1hot[17]}})   |
                                    (reg_x18_s2_read      & {32{id_branch_rs1_sel_1hot[18]}})   |
                                    (reg_x19_s3_read      & {32{id_branch_rs1_sel_1hot[19]}})   |
                                    (reg_x20_s4_read      & {32{id_branch_rs1_sel_1hot[20]}})   |
                                    (reg_x21_s5_read      & {32{id_branch_rs1_sel_1hot[21]}})   |
                                    (reg_x22_s6_read      & {32{id_branch_rs1_sel_1hot[22]}})   |
                                    (reg_x23_s7_read      & {32{id_branch_rs1_sel_1hot[23]}})   |
                                    (reg_x24_s8_read      & {32{id_branch_rs1_sel_1hot[24]}})   |
                                    (reg_x25_s9_read      & {32{id_branch_rs1_sel_1hot[25]}})   |
                                    (reg_x26_s10_read     & {32{id_branch_rs1_sel_1hot[26]}})   |
                                    (reg_x27_s11_read     & {32{id_branch_rs1_sel_1hot[27]}})   |
                                    (reg_x28_t3_read      & {32{id_branch_rs1_sel_1hot[28]}})   |
                                    (reg_x29_t4_read      & {32{id_branch_rs1_sel_1hot[29]}})   |
                                    (reg_x30_t5_read      & {32{id_branch_rs1_sel_1hot[30]}})   |
                                    (reg_x31_t6_read      & {32{id_branch_rs1_sel_1hot[31]}})   ;

// Branch source register 1 including ongoing-writes
assign id_branch_rs1_rdata_w_fwd_o =  id_branch_rs1_rdata_wo_fwd & {32{~(wb_branch_rs1_eq_dest | ex_branch_rs1_eq_dest)}} |
                                     (ex_reg_dest_wdata          & {32{id_branch_rs1_sel_1hot[32]}})                      |
                                     (wb_reg_dest_wdata          & {32{id_branch_rs1_sel_1hot[33]}})                      ;

// Source register 2 read mux
assign id_reg_src2_rdata_wo_fwd   = (reg_x00_zero_read    & {32{id_reg_src2_sel_1hot[ 0]}})   |
                                    (reg_x01_ra_read      & {32{id_reg_src2_sel_1hot[ 1]}})   |
                                    (reg_x02_sp_read      & {32{id_reg_src2_sel_1hot[ 2]}})   |
                                    (reg_x03_gp_read      & {32{id_reg_src2_sel_1hot[ 3]}})   |
                                    (reg_x04_tp_read      & {32{id_reg_src2_sel_1hot[ 4]}})   |
                                    (reg_x05_t0_read      & {32{id_reg_src2_sel_1hot[ 5]}})   |
                                    (reg_x06_t1_read      & {32{id_reg_src2_sel_1hot[ 6]}})   |
                                    (reg_x07_t2_read      & {32{id_reg_src2_sel_1hot[ 7]}})   |
                                    (reg_x08_s0_read      & {32{id_reg_src2_sel_1hot[ 8]}})   |
                                    (reg_x09_s1_read      & {32{id_reg_src2_sel_1hot[ 9]}})   |
                                    (reg_x10_a0_read      & {32{id_reg_src2_sel_1hot[10]}})   |
                                    (reg_x11_a1_read      & {32{id_reg_src2_sel_1hot[11]}})   |
                                    (reg_x12_a2_read      & {32{id_reg_src2_sel_1hot[12]}})   |
                                    (reg_x13_a3_read      & {32{id_reg_src2_sel_1hot[13]}})   |
                                    (reg_x14_a4_read      & {32{id_reg_src2_sel_1hot[14]}})   |
                                    (reg_x15_a5_read      & {32{id_reg_src2_sel_1hot[15]}})   |
                                    (reg_x16_a6_read      & {32{id_reg_src2_sel_1hot[16]}})   |
                                    (reg_x17_a7_read      & {32{id_reg_src2_sel_1hot[17]}})   |
                                    (reg_x18_s2_read      & {32{id_reg_src2_sel_1hot[18]}})   |
                                    (reg_x19_s3_read      & {32{id_reg_src2_sel_1hot[19]}})   |
                                    (reg_x20_s4_read      & {32{id_reg_src2_sel_1hot[20]}})   |
                                    (reg_x21_s5_read      & {32{id_reg_src2_sel_1hot[21]}})   |
                                    (reg_x22_s6_read      & {32{id_reg_src2_sel_1hot[22]}})   |
                                    (reg_x23_s7_read      & {32{id_reg_src2_sel_1hot[23]}})   |
                                    (reg_x24_s8_read      & {32{id_reg_src2_sel_1hot[24]}})   |
                                    (reg_x25_s9_read      & {32{id_reg_src2_sel_1hot[25]}})   |
                                    (reg_x26_s10_read     & {32{id_reg_src2_sel_1hot[26]}})   |
                                    (reg_x27_s11_read     & {32{id_reg_src2_sel_1hot[27]}})   |
                                    (reg_x28_t3_read      & {32{id_reg_src2_sel_1hot[28]}})   |
                                    (reg_x29_t4_read      & {32{id_reg_src2_sel_1hot[29]}})   |
                                    (reg_x30_t5_read      & {32{id_reg_src2_sel_1hot[30]}})   |
                                    (reg_x31_t6_read      & {32{id_reg_src2_sel_1hot[31]}})   ;

// Source register 2 including ongoing-writes
assign id_reg_src2_rdata_w_fwd_o  =  id_reg_src2_rdata_wo_fwd & {32{~(wb_reg_src2_eq_dest | ex_reg_src2_eq_dest)}} |
                                    (ex_reg_dest_wdata        & {32{id_reg_src2_sel_1hot[32]}})                    |
                                    (wb_reg_dest_wdata        & {32{id_reg_src2_sel_1hot[33]}})                    ;

// Timing: fast-path branch rs2 read - uses id_branch_rs2_fast_sel_i
assign id_branch_rs2_sel_1hot     = {wb_branch_rs2_eq_dest, ex_branch_rs2_eq_dest, (32'h00000001 << id_branch_rs2_fast_sel_i)};
assign id_branch_rs2_rdata_wo_fwd = (reg_x00_zero_read    & {32{id_branch_rs2_sel_1hot[ 0]}})   |
                                    (reg_x01_ra_read      & {32{id_branch_rs2_sel_1hot[ 1]}})   |
                                    (reg_x02_sp_read      & {32{id_branch_rs2_sel_1hot[ 2]}})   |
                                    (reg_x03_gp_read      & {32{id_branch_rs2_sel_1hot[ 3]}})   |
                                    (reg_x04_tp_read      & {32{id_branch_rs2_sel_1hot[ 4]}})   |
                                    (reg_x05_t0_read      & {32{id_branch_rs2_sel_1hot[ 5]}})   |
                                    (reg_x06_t1_read      & {32{id_branch_rs2_sel_1hot[ 6]}})   |
                                    (reg_x07_t2_read      & {32{id_branch_rs2_sel_1hot[ 7]}})   |
                                    (reg_x08_s0_read      & {32{id_branch_rs2_sel_1hot[ 8]}})   |
                                    (reg_x09_s1_read      & {32{id_branch_rs2_sel_1hot[ 9]}})   |
                                    (reg_x10_a0_read      & {32{id_branch_rs2_sel_1hot[10]}})   |
                                    (reg_x11_a1_read      & {32{id_branch_rs2_sel_1hot[11]}})   |
                                    (reg_x12_a2_read      & {32{id_branch_rs2_sel_1hot[12]}})   |
                                    (reg_x13_a3_read      & {32{id_branch_rs2_sel_1hot[13]}})   |
                                    (reg_x14_a4_read      & {32{id_branch_rs2_sel_1hot[14]}})   |
                                    (reg_x15_a5_read      & {32{id_branch_rs2_sel_1hot[15]}})   |
                                    (reg_x16_a6_read      & {32{id_branch_rs2_sel_1hot[16]}})   |
                                    (reg_x17_a7_read      & {32{id_branch_rs2_sel_1hot[17]}})   |
                                    (reg_x18_s2_read      & {32{id_branch_rs2_sel_1hot[18]}})   |
                                    (reg_x19_s3_read      & {32{id_branch_rs2_sel_1hot[19]}})   |
                                    (reg_x20_s4_read      & {32{id_branch_rs2_sel_1hot[20]}})   |
                                    (reg_x21_s5_read      & {32{id_branch_rs2_sel_1hot[21]}})   |
                                    (reg_x22_s6_read      & {32{id_branch_rs2_sel_1hot[22]}})   |
                                    (reg_x23_s7_read      & {32{id_branch_rs2_sel_1hot[23]}})   |
                                    (reg_x24_s8_read      & {32{id_branch_rs2_sel_1hot[24]}})   |
                                    (reg_x25_s9_read      & {32{id_branch_rs2_sel_1hot[25]}})   |
                                    (reg_x26_s10_read     & {32{id_branch_rs2_sel_1hot[26]}})   |
                                    (reg_x27_s11_read     & {32{id_branch_rs2_sel_1hot[27]}})   |
                                    (reg_x28_t3_read      & {32{id_branch_rs2_sel_1hot[28]}})   |
                                    (reg_x29_t4_read      & {32{id_branch_rs2_sel_1hot[29]}})   |
                                    (reg_x30_t5_read      & {32{id_branch_rs2_sel_1hot[30]}})   |
                                    (reg_x31_t6_read      & {32{id_branch_rs2_sel_1hot[31]}})   ;
assign id_branch_rs2_rdata_w_fwd_o =  id_branch_rs2_rdata_wo_fwd & {32{~(wb_branch_rs2_eq_dest | ex_branch_rs2_eq_dest)}} |
                                     (ex_reg_dest_wdata          & {32{id_branch_rs2_sel_1hot[32]}})                      |
                                     (wb_reg_dest_wdata          & {32{id_branch_rs2_sel_1hot[33]}})                      ;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       READ PATHS FOR THE LOAD/STORE UNIT                                             //////
//////                               (THESE PATHS ARE ACTIVE DURING THE EXECUTION PHASE)                                    //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Destination Register selector (EX phase).
//
// SELECT-FIELD CONTRACT - distinct from the decode-phase block above; the EX
// overlay (ex_uop_src1_sel_i) is a DIFFERENT signal: it sets x2/sp (not x1),
// only during the UOP push/pop load-store micro-ops (uop_load_store_en,
// arv_uop_sequencer.v). Unlike the decode-phase mux this is NEVER 2-hot among
// two real regs:
//   - normal load/store/op: overlay = 0, base = the real rs1 -> 1-hot.
//   - UOP push/pop ldst: overlay = x2/sp, and the base ex_reg_src1_sel_i is
//     forced to x0 (ex_reg_src1_sel_o = {5{ex_ldst_busy}} & ..., arv_decode.v,
//     and ex_ldst_busy = 0 for a UOP because the UOP LSU uses the separate
//     ex_uop_ldst_control path, arv_load_store.v - decode's ex_ldst_control is
//     not set). So the field is {x0, x2}: x0 is the hardwired-0 OR-identity, so
//     the read is cleanly reg_x02_sp.
// Invariant a future editor MUST preserve: if a UOP ldst ever drives a non-x0
// base here while the x2/sp overlay is active, the read becomes a real 2-hot
// (basereg | sp) corrupted address. Keep ex_ldst_busy gating the base to x0 for
// UOP ldst, or make this field one-hot among real regs.
// Forwarding tags are not merged at EX phase (no [33:32] here, unlike decode).
assign ex_reg_src1_sel_1hot       = (32'h00000001 << ex_reg_src1_sel_i) | ex_uop_src1_sel_i;
assign ex_reg_src2_sel_1hot       = (32'h00000001 << ex_reg_src2_sel_i) | ex_uop_src2_sel_i;

// Source register 1
assign ex_reg_src1_rdata_wo_fwd_o = (reg_x00_zero_read    & {32{ex_reg_src1_sel_1hot[ 0]}})  |
                                    (reg_x01_ra_read      & {32{ex_reg_src1_sel_1hot[ 1]}})  |
                                    (reg_x02_sp_read      & {32{ex_reg_src1_sel_1hot[ 2]}})  |
                                    (reg_x03_gp_read      & {32{ex_reg_src1_sel_1hot[ 3]}})  |
                                    (reg_x04_tp_read      & {32{ex_reg_src1_sel_1hot[ 4]}})  |
                                    (reg_x05_t0_read      & {32{ex_reg_src1_sel_1hot[ 5]}})  |
                                    (reg_x06_t1_read      & {32{ex_reg_src1_sel_1hot[ 6]}})  |
                                    (reg_x07_t2_read      & {32{ex_reg_src1_sel_1hot[ 7]}})  |
                                    (reg_x08_s0_read      & {32{ex_reg_src1_sel_1hot[ 8]}})  |
                                    (reg_x09_s1_read      & {32{ex_reg_src1_sel_1hot[ 9]}})  |
                                    (reg_x10_a0_read      & {32{ex_reg_src1_sel_1hot[10]}})  |
                                    (reg_x11_a1_read      & {32{ex_reg_src1_sel_1hot[11]}})  |
                                    (reg_x12_a2_read      & {32{ex_reg_src1_sel_1hot[12]}})  |
                                    (reg_x13_a3_read      & {32{ex_reg_src1_sel_1hot[13]}})  |
                                    (reg_x14_a4_read      & {32{ex_reg_src1_sel_1hot[14]}})  |
                                    (reg_x15_a5_read      & {32{ex_reg_src1_sel_1hot[15]}})  |
                                    (reg_x16_a6_read      & {32{ex_reg_src1_sel_1hot[16]}})  |
                                    (reg_x17_a7_read      & {32{ex_reg_src1_sel_1hot[17]}})  |
                                    (reg_x18_s2_read      & {32{ex_reg_src1_sel_1hot[18]}})  |
                                    (reg_x19_s3_read      & {32{ex_reg_src1_sel_1hot[19]}})  |
                                    (reg_x20_s4_read      & {32{ex_reg_src1_sel_1hot[20]}})  |
                                    (reg_x21_s5_read      & {32{ex_reg_src1_sel_1hot[21]}})  |
                                    (reg_x22_s6_read      & {32{ex_reg_src1_sel_1hot[22]}})  |
                                    (reg_x23_s7_read      & {32{ex_reg_src1_sel_1hot[23]}})  |
                                    (reg_x24_s8_read      & {32{ex_reg_src1_sel_1hot[24]}})  |
                                    (reg_x25_s9_read      & {32{ex_reg_src1_sel_1hot[25]}})  |
                                    (reg_x26_s10_read     & {32{ex_reg_src1_sel_1hot[26]}})  |
                                    (reg_x27_s11_read     & {32{ex_reg_src1_sel_1hot[27]}})  |
                                    (reg_x28_t3_read      & {32{ex_reg_src1_sel_1hot[28]}})  |
                                    (reg_x29_t4_read      & {32{ex_reg_src1_sel_1hot[29]}})  |
                                    (reg_x30_t5_read      & {32{ex_reg_src1_sel_1hot[30]}})  |
                                    (reg_x31_t6_read      & {32{ex_reg_src1_sel_1hot[31]}})  ;

// Source register 2
assign ex_reg_src2_rdata_wo_fwd_o = (reg_x00_zero_read    & {32{ex_reg_src2_sel_1hot[ 0]}})  |
                                    (reg_x01_ra_read      & {32{ex_reg_src2_sel_1hot[ 1]}})  |
                                    (reg_x02_sp_read      & {32{ex_reg_src2_sel_1hot[ 2]}})  |
                                    (reg_x03_gp_read      & {32{ex_reg_src2_sel_1hot[ 3]}})  |
                                    (reg_x04_tp_read      & {32{ex_reg_src2_sel_1hot[ 4]}})  |
                                    (reg_x05_t0_read      & {32{ex_reg_src2_sel_1hot[ 5]}})  |
                                    (reg_x06_t1_read      & {32{ex_reg_src2_sel_1hot[ 6]}})  |
                                    (reg_x07_t2_read      & {32{ex_reg_src2_sel_1hot[ 7]}})  |
                                    (reg_x08_s0_read      & {32{ex_reg_src2_sel_1hot[ 8]}})  |
                                    (reg_x09_s1_read      & {32{ex_reg_src2_sel_1hot[ 9]}})  |
                                    (reg_x10_a0_read      & {32{ex_reg_src2_sel_1hot[10]}})  |
                                    (reg_x11_a1_read      & {32{ex_reg_src2_sel_1hot[11]}})  |
                                    (reg_x12_a2_read      & {32{ex_reg_src2_sel_1hot[12]}})  |
                                    (reg_x13_a3_read      & {32{ex_reg_src2_sel_1hot[13]}})  |
                                    (reg_x14_a4_read      & {32{ex_reg_src2_sel_1hot[14]}})  |
                                    (reg_x15_a5_read      & {32{ex_reg_src2_sel_1hot[15]}})  |
                                    (reg_x16_a6_read      & {32{ex_reg_src2_sel_1hot[16]}})  |
                                    (reg_x17_a7_read      & {32{ex_reg_src2_sel_1hot[17]}})  |
                                    (reg_x18_s2_read      & {32{ex_reg_src2_sel_1hot[18]}})  |
                                    (reg_x19_s3_read      & {32{ex_reg_src2_sel_1hot[19]}})  |
                                    (reg_x20_s4_read      & {32{ex_reg_src2_sel_1hot[20]}})  |
                                    (reg_x21_s5_read      & {32{ex_reg_src2_sel_1hot[21]}})  |
                                    (reg_x22_s6_read      & {32{ex_reg_src2_sel_1hot[22]}})  |
                                    (reg_x23_s7_read      & {32{ex_reg_src2_sel_1hot[23]}})  |
                                    (reg_x24_s8_read      & {32{ex_reg_src2_sel_1hot[24]}})  |
                                    (reg_x25_s9_read      & {32{ex_reg_src2_sel_1hot[25]}})  |
                                    (reg_x26_s10_read     & {32{ex_reg_src2_sel_1hot[26]}})  |
                                    (reg_x27_s11_read     & {32{ex_reg_src2_sel_1hot[27]}})  |
                                    (reg_x28_t3_read      & {32{ex_reg_src2_sel_1hot[28]}})  |
                                    (reg_x29_t4_read      & {32{ex_reg_src2_sel_1hot[29]}})  |
                                    (reg_x30_t5_read      & {32{ex_reg_src2_sel_1hot[30]}})  |
                                    (reg_x31_t6_read      & {32{ex_reg_src2_sel_1hot[31]}})  ;


endmodule // arv_int_registers

`default_nettype wire

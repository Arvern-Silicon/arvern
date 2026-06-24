//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_csr_cntr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_csr_cntr.v
// Module Description : RISC-V CSRs: Zicntr counter / timer (mcycle / minstret / mcounteren + U-mode shadows)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_csr_cntr (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// BANK ENABLES (DRIVEN BY arv_csr_top)
    input  wire           bank_mcycle_i,       // 0xB00-0xB3F (mcycle, minstret)
    input  wire           bank_mcycleh_i,      // 0xB80-0xBBF (mcycleh, minstreth)
    input  wire           bank_counter_i,      // 0xC00-0xC3F (cycle, time, instret)
    input  wire           bank_counterh_i,     // 0xC80-0xCBF (cycleh, timeh, instreth)
    input  wire           bank_mtrap_setup_i,  // 0x300-0x33F (for mcounteren@0x306, mcountinhibit@0x320)

    input  wire    [63:0] register_sel_i,
    input  wire    [31:0] register_value_nxt_i,
    input  wire           disable_write_i,

    input  wire           inst_retired_i,

// TIME INTERFACE
    output wire           time_req_o,
    input  wire           time_gnt_i,
    input  wire    [63:0] time_val_i,

    output wire           ex_csr_ready_o,
    output wire     [2:0] mcounteren_o,
    output wire    [31:0] counters_rdata_o

);

// USER PARAMETERs
//========================================
parameter   ARST_EN = 1'b1;   // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)


//////======================================================================================================================//////
//////                                       ZICNTR IMPLEMENTATION                                                          //////
//////======================================================================================================================//////

//------------------------------------------------------------------
// Counter registers
//------------------------------------------------------------------
wire [63:0] mcycle_reg;    // mcycleh  : mcycle   - free-running cycle counter
wire [63:0] minstret_reg;  // minstreth: minstret - instructions-retired counter
wire  [2:0] mcounteren_reg;
wire  [2:0] mcountinhibit_reg;

//------------------------------------------------------------------
// Write enables
//------------------------------------------------------------------
wire mcycle_wr        = bank_mcycle_i      & register_sel_i[0]  & ~disable_write_i;
wire mcycleh_wr       = bank_mcycleh_i     & register_sel_i[0]  & ~disable_write_i;
wire minstret_wr      = bank_mcycle_i      & register_sel_i[2]  & ~disable_write_i;
wire minstreth_wr     = bank_mcycleh_i     & register_sel_i[2]  & ~disable_write_i;

// SPLIT-OWNERSHIP CONTRACT (mcounteren @0x306 / mcountinhibit @0x320): the
// conceptual 11-bit registers are partitioned across two modules. THIS module
// (arv_csr_cntr) owns bits [2:0] (CY/TM/IR). arv_csr_hpm independently decodes
// the SAME write-enables and owns bits [10:3] (HPM3-10).
// Both modules must keep these two mcounteren_wr/mcountinhibit_wr derivations
// identical (bank_mtrap_setup_i & register_sel_i[6]/[32] & ~disable_write_i).
wire mcounteren_wr    = bank_mtrap_setup_i & register_sel_i[6]  & ~disable_write_i;
wire mcountinhibit_wr = bank_mtrap_setup_i & register_sel_i[32] & ~disable_write_i;

//------------------------------------------------------------------
// mcycle counter (free-running, inhibitable via mcountinhibit[0])
//------------------------------------------------------------------

// Gate carry by ~mcycle_wr: when the user writes lo the same cycle as the
// (lo == 0xFFFFFFFF) wrap, write wins on lo and the count event is absorbed,
// so hi must NOT spuriously increment.
wire        mcycle_incr_msb = (mcycle_reg[31:0] == 32'hFFFFFFFF) & !mcountinhibit_reg[0] & ~mcycle_wr;

// Priority write > increment > hold, expressed as enable + next-state for arv_dff.
wire        mcycle_lo_en    = mcycle_wr  | ~mcountinhibit_reg[0];
wire [31:0] mcycle_lo_nxt   = mcycle_wr  ? register_value_nxt_i : (mcycle_reg[31:0]  + 32'h00000001);
wire        mcycle_hi_en    = mcycleh_wr | mcycle_incr_msb;
wire [31:0] mcycle_hi_nxt   = mcycleh_wr ? register_value_nxt_i : (mcycle_reg[63:32] + 32'h00000001);

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mcycle_lo (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcycle_lo_en),
                                                       .d_i (mcycle_lo_nxt),
                                                       .q_o (mcycle_reg[31:0]));

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mcycle_hi (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcycle_hi_en),
                                                       .d_i (mcycle_hi_nxt),
                                                       .q_o (mcycle_reg[63:32]));

//------------------------------------------------------------------
// minstret counter (instruction-retired, inhibitable via mcountinhibit[2])
//
// mcountinhibit forwarding: use the value that mcountinhibit_reg WILL have
// after this clock edge (i.e. the write value when mcountinhibit_wr is active,
// otherwise the current registered value).
//------------------------------------------------------------------
wire  [2:0] mcountinhibit_nxt = mcountinhibit_wr ? register_value_nxt_i[2:0] : mcountinhibit_reg;

// Gate carry by inst_retired_i so that stall cycles (where lo stays at
// 0xFFFFFFFF with no instruction retiring) do not spuriously increment hi.
// Also gate by ~minstret_wr: a CSR write to lo the same cycle as a retire
// event with old lo == 0xFFFFFFFF must NOT carry (write wins on lo).
wire        minstret_incr_msb = (minstret_reg[31:0] == 32'hFFFFFFFF) & inst_retired_i & !mcountinhibit_nxt[2] & ~minstret_wr;

wire        minstret_lo_en    = minstret_wr  | (inst_retired_i & !mcountinhibit_nxt[2]);
wire [31:0] minstret_lo_nxt   = minstret_wr  ? register_value_nxt_i : (minstret_reg[31:0]  + 32'h00000001);
wire        minstret_hi_en    = minstreth_wr | minstret_incr_msb;
wire [31:0] minstret_hi_nxt   = minstreth_wr ? register_value_nxt_i : (minstret_reg[63:32] + 32'h00000001);

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_minstret_lo (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(minstret_lo_en),
                                                         .d_i (minstret_lo_nxt),
                                                         .q_o (minstret_reg[31:0]));

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_minstret_hi (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(minstret_hi_en),
                                                         .d_i (minstret_hi_nxt),
                                                         .q_o (minstret_reg[63:32]));

//------------------------------------------------------------------
// mcounteren: gates U/S-mode access to cycle/time/instret
//------------------------------------------------------------------
arv_dff #(.WIDTH(3), .ARST_EN(ARST_EN)) u_mcounteren (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcounteren_wr),
                                                       .d_i (register_value_nxt_i[2:0]),
                                                       .q_o (mcounteren_reg));

//------------------------------------------------------------------
// mcountinhibit: stops counters when set
//------------------------------------------------------------------
// Bit[1] is hardwired 0 per Priv spec 3.1.13: it corresponds to the mtime counter,
// which is implemented outside the core (CLINT/Zicntr) and is not architecturally
// inhibitable. WARL: writes to bit[1] are silently dropped.
arv_dff #(.WIDTH(3), .ARST_EN(ARST_EN)) u_mcountinhibit (
                     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcountinhibit_wr),
                                                          .d_i ({register_value_nxt_i[2], 1'b0, register_value_nxt_i[0]}),
                                                          .q_o (mcountinhibit_reg));

//------------------------------------------------------------------
// Time req/gnt: register grant and capture time value on grant cycle.
// Registering time_gnt_i breaks the combinatorial feedthrough path
//------------------------------------------------------------------
wire time_access        = (bank_counter_i  & register_sel_i[1]) |
                          (bank_counterh_i & register_sel_i[1]) ;

wire time_gnt_r;
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_time_gnt (
                .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                     .d_i (time_gnt_i),
                                                     .q_o (time_gnt_r));

assign time_req_o       =  time_access & ~time_gnt_r;
assign ex_csr_ready_o   = ~time_access |  time_gnt_r;

//------------------------------------------------------------------
// Read mux
//------------------------------------------------------------------
wire mcycle_sel         = bank_mcycle_i      & register_sel_i[0];
wire minstret_sel       = bank_mcycle_i      & register_sel_i[2];
wire mcycleh_sel        = bank_mcycleh_i     & register_sel_i[0];
wire minstreth_sel      = bank_mcycleh_i     & register_sel_i[2];
wire cycle_sel          = bank_counter_i     & register_sel_i[0];
wire time_sel           = bank_counter_i     & register_sel_i[1];
wire instret_sel        = bank_counter_i     & register_sel_i[2];
wire cycleh_sel         = bank_counterh_i    & register_sel_i[0];
wire timeh_sel          = bank_counterh_i    & register_sel_i[1];
wire instreth_sel       = bank_counterh_i    & register_sel_i[2];
wire mcounteren_sel     = bank_mtrap_setup_i & register_sel_i[6];
wire mcountinhibit_sel  = bank_mtrap_setup_i & register_sel_i[32];

assign counters_rdata_o = ({32{mcycle_sel       }} & mcycle_reg[31:0]          )  |
                          ({32{minstret_sel     }} & minstret_reg[31:0]        )  |
                          ({32{mcycleh_sel      }} & mcycle_reg[63:32]         )  |
                          ({32{minstreth_sel    }} & minstret_reg[63:32]       )  |
                          ({32{cycle_sel        }} & mcycle_reg[31:0]          )  |
                          ({32{time_sel         }} & time_val_i[31:0]          )  |
                          ({32{instret_sel      }} & minstret_reg[31:0]        )  |
                          ({32{cycleh_sel       }} & mcycle_reg[63:32]         )  |
                          ({32{timeh_sel        }} & time_val_i[63:32]         )  |
                          ({32{instreth_sel     }} & minstret_reg[63:32]       )  |
                          ({32{mcounteren_sel   }} & {29'h0, mcounteren_reg}   )  |
                          ({32{mcountinhibit_sel}} & {29'h0, mcountinhibit_reg})  ;

assign mcounteren_o     = mcounteren_reg;

//------------------------------------------------------------------
// Lint: only a handful of register_sel_i bits decode a counter CSR in
// this bank, and only mcountinhibit_nxt[2] (IR) gates minstret here
// (CY/TM live in arv_csr_hpm / are address-decoded elsewhere). Full-
// width reads keep these clean across every parameterization.
//------------------------------------------------------------------
wire  [2:0] register_sel__5__3_unused = register_sel_i[5:3];
wire [24:0] register_sel_31__7_unused = register_sel_i[31:7];
wire [30:0] register_sel_63_33_unused = register_sel_i[63:33];
wire  [1:0] mcountinhibit_nxt_unused  = mcountinhibit_nxt[1:0];


endmodule // arv_csr_cntr

`default_nettype wire

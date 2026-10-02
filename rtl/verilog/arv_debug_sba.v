//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_debug_sba
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_debug_sba.v
// Module Description : RISC-V Debug Module System Bus Access (SBA) engine (Debug
//                      Spec 1.0): the sbcs (0x38) / sbaddress0 (0x39) / sbdata0 (0x3C)
//                      DMI registers plus a single-transfer AHB-Lite master for
//                      debugger memory access with the hart halted or running.
//
//                      Attach model (key integration fact): the SBA master is MUXED
//                      onto the core's existing data AHB port at the arvern top level
//                      and ARBITRATES for it, so system bus access works with the hart
//                      either halted or RUNNING. A trigger parks the engine in SB_REQ
//                      asserting sb_bus_req_o; the arbiter at arvern returns sb_bus_gnt_i
//                      on a cycle where the hart is not issuing an address phase, and the
//                      engine then owns the bus for its whole APH+DPH while the LSU is
//                      held off with a wait state. Debugger vs software accesses are
//                      tagged by data_hmaster_o (= sb_bus_active_o) so the SoC fabric
//                      can protect them.
//
//                      Access triggering, autoincrement, the sbbusy / sberror /
//                      sbbusyerror semantics and 8/16/32-bit size handling follow the
//                      spec and are documented at their logic below; 64/128-bit are
//                      not supported.
//
//                      Present whenever DEBUG_EN=1 (the frozen hart's only memory path).
//----------------------------------------------------------------------------
`default_nettype none

module  arv_debug_sba (
// Clock / reset (hclk domain)
    input  wire              hclk_i,
    input  wire              dbgresetn_i,
    input  wire              dm_sinit_i,                    // synchronous init to reset values (dmactive=0)

// DMI register access - decoded by the DM from an accepted DMI transaction.
    input  wire        [6:0] addr7_i,                       // DMI register address
    input  wire              is_read_i,                     // this transaction is a DMI read  (accept & op=read)
    input  wire              is_write_i,                    // this transaction is a DMI write (accept & op=write)
    input  wire       [31:0] wdata_i,                       // DMI write data

// Register read-back to the DM's DMI read mux.
    output wire       [31:0] sbcs_rdata_o,
    output wire       [31:0] sbaddress0_rdata_o,
    output wire       [31:0] sbdata0_rdata_o,
    output wire              sb_busy_o,                     // sbbusy (busy | trigger cycle) - resume interlock at the DM

// AHB-Lite system bus master - muxed onto the core data port at arvern top.
    output wire              sb_bus_req_o,                  // 1 = engine wants the data bus (parked in SB_REQ)
    input  wire              sb_bus_gnt_i,                  // 1 = arbiter hands the bus over from the next cycle
    output wire              sb_bus_active_o,               // 1 = SBA owns the data bus this cycle (mux select)
    output wire       [31:0] sb_haddr_o,
    output wire        [1:0] sb_htrans_o,
    output wire              sb_hwrite_o,
    output wire        [2:0] sb_hsize_o,
    output wire        [2:0] sb_hburst_o,
    output wire       [31:0] sb_hwdata_o,
    input  wire       [31:0] sb_hrdata_i,
    input  wire              sb_hready_i,
    input  wire              sb_hresp_i
);

// USER PARAMETER
//========================================
parameter                ARST_EN = 1'b1;                 // 1=async active-low reset, 0=sync (matches arv_dff)

//////======================================================================================================================//////
//////    Register addresses + constants                                                                                    //////
//////======================================================================================================================//////

localparam [6:0] SBCS        = 7'h38;
localparam [6:0] SBADDRESS0  = 7'h39;
localparam [6:0] SBDATA0     = 7'h3c;

localparam [1:0] SB_IDLE     = 2'd0,   // bus master idle
                 SB_REQ      = 2'd3,   // access accepted, waiting for the data-bus grant
                 SB_APH      = 2'd1,   // AHB address phase (HTRANS=NONSEQ)
                 SB_DPH      = 2'd2;   // AHB data phase (wait HREADY)

// sberror codes
localparam [2:0] SBERR_NONE  = 3'd0,
                 SBERR_ADDR  = 3'd2,
                 SBERR_ALIGN = 3'd3,
                 SBERR_SIZE  = 3'd4;

//////======================================================================================================================//////
//////    Configuration registers (written via sbcs)                                                                        //////
//////======================================================================================================================//////
wire  [1:0] state_q;
wire  [2:0] sbaccess_q;
wire        sbreadonaddr_q;
wire        sbautoincr_q;
wire        sbreadondata_q;

wire        wr_sbcs   = is_write_i & (addr7_i == SBCS);
wire        wr_sbaddr = is_write_i & (addr7_i == SBADDRESS0);
wire        wr_sbdata = is_write_i & (addr7_i == SBDATA0);
wire        rd_sbdata = is_read_i  & (addr7_i == SBDATA0);
wire        busy      = (state_q != SB_IDLE);

arv_dff_sinit #(.WIDTH(3), .RST_VAL(3'd2), .ARST_EN(ARST_EN)) u_sbaccess (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit_i), .en_i(wr_sbcs),
                                                                             .d_i (wdata_i[19:17]), .q_o(sbaccess_q));

arv_dff_sinit #(.ARST_EN(ARST_EN)) u_sbreadonaddr (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit_i), .en_i(wr_sbcs),
                                                                             .d_i (wdata_i[20]),    .q_o(sbreadonaddr_q));

arv_dff_sinit #(.ARST_EN(ARST_EN)) u_sbautoincr (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit_i), .en_i(wr_sbcs),
                                                                             .d_i (wdata_i[16]),    .q_o(sbautoincr_q));

arv_dff_sinit #(.ARST_EN(ARST_EN)) u_sbreadondata (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit_i), .en_i(wr_sbcs),
                                                                             .d_i (wdata_i[15]),    .q_o(sbreadondata_q));


//////=======================================================================================================================//////
//////    Trigger decode + start arbitration                                                                                 //////
//////    A trigger is any operation that initiates a bus access. It is honoured only when there is no sticky error and the  //////
//////    engine is idle. Errors/misuse are reported per spec without starting a bus cycle.                                  //////
//////=======================================================================================================================//////
wire [31:0] sbaddress_q;
wire [31:0] sbdata_q;
wire  [2:0] sberror_q;
wire        sbbusyerror_q;

wire        no_err      = (sberror_q == SBERR_NONE) & ~sbbusyerror_q;

wire  [1:0] acc_alsb    = wr_sbaddr ? wdata_i[1:0] : sbaddress_q[1:0];         // access-address LSBs

wire        want_roa    = wr_sbaddr & sbreadonaddr_q;                          // read-on-addr
wire        want_wr     = wr_sbdata;                                           // bus write
wire        want_rod    = rd_sbdata & sbreadondata_q;                          // read-on-data
wire        trig        = want_roa | want_wr | want_rod;

wire        size_sup    = (sbaccess_q <= 3'd2);                                // 8/16/32-bit supported
wire        aligned     = (sbaccess_q == 3'd0)                            |
                         ((sbaccess_q == 3'd1) & (acc_alsb[0]   == 1'b0)) |
                         ((sbaccess_q == 3'd2) & (acc_alsb[1:0] == 2'b00));

wire        can_start   = trig & no_err & ~busy;
wire        start_acc   = can_start &  size_sup &  aligned;                    // accept: park in SB_REQ until granted
wire        err_size    = can_start & ~size_sup;                               // sberror=4, no access
wire        err_align   = can_start &  size_sup & ~aligned;                    // sberror=3, no access

// The hart's run state is NOT part of can_start: the engine arbitrates for the shared data
// port (SB_REQ -> sb_bus_gnt_i) instead of requiring a halted hart, so a debugger can read
// and write memory on a running target. An access accepted here always completes; it may
// just wait a few cycles for the hart to leave the data bus alone (sbbusy stays 1 meanwhile).

// sbbusyerror: an sbaddress0/sbdata0 write, or an sbdata0 read, while the engine is busy
// sets sbbusyerror UNCONDITIONALLY (Debug Spec 1.0, sbcs.sbbusyerror - independent of the
// sbreadonaddr/sbreadondata enables); the register write itself is dropped (~busy gates).
wire        busyerr_set = busy & (wr_sbaddr | wr_sbdata | rd_sbdata);


//////======================================================================================================================//////
//////    Latched operation (valid from start through completion)                                                           //////
//////======================================================================================================================//////

wire        op_write_q;
wire  [1:0] op_size_q;

// The access ADDRESS and write DATA are NOT shadowed here: sbaddress_q and sbdata_q are
// both frozen for the whole transaction -- debugger writes to them are gated by ~busy,
// sbaddress autoincrements only at completion (dph_ok, the same edge the read capture
// completes, i.e. after the read lanes below are consumed), and sbdata is overwritten
// only by a READ result -- so the AHB master drives sb_haddr_o / sb_hwdata_o directly
// from them, and the read-lane select uses sbaddress_q[1:0] directly (no LSB snapshot).
// Only the direction and size are snapshot at start, because sbcs (hence sbaccess_q)
// is NOT ~busy-gated and could be rewritten mid-transaction.

// A dmactive soft-reset (dm_sinit_i, a level) mid-transfer must not force-idle the FSM: the
// bus mux at arvern would switch away while the slave is still in the data phase and a write
// would sample the LSU's HWDATA. The transfer-carrying flops take the soft reset only once the
// bus is released (IDLE via the normal dph_done path); dm_sinit_i is still asserted then.
wire        sinit_xfer      = dm_sinit_i & ~sb_bus_active_o;

arv_dff_sinit #(.ARST_EN(ARST_EN)) u_op_write (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(sinit_xfer), .en_i(start_acc),
                                                                             .d_i (want_wr),         .q_o(op_write_q));

arv_dff_sinit #(.WIDTH(2), .ARST_EN(ARST_EN)) u_op_size (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(sinit_xfer), .en_i(start_acc),
                                                                             .d_i (sbaccess_q[1:0]), .q_o(op_size_q));


//////======================================================================================================================//////
//////    AHB master FSM                                                                                                    //////
//////======================================================================================================================//////

wire        dph_done        = (state_q == SB_DPH) & sb_hready_i;   // data phase completes (2-cycle HRESP: hresp still high here)
wire        dph_err         = dph_done & sb_hresp_i;
wire        dph_ok          = dph_done & ~sb_hresp_i;
wire        dph_ok_rd       = dph_ok   & ~op_write_q;

wire  [1:0] state_nxt       = (state_q == SB_IDLE) ? (start_acc    ? SB_REQ : SB_IDLE) :
                              (state_q == SB_REQ ) ? (sb_bus_gnt_i ? SB_APH : SB_REQ ) :
                              (state_q == SB_APH ) ? (sb_hready_i  ? SB_DPH : SB_APH ) :
                                                     (sb_hready_i  ? SB_IDLE: SB_DPH ) ;

arv_dff_sinit #(.WIDTH(2), .ARST_EN(ARST_EN)) u_state (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(sinit_xfer), .en_i(1'b1),
                                                                             .d_i (state_nxt), .q_o(state_q));

// AHB outputs. HWDATA is replicated across lanes for sub-word writes.
wire [31:0] hwdata_fmt      = (op_size_q == 2'd0) ? {4{sbdata_q[ 7:0]}} :
                              (op_size_q == 2'd1) ? {2{sbdata_q[15:0]}} :
                                                       sbdata_q         ;

assign      sb_bus_req_o    = (state_q == SB_REQ);
assign      sb_bus_active_o = (state_q == SB_APH) | (state_q == SB_DPH);
assign      sb_htrans_o     = (state_q == SB_APH) ? 2'b10 : 2'b00;       // NONSEQ in address phase, IDLE otherwise
assign      sb_haddr_o      = sbaddress_q;
assign      sb_hwrite_o     = op_write_q;
assign      sb_hsize_o      = {1'b0, op_size_q};                         // 0/1/2 = byte/half/word
assign      sb_hburst_o     = 3'b000;                                    // SINGLE
assign      sb_hwdata_o     = hwdata_fmt;                                // (HPROT is the constant 4'b0011 {non-cache, non-buf, privileged (M), data}, hardcoded at the arvern data-bus mux)

//////======================================================================================================================//////
//////    Read-data capture (right-justified, zero-extended) into sbdata0                                                   //////
//////======================================================================================================================//////

wire  [1:0] rd_alsb         = sbaddress_q[1:0];      // frozen for the whole transaction (see op snapshot note)
wire  [7:0] rd_byte         = (rd_alsb == 2'b00)     ? sb_hrdata_i[ 7: 0] :
                              (rd_alsb == 2'b01)     ? sb_hrdata_i[15: 8] :
                              (rd_alsb == 2'b10)     ? sb_hrdata_i[23:16] :
                                                       sb_hrdata_i[31:24] ;
wire [15:0] rd_half         = (rd_alsb[1] == 1'b0)   ? sb_hrdata_i[15: 0] :
                                                       sb_hrdata_i[31:16] ;
wire [31:0] rd_fmt          = (op_size_q == 2'd0)    ? {24'b0, rd_byte} :
                              (op_size_q == 2'd1)    ? {16'b0, rd_half} :
                                                               sb_hrdata_i ;


//////======================================================================================================================//////
//////    sbaddress0 - debugger write (idle only) OR post-access autoincrement                                              //////
//////======================================================================================================================//////

wire [31:0] incr_bytes      = (op_size_q == 2'd0) ? 32'd1 :
                              (op_size_q == 2'd1) ? 32'd2 : 32'd4;

wire        sbaddr_en       = (wr_sbaddr & ~busy) | (dph_ok & sbautoincr_q);
wire [31:0] sbaddr_nxt      = (wr_sbaddr & ~busy) ? wdata_i : (sbaddress_q + incr_bytes);

arv_dff_sinit #(.WIDTH(32), .ARST_EN(ARST_EN)) u_sbaddress (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(sinit_xfer), .en_i(sbaddr_en),
                                                                             .d_i (sbaddr_nxt), .q_o(sbaddress_q));


//////======================================================================================================================//////
//////    sbdata0 - debugger write (idle only) OR read-result capture                                                       //////
//////======================================================================================================================//////

wire        sbdata_en       = (wr_sbdata & ~busy) | dph_ok_rd;   // sbdata_q declared up top (used earlier by hwdata_fmt)
wire [31:0] sbdata_nxt      = (wr_sbdata & ~busy) ? wdata_i : rd_fmt;

arv_dff_sinit #(.WIDTH(32), .ARST_EN(ARST_EN)) u_sbdata (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(sinit_xfer), .en_i(sbdata_en),
                                                                             .d_i (sbdata_nxt), .q_o(sbdata_q));


//////======================================================================================================================//////
//////    sberror (W1C) - engine sets size/alignment/bus-error; a new error wins a simultaneous W1C clear                    //////
//////======================================================================================================================//////

wire        sberr_w1c       = wr_sbcs & (|wdata_i[14:12]);
wire        sberr_set       = err_size | err_align | dph_err;
// err_size and err_align are mutually exclusive, and dph_err (busy) excludes both
// (~busy). The ?: chain is a priority formality.
wire  [2:0] sberr_code      = err_size    ? SBERR_SIZE  :
                              err_align   ? SBERR_ALIGN : SBERR_ADDR;   // dph_err -> address
wire        sberr_en        = sberr_w1c | sberr_set;
wire  [2:0] sberr_nxt       = sberr_set ? sberr_code  : SBERR_NONE;   // set has priority over clear

arv_dff_sinit #(.WIDTH(3), .ARST_EN(ARST_EN)) u_sberror (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit_i), .en_i(sberr_en),
                                                                             .d_i (sberr_nxt), .q_o(sberror_q));


//////======================================================================================================================//////
//////    sbbusyerror (W1C)                                                                                                 //////
//////======================================================================================================================//////

wire        sbbe_w1c        = wr_sbcs & wdata_i[22];
wire        sbbe_en         = sbbe_w1c | busyerr_set;
wire        sbbe_nxt        = busyerr_set;                            // set has priority over clear

arv_dff_sinit #(.ARST_EN(ARST_EN)) u_sbbusyerror (
                .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit_i), .en_i(sbbe_en),
                                                                             .d_i (sbbe_nxt), .q_o(sbbusyerror_q));


//////======================================================================================================================//////
//////    Read-back assembly                                                                                                //////
//////    sbbusy is reported combinationally including the trigger cycle (start_acc) so a fast poll cannot miss it.          //////
//////======================================================================================================================//////

wire   sbbusy       = busy | start_acc;

// Exported for two consumers at the DM / arvern level: the resume interlock (a resume is
// held off until the engine drains, so it never races an in-flight debugger access), and the
// clock-gate keep-alive (an accepted access outlives the DMI transaction that triggered
// it, so hclk must stay ungated through it even if the hart is WFI-sleeping).
assign sb_busy_o    = sbbusy;

assign sbcs_rdata_o =   32'd0                            |
                      ( 32'd1                 << 29)     |   // sbversion = 1 (Debug Spec 1.0)
                      ({31'd0, sbbusyerror_q} << 22)     |
                      ({31'd0, sbbusy}        << 21)     |
                      ({31'd0, sbreadonaddr_q}<< 20)     |
                      ({29'd0, sbaccess_q}    << 17)     |
                      ({31'd0, sbautoincr_q}  << 16)     |
                      ({31'd0, sbreadondata_q}<< 15)     |
                      ({29'd0, sberror_q}     << 12)     |
                      ( 32'd32                <<  5)     |   // sbasize = 32 (system bus address width)
                      ( 32'd1                 <<  2)     |   // sbaccess32 supported
                      ( 32'd1                 <<  1)     |   // sbaccess16 supported
                      ( 32'd1                 <<  0)     ;   // sbaccess8  supported

assign sbaddress0_rdata_o = sbaddress_q;
assign sbdata0_rdata_o    = sbdata_q;

endmodule // arv_debug_sba

`default_nettype wire

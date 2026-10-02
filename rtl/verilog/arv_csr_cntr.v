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
// Module Description : RISC-V CSRs: Zicntr counter / timer (mcycle / minstret / mcounteren / mcountinhibit + U-mode shadows)
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
    input  wire           minstret_undo_i,     // sync exception taken: un-retire the counted instruction
    input  wire           stopcount_freeze_i,  // dcsr.stopcount & Debug Mode: freeze increments (writes still land)
    input  wire           dm_acsr_active_i,    // the CSR access is the Debug Module's, not a dispatched instruction

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
parameter   ARST_EN = 1'b1;    // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter   SU_MODE_EN = 1'b1; // S+U privilege modes (0 = M-only: mcounteren has no lower privilege to gate)


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
// stopcount_freeze_i (dcsr.stopcount in Debug Mode) gates the INCREMENT only, not the
// CSR write - a DM/SW write to mcycle still lands while the hart is halted.
wire        mcycle_incr_msb = (mcycle_reg[31:0] == 32'hFFFFFFFF) & !mcountinhibit_reg[0] & ~mcycle_wr & ~stopcount_freeze_i;

// Priority write > increment > hold, expressed as enable + next-state for arv_dff.
wire        mcycle_lo_en    = mcycle_wr  | (~mcountinhibit_reg[0] & ~stopcount_freeze_i);
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

// A write takes effect after the writing instruction completes (Priv 3.1.11), so an
// instruction retiring in the write cycle still counts on top of the written value
// (minstret_co, carry into the other half included). Carries are gated by an actual
// step so that stall cycles with lo == 0xFFFFFFFF do not increment hi.
// minstret_undo_i un-retires the instruction that caused a synchronous exception.
wire        minstret_co       = inst_retired_i & !mcountinhibit_nxt[2] & ~stopcount_freeze_i;
wire        minstret_cnt_en   = !mcountinhibit_nxt[2] & ~minstret_wr & ~minstreth_wr & ~stopcount_freeze_i;
wire        minstret_inc      = inst_retired_i   & minstret_cnt_en;
wire        minstret_dec      = minstret_undo_i  & minstret_cnt_en;
wire        minstret_step     = minstret_inc ^ minstret_dec;   // 0 when both or neither
wire        minstret_down     = minstret_dec & ~minstret_inc;

wire        minstret_incr_msb = (minstret_reg[31:0] == 32'hFFFFFFFF) & minstret_step & ~minstret_down;
wire        minstret_decr_msb = (minstret_reg[31:0] == 32'h00000000) & minstret_step &  minstret_down;
wire        minstret_wr_carry = minstret_wr  & minstret_co & (register_value_nxt_i == 32'hFFFFFFFF);
wire        minstreth_wr_cy   = minstreth_wr & minstret_co & (minstret_reg[31:0]   == 32'hFFFFFFFF);

wire        minstret_lo_en    = minstret_wr  | minstret_step | (minstreth_wr & minstret_co);
wire [31:0] minstret_lo_nxt   = minstret_wr  ? (register_value_nxt_i + {31'h0, minstret_co}) :
                                minstreth_wr ? (minstret_reg[31:0]   + 32'h00000001)         :
                                               (minstret_reg[31:0]   + (minstret_down ? 32'hFFFFFFFF : 32'h00000001));
wire        minstret_hi_en    = minstreth_wr | minstret_incr_msb | minstret_decr_msb | minstret_wr_carry;
wire [31:0] minstret_hi_nxt   = minstreth_wr ? (register_value_nxt_i + {31'h0, minstreth_wr_cy}) :
                                               (minstret_reg[63:32]  + (minstret_down ? 32'hFFFFFFFF : 32'h00000001));

// A CSR read of minstret executes in EX, after its own dispatch was counted: report the
// count of the instructions before it. minstret_self_q = the last dispatched instruction
// (the reader, while it is in EX) was counted. A Debug Module abstract read is not a
// dispatched instruction and sees the count unchanged.
wire        minstret_self_q;
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_minstret_self (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(inst_retired_i),
                                                         .d_i (minstret_co),
                                                         .q_o (minstret_self_q));
wire [63:0] minstret_rd       = minstret_reg - {63'h0, minstret_self_q & ~dm_acsr_active_i};

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
// mcounteren gates the NEXT-LOWER privilege's access to cycle/time/instret. Priv
// 3.1.11 requires it only when U-mode is implemented, so at SU_MODE_EN=0 it does not
// exist at all: the address is carved out of the M-mode window in arv_csr_top.v and
// an access raises illegal-instruction (2.1), exactly as for medeleg/mideleg.
//
// No flop is built here in that case -- the value is unreachable.
generate
if (SU_MODE_EN != 0) begin : g_mcounteren

    arv_dff #(.WIDTH(3), .ARST_EN(ARST_EN)) u_mcounteren (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcounteren_wr),
                                                           .d_i (register_value_nxt_i[2:0]),
                                                           .q_o (mcounteren_reg));

end else begin : g_no_mcounteren

    assign mcounteren_reg = 3'b000;

    wire   mcounteren_wr_unused = mcounteren_wr;

end
endgenerate

//------------------------------------------------------------------
// mcountinhibit: stops counters when set
//------------------------------------------------------------------
// Bit[1] is hardwired 0 per Priv spec 3.1.12: it corresponds to the mtime counter,
// which is implemented outside the core (CLINT/Zicntr) and is not architecturally
// inhibitable. WARL: writes to bit[1] are silently dropped.
arv_dff #(.WIDTH(3), .ARST_EN(ARST_EN)) u_mcountinhibit (
                     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcountinhibit_wr),
                                                          .d_i ({register_value_nxt_i[2], 1'b0, register_value_nxt_i[0]}),
                                                          .q_o (mcountinhibit_reg));

//------------------------------------------------------------------
// TIME req/gnt: 4-phase request sequencing, read served live
//------------------------------------------------------------------
// Contract (arvern.v "TIME INTERFACE"): time_req_o is a level request that
// drops on the completion cycle; time_val_i is an hclk-domain register owned
// by the timer (the timer owns any CDC) and must be held stable through the
// cycle after the grant. Both grant styles are supported:
//   - pulse grant (ahb_aclint): time_gnt_o pulses one cycle when a fresh
//     snapshot is ready; time_val_o is held stable between refreshes.
//   - hold grant: gnt asserted and val held until the timer observes
//     time_req_o deasserted.
//   - tied grant (time_gnt_i = 1'b1): free-running hclk-synchronous counter.
//
// Sequencing invariants (the value itself is held by the timer per contract,
// so no core-side capture register is needed):
//   - A read completes ONLY via time_done_r -- the registered conjunction of
//     an OUTSTANDING request and the raw grant. A stale registered grant can
//     never complete a later read, and a late grant after a trap-killed
//     request (request no longer outstanding) produces no completion.
//   - A new request is asserted only while the registered grant is observed
//     LOW (4-phase closure), so a re-request cannot race the timer's release.
//     The completion cycle samples time_val_i live: the request was still
//     high on the grant cycle, so a hold-type timer cannot have released the
//     value yet, and a pulse-type timer holds it until the next refresh.
//
// TIED/FAST-PATH (time_hs_mode_r = 0): grant already high with no handshake
// history -- only a tied-1 hclk-synchronous timer can present this, so the
// read completes immediately (zero stall) from the live, synchronous value;
// no request is issued (a wait-for-gnt-low would deadlock this integration).
//
// The DM abstract-CSR path ignores ex_csr_ready_o; a DM read of time/timeh
// samples time_val_i directly (an hclk-domain register per contract -- the
// last granted/refreshed snapshot). U-mode-denied accesses never reach here
// (arv_csr_top qualifies the bank with ~ex_excp_illegal_inst), so no
// spurious request is issued.
//------------------------------------------------------------------
wire time_access        = (bank_counter_i  & register_sel_i[1]) |
                          (bank_counterh_i & register_sel_i[1]) ;

// Registered grant observation. Registering time_gnt_i both breaks the
// combinational gnt -> ex_csr_ready feedthrough (timing flop) and provides
// the "grant observed low" test required for 4-phase closure.
wire time_gnt_r;
wire time_done_r;
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_time_gnt (
                .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                     .d_i (time_gnt_i),
                                                     .q_o (time_gnt_r));

// Sticky handshake-mode latch: set forever by the first request ever issued.
// A tied-gnt integration never issues a request (see time_req_o below), so
// it keeps the fast path enabled for life; any handshaking timer disables
// the fast path before its first grant can ever be observed.
wire time_hs_mode_r;
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_time_hs_mode (
                .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(time_req_o),
                                                     .d_i (1'b1),
                                                     .q_o (time_hs_mode_r));

// 4-phase level request: only while no completion is pending for this access
// AND the grant has been observed low (previous handshake closed).
// In tied mode time_gnt_r is permanently high, so no request is ever made.
assign time_req_o       = time_access & ~time_done_r & ~time_gnt_r;

// Completion pulse: grant observed while the request was outstanding.
// Strict 1-cycle pulse -- the request drops combinationally on the done
// cycle, so the registered conjunction self-clears on the next edge. An
// unconsumed or trap-killed completion simply re-arbitrates a fresh
// handshake on the next access.
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_time_done (
                .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                     .d_i (time_req_o & time_gnt_i),
                                                     .q_o (time_done_r));

// Non-time CSRs are always ready (unchanged); time/timeh reads complete on
// the handshake-done cycle, or immediately on the tied-gnt fast path.
assign ex_csr_ready_o   = ~time_access | time_done_r | (time_gnt_r & ~time_hs_mode_r);

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
                          ({32{minstret_sel     }} & minstret_rd[31:0]         )  |
                          ({32{mcycleh_sel      }} & mcycle_reg[63:32]         )  |
                          ({32{minstreth_sel    }} & minstret_rd[63:32]        )  |
                          ({32{cycle_sel        }} & mcycle_reg[31:0]          )  |
                          ({32{time_sel         }} & time_val_i[31:0]          )  |  // live: timer-held per contract (see TIME handshake block)
                          ({32{instret_sel      }} & minstret_rd[31:0]         )  |
                          ({32{cycleh_sel       }} & mcycle_reg[63:32]         )  |
                          ({32{timeh_sel        }} & time_val_i[63:32]         )  |  // live: timer-held per contract (see TIME handshake block)
                          ({32{instreth_sel     }} & minstret_rd[63:32]        )  |
                          ({32{mcounteren_sel   }} & {29'h0, mcounteren_reg}   )  |
                          ({32{mcountinhibit_sel}} & {29'h0, mcountinhibit_reg})  ;

assign mcounteren_o     = mcounteren_reg;

//------------------------------------------------------------------
// Lint: tie off register_sel_i bits not decoded in this bank.
//------------------------------------------------------------------
wire  [2:0] register_sel__5__3_unused = register_sel_i[5:3];
wire [24:0] register_sel_31__7_unused = register_sel_i[31:7];
wire [30:0] register_sel_63_33_unused = register_sel_i[63:33];
wire  [1:0] mcountinhibit_nxt_unused  = mcountinhibit_nxt[1:0];


endmodule // arv_csr_cntr

`default_nettype wire

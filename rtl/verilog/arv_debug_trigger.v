//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_debug_trigger
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_debug_trigger.v
// Module Description : RISC-V Sdtrig trigger CSR file (Debug Spec 1.0):
//                      tselect / tdata1(mcontrol6) / tdata2 / tinfo / tcontrol storage
//                      + WARL + readback, plus the mcontrol6 match/fire logic for
//                      EXECUTE (instruction-address) and LOAD/STORE data-address
//                      (select=0) triggers. Match is fully internal (no config bus):
//                      each trigger compares id_pc or ex_data_addr against tdata2
//                      (equal / NAPOT), priv-gated by m/s/u. Each path emits an
//                      OR-reduced {fire, action} pair; arv_csr_traps routes action=0 to
//                      the breakpoint exception and action=1 to Debug-Mode entry, the
//                      load/store fire riding the EX misalign path (suppress pre-AHB).
//                      tcontrol.mte/mpte guards action=0 M-mode re-triggering. DATA-VALUE
//                      match (select=1) is not implemented (select WARL 0).
//----------------------------------------------------------------------------
`default_nettype none

module  arv_debug_trigger (

// AHB CLOCK & RESET
    input  wire                          hclk_i,
    input  wire                          hresetn_i,

// CSR WRITE/READ PORT (shared EX datapath, already muxed to the DM abstract
// access values upstream in arv_csr_top -> dm_acsr writes land here too)
    input  wire                          bank_trigger_i,            // 0x780-0x7BF bank active (priv/excp-qualified)
    input  wire                   [63:0] register_sel_i,            // one-hot low-6-bits of CSR address
    input  wire                   [31:0] register_value_nxt_i,      // post-RMW write data
    input  wire                          disable_write_i,           // CSRRS/CSRRC with rs1==x0 / uimm==0 -> no write

// DEBUG MODE (whole-register dmode write-protection + match suppression while halted)
    input  wire                          debug_mode_i,              // hart is in Debug Mode (registered; frozen hart)

// MATCH-PATH HART STATE (execute trigger)
    input  wire                   [31:0] id_pc_i,                   // PC of the instruction at the id_pc boundary
    input  wire                    [1:0] priv_mode_i,               // current privilege (3=M, 1=S, 0=U)
    input  wire                          id_issue_active_nodbg_i,   // a valid instruction is about to issue (NOT debug-gated; includes illegal instructions)
    input  wire                          m_trap_entry_i,            // an M-mode trap is being taken this cycle (mte FSM)
    input  wire                          mret_i,                    // an mret is retiring this cycle (mte FSM)
    input  wire                          rnmi_entry_i,              // an RNMI is being taken this cycle (mte FSM, NMI shadow)
    input  wire                          mnret_i,                   // an mnret is retiring this cycle (mte FSM restore from the NMI shadow)

// MATCH-PATH HART STATE (load/store data-address watchpoint, EX stage)
    input  wire                   [31:0] ex_data_addr_i,            // EX-stage load/store data address (rs1+imm, pre-access)
    input  wire                          ex_is_load_i,              // a valid (non-hazard) load access is in EX this cycle
    input  wire                          ex_is_store_i,             // a valid (non-hazard) store access is in EX this cycle
    input  wire                    [2:0] ex_size_i,                 // AHB hsize of the EX access (0=byte,1=half,2=word)

// READ DATA FOR THE SELECTED TRIGGER CSR (0x7a0-0x7a5)
    output wire                   [31:0] trigger_rdata_o,

// EXECUTE-TRIGGER FIRE (OR-reduced over all implemented triggers)
    output wire                          trigger_exec_match_o,      // EARLY flop-sourced match (= fire w/o the issue-active qualifier) - see arv_decode timing optimization D
    output wire                          trigger_exec_fire_o,       // 1 = a matching execute trigger fires this cycle
    output wire                          trigger_exec_action_o,     // action of the matching trigger (1=enter-debug wins, 0=breakpoint); consumers qualify with fire/match

// LOAD/STORE DATA-ADDRESS WATCHPOINT FIRE (OR-reduced over all implemented triggers)
    output wire                          trigger_ls_fire_o,         // 1 = a matching load/store watchpoint fires this cycle (action-agnostic)
    output wire                          trigger_ls_action_o        // action of the firing watchpoint (1=enter-debug wins, 0=breakpoint)

);

// USER PARAMETERs
//========================================
parameter                            ARST_EN       = 1'b1;      // Reset style: 1=async (negedge hresetn_i), 0=sync
parameter                      [3:0] DM_TRIGGER_NR = 4'd1;      // Number of implemented triggers (1-8)
parameter                            SU_MODE_EN    = 1'b1;      // S+U modes present: mcontrol6.s/u are WARL 0 without them


//////======================================================================================================================//////
//////                                       SDTRIG TRIGGER FILE IMPLEMENTATION                                             //////
//////======================================================================================================================//////

//------------------------------------------------------------------
// CSR select decode (low-6-bits one-hot):
//   0x7a0 tselect  -> sel[32]   0x7a3 tdata3   -> sel[35] (RAZ/WI)
//   0x7a1 tdata1   -> sel[33]   0x7a4 tinfo    -> sel[36] (RO)
//   0x7a2 tdata2   -> sel[34]   0x7a5 tcontrol -> sel[37]
//------------------------------------------------------------------
wire tselect_sel  = bank_trigger_i & register_sel_i[32];
wire tdata1_sel   = bank_trigger_i & register_sel_i[33];
wire tdata2_sel   = bank_trigger_i & register_sel_i[34];
wire tdata3_sel   = bank_trigger_i & register_sel_i[35];
wire tinfo_sel    = bank_trigger_i & register_sel_i[36];
wire tcontrol_sel = bank_trigger_i & register_sel_i[37];

wire tselect_wr   = tselect_sel  & ~disable_write_i;
wire tdata1_wr    = tdata1_sel   & ~disable_write_i;
wire tdata2_wr    = tdata2_sel   & ~disable_write_i;
wire tcontrol_wr  = tcontrol_sel & ~disable_write_i;

//------------------------------------------------------------------
// tselect: WARL index of the selected trigger. Writes beyond
// (DM_TRIGGER_NR-1) clamp to the highest legal implemented index.
// 3 bits are sufficient for the 1-8 trigger range.
//------------------------------------------------------------------
// 4-bit compare so NR=8 (legal indices 0-7) never spuriously clamps.
wire [3:0] tsel_req     = {1'b0, register_value_nxt_i[2:0]};
wire [2:0] tselect_q;
wire [2:0] tselect_nxt  = (tsel_req >= DM_TRIGGER_NR) ? (DM_TRIGGER_NR[2:0] - 3'd1)
                                                      :  register_value_nxt_i[2:0];

arv_dff #(.WIDTH(3), .ARST_EN(ARST_EN)) u_tselect (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(tselect_wr),
                                                   .d_i (tselect_nxt),
                                                   .q_o (tselect_q));

//------------------------------------------------------------------
// tcontrol: mte (bit 3) / mpte (bit 7). These form the in-handler
// re-trigger guard for action=0 M-mode execute triggers, mirroring the
// mstatus.mie/mpie shadow (so it is restored by mret, hence m_trap_entry
// excludes NMI upstream):
//   - tcontrol CSR write : mte <= wdata[3], mpte <= wdata[7]  (highest priority)
//   - M-mode trap entry  : mpte <= mte,     mte  <= 0
//   - mret retiring      : mte  <= mpte     (mpte unchanged)
//   - RNMI entry         : mnpte <= mte,    mte  <= 0   (internal shadow, not a CSR field)
//   - mnret retiring     : mte  <= mnpte    (mnpte unchanged)
// The RNMI shadow keeps a native M-mode breakpoint from firing inside the RNMI
// handler, where a trap with NMIE=0 is unexpected (critical error), and lets the
// handler be entered without disarming triggers first. Sdtrig predates Smrnmi and
// specifies only the mstatus-stack pair; this mirrors it on the mnstatus stack.
// CSR-write vs entry/return won't generally coincide; CSR-write wins if they do.
// Reset mte=mpte=mnpte=0.
//------------------------------------------------------------------
wire       mte_q;
wire       mpte_q;
wire       mnpte_q;

wire       mte_en   = tcontrol_wr | rnmi_entry_i | m_trap_entry_i | mret_i | mnret_i;

wire       mte_nxt  = tcontrol_wr    ? register_value_nxt_i[3] :
                      rnmi_entry_i   ? 1'b0                    :
                      m_trap_entry_i ? 1'b0                    :
                      mnret_i        ? mnpte_q                 :
                                       mpte_q                  ;   // mret_i

arv_dff #(.ARST_EN(ARST_EN)) u_tcontrol_mte (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mte_en),
                                                   .d_i (mte_nxt),
                                                   .q_o (mte_q));

wire       mpte_en  = tcontrol_wr | m_trap_entry_i;

wire       mpte_nxt = tcontrol_wr ? register_value_nxt_i[7] : mte_q;   // m_trap_entry_i

arv_dff #(.ARST_EN(ARST_EN)) u_tcontrol_mpte (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mpte_en),
                                                   .d_i (mpte_nxt),
                                                   .q_o (mpte_q));

wire       mnpte_en  = rnmi_entry_i;

arv_dff #(.ARST_EN(ARST_EN)) u_tcontrol_mnpte (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mnpte_en),
                                                   .d_i (mte_q),
                                                   .q_o (mnpte_q));

wire [1:0] tcontrol_q = {mpte_q, mte_q};   // {mpte, mte} for the readback assembly

//------------------------------------------------------------------
// mcontrol6 (tdata1) WARL canonicalisation. Forces every reserved / tied-0 /
// match-status field to 0 so the stored word is a stable WARL fixed-point
// (re-writing the readback is idempotent). Per-field WARL rules are commented
// inline on the tdata1_nxt assembly below.
//
// INTERLOCK (Debug Spec invariant): dmode=0 & action=1 is forbidden. dmode and
// the action gate both derive from the same post-RMW write data, so a debug write
// that clears dmode in the same RMW also forces action -> breakpoint. The next-state
// depends only on the shared write data + debug_mode, so it is computed once at
// module scope and shared by all per-trigger flops.
//
// AREA: only the 11 live WARL bits are STORED per trigger; every other mcontrol6 bit
// is a WARL-forced constant, re-expanded combinationally at readback (pure wiring).
// This also shortens the (near-critical) execute-match cone: action/match become
// single stored bits instead of multi-bit field compares. Stored bit map:
//   [10] dmode   [9:8] size ({0..3})
//   [7]  action ({0,1})                [6]  match (0=equal, 1=NAPOT)
//   [5]  m   [4] s   [3] u   [2] execute   [1] store   [0] load
//
// tdata1.type is NOT stored. It is WARL with exactly one legal value -- 6 (mcontrol6),
// the only type this file implements -- so it reads 6 for every implemented trigger no
// matter what is written. Type 0 is reserved by the Debug Spec for "there is no trigger
// at this tselect" and TERMINATES a debugger's enumeration loop, so reporting it for a
// present-but-unconfigured trigger makes the triggers undiscoverable (OpenOCD stops at
// the first type=0 and reports "Found 0 triggers"). Enumeration instead ends on the
// out-of-range tselect WARL clamp above. A trigger is disarmed by clearing
// execute/store/load (and/or m/s/u) -- which is what a tdata1=0 write does here.
//------------------------------------------------------------------
wire       t1_dmode  = debug_mode_i & register_value_nxt_i[27];               // hart cannot set dmode
wire [1:0] t1_size   = (register_value_nxt_i[18] |                            // 4-7 -> any (0); [18] never stored
                        (register_value_nxt_i[2] & ~|register_value_nxt_i[1:0])) // execute-only: matches ignore size, WARL 0
                                                   ? 2'd0 : register_value_nxt_i[17:16];
wire       t1_action = t1_dmode & (register_value_nxt_i[15:12] == 4'd1);      // 1 only when dmode=1
wire       t1_match  = (register_value_nxt_i[10:7] == 4'd1);                  // implemented {0=equal,1=NAPOT}; else -> equal

wire [10:0] tdata1_nxt = { t1_dmode,                     // [10]   dmode
                           t1_size,                      // [9:8]  size
                           t1_action,                    // [7]    action
                           t1_match,                     // [6]    match
                           register_value_nxt_i[6],      // [5]    m
                           register_value_nxt_i[4] & SU_MODE_EN,   // [4]    s  (hard-wired 0 without S-mode)
                           register_value_nxt_i[3] & SU_MODE_EN,   // [3]    u  (hard-wired 0 without U-mode)
                           register_value_nxt_i[2],      // [2]    execute
                           register_value_nxt_i[1],      // [1]    store
                           register_value_nxt_i[0] };    // [0]    load

//------------------------------------------------------------------
// tinfo (RO): info[15:0] bitmask, bit N = type N supported. We
// implement type 6 (mcontrol6) only -> advertise bit 6. Type 0 is the
// disabled/none encoding of an existing trigger (not a distinct
// supported "type"), so bit 0 / bit 15 are NOT advertised. version
// [31:24] = 1: the ratified Debug Spec 1.0 Sdtrig feature set (mcontrol6).
//------------------------------------------------------------------
localparam [31:0] TINFO_VALUE = 32'h0100_0040;

//------------------------------------------------------------------
// Per-trigger storage: tdata1 (canonical mcontrol6, stored narrowed) + tdata2 (match value).
// Read mux is an OR-reduction over a per-trigger tselect compare, matching
// the house register_sel OR-mux style.
//------------------------------------------------------------------
wire [31:0] tdata1_selected;
wire [31:0] tdata2_selected;

wire [31:0] tdata1_or [0:7];
wire [31:0] tdata2_or [0:7];

// Per-trigger execute match and its action bit (OR-reduced below). "Match" = fire
// minus the common id_issue_active qualifier (factored out at trigger_exec_fire_o).
wire        exec_match_or  [0:7];   // this trigger matches (already mte-gated for action=0 M)
wire        exec_action_or [0:7];   // this trigger matches AND its action==1 (debug entry)

// Per-trigger load/store-watchpoint fire and its action bit (OR-reduced below).
wire        ls_fire_or     [0:7];   // this trigger's ls watchpoint fires (already mte-gated for action=0 M)
wire        ls_action_or   [0:7];   // this trigger's ls watchpoint fires AND its action==1 (debug entry)

// 32-bit loop bound so the genvar compare keeps full width
localparam signed [31:0] TRIG_NR = $signed({28'b0, DM_TRIGGER_NR});

genvar t;
generate
    for (t = 0; t < TRIG_NR; t = t + 1) begin : gen_trig

        wire [10:0] tdata1_q;       // narrowed storage - see the stored bit map at tdata1_nxt
        wire [31:0] tdata2_q;
        wire        hit0_q;         // mcontrol6 hit0 (bit 22): HW-set when THIS trigger enters Debug Mode

        // This trigger is addressed by the current tselect index.
        localparam [31:0] THIS_IDX = t;
        wire        this_sel       = ({29'b0, tselect_q} == THIS_IDX);

        // Whole-register dmode write-protection: when the STORED dmode=1 the
        // entire tdata1 AND tdata2 are read-only to the hart; writable only
        // from the debug path. tselect/tcontrol are NOT gated by this.
        wire        write_allowed = debug_mode_i | ~tdata1_q[10];

        wire        tdata1_we     = tdata1_wr & this_sel & write_allowed;
        wire        tdata2_we     = tdata2_wr & this_sel & write_allowed;

        arv_dff #(.WIDTH(11), .ARST_EN(ARST_EN)) u_tdata1 (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(tdata1_we),
                                                           .d_i (tdata1_nxt),
                                                           .q_o (tdata1_q));

        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_tdata2 (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(tdata2_we),
                                                           .d_i (register_value_nxt_i),
                                                           .q_o (tdata2_q));

        // Full 32-bit mcontrol6 view, re-expanded from the narrowed storage (wiring only;
        // field positions/constants exactly as the pre-narrowing stored word).
        wire [31:0] tdata1_full = { 4'd6,                       // [31:28] type = 6 (mcontrol6); WARL, only legal value
                                    tdata1_q[10],               // [27]    dmode
                                    1'b0,                       // [26]    uncertain -> 0
                                    1'b0,                       // [25]    hit1 -> WARL 0 (no chain support)
                                    2'b0,                       // [24:23] vs/vu -> 0 (no H-extension)
                                    hit0_q,                     // [22]    hit0 (HW-set when this trigger enters Debug Mode; debugger clears via tdata1 write)
                                    1'b0,                       // [21]    select -> WARL 0 (address match only)
                                    1'b0,                       // [20]    0
                                    1'b0,                       // [19]    0
                                    1'b0, tdata1_q[9:8],        // [18:16] size ([18] WARL 0: 4-7 -> any)
                                    3'b0, tdata1_q[7],          // [15:12] action
                                    1'b0,                       // [11]    chain -> WARL 0 (chaining unsupported: the match logic evaluates each trigger independently)
                                    3'b0, tdata1_q[6],          // [10:7]  match
                                    tdata1_q[5],                // [6]     m
                                    1'b0,                       // [5]     uncertainen
                                    tdata1_q[4],                // [4]     s
                                    tdata1_q[3],                // [3]     u
                                    tdata1_q[2],                // [2]     execute
                                    tdata1_q[1],                // [1]     store
                                    tdata1_q[0] };              // [0]     load

        // Read contribution for this trigger.
        assign tdata1_or[t] = {32{this_sel}} & tdata1_full;
        assign tdata2_or[t] = {32{this_sel}} & tdata2_q;

        //----------------------------------------------------------
        // mcontrol6 EXECUTE (instruction-address) match for this trigger.
        //----------------------------------------------------------
        wire        t_exec   = tdata1_q[2];                 // execute
        wire        t_m      = tdata1_q[5];                 // m
        wire        t_s      = tdata1_q[4];                 // s
        wire        t_u      = tdata1_q[3];                 // u
        wire        t_action = tdata1_q[7];                 // 1=enter-debug, else breakpoint
        wire        t_match  = tdata1_q[6];                 // 0=equal, 1=NAPOT

        // Privilege enable: the current privilege's m/s/u bit must be set.
        wire        t_priv_en = ((priv_mode_i == 2'b11) & t_m) |
                                ((priv_mode_i == 2'b01) & t_s) |
                                ((priv_mode_i == 2'b00) & t_u) ;

        // A reset/disarmed trigger has execute=store=load=0 and m=s=u=0, so it can never
        // match -- no separate "type enabled" term is needed (and none may exist: type is
        // WARL-forced to 6, so arming must depend only on the bits that read back).
        wire        t_enabled = t_exec & t_priv_en;

        // Address match by match-type.
        //  equal (0): id_pc == tdata2.
        //  NAPOT (1): compare the bits ABOVE tdata2's lowest 0-bit. tdata2 = base | (2^k - 1)
        //             encodes a 2^(k+1)-byte naturally-aligned region; (tdata2 ^ (tdata2+1))
        //             spans the trailing 1s plus the first 0 (= bits [k:0]), so its complement
        //             is the {31:k+1} compare mask. tdata2=all-ones -> mask 0 -> match-all.
        wire        t_addr_eq    = (id_pc_i == tdata2_q);
        wire [31:0] t_napot_mask = ~(tdata2_q ^ (tdata2_q + 32'd1));
        wire        t_addr_napot = (((id_pc_i ^ tdata2_q) & t_napot_mask) == 32'h0);
        wire        t_addr_match = t_match ? t_addr_napot : t_addr_eq;

        // tcontrol.mte gate: an action=0 trigger matching in M-mode fires only when mte=1
        // (prevents the M-mode breakpoint handler from immediately re-triggering). action=1
        // (debug entry) and S/U-mode matches are never mte-gated.
        wire        t_mte_block  = ~t_action & (priv_mode_i == 2'b11) & ~mte_q;

        // Match: an enabled trigger whose address matches the instruction at the ID
        // boundary (the issue-active FIRE qualifier is applied at the output).
        wire        t_match_g    = t_enabled & t_addr_match & ~t_mte_block;

        assign exec_match_or[t]  = t_match_g;
        assign exec_action_or[t] = t_match_g & t_action;

        //----------------------------------------------------------
        // mcontrol6 LOAD/STORE DATA-ADDRESS (select=0) match for this trigger.
        // Rides the EX-stage misalign timing: ex_data_addr_i is the pre-access
        // load/store address, so a hit suppresses the access (action-agnostic) before
        // the AHB transfer runs.
        //----------------------------------------------------------
        // select (0=address match) is WARL-forced 0 and therefore NOT stored: this
        // path IS the select=0 behaviour (data-value match deferred).
        wire        t_store     =  tdata1_q[1];                 // store
        wire        t_load      =  tdata1_q[0];                 // load
        wire  [2:0] t_size      =  {1'b0, tdata1_q[9:8]};       // size {0=any,1=8b,2=16b,3=32b}

        // Access-type match: the trigger's load/store bit lines up with a live EX access.
        wire        t_ls_access = (t_load  & ex_is_load_i) | (t_store & ex_is_store_i);

        // Size match: size=0 matches any; otherwise the trigger size {1,2,3} maps onto the
        // AHB hsize {0,1,2} of the access (8b<->0, 16b<->1, 32b<->2).
        wire        t_ls_size   = (t_size == 3'd0)                    |
                                  ((t_size == 3'd1) & (ex_size_i == 3'd0)) |
                                  ((t_size == 3'd2) & (ex_size_i == 3'd1)) |
                                  ((t_size == 3'd3) & (ex_size_i == 3'd2));

        wire        t_ls_enabled = t_ls_access & t_priv_en & t_ls_size;

        // Address match by match-type (reuses the same equal/NAPOT logic as the execute
        // path, but compares ex_data_addr instead of id_pc).
        wire        t_ls_addr_eq    = (ex_data_addr_i == tdata2_q);
        wire        t_ls_addr_napot = (((ex_data_addr_i ^ tdata2_q) & t_napot_mask) == 32'h0);
        wire        t_ls_addr_match = t_match ? t_ls_addr_napot : t_ls_addr_eq;

        wire        t_ls_fire_raw   = t_ls_enabled & t_ls_addr_match;

        // tcontrol.mte gate: identical to the execute path -- an action=0 watchpoint matching
        // in M-mode fires only when mte=1 (handler re-trigger guard). action=1 and S/U never gated.
        wire        t_ls_mte_block  = ~t_action & (priv_mode_i == 2'b11) & ~mte_q;
        wire        t_ls_fire       = t_ls_fire_raw & ~t_ls_mte_block;

        assign ls_fire_or[t]     = t_ls_fire;
        assign ls_action_or[t]   = t_ls_fire & t_action;

        //----------------------------------------------------------
        // mcontrol6 hit0 (bit 22): HW sets hit0=1 when THIS trigger fires (breakpoint or
        // Debug Mode entry), so a handler or a debugger can read tdata1 per trigger and see
        // exactly which one fired. Software clears it by writing tdata1 with bit[22]=0
        // (writing 1 is also legal WARL). chain is unsupported so hit1 is tied 0.
        //
        // Set condition:
        //   execute    : exec_match_or[t] & id_issue_active & ~debug_mode  (this trigger fires)
        //   load/store : ls_fire_or[t]                     & ~debug_mode  (this trigger fires)
        // whatever the action (Debug 1.0 mcontrol6 hit0: set when the trigger fires).
        //
        // TIMING: hit0_q is PURELY DOWNSTREAM. It CAPTURES the already-computed action-fire in a
        // flop; hit0_q fans out only to the tdata1_full readback (pure wiring). It is NOT read by
        // any match/fire/enter-debug term, so the (near-critical) execute-match cone is unchanged.
        //
        // FLOP: enable on a debugger tdata1 write to this trigger (tdata1_we, already dmode-gated
        // via write_allowed) OR a HW action-fire. Next = fire ? 1 : wdata[22] -> a simultaneous
        // HW-set wins over a debugger clear. Reset 0.
        wire        t_hit0_set = (exec_match_or[t]  & id_issue_active_nodbg_i & ~debug_mode_i) |
                                 (ls_fire_or[t]                               & ~debug_mode_i) ;

        wire        hit0_en    = tdata1_we | t_hit0_set;
        wire        hit0_nxt   = t_hit0_set ? 1'b1 : register_value_nxt_i[22];

        arv_dff #(.ARST_EN(ARST_EN)) u_hit0 (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(hit0_en),
                                                           .d_i (hit0_nxt),
                                                           .q_o (hit0_q));

    end
    // Unused upper OR slots when fewer than 8 triggers are implemented.
    for (t = TRIG_NR; t < 8; t = t + 1) begin : gen_trig_unused
        assign tdata1_or[t]      = 32'h0;
        assign tdata2_or[t]      = 32'h0;
        assign exec_match_or[t]  = 1'b0;
        assign exec_action_or[t] = 1'b0;
        assign ls_fire_or[t]     = 1'b0;
        assign ls_action_or[t]   = 1'b0;
    end
endgenerate

assign tdata1_selected = tdata1_or[0] | tdata1_or[1] | tdata1_or[2] | tdata1_or[3] |
                         tdata1_or[4] | tdata1_or[5] | tdata1_or[6] | tdata1_or[7];
assign tdata2_selected = tdata2_or[0] | tdata2_or[1] | tdata2_or[2] | tdata2_or[3] |
                         tdata2_or[4] | tdata2_or[5] | tdata2_or[6] | tdata2_or[7];

//------------------------------------------------------------------
// Execute-trigger match / fire OR-reduction.
//   match  = OR of per-trigger matches, suppressed while halted (debug_mode_i is the
//            REGISTERED Debug-Mode flag: a frozen hart issues nothing, and this mirrors
//            the debug-gated ebreak exception so the parked dpc instruction cannot
//            re-match. Using the registered flag keeps the path loop-free against the
//            action=1 -> debug_halt issue stall). Flop-sourced only -> exported EARLY
//            for the decode issue/branch gating (arv_decode timing optimization D).
//   fire   = match qualified by "a valid instruction is about to issue" - the
//            architectural fire that raises the breakpoint exception / debug entry.
//   action = OR of (match & action==1): if multiple triggers match the same cycle,
//            action=1 (enter Debug Mode) OUTRANKS action=0 (breakpoint exception).
//------------------------------------------------------------------
wire   exec_match_any        = exec_match_or[0] | exec_match_or[1] | exec_match_or[2] | exec_match_or[3] |
                               exec_match_or[4] | exec_match_or[5] | exec_match_or[6] | exec_match_or[7];

assign trigger_exec_match_o  = exec_match_any & ~debug_mode_i;
assign trigger_exec_fire_o   = trigger_exec_match_o & id_issue_active_nodbg_i;
assign trigger_exec_action_o = exec_action_or[0] | exec_action_or[1] | exec_action_or[2] | exec_action_or[3] |
                               exec_action_or[4] | exec_action_or[5] | exec_action_or[6] | exec_action_or[7];

//------------------------------------------------------------------
// Load/store-watchpoint fire OR-reduction. Same structure/semantics as the
// execute path: fire suppressed while halted (registered debug_mode_i; a frozen hart
// issues no load/store), and action=1 (enter Debug) outranks action=0 (breakpoint) on
// a same-cycle multi-trigger match. trigger_ls_fire_o is action-agnostic and drives the
// LSU access suppression (so a store does not modify memory on a hit).
//------------------------------------------------------------------
wire   ls_fire_any           = ls_fire_or[0] | ls_fire_or[1] | ls_fire_or[2] | ls_fire_or[3] |
                               ls_fire_or[4] | ls_fire_or[5] | ls_fire_or[6] | ls_fire_or[7];

assign trigger_ls_fire_o     = ls_fire_any & ~debug_mode_i;
assign trigger_ls_action_o   = ls_action_or[0] | ls_action_or[1] | ls_action_or[2] | ls_action_or[3] |
                               ls_action_or[4] | ls_action_or[5] | ls_action_or[6] | ls_action_or[7];

//------------------------------------------------------------------
// Read mux for the selected trigger CSR (0x7a0-0x7a5).
// tdata3 (textra) is RAZ/WI -> contributes 0.
//------------------------------------------------------------------
assign trigger_rdata_o = ({32{tselect_sel }} & {29'h0, tselect_q})                       |
                         ({32{tdata1_sel  }} & tdata1_selected)                          |
                         ({32{tdata2_sel  }} & tdata2_selected)                          |
                         ({32{tinfo_sel   }} & TINFO_VALUE)                              |
                         ({32{tcontrol_sel}} & {24'h0, tcontrol_q[1], 3'h0, tcontrol_q[0], 3'h0});

//------------------------------------------------------------------
// Lint: only sel[32:37] of register_sel_i decode a trigger CSR; tdata3_sel
// is decoded only to keep its write a no-op (RAZ/WI) and is otherwise unused.
//------------------------------------------------------------------
wire        tdata3_sel_unused          = tdata3_sel;
wire [31:0] register_sel_31__0_unused  = register_sel_i[31:0];
wire [25:0] register_sel_63_38_unused  = register_sel_i[63:38];


endmodule // arv_debug_trigger

`default_nettype wire

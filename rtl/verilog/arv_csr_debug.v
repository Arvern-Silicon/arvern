//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_csr_debug
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_csr_debug.v
// Module Description : RISC-V External Debug (Sdext, Debug Spec 1.0) hart-side logic,
//                      frozen-hart model. Owns the D-mode CSRs (dcsr 0x7B0, dpc 0x7B1;
//                      dscratch0/1 not implemented - no Program Buffer -> RAZ/WI) and
//                      the debug-mode entry/exit handshake.
//
//                      Frozen-hart: in Debug Mode the hart does NOT execute. Halt is a
//                      WFI-style decode issue-stall (debug_halt_active_o), not a fetch
//                      freeze; resume reuses the existing trap-redirect mux
//                      (debug_resume_redirect_o) to refetch from dpc, exactly as
//                      mret/sret do - so no bespoke exit stall is needed.
//
//                      Entry sources: external haltreq, ebreak (per-privilege dcsr
//                      bit), single-step completion, trigger, and halt-on-reset. The
//                      single-step FSM, cause priority mux and dpc capture are each
//                      documented at their logic below rather than restated here.
//
//                      The dm_csr_* port is the DM's abstract-access side-port into
//                      these CSRs while the hart is frozen.
//
//                      Built only when DEBUG_EN=1 (else not instantiated -> bit-identical).
//----------------------------------------------------------------------------
`default_nettype none

module  arv_csr_debug (

// Clock / reset
    input  wire           hclk_i,
    input  wire           hresetn_i,

// Hart state taps (from arv_csr_traps / pipeline)
    input  wire     [1:0] priv_mode_current_i,         // current privilege (3=M,1=S,0=U)
    input  wire    [31:0] id_pc_i,                     // PC of instruction in ID (dpc source)
    input  wire    [31:0] ex_pc_i,                     // PC in EX (the WFI itself during WFI sleep)
    input  wire           id_instruction_valid_i,      // ID stage holds a valid instruction
    input  wire           id_excp_inst_access_fault_i, // the next instruction's fetch faulted (its PC is in ID, no instruction)
    input  wire           crit_error_i,                // hart is in the Smdbltrp critical-error state
    input  wire    [31:0] crit_error_pc_i,             // PC it stopped on (dpc source for a halt from there)
    input  wire           id_wfi_active_i,             // hart is in/entering WFI sleep (dpc=WFI+4)
    input  wire           id_excp_ebreak_nodbg_i,      // ebreak decoded in ID, NOT gated by the debug-halt stall
    input  wire           trigger_enter_debug_i,       // Sdtrig mcontrol6 action=1 trigger fires (execute + load/store)
    input  wire           trigger_hold_early_i,        // EARLY flop-sourced Sdtrig hold (exec match w/o issue qual) -> debug_issue_hold_o leg only
    input  wire           ls_wp_suppress_i,            // Sdtrig load/store watchpoint suppressed the EX access this cycle (any action) -> dpc=ex_pc
    input  wire           resethaltreq_i,              // DM resethaltreq state -> halt out of reset with cause=5
    input  wire           trap_pending_i,              // a normal trap is in flight (defer debug entry)
    input  wire           entry_defer_i,               // older EX/WB fault pending/unresolved, or UOP final branch in flight (defers entry only, never resume)
    input  wire           nmip_i,                      // NMI pending (dcsr.nmip)
    input  wire           inst_retired_i,              // 1-cycle instruction-retire (dispatch) pulse - step boundary
    input  wire           trap_taken_i,                // 1-cycle trap-taken pulse - step boundary (covers stepie=1 IRQ)

// External debug-control handshake (from the Debug Module)
    input  wire           debug_req_i,                 // halt request (haltreq), level
    input  wire           resume_req_i,                // resume request (resumereq), level

// Debug-Module abstract CSR access side-port
    input  wire           dm_csr_access_i,             // DM is accessing a debug CSR this cycle
    input  wire     [1:0] dm_csr_sel_i,                // 0=dcsr 1=dpc; 2/3=dscratch0/1 (not implemented -> RAZ/WI)
    input  wire           dm_csr_wen_i,                // 1=write, 0=read
    input  wire    [31:0] dm_csr_wdata_i,              // write data
    output wire    [31:0] dm_csr_rdata_o,              // read data (selected debug CSR)

// Debug-mode status / control to the rest of the core
    output wire           debug_mode_o,                // 1 = hart is in Debug Mode (halted)
    output wire           debug_halt_active_o,         // issue-stall + IRQ-mask + clock-alive
    output wire           debug_issue_hold_o,          // EARLY flop-sourced superset of the entry/halt issue-stall, minus the ebreak leg (decode's debug gating term)
    output wire           debug_ebreak_cfg_o,          // dcsr.ebreak* enable for the CURRENT privilege; decode ANDs it with its local ebreak decode
    output wire           debug_resume_redirect_o,     // 1-cycle: redirect fetch to dpc (trap mux)
    output wire    [31:0] dpc_o,                       // resume PC (parked)
    output wire     [1:0] dcsr_prv_o,                  // privilege to restore on resume
    output wire           ebreak_enter_debug_o,        // mask ebreak out of the normal trap path
    output wire           ls_wp_entry_o,               // Debug Mode entered on a load/store watchpoint (the access is not retired)
    output wire           debug_halted_raw_o,          // RAW (undrained) halted status; arv_csr_traps drain-qualifies it for the DM
    output wire           dpc_valid_o,                 // dpc has been captured this halt (qualify DM allhalted)
    output wire           debug_step_no_irq_o,         // single-step in progress with dcsr.stepie=0 (mask IRQ/NMI)

// Counter freeze controls (dcsr.stopcount / dcsr.stoptime) - active only in Debug Mode
    output wire           debug_stopcount_o,           // freeze mcycle/minstret/hpm increments
    output wire           debug_stoptime_o             // freeze 'time' (off-core pin to SoC)

);

// USER PARAMETERs
//========================================
parameter                 ARST_EN    = 1'b1;           // Reset style: 1=async, 0=sync (matches arv_dff)
parameter                 SU_MODE_EN = 1'b1;           // S+U modes present (gates dcsr.ebreaks/ebreaku + prv WARL)
parameter                 C_EXT_EN   = 1'b1;           // Compressed instructions present (gates dpc WARL alignment:
                                                       // IALIGN=16 -> dpc[0]=0; IALIGN=32 -> dpc[1:0]=0)

//////======================================================================================================================//////
//////                                                                                                                      //////
//////    Privilege decode of the instruction currently at the ebreak boundary                                              //////
//////                                                                                                                      //////
//////======================================================================================================================//////
wire        current_in_machine    = (priv_mode_current_i == 2'b11);
wire        current_in_supervisor = (priv_mode_current_i == 2'b01);
wire        current_in_user       = (priv_mode_current_i == 2'b00);

//////======================================================================================================================//////
//////                                                                                                                      //////
//////    dcsr / dpc register state                                                                                         //////
//////                                                                                                                      //////
//////======================================================================================================================//////
wire        dcsr_ebreakm;    // [15]
wire        dcsr_ebreaks;    // [13]
wire        dcsr_ebreaku;    // [12]
wire        dcsr_stepie;     // [11]
wire        dcsr_stopcount;  // [10]
wire        dcsr_stoptime;   // [9]
wire  [2:0] dcsr_cause;      // [8:6]
wire        dcsr_step;       // [2]
wire  [1:0] dcsr_prv;        // [1:0]
wire [31:0] dpc_q;

wire        debug_mode_q;    // registered Debug-Mode flag
wire        dpc_captured_q;  // dpc has been latched for this halt
wire        step_pending_q;

//////======================================================================================================================//////
//////                                                                                                                      //////
//////    Debug-mode entry / exit handshake                                                                                 //////
//////                                                                                                                      //////
//////======================================================================================================================//////


// ebreak enters Debug Mode only when the current privilege's dcsr.ebreak* bit is set.
// The config term is exported (debug_ebreak_cfg_o) so decode can rebuild the same
// hold locally instead of round-tripping through this module (TIMING).
wire debug_ebreak_cfg   = (current_in_machine    & dcsr_ebreakm) |
                          (current_in_supervisor & dcsr_ebreaks) |
                          (current_in_user       & dcsr_ebreaku) ;

wire ebreak_enter_debug =  id_excp_ebreak_nodbg_i & debug_ebreak_cfg;

// Halt-on-reset (resethaltreq): a ONE-SHOT armed by the hart's reset. reset_halt_arm_q resets to
// 1 (RST_VAL); if the DM's resethaltreq is set when the hart comes out of reset, reset_halt_entry
// halts the hart at (before) its first instruction, with dpc = the reset vector, cause = 5. arm clears
// as soon as the first instruction reaches ID, so (a) it fires only for THIS reset, and (b) writing
// resethaltreq while the hart is RUNNING does NOT halt it -- the request only acts on the next reset.
// reset_halt_entry is a flop-AND-input (no combinational dependence on debug_entry) -> no UNOPTFLAT loop.
wire        reset_halt_arm_q;
wire        reset_halt_arm_en = reset_halt_arm_q & (id_instruction_valid_i |   // clear on the first ID instruction,
                                                    id_excp_inst_access_fault_i);   // or its fetch fault
arv_dff #(.RST_VAL(1'b1), .ARST_EN(ARST_EN)) u_reset_halt_arm (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(reset_halt_arm_en),
                                               .d_i (1'b0), .q_o(reset_halt_arm_q));
wire        reset_halt_entry  = reset_halt_arm_q & resethaltreq_i;

// Debug entry: not already halted, no normal trap in flight (let it resolve first),
// and a halt source is firing. Combinational so an ebreak / execute-trigger is held at
// its own boundary the same cycle it is detected (dpc then captures that PC). The
// trigger_enter_debug_i source rides the ebreak path verbatim: dpc = matching instr PC.
// reset_halt_entry rides the haltreq path: the first post-reset instruction is held -> dpc = reset vector.
wire debug_entry = ~debug_mode_q & ~trap_pending_i & ~entry_defer_i &
                   (debug_req_i  |  ebreak_enter_debug | step_pending_q | trigger_enter_debug_i | reset_halt_entry);

// Resume: requested while halted, and only once dpc is known. One-cycle pulse that
// drives the trap-redirect mux (target = dpc) and clears Debug Mode. The redirect
// cycle itself is held by trap_stall_o/trap_branch_detect_r in arv_csr_traps.
wire debug_resume_redirect = debug_mode_q & resume_req_i & dpc_captured_q & ~trap_pending_i;

// Issue stall: from the entry cycle (combinational, holds the ebreak) through the
// whole halt. Exit redirect is covered by the trap-stall path, so no extension here.
wire debug_halt_active = debug_mode_q | debug_entry;

// EARLY issue hold for decode's issue/branch gating: a flop-sourced SUPERSET of
// debug_halt_active minus the ebreak leg (decode rebuilds that one locally from
// debug_ebreak_cfg_o) and minus the load/store-watchpoint entry, which comes from
// the EX address and reaches decode through ex_excp_squash instead. The debug_entry
// qualifiers (~debug_mode_q, ~trap_pending_i) and the trigger issue-active qualifier
// are deliberately dropped - see arv_decode timing optimization D for the
// superset-safety argument.
assign debug_issue_hold_o = debug_mode_q     |
                            debug_req_i      |
                            step_pending_q   |
                            reset_halt_entry |
                            trigger_hold_early_i;

// Registered Debug-Mode flag: set on entry, cleared on resume.
wire debug_mode_en  = debug_entry | debug_resume_redirect;
wire debug_mode_nxt = debug_entry;   // 1 on entry, 0 on resume
arv_dff #(.ARST_EN(ARST_EN)) u_debug_mode (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(debug_mode_en),
                                               .d_i (debug_mode_nxt),
                                               .q_o (debug_mode_q));

//////======================================================================================================================//////
//////                                                                                                                      //////
//////    Single-step FSM (dcsr.step)                                                                                       //////
//////                                                                                                                      //////
//////    Arm on resume-with-step; cross exactly one instruction boundary (one retire                                      //////
//////    OR one trap taken); set a sticky re-halt request that re-enters Debug Mode                                       //////
//////    with dcsr.cause=4. The boundary covers all three cases: a normally-retiring                                      //////
//////    instruction (inst_retired_i), a synchronous-exception-taking instruction                                         //////
//////    (inst_retired_i pulses at dispatch, AND trap_taken_i fires), and a stepie=1                                      //////
//////    interrupt taken before any retire (trap_taken_i only).                                                           //////
//////======================================================================================================================//////

// Arm the step when resuming from Debug Mode with dcsr.step set (1-cycle pulse).
wire step_resume_arm = debug_resume_redirect & dcsr_step;

// step_armed: high from resume until the single instruction boundary is crossed.
wire step_armed_q;
wire step_boundary  = step_armed_q & (inst_retired_i | trap_taken_i);

// Clear on the boundary AND on any debug entry: a haltreq/ebreak/trigger that re-enters
// Debug Mode mid-step (before the boundary) leaves no retire/trap, so without the
// debug_entry clear, step_armed_q would linger through the halt and spuriously mask
// IRQs + force a cause=4 re-halt after a subsequent dcsr.step=0 free-run resume.
// step_resume_arm and debug_entry are mutually exclusive (entry needs ~debug_mode_q;
// resume happens while debug_mode_q=1), so step_armed_nxt stays unambiguous.
wire step_armed_en  = step_resume_arm | step_boundary | debug_entry;
wire step_armed_nxt = step_resume_arm;       // set on arm, clear on boundary / entry
arv_dff #(.ARST_EN(ARST_EN)) u_step_armed (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(step_armed_en),
                                               .d_i (step_armed_nxt),
                                               .q_o (step_armed_q));

// step_pending: STICKY re-halt request. Set at the boundary, then deferred through the
// existing ~trap_pending_i gate in debug_entry exactly like haltreq (so in the
// trap-during-step case it waits until the handler PC is at ID, giving dpc=handler),
// cleared when debug entry is actually taken.
wire step_pending_set = step_boundary;
wire step_pending_en  = step_pending_set | debug_entry;

// & ~debug_entry: if the step boundary COINCIDES with a higher-priority debug entry
// (haltreq/ebreak/trigger firing the same cycle the stepped instruction retires), the
// entry wins (cause=3/1/2) and step_pending must NOT latch - otherwise it would stick
// set through the halt (en=0 while debug_mode_q=1) and fire a spurious cause=4 re-halt
// on the next resume. Symmetric to the step_armed debug_entry clear. The normal-complete
// and trap-during-step paths have debug_entry=0 at the boundary (deferred by
// ~trap_pending_i / no concurrent halt source), so step_pending still sets there.
wire step_pending_nxt = step_pending_set & ~debug_entry;   // set on boundary, clear on entry
arv_dff #(.ARST_EN(ARST_EN)) u_step_pending (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(step_pending_en),
                                               .d_i (step_pending_nxt),
                                               .q_o (step_pending_q));

// IRQ/NMI mask for the duration of a dcsr.stepie=0 step (consumed in arv_csr_traps,
// OR-ed into irq_detect/nmi_detect at their source so the masked source vanishes from
// every consumer - trap entry, trap_stall_raw, and wfi_wakeup - avoiding a step
// deadlock on a level-held masked IRQ).
wire debug_step_no_irq = step_armed_q & ~dcsr_stepie;

//////======================================================================================================================//////
//////                                                                                                                      //////
//////    dpc capture (irq_mepc_settle pattern: wait for a valid ID instruction)                                          //////
//////                                                                                                                      //////
//////    For ebreak  : the held instruction IS the ebreak  -> dpc = ebreak PC.                                            //////
//////    For haltreq : the held instruction is the next un-issued one -> dpc = next PC.                                   //////
//////======================================================================================================================//////
wire        dm_wr_dcsr      = dm_csr_access_i & dm_csr_wen_i & (dm_csr_sel_i == 2'd0);
wire        dm_wr_dpc       = dm_csr_access_i & dm_csr_wen_i & (dm_csr_sel_i == 2'd1);

// A fetch fault parks the next PC in ID without an instruction: dpc = that PC, and the fault is taken on resume.
wire        dpc_capture     = debug_mode_q & ~dpc_captured_q & (id_instruction_valid_i | id_excp_inst_access_fault_i);

// On halt during WFI the spec MANDATES the WFI complete and dpc point to the
// FOLLOWING instruction (Sdext: "dpc is set to the next instruction that should be
// executed"). The PC is captured INTO DPC at debug ENTRY, where id_wfi_active_i and
// ex_pc_i are both valid (EX is frozen on the WFI's PC) - the dpc_capture strobe can
// fire cycles later under instruction-bus wait states, after debug_halt_active has
// torn down the live wfi_active state in decode, so entry-time capture keeps dpc
// independent of strobe timing (and needs no entry-PC shadow register - AREA).
// WFI is 32-bit -> following instruction at WFI_PC+4.
wire        wfi_entry_latch = debug_entry & id_wfi_active_i;

// Smdbltrp critical error: the hart ceased execution without updating the pc, so the
// instruction it stopped on never ran and is still the next one to execute. The
// dpc_capture strobe would take id_pc_i, one instruction too far -- the same problem
// ls_wp_entry_latch below exists to avoid. crit_error_pc_i is sticky in arv_csr_traps,
// so this reads the same value on every halt, not just the first.
wire        crit_err_entry_latch = debug_entry & crit_error_i;

// load/store watchpoint: an EX-stage event. A suppressed EX load/store (ls_wp_suppress_i,
// action-agnostic) never ran, so dpc must point at it (ex_pc_i) to re-execute on resume --
// but that load/store is in EX while ID already holds the NEXT instruction, so a plain id_pc
// capture would put dpc one instruction too far. Covers a watchpoint entering debug on its own
// AND a higher-priority source (haltreq/step/ebreak) entering the same cycle a watchpoint
// suppressed the access. Captured at debug ENTRY for the same strobe-timing reason as the
// WFI case above (ex_pc_i has moved on by the time the dpc_capture strobe fires).
wire        ls_wp_entry_latch = debug_entry & ls_wp_suppress_i;
assign      ls_wp_entry_o     = ls_wp_entry_latch;

// WFI-entry, watchpoint-entry and critical-error entry all capture at entry; every
// other source captures id_pc via the dpc_capture strobe
// (entry_capture sets dpc_captured below, so the strobe never overwrites these three).
// The critical-error arm sits FIRST: a hart that ceased execution inside a WFI would
// otherwise report ex_pc_i+4, and this is the one case where a wrong dpc cannot be
// tolerated. The three are expected to be mutually exclusive; the ordering removes the
// need to rely on it.
wire        entry_capture    = wfi_entry_latch | ls_wp_entry_latch | crit_err_entry_latch;
wire [31:0] entry_capture_pc = crit_err_entry_latch ? crit_error_pc_i   :
                               wfi_entry_latch      ? (ex_pc_i + 32'd4) :
                                                      ex_pc_i           ;

// dpc WARL alignment (mirrors mepc_align_mask in arv_csr_traps): C builds (IALIGN=16)
// clear bit 0 only; non-C builds (IALIGN=32) also clear bit 1. The mask is applied
// uniformly to both the software-write and hardware-capture paths - captured PCs are
// already IALIGN-aligned, so masking them is a no-op, and one shared mask keeps the
// WARL rule in a single place.
wire [31:0] dpc_align_mask = C_EXT_EN ? 32'hFFFFFFFE : 32'hFFFFFFFC;

// The three dpc write sources are mutually exclusive: dm_wr_dpc needs halted+drained,
// entry_capture needs ~debug_mode_q (entry cycle), dpc_capture needs debug_mode_q &
// ~dpc_captured_q (and entry_capture sets dpc_captured_q). The ?: order is a formality.
wire        dpc_en  = dpc_capture | dm_wr_dpc | entry_capture;
wire [31:0] dpc_nxt = (dm_wr_dpc     ? dm_csr_wdata_i   :
                       entry_capture ? entry_capture_pc : id_pc_i) & dpc_align_mask;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_dpc (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dpc_en), .d_i(dpc_nxt), .q_o(dpc_q));

// dpc_captured: set when dpc is latched (strobe or entry capture), cleared on resume so
// the next halt re-captures.
wire        dpc_captured_en  = dpc_capture | entry_capture | debug_resume_redirect;
wire        dpc_captured_nxt = dpc_capture | entry_capture;   // 1 on capture, 0 on resume
arv_dff #(.ARST_EN(ARST_EN)) u_dpc_captured (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dpc_captured_en),
                                               .d_i (dpc_captured_nxt),
                                               .q_o (dpc_captured_q));

//////======================================================================================================================//////
//////                                                                                                                      //////
//////    dcsr fields                                                                                                       //////
//////                                                                                                                      //////
//////======================================================================================================================//////

// cause[8:6]: latched at entry as an explicit PRIORITY mux. Debug Spec 1.0 Table 8
// priority among the causes we implement (highest -> lowest):
//   resethaltreq(5) > haltreq(3) > trigger(2) > ebreak(1) > step(4).
// resethaltreq can only fire out of reset (reset_halt_entry).
wire [2:0] dcsr_cause_nxt = reset_halt_entry       ? 3'd5 :   // resethaltreq (highest)
                            debug_req_i            ? 3'd3 :   // haltreq
                            trigger_enter_debug_i  ? 3'd2 :   // trigger
                            ebreak_enter_debug     ? 3'd1 :   // ebreak
                            step_pending_q         ? 3'd4 :   // step     (lowest)
                                                     3'd3 ;   // unreachable: debug_entry guarantees a source
arv_dff #(.WIDTH(3), .ARST_EN(ARST_EN)) u_dcsr_cause (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(debug_entry),
                                               .d_i (dcsr_cause_nxt),
                                               .q_o (dcsr_cause));

// prv[1:0]: captured at entry (privilege we interrupted), DM-writable (WARL) in Debug Mode.
// Reset to M (3). WARL: {3=M} legal always; {0=U,1=S} legal only when SU_MODE_EN; {2} never legal.
wire       prv_wr_is_m   = (dm_csr_wdata_i[1:0] == 2'b11);         // M: always legal
wire       prv_wr_is_su  = SU_MODE_EN   & ~dm_csr_wdata_i[1];      // U(00)/S(01): only with SU
wire       prv_wr_legal  = prv_wr_is_m  |  prv_wr_is_su;
wire [1:0] dcsr_prv_warl = prv_wr_legal ?  dm_csr_wdata_i[1:0] : 2'b11;
wire       dcsr_prv_en   = debug_entry  |  dm_wr_dcsr;
wire [1:0] dcsr_prv_nxt  = debug_entry  ?  priv_mode_current_i : dcsr_prv_warl;
arv_dff #(.WIDTH(2), .RST_VAL(2'b11), .ARST_EN(ARST_EN)) u_dcsr_prv (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dcsr_prv_en),
                                               .d_i (dcsr_prv_nxt),
                                               .q_o (dcsr_prv));

// Configuration bits - DM-writable (WARL), reset 0. ebreaks/ebreaku exist only with SU.
arv_dff #(.ARST_EN(ARST_EN)) u_dcsr_ebreakm (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dm_wr_dcsr),
                                               .d_i (dm_csr_wdata_i[15]),              .q_o(dcsr_ebreakm));
arv_dff #(.ARST_EN(ARST_EN)) u_dcsr_ebreaks (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dm_wr_dcsr),
                                               .d_i (dm_csr_wdata_i[13] & SU_MODE_EN), .q_o(dcsr_ebreaks));
arv_dff #(.ARST_EN(ARST_EN)) u_dcsr_ebreaku (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dm_wr_dcsr),
                                               .d_i (dm_csr_wdata_i[12] & SU_MODE_EN), .q_o(dcsr_ebreaku));
arv_dff #(.ARST_EN(ARST_EN)) u_dcsr_stepie (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dm_wr_dcsr),
                                               .d_i (dm_csr_wdata_i[11]),              .q_o(dcsr_stepie));
arv_dff #(.ARST_EN(ARST_EN)) u_dcsr_stopcount (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dm_wr_dcsr),
                                               .d_i (dm_csr_wdata_i[10]),              .q_o(dcsr_stopcount));
arv_dff #(.ARST_EN(ARST_EN)) u_dcsr_stoptime (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dm_wr_dcsr),
                                               .d_i (dm_csr_wdata_i[9]),               .q_o(dcsr_stoptime));
arv_dff #(.ARST_EN(ARST_EN)) u_dcsr_step (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(dm_wr_dcsr),
                                               .d_i (dm_csr_wdata_i[2]),               .q_o(dcsr_step));

// nmip[3]: read-only status reflection of a pending NMI.
wire dcsr_nmip = nmip_i;


//////======================================================================================================================//////
//////                                                                                                                      //////
//////    dcsr read assembly + DM read mux                                                                                  //////
//////                                                                                                                      //////
//////======================================================================================================================//////
wire [31:0] dcsr_read = { 4'd4,            // [31:28] debugver = 4 (external debug 1.0)
                          4'd0,            // [27:24] extcause
                          4'd0,            // [23:20] reserved
                          1'b0,            // [19]    cetrig
                          1'b0,            // [18]    pelp
                          1'b0,            // [17]    ebreakvs
                          1'b0,            // [16]    ebreakvu
                          dcsr_ebreakm,    // [15]
                          1'b0,            // [14]    reserved
                          dcsr_ebreaks,    // [13]
                          dcsr_ebreaku,    // [12]
                          dcsr_stepie,     // [11]
                          dcsr_stopcount,  // [10]
                          dcsr_stoptime,   // [9]
                          dcsr_cause,      // [8:6]
                          1'b0,            // [5]     v
                          1'b0,            // [4]     mprven
                          dcsr_nmip,       // [3]
                          dcsr_step,       // [2]
                          dcsr_prv };      // [1:0]

assign dm_csr_rdata_o = (dm_csr_sel_i == 2'd0) ? dcsr_read :
                        (dm_csr_sel_i == 2'd1) ? dpc_q     :
                                                 32'd0     ;

//////======================================================================================================================//////
//////                                                                                                                      //////
//////    Outputs                                                                                                           //////
//////                                                                                                                      //////
//////======================================================================================================================//////

assign debug_mode_o            = debug_mode_q;
assign debug_halt_active_o     = debug_halt_active;
assign debug_ebreak_cfg_o      = debug_ebreak_cfg;
assign debug_resume_redirect_o = debug_resume_redirect;
assign dpc_o                   = dpc_q;
assign dcsr_prv_o              = dcsr_prv;
assign ebreak_enter_debug_o    = ebreak_enter_debug;
assign debug_step_no_irq_o     = debug_step_no_irq;
assign debug_halted_raw_o      = debug_mode_q;   // RAW (undrained) Debug-Mode flag; drain-qualified in arv_csr_traps
assign dpc_valid_o             = dpc_captured_q; // dpc latched for this halt

// Counter-freeze controls. Active only while in Debug Mode (debug_mode_q registered),
// gated by the corresponding dcsr bit. stopcount freezes the hart-local counters'
// INCREMENT (mcycle/minstret/hpm) - CSR writes still land; stoptime drives an off-core
// pin so the SoC freezes mtime. With DEBUG_EN=0 this module is not built and both
// collapse to 0 via the g_no_debug tie-offs (core stays bit-identical).
assign debug_stopcount_o       = debug_mode_q & dcsr_stopcount;
assign debug_stoptime_o        = debug_mode_q & dcsr_stoptime;

endmodule // arv_csr_debug

`default_nettype wire

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_csr_traps
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_csr_traps.v
// Module Description : RISC-V CSRs: trap entry/exit FSM (mstatus / mie / mip / mtvec / mepc / mcause /
//                                                        mtval + S-mode shadows + mideleg /
//                                                        medeleg + WFI sleep + IRQ/NMI prioritisation
//                                                        + Ssdbltrp double trap: SDT / menvcfgh.DTE / mtval2)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_csr_traps (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// INTERFACE TO READ/WRITE CSR REGISTERS WITH INSTRUCTIONS
    input  wire           bank_mtrap_setup_i,
    input  wire           bank_mtrap_handling_i,
    input  wire           bank_strap_setup_i,
    input  wire           bank_strap_handling_i,
    input  wire           bank_nmi_handling_i,
    input  wire           disable_write_i,
    input  wire    [63:0] register_sel_i,
    input  wire    [31:0] register_value_nxt_i,
    output wire    [31:0] traps_rdata_o,
    output wire    [10:0] scounteren_o,

// INTERFACE TO INSTRUCTION FETCH AND INST DECODER
    input  wire           id_opcode_mret_i,
    input  wire           id_opcode_sret_i,
    output wire           cfg_timeout_wait_o,
    output wire           cfg_trap_sret_o,
    output wire           cfg_trap_vm_o,

// TRAP INTERFACE TO DECODE
    output wire           trap_stall_o,
    output wire           ex_excp_squash_o,
    output wire           trap_branch_detect_o,
    output wire    [31:0] trap_branch_target_o,
    output wire           wfi_wakeup_o,
    output wire           wfi_wakeup_live_o,
    input  wire           id_wfi_active_i,

// EXTERNAL INTERRUPT INPUTS
    input  wire           irq_m_software_i,
    input  wire           irq_s_software_i,
    input  wire           irq_m_timer_i,
    input  wire           irq_m_external_i,
    input  wire           irq_s_external_i,
    input  wire    [15:0] irq_platform_i,

// EXCEPTIONS (SYNCHRONOUS TRAPS)
    input  wire           if_excp_inst_address_misaligned_i,
    input  wire           id_excp_inst_access_fault_i,
    input  wire    [31:0] id_inst_fault_addr_i,
    input  wire           id_excp_illegal_inst_i,
    input  wire           id_excp_ebreak_i,
    input  wire           id_excp_ebreak_nodbg_i,
    input  wire           id_excp_ecall_i,
    input  wire           ex_excp_illegal_inst_i,
    input  wire           ex_excp_load_address_misaligned_i,
    input  wire           ex_excp_store_address_misaligned_i,
    input  wire           ex_excp_load_access_fault_i,
    input  wire           ex_excp_store_access_fault_i,
    input  wire           wb_bus_error_load_i,
    input  wire           wb_bus_error_store_i,
    input  wire           wb_uop_sourced_i,       // the access in the data phase came from a Zcmp/Zcmt micro-op
    input  wire           wb_uop_seq_alive_i,     // ... and the sequence that issued it still owns EX
    input  wire           wb_uop_jt_sourced_i,    // the access in the data phase is a Zcmt table read

// SDTRIG EXECUTE-TRIGGER (Sdtrig mcontrol6)
    input  wire           trigger_exec_match_i,   // EARLY action-agnostic match (fire w/o the issue-active qualifier; flop-sourced) -> debug_issue_hold_o leg only
    input  wire           trigger_exec_fire_i,    // a matching execute trigger fires this cycle
    input  wire           trigger_exec_action_i,  // its action (1=enter-debug, 0=breakpoint excp)
    output wire           m_trap_entry_o,         // M-mode trap being taken this cycle (mte FSM, excl. NMI)
    output wire           mret_o,                 // mret retiring this cycle (mte FSM restore)
    output wire           rnmi_entry_o,           // RNMI (or double-trap divert) being taken this cycle (mte FSM, NMI stack)
    output wire           mnret_o,                // mnret retiring this cycle (mte FSM restore from the NMI shadow)

// SDTRIG LOAD/STORE DATA-ADDRESS WATCHPOINT (Sdtrig mcontrol6; EX stage, rides misalign)
    input  wire           trigger_ls_fire_i,      // a matching load/store watchpoint fires this cycle
    input  wire           trigger_ls_action_i,    // its action (1=enter-debug, 0=breakpoint excp)
    input  wire           resethaltreq_i,         // DM resethaltreq state -> hart halts out of reset (cause=5)

// PIPELINE READY SIGNALS (FOR DRAIN DETECTION)
    input  wire           ex_alu_ready_i,
    input  wire           ex_ldst_ready_i,
    input  wire           ex_ldst_unresolved_i,   // EX load/store whose fault status is not yet known
    input  wire           ex_pmp_refetch_i,       // PMP CSR write in EX: the pending fetch fault was checked under the old PMP state
    input  wire           ex_csr_ready_i,
    input  wire           ex_uop_has_branch_i,
    input  wire           ex_uop_ready_i,
    input  wire           ex_uop_take_branch_i,
    input  wire           id_instruction_valid_i,
    input  wire           wb_ldst_ready_i,

// PIPELINE MONITORING & CONTROL IN CASE OF TRAP
    output wire           if_stop_cmd_o,
    output wire           lockup_o,

// PC PIPELINE INPUTS (FOR MEPC SAVE)
    input  wire    [31:0] id_pc_i,
    input  wire    [31:0] ex_pc_i,
    input  wire    [31:0] wb_pc_i,

// DATA ADDRESS PIPELINE (FOR MTVAL SAVE)
    input  wire    [31:0] ex_data_addr_i,

// PRIVILEGE MODE
    input  wire     [1:0] priv_mode_current_i,
    output wire     [1:0] priv_mode_next_o,
    output wire           priv_mode_update_o,
    output wire     [1:0] priv_mode_ldst_o,

// WRITE-BACK SUPPRESSION
    output wire           trap_kill_ex_o,

// IRQ KILL FOR MULTI-CYCLE OPERATIONS
    input  wire           ex_alu_is_killable_i,
    input  wire           ex_uop_is_killable_i,
    input  wire           ex_uop_kill_window_i,     // push/pop still has a killable load/store ahead
    input  wire           ex_uop_jt_active_i,
    input  wire           id_uop_jt_start_i,
    input  wire     [3:0] marv_ctl_i,
    output wire           trap_kill_muldiv_o,
    output wire           trap_kill_uop_o,
    output wire           trap_kill_uop_hold_o,     // kill requested: the sequencer stops issuing and drains
    output wire           ex_uop_excp_abort_o,
    output wire           ex_uop_jt_fault_o,        // flop-sourced: the Zcmt table read got a bus error (abort the JT branch leg)

// HPM TRAP EVENTS
    output wire           trap_taken_o,
    output wire           trap_is_irq_o,
    output wire           minstret_undo_o,

// INITIALIZATION OF THE TRAP VECTOR DEFAULT VALUES
    input  wire           init_pc_i,
    input  wire    [31:0] reset_vector_i,

// NMI (SMRNMI)
    input  wire           nmi_i,
    input  wire    [31:0] marv_nmvec_i,                // RNMI handler base (CSR 0x7FD, owned by arv_csr_top)
    input  wire           id_opcode_mnret_i,

// MIP[9] SEIP RMW WRITE-BACK
    output wire           sip_seip_sw_o,
    input  wire           mip_seip_sw_rmw_nxt_i,

// INSTRUCTION RETIRE (single-step boundary - consumed only when DEBUG_EN=1)
    input  wire           inst_retired_i,

// EXTERNAL DEBUG (Sdext)
    input  wire           debug_req_i,
    input  wire           resume_req_i,
    input  wire           dm_csr_access_i,
    input  wire     [1:0] dm_csr_sel_i,
    input  wire           dm_csr_wen_i,
    input  wire    [31:0] dm_csr_wdata_i,
    output wire    [31:0] dm_csr_rdata_o,
    output wire           debug_mode_o,
    output wire           debug_halt_active_o,
    output wire           debug_issue_hold_o,          // EARLY flop-sourced issue hold for decode (see arv_csr_debug)
    output wire           debug_ebreak_cfg_o,          // dcsr.ebreak* enable for the current privilege (see arv_csr_debug)
    output wire           debug_halted_o,
    output wire           debug_stopcount_o,
    output wire           debug_stoptime_o

);

// PARAMETER
//=====================================================
parameter                 ARST_EN        = 1'b1;       // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 C_EXT_EN       = 1'b0;       // Compressed instructions enabled (affects MEPC/SEPC alignment)
parameter                 SU_MODE_EN     = 1'b1;       // S+U privilege modes (0=M-only: S-CSRs absent (illegal), no delegation,
                                                       // current_priv hardwired to M, MPP forced to M; 1=M+S+U full)
parameter                 DEBUG_EN       = 1'b0;       // External debug (Sdext)
parameter                 PMP_NR         = 0;          // Writable PMP entries: 0, 4, 8 or 16 (0 = causes 5/7 have no producer)
parameter                 ZICNTR_EN      = 1'b1;       // Zicntr: cycle / time / instret (scounteren enable bits 2:0)
parameter                 ZIHPM_NR       = 0;          // Zihpm counters 3..10 implemented (scounteren enable bits 10:3)


//////======================================================================================================================//////
//////                              INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION: TRAP-SETUP REGISTERS                   //////
//////======================================================================================================================//////

wire  [31:0] sstatus;
wire         sstatus_sel;
wire         sstatus_wr;
wire         sstatus_sie;
wire         sstatus_spie;
wire         sstatus_spp;

wire  [31:0] sie;
wire         sie_sel;
wire         sie_wr;
wire         sie_ssie;
wire         sie_stie;
wire         sie_seie;
wire  [15:0] sie_spie;

wire  [31:0] stvec;
wire         stvec_sel;
wire         stvec_wr;
wire   [1:0] stvec_mode;
wire  [29:0] stvec_base;

wire  [31:0] scounteren;
wire         scounteren_sel;
wire         scounteren_wr;
wire  [10:0] scounteren_reg;

wire  [31:0] mstatus;
wire         mstatus_sel;
wire         mstatus_wr;
wire         mstatus_mie;
wire         mstatus_mpie;
wire   [1:0] mstatus_mpp;
wire         mstatus_mprv;
wire         mstatus_tw;
wire         mstatus_tsr;
wire         mstatus_sum;
wire         mstatus_mxr;
wire         mstatus_tvm;

wire  [31:0] medeleg;
wire         medeleg_sel;
wire         medeleg_wr;
wire         medeleg_iadm;
wire         medeleg_iacf;
wire         medeleg_illi;
wire         medeleg_ebrk;
wire         medeleg_ldam;
wire         medeleg_ldaf;
wire         medeleg_stam;
wire         medeleg_staf;
wire         medeleg_ecau;
wire         medeleg_ecas;

wire  [31:0] mideleg;
wire         mideleg_sel;
wire         mideleg_wr;
wire         mideleg_ssi;
wire         mideleg_sti;
wire         mideleg_sei;
wire  [15:0] mideleg_dpu;

wire  [31:0] mie;
wire         mie_sel;
wire         mie_wr;
wire         mie_msie;
wire         mie_mtie;
wire         mie_meie;
wire  [15:0] mie_mpie;

wire  [31:0] mtvec;
wire         mtvec_sel;
wire         mtvec_wr;
wire   [1:0] mtvec_mode;
wire  [29:0] mtvec_base;

wire  [31:0] mstatush;
wire         mstatush_sel;
wire         mstatush_wr;
wire         mstatush_mdt;

wire  [31:0] medelegh;
wire         medelegh_sel;
//wire       medelegh_wr;

wire  [31:0] menvcfgh;
wire         menvcfgh_sel;
wire         menvcfgh_wr;

wire  [31:0] mscratch;
wire         mscratch_sel;
wire         mscratch_wr;
wire  [31:0] mscratch_mscratch;

wire  [31:0] sscratch;
wire         sscratch_sel;
wire         sscratch_wr;
wire  [31:0] sscratch_sscratch;

wire  [31:0] mepc;
wire         mepc_sel;
wire         mepc_wr;
wire  [30:0] mepc_mepc;

wire  [31:0] sepc;
wire         sepc_sel;
wire         sepc_wr;
wire  [30:0] sepc_sepc;

wire  [31:0] mcause;
wire         mcause_sel;
wire         mcause_wr;
wire         mcause_irq;
wire   [4:0] mcause_mcause;

wire  [31:0] scause;
wire         scause_sel;
wire         scause_wr;
wire         scause_irq;
wire   [4:0] scause_scause;

wire  [31:0] mtval;
wire         mtval_sel;
wire         mtval_wr;
wire  [31:0] mtval_mtval;

wire  [31:0] stval;
wire         stval_sel;
wire         stval_wr;
wire  [31:0] stval_stval;

wire  [31:0] mip;
wire         mip_sel;
wire         mip_wr;
wire         mip_msip;
wire         mip_mtip;
wire         mip_meip;

wire  [31:0] sip;
wire         sip_sel;
wire         sip_wr;
wire         sip_ssip;
wire         sip_stip;
wire         sip_seip_sw;
wire         sip_seip;

wire  [15:0] ie_pie;
wire  [15:0] ip_pip;

wire  [31:0] mtinst;
wire         mtinst_sel;
//wire       mtinst_wr;

wire  [31:0] mtval2;
wire         mtval2_sel;
wire         mtval2_wr;

// Ssdbltrp: effective SDT = SDT flop & menvcfgh.DTE. This is BOTH the reads-as
// value of mstatus/sstatus bit 24 AND the double-trap redirect arm (DTE=0 makes
// the extension behave as absent). Tied 0 when SU_MODE_EN=0 (g_no_ssdbltrp).
wire         sstatus_sdt_eff;
wire         sstatus_sdt_eff_route;

wire         current_in_machine;
wire         current_in_supervisor;
wire         current_in_user;

wire         excp_detect_in_if;
wire         excp_detect_in_id;
wire         excp_detect_in_ex;

wire         excp_ignore_deleg;
wire  [11:0] excp_vector_prio;
wire  [11:0] excp_vector_highest;
wire  [11:0] excp_vector_cause;
wire  [11:0] excp_vector_deleg;
wire   [3:0] excp_cause;
wire         excp_detect;
wire         excp_detect_to_m;
wire         excp_detect_to_s;
wire         excp_detect_to_s_raw;
wire         excp_dbl_trap;

wire         irq_ignore_deleg;
wire  [31:0] irq_vector_prio;
wire  [31:0] irq_vector_highest;
wire  [31:0] irq_vector_cause;
wire  [31:0] irq_vector_deleg;
wire   [4:0] irq_cause;
wire         irq_detect;
wire         irq_detect_to_m;
wire         irq_detect_to_s;
wire         irq_detect_to_s_raw;
wire         irq_dbl_trap;

// Trap state machine
wire         trap_taken;
wire         trap_is_irq;
wire         trap_is_nmi;
wire         trap_is_dbl;
wire         trap_to_m;
wire         trap_to_s;
wire         m_trap_entry;          // Trap delivered to M-mode through the mstatus/mepc/mcause stack
wire         m_dbl_trap;            // Smdbltrp: that trap arrived while mstatus.MDT was already set
wire         m_dbl_to_rnmi;         // ... and mnstatus.NMIE=1, so it diverts to the RNMI handler
wire         m_dbl_to_cerr;         // ... and mnstatus.NMIE=0, so the hart enters the critical-error state
wire         rnmi_entry;            // Any delivery through the mnepc/mncause/mnstatus stack
wire   [4:0] trap_cause_latched;
wire  [31:0] mepc_save_latched;
wire  [31:0] mtval_save_latched;
wire  [31:0] mepc_save_value;
wire         mret_taken;
wire         sret_taken;
wire         mnret_taken;
wire   [2:0] trap_stage;
wire         nmi_suppress_post_mnret;

wire  [31:0] trap_target_direct;
wire  [31:0] trap_target_vectored;
wire         use_vectored;
wire  [31:0] trap_branch_target_comb;
wire         trap_branch_detect_comb;
wire  [31:0] trap_branch_target_r;
wire         trap_branch_detect_r;
wire   [1:0] priv_mode_next_comb;
wire         priv_mode_update_comb;
wire   [1:0] priv_mode_next_r;
wire         priv_mode_update_r;

wire         mepc_align_mask;
wire         uop_wait_for_id_valid;
wire         trap_pending;
wire         uop_kill_suppress;
wire         uop_async_ok;
wire         id_pc_settled;
wire         trap_stall_raw;
wire         muldiv_kill_suppress;

wire         in_lockup;
wire         pipeline_drained_for_id;
wire         pipeline_drained_for_ex;

// NMI CSR register select
wire         mnscratch_sel;
wire         mnepc_sel;
wire         mncause_sel;
wire         mnstatus_sel;

// NMI CSR storage
wire  [30:0] mnepc_mnepc;
wire         mnstatus_nmie;         // NMI enable bit (cleared on NMI entry, set on mnret)
wire   [1:0] mnstatus_mnpp;         // Previous privilege mode (saved on NMI entry)

// NMI CSR read values
wire  [31:0] mnscratch;
wire  [31:0] mnepc;
wire  [31:0] mncause;
wire  [31:0] mnstatus;

// NMI control
wire         nmi_detect;            // NMI is active and NMIE is set
wire         nmi_any_source;        // any RNMI source pending: registered pin OR sticky data-bus error


//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                 EXTERNAL DEBUG (Sdext)                                               //////
//////                                                                                                                      //////
//////======================================================================================================================//////

wire         dbg_halt_active;       // WFI-style issue stall (-> decode) + IRQ mask + clock-alive
wire         dbg_resume_redirect;   // 1-cycle resume pulse -> trap-redirect mux (target=dpc)
wire  [31:0] dbg_dpc;               // parked resume PC
wire   [1:0] dbg_dcsr_prv;          // privilege to restore on resume
wire         dbg_ebreak_enter;      // ebreak should enter Debug Mode (mask normal trap)
wire         dbg_ls_wp_entry;       // Debug Mode entered on a load/store watchpoint (un-retire the access)
wire         ls_debug_fire;         // load/store watchpoint with action=1 (enter Debug Mode)
assign       ls_debug_fire        = trigger_ls_fire_i & trigger_ls_action_i;
wire         dbg_step_no_irq;       // single-step with dcsr.stepie=0 -> mask IRQ + NMI at source
wire         trigger_ls_break;

generate
if (DEBUG_EN) begin : g_debug

    wire     dbg_mode;              // in Debug Mode (halted)
    wire     dbg_halted_raw;        // Debug Mode flag before pipeline-drain qualification (g_debug-local)
    wire     dbg_dpc_valid;         // dpc captured for this halt (qualifies DM-facing allhalted)

    // PC the critical error stopped on -- the value mepc WOULD have taken, so it carries the
    // kill-override in mepc_save_value rather than the raw latch. A debugger halting the hart
    // afterwards must read this as dpc: the instruction never ran, so it is still "the next
    // instruction to execute". Sticky on the same edge as in_lockup, so a later halt/resume
    // cycle cannot rewrite it. Lives here because arv_csr_debug is its only reader; in_lockup
    // itself stays unconditional, since lockup_o is a pin in every configuration.
    wire [31:0] crit_error_pc;
    arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_crit_error_pc (
               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(m_dbl_to_cerr), .d_i(mepc_save_value), .q_o(crit_error_pc));

    arv_csr_debug #(.ARST_EN(ARST_EN), .SU_MODE_EN(SU_MODE_EN), .C_EXT_EN(C_EXT_EN)) u_arv_csr_debug (

// Clock / reset
        .hclk_i                  ( hclk_i                 ),
        .hresetn_i               ( hresetn_i              ),

// Hart state taps
        .priv_mode_current_i     ( priv_mode_current_i    ),
        .id_pc_i                 ( id_pc_i                ),
        .ex_pc_i                 ( ex_pc_i                ),
        .id_instruction_valid_i  ( id_instruction_valid_i ),
        .id_excp_inst_access_fault_i ( id_excp_inst_access_fault_i ),
        .crit_error_i            ( in_lockup              ),
        .crit_error_pc_i         ( crit_error_pc          ),
        .id_wfi_active_i         ( id_wfi_active_i        ),
        .id_excp_ebreak_nodbg_i  ( id_excp_ebreak_nodbg_i ),
        .trigger_enter_debug_i   ((trigger_exec_fire_i & trigger_exec_action_i) |
                                  (trigger_ls_fire_i   & trigger_ls_action_i  ) ),  // Sdtrig action=1 (execute + load/store)
        .trigger_hold_early_i    ( trigger_exec_match_i                         ),  // EARLY hold: exec match (action-agnostic); an ls debug entry squashes instead
        .ls_wp_suppress_i        ( trigger_ls_fire_i                            ),  // a watchpoint suppressed the EX load/store this cycle (action-agnostic) -> on debug entry dpc=ex_pc
        .resethaltreq_i          ( resethaltreq_i         ),                        // DM resethaltreq state -> halt out of reset (cause=5)
        .trap_pending_i          ( trap_pending         ),
        .entry_defer_i           ((excp_detect_in_ex & ~ls_debug_fire) |                       // let an older EX fault latch before a halt/step entry,
                                   ex_ldst_unresolved_i | ((ex_uop_has_branch_i | ~ex_uop_ready_i) & ~ls_debug_fire) ), // and a UOP sequence to complete first; a load/store
                                                                                                   // watchpoint outranks its own access's misalign/access
                                                                                                   // fault and aborts the UOP sequence, so it enters now
        .nmip_i                  ( nmi_any_source         ),  // dcsr.nmip: pin (registered) OR sticky data-bus-error RNMI
        .inst_retired_i          ( inst_retired_i         ),
        .trap_taken_i            ( trap_taken             ),

// External debug-control handshake
        .debug_req_i             ( debug_req_i            ),
        .resume_req_i            ( resume_req_i           ),

// Debug-Module abstract CSR access side-port
        .dm_csr_access_i         ( dm_csr_access_i        ),
        .dm_csr_sel_i            ( dm_csr_sel_i           ),
        .dm_csr_wen_i            ( dm_csr_wen_i           ),
        .dm_csr_wdata_i          ( dm_csr_wdata_i         ),
        .dm_csr_rdata_o          ( dm_csr_rdata_o         ),

// Debug-mode status / control to the rest of the core
        .debug_mode_o            ( dbg_mode               ),
        .debug_halt_active_o     ( dbg_halt_active        ),
        .debug_issue_hold_o      ( debug_issue_hold_o     ),
        .debug_ebreak_cfg_o      ( debug_ebreak_cfg_o     ),
        .debug_resume_redirect_o ( dbg_resume_redirect    ),
        .dpc_o                   ( dbg_dpc                ),
        .dcsr_prv_o              ( dbg_dcsr_prv           ),
        .ebreak_enter_debug_o    ( dbg_ebreak_enter       ),
        .ls_wp_entry_o           ( dbg_ls_wp_entry        ),
        .debug_halted_raw_o      ( dbg_halted_raw         ),
        .dpc_valid_o             ( dbg_dpc_valid          ),
        .debug_step_no_irq_o     ( dbg_step_no_irq        ),
        .debug_stopcount_o       ( debug_stopcount_o      ),
        .debug_stoptime_o        ( debug_stoptime_o       )
    );

    assign      debug_mode_o                = dbg_mode;
    assign      debug_halt_active_o         = dbg_halt_active;

    // Drain-qualified halted status reported to the Debug Module: Debug Mode AND the
    // pipeline has drained (no in-flight MUL/DIV/load/CSR/UOP writeback, and no
    // non-killable cm.jt/cm.jalt AHB phase) AND dpc has been captured for this halt.
    assign      debug_halted_o              = dbg_halted_raw & pipeline_drained_for_id & ~ex_uop_jt_active_i & dbg_dpc_valid;

end else begin : g_no_debug

    assign      dm_csr_rdata_o              = 32'h0;
    assign      dbg_halt_active             =  1'b0;
    assign      debug_issue_hold_o          =  1'b0;
    assign      debug_ebreak_cfg_o          =  1'b0;

    assign      dbg_resume_redirect         =  1'b0;
    assign      dbg_dpc                     = 32'h0;
    assign      dbg_dcsr_prv                =  2'b11;
    assign      dbg_ebreak_enter            =  1'b0;
    assign      dbg_ls_wp_entry             =  1'b0;
    assign      dbg_step_no_irq             =  1'b0;
    assign      debug_mode_o                =  1'b0;
    assign      debug_halt_active_o         =  1'b0;
    assign      debug_halted_o              =  1'b0;
    assign      debug_stopcount_o           =  1'b0;
    assign      debug_stoptime_o            =  1'b0;

    // Lint cleanup
    wire        debug_req_unused            = debug_req_i;
    wire        resume_req_unused           = resume_req_i;
    wire        id_excp_ebreak_nodbg_unused = id_excp_ebreak_nodbg_i;
    wire        trigger_exec_match_unused   = trigger_exec_match_i;
    wire        dm_csr_access_unused        = dm_csr_access_i;
    wire  [1:0] dm_csr_sel_unused           = dm_csr_sel_i;
    wire        dm_csr_wen_unused           = dm_csr_wen_i;
    wire [31:0] dm_csr_wdata_unused         = dm_csr_wdata_i;
    wire        inst_retired_unused         = inst_retired_i;
    wire        resethaltreq_unused         = resethaltreq_i;
end
endgenerate


//////======================================================================================================================//////
//////                                        REGISTERED IRQ / NMI INPUTS                                                   //////
//////                                                                                                                      //////
//////  Registering these primary inputs breaks the combinatorial feedthrough path:                                         //////
//////    irq_*_i / nmi_i -> irq_detect/nmi_detect -> trap_stall_o -> id_branch_detect_o -> inst_haddr_o                    //////
//////======================================================================================================================//////

wire         irq_m_software_r;
wire         irq_s_software_r;
wire         irq_m_timer_r;
wire         irq_m_external_r;
wire         irq_s_external_r;
wire  [15:0] irq_platform_r;
wire         nmi_r;

arv_dff #(.ARST_EN(ARST_EN))             u_irq_m_software_r (
                       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(irq_m_software_i), .q_o(irq_m_software_r));
arv_dff #(.ARST_EN(ARST_EN))             u_irq_s_software_r (
                       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(irq_s_software_i), .q_o(irq_s_software_r));
arv_dff #(.ARST_EN(ARST_EN))             u_irq_m_timer_r    (
                       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(irq_m_timer_i),    .q_o(irq_m_timer_r));
arv_dff #(.ARST_EN(ARST_EN))             u_irq_m_external_r (
                       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(irq_m_external_i), .q_o(irq_m_external_r));
arv_dff #(.ARST_EN(ARST_EN))             u_irq_s_external_r (
                       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(irq_s_external_i), .q_o(irq_s_external_r));
arv_dff #(.WIDTH(16), .ARST_EN(ARST_EN)) u_irq_platform_r   (
                       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(irq_platform_i),   .q_o(irq_platform_r));
arv_dff #(.ARST_EN(ARST_EN))             u_nmi_r            (
                       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(nmi_i),            .q_o(nmi_r));




//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       SUPERVISOR TRAP SETUP REGISTERS                                                //////
//////                                                                                                                      //////
//////----------------------------------------------------------------------------------------------------------------------//////
//////                                                                                                                      //////
//////        Supervisor Trap Setup:                                                                                        //////
//////                                  + SSTATUS  : 0x100 : Supervisor status register                                     //////
//////                                  + SIE      : 0x104 : Supervisor interrupt-enable register                           //////
//////                                  + STVEC    : 0x105 : Supervisor trap handler base address                           //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//
//  DECODER
//
assign       sstatus_sel    =  (register_sel_i['h0]  &  bank_strap_setup_i);  // 0x100
assign       sie_sel        =  (register_sel_i['h4]  &  bank_strap_setup_i);  // 0x104
assign       stvec_sel      =  (register_sel_i['h5]  &  bank_strap_setup_i);  // 0x105
assign       scounteren_sel =  (register_sel_i['h6]  &  bank_strap_setup_i);  // 0x106

assign       sstatus_wr     = ((sstatus_sel          & ~disable_write_i) | mstatus_wr) & SU_MODE_EN;
assign       sie_wr         = ((sie_sel              & ~disable_write_i) | mie_wr    ) & SU_MODE_EN;
assign       stvec_wr       =  (stvec_sel            & ~disable_write_i)               & SU_MODE_EN;
assign       scounteren_wr  =  (scounteren_sel       & ~disable_write_i)               & SU_MODE_EN;

//
//  SSTATUS (0x100 : Supervisor status register)
//
//                       - SIE   1     S-mode global interrupt-enable bit (self clears when entered)
//                       - SPIE  5     Holds the value of the interrupt-enable bit active prior to the S-mode trap (copy of SIE before the trap)
//                       - SPP   8     Holds the previous privilege mode before the trap (either U or S)
//

// Ssdbltrp: a write that sets SDT (bit 24, honoured only while DTE=1) clears SIE
// regardless of the SIE value written in the same access.
wire sstatus_sdt_wr_set = sstatus_wr & menvcfgh[27] & register_value_nxt_i[24];
wire sstatus_sie_en  = (trap_taken & trap_to_s) | sret_taken | sstatus_wr;
wire sstatus_sie_nxt = (trap_taken & trap_to_s) ? 1'b0          :
                       sret_taken               ? sstatus_spie  :
                                                 (register_value_nxt_i[1] & ~sstatus_sdt_wr_set);
arv_dff #(.ARST_EN(ARST_EN)) u_sstatus_sie (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sstatus_sie_en), .d_i(sstatus_sie_nxt), .q_o(sstatus_sie));

wire sstatus_spie_en  = (trap_taken & trap_to_s) | sret_taken | sstatus_wr;
wire sstatus_spie_nxt = (trap_taken & trap_to_s) ? sstatus_sie   :
                        sret_taken               ? 1'b1          :
                                                   register_value_nxt_i[5];
arv_dff #(.ARST_EN(ARST_EN)) u_sstatus_spie (
        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sstatus_spie_en), .d_i(sstatus_spie_nxt), .q_o(sstatus_spie));

wire sstatus_spp_en  = (trap_taken & trap_to_s) | sret_taken | sstatus_wr;
wire sstatus_spp_nxt = (trap_taken & trap_to_s) ? priv_mode_current_i[0] :
                       sret_taken               ? 1'b0                   :
                                                  register_value_nxt_i[8];
arv_dff #(.ARST_EN(ARST_EN)) u_sstatus_spp (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sstatus_spp_en), .d_i(sstatus_spp_nxt), .q_o(sstatus_spp));

//
//  SIE (0x104 : Supervisor Interrupt Enable Register)
//
//                       - SSIE  1     Interrupt-enable bit for supervisor-level software interrupts.
//                       - STIE  5     Interrupt-enable bit for supervisor-level timer interrupts.
//                       - SEIE  9     Interrupt-enable bit for supervisor-level external interrupts.
//                       - SPIE  31:16 Interrupt-enable bit for supervisor-level interrupts designated for platform use.
//
wire  mie_wr_msk = mie_wr & SU_MODE_EN;

// Writes via SIE to bits where mideleg=0 must be ignored (only M-mode via MIE may change them).
wire sie_ssie_en  = mie_wr_msk | (sie_wr & mideleg_ssi);
wire sie_ssie_nxt = register_value_nxt_i[1];
arv_dff #(.ARST_EN(ARST_EN)) u_sie_ssie (
    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sie_ssie_en), .d_i(sie_ssie_nxt), .q_o(sie_ssie));

wire sie_stie_en  = mie_wr_msk | (sie_wr & mideleg_sti);
wire sie_stie_nxt = register_value_nxt_i[5];
arv_dff #(.ARST_EN(ARST_EN)) u_sie_stie (
    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sie_stie_en), .d_i(sie_stie_nxt), .q_o(sie_stie));

wire sie_seie_en  = mie_wr_msk | (sie_wr & mideleg_sei);
wire sie_seie_nxt = register_value_nxt_i[9];
arv_dff #(.ARST_EN(ARST_EN)) u_sie_seie (
    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sie_seie_en), .d_i(sie_seie_nxt), .q_o(sie_seie));

wire        ie_pie_en  = mie_wr | sie_wr;
wire [15:0] ie_pie_nxt = mie_wr ?  register_value_nxt_i[31:16]                                          :  // access through MIE can write everything
                                 ((register_value_nxt_i[31:16] & mideleg_dpu) | (ie_pie & ~mideleg_dpu));  // access through SIE only write delegated bits
arv_dff #(.WIDTH(16), .ARST_EN(ARST_EN)) u_ie_pie (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ie_pie_en), .d_i(ie_pie_nxt), .q_o(ie_pie));

// Supervisor mode only reads delegated. Machine always reads everything
assign sie_spie = ie_pie & mideleg_dpu;
assign mie_mpie = ie_pie;

//
//  STVEC (0x105 : Supervisor trap handler base address)
//
//                       - MODE  1:0   Vector mode (0: Direct -> all traps set pc to BASE / 1: Vectored -> asynchronous interrupts set pc to BASE+4×cause)
//                       - BASE  31:2  Vector base address.
//

arv_dff #(.WIDTH(2), .ARST_EN(ARST_EN)) u_stvec_mode (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(stvec_wr),
                                                      .d_i ({1'b0, register_value_nxt_i[0]}),
                                                      .q_o (stvec_mode));  // MODE >= 2 reserved

// CONTRACT: init_pc_i MUST be a single-cycle pulse. A level-held driver would clobber subsequent stvec_wr writes every cycle the level is held.
wire init_pc_msk = init_pc_i & SU_MODE_EN;
wire        stvec_base_en  = stvec_wr | init_pc_msk;
wire [29:0] stvec_base_nxt = stvec_wr ? register_value_nxt_i[31:2] : (reset_vector_i[31:2]+30'h00000003);   // reset_vector + 12
arv_dff #(.WIDTH(30), .ARST_EN(ARST_EN)) u_stvec_base (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(stvec_base_en),
                                                       .d_i (stvec_base_nxt),
                                                       .q_o (stvec_base));

//
//  SCOUNTEREN (0x106 : Supervisor Counter Enable)
//
//                       - CY    0     Allow U-mode to read cycle/cycleh
//                       - TM    1     Allow U-mode to read time/timeh
//                       - IR    2     Allow U-mode to read instret/instreth
//                       - HPM3.. 10:3 Allow U-mode to read hpmcounter3..10
//
//  U-mode counter access is permitted iff (mcounteren[i] & scounteren[i]) for
//  the corresponding bit. S-mode access is gated by mcounteren only.
//
// A counter-enable bit for a counter that is not implemented is read-only zero
// (Priv 3.1.11). mcounteren gets that for free -- arv_csr_cntr.v is not built
// when Zicntr is absent -- but scounteren lives here, so it masks explicitly:
// bits 2:0 follow Zicntr, bits 10:3 follow the implemented mhpmcounter3..10.
localparam [7:0]  SCOUNTEREN_HPM_MASK = (ZIHPM_NR  >= 8) ? 8'hFF  : ((8'h01 << ZIHPM_NR) - 8'h01);
localparam [2:0]  SCOUNTEREN_STD_MASK = (ZICNTR_EN != 0) ? 3'b111 : 3'b000;
localparam [10:0] SCOUNTEREN_MASK     = {SCOUNTEREN_HPM_MASK, SCOUNTEREN_STD_MASK};

arv_dff #(.WIDTH(11), .ARST_EN(ARST_EN)) u_scounteren_reg (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(scounteren_wr),
                                                           .d_i (register_value_nxt_i[10:0] & SCOUNTEREN_MASK),
                                                           .q_o (scounteren_reg));

assign scounteren = {21'h0, scounteren_reg};
assign scounteren_o = scounteren_reg;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                           MACHINE TRAP SETUP REGISTERS                                               //////
//////                                                                                                                      //////
//////----------------------------------------------------------------------------------------------------------------------//////
//////                                                                                                                      //////
//////        Machine Trap Setup:                                                                                           //////
//////                                  + MSTATUS  : 0x300 : Machine status register                                        //////
//////                                  + MEDELEG  : 0x302 : Machine exception delegation register                          //////
//////                                  + MIDELEG  : 0x303 : Machine interrupt delegation register                          //////
//////                                  + MIE      : 0x304 : Machine interrupt-enable register                              //////
//////                                  + MTVEC    : 0x305 : Machine trap-handler base address                              //////
//////                                  + MSTATUSH : 0x310 : Additional machine status register, RV32 only                  //////
//////                                  + MEDELEGH : 0x312 : Upper 32bits of medeleg, RV32 only                             //////
//////                                  + MENVCFGH : 0x31A : Upper 32bits of menvcfg, RV32 only (Ssdbltrp DTE only)         //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//
//  DECODER
//
assign       mstatus_sel    =  (register_sel_i['h0]  &  bank_mtrap_setup_i);  // 0x300
assign       medeleg_sel    =  (register_sel_i['h2]  &  bank_mtrap_setup_i);  // 0x302
assign       mideleg_sel    =  (register_sel_i['h3]  &  bank_mtrap_setup_i);  // 0x303
assign       mie_sel        =  (register_sel_i['h4]  &  bank_mtrap_setup_i);  // 0x304
assign       mtvec_sel      =  (register_sel_i['h5]  &  bank_mtrap_setup_i);  // 0x305
assign       mstatush_sel   =  (register_sel_i['h10] &  bank_mtrap_setup_i);  // 0x310
assign       medelegh_sel   =  (register_sel_i['h12] &  bank_mtrap_setup_i);  // 0x312
assign       menvcfgh_sel   =  (register_sel_i['h1A] &  bank_mtrap_setup_i);  // 0x31A

assign       mstatus_wr     =  (mstatus_sel          & ~disable_write_i);
assign       medeleg_wr     =  (medeleg_sel          & ~disable_write_i) & SU_MODE_EN;  // absent (illegal-instruction) when SU_MODE_EN=0
assign       mideleg_wr     =  (mideleg_sel          & ~disable_write_i) & SU_MODE_EN;  // absent (illegal-instruction) when SU_MODE_EN=0
assign       mie_wr         =  (mie_sel              & ~disable_write_i);
assign       mtvec_wr       =  (mtvec_sel            & ~disable_write_i);
assign       mstatush_wr    =  (mstatush_sel         & ~disable_write_i);
//assign     medelegh_wr    =  (medelegh_sel         & ~disable_write_i);
assign       menvcfgh_wr    =  (menvcfgh_sel         & ~disable_write_i) & SU_MODE_EN;  // absent (illegal-instruction) when SU_MODE_EN=0

//
//  MSTATUS (0x300 : Machine status register)
//
//                       - SIE   1     S-mode global interrupt-enable bit (self clears when entered)
//                       - MIE   3     M-mode global interrupt-enable bit (self clears when entered)
//                       - SPIE  5     Holds the value of the interrupt-enable bit active prior to the S-mode trap (copy of SIE before the trap)
//                       - MPIE  7     Holds the value of the interrupt-enable bit active prior to the M-mode trap (copy of MIE before the trap)
//                       - SPP   8     Holds the previous privilege mode before the trap (either U or S)
//                       - MPP   12:11 Holds the previous privilege mode before the trap (either U, S, H or M)
//                       - MPRV  17    Modify PRiVilege. When MPRV=1, loads/stores in M-mode use MPP privilege level.
//                       - TW    21    When TW=1, WFI will raise an illegal-instruction trap in S-Mode. When TW=0, WFI brings the CPU to sleep. WFI always traps in U-Mode regardless of TW.
//                       - TSR   22    Trap SRET. When TSR=1, attempts to execute SRET while executing in S-mode will raise an illegal-instruction exception.

// Smdbltrp couples MIE to MDT, and only for EXPLICIT CSR writes: setting MDT=1 by a write
// clears MIE, and a write of MIE=1 takes effect only while MDT is already 0. Hardware paths are
// untouched -- trap entry clears MIE on its own, and MRET restores it from MPIE while clearing
// MDT in the same cycle. On RV32 the two bits live in different CSRs, so there is no
// same-instruction case to resolve.
wire mdt_wr_set      = mstatush_wr & register_value_nxt_i[10];

wire mstatus_mie_en  = m_trap_entry | mret_taken | mstatus_wr | mdt_wr_set;
wire mstatus_mie_nxt = m_trap_entry ? 1'b0         :
                       mret_taken   ? mstatus_mpie :
                       mdt_wr_set   ? 1'b0         :
                                      (register_value_nxt_i[3] & ~mstatush_mdt);
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_mie (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_mie_en), .d_i(mstatus_mie_nxt), .q_o(mstatus_mie));

wire mstatus_mpie_en  = m_trap_entry | mret_taken | mstatus_wr;
wire mstatus_mpie_nxt = m_trap_entry ? mstatus_mie :
                        mret_taken   ? 1'b1        :
                                       register_value_nxt_i[7];
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_mpie (
        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_mpie_en), .d_i(mstatus_mpie_nxt), .q_o(mstatus_mpie));

// SU_MODE_EN=0: MPP hardwired to 2'b11 (M)
wire       mstatus_mpp_en  = m_trap_entry | mret_taken | mstatus_wr;
wire [1:0] mstatus_mpp_nxt = m_trap_entry ? priv_mode_current_i          :
                             mret_taken   ? (SU_MODE_EN ? 2'b00 : 2'b11) :
                                            (!SU_MODE_EN                            ? 2'b11        :
                                             (register_value_nxt_i[12:11] == 2'b10) ? 2'b00        : // 2'b10 is reserved (no H-mode): WARL to U, matching sail-riscv
                                                                                      register_value_nxt_i[12:11]);
arv_dff #(.WIDTH(2), .RST_VAL(SU_MODE_EN ? 2'b00 : 2'b11), .ARST_EN(ARST_EN)) u_mstatus_mpp (
                                                        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_mpp_en),
                                                                                             .d_i (mstatus_mpp_nxt),
                                                                                             .q_o (mstatus_mpp));

arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_tw (
      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_wr & SU_MODE_EN),
                                           .d_i (register_value_nxt_i[21]),
                                           .q_o (mstatus_tw));

arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_tsr (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_wr & SU_MODE_EN),
                                            .d_i (register_value_nxt_i[22]),
                                            .q_o (mstatus_tsr));

//                       - MPRV  17    Modify PRiVilege. When MPRV=1, loads/stores use MPP privilege instead of current mode.
//                                     Cleared on MRET/SRET/MNRET when returning to a mode less privileged than M.
wire mstatus_wr_msk = mstatus_wr & SU_MODE_EN;
// Priv. spec: "An MRET or SRET instruction that changes the privilege mode to a
// mode less privileged than M also sets MPRV=0"; SRET always returns to SPP in
// {S,U} < M, so its clear term is unconditional. Smrnmi extends the same rule to MNRET.
// SHARED TERM: Ssdbltrp gives sstatus.SDT the identical "xRET returning below M"
// hardware-clear condition, so the SDT flop (g_ssdbltrp) reuses this wire verbatim.
wire mstatus_mprv_clr = sret_taken | (mret_taken  & (mstatus_mpp   != 2'b11))
                                   | (mnret_taken & (mnstatus_mnpp != 2'b11))
                                   | (dbg_resume_redirect & (dbg_dcsr_prv != 2'b11));
wire mstatus_mprv_en  = mstatus_mprv_clr | mstatus_wr_msk;
wire mstatus_mprv_nxt = mstatus_mprv_clr ? 1'b0 :   // Clear when returning to mode < M (MRET/SRET/MNRET alike)
                                           register_value_nxt_i[17];
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_mprv (
        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_mprv_en),
                                             .d_i (mstatus_mprv_nxt),
                                             .q_o (mstatus_mprv));

// SUM (bit 18): hardwired 0. The spec ties this one to address translation, not
// merely to S-mode: "SUM is read-only 0 if S-mode is not supported OR IF
// satp.MODE IS READ-ONLY 0".
assign mstatus_sum = 1'b0;

// MXR (bit 19): WARL writable -- "MXR is read-only 0 if S-mode is not supported",
// with no satp.MODE clause (unlike SUM above), so it stays writable on a Bare-only hart.
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_mxr (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sstatus_wr),
                                            .d_i (register_value_nxt_i[19]),
                                            .q_o (mstatus_mxr));

// TVM (bit 20): M-only, not visible in sstatus. Same rule as MXR -- "TVM is
// read-only 0 when S-mode is not supported", with no satp.MODE clause.
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_tvm (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_wr & SU_MODE_EN),
                                            .d_i (register_value_nxt_i[20]),
                                            .q_o (mstatus_tvm));

assign  cfg_timeout_wait_o = mstatus_tw;
assign  cfg_trap_sret_o    = mstatus_tsr;
assign  cfg_trap_vm_o      = mstatus_tvm;


//
//  MEDELEG (0x302 : Machine exception delegation register)
//
//                       - IADM  0     Instruction address misaligned
//                       - IACF  1     Instruction access fault
//                       - ILLI  2     Illegal instruction
//                       - EBRK  3     Breakpoint
//                       - LDAM  4     Load address misaligned
//                       - LDAF  5     Load access fault
//                       - STAM  6     Store address misaligned
//                       - STAF  7     Store access fault
//                       - ECAU  8     Environment call from U-mode
//                       - ECAS  9     Environment call from S-mode
//                       - ECAM  11    Environment call from M-mode.   <-- read-only 0

arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_iadm (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[0]), .q_o(medeleg_iadm));
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_iacf (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[1]), .q_o(medeleg_iacf));
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_illi (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[2]), .q_o(medeleg_illi));
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_ebrk (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[3]), .q_o(medeleg_ebrk));
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_ldam (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[4]), .q_o(medeleg_ldam));
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_stam (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[6]), .q_o(medeleg_stam));

// medeleg[5] / medeleg[7] track whether causes 5 and 7 have a producer.
generate
if (PMP_NR != 0) begin : g_medeleg_acf
    arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_ldaf (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[5]), .q_o(medeleg_ldaf));
    arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_staf (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[7]), .q_o(medeleg_staf));
end else begin : g_no_medeleg_acf
    assign medeleg_ldaf = 1'b0;
    assign medeleg_staf = 1'b0;
end
endgenerate
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_ecau (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[8]), .q_o(medeleg_ecau));
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_ecas (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[9]), .q_o(medeleg_ecas));

//
//  MIDELEG (0x303 : Machine interrupt delegation register)
//
//                       - SSI   1     Supervisor software interrupt
//                       - MSI   3     Machine software interrupt      --> hardwired 0
//                       - STI   5     Supervisor timer interrupt
//                       - MTI   7     Machine timer interrupt         --> hardwired 0
//                       - SEI   9     Supervisor external interrupt
//                       - MEI   11    Machine external interrupt      --> hardwired 0
//                       - DPU   31:16 Designated for platform use

arv_dff #(.ARST_EN(ARST_EN))             u_mideleg_ssi (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mideleg_wr), .d_i(register_value_nxt_i[1]),     .q_o(mideleg_ssi));
arv_dff #(.ARST_EN(ARST_EN))             u_mideleg_sti (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mideleg_wr), .d_i(register_value_nxt_i[5]),     .q_o(mideleg_sti));
arv_dff #(.ARST_EN(ARST_EN))             u_mideleg_sei (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mideleg_wr), .d_i(register_value_nxt_i[9]),     .q_o(mideleg_sei));
arv_dff #(.WIDTH(16), .ARST_EN(ARST_EN)) u_mideleg_dpu (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mideleg_wr), .d_i(register_value_nxt_i[31:16]), .q_o(mideleg_dpu));

//
//  MIE (0x304 : Machine interrupt-enable register)
//
//                       - SSIE  1     Interrupt-enable bit for supervisor-level software interrupts.
//                       - MSIE  3     Interrupt-enable bit for machine-level software interrupts.
//                       - STIE  5     Interrupt-enable bit for supervisor-level timer interrupts.
//                       - MTIE  7     Interrupt-enable bit for machine-level timer interrupts.
//                       - SEIE  9     Interrupt-enable bit for supervisor-level external interrupts.
//                       - MEIE  11    Interrupt-enable bit for machine-level external interrupts.
//                       - MPIE  31:16 Interrupt-enable bit for machine-level interrupts designated for platform use.
//

arv_dff #(.ARST_EN(ARST_EN)) u_mie_msie (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mie_wr), .d_i(register_value_nxt_i[3]),  .q_o(mie_msie));
arv_dff #(.ARST_EN(ARST_EN)) u_mie_mtie (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mie_wr), .d_i(register_value_nxt_i[7]),  .q_o(mie_mtie));
arv_dff #(.ARST_EN(ARST_EN)) u_mie_meie (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mie_wr), .d_i(register_value_nxt_i[11]), .q_o(mie_meie));

//
//  MTVEC (0x305 : Machine trap-handler base address)
//
//                       - MODE  1:0   Vector mode (0: Direct -> all traps set pc to BASE / 1: Vectored -> asynchronous interrupts set pc to BASE+4×cause)
//                       - BASE  31:2  Vector base address.
//

arv_dff #(.WIDTH(2), .ARST_EN(ARST_EN)) u_mtvec_mode (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mtvec_wr),
                                                      .d_i ({1'b0, register_value_nxt_i[0]}),
                                                      .q_o (mtvec_mode));   // MODE >= 2 reserved

// CONTRACT: init_pc_i MUST be a single-cycle pulse. A level-held driver would clobber subsequent mtvec_wr writes every cycle the level is held.
wire        mtvec_base_en  = mtvec_wr | init_pc_i;
wire [29:0] mtvec_base_nxt = mtvec_wr ? register_value_nxt_i[31:2] : (reset_vector_i[31:2]+30'h00000002);   // reset_vector + 8
arv_dff #(.WIDTH(30), .ARST_EN(ARST_EN)) u_mtvec_base (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mtvec_base_en),
                                                       .d_i (mtvec_base_nxt),
                                                       .q_o (mtvec_base));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                      SUPERVISOR TRAP HANDLING REGISTERS                                              //////
//////                                                                                                                      //////
//////----------------------------------------------------------------------------------------------------------------------//////
//////                                                                                                                      //////
//////        Supervisor Trap Handling:                                                                                     //////
//////                                  + SSCRATCH : 0x140 : Supervisor scratch register                                    //////
//////                                  + SEPC     : 0x141 : Supervisor exception program counter                           //////
//////                                  + SCAUSE   : 0x142 : Supervisor trap cause                                          //////
//////                                  + STVAL    : 0x143 : Supervisor trap value                                          //////
//////                                  + SIP      : 0x144 : Supervisor interrupt pending                                   //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//
//  DECODER
//
assign       sscratch_sel   =  (register_sel_i['h0]  &  bank_strap_handling_i);  // 0x140
assign       sepc_sel       =  (register_sel_i['h1]  &  bank_strap_handling_i);  // 0x141
assign       scause_sel     =  (register_sel_i['h2]  &  bank_strap_handling_i);  // 0x142
assign       stval_sel      =  (register_sel_i['h3]  &  bank_strap_handling_i);  // 0x143
assign       sip_sel        =  (register_sel_i['h4]  &  bank_strap_handling_i);  // 0x144

assign       sscratch_wr    =  (sscratch_sel         & ~disable_write_i) & SU_MODE_EN;  // absent (illegal-instruction) when SU_MODE_EN=0
assign       sepc_wr        =  (sepc_sel             & ~disable_write_i) & SU_MODE_EN;  // absent (illegal-instruction) when SU_MODE_EN=0
assign       scause_wr      =  (scause_sel           & ~disable_write_i) & SU_MODE_EN;  // absent (illegal-instruction) when SU_MODE_EN=0
assign       stval_wr       =  (stval_sel            & ~disable_write_i) & SU_MODE_EN;  // absent (illegal-instruction) when SU_MODE_EN=0
assign       sip_wr         =  (sip_sel              & ~disable_write_i) & SU_MODE_EN;  // absent (illegal-instruction) when SU_MODE_EN=0

//
//  SSCRATCH (0x140 : Supervisor scratch register)
//
//                       - SSCRATCH 31:0  Typically, it is used to hold a pointer to the hart-local
//                                        supervisor context while the hart is executing user code.

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_sscratch_sscratch (
                         .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sscratch_wr),
                                                              .d_i (register_value_nxt_i[31:0]),
                                                              .q_o (sscratch_sscratch));

//
//  SEPC (0x141 : Supervisor exception program counter)
//
//                       - SEPC     31:0  When a trap is taken into S-mode, sepc is written with the
//                                        virtual address of the instruction that was interrupted or
//                                        that encountered the exception.
//                                        The low bit of sepc (sepc[0]) is always zero.

wire        sepc_sepc_en  = (trap_taken & trap_to_s) | sepc_wr;
wire [30:0] sepc_sepc_nxt = (trap_taken & trap_to_s) ? {mepc_save_value[31:2],      mepc_save_value[1]      & mepc_align_mask} :
                                                       {register_value_nxt_i[31:2], register_value_nxt_i[1] & mepc_align_mask};
arv_dff #(.WIDTH(31), .ARST_EN(ARST_EN)) u_sepc_sepc (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sepc_sepc_en),
                                                      .d_i (sepc_sepc_nxt),
                                                      .q_o (sepc_sepc));

//
//  SCAUSE (0x142 : Supervisor trap cause)
//
//  Cause codes: the S-visible subset of the mcause table below
//  (scause never reports the machine-only codes msi=3 / mti=7 / mei=11).

wire scause_irq_en  = (trap_taken & trap_to_s) | scause_wr;
wire scause_irq_nxt = (trap_taken & trap_to_s) ? trap_is_irq : register_value_nxt_i[31];
arv_dff #(.ARST_EN(ARST_EN)) u_scause_irq (
      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(scause_irq_en), .d_i(scause_irq_nxt), .q_o(scause_irq));

wire       scause_scause_en  = (trap_taken & trap_to_s) | scause_wr;
wire [4:0] scause_scause_nxt = (trap_taken & trap_to_s) ? trap_cause_latched : register_value_nxt_i[4:0];
arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_scause_scause (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(scause_scause_en), .d_i(scause_scause_nxt), .q_o(scause_scause));

//
//  STVAL (0x143 : Supervisor trap value)
//
//                       - STVAL    31:0  When a trap is taken into S-mode, stval is written with exception-specific
//                                        information to assist software in handling the trap.

wire        stval_stval_en  = (trap_taken & trap_to_s) | stval_wr;
wire [31:0] stval_stval_nxt = (trap_taken & trap_to_s) ? mtval_save_latched : register_value_nxt_i[31:0];
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_stval_stval (
                   .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(stval_stval_en), .d_i(stval_stval_nxt), .q_o(stval_stval));

//
//  SIP (0x144 : Supervisor interrupt pending)
//
//                       - SSIP  1     Interrupt-pending bit for supervisor-level software interrupts.
//                       - STIP  5     Interrupt-pending bit for supervisor-level timer interrupts.
//                       - SEIP  9     Interrupt-pending bit for supervisor-level external interrupts.
//                       - SPIP  31:16 Interrupt-pending bit for interrupts designated for platform use.
//
// Unlike MIP (where MSIP/MTIP/MEIP are read-only hardware wires), the SIP bits
// are software-writable. This asymmetry is intentional per the RISC-V privileged
// spec: M-mode firmware (e.g. OpenSBI) virtualizes interrupts for S-mode (e.g.
// Linux) by trapping real hardware interrupts and injecting virtual ones via
// these writable pending bits:
//   - SSIP: writable from both SIP (S-mode) and MIP (M-mode), for IPIs
//   - STIP: writable only via MIP (M-mode), for virtual timer interrupts
//   - SEIP: writable only via MIP (M-mode), OR'd with hardware signal
//

// SSIP: writable from M-mode unconditionally (MIP); writable from S-mode (SIP) only when delegated (mideleg_ssi=1).
// HW set: per ACLINT specification the SSWI device emits a one-cycle EDGE on irq_s_software_i.
wire irq_s_software_r_msk = irq_s_software_r & SU_MODE_EN;
wire mip_wr_msk           = mip_wr           & SU_MODE_EN;
wire sip_ssip_en  = irq_s_software_r_msk | mip_wr_msk | (sip_wr & mideleg_ssi);
wire sip_ssip_nxt = irq_s_software_r_msk ? 1'b1 :
                    mip_wr_msk           ? register_value_nxt_i[1] :
                                           register_value_nxt_i[1];
arv_dff #(.ARST_EN(ARST_EN)) u_sip_ssip (
    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sip_ssip_en), .d_i(sip_ssip_nxt), .q_o(sip_ssip));

// HW contribution is latched into sip_ssip directly -- no combinational OR needed.
wire sip_ssip_eff = sip_ssip;

// STIP: writable only from M-mode (MIP), read-only in SIP
arv_dff #(.ARST_EN(ARST_EN)) u_sip_stip (
    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mip_wr & SU_MODE_EN), .d_i(register_value_nxt_i[5]), .q_o(sip_stip));

// SEIP: software-writable portion (M-mode only via MIP, read-only in SIP).
// Read value is the logical-OR of the SW bit and the external interrupt
// controller signal, so either hardware or M-mode software can assert SEIP.
assign sip_seip_sw_o = sip_seip_sw;
arv_dff #(.ARST_EN(ARST_EN)) u_sip_seip_sw (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mip_wr & SU_MODE_EN), .d_i(mip_seip_sw_rmw_nxt_i), .q_o(sip_seip_sw));

assign sip_seip = sip_seip_sw | irq_s_external_r;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                         MACHINE TRAP HANDLING REGISTERS                                              //////
//////                                                                                                                      //////
//////----------------------------------------------------------------------------------------------------------------------//////
//////                                                                                                                      //////
//////        Machine Trap Handling:                                                                                        //////
//////                                  + MSCRATCH : 0x340 : Machine scratch register                                       //////
//////                                  + MEPC     : 0x341 : Machine exception program counter                              //////
//////                                  + MCAUSE   : 0x342 : Machine trap cause                                             //////
//////                                  + MTVAL    : 0x343 : Machine trap value                                             //////
//////                                  + MIP      : 0x344 : Machine interrupt pending                                      //////
//////                                  + MTINST   : 0x34A : Machine trap instruction (transformed)                         //////
//////                                  + MTVAL2   : 0x34B : Machine second trap value                                      //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//
//  DECODER
//
assign       mscratch_sel   =  (register_sel_i['h0]  &  bank_mtrap_handling_i);  // 0x340
assign       mepc_sel       =  (register_sel_i['h1]  &  bank_mtrap_handling_i);  // 0x341
assign       mcause_sel     =  (register_sel_i['h2]  &  bank_mtrap_handling_i);  // 0x342
assign       mtval_sel      =  (register_sel_i['h3]  &  bank_mtrap_handling_i);  // 0x343
assign       mip_sel        =  (register_sel_i['h4]  &  bank_mtrap_handling_i);  // 0x344
assign       mtinst_sel     =  (register_sel_i['hA]  &  bank_mtrap_handling_i);  // 0x34A
assign       mtval2_sel     =  (register_sel_i['hB]  &  bank_mtrap_handling_i);  // 0x34B

assign       mscratch_wr    =  (mscratch_sel         & ~disable_write_i);
assign       mepc_wr        =  (mepc_sel             & ~disable_write_i);
assign       mcause_wr      =  (mcause_sel           & ~disable_write_i);
assign       mtval_wr       =  (mtval_sel            & ~disable_write_i);
assign       mip_wr         =  (mip_sel              & ~disable_write_i);
//assign     mtinst_wr      =  (mtinst_sel           & ~disable_write_i);
assign       mtval2_wr      =  (mtval2_sel           & ~disable_write_i);   // storage in g_ssdbltrp (read-only zero when SU_MODE_EN=0)

//
//  MSCRATCH (0x340 : Machine scratch register)
//
//                       - MSCRATCH 31:0  Typically, it is used to hold a pointer to a machine-mode
//                                        hart-local context space and swapped with a user register
//                                        upon entry to an M-mode trap handler.
//

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mscratch_mscratch (
                         .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mscratch_wr),
                                                              .d_i (register_value_nxt_i[31:0]),
                                                              .q_o (mscratch_mscratch));

//
//  MEPC (0x341 : Machine exception program counter)
//
//                       - MEPC     31:0  When a trap is taken into M-mode, mepc is written with the
//                                        virtual address of the instruction that was interrupted or
//                                        that encountered the exception.
//                                        The low bit of mepc (mepc[0]) is always zero.

// When C extension is not supported (C_EXT_EN=0), IALIGN=32, so mepc[1:0] are always zero.
// When C extension is supported (C_EXT_EN=1), IALIGN=16, so only mepc[0] is always zero.
assign mepc_align_mask = C_EXT_EN ? 1'b1 : 1'b0;

// Kill override is only valid for IRQ/NMI traps (trap_stage==0). Sync EX
// exceptions (trap_stage[2]) already have stage-correct PCs latched in
// mepc_save_latched (via trap_pc_to_save) and must not be overridden. This
// expression feeds BOTH mepc_mepc and mnepc_mnepc_reg (NMI path).
// trap_pc_to_save cascade-order invariant (two constraints, both required):
//   (a) `(nmi_detect & ex_uop_jt_active_i) ? ex_pc_i` MUST stay ABOVE
//       `excp_detect_in_ex ? ex_pc_i` so an NMI during cm.jt saves the cm.jt PC
//       (the gate below blocks the kill override, mnepc inherits
//       mepc_save_latched = ex_pc_i).
//   (b) `excp_detect_in_ex` MUST stay ABOVE the generic
//       `nmi_detect ? id_pc_i`: an NMI preempting a
//       same-cycle-detected sync exception must save the faulting EX PC,
//       not the younger decode PC, for Smrnmi resumability after MNRET.
// trap_kill_restart: the trap lands on a MUL/DIV or UOP killed in EX -- xepc names
// that instruction so it re-executes after xRET (it was counted at dispatch, see
// minstret_undo_o). uop_held_abort: a push/pop that a kill-window IRQ/NMI was about to kill
// aborted on its own bus error instead; it restarts the same way, and the bus-error RNMI
// that follows (inside the handler) only reports the access.
wire   uop_held_abort;
wire   trap_kill_restart = (trap_kill_muldiv_o | trap_kill_uop_o | uop_held_abort) & ~trap_stage[2];
assign mepc_save_value   = trap_kill_restart ? ex_pc_i : mepc_save_latched;

wire        mepc_mepc_en  = m_trap_entry | mepc_wr;
wire [30:0] mepc_mepc_nxt = m_trap_entry ? {mepc_save_value[31:2],      mepc_save_value[1]      & mepc_align_mask} :
                                           {register_value_nxt_i[31:2], register_value_nxt_i[1] & mepc_align_mask};
arv_dff #(.WIDTH(31), .ARST_EN(ARST_EN)) u_mepc_mepc (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mepc_mepc_en), .d_i(mepc_mepc_nxt), .q_o(mepc_mepc));

//
//  MCAUSE (0x342 : Machine trap cause)
//
//                    Interrupt | Exception | Code Description
//                  ------------+-----------+----------------------------------------
//                        1     |     1     |   Supervisor software interrupt
//                        1     |     3     |   Machine software interrupt
//                        1     |     5     |   Supervisor timer interrupt
//                        1     |     7     |   Machine timer interrupt
//                        1     |     9     |   Supervisor external interrupt
//                        1     |    11     |   Machine external interrupt
//                        1     |    31-16  |   Designated for platform use
//                  ------------+-----------+----------------------------------------
//                        0     |     0     |   Instruction address misaligned
//                        0     |     1     |   Instruction access fault
//                        0     |     2     |   Illegal instruction
//                        0     |     3     |   Breakpoint
//                        0     |     4     |   Load address misaligned
//                        0     |     5     |   Load access fault
//                        0     |     6     |   Store/AMO address misaligned
//                        0     |     7     |   Store/AMO access fault
//                        0     |     8     |   Environment call from U-mode
//                        0     |     9     |   Environment call from S-mode
//                        0     |    11     |   Environment call from M-mode
//                        0     |    16     |   Double trap (Ssdbltrp; original cause in mtval2)

// Ssdbltrp: a double trap is delivered as a SYNCHRONOUS-style M trap even when the
// original event was an interrupt -- mcause.interrupt=0, code=16; the original cause
// code goes to mtval2 (g_ssdbltrp above).
wire mcause_irq_en  = m_trap_entry | mcause_wr;
wire mcause_irq_nxt = m_trap_entry ? (trap_is_irq & ~trap_is_dbl) : register_value_nxt_i[31];
arv_dff #(.ARST_EN(ARST_EN)) u_mcause_irq (
      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcause_irq_en), .d_i(mcause_irq_nxt), .q_o(mcause_irq));

wire       mcause_mcause_en  = m_trap_entry | mcause_wr;
wire [4:0] mcause_mcause_nxt = m_trap_entry ? (trap_is_dbl ? 5'd16 : trap_cause_latched) : register_value_nxt_i[4:0];
arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_mcause_mcause (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcause_mcause_en), .d_i(mcause_mcause_nxt), .q_o(mcause_mcause));

//
//  MTVAL (0x343 : Machine trap value)
//
//                       - MTVAL    31:0  When a trap is taken into M-mode, mtval is either set to zero
//                                        or written with exception-specific information to assist
//                                        software in handling the trap.

wire        mtval_mtval_en  = m_trap_entry | mtval_wr;
// Ssdbltrp (Priv 12.1.1.5): a double trap writes every register "except mcause and mtval2 ...
// with the same information that the unexpected trap would have written if it was taken into
// M-mode" -- so mtval carries the original trap's value, not zero. Only mcause (16) and mtval2
// (the original cause code) are special-cased.
wire [31:0] mtval_mtval_nxt = m_trap_entry ? mtval_save_latched : register_value_nxt_i[31:0];
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mtval_mtval (
                   .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mtval_mtval_en), .d_i(mtval_mtval_nxt), .q_o(mtval_mtval));

//
//  MIP (0x344 : Machine interrupt pending)
//
//                       - MSIP   3    Interrupt-pending bit for machine-level software interrupts.
//                       - MTIP   7    Interrupt-pending bit for machine-level timer interrupts.
//                       - MEIP  11    Interrupt-pending bit for machine-level external interrupts.
//                       - MPIP  31:16 Interrupt-pending bit for interrupts designated for platform use.
//
// MSIP/MTIP/MEIP are read-only - they directly reflect external hardware inputs.
// M-mode is the highest privilege level, so no higher-privilege software exists
// to virtualize interrupts for it (unlike SIP, where M-mode virtualizes for S-mode).
//
assign mip_msip = irq_m_software_r;
assign mip_mtip = irq_m_timer_r;
assign mip_meip = irq_m_external_r;

// Platform-specific pending bits: set by software write or external hardware input
// (for supervisor level writes, mask individual read/write accesses according to delegation)
// Deliberately latched, NOT pure level-sensitive (unlike MSIP/MTIP/MEIP above which directly assign irq_*_r).
// The asymmetry with MSIP/MTIP/MEIP is intentional - those wire to known level-sensitive sources (CLINT/PLIC)
// while the 16 platform IRQs are generic and must tolerate both source models.
wire [15:0] ip_pip_nxt = mip_wr ?  (register_value_nxt_i[31:16] | irq_platform_r)                                          :
                         sip_wr ? ((register_value_nxt_i[31:16] & mideleg_dpu) | (ip_pip & ~mideleg_dpu) | irq_platform_r) :
                                  (ip_pip | irq_platform_r);
arv_dff #(.WIDTH(16), .ARST_EN(ARST_EN)) u_ip_pip (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(ip_pip_nxt), .q_o(ip_pip));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       NMI TRAP HANDLING REGISTERS (SMRNMI)                                           //////
//////                                                                                                                      //////
//////----------------------------------------------------------------------------------------------------------------------//////
//////                                                                                                                      //////
//////        NMI Trap Handling:                                                                                            //////
//////                                  + MNSCRATCH : 0x740 : NMI scratch register                                          //////
//////                                  + MNEPC     : 0x741 : NMI exception program counter                                 //////
//////                                  + MNCAUSE   : 0x742 : NMI trap cause (read-only: 2=pin, 3=bus error, dbl-trap code)  //////
//////                                  + MNSTATUS  : 0x744 : NMI status register (NMIE + MNPP)                             //////
//////                                                                                                                      //////
//////  CSR bank 0x740-0x75F: bits[11:6] = 6'b011101                                                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//
//  DECODER
//
assign       mnscratch_sel  =  (register_sel_i['h0]  &  bank_nmi_handling_i);  // 0x740
assign       mnepc_sel      =  (register_sel_i['h1]  &  bank_nmi_handling_i);  // 0x741
assign       mncause_sel    =  (register_sel_i['h2]  &  bank_nmi_handling_i);  // 0x742 (read-only)
//           0x743 reserved
assign       mnstatus_sel   =  (register_sel_i['h4]  &  bank_nmi_handling_i);  // 0x744

// Write enables and storage declared locally
wire         mnscratch_wr   =  (mnscratch_sel & ~disable_write_i);
wire         mnepc_wr       =  (mnepc_sel     & ~disable_write_i);
//           mncause is read-only
wire         mnstatus_wr    =  (mnstatus_sel  & ~disable_write_i);

//
//  MNSCRATCH (0x740 : NMI scratch register)
//
wire  [31:0] mnscratch_mnscratch;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mnscratch_mnscratch (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mnscratch_wr), .d_i(register_value_nxt_i[31:0]), .q_o(mnscratch_mnscratch));

//
//  MNEPC (0x741 : NMI exception program counter)
//
wire [30:0] mnepc_mnepc_reg;
wire        mnepc_mnepc_reg_en  = rnmi_entry | mnepc_wr;
wire [30:0] mnepc_mnepc_reg_nxt = rnmi_entry ? {mepc_save_value[31:2],      mepc_save_value[1]      & mepc_align_mask} :
                                               {register_value_nxt_i[31:2], register_value_nxt_i[1] & mepc_align_mask} ;
arv_dff #(.WIDTH(31), .ARST_EN(ARST_EN)) u_mnepc_mnepc_reg (
                        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mnepc_mnepc_reg_en), .d_i(mnepc_mnepc_reg_nxt), .q_o(mnepc_mnepc_reg));

//
//  MNCAUSE (0x742 : NMI trap cause) -- WARL, read-only.
//
//  bit[31]=1 (interrupt): a true RNMI. Cause encoding follows SiFive (U74 Core Complex
//  Manual 21G3.02.00, Table 113):
//      2 = external RNMI input pin      3 = bus error
//
//  bit[31]=0 (exception): an Smdbltrp double trap diverted here, carrying the cause code
//  of the exception that precipitated it (Priv 8.3). An Ssdbltrp redirect (cause 16) never
//  arrives here: it starts below M, and MDT=1 implies M-mode.
//
// Source mux: the pin wins over a bus error, so a bus error pending alongside it reports 2
// and stays pending. The double-trap arm sits first -- it is not an NMI source at all, and
// nmi_src_pin holds whatever the last real RNMI was.
//
// nmi_src_pin is latched at nmi_detect, not sampled at trap_taken: the pin can deassert in
// the cycle between the two, which would report a pin NMI as a bus error.
wire        nmi_src_pin;
arv_dff #(.ARST_EN(ARST_EN)) u_nmi_src_pin (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(nmi_detect), .d_i(nmi_r), .q_o(nmi_src_pin));

wire [31:0] mncause_nxt = m_dbl_to_rnmi ? {27'h0000000, trap_cause_latched}                          :
                          nmi_src_pin   ? 32'h80000002                                              :
                                          32'h80000003                                              ;
arv_dff #(.WIDTH(32), .RST_VAL(32'h80000002), .ARST_EN(ARST_EN)) u_mncause (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(rnmi_entry),
                                                   .d_i (mncause_nxt), .q_o(mncause));

//
//  MNSTATUS (0x744 : NMI status register)
//
//                       - NMIE   3     NMI enable bit: cleared on NMI entry, set on mnret.
//                                      While NMIE=0, NMI is suppressed (allows handler to run without nesting).
//                       - MNPP  12:11  Previous privilege mode (saved on NMI entry, restored on mnret).
//
wire      mnstatus_nmie_reg;
wire      mnstatus_nmie_reg_en  = rnmi_entry | mnret_taken | mnstatus_wr;
wire      mnstatus_nmie_reg_nxt = rnmi_entry  ? 1'b0 :                                        // Cleared on NMI entry
                                  mnret_taken ? 1'b1 :                                        // Restored on mnret
                                               (mnstatus_nmie_reg | register_value_nxt_i[3]); // Smrnmi: NMIE is software-set-only; writing 0 has no effect

arv_dff #(.ARST_EN(ARST_EN)) u_mnstatus_nmie_reg (  // NMI disabled after reset (Smrnmi spec: NMIE resets to 0)
                .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mnstatus_nmie_reg_en),
                                                     .d_i (mnstatus_nmie_reg_nxt),
                                                     .q_o (mnstatus_nmie_reg));

wire [1:0] mnstatus_mnpp_reg;
wire       mnstatus_mnpp_reg_en  = rnmi_entry | mnret_taken | mnstatus_wr;
wire [1:0] mnstatus_mnpp_reg_nxt = m_dbl_to_rnmi              ? 2'b11               :  // "written to indicate M-mode"
                                   (trap_taken & trap_is_nmi) ? priv_mode_current_i :
                                    mnret_taken               ? 2'b11               :  // Reset MPP after use
                                                                (!SU_MODE_EN                           ? 2'b11               :
                                                                (register_value_nxt_i[12:11] == 2'b10) ? mnstatus_mnpp_reg   : // 2'b10 reserved
                                                                                                         register_value_nxt_i[12:11]);
arv_dff #(.WIDTH(2), .RST_VAL(2'b11), .ARST_EN(ARST_EN)) u_mnstatus_mnpp_reg (  // Reset: M-mode
                                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mnstatus_mnpp_reg_en),
                                                                                 .d_i (mnstatus_mnpp_reg_nxt),
                                                                                 .q_o (mnstatus_mnpp_reg));

// NMI CSR read assigns
assign mnscratch     = mnscratch_mnscratch;
assign mnepc_mnepc   = mnepc_mnepc_reg;
assign mnepc         = {mnepc_mnepc, 1'b0};
assign mnstatus_nmie = mnstatus_nmie_reg;
assign mnstatus_mnpp = mnstatus_mnpp_reg;
assign mnstatus      = {19'h00000, mnstatus_mnpp, 7'h00, mnstatus_nmie, 3'h0};


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                  SSDBLTRP: S-MODE DOUBLE TRAP (SDT / DTE / MTVAL2)                                   //////
//////                                                                                                                      //////
//////----------------------------------------------------------------------------------------------------------------------//////
//////                                                                                                                      //////
//////  Ssdbltrp (ratified): when a trap would be taken into S-mode while sstatus.SDT=1 (and menvcfg.DTE=1), it is          //////
//////  instead delivered to M-mode as a double trap: mcause=16 (interrupt bit 0), mtval2=original cause code, every     //////
//////  other register (mtval included) as the original trap would have written it.                                       //////
//////  The redirect decision lives in the excp/irq delegation routing (excp_dbl_trap / irq_dbl_trap) and is latched as     //////
//////  trap_is_dbl alongside trap_to_m/trap_to_s in the trap-entry FSM.                                                    //////
//////                                                                                                                      //////
//////        Architectural state:                                                                                          //////
//////                                  + SSTATUS.SDT  : mstatus/sstatus bit 24  : S-mode double-trap flag                  //////
//////                                  + MENVCFGH.DTE : 0x31A bit 27 (menvcfg[59]) : double-trap enable                    //////
//////                                  + MTVAL2       : 0x34B : machine second trap value (original cause code)            //////
//////                                                                                                                      //////
//////  The whole feature is bundled with SU_MODE_EN (S-mode absent => Ssdbltrp absent: SDT/DTE read 0, redirect terms      //////
//////  fold away, menvcfgh/mtval2 stay RAZ/WI through the known-bank posture).                                             //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

generate
    if (SU_MODE_EN) begin : g_ssdbltrp

        //
        //  MENVCFGH (0x31A : Upper 32 bits of menvcfg)
        //
        //                       - DTE   27    Double-trap enable (menvcfg bit 59). WARL, writable both ways.
        //                                     When DTE=0 the implementation behaves as though Ssdbltrp were
        //                                     absent: SDT reads 0 / SW writes ignored, and NO double-trap
        //                                     redirect (pure spec-literal horizontal delegation).
        //
        //  RESET VALUE 1'b1 -- deliberate aRVern choice: the spec leaves the menvcfg reset value
        //  UNSPECIFIED (and mstatus.MDT, the M-level analogue, resets to 1), so protection-by-default
        //  is picked: firmware that never touches menvcfgh gets the double-trap redirect.
        //  menvcfg (0x30A, low half) is RAZ/WI -- no implemented low-half field.
        //
        wire        menvcfgh_dte;
        arv_dff #(.RST_VAL(1'b1), .ARST_EN(ARST_EN)) u_menvcfgh_dte (
               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(menvcfgh_wr),
                                                    .d_i (register_value_nxt_i[27]),
                                                    .q_o (menvcfgh_dte));

        //
        //  SSTATUS.SDT (bit 24 of mstatus AND sstatus -- sstatus is architecturally a view of
        //  mstatus, so the bit is exposed on both read/write paths, like SPP/SPIE):
        //
        //  HW set  : any trap taken INTO S-mode -- exception or interrupt -- on the same cycle
        //            the sepc/scause/sstatus stack is written (trap_taken & trap_to_s).
        //  HW clear: SRET unconditionally; MRET / MNRET / dret only when the NEW privilege
        //            mode is U (Priv 3.1.6.2, Debug 4.8). A return into S keeps SDT so the
        //            interrupted S handler stays protected.
        //  SW write: register_value_nxt_i[24] on the sstatus_wr strobe (which already includes
        //            mstatus_wr), honoured only while DTE=1 -- with DTE=0 the extension behaves
        //            as absent (SDT reads 0, SW writes ignored).
        //  The HW set/clear terms deliberately stay live while DTE=0 (fewer gates): the spec
        //  leaves the underlying value across a DTE 0->1 transition UNSPECIFIED, so keeping
        //  the flop tracking is a free -- and the simplest -- choice.
        //
        wire        sstatus_sdt;
        wire        sstatus_sdt_set = trap_taken & trap_to_s;
        wire        sstatus_sdt_clr = sret_taken
                                    | (mret_taken          & (mstatus_mpp   == 2'b00))
                                    | (mnret_taken         & (mnstatus_mnpp == 2'b00))
                                    | (dbg_resume_redirect & (dbg_dcsr_prv  == 2'b00));
        wire        sstatus_sdt_en  = sstatus_sdt_set | sstatus_sdt_clr | (sstatus_wr & menvcfgh_dte);
        wire        sstatus_sdt_nxt = sstatus_sdt_set  ? 1'b1 :
                                      sstatus_sdt_clr  ? 1'b0 :
                                                         register_value_nxt_i[24];
        arv_dff #(.ARST_EN(ARST_EN)) u_sstatus_sdt (
               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sstatus_sdt_en),
                                                    .d_i (sstatus_sdt_nxt),
                                                    .q_o (sstatus_sdt));

        //
        //  MTVAL2 (0x34B : Machine second trap value) -- MRW, full MXLEN-bit read/write per spec
        //  (no WARL narrowing). HW-written only on a double-trap delivery with the original
        //  trap's cause: {27'h0, 5-bit cause code}.
        //
        //  ENCODING CHOICE (WARL reading of "the exception code of the original trap"): for a
        //  doubled INTERRUPT the stored value is the interrupt's cause CODE, zero-extended, with
        //  NO interrupt bit -- mcause=16 already identifies the event as a double trap, and
        //  trap_cause_latched (5 bits) holds the pre-double code for both flavours.
        //
        wire [31:0] mtval2_mtval2;
        wire        mtval2_hw_wr  = m_trap_entry & trap_is_dbl;
        wire        mtval2_en     = mtval2_hw_wr | mtval2_wr;
        wire [31:0] mtval2_nxt    = mtval2_hw_wr ? {27'h0000000, trap_cause_latched} :
                                                   register_value_nxt_i[31:0];
        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mtval2_mtval2 (
               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mtval2_en),
                                                    .d_i (mtval2_nxt),
                                                    .q_o (mtval2_mtval2));

        // Effective SDT: reads-as value of bit 24 (DTE-gated, registered view).
        assign sstatus_sdt_eff = sstatus_sdt & menvcfgh_dte;

        // Write-in-flight forwarding (ROUTING view only): a software CSR write to
        // sstatus/mstatus bit 24 or menvcfgh.DTE commits in EX on the same cycle the
        // NEXT program-order instruction's synchronous exception is classified in ID
        // (Zicsr: the write must be visible in program order). A sync exception cannot
        // be deferred the way csr_irq_config_wr defers IRQs, so the new value is
        // forwarded into the routing term. CSR reads keep the registered view
        // (back-to-back CSR ops are EX-serialized; no read window exists). The
        // sstatus forwarding gate mirrors u_sstatus_sdt's write enable (registered
        // DTE): a write ignored by the flop is equally ignored here.
        wire   menvcfgh_dte_route = menvcfgh_wr                 ? register_value_nxt_i[27] : menvcfgh_dte;
        wire   sstatus_sdt_route  = (sstatus_wr & menvcfgh_dte) ? register_value_nxt_i[24] : sstatus_sdt;
        assign sstatus_sdt_eff_route = sstatus_sdt_route & menvcfgh_dte_route;
        assign mtval2          = mtval2_mtval2;
        assign menvcfgh        = {4'b0000, menvcfgh_dte, 27'h0000000};

    end else begin : g_no_ssdbltrp

        // M-only build: Ssdbltrp absent. SDT/DTE tied 0 so every redirect/read term
        // folds away; menvcfgh and mtval2 read 0 (RAZ/WI known-bank posture).
        assign sstatus_sdt_eff       = 1'b0;
        assign sstatus_sdt_eff_route = 1'b0;
        assign mtval2          = 32'h00000000;
        assign menvcfgh        = 32'h00000000;

        // Lint cleanup
        wire   menvcfgh_wr_unused = menvcfgh_wr;
        wire   mtval2_wr_unused   = mtval2_wr;

    end
endgenerate


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                               CSR REGISTERS READ                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Construct register for Trap Setup Registers reads
// Bit 24 is Ssdbltrp SDT (visible in BOTH views, like SPP/SPIE); reads 0 whenever DTE=0.
assign mstatus        = {7'h00, sstatus_sdt_eff, 1'h0, mstatus_tsr, mstatus_tw, mstatus_tvm, mstatus_mxr, mstatus_sum, mstatus_mprv, 4'h0, mstatus_mpp, 2'h0, sstatus_spp, mstatus_mpie, 1'h0, sstatus_spie, 1'h0, mstatus_mie, 1'h0, sstatus_sie, 1'h0};
assign sstatus        = {7'h00, sstatus_sdt_eff, 1'h0, 1'h0,        1'h0,       1'h0,        mstatus_mxr, mstatus_sum, 1'h0,         4'h0, 2'h0,        2'h0, sstatus_spp, 1'h0,         1'h0, sstatus_spie, 1'h0, 1'h0,        1'h0, sstatus_sie, 1'h0};

assign mie            = {mie_mpie, 4'h0, mie_meie, 1'h0, sie_seie, 1'h0, mie_mtie, 1'h0, sie_stie, 1'h0, mie_msie, 1'h0, sie_ssie, 1'h0};
assign sie            = {sie_spie, 4'h0,   1'h0,   1'h0, sie_seie & mideleg_sei, 1'h0,   1'h0,   1'h0, sie_stie & mideleg_sti, 1'h0,   1'h0,   1'h0, sie_ssie & mideleg_ssi, 1'h0};

assign mtvec          = {mtvec_base, mtvec_mode};
assign stvec          = {stvec_base, stvec_mode};

assign medeleg        = {22'h000000, medeleg_ecas, medeleg_ecau, medeleg_staf, medeleg_stam, medeleg_ldaf, medeleg_ldam, medeleg_ebrk, medeleg_illi, medeleg_iacf, medeleg_iadm};
assign mideleg        = {mideleg_dpu, 4'h0, 1'b0, 1'b0, mideleg_sei, 1'b0, 1'b0, 1'b0, mideleg_sti, 1'b0, 1'b0, 1'b0, mideleg_ssi, 1'b0};

//
//  MSTATUSH.MDT (bit 10) -- Smdbltrp M-mode double-trap protection.
//  Resets to 1: protection by default, mirroring menvcfgh.DTE.
//  WARL, software-writable; every other bit reads 0.
//
// Hardware set/clear. NOT the mstatus_mprv_clr rule: MRET/SRET executed in M-mode clear MDT
// unconditionally, where MPRV clears only when the return drops below M. MNRET and dret clear
// only when the target is below M. An RNMI does not set MDT -- it carries its own mnstatus.
wire mdt_set = m_trap_entry;
wire mdt_clr = mret_taken
             | (sret_taken           & current_in_machine)
             | (mnret_taken          & (mnstatus_mnpp != 2'b11))
             | (dbg_resume_redirect  & (dbg_dcsr_prv  != 2'b11));

wire mstatush_mdt_en  = mdt_set | mdt_clr | mstatush_wr;
wire mstatush_mdt_nxt = mdt_set ? 1'b1 :
                        mdt_clr ? 1'b0 :
                                  register_value_nxt_i[10];

arv_dff #(.RST_VAL(1'b1), .ARST_EN(ARST_EN)) u_mstatush_mdt (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatush_mdt_en),
                                                   .d_i (mstatush_mdt_nxt),
                                                   .q_o (mstatush_mdt));

assign mstatush       = {21'h000000, mstatush_mdt, 10'h000};
assign medelegh       = 32'h00000000;

// Construct register for Trap Handling Registers reads
assign mscratch       = mscratch_mscratch;
assign sscratch       = sscratch_sscratch;

assign mepc           = {mepc_mepc, 1'b0};
assign sepc           = {sepc_sepc, 1'b0};

assign mcause         = {mcause_irq, 15'h0000, 8'h00, 3'h0, mcause_mcause};
assign scause         = {scause_irq, 15'h0000, 8'h00, 3'h0, scause_scause};

assign mtval          = mtval_mtval;
assign stval          = stval_stval;

assign mip            = {ip_pip,               4'h0, mip_meip, 1'h0, sip_seip,               1'h0, mip_mtip, 1'h0, sip_stip,               1'h0, mip_msip, 1'h0, sip_ssip_eff,               1'h0};
assign sip            = {ip_pip & mideleg_dpu, 4'h0,   1'h0,   1'h0, sip_seip & mideleg_sei, 1'h0, 1'h0,     1'h0, sip_stip & mideleg_sti, 1'h0, 1'h0,     1'h0, sip_ssip_eff & mideleg_ssi, 1'h0};

assign mtinst         = 32'h00000000;   // Optional: not implemented
                                        // mtval2 is implemented (Ssdbltrp) -- driven from the g_ssdbltrp generate above

//====================================================================================//
//  RNMI SOURCES -- external pin AND internal data-bus error                          //
//====================================================================================//
//
// nmi_i is a HELD LEVEL from the integrator. A data-bus error is a one-cycle PULSE, so it
// needs its own pending flop: nmi_suppress_post_mnret exists to stop a held level re-firing
// and does nothing for a pulse. Set on the error, cleared when the RNMI is taken.
//
// PRIORITY: the external pin wins. A bus error arriving in the same cycle simply stays
// pending and is taken after mnret -- it cannot be lost, because the flop holds it.
//
// While mnstatus.NMIE=0 (inside an RNMI handler) nmi_detect is masked, so the pending flop
// just holds; that IS the deferral. Combined with the first-fault-wins capture in
// arv_csr_top, a second bus error in that window sets marv_estat.overrun and is dropped --
// the CV32E40S rule.

wire        bus_error_pulse = wb_bus_error_load_i | wb_bus_error_store_i;
wire        wb_uop_bus_error = bus_error_pulse & wb_uop_sourced_i & wb_uop_seq_alive_i;
wire        wb_jt_load_error = wb_bus_error_load_i & wb_uop_jt_sourced_i;

// A bus error that aborts a Zcmt table jump, held until the RNMI it raises is taken. Needed
// only because jt_fault_exit clears ex_uop_jt_active_i a cycle before nmi_detect fires.
wire        jt_bus_abort;

// Cleared only by the BUS-ERROR RNMI (~nmi_src_pin, the source mncause reports). Clearing on ANY RNMI would let a pin NMI arriving in this window
// consume the flag, and the bus-error RNMI behind it would fall through to id_pc_i again.
wire        jt_bus_abort_set = wb_jt_load_error & ex_uop_jt_active_i;
wire        jt_bus_abort_clr = trap_taken & trap_is_nmi & ~nmi_src_pin;
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_jt_bus_abort (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(jt_bus_abort_set | jt_bus_abort_clr),
                                                   .d_i (jt_bus_abort_set), .q_o(jt_bus_abort));

wire        nmi_bus_pending;
wire        nmi_bus_taken   = trap_taken & trap_is_nmi & nmi_bus_pending & ~nmi_src_pin;
wire        nmi_bus_pend_en = bus_error_pulse | nmi_bus_taken;
arv_dff #(.ARST_EN(ARST_EN)) u_nmi_bus_pending (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(nmi_bus_pend_en),
                                                   .d_i (bus_error_pulse), .q_o(nmi_bus_pending));

// Both sources feed nmi_detect / wfi_wakeup / dcsr.nmip (declared with the NMI control wires above).
assign       nmi_any_source  = nmi_r | nmi_bus_pending;

// ~dbg_step_no_irq: dcsr.stepie=0 masks NMI (and IRQs) for the span of a single-step.
assign nmi_detect            = nmi_any_source & mnstatus_nmie & ~nmi_suppress_post_mnret & ~dbg_step_no_irq;


// Mux read data
assign traps_rdata_o  = ({32{mstatus_sel }}  & mstatus  ) |     // Machine Trap Setup
                        ({32{medeleg_sel }}  & medeleg  ) |
                        ({32{mideleg_sel }}  & mideleg  ) |
                        ({32{mie_sel     }}  & mie      ) |
                        ({32{mtvec_sel   }}  & mtvec    ) |
                        ({32{mstatush_sel}}  & mstatush ) |
                        ({32{medelegh_sel}}  & medelegh ) |
                        ({32{menvcfgh_sel}}  & menvcfgh ) |

                        ({32{sstatus_sel }}  & sstatus    ) |     // Supervisor Trap Setup
                        ({32{sie_sel     }}  & sie        ) |
                        ({32{stvec_sel   }}  & stvec      ) |
                        ({32{scounteren_sel}} & scounteren) |

                        ({32{mscratch_sel}}  & mscratch ) |     // Machine Trap Handling
                        ({32{mepc_sel    }}  & mepc     ) |
                        ({32{mcause_sel  }}  & mcause   ) |
                        ({32{mtval_sel   }}  & mtval    ) |
                        ({32{mip_sel     }}  & mip      ) |
                        ({32{mtinst_sel  }}  & mtinst   ) |
                        ({32{mtval2_sel  }}  & mtval2   ) |

                        ({32{sscratch_sel}}  & sscratch ) |     // Supervisor Trap Handling
                        ({32{sepc_sel    }}  & sepc     ) |
                        ({32{scause_sel  }}  & scause   ) |
                        ({32{stval_sel   }}  & stval    ) |
                        ({32{sip_sel     }}  & sip      ) |

                        ({32{mnscratch_sel}} & mnscratch) |   // NMI Trap Handling (Smrnmi)
                        ({32{mnepc_sel   }}  & mnepc    ) |
                        ({32{mncause_sel }}  & mncause  ) |
                        ({32{mnstatus_sel}}  & mnstatus ) ;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                               EXCEPTION HANDLING                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Decode current privilege mode
assign   current_in_machine    = (priv_mode_current_i==2'b11);
assign   current_in_supervisor = (priv_mode_current_i==2'b01);
assign   current_in_user       = (priv_mode_current_i==2'b00);

// Privilege-aware global interrupt enables (RISC-V spec 3.1.6.1):
//   - M-mode interrupts: always enabled when current_priv < M, gated by mstatus_mie when in M-mode
//   - S-mode interrupts: always enabled when current_priv < S (i.e. U-mode), gated by sstatus_sie when in S-mode
wire     m_irq_global_en       = ~current_in_machine |  mstatus_mie ;
wire     s_irq_global_en       =  current_in_user    | (sstatus_sie & current_in_supervisor);

// + Instruction Fetch Trap   --> Stop instruction Fetch, wait until ID, EX and WB are not busy
// + Instruction Decode Trap  --> Stop instruction Fetch+Decode, wait until EX and WB are not busy
// + Execute Trap             --> Stop instruction Fetch+Decode+Execute, wait until WB is not busy
// + WB Trap                  --> Stop all
// An older instruction still owns EX with an open outcome: a load/store whose fault status is
// unresolved, or a Zcmp/Zcmt sequence still issuing micro-ops. A younger fetch fault must not
// latch before it: the older fault could no longer be taken.
wire     ex_older_open         =  ex_ldst_unresolved_i | ~ex_uop_ready_i;
wire     id_inst_access_fault  =  id_excp_inst_access_fault_i & ~ex_older_open & ~ex_pmp_refetch_i;

assign   excp_detect_in_if     =  if_excp_inst_address_misaligned_i;
// The Sdtrig action=0 execute breakpoint is an ID-stage exception: include it so trap_stage[1]
// latches and the trap drains via pipeline_drained_for_id (same path as ebreak). Without this the
// trigger would set excp_vector_prio[0]/cause-3 but never latch a stage -> trap_drained=0 -> hang.
assign   excp_detect_in_id     = ((id_excp_ebreak_i & ~dbg_ebreak_enter) | id_excp_ecall_i | id_inst_access_fault | id_excp_illegal_inst_i |
                                  (trigger_exec_fire_i & ~trigger_exec_action_i));
assign   excp_detect_in_ex     = (ex_excp_store_address_misaligned_i | ex_excp_load_address_misaligned_i | ex_excp_illegal_inst_i | trigger_ls_break |
                                  ex_excp_store_access_fault_i       | ex_excp_load_access_fault_i);

// Sdtrig load/store action=0 breakpoint: an EX-stage breakpoint exception (cause 3,
// mtval=ex_data_addr) that rides the load/store-address-misalign path; it drives
// excp_detect_in_ex -> trap_stage[2] latches -> the trigger-only exception drains.
//
// The two fetch-side causes that bypass the trap_stall suppression -- bits 1/4 come from
// arv_fetch, not gated by decode's instruction_request (bits 5/6/2 are held off by decode's
// dispatch gating -- trap_stall_o and ex_excp_squash_o -- and need no gate) -- are gated with
// ~excp_detect_in_ex in excp_vector_prio ("older fault wins"); the younger fetch fault
// re-raises on re-fetch after the older trap's handler returns.
assign   trigger_ls_break      = trigger_ls_fire_i & ~trigger_ls_action_i;

// Sync LSU exception (misalign in EX, access-fault in WB) that aborts any in-flight
// Zcmp UOP sequence. Excludes illegal-inst because UOP-issued ops are synthesised
// and cannot be illegal. Consumed by arv_decode to clear the UOP control flops.
// trigger_ls_fire_i (action-AGNOSTIC, not trigger_ls_break) so BOTH a breakpoint (action=0)
// AND a Debug-Mode-entry (action=1) watchpoint that hits a Zcmp UOP micro-op store/load aborts
// the in-flight sequence. Debug entry does NOT drive trap_kill_uop_o (that path is IRQ/NMI only),
// and the access suppression alone would let the FSM read the suppressed micro-op as "done" and
// drip the remaining stores out while halted (a frozen-hart + watchpoint-semantics violation).
// Aborting clears the UOP flops in decode the same cycle; dpc/mepc = ex_pc = the CM.PUSH/POP
// macro-op PC, and Zcmp updates sp last, so the whole sequence restarts cleanly on resume/mret.
assign   ex_uop_excp_abort_o   = ex_excp_load_address_misaligned_i  |
                                 ex_excp_store_address_misaligned_i |
                                 ex_excp_load_access_fault_i        |   // PMP-denied micro-op access (incl. the Zcmt table read)
                                 ex_excp_store_access_fault_i       |
                                 wb_uop_bus_error                   |   // only the sequence's OWN access, never an older one
                                 trigger_ls_fire_i                  ;   // watchpoint (either action) may hit a Zcmp UOP micro-op address

// Stop commands
assign   if_stop_cmd_o         =  in_lockup;
assign   lockup_o              =  in_lockup;

//
// Order the vectors according to the priority order as specified
//
//----------+-----------+---------------------------------------------------------------------------------------------------------
// Priority |  Exc.Code |  Description
//----------+-----------+---------------------------------------------------------------------------------------------------------
// Highest  |         3 |  Instruction address breakpoint (from Debugger)
//          +-----------+---------------------------------------------------------------------------------------------------------
//          |         1 |  Instruction access fault
//          +-----------+---------------------------------------------------------------------------------------------------------
//          |         2 |  Illegal instruction
//          |         0 |  Instruction address misaligned
//          |    8,9,11 |  Environment call
//          |         3 |  Environment break
//          |         3 |  Load/store address breakpoint (from Debugger)
//          +-----------+---------------------------------------------------------------------------------------------------------
//          |       5,7 |  Load/store access fault
//          +-----------+---------------------------------------------------------------------------------------------------------
// Lowest   |       4,6 |  Load/store address misaligned
//----------+-----------+---------------------------------------------------------------------------------------------------------

// Exceptions ordered by priority (LSB: highest, MSB: lowest).
assign   excp_vector_prio    = { ex_excp_store_address_misaligned_i,                         // bit: 11      // EX - cause: 6
                                 ex_excp_load_address_misaligned_i,                          // bit: 10      // EX - cause: 4
                                 ex_excp_store_access_fault_i,                               // bit:  9      // EX - cause: 7
                                 ex_excp_load_access_fault_i,                                // bit:  8      // EX - cause: 5
                                 trigger_ls_break,                                           // bit:  7      // EX - cause: 3  (Sdtrig action=0 load/store-addr breakpoint)
                                 id_excp_ebreak_i,                                           // bit:  6      // ID - cause: 3
                                 id_excp_ecall_i,                                            // bit:  5      // ID - cause: 8, 9, 11
                                 if_excp_inst_address_misaligned_i
                                   & ~excp_detect_in_ex,                                     // bit:  4      // IF - cause: 0  (older EX excp wins)
                                 ex_excp_illegal_inst_i,                                     // bit:  3      // EX - cause: 2
                                 id_excp_illegal_inst_i,                                     // bit:  2      // ID - cause: 2
                                 id_inst_access_fault
                                   & ~excp_detect_in_ex,                                     // bit:  1      // ID - cause: 1  (older EX excp wins)
                                 (trigger_exec_fire_i & ~trigger_exec_action_i)              // bit:  0      // ID - cause: 3  (Sdtrig action=0 instr-addr breakpoint)
                               };

// Only keep the highest priority exception
assign   excp_vector_highest =   excp_vector_prio & ~(excp_vector_prio - 12'h001);

// Reordered by cause (1-hot signal)
assign   excp_vector_cause   = {(excp_vector_highest[5] & current_in_machine),                               // ID    - cause: 11
                                 1'b0,                                                                       //       - cause: 10
                                (excp_vector_highest[5] & current_in_supervisor),                            // ID    - cause:  9
                                (excp_vector_highest[5] & current_in_user),                                  // ID    - cause:  8
                                 excp_vector_highest[9],                                                     // WB    - cause:  7
                                 excp_vector_highest[11],                                                    // EX    - cause:  6
                                 excp_vector_highest[8] & ~ex_uop_jt_active_i,                               // (Zcmt table fetch -> cause 1)                                                     // WB    - cause:  5
                                 excp_vector_highest[10],                                                    // EX    - cause:  4
                                (excp_vector_highest[0] | excp_vector_highest[6] | excp_vector_highest[7]),  // ID    - cause:  3
                                 excp_vector_highest[2] | excp_vector_highest[3],                            // ID/EX - cause:  2
                                 excp_vector_highest[1] | (excp_vector_highest[8] & ex_uop_jt_active_i),                                                     // ID    - cause:  1
                                 excp_vector_highest[4]                                                      // IF    - cause:  0
                              };

// Compute cause number
assign   excp_cause          = ({4{excp_vector_cause[11]}} & 4'd11) |
                               ({4{excp_vector_cause[10]}} & 4'd10) |
                               ({4{excp_vector_cause[9] }} & 4'd9 ) |
                               ({4{excp_vector_cause[8] }} & 4'd8 ) |
                               ({4{excp_vector_cause[7] }} & 4'd7 ) |
                               ({4{excp_vector_cause[6] }} & 4'd6 ) |
                               ({4{excp_vector_cause[5] }} & 4'd5 ) |
                               ({4{excp_vector_cause[4] }} & 4'd4 ) |
                               ({4{excp_vector_cause[3] }} & 4'd3 ) |
                               ({4{excp_vector_cause[2] }} & 4'd2 ) |
                               ({4{excp_vector_cause[1] }} & 4'd1 ) |
                               ({4{excp_vector_cause[0] }} & 4'd0 ) ;

// Exceptions delegation configuration
assign   excp_vector_deleg   = { 1'b0,
                                 1'b0,
                                 medeleg_ecas,
                                 medeleg_ecau,
                                 medeleg_staf,
                                 medeleg_stam,
                                 medeleg_ldaf,
                                 medeleg_ldam,
                                 medeleg_ebrk,
                                 medeleg_illi,
                                 medeleg_iacf,
                                 medeleg_iadm
                               } & ~{12{excp_ignore_deleg}};

//  Manage delegation
//
//  +------------------------------------------------------------------------------------+
//  | Current Privilege              | Trap Cause | Delegation Bit | Taken In            |
//  |--------------------------------+------------+----------------+---------------------|
//  |  M                             | Exception  | (ignored)      |  M-mode             |
//  |  S                             | Exception  | MD=1           |  S-mode             |
//  |  S                             | Exception  | MD=0           |  M-mode             |
//  |  U                             | Exception  | MD=1           |  S-mode             |
//  |  U                             | Exception  | MD=0           |  M-mode             |
//  |--------------------------------+------------+----------------+---------------------|
//  |  M with MDT=1                  | Any trap   | (ignored)      |  M-mode double trap |
//  |  S/U with SDT=1 (and DTE=1)    | Any trap   | MD/MI=1        |  M-mode double trap |
//  +------------------------------------------------------------------------------------+

// Delegation is ignored when already in M-mode (spec-literal routing).
// Ssdbltrp (excp_dbl_trap / irq_dbl_trap): when a trap would be taken into S-mode
// while sstatus.SDT=1 (and menvcfgh.DTE=1), it is instead delivered to M-mode as a
// double trap with mcause=16. With DTE=0 the routing here is pure spec-literal
// horizontal delegation (no override of any kind).
assign   excp_ignore_deleg  = current_in_machine;



// Detect if exception goes in M or S mode.
// Ssdbltrp double-trap redirect: an exception whose delegation routing targets S-mode
// while SDT=1 & DTE=1 (sstatus_sdt_eff) is re-routed to M-mode as a double trap. The
// decision is made HERE -- the same point delegation routing is decided -- so the
// trap-entry FSM latches (trap_to_m/trap_to_s/trap_is_dbl) inherit it naturally.
assign   excp_detect          = |(excp_vector_prio);
assign   excp_detect_to_s_raw = |(excp_vector_cause &  excp_vector_deleg);
assign   excp_dbl_trap        =   excp_detect_to_s_raw &  sstatus_sdt_eff_route;   // routing view: forwards an in-flight SDT/DTE write
assign   excp_detect_to_s     =   excp_detect_to_s_raw & ~sstatus_sdt_eff_route;
assign   excp_detect_to_m     = |(excp_vector_cause & ~excp_vector_deleg) | excp_dbl_trap;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                               INTERRUPT HANDLING                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//
// Order the vectors according to the priority order as specified (RISC-V spec 3.1.9)
// All M-level interrupts have higher priority than all S-level interrupts
//
//----------+-----------+---------------------------------------------------------------------------------------------------------
// Priority |  Exc.Code |  Description
//----------+-----------+---------------------------------------------------------------------------------------------------------
// Highest  |        31 |
//          |        30 |  Designated for platform use
//          |       ... |
//          |        16 |
//          +-----------+---------------------------------------------------------------------------------------------------------
//          |        11 |  Machine external interrupt
//          +-----------+---------------------------------------------------------------------------------------------------------
//          |         3 |  Machine software interrupt
//          +-----------+---------------------------------------------------------------------------------------------------------
//          |         7 |  Machine timer interrupt
//          +-----------+---------------------------------------------------------------------------------------------------------
//          |         9 |  Supervisor external interrupt
//          +-----------+---------------------------------------------------------------------------------------------------------
//          |         1 |  Supervisor software interrupt
//          +-----------+---------------------------------------------------------------------------------------------------------
// Lowest   |         5 |  Supervisor timer interrupt
//----------+-----------+---------------------------------------------------------------------------------------------------------

// Interrupt Pendings, masked by enable bit and ordered by priority (LSB: highest, MSB: lowest)
//
// Global interrupt enable is privilege-aware (RISC-V spec 3.1.6.1):
//   - M-mode interrupts use m_irq_global_en (always enabled when priv < M)
//   - S-mode interrupts use s_irq_global_en (always enabled when priv < S)
//
// Delegation routing (RISC-V Priv. spec 3.1.6.1 / 3.1.8):
//   mideleg[i]=1 ==> cause i routes to S-mode (gated by s_irq_global_en)
//   mideleg[i]=0 ==> cause i routes to M-mode (gated by m_irq_global_en)
// The MTI/MSI/MEI causes are M-only (no mideleg bits in mideleg_wr at causes 3/7/11)
// so they always route to M unconditionally.
// The supervisor-class causes (SSI=1, STI=5, SEI=9) have BOTH M-route and S-route
// slots, mutually exclusive on mideleg_X (mirrors the platform IRQ block below).
//
// mie/sie aliasing: mie[1/5/9] (SSIE/STIE/SEIE) and sie[1/5/9] are a single
// shared register set (sie_ssie / sie_stie / sie_seie.
// Both the M-route and S-route slots for a given S-class cause must
// reference the SAME sie_Xie wire
//
// Priority is TWO-LEVEL: destined privilege mode first, cause order second.
// The bit positions below encode only the cause order (MEI>MSI>MTI>SEI>SSI>STI),
// which is defined for interrupts destined to the SAME mode. Ranking an
// S-destined cause against an M-destined one by that order alone is wrong --
// e.g. a delegated SSI (bit[28]) would outrank a non-delegated STI (bit[30])
// and let S-mode run with an enabled M-mode interrupt pending. So the M-route
// and S-route terms are kept in separate vectors and the M vector wins whole.
wire [31:0] irq_vector_prio_m = {  1'h0                                                             ,  // bit[31]
                                 ((sip_stip   & ~mideleg_sti    ) & sie_stie     & m_irq_global_en) ,  // bit[30] STI  (cause  5) - lowest standard
                                   1'h0                                                             ,  // bit[29]
                                 ((sip_ssip_eff & ~mideleg_ssi  ) & sie_ssie     & m_irq_global_en) ,  // bit[28] SSI  (cause  1)
                                   1'h0                                                             ,  // bit[27]
                                 ((sip_seip   & ~mideleg_sei    ) & sie_seie     & m_irq_global_en) ,  // bit[26] SEI  (cause  9)
                                   1'h0                                                             ,  // bit[25]
                                 ( mip_mtip                       & mie_mtie     & m_irq_global_en) ,  // bit[24] MTI  (cause  7) - mideleg has no bit for cause 7
                                   1'h0                                                             ,  // bit[23]
                                 ( mip_msip                       & mie_msie     & m_irq_global_en) ,  // bit[22] MSI  (cause  3) - mideleg has no bit for cause 3
                                   1'h0                                                             ,  // bit[21]
                                 ( mip_meip                       & mie_meie     & m_irq_global_en) ,  // bit[20] MEI  (cause 11) - highest standard
                                   4'h0                                                             ,
                                 ((ip_pip[0]  & ~mideleg_dpu[0] ) & mie_mpie[0]  & m_irq_global_en) ,
                                 ((ip_pip[1]  & ~mideleg_dpu[1] ) & mie_mpie[1]  & m_irq_global_en) ,
                                 ((ip_pip[2]  & ~mideleg_dpu[2] ) & mie_mpie[2]  & m_irq_global_en) ,
                                 ((ip_pip[3]  & ~mideleg_dpu[3] ) & mie_mpie[3]  & m_irq_global_en) ,
                                 ((ip_pip[4]  & ~mideleg_dpu[4] ) & mie_mpie[4]  & m_irq_global_en) ,
                                 ((ip_pip[5]  & ~mideleg_dpu[5] ) & mie_mpie[5]  & m_irq_global_en) ,
                                 ((ip_pip[6]  & ~mideleg_dpu[6] ) & mie_mpie[6]  & m_irq_global_en) ,
                                 ((ip_pip[7]  & ~mideleg_dpu[7] ) & mie_mpie[7]  & m_irq_global_en) ,
                                 ((ip_pip[8]  & ~mideleg_dpu[8] ) & mie_mpie[8]  & m_irq_global_en) ,
                                 ((ip_pip[9]  & ~mideleg_dpu[9] ) & mie_mpie[9]  & m_irq_global_en) ,
                                 ((ip_pip[10] & ~mideleg_dpu[10]) & mie_mpie[10] & m_irq_global_en) ,
                                 ((ip_pip[11] & ~mideleg_dpu[11]) & mie_mpie[11] & m_irq_global_en) ,
                                 ((ip_pip[12] & ~mideleg_dpu[12]) & mie_mpie[12] & m_irq_global_en) ,
                                 ((ip_pip[13] & ~mideleg_dpu[13]) & mie_mpie[13] & m_irq_global_en) ,
                                 ((ip_pip[14] & ~mideleg_dpu[14]) & mie_mpie[14] & m_irq_global_en) ,
                                 ((ip_pip[15] & ~mideleg_dpu[15]) & mie_mpie[15] & m_irq_global_en)
                                };

wire [31:0] irq_vector_prio_s = {  1'h0                                                             ,  // bit[31]
                                 ((sip_stip   &  mideleg_sti    ) & sie_stie     & s_irq_global_en) ,  // bit[30] STI  (cause  5) - lowest standard
                                   1'h0                                                             ,  // bit[29]
                                 ((sip_ssip_eff &  mideleg_ssi  ) & sie_ssie     & s_irq_global_en) ,  // bit[28] SSI  (cause  1)
                                   1'h0                                                             ,  // bit[27]
                                 ((sip_seip   &  mideleg_sei    ) & sie_seie     & s_irq_global_en) ,  // bit[26] SEI  (cause  9)
                                   1'h0                                                             ,  // bit[25]
                                   1'h0                                                             ,  // bit[24] MTI  - M-only, never delegated
                                   1'h0                                                             ,  // bit[23]
                                   1'h0                                                             ,  // bit[22] MSI  - M-only, never delegated
                                   1'h0                                                             ,  // bit[21]
                                   1'h0                                                             ,  // bit[20] MEI  - M-only, never delegated
                                   4'h0                                                             ,
                                 ((ip_pip[0]  &  mideleg_dpu[0] ) & sie_spie[0]  & s_irq_global_en) ,
                                 ((ip_pip[1]  &  mideleg_dpu[1] ) & sie_spie[1]  & s_irq_global_en) ,
                                 ((ip_pip[2]  &  mideleg_dpu[2] ) & sie_spie[2]  & s_irq_global_en) ,
                                 ((ip_pip[3]  &  mideleg_dpu[3] ) & sie_spie[3]  & s_irq_global_en) ,
                                 ((ip_pip[4]  &  mideleg_dpu[4] ) & sie_spie[4]  & s_irq_global_en) ,
                                 ((ip_pip[5]  &  mideleg_dpu[5] ) & sie_spie[5]  & s_irq_global_en) ,
                                 ((ip_pip[6]  &  mideleg_dpu[6] ) & sie_spie[6]  & s_irq_global_en) ,
                                 ((ip_pip[7]  &  mideleg_dpu[7] ) & sie_spie[7]  & s_irq_global_en) ,
                                 ((ip_pip[8]  &  mideleg_dpu[8] ) & sie_spie[8]  & s_irq_global_en) ,
                                 ((ip_pip[9]  &  mideleg_dpu[9] ) & sie_spie[9]  & s_irq_global_en) ,
                                 ((ip_pip[10] &  mideleg_dpu[10]) & sie_spie[10] & s_irq_global_en) ,
                                 ((ip_pip[11] &  mideleg_dpu[11]) & sie_spie[11] & s_irq_global_en) ,
                                 ((ip_pip[12] &  mideleg_dpu[12]) & sie_spie[12] & s_irq_global_en) ,
                                 ((ip_pip[13] &  mideleg_dpu[13]) & sie_spie[13] & s_irq_global_en) ,
                                 ((ip_pip[14] &  mideleg_dpu[14]) & sie_spie[14] & s_irq_global_en) ,
                                 ((ip_pip[15] &  mideleg_dpu[15]) & sie_spie[15] & s_irq_global_en)
                                };

// Destined-privilege level: any M-destined interrupt masks every S-destined one.
// In M-mode s_irq_global_en is already 0, so irq_vector_prio_s is all-zero there
// and this mux is a no-op.
assign   irq_vector_prio    = (|irq_vector_prio_m) ? irq_vector_prio_m : irq_vector_prio_s;

// Only keep the highest priority exception
assign   irq_vector_highest =     irq_vector_prio & ~(irq_vector_prio - 32'h00000001);

// Reordered by cause (1-hot signal)
// Maps from priority-ordered bit positions back to cause-code-indexed positions.
// Standard interrupts are priority-ordered per spec (MEI>MSI>MTI>SEI>SSI>STI),
// so the mapping is not a simple bit-reversal for causes 1,3,5,9.
assign   irq_vector_cause   =    {irq_vector_highest[0],          // cause[31] platform
                                  irq_vector_highest[1],          // cause[30] platform
                                  irq_vector_highest[2],          // cause[29] platform
                                  irq_vector_highest[3],          // cause[28] platform
                                  irq_vector_highest[4],          // cause[27] platform
                                  irq_vector_highest[5],          // cause[26] platform
                                  irq_vector_highest[6],          // cause[25] platform
                                  irq_vector_highest[7],          // cause[24] platform
                                  irq_vector_highest[8],          // cause[23] platform
                                  irq_vector_highest[9],          // cause[22] platform
                                  irq_vector_highest[10],         // cause[21] platform
                                  irq_vector_highest[11],         // cause[20] platform
                                  irq_vector_highest[12],         // cause[19] platform
                                  irq_vector_highest[13],         // cause[18] platform
                                  irq_vector_highest[14],         // cause[17] platform
                                  irq_vector_highest[15],         // cause[16] platform
                                  irq_vector_highest[16],         // cause[15] (unused)
                                  irq_vector_highest[17],         // cause[14] (unused)
                                  irq_vector_highest[18],         // cause[13] (unused)
                                  irq_vector_highest[19],         // cause[12] (unused)
                                  irq_vector_highest[20],         // cause[11] MEI  (prio bit[20])
                                  irq_vector_highest[21],         // cause[10] (unused)
                                  irq_vector_highest[26],         // cause[9]  SEI  (prio bit[26])
                                  irq_vector_highest[23],         // cause[8]  (unused)
                                  irq_vector_highest[24],         // cause[7]  MTI  (prio bit[24])
                                  irq_vector_highest[25],         // cause[6]  (unused)
                                  irq_vector_highest[30],         // cause[5]  STI  (prio bit[30])
                                  irq_vector_highest[27],         // cause[4]  (unused)
                                  irq_vector_highest[22],         // cause[3]  MSI  (prio bit[22])
                                  irq_vector_highest[29],         // cause[2]  (unused)
                                  irq_vector_highest[28],         // cause[1]  SSI  (prio bit[28])
                                  irq_vector_highest[31]          // cause[0]  (unused)
                                 };

// Compute cause
assign   irq_cause          = ({5{irq_vector_cause[31]}} & 5'd31) |
                              ({5{irq_vector_cause[30]}} & 5'd30) |
                              ({5{irq_vector_cause[29]}} & 5'd29) |
                              ({5{irq_vector_cause[28]}} & 5'd28) |
                              ({5{irq_vector_cause[27]}} & 5'd27) |
                              ({5{irq_vector_cause[26]}} & 5'd26) |
                              ({5{irq_vector_cause[25]}} & 5'd25) |
                              ({5{irq_vector_cause[24]}} & 5'd24) |
                              ({5{irq_vector_cause[23]}} & 5'd23) |
                              ({5{irq_vector_cause[22]}} & 5'd22) |
                              ({5{irq_vector_cause[21]}} & 5'd21) |
                              ({5{irq_vector_cause[20]}} & 5'd20) |
                              ({5{irq_vector_cause[19]}} & 5'd19) |
                              ({5{irq_vector_cause[18]}} & 5'd18) |
                              ({5{irq_vector_cause[17]}} & 5'd17) |
                              ({5{irq_vector_cause[16]}} & 5'd16) |
                            //({5{irq_vector_cause[15]}} & 5'd15) |
                            //({5{irq_vector_cause[14]}} & 5'd14) |
                            //({5{irq_vector_cause[13]}} & 5'd13) |
                            //({5{irq_vector_cause[12]}} & 5'd12) |
                              ({5{irq_vector_cause[11]}} & 5'd11) |
                            //({5{irq_vector_cause[10]}} & 5'd10) |
                              ({5{irq_vector_cause[9] }} & 5'd9 ) |
                            //({5{irq_vector_cause[8] }} & 5'd8 ) |
                              ({5{irq_vector_cause[7] }} & 5'd7 ) |
                            //({5{irq_vector_cause[6] }} & 5'd6 ) |
                              ({5{irq_vector_cause[5] }} & 5'd5 ) |
                            //({5{irq_vector_cause[4] }} & 5'd4 ) |
                              ({5{irq_vector_cause[3] }} & 5'd3 ) |
                            //({5{irq_vector_cause[2] }} & 5'd2 ) |
                              ({5{irq_vector_cause[1] }} & 5'd1 ) ;
                            //({5{irq_vector_cause[0] }} & 5'd0 ) ;

// IRQ delegation configuration
assign   irq_vector_deleg   = (mideleg & ~{32{irq_ignore_deleg}});

//  Manage delegation
//
//  Same delegation matrix as the exception table above, with mideleg (MI) substituted for
//  medeleg (MD).  M-mode never delegates; there is no S-already-in-trap lockup row for IRQs.

// Delegation is ignored when already in M-mode.
assign   irq_ignore_deleg  =  current_in_machine;

// Suppress IRQ detection when a CSR write to any interrupt-config register
// (mstatus, sstatus, mie, sie, mip, sip) is in progress. The CSR write
// updates the enable / pending registers on the next clock edge, but
// irq_vector_cause is combinational and still sees the old values -
// without this guard, an IRQ can slip through on the same cycle that
// software disables/clears it (e.g. csrw mip,0 phantom-firing the pending
// IRQ it was meant to clear).
//
// This OR-mask must include EVERY CSR write that can change a term in the
// irq_vector_cause / irq_vector_prio expressions.
wire     csr_irq_config_wr  = mstatus_wr | sstatus_wr | mie_wr | sie_wr | mip_wr | sip_wr | mideleg_wr | medeleg_wr | menvcfgh_wr    // menvcfgh: DTE feeds the IRQ double-trap routing
                            | mstatush_wr;                                                                                           // mstatush: MDT write clears MIE

// Post-MRET IRQ suppression: suppress IRQ detection after MRET until
// the first valid instruction arrives in ID. This guarantees the MEPC
// instruction enters EX before a new IRQ can fire, preventing livelock
// where aggressive IRQs catch the same instruction in ID after every MRET
// (pipeline drain sees EX as ready, traps immediately, MEPC unchanged).
// Gated by marv_ctl_i[2] (livelock protection enable).
// Must also require pipeline_drained_for_id (EX+WB ready) so the instruction actually
// dispatches the same cycle suppress clears; a valid-but-stalled instruction would let
// the IRQ re-fire at the same id_pc_i next cycle (instruction not consumed) - livelock.
// Also gate on ~ex_uop_jt_active_i: cm.jt/cm.jalt has a non-killable AHB phase (JT_DPH/JT_ALU)
// where MEPC is saved as ex_pc_i (the cm.jt PC).
// MNRET must arm post-trap IRQ suppression the same way MRET does. Without
// the mnret_taken term, an IRQ pending at MNRET completion traps
// on the exact PC the mnret resumed to - same livelock vector as the MRET
wire     irq_suppress_post_mret;
wire     irq_suppress_clr  = irq_suppress_post_mret & id_instruction_valid_i & pipeline_drained_for_id & ~trap_branch_detect_r & ~ex_uop_jt_active_i & ~id_uop_jt_start_i;
wire     irq_suppress_post_mret_en  = ((mret_taken |  mnret_taken) & marv_ctl_i[2]) | irq_suppress_clr;
wire     irq_suppress_post_mret_nxt = ((mret_taken |  mnret_taken) & marv_ctl_i[2]) ? 1'b1 : 1'b0;

arv_dff #(.ARST_EN(ARST_EN)) u_irq_suppress_post_mret (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(irq_suppress_post_mret_en),
                                                       .d_i (irq_suppress_post_mret_nxt),
                                                       .q_o (irq_suppress_post_mret));

// NMI livelock protection: after mnret, suppress nmi_detect for one valid instruction.
// Without this, if nmi_i stays asserted, mnret immediately re-enables NMIE and the NMI
// handler is re-entered before executing a single instruction. Gated by marv_ctl_i[2].
wire nmi_suppress_post_mnret_reg;
wire nmi_suppress_clr = nmi_suppress_post_mnret_reg & id_instruction_valid_i & ~trap_branch_detect_r;
wire nmi_suppress_post_mnret_reg_en  = (mnret_taken & marv_ctl_i[2]) | nmi_suppress_clr;
wire nmi_suppress_post_mnret_reg_nxt = (mnret_taken & marv_ctl_i[2]) ? 1'b1 : 1'b0;
arv_dff #(.ARST_EN(ARST_EN)) u_nmi_suppress_post_mnret_reg (
                        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(nmi_suppress_post_mnret_reg_en),
                                                             .d_i (nmi_suppress_post_mnret_reg_nxt),
                                                             .q_o (nmi_suppress_post_mnret_reg));
assign nmi_suppress_post_mnret = nmi_suppress_post_mnret_reg;

// Detect if exception goes in M or S mode
// ~dbg_step_no_irq: dcsr.stepie=0 masks maskable IRQs for the span of a single-step.
// Synchronous exceptions on the stepped instruction are intentionally NOT affected.
//
// mnstatus_nmie: Smrnmi -- "When NMIE=0, all interrupts are disabled" (inside the
// RNMI handler, and out of reset since NMIE resets to 0). wfi_wakeup_o is deliberately
// NOT gated by NMIE: waking without taking the IRQ is spec-legal and avoids a
// sleep-forever hazard on WFI inside the RNMI handler; the level-held IRQ is taken
// after mnret.
assign   irq_detect        = |(irq_vector_cause) & ~csr_irq_config_wr & ~irq_suppress_post_mret & ~dbg_step_no_irq
                                                 &  mnstatus_nmie;
// Ssdbltrp double-trap redirect for INTERRUPTS: same mechanism as the exception pair
// above -- an interrupt whose delegation routing targets S-mode while SDT=1 & DTE=1 is
// re-routed to M-mode as a double trap (mcause=16, interrupt bit 0, code in mtval2).
assign   irq_detect_to_s_raw = |(irq_vector_cause &  irq_vector_deleg);
assign   irq_dbl_trap        =   irq_detect_to_s_raw &  sstatus_sdt_eff_route;   // routing view (IRQ side is additionally deferred by csr_irq_config_wr)
assign   irq_detect_to_s     =   irq_detect_to_s_raw & ~sstatus_sdt_eff_route;
assign   irq_detect_to_m     = |(irq_vector_cause & ~irq_vector_deleg) | irq_dbl_trap;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                            TRAP ENTRY STATE MACHINE                                                  //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//------------------------------------------------------------------------
// MRET / SRET / MNRET detection
//------------------------------------------------------------------------
assign   mret_taken        =  id_opcode_mret_i   & ~trap_pending;
assign   sret_taken        =  id_opcode_sret_i   & ~trap_pending  & SU_MODE_EN;
assign   mnret_taken       =  id_opcode_mnret_i  & ~trap_pending;

//------------------------------------------------------------------------
// Exception/interrupt/NMI type classification (latched when trap_pending first asserts)
// Priority: NMI > synchronous-exception > IRQ
//   - NMI is non-maskable, highest priority
//   - A sync exception belongs to the instruction in flight and wins over a same-cycle
//     IRQ (see trap_is_irq formula: `irq_detect & ~excp_detect & ~nmi_detect`)
//   - IRQ wins only when no sync exception is pending this cycle
//------------------------------------------------------------------------
// Guard against simultaneous IRQ and MRET/SRET/MNRET: if a ret instruction is
// dispatching this cycle, do NOT set trap_pending. The ret's own branch fires
// (trap_branch_detect_r goes high next cycle, suppressing the next-cycle stall),
// and irq_suppress_post_mret is set next cycle so the IRQ re-fires safely after
// the first post-ret instruction. Without this guard, an IRQ detected on the same
// cycle as MRET would set trap_pending while mret_taken also fires, corrupting
// MSTATUS and preventing the MRET return from completing.

// Async sources wait while an EX load/store still has an unresolved fault status: once it
// resolves, a fault and the interrupt are detected in the same cycle and the exception wins
// below (precise ordering; the interrupt stays level-pending).
// A Zcmp/Zcmt sequence in flight is entered only where it can be killed (push/pop with a
// load/store still ahead, kill enabled): the sequencer then issues nothing more, drains its
// data phase and restarts from scratch after the handler. Anywhere else (last load/store,
// sp update, ret, cm.mv*, cm.jt/jalt, kill disabled or livelock-suppressed) the source waits
// for the sequence to complete, so a later micro-op fault is never shadowed by a pending trap.
assign uop_async_ok        = ex_uop_ready_i |
                             (ex_uop_kill_window_i & ((marv_ctl_i[1] & irq_detect) | nmi_detect) &
                              ~(uop_kill_suppress & marv_ctl_i[2]));
wire async_detect          = (irq_detect | nmi_detect) & ~ex_ldst_unresolved_i & uop_async_ok;
wire trap_pending_set      = (excp_detect | async_detect)               &    // a trap source is firing this cycle
                              ~trap_pending                           &    // no trap already pending
                              ~trap_branch_detect_r                     &    // not the cycle of an outgoing trap-branch redirect
                              ~mret_taken & ~sret_taken & ~mnret_taken  &    // not concurrent with an xRET (preserves MSTATUS/MIE handoff)
                              ~dbg_halt_active;                              // no traps while halted in OR entering Debug Mode (frozen hart)

// The kill-window IRQ/NMI is either already holding the sequence, or latched in the very
// cycle its own data phase errors: in both cases the sequence aborts instead of being killed.
wire uop_held_abort_set    = wb_uop_bus_error & (trap_kill_uop_hold_o | (trap_pending_set & ~excp_detect & ~ex_uop_ready_i));
wire uop_held_abort_en     = uop_held_abort_set | trap_taken;
arv_dff #(.ARST_EN(ARST_EN)) u_uop_held_abort (
               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(uop_held_abort_en),
                                                    .d_i (uop_held_abort_set),
                                                    .q_o (uop_held_abort));

arv_dff #(.ARST_EN(ARST_EN)) u_trap_is_irq (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_set),
                                            .d_i (irq_detect & ~excp_detect & ~nmi_detect),
                                            .q_o (trap_is_irq));

arv_dff #(.ARST_EN(ARST_EN)) u_trap_is_nmi (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_set),
                                            .d_i (nmi_detect),
                                            .q_o (trap_is_nmi));

wire trap_to_m_nxt = nmi_detect                  ? 1'b1            :   // NMI always M-mode
                     (irq_detect & ~excp_detect) ? irq_detect_to_m :
                                                   excp_detect_to_m;
arv_dff #(.ARST_EN(ARST_EN)) u_trap_to_m (
     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_set),
                                          .d_i (trap_to_m_nxt),
                                          .q_o (trap_to_m));

wire trap_to_s_nxt = nmi_detect                  ? 1'b0            :   // NMI never S-mode
                     (irq_detect & ~excp_detect) ? irq_detect_to_s :
                                                   excp_detect_to_s;
arv_dff #(.ARST_EN(ARST_EN)) u_trap_to_s (
     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_set),
                                          .d_i (trap_to_s_nxt),
                                          .q_o (trap_to_s));

// Ssdbltrp: latched alongside trap_to_m/trap_to_s (same enable, same arm order) so the
// double-trap decision travels with the delegation route it was derived from, keeping
// {trap_to_m, trap_is_dbl, trap_cause_latched} coherent. NMIs never target S-mode, so an
// NMI is never a double trap.
wire trap_is_dbl_nxt = nmi_detect                  ? 1'b0          :  // NMI never doubles
                       (irq_detect & ~excp_detect) ? irq_dbl_trap  :
                                                     excp_dbl_trap ;
arv_dff #(.ARST_EN(ARST_EN)) u_trap_is_dbl (
     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_set),
                                          .d_i (trap_is_dbl_nxt),
                                          .q_o (trap_is_dbl));

wire [4:0] trap_cause_latched_nxt = nmi_detect                  ? 5'h0             :   // RNMI: mncause is composed separately (u_mncause)
                                    (irq_detect & ~excp_detect) ? irq_cause        :
                                                                  {1'b0, excp_cause};
arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_trap_cause_latched (
                         .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_set),
                                                              .d_i (trap_cause_latched_nxt),
                                                              .q_o (trap_cause_latched));

//------------------------------------------------------------------------
// MEPC save value: PC of faulting instruction based on trap stage (latched)
// For IRQs during UOP branches: pipeline_drained_for_uop ensures we wait
// until the branch target instruction arrives in ID, so id_pc_i is correct.
// The mepc is re-latched from id_pc_i when the UOP drain completes.
//
// The re-settle applies to IRQs and to PURE NMIs -- an NMI coinciding with a UOP
// return branch or a killed MUL/DIV would otherwise latch the stale pre-branch
// id_pc_i into mnepc. The ~|trap_stage guard is essential: trap_is_nmi (unlike
// trap_is_irq, whose latch term carries ~excp_detect) can be latched alongside a
// sync exception, where mepc_save_latched already holds the faulting EX/WB PC
// (invariant (b) above) and a lingering muldiv_kill_suppress must not overwrite
// it. trap_stage is 3'b000 for a pure NMI.
//------------------------------------------------------------------------
// The branch target has reached ID: as an instruction, or as a fetch fault that parks its PC.
assign      id_pc_settled        =  id_instruction_valid_i | id_excp_inst_access_fault_i;
wire        async_mepc_resettle  =  trap_is_irq | (trap_is_nmi & ~|trap_stage);
wire        irq_mepc_settle      =  trap_pending & async_mepc_resettle & uop_wait_for_id_valid  & id_pc_settled;
wire        muldiv_mepc_settle   =  trap_pending & async_mepc_resettle & muldiv_kill_suppress   & id_instruction_valid_i;
wire [31:0] trap_pc_to_save      =  (id_wfi_active_i & nmi_detect)    ?   ex_pc_i + 32'd4 : // NMI+WFI: save WFI+4
                                    (nmi_detect & jt_bus_abort & ~nmi_r) ? wb_pc_i        : // BUS ERROR aborting cm.jt: name the cm.jt ITSELF. ~nmi_r so a
                                    (nmi_detect & ex_uop_jt_active_i) ?   ex_pc_i         : // PIN NMI during cm.jt: save the cm.jt PC.
                                     excp_detect_in_ex                ?   ex_pc_i         : // sync excp in EX: faulting PC (NMI/IRQ resumable)
                                     excp_detect_in_if                ?   ex_pc_i         : // sync excp in IF (inst-addr-misalign).
                                     nmi_detect                       ?   id_pc_i         : // NMI (no in-flight sync excp): save ID PC.
                                    (id_wfi_active_i & irq_detect)    ?   ex_pc_i + 32'd4 : // IRQ+WFI: save WFI+4
                                    (irq_detect & ex_uop_jt_active_i) ?   ex_pc_i         : // IRQ+JT : save cm.jt PC
                                                                          id_pc_i         ; // IRQ    : save ID PC
wire        mepc_save_latched_en  = irq_mepc_settle | muldiv_mepc_settle | trap_pending_set;
wire [31:0] mepc_save_latched_nxt = irq_mepc_settle    ? id_pc_i :
                                    muldiv_mepc_settle ? id_pc_i :
                                                         trap_pc_to_save;

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mepc_save_latched (
                         .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mepc_save_latched_en),
                                                              .d_i (mepc_save_latched_nxt),
                                                              .q_o (mepc_save_latched));

//------------------------------------------------------------------------
// MTVAL save value: exception-specific trap value (latched)
//   - Instruction addr misaligned (IF):          faulting PC (id_pc_i)
//   - Instruction access fault    (ID):          faulting-fetch byte address (id_inst_fault_addr_i)
//   - Load/store addr misaligned (EX):           faulting data address
//   - Load/store access fault (EX):              faulting data address
//   - All others (illegal, ECALL, EBREAK, IRQ):  0
//------------------------------------------------------------------------
wire [31:0] mtval_save_nxt   =  (ex_excp_load_address_misaligned_i | ex_excp_store_address_misaligned_i
                                                                  | trigger_ls_break
                                | ex_excp_load_access_fault_i     | ex_excp_store_access_fault_i)       ? ex_data_addr_i        :
                                id_inst_access_fault                                                    ? id_inst_fault_addr_i  :
                                if_excp_inst_address_misaligned_i                                       ? id_pc_i               :
                                                                                                           32'h0;

// Only address-based exceptions produce a non-zero mtval; ECALL/EBREAK/illegal/IRQ all write 0.
// The Sdtrig load/store breakpoint writes the faulting data address, like a misalign.
wire  mtval_exception_active =  ex_excp_load_address_misaligned_i  |
                                ex_excp_store_address_misaligned_i |
                                ex_excp_load_access_fault_i        |
                                ex_excp_store_access_fault_i       |
                                trigger_ls_break                   |
                                if_excp_inst_address_misaligned_i  |
                                id_inst_access_fault;

wire        mtval_save_latched_en  = trap_taken | (trap_pending_set & mtval_exception_active);
wire [31:0] mtval_save_latched_nxt = trap_taken ? 32'h0 : mtval_save_nxt;

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mtval_save_latched (
                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mtval_save_latched_en),
                                                               .d_i (mtval_save_latched_nxt),
                                                               .q_o (mtval_save_latched));

//------------------------------------------------------------------------
// Pipeline drain detection
// Uses existing ready signals from decode's stall detection
//------------------------------------------------------------------------
wire   ex_ready                 = ex_alu_ready_i & ex_ldst_ready_i & ex_csr_ready_i & ex_uop_ready_i;
wire   wb_ready                 = wb_ldst_ready_i;

assign pipeline_drained_for_id  = ex_ready & wb_ready;
assign pipeline_drained_for_ex  = wb_ready;

//------------------------------------------------------------------------
// IRQ kill: abort multi-cycle MUL/DIV and UOP operations for low-latency
// interrupt response. Kill signals fire when an IRQ is pending and the
// respective unit is busy. The killed instruction restarts from mepc
// after the ISR returns.
// - MUL/DIV: gated by ex_alu_is_killable_i (a killable multi-cycle MUL/DIV
//   is in progress)
// - UOP: gated by ex_uop_is_killable_i - the sequencer's is_killable signal
//   guarantees any in-flight AHB data phase has completed before aborting
//
// Livelock prevention: after killing a muldiv, suppress the next kill
// until the restarted instruction completes naturally. Without this,
// rapid IRQ pulses can kill the same instruction repeatedly, preventing
// forward progress.
//
// Two-phase state machine:
//   Phase 0 (suppress=0): normal operation, kills allowed
//   Phase 1 (suppress=1, wait_done=0): killed, waiting for restarted
//     muldiv to begin. Uses ex_alu_is_killable_i (not ~ex_alu_ready_i)
//     to avoid false triggers from verification stalls on non-muldiv
//     instructions in the IRQ handler.
//   Phase 2 (suppress=1, wait_done=1): restarted muldiv in progress,
//     waiting for it to complete
//------------------------------------------------------------------------
wire  muldiv_kill_wait_done;
wire muldiv_kill_restarted  =  muldiv_kill_suppress & ~muldiv_kill_wait_done &  ex_alu_is_killable_i;  // Restarted muldiv is running
wire muldiv_kill_completed  =  muldiv_kill_suppress &  muldiv_kill_wait_done & ~ex_alu_is_killable_i;  // Muldiv completed

wire muldiv_kill_suppress_en  = trap_kill_muldiv_o | muldiv_kill_completed;
wire muldiv_kill_suppress_nxt = trap_kill_muldiv_o ? 1'b1 : 1'b0;

arv_dff #(.ARST_EN(ARST_EN)) u_muldiv_kill_suppress (
                .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(muldiv_kill_suppress_en),
                                                     .d_i (muldiv_kill_suppress_nxt),
                                                     .q_o (muldiv_kill_suppress));

wire muldiv_kill_wait_done_en  = trap_kill_muldiv_o | muldiv_kill_restarted | muldiv_kill_completed;
wire muldiv_kill_wait_done_nxt = trap_kill_muldiv_o    ? 1'b0 :
                                 muldiv_kill_restarted ? 1'b1 :
                                                         1'b0;
arv_dff #(.ARST_EN(ARST_EN)) u_muldiv_kill_wait_done (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(muldiv_kill_wait_done_en),
                                                      .d_i (muldiv_kill_wait_done_nxt),
                                                      .q_o (muldiv_kill_wait_done));

wire   irqkill_muldiv_en      = marv_ctl_i[0];
wire   irqkill_uop_en         = marv_ctl_i[1];
wire   livelock_prot_en       = marv_ctl_i[2];

// NMI low-latency guarantee: NMI must always be able to abort a multi-cycle
// MUL/DIV, regardless of whether software has enabled irqkill_muldiv_en.
// IRQs are still gated by the configuration bit (software opt-in).
assign trap_kill_muldiv_o     = ((irqkill_muldiv_en & trap_is_irq) | trap_is_nmi) &
                                 trap_pending & ex_alu_is_killable_i & ~(muldiv_kill_suppress & livelock_prot_en);

// UOP kill: abort mid-sequence push/pop or table jump for low-latency IRQ response.
// The is_killable signal from the sequencer ensures AHB safety (data phase complete).
// Livelock prevention: after killing a UOP, suppress the next kill until the restarted
// sequence completes naturally. Without this, rapid IRQs can kill the same sequence
// repeatedly (especially long ones like CM.POPRET), preventing forward progress.
wire  uop_kill_wait_done;
wire uop_kill_restarted  =  uop_kill_suppress & ~uop_kill_wait_done &  ex_uop_kill_window_i;  // Restarted UOP sequence is running
wire uop_kill_completed  =  uop_kill_suppress &  uop_kill_wait_done &  ex_uop_ready_i;        // UOP sequence completed

wire uop_kill_suppress_en  = trap_kill_uop_o | uop_kill_completed;
wire uop_kill_suppress_nxt = trap_kill_uop_o ? 1'b1 : 1'b0;

arv_dff #(.ARST_EN(ARST_EN)) u_uop_kill_suppress (
             .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(uop_kill_suppress_en)
                                                , .d_i (uop_kill_suppress_nxt),
                                                  .q_o (uop_kill_suppress));

wire uop_kill_wait_done_en  = trap_kill_uop_o | uop_kill_restarted | uop_kill_completed;
wire uop_kill_wait_done_nxt = trap_kill_uop_o    ? 1'b0 :
                              uop_kill_restarted ? 1'b1 :
                                                   1'b0;

arv_dff #(.ARST_EN(ARST_EN)) u_uop_kill_wait_done (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(uop_kill_wait_done_en),
                                                   .d_i (uop_kill_wait_done_nxt),
                                                   .q_o (uop_kill_wait_done));


// NMI low-latency guarantee: NMI must always be able to abort a Zcmp UOP
// sequence, regardless of whether software has enabled irqkill_uop_en.
// IRQs are still gated by the configuration bit (software opt-in).
assign trap_kill_uop_hold_o   = ((irqkill_uop_en & trap_is_irq) | trap_is_nmi) &
                                 trap_pending & ~(uop_kill_suppress & livelock_prot_en);
assign trap_kill_uop_o        =  trap_kill_uop_hold_o & ex_uop_is_killable_i;

wire pipeline_drained_for_irq = (ex_alu_ready_i  | trap_kill_muldiv_o) &
                                 ex_ldst_ready_i & ex_csr_ready_i      &
                                (ex_uop_ready_i  | trap_kill_uop_o)    &
                                 wb_ready;

// UOP branch drain: when a UOP has a pending branch during a trap,
// wait for the branch redirect to fire AND the branch target instruction
// to arrive in the ID stage, so id_pc_i has the correct value for MEPC.
wire jt_load_fault_in_ex       = ex_uop_jt_active_i & wb_jt_load_error;
assign ex_uop_jt_fault_o       = jt_load_fault_in_ex;

wire uop_wait_for_id_valid_en  = trap_taken | jt_load_fault_in_ex | (ex_uop_take_branch_i & trap_stall_raw) | (uop_wait_for_id_valid & id_pc_settled);
wire uop_wait_for_id_valid_nxt = trap_taken                              ? 1'b0 :
                                 jt_load_fault_in_ex                     ? 1'b0 :
                                 (ex_uop_take_branch_i & trap_stall_raw) ? 1'b1 :
                                                                           1'b0;
arv_dff #(.ARST_EN(ARST_EN)) u_uop_wait_for_id_valid (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(uop_wait_for_id_valid_en),
                                                      .d_i (uop_wait_for_id_valid_nxt),
                                                      .q_o (uop_wait_for_id_valid));

// When a UOP kill fires, the branch will never execute, so bypass the has_branch check.
// Without this, CM.POPRET kills stall the drain for one cycle (has_branch clears next cycle),
// causing mepc_save_value to miss the ex_pc_i override and use id_pc_i instead.
// jt_load_fault_in_ex bypasses ex_uop_has_branch_i for the same reason on cm.jt/cm.jalt.
wire pipeline_drained_for_uop = (~ex_uop_has_branch_i | trap_kill_uop_o | jt_load_fault_in_ex) & ~uop_wait_for_id_valid;

wire trap_drained             = ((trap_stage[0] & pipeline_drained_for_id)   |  // IF exceptions drain like ID
                                 (trap_stage[1] & pipeline_drained_for_id)   |
                                 (trap_stage[2] & pipeline_drained_for_ex)   |
                                 (trap_is_irq   & pipeline_drained_for_irq)  |
                                 (trap_is_nmi   & pipeline_drained_for_irq)) & pipeline_drained_for_uop;  // NMI drains like IRQ

//------------------------------------------------------------------------
// Trap stage latch: records which pipeline stage detected the exception
//------------------------------------------------------------------------
wire       trap_stage_en  = trap_taken | ~trap_pending;
wire [2:0] trap_stage_nxt = trap_taken ? 3'b000 : {excp_detect_in_ex, excp_detect_in_id, excp_detect_in_if};

arv_dff #(.WIDTH(3), .ARST_EN(ARST_EN)) u_trap_stage (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_stage_en),
                                                      .d_i (trap_stage_nxt),
                                                      .q_o (trap_stage));

//------------------------------------------------------------------------
// Trap pending: stalls decode while waiting for pipeline drain
// When trap_taken fires, trap_branch_detect redirects fetch AND decode
// clears stale EX pipeline registers (CSR/LDST control), so the faulting
// instruction can no longer re-trigger exception detection.
//------------------------------------------------------------------------
wire trap_pending_en  = trap_taken | trap_pending_set;
wire trap_pending_nxt = trap_taken ? 1'b0 : 1'b1;

arv_dff #(.ARST_EN(ARST_EN)) u_trap_pending (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_en),
                                               .d_i (trap_pending_nxt),
                                               .q_o (trap_pending));

// Full combinational stall view (EX/WB exceptions and IRQs, before trap_pending
// registers), used by the UOP-branch wait logic above. Decode receives it split
// into trap_stall_o and ex_excp_squash_o below.
assign   trap_stall_raw       =  trap_pending | ((excp_detect_in_ex | irq_detect | nmi_detect) & ~trap_pending);

// Decode sees the stall in two parts. trap_stall_o drives the fetch-facing
// request and branch detect and leaves out the EX-stage exception, whose sources
// (PMP, misaligned, load/store trigger, EX CSR illegal) sit behind the load/store
// address adder or the CSR decode.
// ex_excp_squash_o is that EX-stage term, plus a load/store watchpoint entering
// Debug Mode. When a UOP has a pending branch, both are suppressed so the branch
// redirect can fire (id_instruction_request_o stays high for one cycle).
// Decode ANDs the squash into every dispatch it commits (EX control, SYSTEM ops,
// retire), so the ID instruction never enters EX. Fetch may consume it and
// follow a redirect in that cycle; trap_pending or debug_mode then holds
// everything from the next cycle and the trap or resume redirect overrides.
// in_lockup ORs in outside the UOP-branch qualifier: the critical-error state ceases
// execution unconditionally. Without it the trap clears trap_pending without
// redirecting, and decode would simply resume at the next sequential instruction --
// if_stop_cmd_o stops fetch, but says nothing about what is already in the buffer.
wire     trap_stall_fetch     =  trap_pending | ((irq_detect | nmi_detect) & ~trap_pending);
assign   trap_stall_o         = ((trap_stall_fetch | trap_branch_detect_r) & (~ex_uop_has_branch_i | jt_load_fault_in_ex)) | in_lockup;
assign   ex_excp_squash_o     = (excp_detect_in_ex | ls_debug_fire) &
                                 ~trap_pending & (~ex_uop_has_branch_i | jt_load_fault_in_ex);

//------------------------------------------------------------------------
// Trap taken: fires when pending and pipeline is drained
//------------------------------------------------------------------------
assign   trap_taken           =  trap_pending & trap_drained;

//------------------------------------------------------------------------
// Smdbltrp: a trap targeting M-mode while mstatus.MDT is already set is an
// unexpected double trap. It is not delivered through mtvec at all:
//
//   NMIE=1 -> diverted to the RNMI handler. mnepc/mncause take the values the
//             trap would have written to mepc/mcause, MNPP reads M and NMIE
//             clears; the M stack (mstatus/mepc/mcause/mtval) is untouched.
//   NMIE=0 -> critical-error state: no architectural state changes, not even
//             the PC, and lockup_o asserts for the platform to act on.
//
// MDT=1 implies M-mode -- every exit from M (mret, sret-in-M, mnret/dret below
// M) clears it -- so the privilege update is a no-op on both paths and needs no
// special case.
//
// Interrupts cannot precipitate one: trap entry clears mstatus.MIE, and MIE is
// settable only while MDT is 0, so MDT=1 with MIE=1 is unreachable. The term is
// left as plain ~trap_is_nmi to match the spec wording rather than that argument.
//------------------------------------------------------------------------
// Two independent ways to be unexpected (Priv 3.1.6.2):
//   mstatush_mdt                       -- a second trap into M before the handler re-armed
//   current_in_machine & ~mnstatus_nmie -- "a trap that occurs when executing in M-mode with
//                                          mnstatus.NMIE set to 0 is an unexpected trap".
// The second arm carries ~NMIE, so it can only ever route to the critical-error state: with no
// RNMI deliverable there is no escape to divert to. It covers a fault inside an RNMI handler,
// and equally the reset state, where NMIE is 0 until firmware sets it.
assign   m_dbl_trap           =  trap_taken & trap_to_m & ~trap_is_nmi &
                                 (mstatush_mdt | (current_in_machine & ~mnstatus_nmie));
assign   m_dbl_to_rnmi        =  m_dbl_trap &  mnstatus_nmie;
assign   m_dbl_to_cerr        =  m_dbl_trap & ~mnstatus_nmie;

assign   m_trap_entry         =  trap_taken & trap_to_m & ~trap_is_nmi & ~m_dbl_trap;
assign   rnmi_entry           = (trap_taken & trap_is_nmi) | m_dbl_to_rnmi;

// Sdtrig mte/mpte FSM taps (consumed by arv_debug_trigger). m_trap_entry mirrors the
// mstatus.mie save/clear condition (M-mode, non-NMI trap entry) so mte is restored
// symmetrically by mret_o; an NMI uses mnret/mnstatus and is excluded here. A double
// trap returns via mnret, so it must not push an mte save that mret_o would restore.
assign   m_trap_entry_o       =  m_trap_entry;
assign   mret_o               =  mret_taken;
assign   rnmi_entry_o         =  rnmi_entry;
assign   mnret_o              =  mnret_taken;

//------------------------------------------------------------------------
// Write-back suppression for faulting instructions
// Suppress EX-stage writes (ALU/CSR) when EX-stage exception detected
// ID/IF exceptions and interrupts do NOT suppress: older in-flight
// instructions must complete normally during pipeline drain
//------------------------------------------------------------------------
assign   trap_kill_ex_o       =  trap_pending & trap_stage[2];

//------------------------------------------------------------------------
// WFI wakeup: any enabled interrupt wakes WFI (regardless of global enable).
//------------------------------------------------------------------------
assign   wfi_wakeup_o         = |(mip & mie) | nmi_detect;

//------------------------------------------------------------------------
// Live wakeup: same wakeup semantics as wfi_wakeup_o, but combinatorial so
// it can ungate hclk_en_o at the top level while the clock is gated during
// WFI sleep (the registered irq_*_r / ip_pip / sip_* shadows are frozen by
// the gated clock and cannot update during sleep).
//
// marv_ctl[3]: force the live-wake high to keep hclk_en_o asserted
//------------------------------------------------------------------------
assign   wfi_wakeup_live_o    = (marv_ctl_i[3]                                 )  |
                                (irq_m_software_i   & mie_msie                 )  |
                                (irq_s_software_i               & SU_MODE_EN   )  |  // not to be masked with sie_ssie (irq_s_software_i is a one-cycle pulse, and the hart must wake up to latch sip.SSIP)
                                (irq_s_software_r               & SU_MODE_EN   )  |  // second gated edge: sip.SSIP is set from the latched pulse, not from irq_s_software_i
                                (sip_ssip_eff       & sie_ssie  & SU_MODE_EN   )  |
                                (irq_m_timer_i      & mie_mtie                 )  |
                                (sip_stip           & sie_stie  & SU_MODE_EN   )  |
                                (irq_m_external_i   & mie_meie                 )  |
                                (irq_s_external_i   & sie_seie                 )  |
                                (sip_seip_sw        & sie_seie                 )  |
                                (|(irq_platform_i   & mie_mpie                ))  |
                                (|(ip_pip           & mie_mpie                ))  |
                                (nmi_i & mnstatus_nmie & ~nmi_suppress_post_mnret) |
                                ((bus_error_pulse | nmi_bus_pending)
                                       & mnstatus_nmie & ~nmi_suppress_post_mnret) |
                                (dbg_halt_active);   // keep hclk alive while halted / entering / resuming.

//------------------------------------------------------------------------
// Trap target computation (combinational for decode branch infrastructure)
//------------------------------------------------------------------------
assign   trap_target_direct      = trap_to_m ? {mtvec_base, 2'b00} : {stvec_base, 2'b00};
assign   trap_target_vectored    = trap_target_direct + {25'b0, trap_cause_latched, 2'b00};
// ~trap_is_dbl: a double trap is delivered with mcause.interrupt=0 (even when the
// original event was an interrupt), and vectored mode applies to interrupts only,
// so a doubled interrupt takes the DIRECT mtvec target (Ssdbltrp).
assign   use_vectored            = trap_is_irq & ~trap_is_dbl & (trap_to_m ? (mtvec_mode==2'b01) : (stvec_mode==2'b01));

assign   trap_branch_target_comb = dbg_resume_redirect ? (dbg_dpc & 32'hFFFFFFFE) :
                                   mnret_taken         ? {mnepc_mnepc, 1'b0}      :
                                   mret_taken          ? {mepc_mepc,   1'b0}      :
                                   sret_taken          ? {sepc_sepc,   1'b0}      :
                                   rnmi_entry          ? marv_nmvec_i             :
                                   use_vectored        ? trap_target_vectored     :
                                                         trap_target_direct       ;

// ~m_dbl_to_cerr: the critical-error state updates no architectural state, "including the
// pc" (Priv 3.1.6.2), so the trap must not redirect fetch.
assign   trap_branch_detect_comb = (trap_taken & ~m_dbl_to_cerr) | mret_taken | sret_taken | mnret_taken | dbg_resume_redirect;

// Registered outputs: target/detect delayed one cycle for timing improvement.
// trap_stall_o is extended by trap_branch_detect_r to keep decode frozen
// through the redirect cycle (since trap_pending clears one cycle earlier).
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_trap_branch_target_r (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(trap_branch_target_comb), .q_o(trap_branch_target_r));
arv_dff #(.ARST_EN(ARST_EN)) u_trap_branch_detect_r (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(trap_branch_detect_comb), .q_o(trap_branch_detect_r));

assign   trap_branch_target_o = trap_branch_target_r;
assign   trap_branch_detect_o = trap_branch_detect_r;

//------------------------------------------------------------------------
// Critical-error state (Smdbltrp)
//
// Entered when a double trap arrives with mnstatus.NMIE=0, i.e. out of reset or
// inside an RNMI handler. The hart ceases execution and asserts lockup_o for the
// platform; the spec leaves the platform's response open, so recovery is a reset.
// Sticky to reset accordingly -- and NMIE cannot be raised again from here, since
// only mnret sets it and no instruction will dispatch.
//------------------------------------------------------------------------
wire in_lockup_en  = m_dbl_to_cerr;
wire in_lockup_nxt = 1'b1;
arv_dff #(.ARST_EN(ARST_EN)) u_in_lockup (
           .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(in_lockup_en),      .d_i(in_lockup_nxt),      .q_o(in_lockup));

//------------------------------------------------------------------------
// Privilege mode updates
//------------------------------------------------------------------------
assign   priv_mode_next_comb   = !SU_MODE_EN              ? 2'b11               :
                                  dbg_resume_redirect     ? dbg_dcsr_prv        :
                                 (trap_taken & trap_to_m) ? 2'b11               :
                                 (trap_taken & trap_to_s) ? 2'b01               :
                                  mnret_taken             ? mnstatus_mnpp       :
                                  mret_taken              ? mstatus_mpp         :
                                  sret_taken              ? {1'b0, sstatus_spp} :
                                                            priv_mode_current_i ;

assign   priv_mode_update_comb = trap_taken | mret_taken | sret_taken | mnret_taken | dbg_resume_redirect;

// Registered outputs: delayed one cycle in sync with trap_branch_detect_r/trap_branch_target_r.
// arv_csr_top's combinational bypass (privilege_mode_update ? privilege_mode_nxt : privilege_mode)
// ensures if_priv_mode_o reflects the new mode on the same cycle as the fetch redirect fires.
arv_dff #(.WIDTH(2), .RST_VAL(2'b11), .ARST_EN(ARST_EN)) u_priv_mode_next_r (   // Machine mode after reset
                                        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                                             .d_i (priv_mode_next_comb),
                                                                             .q_o (priv_mode_next_r));
arv_dff #(.ARST_EN(ARST_EN)) u_priv_mode_update_r (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                   .d_i (priv_mode_update_comb),
                                                   .q_o (priv_mode_update_r));

assign   priv_mode_next_o   = priv_mode_next_r;
assign   priv_mode_update_o = priv_mode_update_r;

// Effective privilege mode for load/store data accesses (MPRV-aware)
// When MPRV=1 and in M-mode, use MPP instead of current privilege mode.
// MPRV is ignored while in an RNMI handler (mnstatus.NMIE=0): RISC-V Priv
// spec Smrnmi requires the hart to behave as though MPRV were clear when NMIE=0.
assign   priv_mode_ldst_o  = !SU_MODE_EN                                          ? 2'b11              :
                             (mstatus_mprv & current_in_machine &  mnstatus_nmie) ? mstatus_mpp        :
                                                                                    priv_mode_current_i;

// HPM trap events (arv_csr_top). The critical-error entry updates no architectural state
// (Priv 3.1.6.2), mhpmcounter included, so it is not a counted trap.
assign     trap_taken_o    =  trap_taken & ~m_dbl_to_cerr;
assign     trap_is_irq_o   =  trap_is_irq;

//------------------------------------------------------------------------
// minstret un-retire (Zicntr, Priv 3.1.11): "Instructions that cause synchronous
// exceptions, including ECALL and EBREAK, are not considered to have retired and
// hence do not increment minstret."
//------------------------------------------------------------------------
// An instruction-fetch access fault or an Sdtrig execute breakpoint (action=0) traps an
// instruction that was never dispatched, hence never counted: nothing to un-retire.
wire trap_undispatched;
arv_dff #(.ARST_EN(ARST_EN)) u_trap_undispatched (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_set),
                                               .d_i (excp_vector_highest[1] | excp_vector_highest[0]),
                                               .q_o (trap_undispatched));

// ~m_dbl_to_cerr: the critical-error state updates no architectural state (Priv 3.1.6.2),
// and minstret is architectural. Every other trap still un-retires its instruction.
// An IRQ/NMI that kills a multi-cycle op in EX also un-retires it: the op was counted
// at dispatch and is re-dispatched after xRET. Completed accesses stay retired (a data-bus
// NMI never un-retires the store that caused it -- doc/spec_compliance_notes.md).
// An NMI latched together with a synchronous exception is taken first and names the excepting
// instruction (it re-executes after mnret), so that instruction is un-retired as well.
assign     minstret_undo_o = (trap_taken & (((~trap_is_irq & (~trap_is_nmi | (|trap_stage))) & ~trap_undispatched) |
                                            trap_kill_restart) & ~m_dbl_to_cerr) |
                              dbg_ls_wp_entry;   // the watchpointed access re-executes after resume


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                  LINT CLEANUP                                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

wire [1:0] reset_vector_unused     = reset_vector_i[1:0];
wire       mepc_save_value0_unused = mepc_save_value[0];
wire       register_sel_unused     = |register_sel_i;

wire       dbg_dpc_0_unused        = dbg_dpc[0];

// Signals whose consumers fold to constants in some configurations.
generate
    if (SU_MODE_EN == 1'b0) begin : gen_su_unused
        wire id_opcode_sret_unused       = id_opcode_sret_i;
        wire irq_s_software_r_unused     = irq_s_software_r;
    end

    // Also dead with SU_MODE_EN=0: with no S/U modes the privilege to restore
    // on debug resume is always M, so dcsr.prv folds to a constant.
    if (DEBUG_EN == 1'b0 || SU_MODE_EN == 1'b0) begin : gen_debug_unused
        wire [1:0] dbg_dcsr_prv_unused   = dbg_dcsr_prv;
    end
endgenerate


endmodule // arv_csr_traps

`default_nettype wire

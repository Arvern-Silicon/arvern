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
//                                                        medeleg + WFI sleep + IRQ/NMI prioritisation)
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

// TRAP INTERFACE TO DECODE
    output wire           trap_pending_o,
    output wire           trap_stall_o,
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
    input  wire           id_excp_ecall_i,
    input  wire           ex_excp_illegal_inst_i,
    input  wire           ex_excp_load_address_misaligned_i,
    input  wire           ex_excp_store_address_misaligned_i,
    input  wire           wb_excp_load_access_fault_i,
    input  wire           wb_excp_store_access_fault_i,

// PIPELINE READY SIGNALS (FOR DRAIN DETECTION)
    input  wire           ex_alu_ready_i,
    input  wire           ex_ldst_ready_i,
    input  wire           ex_csr_ready_i,
    input  wire           ex_uop_has_branch_i,
    input  wire           ex_uop_ready_i,
    input  wire           ex_uop_take_branch_i,
    input  wire           id_instruction_valid_i,
    input  wire           wb_ldst_ready_i,
    input  wire           wb_dph_ongoing_i,

// PIPELINE MONITORING & CONTROL IN CASE OF TRAP
    output wire           if_stop_cmd_o,
    output wire           lockup_o,

// PC PIPELINE INPUTS (FOR MEPC SAVE)
    input  wire    [31:0] id_pc_i,
    input  wire    [31:0] ex_pc_i,
    input  wire    [31:0] wb_pc_i,

// DATA ADDRESS PIPELINE (FOR MTVAL SAVE)
    input  wire    [31:0] ex_data_addr_i,
    input  wire    [31:0] wb_data_addr_i,

// PRIVILEGE MODE
    input  wire     [1:0] priv_mode_current_i,
    output wire     [1:0] priv_mode_next_o,
    output wire           priv_mode_update_o,
    output wire     [1:0] priv_mode_ldst_o,

// WRITE-BACK SUPPRESSION
    output wire           trap_kill_ex_o,
    output wire           trap_kill_wb_o,

// IRQ KILL FOR MULTI-CYCLE OPERATIONS
    input  wire           ex_alu_is_killable_i,
    input  wire           ex_uop_is_killable_i,
    input  wire           ex_uop_jt_active_i,
    input  wire           id_uop_jt_start_i,
    input  wire     [4:0] marv_ctl_i,
    output wire           trap_kill_muldiv_o,
    output wire           trap_kill_uop_o,
    output wire           ex_uop_excp_abort_o,

// HPM TRAP EVENTS
    output wire           trap_taken_o,
    output wire           trap_is_irq_o,

// INITIALIZATION OF THE TRAP VECTOR DEFAULT VALUES
    input  wire           init_pc_i,
    input  wire    [31:0] reset_vector_i,

// NMI (SMRNMI)
    input  wire           nmi_i,
    input  wire    [31:0] nmi_vector_i,
    input  wire           id_opcode_mnret_i,

// MIP[9] SEIP RMW WRITE-BACK
    output wire           sip_seip_sw_o,
    input  wire           mip_seip_sw_rmw_nxt_i

);

// PARAMETER
//=====================================================
parameter                 ARST_EN        = 1'b1;       // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 C_EXT_EN       = 1'b0;       // Compressed instructions enabled (affects MEPC/SEPC alignment)
parameter                 NMI_EN         = 1'b0;       // Smrnmi extension enable (resumable NMI)
parameter                 SU_MODE_EN     = 1'b1;       // S+U privilege modes (0=M-only: S-CSRs RAZ/WI, no delegation,
                                                       // current_priv hardwired to M, MPP forced to M; 1=M+S+U full)


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
//wire       mstatush_wr;

wire  [31:0] medelegh;
wire         medelegh_sel;
//wire       medelegh_wr;

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
//wire       mtval2_wr;

wire         current_in_machine;
wire         current_in_supervisor;
wire         current_in_user;

wire         excp_detect_in_if;
wire         excp_detect_in_id;
wire         excp_detect_in_ex;
wire         excp_detect_in_wb;

wire         excp_ignore_deleg;
wire  [11:0] excp_vector_prio;
wire  [11:0] excp_vector_highest;
wire  [11:0] excp_vector_cause;
wire  [11:0] excp_vector_deleg;
wire   [3:0] excp_cause;
wire         excp_detect;
wire         excp_detect_to_m;
wire         excp_detect_to_s;

wire         irq_ignore_deleg;
wire  [31:0] irq_vector_prio;
wire  [31:0] irq_vector_highest;
wire  [31:0] irq_vector_cause;
wire  [31:0] irq_vector_deleg;
wire   [4:0] irq_cause;
wire         irq_detect;
wire         irq_detect_to_m;
wire         irq_detect_to_s;

// Trap state machine
wire         trap_taken;
wire         trap_is_irq;
wire         trap_is_nmi;
wire         trap_to_m;
wire         trap_to_s;
wire   [4:0] trap_cause_latched;
wire  [31:0] mepc_save_latched;
wire  [31:0] mtval_save_latched;
wire  [31:0] mepc_save_value;
wire         mret_taken;
wire         sret_taken;
wire         mnret_taken;
wire   [3:0] trap_stage;
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
wire         trap_stall_raw;
wire         muldiv_kill_suppress;

wire         in_m_excp_trap;  // In M-mode exception handler; cleared on mret only
wire         in_s_excp_trap;  // In S-mode exception handler only; cleared on sret only (not mret)
wire         go_to_lockup;
wire         in_lockup;
wire         lockup_dph_drain_r;
wire         pipeline_drained_for_id;
wire         pipeline_drained_for_ex;
wire         pipeline_drained_for_wb;

// NMI CSR register select (module-scope: used in read mux regardless of NMI_EN)
wire         mnscratch_sel;
wire         mnepc_sel;
wire         mncause_sel;
wire         mnstatus_sel;

// NMI CSR storage (module-scope: referenced by module-level logic outside generate)
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
wire         nmi_escape_lockup_cfg; // marv_ctl[3]: allow NMI to escape lockup


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


//  +======================================================================+======================================================================+======================================================================+
//  |              IRQ OR TRAP FLOW FROM U-LEVEL TO M-LEVEL                |              IRQ OR TRAP FLOW FROM U-LEVEL TO S-LEVEL                |              IRQ OR TRAP FLOW FROM S-LEVEL TO M-LEVEL                |
//  |======================================================================+======================================================================+======================================================================|
//  |                                                                      |                                                                      |                                                                      |
//  |    Before Trap:                                                      |    Before Trap:                                                      |    Before Trap:                                                      |
//  |    ┌────────────────────────────────────────────────────────────┐    |    ┌────────────────────────────────────────────────────────────┐    |    ┌────────────────────────────────────────────────────────────┐    |
//  |    │ Privilege = U   = 0                                        │    |    │ Privilege = U   = 0                                        │    |    │ Privilege = S   = 1                                        │    |
//  |    │ MIE       = 1/0          (interrupts ON or OFF)            │    |    │ SIE       = 1/0          (interrupts ON or OFF)            │    |    │ MIE       = 1/0          (interrupts ON or OFF)            │    |
//  |    │ MPIE      = x            (old)                             │    |    │ SPIE      = x            (old)                             │    |    │ MPIE      = x            (old)                             │    |
//  |    │ MPP       = x            (old)                             │    |    │ SPP       = x            (old)                             │    |    │ MPP       = x            (old)                             │    |
//  |    └────────────────────────────────────────────────────────────┘    |    └────────────────────────────────────────────────────────────┘    |    └────────────────────────────────────────────────────────────┘    |
//  |                                                                      |                                                                      |                                                                      |
//  |    Trap Entry into M:                                                |    Trap Entry into S:                                                |    Trap Entry into M:                                                |
//  |    ┌────────────────────────────────────────────────────────────┐    |    ┌────────────────────────────────────────────────────────────┐    |    ┌────────────────────────────────────────────────────────────┐    |
//  |    │ Privilege = M   = 3      (switch to M-mode)                │    |    │ Privilege = S   = 1      (switch to M-mode)                │    |    │ Privilege = M   = 3      (switch to M-mode)                │    |
//  |    │ MPP       ← U   = 0      (record that we came from U-mode) │    |    │ SPP       ← U   = 0      (record that we came from U-mode) │    |    │ MPP       ← S   = 1      (record that we came from S-mode) │    |
//  |    │ MPIE      ← MIE          (save M interrupt enable)         │    |    │ SPIE      ← SIE          (save current SIE)                │    |    │ MPIE      ← MIE          (save M interrupt enable)         │    |
//  |    │ MIE       ← 0            (disable machine interrupts)      │    |    │ SIE       ← 0            (disable supervisor interrupts)   │    |    │ MIE       ← 0            (disable machine interrupts)      │    |
//  |    │ MTVAL     ← value        (optional trap value)             │    |    │ STVAL     ← value        (optional trap value)             │    |    │ MTVAL     ← value        (optional trap value)             │    |
//  |    │ MEPC      ← PC           (save PC)                         │    |    │ SEPC      ← PC           (save PC)                         │    |    │ MEPC      ← PC           (save PC)                         │    |
//  |    │ MCAUSE    ← cause        (reason for trap)                 │    |    │ SCAUSE    ← cause        (reason for trap)                 │    |    │ MCAUSE    ← cause        (reason for trap)                 │    |
//  |    └────────────────────────────────────────────────────────────┘    |    └────────────────────────────────────────────────────────────┘    |    └────────────────────────────────────────────────────────────┘    |
//  |                                                                      |                                                                      |                                                                      |
//  |    Handler executes in M-mode (interrupts disabled because MIE = 0)  |    Handler executes in S-mode (interrupts disabled because SIE = 0)  |    Handler executes in M-mode (interrupts disabled because MIE = 0)  |
//  |                                                                      |                                                                      |                                                                      |
//  |    MRET:                                                             |    SRET:                                                             |    MRET:                                                             |
//  |    ┌────────────────────────────────────────────────────────────┐    |    ┌────────────────────────────────────────────────────────────┐    |    ┌────────────────────────────────────────────────────────────┐    |
//  |    │ Privilege ← MPP = U = 0  (restore previous mode: U)        │    |    │ Privilege ← SPP = U = 0  (restore previous mode: U)        │    |    │ Privilege ← MPP = S = 1  (restore previous mode: S)        │    |
//  |    │ MIE       ← MPIE         (restore saved interrupt enable)  │    |    │ SIE       ← SPIE         (restore saved interrupt enable)  │    |    │ MIE       ← MPIE         (restore saved interrupt enable)  │    |
//  |    │ MPIE      ← 1            (set ready-for-next-trap state)   │    |    │ SPIE      ← 1            (set ready-for-next-trap state)   │    |    │ MPIE      ← 1            (set ready-for-next-trap state)   │    |
//  |    │ MPP       ← U = 0        (reset MPP - safe default)        │    |    │ SPP       ← U = 0        (reset MPP - safe default)        │    |    │ MPP       ← U = 0        (reset MPP - safe default)        │    |
//  |    | PC        ← MEPC         (return to the saved PC)          |    |    | PC        ← SEPC         (return to the saved PC)          |    |    | PC        ← MEPC         (return to the saved PC)          |    |
//  |    └────────────────────────────────────────────────────────────┘    |    └────────────────────────────────────────────────────────────┘    |    └────────────────────────────────────────────────────────────┘    |
//  |                                                                      |                                                                      |                                                                      |
//  +======================================================================+======================================================================+======================================================================+


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

wire sstatus_sie_en  = (trap_taken & trap_to_s) | sret_taken | sstatus_wr;
wire sstatus_sie_nxt = (trap_taken & trap_to_s) ? 1'b0          :
                       sret_taken               ? sstatus_spie  :
                                                  register_value_nxt_i[1];
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
                                  (register_value_nxt_i[31:16] & mideleg_dpu) | (ie_pie & ~mideleg_dpu);   // access through SIE only write delegated bits
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
wire [29:0] stvec_base_nxt = stvec_wr ? register_value_nxt_i[31:2] : (reset_vector_i[31:2]+30'h00000002);
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
arv_dff #(.WIDTH(11), .ARST_EN(ARST_EN)) u_scounteren_reg (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(scounteren_wr),
                                                           .d_i (register_value_nxt_i[10:0]),
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

assign       mstatus_wr     =  (mstatus_sel          & ~disable_write_i);
assign       medeleg_wr     =  (medeleg_sel          & ~disable_write_i) & SU_MODE_EN;  // RAZ/WI when SU_MODE_EN=0
assign       mideleg_wr     =  (mideleg_sel          & ~disable_write_i) & SU_MODE_EN;  // RAZ/WI when SU_MODE_EN=0
assign       mie_wr         =  (mie_sel              & ~disable_write_i);
assign       mtvec_wr       =  (mtvec_sel            & ~disable_write_i);
//assign     mstatush_wr    =  (mstatush_sel         & ~disable_write_i);
//assign     medelegh_wr    =  (medelegh_sel         & ~disable_write_i);

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

wire mstatus_mie_en  = (trap_taken & trap_to_m & ~trap_is_nmi) | mret_taken | mstatus_wr;
wire mstatus_mie_nxt = (trap_taken & trap_to_m & ~trap_is_nmi) ? 1'b0         :
                       mret_taken                              ? mstatus_mpie :
                                                                 register_value_nxt_i[3];
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_mie (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_mie_en), .d_i(mstatus_mie_nxt), .q_o(mstatus_mie));

wire mstatus_mpie_en  = (trap_taken & trap_to_m & ~trap_is_nmi) | mret_taken | mstatus_wr;
wire mstatus_mpie_nxt = (trap_taken & trap_to_m & ~trap_is_nmi) ? mstatus_mie :
                        mret_taken                              ? 1'b1        :
                                                                  register_value_nxt_i[7];
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_mpie (
        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_mpie_en), .d_i(mstatus_mpie_nxt), .q_o(mstatus_mpie));

// SU_MODE_EN=0: MPP hardwired to 2'b11 (M)
wire       mstatus_mpp_en  = (trap_taken & trap_to_m & ~trap_is_nmi) | mret_taken | mstatus_wr;
wire [1:0] mstatus_mpp_nxt = (trap_taken & trap_to_m & ~trap_is_nmi) ? priv_mode_current_i        :
                             mret_taken                              ? (SU_MODE_EN ? 2'b00 : 2'b11) :
                                                                       (!SU_MODE_EN                            ? 2'b11        :
                                                                        (register_value_nxt_i[12:11] == 2'b10) ? mstatus_mpp  : // 2'b10 reserved, keep old value
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
//                                     Cleared on MRET/SRET when returning to a mode less privileged than M.
wire mstatus_wr_msk = mstatus_wr & SU_MODE_EN;
wire mstatus_mprv_en  = (sret_taken | (mret_taken & (mstatus_mpp != 2'b11))) | mstatus_wr_msk;
wire mstatus_mprv_nxt = (sret_taken | (mret_taken & (mstatus_mpp != 2'b11))) ? 1'b0 :   // Clear when returning to mode < M (mnret must NOT touch mstatus per Smrnmi spec)
                                                                               register_value_nxt_i[17];
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_mprv (
        .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_mprv_en),
                                             .d_i (mstatus_mprv_nxt),
                                             .q_o (mstatus_mprv));

// SUM (bit 18), MXR (bit 19): WARL writable since S-mode is supported.
// No functional consumers - paging/MMU is not implemented, so the bits
// have "no effect" per the spec.
// They exist only because they are mandated by the spec when S-mode is supported.
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_sum (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sstatus_wr),
                                            .d_i (register_value_nxt_i[18]),
                                            .q_o (mstatus_sum));

arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_mxr (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(sstatus_wr),
                                            .d_i (register_value_nxt_i[19]),
                                            .q_o (mstatus_mxr));

// TVM (bit 20): M-only; not visible in sstatus. Same WARL rationale -
// no satp / SFENCE.VMA exists, so TVM has nothing to intercept.
arv_dff #(.ARST_EN(ARST_EN)) u_mstatus_tvm (
       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mstatus_wr & SU_MODE_EN),
                                            .d_i (register_value_nxt_i[20]),
                                            .q_o (mstatus_tvm));

assign  cfg_timeout_wait_o = mstatus_tw;
assign  cfg_trap_sret_o    = mstatus_tsr;


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
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_ldaf (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[5]), .q_o(medeleg_ldaf));
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_stam (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[6]), .q_o(medeleg_stam));
arv_dff #(.ARST_EN(ARST_EN)) u_medeleg_staf (.clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(medeleg_wr), .d_i(register_value_nxt_i[7]), .q_o(medeleg_staf));
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
wire [29:0] mtvec_base_nxt = mtvec_wr ? register_value_nxt_i[31:2] : (reset_vector_i[31:2]+30'h00000001);
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

assign       sscratch_wr    =  (sscratch_sel         & ~disable_write_i) & SU_MODE_EN;  // RAZ/WI when SU_MODE_EN=0
assign       sepc_wr        =  (sepc_sel             & ~disable_write_i) & SU_MODE_EN;  // RAZ/WI when SU_MODE_EN=0
assign       scause_wr      =  (scause_sel           & ~disable_write_i) & SU_MODE_EN;  // RAZ/WI when SU_MODE_EN=0
assign       stval_wr       =  (stval_sel            & ~disable_write_i) & SU_MODE_EN;  // RAZ/WI when SU_MODE_EN=0
assign       sip_wr         =  (sip_sel              & ~disable_write_i) & SU_MODE_EN;  // RAZ/WI when SU_MODE_EN=0

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
//                    Interrupt | Exception | Code Description
//                  ------------+-----------+----------------------------------------
//                        1     |     1     |   Supervisor software interrupt
//                        1     |     5     |   Supervisor timer interrupt
//                        1     |     9     |   Supervisor external interrupt
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

// HW contribution is now latched into sip_ssip directly -- no combinational OR needed.
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
//assign     mtval2_wr      =  (mtval2_sel           & ~disable_write_i);

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

// Kill override is only valid for IRQ/NMI traps (trap_stage==0). Sync EX/WB
// exceptions (trap_stage[2]/[3]) already have stage-correct PCs latched in
// mepc_save_latched (via trap_pc_to_save) and must not be overridden. This
// expression feeds BOTH mepc_mepc and mnepc_mnepc_reg (NMI path).
// trap_pc_to_save cascade-order invariant (two constraints, both required):
//   (a) `(nmi_detect & ex_uop_jt_active_i) ? ex_pc_i` MUST stay ABOVE
//       `excp_detect_in_wb ? wb_pc_i` so an NMI co-firing with a WB load
//       access fault during cm.jt saves the cm.jt PC (the gate below blocks
//       the kill override, mnepc inherits mepc_save_latched = ex_pc_i).
//   (b) `excp_detect_in_wb`/`excp_detect_in_ex` MUST stay ABOVE the generic
//       `nmi_detect ? id_pc_i`: an NMI preempting a
//       same-cycle-detected sync exception must save the faulting EX/WB PC,
//       not the younger decode PC, for Smrnmi resumability after MNRET.
assign mepc_save_value = ((trap_kill_muldiv_o | trap_kill_uop_o) & ~trap_stage[3] & ~trap_stage[2]) ? ex_pc_i : mepc_save_latched;

wire        mepc_mepc_en  = (trap_taken & trap_to_m & ~trap_is_nmi) | mepc_wr;
wire [30:0] mepc_mepc_nxt = (trap_taken & trap_to_m & ~trap_is_nmi) ? {mepc_save_value[31:2],      mepc_save_value[1]      & mepc_align_mask} :
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

wire mcause_irq_en  = (trap_taken & trap_to_m & ~trap_is_nmi) | mcause_wr;
wire mcause_irq_nxt = (trap_taken & trap_to_m & ~trap_is_nmi) ? trap_is_irq : register_value_nxt_i[31];
arv_dff #(.ARST_EN(ARST_EN)) u_mcause_irq (
      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcause_irq_en), .d_i(mcause_irq_nxt), .q_o(mcause_irq));

wire       mcause_mcause_en  = (trap_taken & trap_to_m & ~trap_is_nmi) | mcause_wr;
wire [4:0] mcause_mcause_nxt = (trap_taken & trap_to_m & ~trap_is_nmi) ? trap_cause_latched : register_value_nxt_i[4:0];
arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_mcause_mcause (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcause_mcause_en), .d_i(mcause_mcause_nxt), .q_o(mcause_mcause));

//
//  MTVAL (0x343 : Machine trap value)
//
//                       - MTVAL    31:0  When a trap is taken into M-mode, mtval is either set to zero
//                                        or written with exception-specific information to assist
//                                        software in handling the trap.

wire        mtval_mtval_en  = (trap_taken & trap_to_m & ~trap_is_nmi) | mtval_wr;
wire [31:0] mtval_mtval_nxt = (trap_taken & trap_to_m & ~trap_is_nmi) ? mtval_save_latched : register_value_nxt_i[31:0];
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
wire [15:0] ip_pip_nxt = mip_wr ?  register_value_nxt_i[31:16] | irq_platform_r                                          :
                         sip_wr ? (register_value_nxt_i[31:16] & mideleg_dpu) | (ip_pip & ~mideleg_dpu) | irq_platform_r :
                                   ip_pip | irq_platform_r;
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
//////                                  + MNCAUSE   : 0x742 : NMI trap cause (read-only 0: impl-defined)                    //////
//////                                  + MNSTATUS  : 0x744 : NMI status register (NMIE + MNPP)                             //////
//////                                                                                                                      //////
//////  CSR bank 0x740-0x75F: bits[11:6] = 6'b011101                                                                        //////
//////  When NMI_EN=0, these addresses raise illegal instruction (absent CSR rule)                                          //////
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

generate
    if (NMI_EN) begin : gen_nmi

        // Write enables and storage declared locally - absent when NMI_EN=0
        wire         mnscratch_wr  =  (mnscratch_sel & ~disable_write_i);
        wire         mnepc_wr      =  (mnepc_sel     & ~disable_write_i);
        //           mncause is read-only
        wire         mnstatus_wr   =  (mnstatus_sel  & ~disable_write_i);

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
        wire        mnepc_mnepc_reg_en  = (trap_taken & trap_is_nmi) | mnepc_wr;
        wire [30:0] mnepc_mnepc_reg_nxt = (trap_taken & trap_is_nmi) ? {mepc_save_value[31:2],      mepc_save_value[1]      & mepc_align_mask} :
                                                                       {register_value_nxt_i[31:2], register_value_nxt_i[1] & mepc_align_mask};
        arv_dff #(.WIDTH(31), .ARST_EN(ARST_EN)) u_mnepc_mnepc_reg (
                               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mnepc_mnepc_reg_en), .d_i(mnepc_mnepc_reg_nxt), .q_o(mnepc_mnepc_reg));

        //
        //  MNCAUSE (0x742 : NMI trap cause) -- WARL, single NMI source.
        //                                      bit[31]=1 (interrupt), bits[30:0]=0 (cause=0).
        //                                      Constant 0x80000000; reset value is implementation-defined.
        //
        assign mncause = 32'h80000000;

        //
        //  MNSTATUS (0x744 : NMI status register)
        //
        //                       - NMIE   3     NMI enable bit: cleared on NMI entry, set on mnret.
        //                                      While NMIE=0, NMI is suppressed (allows handler to run without nesting).
        //                       - MNPP  12:11  Previous privilege mode (saved on NMI entry, restored on mnret).
        //
        wire      mnstatus_nmie_reg;
        wire      mnstatus_nmie_reg_en  = (trap_taken & trap_is_nmi) | mnret_taken | mnstatus_wr;
        wire      mnstatus_nmie_reg_nxt = (trap_taken & trap_is_nmi) ? 1'b0 :                                    // Cleared on NMI entry
                                          mnret_taken               ? 1'b1 :                                    // Restored on mnret
                                                                      mnstatus_nmie_reg | register_value_nxt_i[3]; // Smrnmi: NMIE is software-set-only; writing 0 has no effect

        arv_dff #(.ARST_EN(ARST_EN)) u_mnstatus_nmie_reg (  // NMI disabled after reset (Smrnmi spec: NMIE resets to 0)
                     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mnstatus_nmie_reg_en),
                                                          .d_i (mnstatus_nmie_reg_nxt),
                                                          .q_o (mnstatus_nmie_reg));

        wire [1:0] mnstatus_mnpp_reg;
        wire       mnstatus_mnpp_reg_en  = (trap_taken & trap_is_nmi) | mnret_taken | mnstatus_wr;
        wire [1:0] mnstatus_mnpp_reg_nxt = (trap_taken & trap_is_nmi) ? priv_mode_current_i :
                                            mnret_taken               ? 2'b11               :  // Reset MPP after use
                                                                       (!SU_MODE_EN                            ? 2'b11               :
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

    end else begin : gen_nmi_disabled

        assign mncause       = 32'h00000000;
        assign mnscratch     = 32'h00000000;
        assign mnepc_mnepc   = 31'h00000000;
        assign mnepc         = 32'h00000000;
        assign mnstatus_nmie =  1'b0;
        assign mnstatus_mnpp =  2'b00;
        assign mnstatus      = 32'h00000000;

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
assign mstatus        = {9'h000, mstatus_tsr, mstatus_tw, mstatus_tvm, mstatus_mxr, mstatus_sum, mstatus_mprv, 4'h0, mstatus_mpp, 2'h0, sstatus_spp, mstatus_mpie, 1'h0, sstatus_spie, 1'h0, mstatus_mie, 1'h0, sstatus_sie, 1'h0};
assign sstatus        = {9'h000, 1'h0,        1'h0,       1'h0,        mstatus_mxr, mstatus_sum, 1'h0,         4'h0, 2'h0,        2'h0, sstatus_spp, 1'h0,         1'h0, sstatus_spie, 1'h0, 1'h0,        1'h0, sstatus_sie, 1'h0};

assign mie            = {mie_mpie, 4'h0, mie_meie, 1'h0, sie_seie, 1'h0, mie_mtie, 1'h0, sie_stie, 1'h0, mie_msie, 1'h0, sie_ssie, 1'h0};
assign sie            = {sie_spie, 4'h0,   1'h0,   1'h0, sie_seie & mideleg_sei, 1'h0,   1'h0,   1'h0, sie_stie & mideleg_sti, 1'h0,   1'h0,   1'h0, sie_ssie & mideleg_ssi, 1'h0};

assign mtvec          = {mtvec_base, mtvec_mode};
assign stvec          = {stvec_base, stvec_mode};

assign medeleg        = {22'h000000, medeleg_ecas, medeleg_ecau, medeleg_staf, medeleg_stam, medeleg_ldaf, medeleg_ldam, medeleg_ebrk, medeleg_illi, medeleg_iacf, medeleg_iadm};
assign mideleg        = {mideleg_dpu, 4'h0, 1'b0, 1'b0, mideleg_sei, 1'b0, 1'b0, 1'b0, mideleg_sti, 1'b0, 1'b0, 1'b0, mideleg_ssi, 1'b0};

assign mstatush       = 32'h00000000;
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
assign mtval2         = 32'h00000000;   // Optional: not implemented

// NMI control signals
assign nmi_detect            = nmi_r & mnstatus_nmie  & NMI_EN & ~nmi_suppress_post_mnret;
// When NMI_EN=0, a lockup state can only be exited via reset.
// With NMI_EN=1, marv_ctl_i[3]=1 enables the documented NMI-escape route.
assign nmi_escape_lockup_cfg = marv_ctl_i[3]          & NMI_EN;


// Mux read data
assign traps_rdata_o  = ({32{mstatus_sel }}  & mstatus  ) |     // Machine Trap Setup
                        ({32{medeleg_sel }}  & medeleg  ) |
                        ({32{mideleg_sel }}  & mideleg  ) |
                        ({32{mie_sel     }}  & mie      ) |
                        ({32{mtvec_sel   }}  & mtvec    ) |
                        ({32{mstatush_sel}}  & mstatush ) |
                        ({32{medelegh_sel}}  & medelegh ) |

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
assign   excp_detect_in_if     =  if_excp_inst_address_misaligned_i;
assign   excp_detect_in_id     = (id_excp_ebreak_i | id_excp_ecall_i | id_excp_inst_access_fault_i       | id_excp_illegal_inst_i);
assign   excp_detect_in_ex     = (ex_excp_store_address_misaligned_i | ex_excp_load_address_misaligned_i | ex_excp_illegal_inst_i);
assign   excp_detect_in_wb     = (wb_excp_store_access_fault_i       | wb_excp_load_access_fault_i                               );

// Sync LSU exception (misalign in EX, access-fault in WB) that aborts any in-flight
// Zcmp UOP sequence. Excludes illegal-inst because UOP-issued ops are synthesised
// and cannot be illegal. Consumed by arv_decode to clear the UOP control flops.
assign   ex_uop_excp_abort_o   = ex_excp_load_address_misaligned_i  |
                                 ex_excp_store_address_misaligned_i |
                                 wb_excp_load_access_fault_i        |
                                 wb_excp_store_access_fault_i       ;

// Stop commands
assign   if_stop_cmd_o         = (in_lockup & ~(nmi_detect & nmi_escape_lockup_cfg));
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
                                 wb_excp_store_access_fault_i,                               // bit:  9      // WB - cause: 7
                                 wb_excp_load_access_fault_i,                                // bit:  8      // WB - cause: 5
                                 1'b0,                                                       // bit:  7      //    - cause: 3
                                 id_excp_ebreak_i,                                           // bit:  6      // ID - cause: 3
                                 id_excp_ecall_i,                                            // bit:  5      // ID - cause: 8, 9, 11
                                 if_excp_inst_address_misaligned_i,                          // bit:  4      // IF - cause: 0
                                 ex_excp_illegal_inst_i & ~excp_detect_in_wb,                // bit:  3      // EX - cause: 2  (older WB-acf wins)
                                 id_excp_illegal_inst_i,                                     // bit:  2      // ID - cause: 2
                                 id_excp_inst_access_fault_i,                                // bit:  1      // ID - cause: 1
                                 1'b0                                                        // bit:  0      //    - cause: 3
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
                                 excp_vector_highest[8],                                                     // WB    - cause:  5
                                 excp_vector_highest[10],                                                    // EX    - cause:  4
                                (excp_vector_highest[0] | excp_vector_highest[6] | excp_vector_highest[7]),  // ID    - cause:  3
                                 excp_vector_highest[2] | excp_vector_highest[3],                            // ID/EX - cause:  2
                                 excp_vector_highest[1],                                                     // ID    - cause:  1
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
//  |  M (already in exception trap) | Exception  | (ignored)      |  Enter lockup       |
//  |  S (already in exception trap) | Exception  | (ignored)      |  M-mode             |
//  +------------------------------------------------------------------------------------+

// Delegation is ignored when already in M-mode or when in an S-mode exception handler.
// Use in_s_excp_trap (NOT in_s_trap) here: an S-mode IRQ handler that legitimately faults
// on a delegable exception must be allowed to have the nested exception delegated to S-mode
// Blocking on in_s_excp_trap still protects against the dangerous case: nested exception inside
// an S-mode exception handler would clobber sepc/scause/stval before software has saved them.
assign   excp_ignore_deleg  = current_in_machine | (current_in_supervisor & in_s_excp_trap);

// Go to lockup state if an M-mode exception is raised while already in an M-mode exception handler.
// Uses in_m_excp_trap (cleared on mret only) so nested M-mode exceptions after returning from a
// nested handler are correctly detected.
//
// Two absorb terms suppress a FALSE lockup on the drainage of an aborted Zcmp UOP:
//   ~trap_branch_detect_r : covers the trap-branch cycle itself, before the new
//                           lockup_dph_drain_r flop has had an edge to sample.
//   ~lockup_dph_drain_r   : holds the absorb open while the trailing in-flight AHB
//                           data phase of the aborted UOP is still draining. The
//                           DPH error completes one or more cycles after the trap
//                           is taken (latency scales with interconnect depth, e.g.
//                           -gahb), so a fixed 1-cycle mask was too narrow.
// A GENUINE handler double-fault still locks up: it occurs only after the handler
// has executed an instruction, long after lockup_dph_drain_r has cleared, and the
// flop re-arms ONLY on a new trap-branch (never on handler loads/stores).
assign   go_to_lockup       = (|excp_vector_prio) & (current_in_machine & in_m_excp_trap)
                              & ~trap_branch_detect_r & ~lockup_dph_drain_r;

// Detect if exception goes in M or S mode
assign   excp_detect        = |(excp_vector_prio);
assign   excp_detect_to_m   = |(excp_vector_cause & ~excp_vector_deleg);
assign   excp_detect_to_s   = |(excp_vector_cause &  excp_vector_deleg);


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
assign   irq_vector_prio    =  {  1'h0                                                             ,  // bit[31]
                                ((sip_stip   & ~mideleg_sti    ) & sie_stie     & m_irq_global_en) |
                                ((sip_stip   &  mideleg_sti    ) & sie_stie     & s_irq_global_en) ,  // bit[30] STI  (cause  5) - lowest standard
                                  1'h0                                                             ,  // bit[29]
                                ((sip_ssip_eff & ~mideleg_ssi  ) & sie_ssie     & m_irq_global_en) |
                                ((sip_ssip_eff &  mideleg_ssi  ) & sie_ssie     & s_irq_global_en) ,  // bit[28] SSI  (cause  1)
                                  1'h0                                                             ,  // bit[27]
                                ((sip_seip   & ~mideleg_sei    ) & sie_seie     & m_irq_global_en) |
                                ((sip_seip   &  mideleg_sei    ) & sie_seie     & s_irq_global_en) ,  // bit[26] SEI  (cause  9)
                                  1'h0                                                             ,  // bit[25]
                                ( mip_mtip                       & mie_mtie     & m_irq_global_en) ,  // bit[24] MTI  (cause  7) - mideleg has no bit for cause 7
                                  1'h0                                                             ,  // bit[23]
                                ( mip_msip                       & mie_msie     & m_irq_global_en) ,  // bit[22] MSI  (cause  3) - mideleg has no bit for cause 3
                                  1'h0                                                             ,  // bit[21]
                                ( mip_meip                       & mie_meie     & m_irq_global_en) ,  // bit[20] MEI  (cause 11) - highest standard
                                  4'h0                                                             ,
                                ((ip_pip[0]  & ~mideleg_dpu[0] ) & mie_mpie[0]  & m_irq_global_en) | ((ip_pip[0]  &  mideleg_dpu[0] ) & sie_spie[0]  & s_irq_global_en),
                                ((ip_pip[1]  & ~mideleg_dpu[1] ) & mie_mpie[1]  & m_irq_global_en) | ((ip_pip[1]  &  mideleg_dpu[1] ) & sie_spie[1]  & s_irq_global_en),
                                ((ip_pip[2]  & ~mideleg_dpu[2] ) & mie_mpie[2]  & m_irq_global_en) | ((ip_pip[2]  &  mideleg_dpu[2] ) & sie_spie[2]  & s_irq_global_en),
                                ((ip_pip[3]  & ~mideleg_dpu[3] ) & mie_mpie[3]  & m_irq_global_en) | ((ip_pip[3]  &  mideleg_dpu[3] ) & sie_spie[3]  & s_irq_global_en),
                                ((ip_pip[4]  & ~mideleg_dpu[4] ) & mie_mpie[4]  & m_irq_global_en) | ((ip_pip[4]  &  mideleg_dpu[4] ) & sie_spie[4]  & s_irq_global_en),
                                ((ip_pip[5]  & ~mideleg_dpu[5] ) & mie_mpie[5]  & m_irq_global_en) | ((ip_pip[5]  &  mideleg_dpu[5] ) & sie_spie[5]  & s_irq_global_en),
                                ((ip_pip[6]  & ~mideleg_dpu[6] ) & mie_mpie[6]  & m_irq_global_en) | ((ip_pip[6]  &  mideleg_dpu[6] ) & sie_spie[6]  & s_irq_global_en),
                                ((ip_pip[7]  & ~mideleg_dpu[7] ) & mie_mpie[7]  & m_irq_global_en) | ((ip_pip[7]  &  mideleg_dpu[7] ) & sie_spie[7]  & s_irq_global_en),
                                ((ip_pip[8]  & ~mideleg_dpu[8] ) & mie_mpie[8]  & m_irq_global_en) | ((ip_pip[8]  &  mideleg_dpu[8] ) & sie_spie[8]  & s_irq_global_en),
                                ((ip_pip[9]  & ~mideleg_dpu[9] ) & mie_mpie[9]  & m_irq_global_en) | ((ip_pip[9]  &  mideleg_dpu[9] ) & sie_spie[9]  & s_irq_global_en),
                                ((ip_pip[10] & ~mideleg_dpu[10]) & mie_mpie[10] & m_irq_global_en) | ((ip_pip[10] &  mideleg_dpu[10]) & sie_spie[10] & s_irq_global_en),
                                ((ip_pip[11] & ~mideleg_dpu[11]) & mie_mpie[11] & m_irq_global_en) | ((ip_pip[11] &  mideleg_dpu[11]) & sie_spie[11] & s_irq_global_en),
                                ((ip_pip[12] & ~mideleg_dpu[12]) & mie_mpie[12] & m_irq_global_en) | ((ip_pip[12] &  mideleg_dpu[12]) & sie_spie[12] & s_irq_global_en),
                                ((ip_pip[13] & ~mideleg_dpu[13]) & mie_mpie[13] & m_irq_global_en) | ((ip_pip[13] &  mideleg_dpu[13]) & sie_spie[13] & s_irq_global_en),
                                ((ip_pip[14] & ~mideleg_dpu[14]) & mie_mpie[14] & m_irq_global_en) | ((ip_pip[14] &  mideleg_dpu[14]) & sie_spie[14] & s_irq_global_en),
                                ((ip_pip[15] & ~mideleg_dpu[15]) & mie_mpie[15] & m_irq_global_en) | ((ip_pip[15] &  mideleg_dpu[15]) & sie_spie[15] & s_irq_global_en)
                               };

// Only keep the highest priority exception
assign   irq_vector_highest =     irq_vector_prio & ~(irq_vector_prio - 32'h00000001);

// Reordered by cause (1-hot signal)
// Maps from priority-ordered bit positions back to cause-code-indexed positions.
// Standard interrupts were reordered for spec-compliant priority (MEI>MSI>MTI>SEI>SSI>STI),
// so the mapping is no longer a simple bit-reversal for causes 1,3,5,9.
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
//  +------------------------------------------------------------------------------------+
//  | Current Privilege              | Trap Cause | Delegation Bit | Taken In            |
//  |--------------------------------+------------+----------------+---------------------|
//  |  M                             | Interrupt  | (ignored)      |  M-mode             |
//  |  S                             | Interrupt  | MI=1           |  S-mode             |
//  |  S                             | Interrupt  | MI=0           |  M-mode             |
//  |  U                             | Interrupt  | MI=1           |  S-mode             |
//  |  U                             | Interrupt  | MI=0           |  M-mode             |
//  +------------------------------------------------------------------------------------+

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
wire     csr_irq_config_wr  = mstatus_wr | sstatus_wr | mie_wr | sie_wr | mip_wr | sip_wr | mideleg_wr | medeleg_wr;

// Post-MRET IRQ suppression: suppress IRQ detection after MRET until
// the first valid instruction arrives in ID. This guarantees the MEPC
// instruction enters EX before a new IRQ can fire, preventing livelock
// where aggressive IRQs catch the same instruction in ID after every MRET
// (pipeline drain sees EX as ready, traps immediately, MEPC unchanged).
// Gated by marv_ctl_i[2] (livelock protection enable).
// Must also require pipeline_drained_for_id (EX+WB ready) so the instruction actually
// dispatches the same cycle suppress clears. Without this, a random ALU stall (-rsalu)
// can make the instruction valid-but-not-dispatched; suppress clears, next cycle irq fires
// at the same id_pc_i (instruction not consumed), causing MEPC to repeat - livelock.
// Also gate on ~ex_uop_jt_active_i: cm.jt/cm.jalt has a non-killable AHB phase (JT_DPH/JT_ALU)
// where MEPC is saved as ex_pc_i (the cm.jt PC).
// MNRET must arm post-trap IRQ suppression the same way MRET does. Without
// the (mnret_taken & NMI_EN) term, an IRQ pending at MNRET completion traps
// on the exact PC the mnret resumed to - same livelock vector as the MRET
// case. The NMI_EN guard keeps mnret_taken=0 hard-wired when Smrnmi is off.
wire     irq_suppress_post_mret;
wire     irq_suppress_clr  = irq_suppress_post_mret & id_instruction_valid_i & pipeline_drained_for_id & ~trap_branch_detect_r & ~ex_uop_jt_active_i & ~id_uop_jt_start_i;
wire     irq_suppress_post_mret_en  = ((mret_taken | (mnret_taken & NMI_EN)) & marv_ctl_i[2]) | irq_suppress_clr;
wire     irq_suppress_post_mret_nxt = ((mret_taken | (mnret_taken & NMI_EN)) & marv_ctl_i[2]) ? 1'b1 : 1'b0;

arv_dff #(.ARST_EN(ARST_EN)) u_irq_suppress_post_mret (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(irq_suppress_post_mret_en),
                                                       .d_i (irq_suppress_post_mret_nxt),
                                                       .q_o (irq_suppress_post_mret));

// NMI livelock protection: after mnret, suppress nmi_detect for one valid instruction.
// Without this, if nmi_i stays asserted, mnret immediately re-enables NMIE and the NMI
// handler is re-entered before executing a single instruction. Gated by marv_ctl_i[2].
generate
    if (NMI_EN) begin : gen_nmi_suppress
        wire nmi_suppress_post_mnret_reg;
        wire nmi_suppress_clr = nmi_suppress_post_mnret_reg & id_instruction_valid_i & ~trap_branch_detect_r;
        wire nmi_suppress_post_mnret_reg_en  = (mnret_taken & marv_ctl_i[2]) | nmi_suppress_clr;
        wire nmi_suppress_post_mnret_reg_nxt = (mnret_taken & marv_ctl_i[2]) ? 1'b1 : 1'b0;
        arv_dff #(.ARST_EN(ARST_EN)) u_nmi_suppress_post_mnret_reg (
                               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(nmi_suppress_post_mnret_reg_en),
                                                                    .d_i (nmi_suppress_post_mnret_reg_nxt),
                                                                    .q_o (nmi_suppress_post_mnret_reg));
        assign nmi_suppress_post_mnret = nmi_suppress_post_mnret_reg;
    end else begin : gen_nmi_suppress_disabled
        assign nmi_suppress_post_mnret = 1'b0;
    end
endgenerate

// Detect if exception goes in M or S mode
assign   irq_detect        = |(irq_vector_cause) & ~csr_irq_config_wr & ~irq_suppress_post_mret;
assign   irq_detect_to_m   = |(irq_vector_cause  & ~irq_vector_deleg);
assign   irq_detect_to_s   = |(irq_vector_cause  &  irq_vector_deleg);


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
assign   mret_taken        =  id_opcode_mret_i   & ~trap_pending_o;
assign   sret_taken        =  id_opcode_sret_i   & ~trap_pending_o  & SU_MODE_EN;
assign   mnret_taken       =  id_opcode_mnret_i  & ~trap_pending_o  & NMI_EN;

//------------------------------------------------------------------------
// Exception/interrupt/NMI type classification (latched when trap_pending first asserts)
// Priority: NMI > synchronous-exception > IRQ
//   - NMI is non-maskable, highest priority
//   - A sync exception belongs to the instruction in flight and wins over a same-cycle
//     IRQ (see trap_is_irq formula: `irq_detect & ~excp_detect & ~nmi_detect`)
//   - IRQ wins only when no sync exception is pending this cycle
//------------------------------------------------------------------------
// Guard against simultaneous IRQ and MRET/SRET/MNRET: if a ret instruction is
// dispatching this cycle, do NOT set trap_pending_o. The ret's own branch fires
// (trap_branch_detect_r goes high next cycle, suppressing the next-cycle stall),
// and irq_suppress_post_mret is set next cycle so the IRQ re-fires safely after
// the first post-ret instruction. Without this guard, an IRQ detected on the same
// cycle as MRET would set trap_pending_o while mret_taken also fires, corrupting
// MSTATUS and preventing the MRET return from completing.

wire trap_pending_set      = (excp_detect | irq_detect | nmi_detect)                               &    // a trap source is firing this cycle
                             (~trap_pending_o                                                           // normal path: no trap already pending
                                | (in_lockup & nmi_detect & nmi_escape_lockup_cfg & ~trap_is_nmi)) &    // OR: re-arm as NMI when in lockup with escape enabled
                              ~trap_branch_detect_r                                                &    // not the cycle of an outgoing trap-branch redirect
                              ~mret_taken & ~sret_taken & ~mnret_taken;                                 // not concurrent with an xRET (preserves MSTATUS/MIE handoff)

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

wire [4:0] trap_cause_latched_nxt = nmi_detect                  ? 5'h0             :   // NMI cause not used (mncause=0)
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
//------------------------------------------------------------------------
wire        irq_mepc_settle      =  trap_pending_o & trap_is_irq & uop_wait_for_id_valid  & id_instruction_valid_i;
wire        muldiv_mepc_settle   =  trap_pending_o & trap_is_irq & muldiv_kill_suppress   & id_instruction_valid_i;
wire [31:0] trap_pc_to_save      =  (id_wfi_active_i & nmi_detect)    ?   ex_pc_i + 32'd4 : // NMI+WFI: save WFI+4
                                    (nmi_detect & ex_uop_jt_active_i) ?   ex_pc_i         : // NMI+JT : save cm.jt PC
                                     excp_detect_in_wb                ?   wb_pc_i         : // sync excp in WB: faulting PC (NMI/IRQ resumable)
                                     excp_detect_in_ex                ?   ex_pc_i         : // sync excp in EX: faulting PC (NMI/IRQ resumable)
                                     excp_detect_in_if                ?   ex_pc_i         : // sync excp in IF (inst-addr-misalign).
                                     nmi_detect                       ?   id_pc_i         : // NMI (no in-flight sync excp): save ID PC
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
//   - Load/store access fault (WB):              faulting data address
//   - All others (illegal, ECALL, EBREAK, IRQ):  0
//------------------------------------------------------------------------
wire [31:0] mtval_save_nxt   =  excp_detect_in_wb                                                       ? wb_data_addr_i        :
                               (ex_excp_load_address_misaligned_i | ex_excp_store_address_misaligned_i) ? ex_data_addr_i        :
                                id_excp_inst_access_fault_i                                             ? id_inst_fault_addr_i  :
                                if_excp_inst_address_misaligned_i                                       ? id_pc_i               :
                                                                                                           32'h0;

// Only address-based exceptions produce a non-zero mtval; ECALL/EBREAK/illegal/IRQ all write 0.
wire  mtval_exception_active =  excp_detect_in_wb                  |
                                ex_excp_load_address_misaligned_i  |
                                ex_excp_store_address_misaligned_i |
                                if_excp_inst_address_misaligned_i  |
                                id_excp_inst_access_fault_i;

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
assign pipeline_drained_for_wb  = 1'b1;

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
                                 trap_pending_o & ex_alu_is_killable_i & ~(muldiv_kill_suppress & livelock_prot_en);

// UOP kill: abort mid-sequence push/pop or table jump for low-latency IRQ response.
// The is_killable signal from the sequencer ensures AHB safety (data phase complete).
// Livelock prevention: after killing a UOP, suppress the next kill until the restarted
// sequence completes naturally. Without this, rapid IRQs can kill the same sequence
// repeatedly (especially long ones like CM.POPRET), preventing forward progress.
wire  uop_kill_suppress;
wire  uop_kill_wait_done;
wire uop_kill_restarted  =  uop_kill_suppress & ~uop_kill_wait_done &  ex_uop_is_killable_i;  // Restarted UOP sequence is running
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
assign trap_kill_uop_o        = ((irqkill_uop_en & trap_is_irq) | trap_is_nmi) &
                                 trap_pending_o & ex_uop_is_killable_i & ~(uop_kill_suppress & livelock_prot_en);

wire pipeline_drained_for_irq = (ex_alu_ready_i  | trap_kill_muldiv_o) &
                                 ex_ldst_ready_i & ex_csr_ready_i      &
                                (ex_uop_ready_i  | trap_kill_uop_o)    &
                                 wb_ready;

// UOP branch drain: when a UOP has a pending branch during a trap,
// wait for the branch redirect to fire AND the branch target instruction
// to arrive in the ID stage, so id_pc_i has the correct value for MEPC.
wire jt_load_fault_in_ex = ex_uop_jt_active_i & wb_excp_load_access_fault_i;

wire uop_wait_for_id_valid_en  = trap_taken | jt_load_fault_in_ex | (ex_uop_take_branch_i & trap_stall_raw) | (uop_wait_for_id_valid & id_instruction_valid_i);
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
                                 (trap_stage[3] & pipeline_drained_for_wb)   |
                                 (trap_is_irq   & pipeline_drained_for_irq)  |
                                 (trap_is_nmi   & pipeline_drained_for_irq)) & pipeline_drained_for_uop;  // NMI drains like IRQ

//------------------------------------------------------------------------
// Trap stage latch: records which pipeline stage detected the exception
//------------------------------------------------------------------------
wire       trap_stage_en  = trap_taken | ~trap_pending_o;
wire [3:0] trap_stage_nxt = trap_taken ? 4'b0000 : {excp_detect_in_wb, excp_detect_in_ex, excp_detect_in_id, excp_detect_in_if};

arv_dff #(.WIDTH(4), .ARST_EN(ARST_EN)) u_trap_stage (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_stage_en),
                                                      .d_i (trap_stage_nxt),
                                                      .q_o (trap_stage));

//------------------------------------------------------------------------
// Trap pending: stalls decode while waiting for pipeline drain
// When trap_taken fires, trap_branch_detect redirects fetch AND decode
// clears stale EX pipeline registers (CSR/LDST control), so the faulting
// instruction can no longer re-trigger exception detection.
//------------------------------------------------------------------------
wire trap_pending_o_en  = trap_taken | trap_pending_set;
wire trap_pending_o_nxt = trap_taken ? 1'b0 : 1'b1;

arv_dff #(.ARST_EN(ARST_EN)) u_trap_pending_o (
          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(trap_pending_o_en),
                                               .d_i (trap_pending_o_nxt),
                                               .q_o (trap_pending_o));

// Combinational stall: includes immediate EX/WB exception detection and IRQs
// to prevent the pipeline from advancing in the same cycle the exception
// fires (before trap_pending_o registers on the next clock edge).
// Exception: when a UOP has a pending branch, suppress the stall so the
// branch redirect can fire (id_instruction_request_o stays high for one cycle).
assign   trap_stall_raw       =  trap_pending_o | ((excp_detect_in_ex | excp_detect_in_wb | irq_detect | nmi_detect) & ~trap_pending_o);
assign   trap_stall_o         = (trap_stall_raw | trap_branch_detect_r) & (~ex_uop_has_branch_i | jt_load_fault_in_ex);

//------------------------------------------------------------------------
// Trap taken: fires when pending and pipeline is drained
//------------------------------------------------------------------------
assign   trap_taken           =  trap_pending_o & trap_drained;

//------------------------------------------------------------------------
// Write-back suppression for faulting instructions
// Suppress EX-stage writes (ALU/CSR) when EX-stage exception detected
// Suppress WB-stage writes (load) when WB-stage exception detected
// ID/IF exceptions and interrupts do NOT suppress: older in-flight
// instructions must complete normally during pipeline drain
//------------------------------------------------------------------------
assign   trap_kill_ex_o       =  trap_pending_o & trap_stage[2];
assign   trap_kill_wb_o       =  trap_pending_o & trap_stage[3];

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
// marv_ctl[4]: force the live-wake high to keep hclk_en_o asserted
//------------------------------------------------------------------------
assign   wfi_wakeup_live_o    = (marv_ctl_i[4]                                 )  |
                                (irq_m_software_i   & mie_msie                 )  |
                                (irq_s_software_i   & sie_ssie  & SU_MODE_EN   )  |
                                (sip_ssip_eff       & sie_ssie  & SU_MODE_EN   )  |
                                (irq_m_timer_i      & mie_mtie                 )  |
                                (sip_stip           & sie_stie  & SU_MODE_EN   )  |
                                (irq_m_external_i   & mie_meie                 )  |
                                (irq_s_external_i   & sie_seie                 )  |
                                (sip_seip_sw        & sie_seie                 )  |
                                (|(irq_platform_i   & mie_mpie                ))  |
                                (|(ip_pip           & mie_mpie                ))  |
                                (nmi_i & mnstatus_nmie & NMI_EN & ~nmi_suppress_post_mnret);

//------------------------------------------------------------------------
// Trap target computation (combinational for decode branch infrastructure)
//------------------------------------------------------------------------
assign   trap_target_direct   = trap_to_m ? {mtvec_base, 2'b00} : {stvec_base, 2'b00};
assign   trap_target_vectored = trap_target_direct + {25'b0, trap_cause_latched, 2'b00};
assign   use_vectored         = trap_is_irq & (trap_to_m ? (mtvec_mode==2'b01) : (stvec_mode==2'b01));

assign   trap_branch_target_comb = mnret_taken  ? {mnepc_mnepc, 1'b0}  :
                                   mret_taken   ? {mepc_mepc,   1'b0}  :
                                   sret_taken   ? {sepc_sepc,   1'b0}  :
                                   trap_is_nmi  ? nmi_vector_i         :
                                   use_vectored ? trap_target_vectored :
                                                  trap_target_direct;

assign   trap_branch_detect_comb = trap_taken | mret_taken | sret_taken | mnret_taken;

// Registered outputs: target/detect delayed one cycle for timing improvement.
// trap_stall_o is extended by trap_branch_detect_r to keep decode frozen
// through the redirect cycle (since trap_pending_o clears one cycle earlier).
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_trap_branch_target_r (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(trap_branch_target_comb), .q_o(trap_branch_target_r));
arv_dff #(.ARST_EN(ARST_EN)) u_trap_branch_detect_r (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(trap_branch_detect_comb), .q_o(trap_branch_detect_r));

assign   trap_branch_target_o = trap_branch_target_r;
assign   trap_branch_detect_o = trap_branch_detect_r;

//------------------------------------------------------------------------
// In-trap state tracking
//
// in_m_excp_trap: set when an exception is taken to M-mode; cleared on mret.
//   Not cleared on sret - sret only returns from S-mode, so an in-flight
//   M-mode exception handler is unaffected.
//   Also cleared when an NMI escapes lockup: the lockup was caused by a
//   double-exception in M-mode, and the NMI handler must be able to take
//   further exceptions without immediately re-triggering lockup.
//
// in_s_excp_trap: set ONLY when an exception (not an IRQ) is taken to S-mode;
//   cleared on sret only. Used by excp_ignore_deleg to block delegation of a
//   nested exception while sepc/scause are still live for an in-progress
//   S-mode exception handler. IRQ handlers are intentionally NOT protected:
//   the spec allows nested S-IRQ -> delegable-exception (software saves
//   sepc/scause on entry and SIE blocks further S-IRQs, but not exceptions).
//
//------------------------------------------------------------------------
wire  m_excp_trap_set    =  trap_taken & trap_to_m & ~trap_is_irq & ~trap_is_nmi;
wire  s_excp_trap_set    =  trap_taken & trap_to_s & ~trap_is_irq;
wire  nmi_escapes_lockup =  in_lockup  & trap_taken & trap_is_nmi & nmi_escape_lockup_cfg;

wire in_m_excp_trap_en  = m_excp_trap_set | mret_taken | nmi_escapes_lockup;
wire in_m_excp_trap_nxt = m_excp_trap_set ? 1'b1 :
                          mret_taken      ? 1'b0 :
                                            1'b0;  // NMI escapes lockup: clear stale exception context
arv_dff #(.ARST_EN(ARST_EN)) u_in_m_excp_trap (
           .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(in_m_excp_trap_en), .d_i(in_m_excp_trap_nxt), .q_o(in_m_excp_trap));

wire in_s_excp_trap_en  = s_excp_trap_set | sret_taken;
wire in_s_excp_trap_nxt = s_excp_trap_set ? 1'b1 : 1'b0;
arv_dff #(.ARST_EN(ARST_EN)) u_in_s_excp_trap (
          .clk_i(hclk_i), .rst_n_i(hresetn_i),  .en_i(in_s_excp_trap_en), .d_i(in_s_excp_trap_nxt), .q_o(in_s_excp_trap));

wire in_lockup_en  = go_to_lockup | nmi_escapes_lockup;
wire in_lockup_nxt = go_to_lockup ? 1'b1 : 1'b0;  // NMI escapes lockup if configured
arv_dff #(.ARST_EN(ARST_EN)) u_in_lockup (
           .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(in_lockup_en),      .d_i(in_lockup_nxt),      .q_o(in_lockup));

// Lockup absorb window: a Zcmp-UOP abort can leave an AHB DPH in flight that
// completes with an error one or more cycles after the trap is taken (latency
// scales with interconnect depth, e.g. -gahb). That trailing error is drainage
// of the aborted UOP, not a handler fault. Arm at the trap-branch cycle and
// hold while the in-flight DPH is still draining (wb_dph_ongoing_i); release
// once it has fully drained -- which is always before the handler executes any
// load. Interconnect-depth-independent (bounds on the DPH, not a cycle count).
wire lockup_dph_drain_r_en  = trap_branch_detect_r | ~wb_dph_ongoing_i;
wire lockup_dph_drain_r_nxt = trap_branch_detect_r ? 1'b1 : 1'b0;
arv_dff #(.ARST_EN(ARST_EN)) u_lockup_dph_drain_r (
           .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(lockup_dph_drain_r_en), .d_i(lockup_dph_drain_r_nxt), .q_o(lockup_dph_drain_r));

//------------------------------------------------------------------------
// Privilege mode updates
//------------------------------------------------------------------------
assign   priv_mode_next_comb   = !SU_MODE_EN              ? 2'b11               :
                                 (trap_taken & trap_to_m) ? 2'b11               :
                                 (trap_taken & trap_to_s) ? 2'b01               :
                                  mnret_taken             ? mnstatus_mnpp       :
                                  mret_taken              ? mstatus_mpp         :
                                  sret_taken              ? {1'b0, sstatus_spp} :
                                                            priv_mode_current_i ;

assign   priv_mode_update_comb = trap_taken | mret_taken | sret_taken | mnret_taken;

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
// spec Smrnmi requires the hart to behave as though MPRV were clear when
// NMIE=0. The (NMI_EN ? ... : 1'b1) guard keeps MPRV unconditional when
// Smrnmi is absent (mnstatus_nmie is tied 0 in that build).
assign   priv_mode_ldst_o  = !SU_MODE_EN                                                           ? 2'b11              :
                             (mstatus_mprv & current_in_machine & (NMI_EN ? mnstatus_nmie : 1'b1)) ? mstatus_mpp        :
                                                                                                     priv_mode_current_i;


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
wire       nmi_vector_unused       = (NMI_EN == 0) ? |nmi_vector_i : 1'b0;  // nmi_vector_i only used when NMI_EN=1

assign     trap_taken_o            =  trap_taken;
assign     trap_is_irq_o           =  trap_is_irq;


endmodule // arv_csr_traps

`default_nettype wire

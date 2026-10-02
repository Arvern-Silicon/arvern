//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_csr_top
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_csr_top.v
// Module Description : RISC-V CSRs: top-level address decode, read mux, write-data composition + CSR control fan-out
//----------------------------------------------------------------------------
`default_nettype none

module  arv_csr_top (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// JVT CSR OUTPUT (ZCMT)
    output wire    [31:0] jvt_base_o,

// INTERFACE FOR THE CSR INSTRUCTIONS
    input  wire     [3:0] ex_dec_csr_control_i,
    input  wire    [31:0] ex_dec_csr_rs1_operand_i,
    input  wire    [11:0] ex_dec_csr_reg_addr_i,

// REGISTER WRITE DATA TO INTEGER REGISTERS
    output wire           ex_csr_reg_dest_wr_o,
    output wire    [31:0] ex_csr_reg_dest_wdata_o,

// INTERFACE TO CUSTOM CSR REGISTERS
    input  wire    [31:0] ccsr_rdata_i,
    output wire    [10:0] ccsr_bank_o,
    output wire    [63:0] ccsr_reg_sel_o,
    output wire    [31:0] ccsr_wdata_o,
    output wire           ccsr_wen_o,

// INTERFACE TO INSTRUCTION FETCH AND INST DECODER
    input  wire           id_opcode_mret_i,
    input  wire           id_opcode_sret_i,
    input  wire           id_opcode_mnret_i,
    output wire           ex_csr_ready_o,
    output wire           cfg_timeout_wait_o,
    output wire           cfg_trap_sret_o,

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
    input  wire           id_issue_active_nodbg_i,
    input  wire           id_excp_ecall_i,
    input  wire           ex_excp_load_address_misaligned_i,
    input  wire           ex_excp_store_address_misaligned_i,
    input  wire           ex_excp_load_access_fault_i,
    input  wire           ex_excp_store_access_fault_i,
    input  wire           wb_bus_error_load_i,
    input  wire           wb_bus_error_store_i,

// PIPELINE READY SIGNALS (FOR DRAIN DETECTION)
    input  wire           ex_alu_ready_i,
    input  wire           ex_ldst_ready_i,
    input  wire           ex_ldst_unresolved_i,        // EX load/store whose fault status is not yet known (pass-through to arv_csr_traps)
    input  wire           ex_pmp_refetch_i,            // PMP CSR write in EX: prefetched parcels are discarded (pass-through to arv_csr_traps)
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
    input  wire    [31:0] wb_data_addr_i,
    input  wire           wb_uop_sourced_i,

// SDTRIG LOAD/STORE DATA-ADDRESS WATCHPOINT TAPS
    input  wire           ex_is_load_i,
    input  wire           ex_is_store_i,
    input  wire     [2:0] ex_size_i,
    output wire           trig_ls_fire_o,

// WRITE-BACK SUPPRESSION
    output wire           trap_kill_ex_o,

// IRQ KILL FOR MULTI-CYCLE OPERATIONS
    input  wire           ex_alu_is_killable_i,
    input  wire           ex_uop_is_killable_i,
    input  wire           ex_uop_kill_window_i,
    input  wire           ex_uop_jt_active_i,
    input  wire           wb_uop_seq_alive_i,
    input  wire           wb_uop_jt_sourced_i,
    input  wire           id_uop_jt_start_i,
    output wire           trap_kill_muldiv_o,
    output wire           trap_kill_uop_o,
    output wire           trap_kill_uop_hold_o,
    output wire           ex_uop_excp_abort_o,
    output wire           ex_uop_jt_fault_o,

// OTHERS
    input  wire     [7:0] hartid_i,
    input  wire           init_pc_i,
    input  wire    [31:0] reset_vector_i,
    output wire     [1:0] if_priv_mode_o,
    output wire     [1:0] priv_mode_ldst_o,

// PMP ENTRY STATE (TO THE ADDRESS CHECKERS)
    output wire  [16*8-1:0] pmp_cfg_o,
    output wire [16*32-1:0] pmp_addr_o,
    output wire             pmp_mml_o,
    output wire             pmp_mmwp_o,


// NMI (SMRNMI)
    input  wire           nmi_i,

// ZICNTR TIME INTERFACE
    output wire           time_req_o,
    input  wire           time_gnt_i,
    input  wire    [63:0] time_val_i,

// INSTRUCTION RETIRE (FOR MINSTRET)
    input  wire           inst_retired_i,

// HPM EVENTS
    input  wire     [7:0] id_hpm_events_i,
    input  wire     [7:0] hpm_platform_events_i,

// EXTERNAL DEBUG (Sdext)
    input  wire           debug_req_i,
    input  wire           resume_req_i,
    input  wire           resethaltreq_i,
    input  wire           dm_csr_access_i,
    input  wire     [1:0] dm_csr_sel_i,
    input  wire           dm_csr_wen_i,
    input  wire    [31:0] dm_csr_wdata_i,
    output wire    [31:0] dm_csr_rdata_o,
    input  wire           dm_acsr_active_i,
    input  wire           dm_acsr_wen_i,
    input  wire    [11:0] dm_acsr_addr_i,
    input  wire    [31:0] dm_acsr_wdata_i,
    output wire    [31:0] dm_acsr_rdata_o,
    output wire           dm_acsr_fault_o,
    output wire           debug_mode_o,
    output wire           debug_halt_active_o,
    output wire           debug_issue_hold_o,       // EARLY flop-sourced issue hold for decode (see arv_csr_debug)
    output wire           debug_ebreak_cfg_o,       // dcsr.ebreak* enable, current privilege (see arv_csr_debug)
    output wire           debug_halted_o,
    output wire           trig_break_issue_kill_o,
    output wire           debug_stoptime_o

);

// USER PARAMETERs
//======================================
parameter                 ARST_EN             =  1'b1;        // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 C_EXT_EN            =  1'b0;        // Compressed instructions enabled
parameter                 M_EXT_EN            =  1'b0;        // M extension enabled (multiply+divide)
parameter                 B_EXT_EN            =  1'b0;        // B extension enabled (bit manipulation)
parameter                 ZCMT_EN             =  1'b0;        // Zcmt extension enable (table jumps)
parameter                 MUL_1C_EN           =  1'b0;        // Single-cycle multiplier
parameter                 MUL_4C_EN           =  1'b0;        // Four-cycle multiplier
parameter                 MUL_16C_EN          =  1'b0;        // Sixteen-cycle multiplier
parameter                 DIV_12C_EN          =  1'b0;        // Radix-8 divider (12 cycles)
parameter                 DIV_17C_EN          =  1'b0;        // Radix-4 divider (17 cycles)
parameter                 DIV_33C_EN          =  1'b0;        // Radix-2 divider (33 cycles)
parameter                 CCSR_EN             =  1'b1;        // Enable Custom-CSR interface
parameter                 RV32I_EN            =  1'b1;        // RV32I base ISA (RV32E if 0)
parameter                 SU_MODE_EN          =  1'b1;        // S+U privilege modes (0=M-only, 1=M+S+U)
parameter                 DEBUG_EN            =  1'b0;        // External debug (Sdext)
parameter                 DM_TRIGGER_EN       =  1'b0;        // Sdtrig trigger CSR file present (DEBUG_EN & DM_TRIGGER_NR>0)
parameter           [3:0] DM_TRIGGER_NR       =  4'd0;        // Number of Sdtrig hardware triggers (1-8 when DM_TRIGGER_EN)
parameter                 ZICNTR_EN           =  1'b0;        // Zicntr extension enable (cycle, time, instret)
parameter           [3:0] ZIHPM_NR            =  4'h0;        // Zihpm: number of HPM counters (0-8)
parameter                 SINGLE_CYCLE_BRANCH =  1'b1;        // 1=zero-bubble taken branch (max IPC); 0=one-bubble (max Fmax)
parameter          [23:0] RTL_VERSION         = 24'h000000;   // {major, minor, patch} exposed through mimpid[31:8]
parameter           [2:0] C_EXT_LEVEL         =  3'd0;        // C_EXTENSION level 0-4 (marv_cfg)
parameter           [2:0] B_EXT_LEVEL         =  3'd0;        // B_EXTENSION level 0-4 (marv_cfg)
parameter           [4:0] PMP_NR              =  5'd0;        // Writable PMP entries: 0, 4, 8 or 16


//////======================================================================================================================//////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////======================================================================================================================//////

// marv_cfg[7:6] encoding, derived here so arvern passes ONE parameter and the two
// consumers cannot disagree about what a given count means.
localparam          [1:0] PMP_NR_FIELD        = (PMP_NR == 5'd16) ? 2'd3 :
                                                (PMP_NR == 5'd8 ) ? 2'd2 :
                                                (PMP_NR == 5'd4 ) ? 2'd1 : 2'd0;

localparam                ZIHPM_NR_EN         = (ZIHPM_NR >  0) ? 1'b1  : 1'b0;
localparam          [7:0] HPM_IMPL_MASK       = (ZIHPM_NR == 0) ? 8'h00 :
                                                (ZIHPM_NR == 1) ? 8'h01 :
                                                (ZIHPM_NR == 2) ? 8'h03 :
                                                (ZIHPM_NR == 3) ? 8'h07 :
                                                (ZIHPM_NR == 4) ? 8'h0F :
                                                (ZIHPM_NR == 5) ? 8'h1F :
                                                (ZIHPM_NR == 6) ? 8'h3F :
                                                (ZIHPM_NR == 7) ? 8'h7F : 8'hFF;

wire                      is_active;
wire                      is_csrrw;
wire                      is_csrrs;
wire                      is_csrrc;

wire                      disable_read;
wire                      disable_write;

wire               [31:0] ccsr_value_read;
wire               [31:0] ids_value_read;
wire               [31:0] traps_value_read;
wire               [31:0] jvt_value_read;

wire                      bank_misa_en;
wire                      bank_ids_en;
wire                      bank_mtrap_setup;
wire                      bank_mtrap_handling;
wire                      bank_strap_setup;
wire                      bank_strap_handling;

wire               [63:0] register_select;
wire               [31:0] register_value_nxt;
wire                      sip_seip_sw_from_traps;
wire                      mip_seip_sw_rmw_nxt;

wire                      acc_priv_is_super;
wire                      acc_priv_is_hyper;
wire                      acc_priv_is_machine;

wire                [1:0] privilege_mode;
wire                      cfg_trap_vm;
wire                [1:0] privilege_mode_nxt;
wire                      privilege_mode_update;

wire                      machine_invalid;
wire                      hypervisor_invalid;
wire                      supervisor_invalid;
wire                      write_invalid;
wire                      hpm_csr_absent;
wire                      any_bank_known;
wire                      unimplemented_csr;
wire                      ex_excp_illegal_inst;
wire                [3:0] marv_ctl_reg;
wire               [31:0] marv_ctl_value_read;
wire               [31:0] marv_nmvec;
wire               [31:0] marv_nmvec_value_read;
wire                      bank_marv_cfg;
wire               [31:0] marv_cfg;
wire               [31:0] marv_cfg_value_read;
wire                      bank_nmi_handling;
wire                      bank_reset_vector;
wire               [31:0] reset_vector_value_read;
wire                      bank_marv_epc;
wire               [31:0] marv_epc_value_read;
wire                      bank_marv_eaddr;
wire               [31:0] marv_eaddr_value_read;
wire                      bank_marv_estat;
wire               [31:0] marv_estat_value_read;

wire               [31:0] counters_value_read;
wire                [2:0] mcounteren;
wire               [10:0] scounteren;
wire                      counters_csr_ready;
wire                      bank_mcycle;
wire                      bank_mcycleh;
wire                      bank_counter;
wire                      bank_counterh;
wire                      zicntr_access_denied;
wire                      zihpm_access_denied;

wire               [31:0] hpm_value_read;
wire               [31:0] trigger_value_read;
wire               [31:0] pmp_value_read;
wire           [16*8-1:0] pmp_cfg;
wire          [16*32-1:0] pmp_addr;
wire                      pmp_mml;
wire                      pmp_mmwp;
wire                      bank_trigger;
wire                      debug_mode;

// Sdtrig execute-trigger match/fire/action
wire                      trigger_exec_match;
wire                      trigger_exec_fire;
wire                      trigger_exec_action;

// Sdtrig load/store-watchpoint fire/action
wire                      trigger_ls_fire;
wire                      trigger_ls_action;
wire                      trig_m_trap_entry;
wire                      trig_mret;
wire                      trig_rnmi_entry;
wire                      trig_mnret;
wire                [7:0] mcounteren_hpm;
wire                      trap_taken_hpm;
wire                      trap_is_irq_hpm;
wire                      minstret_undo;
wire                [9:0] core_events;
wire                      debug_stopcount;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                             CSR DECODING AND CONTROL                                                 //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//----------------------------------------------------------------------------------//
// CSR write/read enable per instruction (drives control bits [2]/[3]):             //
//   Write: CSRRW/CSRRWI always; CSRRS/C/SI/CI only when rs1/uimm[4:0] != 0.        //
//   Read : CSRRS/C/SI/CI always; CSRRW/CSRRWI only when rd != x0.                  //
//----------------------------------------------------------------------------------//

// DM abstract general-CSR injection: while dm_acsr_active_i the hart is frozen and the
// decoder's CSR inputs are idle, so we drive a synthesised CSR op onto the EX datapath.
wire  [3:0] dm_acsr_synth_control  = dm_acsr_wen_i    ? 4'b0001               : 4'b1010;
wire  [3:0] ex_csr_control_i       = dm_acsr_active_i ? dm_acsr_synth_control : ex_dec_csr_control_i;
wire [31:0] ex_csr_rs1_operand_i   = dm_acsr_active_i ? dm_acsr_wdata_i       : ex_dec_csr_rs1_operand_i;
wire [11:0] ex_csr_reg_addr_i      = dm_acsr_active_i ? dm_acsr_addr_i        : ex_dec_csr_reg_addr_i;

// Interpret CSR command from instruction decoder
assign     is_active               = (ex_csr_control_i[1:0]!=2'b00);
assign     is_csrrw                = (ex_csr_control_i[1:0]==2'b01);
assign     is_csrrs                = (ex_csr_control_i[1:0]==2'b10);
assign     is_csrrc                = (ex_csr_control_i[1:0]==2'b11);

// Detect edge cases from the spec where read and write are disabled
assign     disable_read            =  is_csrrw             & ex_csr_control_i[2]; // control bit 2 is set whenever RD==X0
// CONTRACT: there is no single central write gate. disable_write must be AND'ed
// individually into EVERY CSR write-enable -- this and any present/future bank
// or consumer (marv_ctl_wr, jvt_wr, ccsr_wen_o, write_invalid, the per-CSR write
// strobes in arv_csr_traps/cntr/hpm, ...). A CSRRS/CSRRC with RS1==x0 / UIMM==0
// must produce NO write side effect; a new consumer that omits ~disable_write
// would silently violate that. Keep the AND at each site.
assign     disable_write           = (is_csrrs | is_csrrc) & ex_csr_control_i[3]; // control bit 3 is set whenever RS1==X0 or UIMM==0

// Compute next CSR register value
assign     register_value_nxt      = is_csrrw ?                             ex_csr_rs1_operand_i  :  // CSRRW
                                     is_csrrs ? (ex_csr_reg_dest_wdata_o |  ex_csr_rs1_operand_i) :  // CSRRS
                                                (ex_csr_reg_dest_wdata_o & ~ex_csr_rs1_operand_i) ;  // CSRRC

// MIP[9] (SEIP) RMW write-back, per RISC-V Privileged Architecture §3.1.9
// (Passages 207-208): "Only the software-writable SEIP bit participates in
// the read-modify-write sequence of a CSRRS or CSRRC instruction." If we
// name the SW-writable bit B and the external interrupt controller signal E,
// the spec mandates  CSRRS: B := B  |  rs1[9]   (NOT (B|E) |  rs1[9])
//                    CSRRC: B := B  & ~rs1[9]   (NOT (B|E) & ~rs1[9])
// The architectural READ at register_value_nxt[9] still includes E (correct
// per the same passage - `rd` receives `B || E`); only the WRITE-BACK path
// for sip_seip_sw uses this un-OR'd computation. sip_seip_sw_from_traps is
// the current B forwarded back from arv_csr_traps.
assign     mip_seip_sw_rmw_nxt     = is_csrrw ?                             ex_csr_rs1_operand_i[9]  :  // CSRRW
                                     is_csrrs ? (sip_seip_sw_from_traps  |  ex_csr_rs1_operand_i[9]) :  // CSRRS
                                                (sip_seip_sw_from_traps  & ~ex_csr_rs1_operand_i[9]) ;  // CSRRC

// Debug Mode status: internal tap (also exported) -- consumed locally for the
// Sdtrig dmode whole-register write-protection gate.
assign     debug_mode_o            = debug_mode;

// CSR Register selection
assign     register_select         = ({{63{1'b0}}, 1'b1} << ex_csr_reg_addr_i[5:0]);

// Read CSR value to be written to the integer registers.
assign     ex_csr_reg_dest_wr_o    = is_active & ~disable_read & ~ex_excp_illegal_inst & ~dm_acsr_active_i;
assign     ex_csr_reg_dest_wdata_o = ccsr_value_read        |
                                     ids_value_read         |
                                     traps_value_read       |
                                     jvt_value_read         |
                                     marv_ctl_value_read    |
                                     marv_nmvec_value_read  |
                                     marv_cfg_value_read    |
                                     reset_vector_value_read|
                                     marv_epc_value_read    |
                                     marv_eaddr_value_read  |
                                     marv_estat_value_read  |
                                     counters_value_read    |
                                     hpm_value_read         |
                                     trigger_value_read     |
                                     pmp_value_read         ;

// CSR ready: stalled when waiting for time interface grant
assign     ex_csr_ready_o          = counters_csr_ready;


//----------------------------------------------------------------------------------//
//                                 Hart Privilege Level                             //
//----------------------------------------------------------------------------------//
//
// 11 - Machine mode
// 10 - Hypervisor mode (not supported)
// 01 - Supervisor mode
// 00 - User mode
//

// Machine mode (2'b11) after reset. Priority: privilege_mode_update load > hold.
arv_dff #(.WIDTH(2), .RST_VAL(2'b11), .ARST_EN(ARST_EN)) u_privilege_mode (
                                       .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(privilege_mode_update),
                                                                            .d_i (privilege_mode_nxt),
                                                                            .q_o (privilege_mode));

assign     if_priv_mode_o           = !SU_MODE_EN           ? 2'b11              :
                                      privilege_mode_update ? privilege_mode_nxt : privilege_mode;

// Bypass for arv_csr_traps feedback: priv_mode_next_o/update_o are registered (1-cycle delay
// for timing improvement). privilege_mode therefore updates one cycle late. This combinational
// bypass ensures priv_mode_current_i immediately reflects a pending privilege change so that
// mstatus.MPP/SPP and other trap-entry context is captured from the correct privilege level
// even when a trap fires in the same cycle as a RET instruction completes its redirect.
wire [1:0] privilege_mode_effective = privilege_mode_update ? privilege_mode_nxt : privilege_mode;

// Detect privilege Level of the current transfer
assign     acc_priv_is_super       = (ex_csr_reg_addr_i[ 9: 8]==2'b01) & is_active;
assign     acc_priv_is_hyper       = (ex_csr_reg_addr_i[ 9: 8]==2'b10) & is_active;
assign     acc_priv_is_machine     = (ex_csr_reg_addr_i[ 9: 8]==2'b11) & is_active;

// Detect valid and invalid accesses.
// INVARIANT: these checks use the REGISTERED privilege_mode (1 cycle stale vs
// privilege_mode_effective), kept off the timing path on purpose. This is
// correct ONLY because any xRET/trap that changes privilege also redirects the
// pipeline and squashes any in-flight CSR op during the one stale cycle, so a
// CSR access never reaches commit while privilege_mode is the wrong value.
// If you retime/relax that squash, switch these to privilege_mode_effective.
assign     machine_invalid         = acc_priv_is_machine &  (privilege_mode!=2'b11) & ~dm_acsr_active_i ;
assign     hypervisor_invalid      = acc_priv_is_hyper;   // H not implemented: always illegal regardless of privilege mode
assign     supervisor_invalid      = acc_priv_is_super   &  (privilege_mode==2'b00) & ~dm_acsr_active_i ;
assign     write_invalid           = (ex_csr_reg_addr_i[11:10]==2'b11)    & is_active & ~disable_write; // Attempt to write to a Read-only

// Zicntr raw bank signals (no ~ex_excp_illegal_inst to avoid combinatorial loop)
wire       bank_pmp;
wire       bank_mseccfg;
wire       bank_counter_raw        = (ex_csr_reg_addr_i[11:6]==6'b110000) & is_active;
wire       bank_counterh_raw       = (ex_csr_reg_addr_i[11:6]==6'b110010) & is_active;

// Counter CSR access denied when the layered filter blocks it:
//   - S-mode access: gated by mcounteren only.
//   - U-mode access: gated by (mcounteren & scounteren) - both M and S must allow.
wire [2:0] ctr_en                  = mcounteren     & (scounteren[2:0]  | {3{privilege_mode == 2'b01}});
wire [7:0] hpm_ctr_en              = mcounteren_hpm & (scounteren[10:3] | {8{privilege_mode == 2'b01}});

assign     zicntr_access_denied    = (privilege_mode != 2'b11) & ~dm_acsr_active_i & ZICNTR_EN   & ((bank_counter_raw  & ((register_select[0] & ~ctr_en[0]) |   // cycle
                                                                                                      (register_select[1] & ~ctr_en[1]) |   // time
                                                                                                      (register_select[2] & ~ctr_en[2]))) | // instret
                                                                                (bank_counterh_raw & ((register_select[0] & ~ctr_en[0]) |   // cycleh
                                                                                                      (register_select[1] & ~ctr_en[1]) |   // timeh
                                                                                                      (register_select[2] & ~ctr_en[2])))); // instreth

// mcounteren gating applies to EVERY hpmcounter3-31, implemented or not. An absent
// counter reads 0 in M-mode (see the Zihpm note below), but Priv 3.1.11 still makes
// a lower-privilege access illegal whenever the mcounteren bit is clear -- and for
// an absent counter that bit is hardwired 0, so ~hpm_ctr_en is always true there.
// Hence no ZIHPM_NR_EN gate and no HPM_IMPL_MASK: both would wrongly let S/U read
// an unimplemented counter as zero instead of trapping.
// The register_select[63:11] term covers hpmcounter11-31 / hpmcounterh11-31. This
// core tracks at most 8 HPM counters, so register_select[10:3] reaches only
// counters 3-10; offsets 11 and up have no enable bit at all, so their mcounteren
// bit is permanently 0 and a lower-privilege access is always illegal. Without it
// they read as zero from S/U instead of trapping.
assign     zihpm_access_denied     = (privilege_mode != 2'b11) & ~dm_acsr_active_i & (bank_counter_raw | bank_counterh_raw) &
                                     ((|(register_select[10:3] & ~hpm_ctr_en)) | (|register_select[63:11]));

// Catch-all: detect access to any CSR address not covered by any implemented bank.
// Spec: "Attempts to access a non-existent CSR raise an illegal instruction exception."
// Bank decode. Each window is 64 CSRs wide but only a handful are implemented, so
// the offset is range-checked as well: without it every unimplemented CSR sharing a
// window is silently RAZ/WI instead of raising illegal-instruction (e.g. stimecmp
// 0x14D, Sstc, which is NOT implemented and must trap).
//
// The bound is the highest IMPLEMENTED offset in each window, so holes BELOW it are
// still accepted (e.g. 0x307-0x309 in the 0x300 window). Closing those needs
// per-register decode; the bound is exact for the 0x140 / 0x180 / 0x7C0 windows,
// where the implemented set is contiguous from 0.
//
// The 0x300 (mhpmevent) and 0xB00/0xB80/0xC00/0xC80 (counter) windows are NOT
// range-checked here: absent HPM offsets simply read 0 (see the Zihpm note below), and a
// bound would be redundant with it.
assign     any_bank_known          = ((ex_csr_reg_addr_i[11:6]==6'b001100)  &
                                     // medeleg (0x302) / mideleg (0x303) must NOT exist without S-mode
                                     // (Priv 3.1.8), and mcounteren (0x306) / menvcfg (0x30A) /
                                     // menvcfgh (0x31A) exist only to serve a lower privilege: accessing
                                     // them raises illegal-instruction rather than reading 0. The rest
                                     // of the 0x300 window is M-mode and always present.
                                     ~((SU_MODE_EN == 0) & ((ex_csr_reg_addr_i[5:0]==6'h02) |
                                                            (ex_csr_reg_addr_i[5:0]==6'h03) |
                                                            (ex_csr_reg_addr_i[5:0]==6'h06) |
                                                            (ex_csr_reg_addr_i[5:0]==6'h0A) |
                                                            (ex_csr_reg_addr_i[5:0]==6'h1A)))) |                  // 0x300-0x33F (mstatus, mie, mtvec,
                                    ((ex_csr_reg_addr_i[11:6]==6'b001101) & (ex_csr_reg_addr_i[5:0] <= 6'h0B)) |  // 0x340-0x37F (mscratch, mepc, mcause, mtval, mip, mtinst 0x34A, mtval2 0x34B)
                                   ((SU_MODE_EN != 0) &
                                    ((ex_csr_reg_addr_i[11:6]==6'b000100) & (ex_csr_reg_addr_i[5:0] <= 6'h0A))) | // 0x100-0x13F (sstatus, sie, stvec, scounteren, senvcfg 0x10A RAZ/WI)
                                   ((SU_MODE_EN != 0) &
                                    ((ex_csr_reg_addr_i[11:6]==6'b000101) & (ex_csr_reg_addr_i[5:0] <= 6'h04))) | // 0x140-0x17F (sscratch, sepc, scause, stval, sip) -- excludes stimecmp 0x14D
                                   ((SU_MODE_EN != 0) &
                                    ((ex_csr_reg_addr_i[11:6]==6'b000110) & (ex_csr_reg_addr_i[5:0] == 6'h00))) | // 0x180-0x1BF (satp RAZ/WI -- Bare mode, no paged translation)
                                    ((ex_csr_reg_addr_i[11:6]==6'b111100) & (ex_csr_reg_addr_i[5:0] >= 6'h11)
                                                                          & (ex_csr_reg_addr_i[5:0] <= 6'h15)) |  // 0xF00-0xF3F (mvendorid, marchid, mimpid, mhartid, mconfigptr)
                                     (ex_csr_reg_addr_i[11:6]==6'b011111)                            |  // 0x7C0-0x7FF (marv_nmvec 0x7FD, marv_estat 0x7FE, marv_ctl 0x7FF).
                                                                                                        // NOT range-checked: the unimplemented offsets are RAZ/WI, and the
                                                                                                        // whole window is the custom-CSR bank 8 when CCSR_EN=1.
                  (DM_TRIGGER_EN  &  (ex_csr_reg_addr_i[11:6]==6'b011110) & |register_select[37:32])           |  // 0x7A0-0x7A5 (Sdtrig: tselect..tcontrol); sel[32..37] ONLY -- dcsr/dpc/dscratch; (sel[48..51]) stay excluded -> illegal
                         (           (ex_csr_reg_addr_i[11:6]==6'b011101) & (ex_csr_reg_addr_i[5:0] <= 6'h04)) |  // 0x740-0x77F (mnscratch, mnepc, mncause, mnstatus @0x744)
                  ((PMP_NR != 0)  &  (ex_csr_reg_addr_i[11:6]==6'b001110)
                                  & ((|register_select[35:32]) | (|register_select[63:48])))                   |  // 0x3A0-0x3A3 (pmpcfg0-3) / 0x3B0-0x3BF (pmpaddr0-15)
                  ((PMP_NR != 0)  &  (ex_csr_reg_addr_i[11:6]==6'b011101)
                                  &  (register_select[7] | register_select[23]))                               |  // 0x747 (mseccfg) / 0x757 (mseccfgh)
                                    ((ex_csr_reg_addr_i[11:6]==6'b111111) &  register_select[63])              |  // 0xFFF (marv_cfg, present regardless of CCSR_EN)
                                    ((ex_csr_reg_addr_i[11:6]==6'b111111) &  register_select[62])              |  // 0xFFE (CCSR: reset_vector)
                                    ((ex_csr_reg_addr_i[11:6]==6'b111111) & |register_select[61:60])           |  // 0xFFC/0xFFD (marv_epc / marv_eaddr)
                                    ((ex_csr_reg_addr_i[11:6]==6'b011111) &  register_select[62])              |  // 0x7FE (marv_estat)
                         (ZCMT_EN &  (ex_csr_reg_addr_i[11:6]==6'b000000) &  register_select[23])              |  // 0x017 (jvt)
                       (ZICNTR_EN &  (ex_csr_reg_addr_i[11:6]==6'b101100))                                     |  // 0xB00-0xB3F (mcycle, minstret, mhpmcounter3-10) -- absent HPM offsets are RAZ/WI (see below)
                       (ZICNTR_EN &  (ex_csr_reg_addr_i[11:6]==6'b101110))                                     |  // 0xB80-0xBBF (mcycleh, minstreth, mhpmcounter3-10h)
                       (ZICNTR_EN &  (ex_csr_reg_addr_i[11:6]==6'b110000))                                     |  // 0xC00-0xC3F (cycle, time, instret, hpmcounter3-10)
                       (ZICNTR_EN &  (ex_csr_reg_addr_i[11:6]==6'b110010))                                     |  // 0xC80-0xCBF (cycleh, timeh, instreth)
                     (ZIHPM_NR_EN &  (ex_csr_reg_addr_i[11:6]==6'b101100))                                     |  // 0xB00-0xB3F (mhpmcounter3-N)
                     (ZIHPM_NR_EN &  (ex_csr_reg_addr_i[11:6]==6'b101110))                                     |  // 0xB80-0xBBF (mhpmcounterh3-N)
                     (ZIHPM_NR_EN &  (ex_csr_reg_addr_i[11:6]==6'b110000))                                     |  // 0xC00-0xC3F (hpmcounter3-N)
                     (ZIHPM_NR_EN &  (ex_csr_reg_addr_i[11:6]==6'b110010))                                     |  // 0xC80-0xCBF (hpmcounterh3-N)
                         (CCSR_EN & ((ex_csr_reg_addr_i[11:6]==6'b100000)                                      |  // CCSR bank 0: 0x800-0x83F
                                     (ex_csr_reg_addr_i[11:6]==6'b100001)                                      |  // CCSR bank 1: 0x840-0x87F
                                     (ex_csr_reg_addr_i[11:6]==6'b100010)                                      |  // CCSR bank 2: 0x880-0x8BF
                                     (ex_csr_reg_addr_i[11:6]==6'b100011)                                      |  // CCSR bank 3: 0x8C0-0x8FF
                                     (ex_csr_reg_addr_i[11:6]==6'b110011)                                      |  // CCSR bank 4: 0xCC0-0xCFF
                                     (ex_csr_reg_addr_i[11:6]==6'b010111)                                      |  // CCSR bank 5: 0x5C0-0x5FF
                                     (ex_csr_reg_addr_i[11:6]==6'b100111)                                      |  // CCSR bank 6: 0x9C0-0x9FF
                                     (ex_csr_reg_addr_i[11:6]==6'b110111)                                      |  // CCSR bank 7: 0xDC0-0xDFF
                                     (ex_csr_reg_addr_i[11:6]==6'b101111)                                      |  // CCSR bank 9: 0xBC0-0xBFF
                                     (ex_csr_reg_addr_i[11:6]==6'b111111)));                                      // CCSR bank 10: 0xFC0-0xFFF

assign     unimplemented_csr       = is_active & ~any_bank_known;

// Per-register existence for the Zihpm ranges.
//
// The behaviour depends on whether Zihpm exists AT ALL:
//
//   ZIHPM_NR == 0 : the extension is not implemented, so mhpmcounter3-31 /
//                   mhpmevent3-31 are non-existent CSRs and an access raises
//                   illegal-instruction -- the general rule, "attempts to access a
//                   non-existent CSR raise an illegal instruction exception".
//
//   ZIHPM_NR  > 0 : Zihpm IS implemented, so the whole mhpmcounter3-31 /
//                   mhpmevent3-31 set exists; the ones this build does not provide
//                   are READ-ONLY ZERO, not absent. Priv 3.1.10: "a legal
//                   implementation is to make both the counter and its
//                   corresponding event selector be read-only 0". The read mux
//                   returns 0 for them on its own and arv_csr_hpm.v masks its write
//                   enables with HPM_WARL_MASK, so nothing further is needed.
//
// Lower-privilege accesses are a separate matter and are always policed by
// zihpm_access_denied above, per the mcounteren gating.
wire       hpm_evt_bank            = (ex_csr_reg_addr_i[11:6]==6'b001100);
wire       hpm_ctr_bank            = (ex_csr_reg_addr_i[11:6]==6'b101100) |   // 0xB00 mhpmcounter
                                     (ex_csr_reg_addr_i[11:6]==6'b101110) |   // 0xB80 mhpmcounterh
                                     (ex_csr_reg_addr_i[11:6]==6'b110000) |   // 0xC00 hpmcounter
                                     (ex_csr_reg_addr_i[11:6]==6'b110010);    // 0xC80 hpmcounterh

assign     hpm_csr_absent          = is_active & (ZIHPM_NR == 0) &
                                     ((hpm_evt_bank & (|(register_select[42:35] & ~HPM_IMPL_MASK) | (|register_select[63:43]))) |
                                      (hpm_ctr_bank & (|(register_select[10:3]  & ~HPM_IMPL_MASK) | (|register_select[63:11]))));

// Lint cleanup
generate
    if (ZIHPM_NR > 0) begin : gen_hpm_bank_unused
        wire hpm_bank_unused = hpm_evt_bank | hpm_ctr_bank;
    end
endgenerate
generate
    if (SU_MODE_EN == 1'b0) begin : gen_tvm_unused
        wire cfg_trap_vm_unused = cfg_trap_vm;
    end
endgenerate

// TVM (mstatus[20]): "when TVM=1, attempts to read or write satp while executing in S-mode raise an illegal-instruction exception".
wire       tvm_satp_denied         = is_active & cfg_trap_vm & (privilege_mode_effective == 2'b01) & ~dm_acsr_active_i & SU_MODE_EN &
                                     (ex_csr_reg_addr_i[11:6] == 6'b000110);   // 0x180-0x1BF

assign     ex_excp_illegal_inst    = machine_invalid         |
                                     tvm_satp_denied         |
                                     hypervisor_invalid      |
                                     supervisor_invalid      |
                                     write_invalid           |
                                     zicntr_access_denied    |
                                     zihpm_access_denied     |
                                     hpm_csr_absent          |
                                     unimplemented_csr       ;

// Structural fault export for the DM abstract CSR engine. With privilege terms
// bypassed during a DM access, ex_excp_illegal_inst reflects only structural faults
// (nonexistent / read-only-write / absent CSR) -> the cmderr=3 source. The hart is
// halted, so this raises no trap (trap entry is gated on ~debug_mode).
assign     dm_acsr_fault_o         = dm_acsr_active_i & ex_excp_illegal_inst;
// CSR read value for the DM (the synthesised CSRRS makes the bank read-mux present the
// addressed CSR on ex_csr_reg_dest_wdata_o combinationally).
assign     dm_acsr_rdata_o         = ex_csr_reg_dest_wdata_o;

// NMI CSR bank active whenever there is no privilege/write error (Smrnmi is unconditional)
assign     bank_nmi_handling       = (ex_csr_reg_addr_i[11:6]==6'b011101) & is_active & ~ex_excp_illegal_inst;

// PMP: pmpcfg0-3 @ 0x3A0-0x3A3 (sel 32-35) and pmpaddr0-15 @ 0x3B0-0x3BF (sel 48-63)
// share one otherwise-unused window. mseccfg/mseccfgh sit in the NMI window at
// sel 7 / 23, which the NMI CSRs (sel 0-4) do not touch.
assign     bank_pmp                = (ex_csr_reg_addr_i[11:6]==6'b001110) & is_active & ~ex_excp_illegal_inst;
assign     bank_mseccfg            = (ex_csr_reg_addr_i[11:6]==6'b011101) & is_active & ~ex_excp_illegal_inst;


// Reset-vector RO CSR at 0xFFE (custom MRO): returns the integrator-driven reset_vector_i so
// firmware can discover its own reset PC. Internal CSR -> always present, independent of CCSR_EN
// Privilege is enforced by the generic machine_invalid check (addr[9:8]==11).
// Bits [1:0] read 0: the fetch unit ignores them (the reset PC is always word-aligned), so the
// CSR reports the EFFECTIVE reset PC, not the raw strap.
// Build-configuration discovery CSR at 0xFFF (read-only; contents built in arv_csr_ids).
assign     bank_marv_cfg           = (ex_csr_reg_addr_i[11:6]==6'b111111) & register_select[63] & is_active & ~ex_excp_illegal_inst;
assign     marv_cfg_value_read     = {32{bank_marv_cfg}} & marv_cfg;

assign     bank_reset_vector       = (ex_csr_reg_addr_i[11:6]==6'b111111) & register_select[62] & is_active & ~ex_excp_illegal_inst;
assign     reset_vector_value_read = {32{bank_reset_vector}} & {reset_vector_i[31:2], 2'b00};


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                          CSR IDS                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Select the banks
assign     bank_misa_en            = (ex_csr_reg_addr_i[11:6]==6'b001100) & is_active & ~ex_excp_illegal_inst; // Machine RW: 0x300
assign     bank_ids_en             = (ex_csr_reg_addr_i[11:6]==6'b111100) & is_active & ~ex_excp_illegal_inst; // Machine RO: 0xF00

arv_csr_ids #(.ARST_EN            (ARST_EN            ),
              .C_EXT_EN           (C_EXT_EN           ),
              .M_EXT_EN           (M_EXT_EN           ),
              .B_EXT_EN           (B_EXT_EN           ),
              .MUL_1C_EN          (MUL_1C_EN          ),
              .MUL_4C_EN          (MUL_4C_EN          ),
              .MUL_16C_EN         (MUL_16C_EN         ),
              .DIV_12C_EN         (DIV_12C_EN         ),
              .DIV_17C_EN         (DIV_17C_EN         ),
              .DIV_33C_EN         (DIV_33C_EN         ),
              .CCSR_EN            (CCSR_EN            ),
              .DEBUG_EN           (DEBUG_EN           ),
              .SU_MODE_EN         (SU_MODE_EN         ),
              .RV32I_EN           (RV32I_EN           ),
              .ZICNTR_EN          (ZICNTR_EN          ),
              .ZIHPM_NR           (ZIHPM_NR           ),
              .SINGLE_CYCLE_BRANCH(SINGLE_CYCLE_BRANCH),
              .RTL_VERSION        (RTL_VERSION        ),
              .C_EXT_LEVEL        (C_EXT_LEVEL        ),
              .B_EXT_LEVEL        (B_EXT_LEVEL        ),
              .PMP_NR_FIELD       (PMP_NR_FIELD       ),
              .DM_TRIGGER_NR      (DM_TRIGGER_NR      )) arv_csr_ids_inst (

    .hartid_i                           ( hartid_i                           ),
    .bank_misa_en_i                     ( bank_misa_en                       ),
    .bank_ids_en_i                      ( bank_ids_en                        ),
    .register_sel_i                     ( register_select                    ),
    .marv_cfg_o                         ( marv_cfg                           ),
    .ids_rdata_o                        ( ids_value_read                     )
);

//////======================================================================================================================//////
//////                                        PHYSICAL MEMORY PROTECTION (PMP + Smepmp)                                     //////
//////======================================================================================================================//////

arv_csr_pmp #(.PMP_NR  ( PMP_NR  ),
              .ARST_EN ( ARST_EN )) arv_csr_pmp_inst (

    .hclk_i                             ( hclk_i                             ),
    .hresetn_i                          ( hresetn_i                          ),

    .bank_pmp_i                         ( bank_pmp                           ),
    .bank_mseccfg_i                     ( bank_mseccfg                       ),

    .register_sel_i                     ( register_select                    ),
    .register_value_nxt_i               ( register_value_nxt[31:0]           ),
    .disable_write_i                    ( disable_write                      ),

    .pmp_cfg_o                          ( pmp_cfg                            ),
    .pmp_addr_o                         ( pmp_addr                           ),
    .pmp_mml_o                          ( pmp_mml                            ),
    .pmp_mmwp_o                         ( pmp_mmwp                           ),

    .pmp_rdata_o                        ( pmp_value_read                     )
);

// The entry state leaves the CSR block unregistered: the address matchers live with the consumers that check against it.
assign     pmp_cfg_o  = pmp_cfg;
assign     pmp_addr_o = pmp_addr;
assign     pmp_mml_o  = pmp_mml;
assign     pmp_mmwp_o = pmp_mmwp;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                      TRAP HANDLING                                                   //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Select the banks
assign     bank_mtrap_setup        = (ex_csr_reg_addr_i[11:6]==6'b001100) & is_active & ~ex_excp_illegal_inst; // Machine    RW: 0x300
assign     bank_mtrap_handling     = (ex_csr_reg_addr_i[11:6]==6'b001101) & is_active & ~ex_excp_illegal_inst; // Machine    RW: 0x340
assign     bank_strap_setup        = (ex_csr_reg_addr_i[11:6]==6'b000100) & is_active & ~ex_excp_illegal_inst; // Supervisor RW: 0x100
assign     bank_strap_handling     = (ex_csr_reg_addr_i[11:6]==6'b000101) & is_active & ~ex_excp_illegal_inst; // Supervisor RW: 0x140

arv_csr_traps #(.ARST_EN     (ARST_EN   ),
                .C_EXT_EN    (C_EXT_EN  ),
                .SU_MODE_EN  (SU_MODE_EN),
                .PMP_NR      (PMP_NR    ),
                .ZICNTR_EN   (ZICNTR_EN ),
                .ZIHPM_NR    (ZIHPM_NR  ),
                .DEBUG_EN    (DEBUG_EN  )) arv_csr_traps_inst (

// AHB CLOCK & RESET
    .hclk_i                             ( hclk_i                             ),
    .hresetn_i                          ( hresetn_i                          ),

// INTERFACE TO READ/WRITE CSR REGISTERS WITH INSTRUCTIONS
    .bank_mtrap_setup_i                 ( bank_mtrap_setup                   ),
    .bank_mtrap_handling_i              ( bank_mtrap_handling                ),
    .bank_strap_setup_i                 ( bank_strap_setup                   ),
    .bank_strap_handling_i              ( bank_strap_handling                ),
    .bank_nmi_handling_i                ( bank_nmi_handling                  ),
    .disable_write_i                    ( disable_write                      ),
    .register_sel_i                     ( register_select                    ),
    .register_value_nxt_i               ( register_value_nxt                 ),
    .traps_rdata_o                      ( traps_value_read                   ),
    .scounteren_o                       ( scounteren                         ),

// INTERFACE TO INSTRUCTION FETCH AND INST DECODER
    .id_opcode_mret_i                   ( id_opcode_mret_i                   ),
    .id_opcode_sret_i                   ( id_opcode_sret_i                   ),
    .id_opcode_mnret_i                  ( id_opcode_mnret_i                  ),
    .cfg_timeout_wait_o                 ( cfg_timeout_wait_o                 ),
    .cfg_trap_sret_o                    ( cfg_trap_sret_o                    ),
    .cfg_trap_vm_o                      ( cfg_trap_vm                        ),

// TRAP INTERFACE TO DECODE
    .trap_stall_o                       ( trap_stall_o                       ),
    .ex_excp_squash_o                   ( ex_excp_squash_o                   ),
    .trap_branch_detect_o               ( trap_branch_detect_o               ),
    .trap_branch_target_o               ( trap_branch_target_o               ),
    .wfi_wakeup_o                       ( wfi_wakeup_o                       ),
    .wfi_wakeup_live_o                  ( wfi_wakeup_live_o                  ),
    .id_wfi_active_i                    ( id_wfi_active_i                    ),

// EXTERNAL INTERRUPT INPUTS
    .irq_m_software_i                   ( irq_m_software_i                   ),
    .irq_s_software_i                   ( irq_s_software_i                   ),
    .irq_m_timer_i                      ( irq_m_timer_i                      ),
    .irq_m_external_i                   ( irq_m_external_i                   ),
    .irq_s_external_i                   ( irq_s_external_i                   ),
    .irq_platform_i                     ( irq_platform_i                     ),

// EXCEPTIONS (SYNCHRONOUS TRAPS)
    .if_excp_inst_address_misaligned_i  ( if_excp_inst_address_misaligned_i  ),
    .id_excp_inst_access_fault_i        ( id_excp_inst_access_fault_i        ),
    .id_inst_fault_addr_i               ( id_inst_fault_addr_i               ),
    .id_excp_illegal_inst_i             ( id_excp_illegal_inst_i             ),
    .id_excp_ebreak_i                   ( id_excp_ebreak_i                   ),
    .id_excp_ebreak_nodbg_i             ( id_excp_ebreak_nodbg_i             ),
    .id_excp_ecall_i                    ( id_excp_ecall_i                    ),

// SDTRIG EXECUTE-TRIGGER (action=0 breakpoint excp + action=1 debug entry; mte FSM taps back)
    .trigger_exec_match_i               ( trigger_exec_match                 ),
    .trigger_exec_fire_i                ( trigger_exec_fire                  ),
    .trigger_exec_action_i              ( trigger_exec_action                ),
    .trigger_ls_fire_i                  ( trigger_ls_fire                    ),
    .trigger_ls_action_i                ( trigger_ls_action                  ),
    .m_trap_entry_o                     ( trig_m_trap_entry                  ),
    .mret_o                             ( trig_mret                          ),
    .rnmi_entry_o                       ( trig_rnmi_entry                    ),
    .mnret_o                            ( trig_mnret                         ),
    .ex_excp_illegal_inst_i             ( ex_excp_illegal_inst               ),
    .ex_excp_load_address_misaligned_i  ( ex_excp_load_address_misaligned_i  ),
    .ex_excp_store_address_misaligned_i ( ex_excp_store_address_misaligned_i ),
    .ex_excp_load_access_fault_i        ( ex_excp_load_access_fault_i        ),
    .ex_excp_store_access_fault_i       ( ex_excp_store_access_fault_i       ),
    .wb_bus_error_load_i                ( wb_bus_error_load_i                ),
    .wb_bus_error_store_i               ( wb_bus_error_store_i               ),
    .wb_uop_sourced_i                   ( wb_uop_sourced_i                   ),
    .wb_uop_seq_alive_i                 ( wb_uop_seq_alive_i                 ),
    .wb_uop_jt_sourced_i                ( wb_uop_jt_sourced_i                ),

// PIPELINE READY SIGNALS (FOR DRAIN DETECTION)
    .ex_alu_ready_i                     ( ex_alu_ready_i                     ),
    .ex_ldst_ready_i                    ( ex_ldst_ready_i                    ),
    .ex_ldst_unresolved_i               ( ex_ldst_unresolved_i               ),
    .ex_pmp_refetch_i                   ( ex_pmp_refetch_i                   ),
    .ex_csr_ready_i                     ( ex_csr_ready_o                     ),
    .ex_uop_has_branch_i                ( ex_uop_has_branch_i                ),
    .ex_uop_ready_i                     ( ex_uop_ready_i                     ),
    .ex_uop_take_branch_i               ( ex_uop_take_branch_i               ),
    .id_instruction_valid_i             ( id_instruction_valid_i             ),
    .wb_ldst_ready_i                    ( wb_ldst_ready_i                    ),

// PIPELINE MONITORING & CONTROL IN CASE OF TRAP
    .if_stop_cmd_o                      ( if_stop_cmd_o                      ),
    .lockup_o                           ( lockup_o                           ),

// PC PIPELINE INPUTS (FOR MEPC SAVE)
    .id_pc_i                            ( id_pc_i                            ),
    .ex_pc_i                            ( ex_pc_i                            ),
    .wb_pc_i                            ( wb_pc_i                            ),

// DATA ADDRESS PIPELINE (FOR MTVAL SAVE)
    .ex_data_addr_i                     ( ex_data_addr_i                     ),

// PRIVILEGE MODE
    .priv_mode_current_i                ( privilege_mode_effective           ),
    .priv_mode_next_o                   ( privilege_mode_nxt                 ),
    .priv_mode_update_o                 ( privilege_mode_update              ),
    .priv_mode_ldst_o                   ( priv_mode_ldst_o                  ),

// WRITE-BACK SUPPRESSION
    .trap_kill_ex_o                     ( trap_kill_ex_o                     ),

// IRQ KILL FOR MULTI-CYCLE OPERATIONS
    .trap_kill_muldiv_o                 ( trap_kill_muldiv_o                 ),
    .trap_kill_uop_o                    ( trap_kill_uop_o                    ),
    .trap_kill_uop_hold_o               ( trap_kill_uop_hold_o               ),
    .ex_uop_excp_abort_o                ( ex_uop_excp_abort_o                ),
    .ex_uop_jt_fault_o                  ( ex_uop_jt_fault_o                  ),
    .marv_ctl_i                         ( marv_ctl_reg                       ),
    .ex_alu_is_killable_i               ( ex_alu_is_killable_i               ),
    .ex_uop_is_killable_i               ( ex_uop_is_killable_i               ),
    .ex_uop_kill_window_i               ( ex_uop_kill_window_i               ),
    .ex_uop_jt_active_i                 ( ex_uop_jt_active_i                 ),
    .id_uop_jt_start_i                  ( id_uop_jt_start_i                  ),

// INITIALIZATION OF THE TRAP VECTOR DEFAULT VALUES
    .init_pc_i                          ( init_pc_i                          ),
    .reset_vector_i                     ( reset_vector_i                     ),

// NMI (SMRNMI)
    .nmi_i                              ( nmi_i                              ),
    .marv_nmvec_i                       ( marv_nmvec                         ),

// HPM TRAP EVENTS
    .trap_taken_o                       ( trap_taken_hpm                     ),
    .trap_is_irq_o                      ( trap_is_irq_hpm                    ),

// MINSTRET UN-RETIRE (Zicntr): a synchronous exception did not retire its instruction
    .minstret_undo_o                    ( minstret_undo                      ),

// MIP[9] SEIP RMW WRITE-BACK (see §3.1.9 P207-208 comment near `mip_seip_sw_rmw_nxt`)
    .sip_seip_sw_o                      ( sip_seip_sw_from_traps             ),
    .mip_seip_sw_rmw_nxt_i              ( mip_seip_sw_rmw_nxt                ),

// INSTRUCTION RETIRE (single-step boundary, consumed only when DEBUG_EN=1)
    .inst_retired_i                     ( inst_retired_i                     ),

// EXTERNAL DEBUG (Sdext)
    .debug_req_i                        ( debug_req_i                        ),
    .resume_req_i                       ( resume_req_i                       ),
    .resethaltreq_i                     ( resethaltreq_i                     ),
    .dm_csr_access_i                    ( dm_csr_access_i                    ),
    .dm_csr_sel_i                       ( dm_csr_sel_i                       ),
    .dm_csr_wen_i                       ( dm_csr_wen_i                       ),
    .dm_csr_wdata_i                     ( dm_csr_wdata_i                     ),
    .dm_csr_rdata_o                     ( dm_csr_rdata_o                     ),
    .debug_mode_o                       ( debug_mode                         ),
    .debug_halt_active_o                ( debug_halt_active_o                ),
    .debug_issue_hold_o                 ( debug_issue_hold_o                 ),
    .debug_ebreak_cfg_o                 ( debug_ebreak_cfg_o                 ),
    .debug_halted_o                     ( debug_halted_o                     ),
    .debug_stopcount_o                  ( debug_stopcount                    ),
    .debug_stoptime_o                   ( debug_stoptime_o                   )

);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                              TIME AND PERFORMANCE COUNTERS                                           //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Zicntr banks
assign     bank_mcycle             = (ex_csr_reg_addr_i[11:6]==6'b101100) & is_active & ~ex_excp_illegal_inst;  // 0xB00-0xB3F (mcycle, minstret)
assign     bank_mcycleh            = (ex_csr_reg_addr_i[11:6]==6'b101110) & is_active & ~ex_excp_illegal_inst;  // 0xB80-0xBBF (mcycleh, minstreth)
assign     bank_counter            = (ex_csr_reg_addr_i[11:6]==6'b110000) & is_active & ~ex_excp_illegal_inst;  // 0xC00-0xC3F (cycle, time, instret)
assign     bank_counterh           = (ex_csr_reg_addr_i[11:6]==6'b110010) & is_active & ~ex_excp_illegal_inst;  // 0xC80-0xCBF (cycleh, timeh, instreth)

generate
    if (ZICNTR_EN == 1'b1) begin : gen_zicntr

        arv_csr_cntr #(.ARST_EN(ARST_EN), .SU_MODE_EN(SU_MODE_EN)) arv_csr_cntr_inst (

            .hclk_i                  ( hclk_i               ),
            .hresetn_i               ( hresetn_i            ),

            .bank_mcycle_i           ( bank_mcycle          ),
            .bank_mcycleh_i          ( bank_mcycleh         ),
            .bank_counter_i          ( bank_counter         ),
            .bank_counterh_i         ( bank_counterh        ),
            .bank_mtrap_setup_i      ( bank_mtrap_setup     ),
            .register_sel_i          ( register_select      ),
            .register_value_nxt_i    ( register_value_nxt   ),
            .disable_write_i         ( disable_write        ),
            .inst_retired_i          ( inst_retired_i       ),
            .minstret_undo_i         ( minstret_undo        ),
            .stopcount_freeze_i      ( debug_stopcount      ),
            .dm_acsr_active_i        ( dm_acsr_active_i     ),
            .time_req_o              ( time_req_o           ),
            .time_gnt_i              ( time_gnt_i           ),
            .time_val_i              ( time_val_i           ),
            .ex_csr_ready_o          ( counters_csr_ready   ),
            .mcounteren_o            ( mcounteren           ),
            .counters_rdata_o        ( counters_value_read  )
        );

    end else begin : gen_zicntr_disabled

        assign      time_req_o           =  1'b0;
        assign      counters_csr_ready   =  1'b1;
        assign      mcounteren           =  3'b111;  // all counters accessible when Zicntr absent
        assign      counters_value_read  = 32'h0;

        wire        bank_mcycle_unused   = bank_mcycle;
        wire        bank_mcycleh_unused  = bank_mcycleh;
        wire        bank_counter_unused  = bank_counter;
        wire        bank_counterh_unused = bank_counterh;
        wire        inst_retired_unused  = inst_retired_i;
        wire        minstret_undo_unused = minstret_undo;
        wire        time_gnt_unused      = time_gnt_i;
        wire [63:0] time_val_unused      = time_val_i;

    end
endgenerate


// Assemble core event bus for HPM counters
// [7:0]  from decoder (fetch/LSU/ALU/CSR stall, branch taken/nt, load, store)
// [8]    exception taken (trap taken but not IRQ and not NMI)
// [9]    interrupt taken (trap taken and is IRQ)
assign core_events = {
    trap_taken_hpm &  trap_is_irq_hpm,   // [9] interrupt
    trap_taken_hpm & ~trap_is_irq_hpm,   // [8] exception
    id_hpm_events_i                       // [7:0]
};

generate
    if (ZIHPM_NR > 0) begin : gen_hpm

        arv_csr_hpm #(.ARST_EN (ARST_EN ),
                      .ZIHPM_NR(ZIHPM_NR)) arv_csr_hpm_inst (

            .hclk_i                  ( hclk_i               ),
            .hresetn_i               ( hresetn_i            ),

            .bank_mcycle_i           ( bank_mcycle          ),
            .bank_mcycleh_i          ( bank_mcycleh         ),
            .bank_mtrap_setup_i      ( bank_mtrap_setup     ),
            .bank_counter_i          ( bank_counter         ),
            .bank_counterh_i         ( bank_counterh        ),
            .register_sel_i          ( register_select      ),
            .register_value_nxt_i    ( register_value_nxt   ),
            .disable_write_i         ( disable_write        ),
            .stopcount_freeze_i      ( debug_stopcount      ),
            .core_events_i           ( core_events          ),
            .platform_events_i       ( hpm_platform_events_i),
            .mcounteren_hpm_o        ( mcounteren_hpm       ),
            .hpm_rdata_o             ( hpm_value_read       )
        );

    end else begin : gen_hpm_disabled

        wire  [9:0] core_events_unused      = core_events;
        wire  [7:0] platform_events_unused  = hpm_platform_events_i;

        assign      hpm_value_read          = 32'h0;
        assign      mcounteren_hpm          = 8'h0;

    end
endgenerate

// Lint cleanup
generate
    if (ZICNTR_EN == 1'b0 && ZIHPM_NR == 0) begin : gen_stopcount_unused
        wire debug_stopcount_unused = debug_stopcount;
    end
endgenerate


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       SDTRIG TRIGGER CSR FILE (DEBUG SPEC 1.0)                                       //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
//
// tselect/tdata1(mcontrol6)/tdata2/tdata3/tinfo/tcontrol at 0x7A0-0x7A5 (bank 0x1E).
// The bank (6'b011110) is SHARED with the D-mode-only dcsr/dpc/dscratch (0x7B0-0x7B3,
// sel[48..51]); those are reached only over the dm_csr side-port and MUST keep raising
// illegal on a general/M-mode csrr, so bank_trigger -- and the any_bank_known term above
// -- qualify on sel[32..37] only. ex_excp_illegal_inst already excludes dcsr (never in
// any_bank_known), so bank_trigger is high only for the six 0x7A0-0x7A5 addresses.
//
// DM abstract writes reach the file via the EXISTING ex_csr datapath (register_select /
// register_value_nxt already muxed to the dm_acsr_* values upstream); no new DM plumbing.

assign     bank_trigger             = (ex_csr_reg_addr_i[11:6]==6'b011110) & is_active & ~ex_excp_illegal_inst;

generate
    if (DM_TRIGGER_EN == 1'b1) begin : gen_trigger

        arv_debug_trigger #(.ARST_EN      (ARST_EN      ),
                            .DM_TRIGGER_NR(DM_TRIGGER_NR),
                            .SU_MODE_EN   (SU_MODE_EN   )) arv_debug_trigger_inst (

            .hclk_i                  ( hclk_i                   ),
            .hresetn_i               ( hresetn_i                ),

            .bank_trigger_i          ( bank_trigger             ),
            .register_sel_i          ( register_select          ),
            .register_value_nxt_i    ( register_value_nxt       ),
            .disable_write_i         ( disable_write            ),
            .debug_mode_i            ( debug_mode               ),

            .id_pc_i                 ( id_pc_i                  ),
            .priv_mode_i             ( privilege_mode_effective ),
            .id_issue_active_nodbg_i ( id_issue_active_nodbg_i  ),
            .m_trap_entry_i          ( trig_m_trap_entry        ),
            .mret_i                  ( trig_mret                ),
            .rnmi_entry_i            ( trig_rnmi_entry          ),
            .mnret_i                 ( trig_mnret               ),

            .ex_data_addr_i          ( ex_data_addr_i           ),
            .ex_is_load_i            ( ex_is_load_i             ),
            .ex_is_store_i           ( ex_is_store_i            ),
            .ex_size_i               ( ex_size_i                ),

            .trigger_rdata_o         ( trigger_value_read       ),
            .trigger_exec_match_o    ( trigger_exec_match       ),
            .trigger_exec_fire_o     ( trigger_exec_fire        ),
            .trigger_exec_action_o   ( trigger_exec_action      ),
            .trigger_ls_fire_o       ( trigger_ls_fire          ),
            .trigger_ls_action_o     ( trigger_ls_action        )
        );

    end else begin : gen_trigger_disabled

        assign      trigger_value_read     = 32'h0;
        assign      trigger_exec_match     =  1'b0;
        assign      trigger_exec_fire      =  1'b0;
        assign      trigger_exec_action    =  1'b0;
        assign      trigger_ls_fire        =  1'b0;
        assign      trigger_ls_action      =  1'b0;

        // Trigger absent: the mte-FSM taps from traps and the EX load/store taps have no consumer.
        wire        bank_trigger_unused    = bank_trigger;
        wire        id_issue_active_unused = id_issue_active_nodbg_i;
        wire        trig_mte_taps_unused   = |{trig_m_trap_entry, trig_mret, trig_rnmi_entry, trig_mnret};
        wire        trig_ls_taps_unused    = |{ex_is_load_i, ex_is_store_i, ex_size_i};

    end
endgenerate

// Action-agnostic load/store-watchpoint fire to the LSU: suppresses the data access (pre-AHB)
// on ANY hit (action=0 breakpoint OR action=1 debug entry), so a store does not modify memory.
// 0 when the trigger file is absent (trigger_ls_fire tied 0) -> non-trigger builds untouched.
assign     trig_ls_fire_o           = trigger_ls_fire;

// Action=0 (breakpoint exception) execute-trigger hold -> holds the matched committing
// instruction at ID. Built from the EARLY match, NOT the issue-qualified fire (see
// arv_decode timing optimization D for why that is behavior-safe). Action=1 (debug
// entry) is held by debug_issue_hold instead, so it is excluded here. Collapses to 0
// when the trigger file is absent (trigger_exec_match tied 0) -> non-trigger builds untouched.
assign     trig_break_issue_kill_o  = trigger_exec_match & ~trigger_exec_action;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                        ARVERN SPECIFIC CONFIGURATION CSR (0x7C0)                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
//
// Built-in Machine-mode RW register at 0x7C0, always present regardless of CCSR_EN.
// Controls IRQ kill behavior for multi-cycle operations.
//

wire          bank_marv_ctl     = (ex_csr_reg_addr_i[11:6]==6'b011111) & is_active & ~ex_excp_illegal_inst; // 0x7C0-0x7FF
wire          marv_ctl_sel      = (register_select[63] &  bank_marv_ctl);                                   // 0x7FF = bit[5:0]=63
wire          marv_ctl_wr       = (marv_ctl_sel        & ~disable_write);

// arvern feature-control CSR (custom, 0x7FF). Bit map:
//   [0]   irqkill_muldiv_en    : kill in-flight MUL/DIV on IRQ
//   [1]   irqkill_uop_en       : kill in-flight UOP sequence on IRQ
//   [2]   livelock_prot_en     : livelock protection -- post-(M)RET IRQ/NMI re-entry guard + multi-cycle-op kill/restart guard
//   [3]   wfi_clkgate_dis      : disable WFI clock-gating (keep hclk running during WFI sleep).
//                                Safety/debug/power-policy knob; WFI still stalls and wakes
//                                normally. Default 0 = clock-gating enabled.
//
// Reset 4'b0111: [2:0]=1 (enabled), [3]=0 (WFI gating on)

arv_dff #(.WIDTH(4), .RST_VAL(4'b0111), .ARST_EN(ARST_EN)) u_marv_ctl (.clk_i(hclk_i), .rst_n_i(hresetn_i),
                    .en_i(marv_ctl_wr),
                    .d_i ({register_value_nxt[3], register_value_nxt[2:0]}),
                    .q_o (marv_ctl_reg));

assign marv_ctl_value_read = ({32{marv_ctl_sel}} & {28'h0, marv_ctl_reg});


//
// RNMI handler base address (custom, 0x7FD) -- MRW, 4-byte aligned.
//
// Firmware-writable so a hart can place its own RNMI handler; under Smdbltrp that is also its
// double-trap handler. Seeded from reset_vector_i like mtvec/stvec, in trap-priority order so
// an M-only boot ROM needs only the first three slots:
//     reset_vector + 0  reset entry   + 4  RNMI   + 8  mtvec   + 12  stvec
// reset_vector_i is an integration constant, not state, so the last-resort vector cannot be
// corrupted by the machine it is meant to rescue -- which is why it is not derived from mtvec.
//
// CONTRACT: init_pc_i MUST be a single-cycle pulse (same contract as mtvec/stvec).
wire          marv_nmvec_sel    = (register_select[61] &  bank_marv_ctl);                  // 0x7FD
wire          marv_nmvec_wr     = (marv_nmvec_sel      & ~disable_write);

wire   [29:0] marv_nmvec_base;
wire          marv_nmvec_base_en  = marv_nmvec_wr | init_pc_i;
wire   [29:0] marv_nmvec_base_nxt = marv_nmvec_wr ? register_value_nxt[31:2]
                                                  : (reset_vector_i[31:2] + 30'h00000001);   // reset_vector + 4
arv_dff #(.WIDTH(30), .ARST_EN(ARST_EN)) u_marv_nmvec_base (.clk_i(hclk_i), .rst_n_i(hresetn_i),
                    .en_i(marv_nmvec_base_en),
                    .d_i (marv_nmvec_base_nxt),
                    .q_o (marv_nmvec_base));

assign marv_nmvec            = {marv_nmvec_base, 2'b00};
assign marv_nmvec_value_read = ({32{marv_nmvec_sel}} & marv_nmvec);


//////======================================================================================================================//////
//////                             DATA-BUS ERROR CAPTURE (marv_epc / marv_eaddr / marv_estat)                              //////
//////======================================================================================================================//////
//
// Captures WHAT faulted and WHERE, at the cycle the error is detected.
//

wire        bus_error_now     = wb_bus_error_load_i | wb_bus_error_store_i;
wire        estat_valid;
wire        estat_capture     = bus_error_now & ~estat_valid;   // first fault only
wire        estat_overrun_set = bus_error_now &  estat_valid;   // a second one while unread

// W1C from software: writing 1 to a bit clears it.
wire        marv_estat_sel  = (register_select[62] & bank_marv_ctl);   // 0x7FE (same 0x7C0-0x7FF bank)
wire        marv_estat_wr   = (marv_estat_sel      & ~disable_write);
wire        estat_w1c_valid = marv_estat_wr & register_value_nxt[0];
wire        estat_w1c_ovr   = marv_estat_wr & register_value_nxt[2];

wire        estat_valid_en  = estat_capture | estat_w1c_valid;
arv_dff #(.ARST_EN(ARST_EN)) u_estat_valid (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(estat_valid_en),
                                                   .d_i (estat_capture), .q_o(estat_valid));

wire        estat_overrun;
wire        estat_ovr_en    = estat_overrun_set | estat_w1c_ovr;
arv_dff #(.ARST_EN(ARST_EN)) u_estat_overrun (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(estat_ovr_en),
                                                   .d_i (estat_overrun_set), .q_o(estat_overrun));

// Classification, sampled with the capture (see the three-way table in the design doc §3.1.1):
//   store       : which half of the access faulted
//   uop_sourced : provenance, latched in the LSU at aph_valid -- NOT sampled here, or an
//                 unrelated later micro-op would be blamed
//   restartable : the sequence that ISSUED this access is still running, so the handler may
//                 replay the macro-op. A UOP access whose own sequence has ALREADY retired
//                 (cm.push's last posted store) is NOT restartable -- replaying it would
//                 double-decrement sp (see doc/spec_compliance_notes.md). Uses wb_uop_seq_alive, not a level
//                 check on ex_uop_enable: the level cannot tell WHICH sequence is running and
//                 misreports back-to-back cm.pushes under heavy wait states.
wire        estat_store_d   = wb_bus_error_store_i;
wire        estat_uop_d     = wb_uop_sourced_i;
wire        estat_restart_d = wb_uop_sourced_i & wb_uop_seq_alive_i & ~wb_uop_jt_sourced_i;

wire  [2:0] estat_class;
arv_dff #(.WIDTH(3), .ARST_EN(ARST_EN)) u_estat_class (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(estat_capture),
                                                   .d_i ({estat_restart_d, estat_uop_d, estat_store_d}),
                                                   .q_o (estat_class));

wire [31:0] marv_epc_reg;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_marv_epc (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(estat_capture), .d_i(wb_pc_i),        .q_o(marv_epc_reg));

wire [31:0] marv_eaddr_reg;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_marv_eaddr (
              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(estat_capture), .d_i(wb_data_addr_i), .q_o(marv_eaddr_reg));

// Read paths. marv_epc/marv_eaddr are MRO in the read-only window (addr[11:10]==11, 0xFFC/0xFFD);
// marv_estat is MRW/W1C beside marv_ctl in the read/write window (0x7FE).
assign bank_marv_epc         = (ex_csr_reg_addr_i[11:6]==6'b111111) & register_select[60] & is_active & ~ex_excp_illegal_inst;
assign marv_epc_value_read   = {32{bank_marv_epc}}   & marv_epc_reg;

assign bank_marv_eaddr       = (ex_csr_reg_addr_i[11:6]==6'b111111) & register_select[61] & is_active & ~ex_excp_illegal_inst;
assign marv_eaddr_value_read = {32{bank_marv_eaddr}} & marv_eaddr_reg;

assign bank_marv_estat       = marv_estat_sel & ~ex_excp_illegal_inst;
// estat_class = {restartable, uop_sourced, store}
assign marv_estat_value_read = {32{bank_marv_estat}} & {27'h0,
                                                        estat_class[1],   // [4] uop_sourced
                                                        estat_class[2],   // [3] restartable
                                                        estat_overrun,    // [2] overrun
                                                        estat_class[0],   // [1] store
                                                        estat_valid};     // [0] valid


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                         INTERFACE TO THE CUSTOM CSR REGISTERS                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
generate
    if (CCSR_EN==1'b1) begin : WITH_CCSR

        // Assign the custom CSR banks
        // Gate by ~ex_excp_illegal_inst to suppress spurious transactions on privilege violations
        // or write-to-read-only faults. No combinatorial loop risk: any_bank_known uses raw
        // address comparisons and does not depend on ccsr_bank_o.
        assign      ccsr_bank_o[0]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b100000);    // Bank  0 - User-Mode      : Read-Write --> 0x800-0x83F
        assign      ccsr_bank_o[1]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b100001);    // Bank  1 - User-Mode      : Read-Write --> 0x840-0x87F
        assign      ccsr_bank_o[2]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b100010);    // Bank  2 - User-Mode      : Read-Write --> 0x880-0x8BF
        assign      ccsr_bank_o[3]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b100011);    // Bank  3 - User-Mode      : Read-Write --> 0x8C0-0x8FF
        assign      ccsr_bank_o[4]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b110011);    // Bank  4 - User-Mode      : Read-Only  --> 0xCC0-0xCFF
        assign      ccsr_bank_o[5]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b010111);    // Bank  5 - Supervisor-Mode: Read-Write --> 0x5C0-0x5FF
        assign      ccsr_bank_o[6]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b100111);    // Bank  6 - Supervisor-Mode: Read-Write --> 0x9C0-0x9FF
        assign      ccsr_bank_o[7]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b110111);    // Bank  7 - Supervisor-Mode: Read-Only  --> 0xDC0-0xDFF
        assign      ccsr_bank_o[8]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b011111);    // Bank  8 - Machine-Mode   : Read-Write --> 0x7C0-0x7FF
        assign      ccsr_bank_o[9]     =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b101111);    // Bank  9 - Machine-Mode   : Read-Write --> 0xBC0-0xBFF
        assign      ccsr_bank_o[10]    =     is_active   & ~ex_excp_illegal_inst & (ex_csr_reg_addr_i[11:6]==6'b111111);    // Bank 10 - Machine-Mode   : Read-Only  --> 0xFC0-0xFFF

        // Protect 0x7FF: mask out register_select[63] from bank 8 to prevent external CCSR
        // from reading/writing the built-in IRQ kill config register.
        // Protect 0xFFE (reset_vector, reg 62) and the RO custom bank indices that alias a
        // built-in (0xFFC-0xFFF), so they are not exposed through the external CCSR interface.
        wire        ro_custom_ccsr_mask   = (ex_csr_reg_addr_i[11:6]==6'b111111) & is_active;
        wire        reset_vector_ccsr_mask= (ex_csr_reg_addr_i[11:6]==6'b111111) & is_active;
        // register_select is indexed by addr[5:0], so the 0x7C0 and 0xFC0 banks COLLIDE on it:
        // 0x7FE and 0xFFE are both select[62]. Each masked index must therefore OR together every
        // built-in that lands on it, or the external custom-CSR interface aliases one of them.
        // Getting this wrong is invisible at CCSR_EN=0 (the default) and shows only at CCSR_EN=1.
        wire [63:0] ccsr_reg_sel_masked   = register_select & ~{
                      (bank_marv_ctl | ro_custom_ccsr_mask),    // [63] 0x7FF marv_ctl  / 0xFFF marv_cfg
                      (bank_marv_ctl | reset_vector_ccsr_mask),  // [62] 0x7FE marv_estat/ 0xFFE reset_vector
                      (bank_marv_ctl | ro_custom_ccsr_mask),    // [61] 0x7FD marv_nmvec/ 0xFFD marv_eaddr
                       ro_custom_ccsr_mask,                     // [60] 0xFFC marv_epc
                       60'h0};

        // Assign other control signals
        assign      ccsr_reg_sel_o     = {64{is_active & (|ccsr_bank_o)}} & ccsr_reg_sel_masked;
        assign      ccsr_wen_o         =     is_active   & ~disable_write & (|ccsr_bank_o);

        // Use ccsr_rdata_i (not ex_csr_reg_dest_wdata_o) as the old-value source for CSRRS/CSRRC:
        // when a custom CSR is selected, ex_csr_reg_dest_wdata_o == ccsr_rdata_i anyway (all other
        // bank contributions are zero-masked), this is functionally equivalent but breaks the
        // combinatorial feedthrough time_val_i -> counters_rdata_o -> ex_csr_reg_dest_wdata_o -> ccsr_wdata_o.
        wire [31:0] ccsr_wdata_nxt     = is_csrrw ?                    ex_csr_rs1_operand_i  :
                                         is_csrrs ? (ccsr_rdata_i |    ex_csr_rs1_operand_i) :
                                                    (ccsr_rdata_i & ~  ex_csr_rs1_operand_i) ;
        assign      ccsr_wdata_o       = {32{is_active}} &   ccsr_wdata_nxt ;
        // Bank-gated AND masked by the built-in selects sharing those banks (marv_ctl 0x7FF,
        // reset_vector 0xFFE): built-in CSR reads are immune to external
        // ccsr_rdata_i discipline - an ill-behaved CCSR driving rdata from bank decode alone
        // cannot corrupt them.
        assign      ccsr_value_read    = {32{is_active   & (|ccsr_bank_o) & ~(marv_ctl_sel | marv_nmvec_sel | bank_reset_vector | bank_marv_cfg |
                                                                              marv_estat_sel | bank_marv_epc | bank_marv_eaddr)}} &  ccsr_rdata_i;

    end else begin        : WITHOUT_CCSR

        // Disable the CCSR interface
        wire [31:0] ccsr_rdata_unused;
        assign      ccsr_rdata_unused  = ccsr_rdata_i;
        assign      ccsr_value_read    = 32'h00000000;
        assign      ccsr_bank_o        = 11'h000;
        assign      ccsr_reg_sel_o     = 64'h0000000000000000;
        assign      ccsr_wdata_o       = 32'h00000000;
        assign      ccsr_wen_o         = 1'b0;

    end
endgenerate




//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                            JVT CSR (ZCMT EXTENSION)                                                  //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

generate
    if (ZCMT_EN==1'b1) begin : WITH_JVT

        // JVT CSR is at address 0x017 (User Read-Write)
        wire   bank_jvt       = (ex_csr_reg_addr_i[11:6]==6'b000000) & is_active & ~ex_excp_illegal_inst;
        wire   jvt_sel        = (register_select['h17] &  bank_jvt);
        wire   jvt_wr         = (jvt_sel               & ~disable_write);

        // 26-bit register (bits[31:6] = base; bits[5:0] fixed to 0, mode field not implemented)
        wire  [25:0] jvt_base_reg;
        arv_dff #(.WIDTH(26), .ARST_EN(ARST_EN)) u_jvt_base (
                         .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(jvt_wr),
                                                              .d_i (register_value_nxt[31:6]),
                                                              .q_o (jvt_base_reg));

        assign jvt_base_o     = {jvt_base_reg, 6'b0};
        assign jvt_value_read = ({32{jvt_sel }} & jvt_base_o);

    end else begin        : WITHOUT_JVT

        assign jvt_value_read = 32'h0;
        assign jvt_base_o     = 32'h0;

    end
endgenerate


// Lint cleanup
generate
    if (ZICNTR_EN == 1'b0 && ZIHPM_NR == 0) begin : gen_counter_bank_unused
        wire       bank_counter_raw_unused  = bank_counter_raw;
        wire       bank_counterh_raw_unused = bank_counterh_raw;
    end
    if (ZICNTR_EN == 1'b0) begin : gen_ctr_en_unused
        wire [2:0] ctr_en_unused            = ctr_en;
    end
    if (ZIHPM_NR == 0) begin : gen_hpm_ctr_en_unused
        wire [7:0] hpm_ctr_en_unused        = hpm_ctr_en;
    end else begin : gen_hpm_ctr_en_unimpl_unused
        // Only counters 0..ZIHPM_NR-1 exist, so HPM_IMPL_MASK leaves the enable
        // bits of the unimplemented counters (7:ZIHPM_NR) without a consumer.
        // Sink them via the constant mask -- no ZIHPM_NR as an index, keeping
        // to the convention arv_csr_hpm.v uses to avoid VER-318.
        wire [7:0] hpm_ctr_en_unimpl_unused = hpm_ctr_en & ~HPM_IMPL_MASK;
    end
endgenerate

endmodule // arv_csr_top

`default_nettype wire

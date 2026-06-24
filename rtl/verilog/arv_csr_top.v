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
    input  wire     [3:0] ex_csr_control_i,
    input  wire    [31:0] ex_csr_rs1_operand_i,
    input  wire    [11:0] ex_csr_reg_addr_i,

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
    input  wire           ex_excp_load_address_misaligned_i,
    input  wire           ex_excp_store_address_misaligned_i,
    input  wire           wb_excp_load_access_fault_i,
    input  wire           wb_excp_store_access_fault_i,

// PIPELINE READY SIGNALS (FOR DRAIN DETECTION)
    input  wire           ex_alu_ready_i,
    input  wire           ex_ldst_ready_i,
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

// WRITE-BACK SUPPRESSION
    output wire           trap_kill_ex_o,
    output wire           trap_kill_wb_o,

// IRQ KILL FOR MULTI-CYCLE OPERATIONS
    input  wire           ex_alu_is_killable_i,
    input  wire           ex_uop_is_killable_i,
    input  wire           ex_uop_jt_active_i,
    input  wire           id_uop_jt_start_i,
    output wire           trap_kill_muldiv_o,
    output wire           trap_kill_uop_o,
    output wire           ex_uop_excp_abort_o,

// OTHERS
    input  wire     [7:0] hartid_i,
    input  wire           init_pc_i,
    input  wire    [31:0] reset_vector_i,
    output wire     [1:0] if_priv_mode_o,
    output wire     [1:0] priv_mode_ldst_o,

// NMI (SMRNMI)
    input  wire           nmi_i,
    input  wire    [31:0] nmi_vector_i,

// ZICNTR TIME INTERFACE
    output wire           time_req_o,
    input  wire           time_gnt_i,
    input  wire    [63:0] time_val_i,

// INSTRUCTION RETIRE (FOR MINSTRET)
    input  wire           inst_retired_i,

// HPM EVENTS
    input  wire     [7:0] id_hpm_events_i,
    input  wire     [7:0] hpm_platform_events_i

);

// USER PARAMETERs
//======================================
parameter                 ARST_EN             =  1'b1;        // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 C_EXT_EN            =  1'b0;        // Compressed instructions enabled
parameter                 M_EXT_EN            =  1'b0;        // M extension enabled (multiply+divide)
parameter                 B_EXT_EN            =  1'b0;        // B extension enabled (bit manipulation)
parameter                 ZCA_EN              =  1'b0;        // Zca extension enable
parameter                 ZCB_EN              =  1'b0;        // Zcb extension enable
parameter                 ZCMP_EN             =  1'b0;        // Zcmp extension enable
parameter                 ZCMT_EN             =  1'b0;        // Zcmt extension enable (table jumps)
parameter                 ZBB_EN              =  1'b0;        // Zbb extension enable
parameter                 ZBA_EN              =  1'b0;        // Zba extension enable
parameter                 ZBS_EN              =  1'b0;        // Zbs extension enable
parameter                 MUL_1C_EN           =  1'b0;        // Single-cycle multiplier
parameter                 MUL_4C_EN           =  1'b0;        // Four-cycle multiplier
parameter                 MUL_16C_EN          =  1'b0;        // Sixteen-cycle multiplier
parameter                 DIV_12C_EN          =  1'b0;        // Radix-8 divider (12 cycles)
parameter                 DIV_17C_EN          =  1'b0;        // Radix-4 divider (17 cycles)
parameter                 DIV_33C_EN          =  1'b0;        // Radix-2 divider (33 cycles)
parameter                 CCSR_EN             =  1'b1;        // Enable Custom-CSR interface
parameter                 RV32I_EN            =  1'b1;        // RV32I base ISA (RV32E if 0)
parameter                 NMI_EN              =  1'b0;        // Smrnmi extension enable (resumable NMI)
parameter                 SU_MODE_EN          =  1'b1;        // S+U privilege modes (0=M-only, 1=M+S+U)
parameter                 ZICNTR_EN           =  1'b0;        // Zicntr extension enable (cycle, time, instret)
parameter           [3:0] ZIHPM_NR            =  4'h0;        // Zihpm: number of HPM counters (0-8)
parameter                 SINGLE_CYCLE_BRANCH =  1'b1;        // 1=zero-bubble taken branch (max IPC); 0=one-bubble (max Fmax)
parameter          [11:0] RTL_VERSION         = 12'h000;      // RTL release version exposed through mimpid[31:20]
parameter          [31:0] MVENDORID           = 32'h00000000; // JEDEC-encoded vendor ID
parameter          [31:0] MARCHID             = 32'h00000000; // arvern architecture ID


//////======================================================================================================================//////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////======================================================================================================================//////

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
wire                [1:0] privilege_mode_nxt;
wire                      privilege_mode_update;

wire                      machine_invalid;
wire                      hypervisor_invalid;
wire                      supervisor_invalid;
wire                      write_invalid;
wire                      nmi_csr_absent;
wire                      any_bank_known;
wire                      unimplemented_csr;
wire                      ex_excp_illegal_inst;
wire                [4:0] marv_ctl_reg;
wire               [31:0] marv_ctl_value_read;
wire                      bank_nmi_handling;
wire                      bank_nmi_vector;
wire               [31:0] nmi_vector_value_read;
wire                      bank_reset_vector;
wire               [31:0] reset_vector_value_read;

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
wire                [7:0] mcounteren_hpm;
wire                      trap_taken_hpm;
wire                      trap_is_irq_hpm;
wire                [9:0] core_events;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                             CSR DECODING AND CONTROL                                                 //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//----------------------------------------------------------------------------------//
// CSR Instructions Read/Write rules according to the spec:                         //
//                                                                                  //
//                            + Write if:                                           //
//                                         CSRRW : always                           //
//                                         CSRRS : not rs1==x0                      //
//                                         CSRRC : not rs1==x0                      //
//                                         CSRRWI: always                           //
//                                         CSRRSI: not uimm[4:0]==0                 //
//                                         CSRRCI: not uimm[4:0]==0                 //
//                                                                                  //
//                            + Read if:                                            //
//                                         CSRRW : not rd==x0                       //
//                                         CSRRS : always                           //
//                                         CSRRC : always                           //
//                                         CSRRWI: not rd==x0                       //
//                                         CSRRSI: always                           //
//                                         CSRRCI: always                           //
//                                                                                  //
//----------------------------------------------------------------------------------//

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
assign     register_value_nxt      = is_csrrw ?                            ex_csr_rs1_operand_i :  // CSRRW
                                     is_csrrs ? ex_csr_reg_dest_wdata_o |  ex_csr_rs1_operand_i :  // CSRRS
                                                ex_csr_reg_dest_wdata_o & ~ex_csr_rs1_operand_i ;  // CSRRC

// MIP[9] (SEIP) RMW write-back, per RISC-V Privileged Architecture §3.1.9
// (Passages 207-208): "Only the software-writable SEIP bit participates in
// the read-modify-write sequence of a CSRRS or CSRRC instruction." If we
// name the SW-writable bit B and the external interrupt controller signal E,
// the spec mandates  CSRRS: B := B  |  rs1[9]   (NOT (B|E) |  rs1[9])
//                    CSRRC: B := B  & ~rs1[9]   (NOT (B|E) & ~rs1[9])
// The architectural READ at register_value_nxt[9] still includes E (correct
// per the same passage — `rd` receives `B || E`); only the WRITE-BACK path
// for sip_seip_sw uses this un-OR'd computation. sip_seip_sw_from_traps is
// the current B forwarded back from arv_csr_traps.
assign     mip_seip_sw_rmw_nxt     = is_csrrw ?                             ex_csr_rs1_operand_i[9] :  // CSRRW
                                     is_csrrs ?  sip_seip_sw_from_traps  |  ex_csr_rs1_operand_i[9] :  // CSRRS
                                                 sip_seip_sw_from_traps  & ~ex_csr_rs1_operand_i[9] ;  // CSRRC

// CSR Register selection
assign     register_select         = ({{63{1'b0}}, 1'b1} << ex_csr_reg_addr_i[5:0]);

// Read CSR value to be written to the integer registers.
assign     ex_csr_reg_dest_wr_o    = is_active & ~disable_read & ~ex_excp_illegal_inst;
assign     ex_csr_reg_dest_wdata_o = ccsr_value_read        |
                                     ids_value_read         |
                                     traps_value_read       |
                                     jvt_value_read         |
                                     marv_ctl_value_read    |
                                     nmi_vector_value_read  |
                                     reset_vector_value_read|
                                     counters_value_read    |
                                     hpm_value_read         ;

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
                                                                            .d_i (privilege_mode_update ? privilege_mode_nxt : privilege_mode),
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
assign     machine_invalid         = acc_priv_is_machine &  (privilege_mode!=2'b11)  ;
assign     hypervisor_invalid      = acc_priv_is_hyper;   // H not implemented: always illegal regardless of privilege mode
assign     supervisor_invalid      = acc_priv_is_super   &  (privilege_mode==2'b00)  ;
assign     write_invalid           = (ex_csr_reg_addr_i[11:10]==2'b11)    & is_active & ~disable_write; // Attempt to write to a Read-only

// NMI CSR bank 0x740-0x744 (bits[11:6]=6'b011101): absent when NMI_EN=0
assign     nmi_csr_absent          = (ex_csr_reg_addr_i[11:6]==6'b011101) & is_active & (NMI_EN==1'b0);

// Zicntr raw bank signals (no ~ex_excp_illegal_inst to avoid combinatorial loop)
wire       bank_counter_raw        = (ex_csr_reg_addr_i[11:6]==6'b110000) & is_active;
wire       bank_counterh_raw       = (ex_csr_reg_addr_i[11:6]==6'b110010) & is_active;

// Counter CSR access denied when the layered filter blocks it:
//   - S-mode access: gated by mcounteren only.
//   - U-mode access: gated by (mcounteren & scounteren) - both M and S must allow.
wire [2:0] ctr_en                  = mcounteren     & (scounteren[2:0]  | {3{privilege_mode == 2'b01}});
wire [7:0] hpm_ctr_en              = mcounteren_hpm & (scounteren[10:3] | {8{privilege_mode == 2'b01}});

assign     zicntr_access_denied    = (privilege_mode != 2'b11) & ZICNTR_EN   & ((bank_counter_raw  & ((register_select[0] & ~ctr_en[0]) |   // cycle
                                                                                                      (register_select[1] & ~ctr_en[1]) |   // time
                                                                                                      (register_select[2] & ~ctr_en[2]))) | // instret
                                                                                (bank_counterh_raw & ((register_select[0] & ~ctr_en[0]) |   // cycleh
                                                                                                      (register_select[1] & ~ctr_en[1]) |   // timeh
                                                                                                      (register_select[2] & ~ctr_en[2])))); // instreth

assign     zihpm_access_denied     = (privilege_mode != 2'b11) & ZIHPM_NR_EN &  (bank_counter_raw | bank_counterh_raw) &
                                                                               |(register_select[10:3] & HPM_IMPL_MASK & ~hpm_ctr_en);

// Catch-all: detect access to any CSR address not covered by any implemented bank.
// Spec: "Attempts to access a non-existent CSR raise an illegal instruction exception."
assign     any_bank_known          = (ex_csr_reg_addr_i[11:6]==6'b001100)                          |  // 0x300-0x33F (mstatus, mie, mtvec, misa, mcounteren, mcountinhibit, mhpmevent3-10, menvcfg, menvcfgh RAZ/WI)
                                     (ex_csr_reg_addr_i[11:6]==6'b001101)                          |  // 0x340-0x37F (mscratch, mepc, mcause, mtval, mip)
                                     (ex_csr_reg_addr_i[11:6]==6'b000100)                          |  // 0x100-0x13F (sstatus, sie, stvec, scounteren, senvcfg RAZ/WI)
                                     (ex_csr_reg_addr_i[11:6]==6'b000101)                          |  // 0x140-0x17F (sscratch, sepc, scause, stval, sip)
                                     (ex_csr_reg_addr_i[11:6]==6'b000110)                          |  // 0x180-0x1BF (satp RAZ/WI -- Bare mode, no paged translation)
                                     (ex_csr_reg_addr_i[11:6]==6'b111100)                          |  // 0xF00-0xF3F (mvendorid, marchid, mimpid, mhartid)
                                     (ex_csr_reg_addr_i[11:6]==6'b011111)                          |  // 0x7C0-0x7FF (marv_ctl)
                         (NMI_EN  &  (ex_csr_reg_addr_i[11:6]==6'b011101))                         |  // 0x740-0x77F (NMI CSRs)
                         (NMI_EN  &  (ex_csr_reg_addr_i[11:6]==6'b111111) & register_select[63])   |  // 0xFFF (CCSR: nmi_vector)
                                     (ex_csr_reg_addr_i[11:6]==6'b111111) & register_select[62]    |  // 0xFFE (CCSR: reset_vector)
                         (ZCMT_EN &  (ex_csr_reg_addr_i[11:6]==6'b000000) & register_select['h17]) |  // 0x017 (jvt)
                       (ZICNTR_EN &  (ex_csr_reg_addr_i[11:6]==6'b101100))                         |  // 0xB00-0xB3F (mcycle, minstret)
                       (ZICNTR_EN &  (ex_csr_reg_addr_i[11:6]==6'b101110))                         |  // 0xB80-0xBBF (mcycleh, minstreth)
                       (ZICNTR_EN &  (ex_csr_reg_addr_i[11:6]==6'b110000))                         |  // 0xC00-0xC3F (cycle, time, instret)
                       (ZICNTR_EN &  (ex_csr_reg_addr_i[11:6]==6'b110010))                         |  // 0xC80-0xCBF (cycleh, timeh, instreth)
                     (ZIHPM_NR_EN &  (ex_csr_reg_addr_i[11:6]==6'b101100))                         |  // 0xB00-0xB3F (mhpmcounter3-N)
                     (ZIHPM_NR_EN &  (ex_csr_reg_addr_i[11:6]==6'b101110))                         |  // 0xB80-0xBBF (mhpmcounterh3-N)
                     (ZIHPM_NR_EN &  (ex_csr_reg_addr_i[11:6]==6'b110000))                         |  // 0xC00-0xC3F (hpmcounter3-N)
                     (ZIHPM_NR_EN &  (ex_csr_reg_addr_i[11:6]==6'b110010))                         |  // 0xC80-0xCBF (hpmcounterh3-N)
                         (CCSR_EN & ((ex_csr_reg_addr_i[11:6]==6'b100000)                          |  // CCSR bank 0: 0x800-0x83F
                                     (ex_csr_reg_addr_i[11:6]==6'b100001)                          |  // CCSR bank 1: 0x840-0x87F
                                     (ex_csr_reg_addr_i[11:6]==6'b100010)                          |  // CCSR bank 2: 0x880-0x8BF
                                     (ex_csr_reg_addr_i[11:6]==6'b100011)                          |  // CCSR bank 3: 0x8C0-0x8FF
                                     (ex_csr_reg_addr_i[11:6]==6'b110011)                          |  // CCSR bank 4: 0xCC0-0xCFF
                                     (ex_csr_reg_addr_i[11:6]==6'b010111)                          |  // CCSR bank 5: 0x5C0-0x5FF
                                     (ex_csr_reg_addr_i[11:6]==6'b100111)                          |  // CCSR bank 6: 0x9C0-0x9FF
                                     (ex_csr_reg_addr_i[11:6]==6'b110111)                          |  // CCSR bank 7: 0xDC0-0xDFF
                                     (ex_csr_reg_addr_i[11:6]==6'b101111)                          |  // CCSR bank 9: 0xBC0-0xBFF
                                     (ex_csr_reg_addr_i[11:6]==6'b111111)));                          // CCSR bank 10: 0xFC0-0xFFF

assign     unimplemented_csr       = is_active & ~any_bank_known;

assign     ex_excp_illegal_inst    = machine_invalid         |
                                     hypervisor_invalid      |
                                     supervisor_invalid      |
                                     write_invalid           |
                                     nmi_csr_absent          |
                                     zicntr_access_denied    |
                                     zihpm_access_denied     |
                                     unimplemented_csr       ;

// NMI CSR bank active only when NMI_EN=1 and no privilege/write error
assign     bank_nmi_handling       = (ex_csr_reg_addr_i[11:6]==6'b011101) & is_active & ~ex_excp_illegal_inst & (NMI_EN==1'b1);

// NMI vector RO CSR at 0xFFF: returns nmi_vector_i; active only when NMI_EN=1
assign     bank_nmi_vector         = (ex_csr_reg_addr_i[11:6]==6'b111111) & register_select[63] & is_active & ~ex_excp_illegal_inst & (NMI_EN==1'b1);
assign     nmi_vector_value_read   = {32{bank_nmi_vector}} & nmi_vector_i;

// Reset-vector RO CSR at 0xFFE (custom MRO): returns the integrator-driven reset_vector_i so
// firmware can discover its own reset PC. Internal CSR -> always present, independent of CCSR_EN
// (and of NMI_EN). Privilege is enforced by the generic machine_invalid check (addr[9:8]==11).
assign     bank_reset_vector       = (ex_csr_reg_addr_i[11:6]==6'b111111) & register_select[62] & is_active & ~ex_excp_illegal_inst;
assign     reset_vector_value_read = {32{bank_reset_vector}} & reset_vector_i;


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
              .ZCA_EN             (ZCA_EN             ),
              .ZCB_EN             (ZCB_EN             ),
              .ZCMP_EN            (ZCMP_EN            ),
              .ZCMT_EN            (ZCMT_EN            ),
              .ZBA_EN             (ZBA_EN             ),
              .ZBB_EN             (ZBB_EN             ),
              .ZBS_EN             (ZBS_EN             ),
              .MUL_1C_EN          (MUL_1C_EN          ),
              .MUL_4C_EN          (MUL_4C_EN          ),
              .MUL_16C_EN         (MUL_16C_EN         ),
              .DIV_12C_EN         (DIV_12C_EN         ),
              .DIV_17C_EN         (DIV_17C_EN         ),
              .DIV_33C_EN         (DIV_33C_EN         ),
              .CCSR_EN            (CCSR_EN            ),
              .NMI_EN             (NMI_EN             ),
              .SU_MODE_EN         (SU_MODE_EN         ),
              .RV32I_EN           (RV32I_EN           ),
              .ZICNTR_EN          (ZICNTR_EN          ),
              .ZIHPM_NR           (ZIHPM_NR           ),
              .SINGLE_CYCLE_BRANCH(SINGLE_CYCLE_BRANCH),
              .RTL_VERSION        (RTL_VERSION        ),
              .MVENDORID          (MVENDORID          ),
              .MARCHID            (MARCHID            )) arv_csr_ids_inst (

    .hartid_i                           ( hartid_i                           ),
    .bank_misa_en_i                     ( bank_misa_en                       ),
    .bank_ids_en_i                      ( bank_ids_en                        ),
    .register_sel_i                     ( register_select                    ),
    .ids_rdata_o                        ( ids_value_read                     )
);


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
                .NMI_EN      (NMI_EN    ),
                .SU_MODE_EN  (SU_MODE_EN)) arv_csr_traps_inst (

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

// TRAP INTERFACE TO DECODE
    .trap_pending_o                     ( trap_pending_o                     ),
    .trap_stall_o                       ( trap_stall_o                       ),
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
    .id_excp_ecall_i                    ( id_excp_ecall_i                    ),
    .ex_excp_illegal_inst_i             ( ex_excp_illegal_inst               ),
    .ex_excp_load_address_misaligned_i  ( ex_excp_load_address_misaligned_i  ),
    .ex_excp_store_address_misaligned_i ( ex_excp_store_address_misaligned_i ),
    .wb_excp_load_access_fault_i        ( wb_excp_load_access_fault_i        ),
    .wb_excp_store_access_fault_i       ( wb_excp_store_access_fault_i       ),

// PIPELINE READY SIGNALS (FOR DRAIN DETECTION)
    .ex_alu_ready_i                     ( ex_alu_ready_i                     ),
    .ex_ldst_ready_i                    ( ex_ldst_ready_i                    ),
    .ex_csr_ready_i                     ( ex_csr_ready_o                     ),
    .ex_uop_has_branch_i                ( ex_uop_has_branch_i                ),
    .ex_uop_ready_i                     ( ex_uop_ready_i                     ),
    .ex_uop_take_branch_i               ( ex_uop_take_branch_i               ),
    .id_instruction_valid_i             ( id_instruction_valid_i             ),
    .wb_ldst_ready_i                    ( wb_ldst_ready_i                    ),
    .wb_dph_ongoing_i                   ( wb_dph_ongoing_i                   ),

// PIPELINE MONITORING & CONTROL IN CASE OF TRAP
    .if_stop_cmd_o                      ( if_stop_cmd_o                      ),
    .lockup_o                           ( lockup_o                           ),

// PC PIPELINE INPUTS (FOR MEPC SAVE)
    .id_pc_i                            ( id_pc_i                            ),
    .ex_pc_i                            ( ex_pc_i                            ),
    .wb_pc_i                            ( wb_pc_i                            ),

// DATA ADDRESS PIPELINE (FOR MTVAL SAVE)
    .ex_data_addr_i                     ( ex_data_addr_i                     ),
    .wb_data_addr_i                     ( wb_data_addr_i                     ),

// PRIVILEGE MODE
    .priv_mode_current_i                ( privilege_mode_effective           ),
    .priv_mode_next_o                   ( privilege_mode_nxt                 ),
    .priv_mode_update_o                 ( privilege_mode_update              ),
    .priv_mode_ldst_o                   ( priv_mode_ldst_o                  ),

// WRITE-BACK SUPPRESSION
    .trap_kill_ex_o                     ( trap_kill_ex_o                     ),
    .trap_kill_wb_o                     ( trap_kill_wb_o                     ),

// IRQ KILL FOR MULTI-CYCLE OPERATIONS
    .trap_kill_muldiv_o                 ( trap_kill_muldiv_o                 ),
    .trap_kill_uop_o                    ( trap_kill_uop_o                    ),
    .ex_uop_excp_abort_o                ( ex_uop_excp_abort_o                ),
    .marv_ctl_i                         ( marv_ctl_reg                       ),
    .ex_alu_is_killable_i               ( ex_alu_is_killable_i               ),
    .ex_uop_is_killable_i               ( ex_uop_is_killable_i               ),
    .ex_uop_jt_active_i                 ( ex_uop_jt_active_i                 ),
    .id_uop_jt_start_i                  ( id_uop_jt_start_i                  ),

// INITIALIZATION OF THE TRAP VECTOR DEFAULT VALUES
    .init_pc_i                          ( init_pc_i                          ),
    .reset_vector_i                     ( reset_vector_i                     ),

// NMI (SMRNMI)
    .nmi_i                              ( nmi_i                              ),
    .nmi_vector_i                       ( nmi_vector_i                       ),

// HPM TRAP EVENTS
    .trap_taken_o                       ( trap_taken_hpm                     ),
    .trap_is_irq_o                      ( trap_is_irq_hpm                    ),

// MIP[9] SEIP RMW WRITE-BACK (see §3.1.9 P207-208 comment near `mip_seip_sw_rmw_nxt`)
    .sip_seip_sw_o                      ( sip_seip_sw_from_traps             ),
    .mip_seip_sw_rmw_nxt_i              ( mip_seip_sw_rmw_nxt                )

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

        arv_csr_cntr #(.ARST_EN(ARST_EN)) arv_csr_cntr_inst (

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
//   [3]   nmi_escape_lockup    : allow NMI to escape lockup state (only meaningful when NMI_EN=1)
//   [4]   wfi_clkgate_dis      : disable WFI clock-gating (keep hclk running during WFI sleep).
//                                Safety/debug/power-policy knob; WFI still stalls and wakes
//                                normally. Default 0 = clock-gating enabled (current behaviour).
// Reset 5'b00111: [2:0]=1 (enabled), [3]=0 (NMI escape off), [4]=0 (WFI gating on)
arv_dff #(.WIDTH(5), .RST_VAL(5'b00111), .ARST_EN(ARST_EN)) u_marv_ctl (.clk_i(hclk_i), .rst_n_i(hresetn_i),
                    .en_i(marv_ctl_wr),
                    .d_i (marv_ctl_wr ? {register_value_nxt[4], NMI_EN & register_value_nxt[3], register_value_nxt[2:0]} : marv_ctl_reg),
                    .q_o (marv_ctl_reg));

assign marv_ctl_value_read = ({32{marv_ctl_sel}} & {27'h0, marv_ctl_reg});


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
        // Protect 0xFFF: mask out register_select[63] from bank 10 when NMI_EN=1 so the
        // built-in nmi_vector RO CSR is not aliased to the external CCSR interface.
        // Protect 0xFFF (nmi_vector, reg 63, when NMI_EN=1) and 0xFFE (reset_vector, reg 62, always)
        // from the external CCSR bank 10 so the built-in RO CSRs are not aliased to the interface.
        wire        nmi_vector_ccsr_mask  = (ex_csr_reg_addr_i[11:6]==6'b111111) & is_active & (NMI_EN==1'b1);
        wire        reset_vector_ccsr_mask= (ex_csr_reg_addr_i[11:6]==6'b111111) & is_active;
        wire [63:0] ccsr_reg_sel_masked   = register_select & ~{(bank_marv_ctl | nmi_vector_ccsr_mask), reset_vector_ccsr_mask, 62'h0};

        // Assign other control signals
        assign      ccsr_reg_sel_o     = {64{is_active}} &  ccsr_reg_sel_masked;
        assign      ccsr_wen_o         =     is_active   & ~disable_write & (|ccsr_bank_o);

        // Use ccsr_rdata_i (not ex_csr_reg_dest_wdata_o) as the old-value source for CSRRS/CSRRC:
        // when a custom CSR is selected, ex_csr_reg_dest_wdata_o == ccsr_rdata_i anyway (all other
        // bank contributions are zero-masked), this is functionally equivalent but breaks the
        // combinatorial feedthrough time_val_i -> counters_rdata_o -> ex_csr_reg_dest_wdata_o -> ccsr_wdata_o.
        wire [31:0] ccsr_wdata_nxt     = is_csrrw ?                   ex_csr_rs1_operand_i :
                                         is_csrrs ? ccsr_rdata_i |    ex_csr_rs1_operand_i :
                                                    ccsr_rdata_i & ~  ex_csr_rs1_operand_i ;
        assign      ccsr_wdata_o       = {32{is_active}} &   ccsr_wdata_nxt ;
        assign      ccsr_value_read    = {32{is_active   & (|ccsr_bank_o)}} &  ccsr_rdata_i;  // bank-gated: don't let ccsr_rdata_i bleed into a non-CCSR read

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
                                                              .d_i (jvt_wr ? register_value_nxt[31:6] : jvt_base_reg),
                                                              .q_o (jvt_base_reg));

        assign jvt_base_o     = {jvt_base_reg, 6'b0};
        assign jvt_value_read = ({32{jvt_sel }} & jvt_base_o);

    end else begin        : WITHOUT_JVT

        assign jvt_value_read = 32'h0;
        assign jvt_base_o     = 32'h0;

    end
endgenerate


endmodule // arv_csr_top

`default_nettype wire

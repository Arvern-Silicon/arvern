//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_decode
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_decode.v
// Module Description : RISC-V instruction decoder
//                      (unified standard + compressed;
//                       branch detect + pipeline control + register/CSR fan-out)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_decode (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// FROM/TO INSTRUCTION FETCH UNIT
    input  wire    [31:0] id_instruction_i,
    input  wire           id_instruction_valid_i,
    input  wire     [1:0] id_priv_mode_i,
    input  wire    [31:0] id_pc_i,
    output wire           id_branch_detect_o,
    output wire           id_branch_cancel_o,
    output wire    [31:0] id_branch_target_o,
    output wire    [31:0] id_branch_target_nxt_o,
    output wire           id_slow_branch_o,
    output wire    [31:0] id_slow_branch_target_o,
    output wire           id_instruction_request_o,

// INTEGER REGISTER READ DURING DECODE PHASE (FOR ALU & BRANCHES)
    input  wire    [31:0] id_reg_src1_rdata_w_fwd_i,
    input  wire    [31:0] id_reg_src2_rdata_w_fwd_i,
    input  wire    [31:0] id_branch_rs1_rdata_w_fwd_i,
    input  wire    [31:0] id_branch_rs2_rdata_w_fwd_i,
    output wire     [4:0] id_reg_src1_sel_o,
    output wire     [4:0] id_reg_src2_sel_o,
    output wire     [4:0] id_branch_rs1_fast_sel_o,
    output wire     [4:0] id_branch_rs2_fast_sel_o,

// JALR SHADOW REGISTER
    input  wire    [31:0] id_jalr_shadow_rdata_i,
    input  wire     [4:0] id_jalr_shadow_sel_i,
    output wire           id_opcode_jalr_o,
    output wire           ex_uop_ret_branch_o,

// INTEGER REGISTER READ DURING EXECUTION PHASE (FOR LOAD-STORE)
    output wire     [4:0] ex_reg_src1_sel_o,
    output wire     [4:0] ex_reg_src2_sel_o,

// INTEGER REGISTER WRITE
    input  wire     [4:0] wb_reg_dest_sel_i,
    output wire     [4:0] ex_reg_dest_sel_o,

// FROM/TO ALU
    input  wire           ex_alu_ready_i,
    output wire    [16:0] ex_alu_control_o,
    output wire     [4:0] ex_alu_mode_o,
    output wire           ex_alu_select_o,

// FROM/TO LOAD-STORE UNIT
    input  wire           ex_ldst_ready_i,
    input  wire           wb_ldst_ready_i,
    input  wire           wb_load_busy_i,
    output wire     [4:0] ex_ldst_control_o,

// FROM/TO CSR REGISTERS
    input  wire           cfg_timeout_wait_i,
    input  wire           cfg_trap_sret_i,
    input  wire           ex_csr_ready_i,
    output wire     [3:0] ex_csr_control_o,
    output wire           ex_uop_has_branch_o,
    output wire           ex_uop_take_branch_o,

// FROM/TO UOP SEQUENCER
    input  wire           ex_uop_ready_i,
    input  wire           ex_uop_kill_i,
    input  wire           ex_uop_excp_abort_i,
    output wire     [9:0] ex_uop_control_o,
    output wire           ex_c_cm_push_nxt_o,
    output wire           id_uop_start_o,
    output wire           id_uop_jt_start_o,
    output wire     [7:0] id_uop_ldst_start_o,
    input  wire           ex_uop_jt_branch_active_i,
    input  wire    [31:0] ex_uop_jt_branch_target_i,

// TO ALU, LOAD-STORE UNIT AND CSR REGISTERS
    output wire    [31:0] ex_operand1_o,
    output wire    [31:0] ex_operand2_o,

// TRAPS & IRQ RELATED
    output wire           id_excp_ebreak_o,
    output wire           id_excp_ecall_o,
    output wire           id_excp_illegal_inst_o,
    output wire           id_opcode_mret_o,
    output wire           id_opcode_sret_o,
    output wire           id_opcode_mnret_o,

// TRAP INTERFACE FROM CSR
    input  wire           trap_pending_i,
    input  wire           trap_stall_i,
    input  wire           trap_branch_detect_i,
    input  wire    [31:0] trap_branch_target_i,
    input  wire           wfi_wakeup_i,
    output wire           id_wfi_active_o,

// PC PIPELINE OUTPUT
    output wire    [31:0] ex_pc_o,

// INSTRUCTION RETIRED (for minstret)
    output wire           id_inst_retired_o,

// HPM PIPELINE EVENTS
    output wire     [7:0] id_hpm_events_o

);

// USER PARAMETERs
//=================================================================================================================
parameter                 ARST_EN      =  1'b1;      // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 ZCA_EN       =  1'b1;      // Zca extension enable (base compressed instructions)
parameter                 ZCB_EN       =  1'b0;      // Zcb extension enable (code-size reduction)
parameter                 ZCMP_EN      =  1'b0;      // Zcmp extension enable (push/pop/double move)
parameter                 ZCMT_EN      =  1'b0;      // Zcmt extension enable (table jumps)
parameter                 UOP_EN       =  1'b0;      // Zcmt or Zcmp extension enable
//--------------------------------------------------------------------------------------------------------------
parameter                 ZBB_EN       =  1'b0;      // Zbb extension enable (basic bit manipulation)
parameter                 ZBA_EN       =  1'b0;      // Zba extension enable (address generation)
parameter                 ZBS_EN       =  1'b0;      // Zbs extension enable (single-bit operations)
parameter                 ZBC_EN       =  1'b0;      // Zbc extension enable (carry-less multiplication)
//--------------------------------------------------------------------------------------------------------------
parameter                 MUL_EN       =  1'b0;      // Multiply enabled (Zmmul or M) - required for C.MUL
parameter                 DIV_EN       =  1'b0;      // Divide enabled (M extension only) - DIV/DIVU/REM/REMU
//--------------------------------------------------------------------------------------------------------------
parameter                 NMI_EN       =  1'b0;      // Smrnmi extension enable (resumable NMI)
parameter                 SU_MODE_EN   =  1'b1;      // S+U privilege modes (0=M-only; 1=M+S+U)
parameter                 ZIHPM_NR     =  0;         // Zihpm: number of HPM counters (0-8)
//=================================================================================================================

// Derived parameter: any C extension enabled (Zca, Zcb, or Zcmp)
localparam                C_EXT_EN     = (ZCA_EN | ZCB_EN | ZCMP_EN);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                            STANDARD OPCODE DECODING                                                  //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Compression / Standard instruction detection
wire         ex_uop_has_branch;
wire         id_use_c_path           = (id_instruction_i[1:0] != 2'b11) & ~ex_uop_has_branch & C_EXT_EN;
wire         id_use_std_path         = (id_instruction_i[1:0] == 2'b11) & ~ex_uop_has_branch;

wire  [31:0] id_std_instruction      =  id_instruction_i;
wire  [15:0] id_c_instruction        =  id_instruction_i[15:0]; // C instructions are pre-aligned in the fetch unit


//==================================================================================================================================================//
//                                           OPCODE BINARY ENCODING FOR EACH TYPE                                                                   //
//==================================================================================================================================================//
//                                                                                                                                                  //
//      31 30             25 24       21 20 19          15 14    12 11        8  7  6                 0                                             //
//     +--+-----------------+-----------+--+--------------+--------+-----------+--+--------------------+                                            //
//     |        funct7      |      rs2     |      rs1     | funct3 |      rd      |        opcode      |  R-Type  (Op-Imm-Reg)                      //
//     +--+-----------------+-----------+--+--------------+--------+-----------+--+--------------------+                                            //
//     |             imm[11:0]             |      rs1     | funct3 |      rd      |        opcode      |  I-Type  (Op-Imm-Reg, JALR, Load, System)  //
//     +--+-----------------+-----------+--+--------------+--------+-----------+--+--------------------+                                            //
//     |      imm[11:5]     |      rs2     |      rs1     | funct3 |   imm[4:0]   |        opcode      |  S-Type  (Store)                           //
//     +--+-----------------+-----------+--+--------------+--------+-----------+--+--------------------+                                            //
//     |12|    imm[10:5]    |      rs2     |      rs1     | funct3 | imm[4:1]  |11|        opcode      |  B-Type  (Branch)                          //
//     +--+-----------------+-----------+--+--------------+--------+-----------+--+--------------------+                                            //
//     |                       imm[31:12]                          |      rd      |        opcode      |  U-Type  (LUI, AUIPC)                      //
//     +--+-----------------+-----------+--+--------------+--------+-----------+--+--------------------+                                            //
//     |20|            imm[10:1]        |11|        imm[19:12]     |      rd      |        opcode      |  J-Type  (JAL)                             //
//     +--+-----------------+-----------+--+--------------+--------+-----------+--+--------------------+                                            //
//      31 30             25 24       21 20 19          15 14    12 11        8  7  6                 0                                             //
//                                                                                                                                                  //
//==================================================================================================================================================//

// Standard instruction opcodes (when not compressed)
wire         id_std_opcode_lui       =  id_use_std_path & (id_std_instruction[6:2]  == {2'b01, 3'b101       }) ;  // LUI        opcode: LUI
wire         id_std_opcode_auipc     =  id_use_std_path & (id_std_instruction[6:2]  == {2'b00, 3'b101       }) ;  // AUIPC      opcode: AUIPC
wire         id_std_opcode_jal       =  id_use_std_path & (id_std_instruction[6:2]  == {2'b11, 3'b011       }) ;  // JAL        opcode: JAL
wire         id_std_opcode_jalr      =  id_use_std_path & (id_std_instruction[6:2]  == {2'b11, 3'b001       }) ;  // JALR       opcode: JALR
wire         id_std_opcode_branch    =  id_use_std_path & (id_std_instruction[6:2]  == {2'b11, 3'b000       }) ;  // Branch     opcode: BEQ, BNE, BLT, BGE, BLTU, BGEU
wire         id_std_opcode_load      =  id_use_std_path & (id_std_instruction[6:2]  == {2'b00, 3'b000       }) ;  // Load       opcode: LB, LH, LW, LBU, LHU
wire         id_std_opcode_store     =  id_use_std_path & (id_std_instruction[6:2]  == {2'b01, 3'b000       }) ;  // Store      opcode: SB, SH, SW
wire         id_std_opcode_opimm     =  id_use_std_path & (id_std_instruction[6:2]  == {2'b00, 3'b100       }) ;  // Op-Imm-Reg opcode: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
wire         id_std_opcode_op        =  id_use_std_path & (id_std_instruction[6:2]  == {2'b01, 3'b100       }) ;  // Op-Reg-Reg opcode: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
wire         id_std_opcode_miscmem   =  id_use_std_path & (id_std_instruction[6:2]  == {2'b00, 3'b011       }) ;  // Misc-Mem   opcode: FENCE, FENCE.TSO, PAUSE
wire         id_std_opcode_system    =  id_use_std_path & (id_std_instruction[6:2]  == {2'b11, 3'b100       }) ;  // System     opcode: ECALL, EBREAK, MRET, WFI, CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI

// M-extension encoding detect for cases where it is illegal
wire         id_m_op_encoding        = (id_std_instruction[6:2] == {2'b01, 3'b100}) & (id_std_instruction[31:25] == 7'b0000001);
wire         id_m_invalid            =  id_m_op_encoding & ( ~(MUL_EN[0] | DIV_EN[0]) | (MUL_EN[0] & ~DIV_EN[0] & id_std_instruction[14]));

// Reserved LOAD/STORE funct3 detection (RV64-only encodings or fully reserved on RV32)
wire         id_std_load_funct3_rsv  = (id_std_instruction[14:12] == 3'b011) |
                                       (id_std_instruction[14:12] == 3'b110) |
                                       (id_std_instruction[14:12] == 3'b111) ;
wire         id_std_store_funct3_rsv = (id_std_instruction[14:12] == 3'b011) |
                                        id_std_instruction[14];

// Forward wire declarations
wire   [2:0] id_std_funct3;
wire         id_opcode_ecall;
wire         id_opcode_ebreak;
wire         id_opcode_wfi;
wire         id_opcode_mret;
wire         id_opcode_sret;
wire         id_opcode_mnret;

// Illegal opcode detection
wire         id_std_opcode_error     = (id_use_std_path & ((id_std_instruction[1:0] != {              2'b11})                               |  // Not Supported: non-32 bit instructions
                                                           (id_std_instruction[4:2] == {       3'b010      })                               |  // Not Supported: custom-0, custom-1, NMSUB, reserved
                                                           (id_std_instruction[4:2] == {       3'b110      })                               |  // Not Supported: OP-IMM-32, OP-32, custom-2, custom-3
                                                           (id_std_instruction[4:2] == {       3'b111      })                               |  // Not Supported: reserved
                                                           (id_std_instruction[6:5] == {2'b10              })                               |  // Not Supported: MADD, MSUB, NMSUB, NMADD, OP-FP, OP-V, custom-2
                                                           (id_std_instruction[6:2] == {2'b11, 3'b101      })                               |  // Not Supported: OP-VE
                                                           (id_std_instruction[6:2] == {2'b01, 3'b011      })                               |  // Not Supported: AMO
                                                           (id_std_instruction[6:2] == {2'b00, 3'b001      })                               |  // Not Supported: LOAD-FP
                                                           (id_std_instruction[6:2] == {2'b01, 3'b001      })                               |  // Not Supported: STORE-FP
                                                            id_m_invalid                                                                    |  // Not Supported: MUL/DIV when M ext absent or DIV under Zmmul
                                                          ((id_std_instruction[6:2] == {2'b00, 3'b000      }) & id_std_load_funct3_rsv)     |  // Reserved LOAD funct3
                                                          ((id_std_instruction[6:2] == {2'b01, 3'b000      }) & id_std_store_funct3_rsv)    |  // Reserved STORE funct3
                                                          ( id_std_opcode_branch & ((id_std_funct3 == 3'b010) | (id_std_funct3 == 3'b011))) |  // Reserved BRANCH funct3 010/011
                                                          ( id_std_opcode_system &  (id_std_funct3 == 3'b100))                              |  // Reserved SYSTEM funct3=100
                                                          ( id_std_opcode_system &  (id_std_funct3 == 3'b000)  &
                                                              ~(id_opcode_ecall | id_opcode_ebreak | id_opcode_wfi |
                                                                id_opcode_mret  | id_opcode_sret   | (id_opcode_mnret & NMI_EN)))        )) |  // SYSTEM funct3=000 non-canonical priv-op
                                       (~C_EXT_EN & (id_instruction_i[1:0] != 2'b11))                                                     ;    // Non-32-bit-encoded fetch with C extension disabled

// Decode the Instruction types
wire         id_std_type_I           =  id_std_opcode_load  | id_std_opcode_system | id_std_opcode_opimm ;
wire         id_std_type_S           =  id_std_opcode_store ;
wire         id_std_type_U           =  id_std_opcode_lui   | id_std_opcode_auipc;
wire         id_std_type_notU        = ~id_std_type_U       & id_use_std_path    ;


// Standard immediate generation (excluding branches, which is decoded separately to optimize timing)
wire  [31:0] id_std_imm;
assign       id_std_imm[31]          =       id_use_std_path    &     id_std_instruction[31]       ;

assign       id_std_imm[30:20]       = ({11{ id_std_type_U }}   &     id_std_instruction[30:20]  ) |
                                       ({11{ id_std_type_notU}} & {11{id_std_instruction[31]   }}) ;

assign       id_std_imm[19:12]       = ({ 8{ id_std_type_U }}   &     id_std_instruction[19:12]  ) |
                                       ({ 8{ id_std_type_notU}} & { 8{id_std_instruction[31]   }}) ;

assign       id_std_imm[11]          = (     id_std_type_notU   &     id_std_instruction[31]     ) ;

assign       id_std_imm[10:5]        = ({ 6{ id_std_type_notU}} &     id_std_instruction[30:25]  ) ;

assign       id_std_imm[4:1]         = ({ 4{ id_std_type_I }}   &     id_std_instruction[24:21]  ) |
                                       ({ 4{ id_std_type_S }}   &     id_std_instruction[11:8]   ) ;

assign       id_std_imm[0]           = (     id_std_type_I      &     id_std_instruction[20]     ) |
                                       (     id_std_type_S      &     id_std_instruction[7]      ) ;

// Standard immediate generation for jump and branches
// Ungated per-type immediates (used for pre-computed branch target adders)
wire  [31:0] id_std_imm_j            = {{12{id_std_instruction[31]}},  id_std_instruction[19:12],
                                            id_std_instruction[20],    id_std_instruction[30:21], 1'b0};
wire  [31:0] id_std_imm_b            = {{20{id_std_instruction[31]}},  id_std_instruction[7],
                                            id_std_instruction[30:25], id_std_instruction[11:8],  1'b0};
wire  [31:0] id_std_imm_i            = {{20{id_std_instruction[31]}},  id_std_instruction[31:20]};


// Functions fields extraction
assign       id_std_funct3           =  id_std_instruction[14:12];
wire   [2:0] id_std_funct3_br        =  id_std_instruction[14:12];
wire   [6:0] id_std_funct7           =  id_std_instruction[31:25];
wire  [11:0] id_std_funct12          =  id_std_instruction[31:20];


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                           Zbb EXTENSION INSTRUCTION DETECTION                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Logic for OP major opcode
wire         id_zbb_opcode_op        = ZBB_EN & id_std_opcode_op    & ( (id_std_funct7 == 7'b0110000) |
                                                                        (id_std_funct7 == 7'b0000101) |
                                                                        (id_std_funct7 == 7'b0000100) |
                                                                       ((id_std_funct7 == 7'b0100000) & (id_std_funct3[2] == 1'b1)));

// Logic for OP-IMM major opcode
wire         id_zbb_opcode_opimm     = ZBB_EN & id_std_opcode_opimm & (((id_std_funct3 == 3'b001) & ( id_std_funct7 == 7'b0110000))  |
                                                                       ((id_std_funct3 == 3'b101) & ((id_std_funct7 == 7'b0110000)   |
                                                                                                     (id_std_funct7 == 7'b0110100)   |
                                                                                                     (id_std_funct7 == 7'b0010100))));

// Zbb (Basic Bit Manipulation) - R-type instructions (opcode 0110011)
wire         id_zbb_andn             = id_zbb_opcode_op    & (id_std_funct7 == 7'b0100000) & (id_std_funct3 == 3'b111);  // AND with NOT
wire         id_zbb_orn              = id_zbb_opcode_op    & (id_std_funct7 == 7'b0100000) & (id_std_funct3 == 3'b110);  // OR with NOT
wire         id_zbb_xnor             = id_zbb_opcode_op    & (id_std_funct7 == 7'b0100000) & (id_std_funct3 == 3'b100);  // XOR with NOT
wire         id_zbb_min              = id_zbb_opcode_op    & (id_std_funct7 == 7'b0000101) & (id_std_funct3 == 3'b100);  // Signed minimum
wire         id_zbb_minu             = id_zbb_opcode_op    & (id_std_funct7 == 7'b0000101) & (id_std_funct3 == 3'b101);  // Unsigned minimum
wire         id_zbb_max              = id_zbb_opcode_op    & (id_std_funct7 == 7'b0000101) & (id_std_funct3 == 3'b110);  // Signed maximum
wire         id_zbb_maxu             = id_zbb_opcode_op    & (id_std_funct7 == 7'b0000101) & (id_std_funct3 == 3'b111);  // Unsigned maximum
wire         id_zbb_rol              = id_zbb_opcode_op    & (id_std_funct7 == 7'b0110000) & (id_std_funct3 == 3'b001);  // Rotate left
wire         id_zbb_ror              = id_zbb_opcode_op    & (id_std_funct7 == 7'b0110000) & (id_std_funct3 == 3'b101);  // Rotate right
wire         id_zbb_zext_h           = id_zbb_opcode_op    & (id_std_funct7 == 7'b0000100) & (id_std_funct3 == 3'b100)   // Zero-extend halfword
                                                                                           & (id_std_instruction[24:20] == 5'b00000);

// Zbb - I-type instructions (opcode 0010011)
wire         id_zbb_clz              = id_zbb_opcode_opimm & (id_std_funct12 == 12'b011000000000) & (id_std_funct3 == 3'b001);  // Count leading zeros
wire         id_zbb_ctz              = id_zbb_opcode_opimm & (id_std_funct12 == 12'b011000000001) & (id_std_funct3 == 3'b001);  // Count trailing zeros
wire         id_zbb_cpop             = id_zbb_opcode_opimm & (id_std_funct12 == 12'b011000000010) & (id_std_funct3 == 3'b001);  // Count population
wire         id_zbb_sext_b           = id_zbb_opcode_opimm & (id_std_funct12 == 12'b011000000100) & (id_std_funct3 == 3'b001);  // Sign-extend byte
wire         id_zbb_sext_h           = id_zbb_opcode_opimm & (id_std_funct12 == 12'b011000000101) & (id_std_funct3 == 3'b001);  // Sign-extend halfword
wire         id_zbb_rori             = id_zbb_opcode_opimm & (id_std_funct7  ==  7'b0110000)      & (id_std_funct3 == 3'b101);  // Rotate right immediate
wire         id_zbb_rev8             = id_zbb_opcode_opimm & (id_std_funct12 == 12'b011010011000) & (id_std_funct3 == 3'b101);  // Reverse bytes
wire         id_zbb_orc_b            = id_zbb_opcode_opimm & (id_std_funct12 == 12'b001010000111) & (id_std_funct3 == 3'b101);  // OR-combine bytes

// Forward declarations for Zcb signals assigned in COMPRESSED DECODING section below.
wire         id_c_sext_b;
wire         id_c_zext_h;
wire         id_c_sext_h;

// Combined detection for any Zbb instruction (including C.SEXT.B/C.SEXT.H)
wire         id_any_zbb              = id_zbb_andn   | id_zbb_orn  | id_zbb_xnor | id_zbb_min   | id_zbb_minu | id_zbb_max  | id_zbb_maxu | id_zbb_orc_b |
                                       id_zbb_rol    | id_zbb_ror  | id_zbb_clz  | id_zbb_ctz   | id_zbb_cpop | id_zbb_rori | id_zbb_rev8 |
                                       id_zbb_zext_h | id_c_zext_h |
                                       id_zbb_sext_b | id_c_sext_b |
                                       id_zbb_sext_h | id_c_sext_h ;


//////======================================================================================================================//////
//////                                       Zba EXTENSION (Address Generation)                                             //////
//////======================================================================================================================//////

// Zba (Address Generation) - R-type instructions (opcode 0110011)
// All Zba instructions compute: rd = rs1 + (rs2 << N) for array indexing
wire         id_zba_opcode_op        = ZBA_EN & id_std_opcode_op & (id_std_funct7 == 7'b0010000);

wire         id_zba_sh1add           = id_zba_opcode_op & (id_std_funct3 == 3'b010);  // rd = rs1 + (rs2 << 1)
wire         id_zba_sh2add           = id_zba_opcode_op & (id_std_funct3 == 3'b100);  // rd = rs1 + (rs2 << 2)
wire         id_zba_sh3add           = id_zba_opcode_op & (id_std_funct3 == 3'b110);  // rd = rs1 + (rs2 << 3)

// Combined detection for any Zba instruction
wire         id_any_zba              = id_zba_sh1add | id_zba_sh2add | id_zba_sh3add;


//////======================================================================================================================//////
//////                                       Zbs EXTENSION (Single-Bit Operations)                                          //////
//////======================================================================================================================//////

// Zbs (Single-Bit Operations) - R-type and I-type instructions
// R-type: opcode 0110011, I-type: opcode 0010011
wire         id_zbs_opcode_op        = ZBS_EN & id_std_opcode_op    & ((id_std_funct7 == 7'b0010100) |
                                                                       (id_std_funct7 == 7'b0100100) |
                                                                       (id_std_funct7 == 7'b0110100));

wire         id_zbs_opcode_opimm     = ZBS_EN & id_std_opcode_opimm & ((id_std_funct7 == 7'b0010100) |
                                                                       (id_std_funct7 == 7'b0100100) |
                                                                       (id_std_funct7 == 7'b0110100));

// Zbs - R-type instructions (opcode 0110011)
wire         id_zbs_bset             = id_zbs_opcode_op    & (id_std_funct7 == 7'b0010100) & (id_std_funct3 == 3'b001);  // Set bit: rd = rs1 | (1 << rs2[4:0])
wire         id_zbs_bclr             = id_zbs_opcode_op    & (id_std_funct7 == 7'b0100100) & (id_std_funct3 == 3'b001);  // Clear bit: rd = rs1 & ~(1 << rs2[4:0])
wire         id_zbs_binv             = id_zbs_opcode_op    & (id_std_funct7 == 7'b0110100) & (id_std_funct3 == 3'b001);  // Invert bit: rd = rs1 ^ (1 << rs2[4:0])
wire         id_zbs_bext             = id_zbs_opcode_op    & (id_std_funct7 == 7'b0100100) & (id_std_funct3 == 3'b101);  // Extract bit: rd = (rs1 >> rs2[4:0]) & 1

// Zbs - I-type instructions (opcode 0010011) - immediate variants
wire         id_zbs_bseti            = id_zbs_opcode_opimm & (id_std_funct7 == 7'b0010100) & (id_std_funct3 == 3'b001);  // Set bit immediate
wire         id_zbs_bclri            = id_zbs_opcode_opimm & (id_std_funct7 == 7'b0100100) & (id_std_funct3 == 3'b001);  // Clear bit immediate
wire         id_zbs_binvi            = id_zbs_opcode_opimm & (id_std_funct7 == 7'b0110100) & (id_std_funct3 == 3'b001);  // Invert bit immediate
wire         id_zbs_bexti            = id_zbs_opcode_opimm & (id_std_funct7 == 7'b0100100) & (id_std_funct3 == 3'b101);  // Extract bit immediate

// Combined detection for any Zbs instruction
wire         id_any_zbs              = id_zbs_bset  | id_zbs_bclr  | id_zbs_binv  | id_zbs_bext |
                                       id_zbs_bseti | id_zbs_bclri | id_zbs_binvi | id_zbs_bexti;

//////======================================================================================================================//////
//////                                       Zbc EXTENSION (Carry-less multiplication)                                      //////
//////======================================================================================================================//////

wire         id_zbc_opcode_op        = ZBC_EN & id_std_opcode_op & (id_std_funct7 == 7'b0000101) & ~id_std_funct3[2];

// Note: as CLMUL instruction are uniquely encoded using funct3, we can use the standard instruction path for decoding
//wire       id_zbc_clmul            = id_zbc_opcode_op & (id_std_funct3 == 3'b001);  // Carry-less multiply (low)
//wire       id_zbc_clmulh           = id_zbc_opcode_op & (id_std_funct3 == 3'b011);  // Carry-less multiply (high)
//wire       id_zbc_clmulr           = id_zbc_opcode_op & (id_std_funct3 == 3'b010);  // Carry-less multiply (reverse)

// Combined detection for any Zbc instruction
wire         id_any_zbc              = id_zbc_opcode_op;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                             COMPRESSED INSTRUCTIONS DECODING                                         //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//--------------------------------------------------------------------------------------
// Assign the decoding bitfields
//--------------------------------------------------------------------------------------

// Compressed instruction fields (extracted in parallel for speed)
wire   [1:0] id_c_op                 =  id_c_instruction[1:0];
wire   [2:0] id_c_funct3             =  id_c_instruction[15:13];
wire   [1:0] id_c_funct2             =  id_c_instruction[6:5];
wire   [5:0] id_c_funct6             =  id_c_instruction[15:10];
wire   [4:0] id_c_rd_rs1             =  id_c_instruction[11:7];
wire   [4:0] id_c_rs2                =  id_c_instruction[6:2];
wire   [2:0] id_c_rd_p               =  id_c_instruction[9:7];
wire   [2:0] id_c_rs1_p              =  id_c_instruction[9:7];
wire   [2:0] id_c_rs2_p              =  id_c_instruction[4:2];

// Expand compressed register notation (3-bit to 5-bit)
wire   [4:0] id_c_rd_p_exp           = {2'b01, id_c_rd_p };
wire   [4:0] id_c_rs1_p_exp          = {2'b01, id_c_rs1_p};
wire   [4:0] id_c_rs2_p_exp          = {2'b01, id_c_rs2_p};

// Expand compressed register notation for stack pointer relative registers (s0-s7): s0, s1 -> x8, x9; s2–s7 -> x18–x23
wire   [4:0] id_c_rs1_sreg_exp       = (id_c_rs1_p[2:1]==2'b00) ? {2'b01, id_c_rs1_p[2:0]} : {2'b10, id_c_rs1_p[2:0]};
wire   [4:0] id_c_rs2_sreg_exp       = (id_c_rs2_p[2:1]==2'b00) ? {2'b01, id_c_rs2_p[2:0]} : {2'b10, id_c_rs2_p[2:0]};

// Quadrant detection (for parallel decode)
wire         id_c_q0                 = id_use_c_path & (id_c_op == 2'b00);
wire         id_c_q1                 = id_use_c_path & (id_c_op == 2'b01);
wire         id_c_q2                 = id_use_c_path & (id_c_op == 2'b10);

//--------------------------------------------------------------------------------------
// Compressed opcode decoding
//--------------------------------------------------------------------------------------

// Quadrant 0 instructions (Zca)
wire         id_c_addi4spn           =  ZCA_EN  & id_c_q0 & (id_c_funct3 == 3'b000)    & (id_c_instruction[12:5]  != 8'h00) ;
wire         id_c_lw                 =  ZCA_EN  & id_c_q0 & (id_c_funct3 == 3'b010)    ;
wire         id_c_sw                 =  ZCA_EN  & id_c_q0 & (id_c_funct3 == 3'b110)    ;

// Quadrant 0 instructions (Zcb) - using reserved funct3=100 space
wire         id_c_lbu                =  ZCB_EN  & id_c_q0 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b000) ;
wire         id_c_lhu                =  ZCB_EN  & id_c_q0 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b001) & (id_c_instruction[6] == 1'b0);
wire         id_c_lh                 =  ZCB_EN  & id_c_q0 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b001) & (id_c_instruction[6] == 1'b1);
wire         id_c_sb                 =  ZCB_EN  & id_c_q0 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b010) ;
wire         id_c_sh                 =  ZCB_EN  & id_c_q0 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b011) ;

// Quadrant 1 instructions
wire         id_c_addi               =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b000)    ;
wire         id_c_jal                =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b001)    ;
wire         id_c_li                 =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b010)    ;
wire         id_c_nzimm_q1_b011_ne0  =  id_c_instruction[12] | (|id_c_instruction[6:2]);
wire         id_c_addi16sp           =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b011)    & id_c_nzimm_q1_b011_ne0              & (id_c_rd_rs1 == 5'd2)      ;
wire         id_c_lui                =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b011)    & id_c_nzimm_q1_b011_ne0              & (id_c_rd_rs1 != 5'd2)      ;
wire         id_c_srli               =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12]   == 1'b0)    & (id_c_funct6[1:0] == 2'b00);
wire         id_c_srai               =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12]   == 1'b0)    & (id_c_funct6[1:0] == 2'b01);
wire         id_c_andi               =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_funct6[1:0]       == 2'b10)   ;
wire         id_c_sub                =  ZCA_EN  & id_c_q1 & (id_c_funct6 == 6'b100011) & (id_c_funct2 == 2'b00);
wire         id_c_xor                =  ZCA_EN  & id_c_q1 & (id_c_funct6 == 6'b100011) & (id_c_funct2 == 2'b01);
wire         id_c_or                 =  ZCA_EN  & id_c_q1 & (id_c_funct6 == 6'b100011) & (id_c_funct2 == 2'b10);
wire         id_c_and                =  ZCA_EN  & id_c_q1 & (id_c_funct6 == 6'b100011) & (id_c_funct2 == 2'b11);
wire         id_c_j                  =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b101)    ;
wire         id_c_beqz               =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b110)    ;
wire         id_c_bnez               =  ZCA_EN  & id_c_q1 & (id_c_funct3 == 3'b111)    ;

// Quadrant 1 instructions (Zcb) - using reserved funct3=100 space with [12:10]=111
wire         id_c_zext_b             =  ZCB_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b111) & (id_c_instruction[6:2] == 5'b11000);
assign       id_c_sext_b             =  ZCB_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b111) & (id_c_instruction[6:2] == 5'b11001);
assign       id_c_zext_h             =  ZCB_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b111) & (id_c_instruction[6:2] == 5'b11010);
assign       id_c_sext_h             =  ZCB_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b111) & (id_c_instruction[6:2] == 5'b11011);
wire         id_c_not                =  ZCB_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b111) & (id_c_instruction[6:2] == 5'b11101);
wire         id_c_mul                =  ZCB_EN  & id_c_q1 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12:10] == 3'b111) & (id_c_instruction[6:5] == 2'b10)   & MUL_EN;  // C.MUL requires both Zcb AND (M or Zmmul)

// Quadrant 2 instructions (Zca)
// (C.SLLI rd=0 is reserved as a HINT and must execute as NOP).
wire         id_c_slli               =  ZCA_EN  & id_c_q2 & (id_c_funct3 == 3'b000)    & (id_c_instruction[12] == 1'b0)                         ;
wire         id_c_jr                 =  ZCA_EN  & id_c_q2 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12] == 1'b0) & (id_c_rd_rs1 != 5'd0) & (id_c_rs2 == 5'd0);
wire         id_c_mv                 =  ZCA_EN  & id_c_q2 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12] == 1'b0) &                          (id_c_rs2 != 5'd0);  // C.MV with rd=0 (rs2!=0) is RVC HINTs and must NOT trap (decode as a normal C.MV/C.ADD writing x0, which is naturally a NOP).
wire         id_c_ebreak             =  ZCA_EN  & id_c_q2 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12] == 1'b1) & (id_c_rd_rs1 == 5'd0) & (id_c_rs2 == 5'd0);
wire         id_c_jalr               =  ZCA_EN  & id_c_q2 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12] == 1'b1) & (id_c_rd_rs1 != 5'd0) & (id_c_rs2 == 5'd0);
wire         id_c_add                =  ZCA_EN  & id_c_q2 & (id_c_funct3 == 3'b100)    & (id_c_instruction[12] == 1'b1) &                          (id_c_rs2 != 5'd0);  // C.ADD with rd=0 (rs2!=0) is RVC HINTs and must NOT trap (decode as a normal C.MV/C.ADD writing x0, which is naturally a NOP).
wire         id_c_lwsp               =  ZCA_EN  & id_c_q2 & (id_c_funct3 == 3'b010)    &                                  (id_c_rd_rs1 != 5'd0) ;
wire         id_c_swsp               =  ZCA_EN  & id_c_q2 & (id_c_funct3 == 3'b110)    ;

// Quadrant 2 instructions (Zcmp) - push/pop/move
wire         id_c_cm_push            =  ZCMP_EN & id_c_q2 & (id_c_instruction[15:10] == 6'b101110) & (id_c_instruction[9:8] == 2'b00) & (id_c_instruction[7:4] >= 4'h4) ;
wire         id_c_cm_pop             =  ZCMP_EN & id_c_q2 & (id_c_instruction[15:10] == 6'b101110) & (id_c_instruction[9:8] == 2'b10) & (id_c_instruction[7:4] >= 4'h4) ;
wire         id_c_cm_popret          =  ZCMP_EN & id_c_q2 & (id_c_instruction[15:10] == 6'b101111) & (id_c_instruction[9:8] == 2'b10) & (id_c_instruction[7:4] >= 4'h4) ;
wire         id_c_cm_popretz         =  ZCMP_EN & id_c_q2 & (id_c_instruction[15:10] == 6'b101111) & (id_c_instruction[9:8] == 2'b00) & (id_c_instruction[7:4] >= 4'h4) ;
wire         id_c_cm_mva01s          =  ZCMP_EN & id_c_q2 & (id_c_instruction[15:10] == 6'b101011) & (id_c_instruction[6:5] == 2'b11) ;
wire         id_c_cm_mvsa01          =  ZCMP_EN & id_c_q2 & (id_c_instruction[15:10] == 6'b101011) & (id_c_instruction[6:5] == 2'b01) ;

// Quadrant 2 instructions (Zcmt) - table jumps
wire         id_c_cm_jt              =  ZCMT_EN & id_c_q2 & (id_c_instruction[15:10] == 6'b101000) & (id_c_instruction[9:7] == 3'b000);
wire         id_c_cm_jalt            =  ZCMT_EN & id_c_q2 & (id_c_instruction[15:10] == 6'b101000) & (id_c_instruction[9:7] != 3'b000);

// Compressed opcode enables (pre-gated with path enable)
wire         id_c_opcode_lui         =  id_c_lui;
wire         id_c_opcode_jal         = (id_c_jal    | id_c_j   );
wire         id_c_opcode_jalr        = (id_c_jalr   | id_c_jr  );
wire         id_c_opcode_branch      = (id_c_beqz   | id_c_bnez);
wire         id_c_opcode_load        = (id_c_lw     | id_c_lwsp     | id_c_lbu      | id_c_lhu    | id_c_lh);
wire         id_c_opcode_store       = (id_c_sw     | id_c_swsp     | id_c_sb       | id_c_sh     );
wire         id_c_opcode_opimm       = (id_c_addi   | id_c_addi16sp | id_c_addi4spn | id_c_li     | id_c_andi   | id_c_slli   |
                                        id_c_srli   | id_c_srai     | id_c_zext_b   | id_c_sext_b | id_c_zext_h | id_c_sext_h | id_c_not);
wire         id_c_opcode_op          = (id_c_add    | id_c_mv       | id_c_sub      | id_c_xor    | id_c_or     | id_c_and    | id_c_mul);
wire         id_c_opcode_system      =  id_c_ebreak;

wire         id_c_opcode_uop         = (id_c_cm_push   | id_c_cm_pop    | id_c_cm_popret | id_c_cm_popretz |
                                        id_c_cm_mva01s | id_c_cm_mvsa01 | id_c_cm_jt     | id_c_cm_jalt    );

// Compressed instruction illegal detection
wire         id_c_opcode_error       =  id_use_c_path & ~(id_c_opcode_lui    | id_c_opcode_jal  | id_c_opcode_jalr    |
                                                          id_c_opcode_branch | id_c_opcode_load | id_c_opcode_store   |
                                                          id_c_opcode_opimm  | id_c_opcode_op   | id_c_opcode_system  |
                                                          id_c_opcode_uop   );


//--------------------------------------------------------------------------------------
// Group compressed instructions by register selection pattern to reduce mux depth
//--------------------------------------------------------------------------------------

// Instructions using compressed prime registers (x8-x15) for RS1
wire         id_c_class_rs1_prime    =  id_c_lw      | id_c_sw     | id_c_sub       | id_c_xor    | id_c_or   | id_c_and |
                                        id_c_beqz    | id_c_bnez   | id_c_srli      | id_c_srai   | id_c_andi |
                                        id_c_lbu     | id_c_lhu    | id_c_lh        | id_c_sb     | id_c_sh   |
                                        id_c_zext_b  | id_c_sext_b | id_c_zext_h    | id_c_sext_h | id_c_not  | id_c_mul ;

// Instructions using SP (x2) for RS1
wire         id_c_class_rs1_sp       =  id_c_lwsp    | id_c_swsp   | id_c_addi16sp  | id_c_addi4spn   |
                                        id_c_cm_push | id_c_cm_pop | id_c_cm_popret | id_c_cm_popretz ;

// Instructions using rd/rs1 field for RS1
wire         id_c_class_rs1_rdrs1    =  id_c_jr   | id_c_jalr | id_c_add  | id_c_addi | id_c_slli;

// Instructions using compressed prime registers for RS2
wire         id_c_class_rs2_prime    =  id_c_sw   | id_c_sub  | id_c_xor  | id_c_or   | id_c_and |
                                        id_c_sb   | id_c_sh   | id_c_mul;

// Instructions using rs2 field for RS2
wire         id_c_class_rs2_rs2      =  id_c_swsp | id_c_add  | id_c_mv;

// Instructions using compressed prime registers for RD (bits [9:7])
wire         id_c_class_rd_prime     =  id_c_sub    | id_c_xor    | id_c_or     | id_c_and    |
                                        id_c_srli   | id_c_srai   | id_c_andi   |
                                        id_c_zext_b | id_c_sext_b | id_c_zext_h | id_c_sext_h | id_c_not | id_c_mul;

// Instructions using bits [4:2] for RD (C.ADDI4SPN, C.LW, Zcb loads)
wire         id_c_class_rd_rs2p      =  id_c_lw   | id_c_addi4spn |
                                        id_c_lbu  | id_c_lhu      | id_c_lh;

// Instructions using rd/rs1 field for RD
wire         id_c_class_rd_rdrs1     =  id_c_lwsp | id_c_addi | id_c_li   | id_c_lui | id_c_addi16sp |
                                        id_c_add  | id_c_mv   | id_c_slli ;

// Instructions using x1 (ra) for RD
wire         id_c_class_rd_ra        =  id_c_jal  | id_c_jalr;


//--------------------------------------------------------------------------------------
// Immediate generation for compressed instructions
//--------------------------------------------------------------------------------------

// Build the different types of immediates
wire  [31:0] id_c_imm_addi4spn       = {22'b0, id_c_instruction[10:7], id_c_instruction[12:11], id_c_instruction[5],   id_c_instruction[6], 2'b00};
wire  [31:0] id_c_imm_lwsw           = {25'b0, id_c_instruction[5],    id_c_instruction[12:10], id_c_instruction[6],   2'b00};

// Zcb load/store offsets (byte and halfword)
// LH/LHU/SH share the same immediate encoding (1-bit halfword index)
wire  [31:0] id_c_imm_h              = {30'b0, id_c_instruction[5],    1'b0};
wire  [31:0] id_c_imm_lbu            = {30'b0, id_c_instruction[5],    id_c_instruction[6]};
wire  [31:0] id_c_imm_sb             = {30'b0, id_c_instruction[5],    id_c_instruction[6]};
wire  [31:0] id_c_imm_shamt          = {26'b0, id_c_instruction[12],   id_c_instruction[6:2]};
wire  [31:0] id_c_imm_swsp           = {24'b0, id_c_instruction[8:7],  id_c_instruction[12:9],  2'b00};
wire  [31:0] id_c_imm_addi           = {   {26{id_c_instruction[12]}}, id_c_instruction[12],    id_c_instruction[6:2]};
wire  [31:0] id_c_imm_lui            = {   {14{id_c_instruction[12]}}, id_c_instruction[12],    id_c_instruction[6:2], 12'b0};
wire  [31:0] id_c_imm_lwsp           = {24'b0, id_c_instruction[3:2],  id_c_instruction[12],    id_c_instruction[6:4], 2'b00};
wire  [31:0] id_c_imm_addi16sp       = {   {22{id_c_instruction[12]}}, id_c_instruction[12],    id_c_instruction[4:3], id_c_instruction[5],    id_c_instruction[2],     id_c_instruction[6],   4'b0000};
wire  [31:0] id_c_imm_b              = {   {23{id_c_instruction[12]}}, id_c_instruction[12],    id_c_instruction[6:5], id_c_instruction[2],    id_c_instruction[11:10], id_c_instruction[4:3], 1'b0};
wire  [31:0] id_c_imm_j              = {   {20{id_c_instruction[12]}}, id_c_instruction[12],    id_c_instruction[8],   id_c_instruction[10:9], id_c_instruction[6],     id_c_instruction[7],   id_c_instruction[2], id_c_instruction[11], id_c_instruction[5:3], 1'b0};

// Zcb unary operation immediates
wire  [31:0] id_c_imm_not            = 32'hFFFFFFFF;  // C.NOT   : XOR with -1
wire  [31:0] id_c_imm_zext_b         = 32'h000000FF;  // C.ZEXT.B: AND with 0xFF

// Memory load/store offsets (LW/SW use same format, Zcb loads/stores have their own)
wire  [31:0] id_c_imm_mem_grp        = (id_c_imm_lwsw      & {32{id_c_lw | id_c_sw}}) |
                                       (id_c_imm_lbu       & {32{id_c_lbu}}         ) |
                                       (id_c_imm_sb        & {32{id_c_sb}}          ) |
                                       (id_c_imm_h         & {32{id_c_lh | id_c_lhu | id_c_sh}});

// Stack-based operations
wire  [31:0] id_c_imm_stack_grp      = (id_c_imm_addi4spn  & {32{id_c_addi4spn}}) |
                                       (id_c_imm_addi16sp  & {32{id_c_addi16sp}}) |
                                       (id_c_imm_lwsp      & {32{id_c_lwsp}}    ) |
                                       (id_c_imm_swsp      & {32{id_c_swsp}}    ) ;

// Immediate arithmetic/logical (ADDI/LI/ANDI/LUI + Zcb unary ops)
wire  [31:0] id_c_imm_arith_grp      = (id_c_imm_addi      & {32{id_c_addi | id_c_li | id_c_andi}}) |
                                       (id_c_imm_lui       & {32{id_c_lui}}                       ) |
                                       (id_c_imm_not       & {32{id_c_not}}                       ) |
                                       (id_c_imm_zext_b    & {32{id_c_zext_b}}                    ) ;

// Shift operations
wire  [31:0] id_c_imm_shamt_grp      = (id_c_imm_shamt     & {32{id_c_srli | id_c_srai | id_c_slli}}) ;

// Final compressed immediate selection
wire  [31:0] id_c_imm                =  id_c_imm_mem_grp   |
                                        id_c_imm_stack_grp |
                                        id_c_imm_arith_grp |
                                        id_c_imm_shamt_grp ;



//--------------------------------------------------------------------------------------
// Funct3 / Funct7 pre-decode
//--------------------------------------------------------------------------------------

// Compressed funct3 mapping on standard instructions
wire   [2:0] id_c_funct3_mem         =  3'b010;  // LW/SW
wire   [2:0] id_c_funct3_lbu         =  3'b100;  // LBU (Zcb)
wire   [2:0] id_c_funct3_lhu         =  3'b101;  // LHU (Zcb)
wire   [2:0] id_c_funct3_lh          =  3'b001;  // LH (Zcb)
wire   [2:0] id_c_funct3_sb          =  3'b000;  // SB (Zcb)
wire   [2:0] id_c_funct3_sh          =  3'b001;  // SH (Zcb)
wire   [2:0] id_c_funct3_beq         =  3'b000;  // BEQ
wire   [2:0] id_c_funct3_bne         =  3'b001;  // BNE
wire   [2:0] id_c_funct3_slli        =  3'b001;  // SLLI
wire   [2:0] id_c_funct3_srli_srai   =  3'b101;  // SRLI/SRAI (distinguished by funct7[5])
wire   [2:0] id_c_funct3_andi        =  3'b111;  // ANDI
wire   [2:0] id_c_funct3_addsub      =  3'b000;  // ADD/SUB/MV
wire   [2:0] id_c_funct3_xor         =  3'b100;  // XOR
wire   [2:0] id_c_funct3_or          =  3'b110;  // OR
wire   [2:0] id_c_funct3_and         =  3'b111;  // AND
wire   [2:0] id_c_funct3_mul         =  3'b000;  // MUL (Zcb)
wire   [2:0] id_c_funct3_not         =  3'b100;  // NOT as XOR (Zcb)
wire   [2:0] id_c_funct3_zext_b      =  3'b111;  // ZEXT.B as AND (Zcb)

// Compressed funct3 selection
wire   [2:0] id_c_funct3_selected    = (id_c_funct3_mem       & {3{id_c_lw | id_c_lwsp | id_c_sw | id_c_swsp}} ) |
                                       (id_c_funct3_lbu       & {3{id_c_lbu}}                                  ) |
                                       (id_c_funct3_lhu       & {3{id_c_lhu}}                                  ) |
                                       (id_c_funct3_lh        & {3{id_c_lh}}                                   ) |
                                       (id_c_funct3_sb        & {3{id_c_sb}}                                   ) |
                                       (id_c_funct3_sh        & {3{id_c_sh}}                                   ) |
                                       (id_c_funct3_slli      & {3{id_c_slli}}                                 ) |
                                       (id_c_funct3_srli_srai & {3{id_c_srli | id_c_srai}}                     ) |
                                       (id_c_funct3_andi      & {3{id_c_andi}}                                 ) |
                                       (id_c_funct3_addsub    & {3{id_c_add  | id_c_sub | id_c_mv}}            ) |
                                       (id_c_funct3_mul       & {3{id_c_mul}}                                  ) |
                                       (id_c_funct3_xor       & {3{id_c_xor}}                                  ) |
                                       (id_c_funct3_or        & {3{id_c_or}}                                   ) |
                                       (id_c_funct3_and       & {3{id_c_and}}                                  ) |
                                       (id_c_funct3_not       & {3{id_c_not}}                                  ) |
                                       (id_c_funct3_zext_b    & {3{id_c_zext_b}}                               ) ;

wire   [2:0] id_c_funct3_selected_br = (id_c_funct3_beq       & {3{id_c_beqz}}                                 ) |
                                       (id_c_funct3_bne       & {3{id_c_bnez}}                                 ) ;

// Funct7 generation
wire   [6:0] id_c_funct7_sub         =  7'b0100000;  // SUB/SRAI
wire   [6:0] id_c_funct7_mul         =  7'b0000001;  // MUL (M extension)
wire   [6:0] id_c_funct7_default     =  7'b0000000;  // Default


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       COMBINE STANDARD & COMPRESSED OPCODES                                          //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Unified opcodes (simple OR - both paths pre-enabled, so no additional gating needed)
wire         id_opcode_lui           =  id_std_opcode_lui      |  id_c_opcode_lui;
wire         id_opcode_auipc         =  id_std_opcode_auipc;   // No compressed equivalent
wire         id_opcode_jal           =  id_std_opcode_jal      |  id_c_opcode_jal;
wire         id_opcode_jalr          =  id_std_opcode_jalr     |  id_c_opcode_jalr;
assign       id_opcode_jalr_o        =  id_opcode_jalr;
wire         id_opcode_branch        =  id_std_opcode_branch   |  id_c_opcode_branch;
wire         id_opcode_load          =  id_std_opcode_load     |  id_c_opcode_load;
wire         id_opcode_store         =  id_std_opcode_store    |  id_c_opcode_store;
wire         id_opcode_opimm         =  id_std_opcode_opimm    |  id_c_opcode_opimm;
wire         id_opcode_op            =  id_std_opcode_op       |  id_c_opcode_op;
wire         id_opcode_miscmem       =  id_std_opcode_miscmem; // No compressed equivalent
wire         id_opcode_system        =  id_std_opcode_system   |  id_c_opcode_system;

// Forward declarations for privilege/mode illegality flags assigned in SYSTEM INSTRUCTIONS section below.
wire         id_opcode_mret_illegal;
wire         id_opcode_sret_illegal;
wire         id_opcode_wfi_illegal;
wire         id_opcode_mnret_illegal;

// Error detection
wire         id_opcode_error         =  id_std_opcode_error    |  // Illegal standard instruction
                                        id_c_opcode_error      |  // Illegal compressed instruction
                                        id_opcode_mret_illegal |  // Illegal MRET usage
                                        id_opcode_sret_illegal |  // Illegal SRET usage
                                        id_opcode_wfi_illegal  |  // Illegal WFI usage
                                        id_opcode_mnret_illegal;  // Illegal MNRET usage

wire         id_opcode_valid         = (id_instruction_valid_i & !id_opcode_error);


// Decode the Instruction types for later use
wire         id_type_R               =  id_opcode_op;
wire         id_type_I               =  id_opcode_load | id_opcode_system | id_opcode_opimm;
wire         id_type_U               =  id_opcode_lui  | id_opcode_auipc;


// Register source1 selection
wire   [4:0] id_reg_src1_sel         =  id_use_std_path       ? id_std_instruction[19:15] :  // Standard format
                                        id_c_class_rs1_prime  ? id_c_rs1_p_exp            :  // Compressed prime registers
                                        id_c_class_rs1_sp     ? 5'd2                      :  // SP (x2)
                                        id_c_class_rs1_rdrs1  ? id_c_rd_rs1               :  // rd/rs1 field
                                        id_c_cm_mva01s        ? id_c_rs1_sreg_exp         :  // CM.MVA01S: src1 = s*
                                        id_c_cm_mvsa01        ? 5'd10                     :  // CM.MVSA01: src1 = a0 (x10)
                                                                5'd0                      ;  // Default to x0

// Register source2 selection
wire   [4:0] id_reg_src2_sel         =  id_use_std_path       ? id_std_instruction[24:20] :  // Standard format
                                        id_c_class_rs2_prime  ? id_c_rs2_p_exp            :  // Compressed prime registers
                                        id_c_class_rs2_rs2    ? id_c_rs2                  :  // rs2 field
                                        id_c_cm_mva01s        ? id_c_rs2_sreg_exp         :  // CM.MVA01S: src2 = s*
                                        id_c_cm_mvsa01        ? 5'd11                     :  // CM.MVSA01: src2 = a1 (x11)
                                                                5'd0                      ;  // Default to x0 (branches)

// Destination register selection
wire   [4:0] id_reg_dest_sel         =  id_use_std_path       ? id_std_instruction[11:7]  :  // Standard format
                                        id_c_class_rd_prime   ? id_c_rd_p_exp             :  // Compressed prime registers [9:7]
                                        id_c_class_rd_rs2p    ? id_c_rs2_p_exp            :  // Compressed register [4:2] (C.ADDI4SPN)
                                        id_c_class_rd_ra      ? 5'd1                      :  // x1 (ra) for JAL/JALR
                                        id_c_class_rd_rdrs1   ? id_c_rd_rs1               :  // rd/rs1 field
                                                                5'd0                      ;  // No dest or x0

// Final funct3/funct7/funct12 muxes
wire   [2:0] id_funct3               =  id_use_std_path       ? id_std_funct3             :
                                                                id_c_funct3_selected      ;

wire   [2:0] id_funct3_br            =  id_use_std_path       ? id_std_funct3_br          :
                                                                id_c_funct3_selected_br   ;

wire   [6:0] id_funct7               =  id_use_std_path       ? id_std_funct7             :
                                       (id_c_sub | id_c_srai) ? id_c_funct7_sub           :
                                        id_c_mul              ? id_c_funct7_mul           :
                                                                id_c_funct7_default       ;

wire  [11:0] id_funct12              =  id_std_funct12;


// Final immediate mux (compressed vs standard). Note that we can use an OR as the values are 0 when not valid due to pre-decoding and gating.
wire  [31:0] id_operand_immediate    = (id_c_imm    | id_std_imm   );


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                ALU CONTROL                                                           //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
// Note: CLMUL instructions use funct3 to differentiate, so we encode them using standard instruction path:
//       funct3=001 (CLMUL), funct3=010 (CLMULR), funct3=011 (CLMULH)

// Forward declarations for signals assigned in later sections but used here.
wire         id_opcode_use_pc;
wire         id_csr_active;

// Detect when the ALU is active
wire         id_alu_active           = id_opcode_valid & id_instruction_request_o & (id_type_R | id_type_I | id_type_U | id_opcode_use_pc) & !id_opcode_load & !id_csr_active;

// Standard mode operations (also shared by MUL/DIV operations).
// Note for spec clarification: OP/OP-IMM ALU ops are selected by funct3 only.
//                              funct7 is used elsewhere solely to pick ADD/SUB, SRL/SRA, and to enable M/Zbb/Zba/Zbs/Zbc.
//                              A *reserved* funct7 (or reserved shift imm[11:5]) within the implemented extension set is NOT trapped here.
wire   [7:0] id_standard_ops         = (id_opcode_op | id_opcode_opimm) ? (8'h01 << id_funct3) : 8'b00000001;  // Default to ADD if not OP/OP-IMM

// Zbb operations
wire  [16:0] id_zbb_ops              = {(id_zbb_sext_b | id_c_sext_b), (id_zbb_sext_h | id_c_sext_h),
                                        (id_zbb_zext_h | id_c_zext_h),  id_zbb_orc_b,
                                         id_zbb_rev8,                   id_zbb_cpop,
                                         id_zbb_ctz,                    id_zbb_clz,
                                        (id_zbb_ror    | id_zbb_rori),  id_zbb_rol,
                                         id_zbb_maxu,                   id_zbb_max,
                                         id_zbb_minu,                   id_zbb_min,
                                         id_zbb_xnor,                   id_zbb_orn,
                                         id_zbb_andn};

// Zba + Zbs operations
wire  [16:0] id_zbs_zba_ops          = { 9'h000,
                                        (id_zbs_bext | id_zbs_bexti),  (id_zbs_binv | id_zbs_binvi),
                                        (id_zbs_bclr | id_zbs_bclri),  (id_zbs_bset | id_zbs_bseti),
                                         1'b0,                          id_zba_sh3add,
                                         id_zba_sh2add,                 id_zba_sh1add};

// Combined ALU control signals
wire  [16:0] id_alu_control          =  (id_any_zba | id_any_zbs)     ? id_zbs_zba_ops          :
                                         id_any_zbb                   ? id_zbb_ops              :
                                                                       {9'h000, id_standard_ops};

// Selects the ALU operating mode
wire   [4:0] id_alu_mode             =   id_any_zbc                   ? 5'b10000 :  // Zbc mode (carry-less multiply)
                                        (id_any_zba | id_any_zbs)     ? 5'b01000 :  // Zba+Zbs modes
                                         id_any_zbb                   ? 5'b00100 :  // Zbb mode (including SEXT)
                                        (id_funct7[0] & id_opcode_op) ? 5'b00010 :  // MUL/DIV mode
                                                                        5'b00001 ;  // Standard instructions mode

// Select alternate function is used for:
//            - activate the transformation of operand2 into its 2's complement
//            - selecting between SRL[I] and SRA[I]
//            - selecting between MUL and DIV/REM operations
wire         id_alu_select           = (id_alu_mode[2] & (id_zbb_min | id_zbb_minu | id_zbb_max | id_zbb_maxu)) |                  // ZBB min/max operations
                                       (id_alu_mode[1] & (id_funct3[2])) |                                                         // 0: multiplication; 1: divison/reminder
                                       (id_alu_mode[0] & (( id_opcode_op                    & id_funct7[5] & id_alu_control[0])  | // SUB     activated for Reg-Reg operations with funct7[5]
                                                          ((id_opcode_op | id_opcode_opimm)                & id_alu_control[2])  | // SLT[I]  activated for Reg-Reg and Imm-Reg operations
                                                          ((id_opcode_op | id_opcode_opimm)                & id_alu_control[3])  | // SLT[I]U activated for Reg-Reg and Imm-Reg operations
                                                          ((id_opcode_op | id_opcode_opimm) & id_funct7[5] & id_alu_control[5]))); // SRA[I]  activated for Reg-Reg and Imm-Reg operations with funct7[5]

// Set control registers for the ALU
// (note that we flush stale ALU op on trap entry which is necessary for muldiv trap kill)
// Priority: trap-flush > ~ready hold > active-load > clear. The flop holds only on the
// ~ready branch, so en = trap_branch_detect_i | ex_alu_ready_i (trap-flush must win even
// when ~ready is also asserted, hence trap is gathered into the enable and handled first
// in the next-state expression).
wire         ex_alu_ctrl_en        =  trap_branch_detect_i | ex_alu_ready_i;

wire   [4:0] ex_alu_mode_nxt       =  trap_branch_detect_i ? 5'h0 :
                                      id_alu_active        ? id_alu_mode : 5'h0;
arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_ex_alu_mode (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_alu_ctrl_en), .d_i(ex_alu_mode_nxt), .q_o(ex_alu_mode_o));

wire         ex_alu_select_nxt     =  trap_branch_detect_i ? 1'h0 :
                                      id_alu_active        ? id_alu_select : 1'h0;
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_ex_alu_select (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_alu_ctrl_en), .d_i(ex_alu_select_nxt), .q_o(ex_alu_select_o));

wire  [16:0] ex_alu_control_nxt    =  trap_branch_detect_i ? 17'h00000 :
                                      id_alu_active        ? id_alu_control : 17'h00000;
arv_dff #(.WIDTH(17), .ARST_EN(ARST_EN)) u_ex_alu_control (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_alu_ctrl_en), .d_i(ex_alu_control_nxt), .q_o(ex_alu_control_o));

wire         ex_alu_busy;
wire         ex_alu_busy_nxt       =  trap_branch_detect_i ? 1'b0 :
                                      id_alu_active        ? 1'b1 : 1'b0;
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_ex_alu_busy (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_alu_ctrl_en), .d_i(ex_alu_busy_nxt), .q_o(ex_alu_busy));

// Selection of the source and destination registers for the ALU
// (the results is stored in the shared operands for ALU and Load-Store units)
// Integer Registers are read during the Decoding phase
assign       id_reg_src1_sel_o        = id_reg_src1_sel;
assign       id_reg_src2_sel_o        = id_reg_src2_sel;

// Fast branch rs1/rs2 selects - 2-way mux using only instruction[1] as select.
// instruction[1]=1 -> standard 32-bit instruction: rs1=inst[19:15], rs2=inst[24:20].
// instruction[1]=0 -> compressed quadrant 1:       rs1={2'b01,inst[9:7]}, rs2=x0 (C.BEQZ/BNEZ compare against 0).
assign       id_branch_rs1_fast_sel_o = id_instruction_i[1] ?         id_instruction_i[19:15] :
                                                              {2'b01, id_instruction_i[ 9: 7]};

assign       id_branch_rs2_fast_sel_o = id_instruction_i[1] ?         id_instruction_i[24:20] :
                                                                5'd0                    ;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                            LOAD-STORE CONTROL                                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

wire         id_ldst_active          =  id_opcode_valid & id_instruction_request_o & (id_opcode_load | id_opcode_store);
wire         id_load_active          =  id_opcode_valid & id_instruction_request_o &  id_opcode_load;

// Priority: trap-flush > ~ready hold > active-load > clear. Holds only on ~ready,
// so en = (trap_branch_detect_i & trap_pending_i) | ex_ldst_ready_i.
wire         ex_ldst_ctrl_en       = (trap_branch_detect_i & trap_pending_i) | ex_ldst_ready_i;
wire   [4:0] ex_ldst_control_nxt   = (trap_branch_detect_i & trap_pending_i) ? 5'b00000 :         // Flush stale load/store op on trap entry (not MRET/SRET)
                                      id_ldst_active                         ? {id_funct3, id_opcode_load, id_opcode_store} : 5'b00000;

arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_ex_ldst_control (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_ldst_ctrl_en), .d_i(ex_ldst_control_nxt), .q_o(ex_ldst_control_o));

wire         ex_ldst_busy            = |ex_ldst_control_o[1:0];
wire         ex_load_busy            =  ex_ldst_control_o[1];


// Integer Registers are read during the Execution phase
assign       ex_reg_src1_sel_o       = {5{ex_ldst_busy}}  & ex_operand1_o[4:0];
assign       ex_reg_src2_sel_o       = {5{ex_ldst_busy}}  & ex_operand1_o[9:5];

// FENCE instruction detection (MISCMEM with funct3=000)
// If a fence is detected, we stall the instruction until the Load-Store unit is not busy
wire         id_opcode_fence         =  id_opcode_miscmem & (id_funct3 == 3'b000);

// FENCE.I instruction detection (MISCMEM with funct3=001)
// Stalls until all stores drain, then flush the instruction buffer (which may hold stale pre-fence instruction bytes).
wire         id_opcode_fence_i       =  id_opcode_miscmem & (id_funct3 == 3'b001);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                          CSR REGISTER CONTROL                                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

wire         id_opcode_csr           =  id_opcode_system & (id_funct3!=3'b000) & (id_funct3!=3'b100);
assign       id_csr_active           =  id_opcode_valid  & id_instruction_request_o & id_opcode_csr;

// Priority: trap-flush > ~ready hold > active-load > clear. Holds only on ~ready,
// so en = (trap_branch_detect_i & trap_pending_i) | ex_csr_ready_i.
wire         ex_csr_ctrl_en        = (trap_branch_detect_i & trap_pending_i) | ex_csr_ready_i;
wire   [3:0] ex_csr_control_nxt    = (trap_branch_detect_i & trap_pending_i) ? 4'b0000 :          // Flush stale CSR op on trap entry (not MRET/SRET)
                                      id_csr_active                          ? {(id_reg_src1_sel==5'h00),  // Detect if RS1==X0 for non-immediate or UIMM==0 for immediate
                                                                                (id_reg_dest_sel==5'h00),  // Detects if RD=X0
                                                                                 id_funct3[1:0]         }  // 01: CSRRW[I] | 10: CSRRS[I] | 11: CSRRC[I]
                                                                             : 4'b0000;
arv_dff #(.WIDTH(4), .ARST_EN(ARST_EN)) u_ex_csr_control (
                     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_csr_ctrl_en), .d_i(ex_csr_control_nxt), .q_o(ex_csr_control_o));

wire         ex_csr_busy             = |ex_csr_control_o[1:0];


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                           UOP SEQUENCER CONTROL                                                      //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Module-level declarations for signals driven inside the generate block below.
wire         ex_uop_busy;
wire         ex_uop_ret_branch;

// Combined activation signal for all Zcmp/Zcmt instructions
wire         id_uop_active           =  id_opcode_valid & id_instruction_request_o & id_c_opcode_uop;
assign       id_uop_start_o          =  id_uop_active;
assign       id_uop_jt_start_o       =  id_c_cm_jt | id_c_cm_jalt;

// Map instructions to µop types
wire   [3:0] id_uop_type             = ({4{id_c_cm_push}}   & 4'd0) |
                                       ({4{id_c_cm_pop}}    & 4'd1) |
                                       ({4{id_c_cm_popret}} & 4'd2) |
                                       ({4{id_c_cm_popretz}}& 4'd3) |
                                       ({4{id_c_cm_mva01s}} & 4'd4) |
                                       ({4{id_c_cm_mvsa01}} & 4'd5) |
                                       ({4{id_c_cm_jt}}     & 4'd6) |
                                       ({4{id_c_cm_jalt}}   & 4'd7) ;

wire         id_uop_has_branch       = (id_c_cm_popret | id_c_cm_popretz | id_c_cm_jt   | id_c_cm_jalt);
wire         id_uop_ret_branch       = (id_c_cm_popret | id_c_cm_popretz);
wire         id_uop_pushpop          = (id_c_cm_popret | id_c_cm_popretz | id_c_cm_push | id_c_cm_pop );
wire         id_uop_mv               = (id_c_cm_mva01s | id_c_cm_mvsa01  );

// Extract instruction fields
wire   [3:0] id_uop_rlist            =  id_instruction_i[7:4];                                    // Register list for push/pop
wire   [1:0] id_uop_spimm            =  id_instruction_i[3:2];                                    // Stack adjustment for push/pop
wire   [7:0] id_uop_index            =  id_instruction_i[9:2];                                    // Index for CM.JT/JALT

// Compute the SP adjustment fo push/pop
wire   [2:0] id_uop_base_blocks      = (id_uop_rlist == 4'hF) ? 3'h4 : {1'b0, id_uop_rlist[3:2]}; // Number of 16B blocks for the base adjustment
wire   [2:0] id_uop_total_block      =  id_uop_base_blocks + {1'b0, id_uop_spimm};                // Add the immadiate stack adjustment (also a numberof 16B blocks)
wire   [6:0] id_uop_sp_adj           = {id_uop_total_block, 4'h0};                                // Total adjustment in bytes

// Compute starting point for the push/pop sequence (the first block to push/pop)
wire   [2:0] id_uop_total_block_m1   =  id_uop_total_block + 3'h7;                                // Remove 1 block
wire   [7:0] id_uop_sp_pop_start     = {1'b0, id_uop_total_block_m1, 4'hC};                       // Remove 4

// For push, we start at -4 (the last block), for pop, we start at total-4 (the first block).
// For cm.jt/cm.jalt, pass the 8-bit index extracted from bits[9:2].
assign       id_uop_ldst_start_o     =  id_uop_jt_start_o  ? id_uop_index       :
                                        id_c_cm_push       ? 8'hFC              :
                                                             id_uop_sp_pop_start;

// Destination registers for CM.MVA01S / CM.MVSA01
wire   [4:0] id_uop_mv_dest1         =  id_c_cm_mva01s ? 5'd10 : id_c_rs1_sreg_exp;
wire   [4:0] id_uop_mv_dest2         =  id_c_cm_mva01s ? 5'd11 : id_c_rs2_sreg_exp;


wire   [4:0] id_uop_config           =  id_uop_pushpop ? {1'b0, id_uop_rlist} : id_uop_mv_dest1;


generate
    if (UOP_EN) begin : WITH_UOP_SEQUENCER
      wire [9:0] ex_uop_control_reg;
      wire       ex_uop_has_branch_reg;
      wire       ex_uop_ret_branch_reg;

      // On IRQ kill: clear immediately so the sequencer is disabled next cycle and won't
      // restart (UOP will re-execute cleanly from MEPC after MRET).
      // Priority: kill/abort-clear > ~ready hold > active-load > clear. Holds only on
      // ~ready, so en = (ex_uop_kill_i | ex_uop_excp_abort_i) | ex_uop_ready_i.
      wire       ex_uop_en           = (ex_uop_kill_i | ex_uop_excp_abort_i) | ex_uop_ready_i;

      // Register for µop control
      wire [9:0] ex_uop_control_nxt  = (ex_uop_kill_i | ex_uop_excp_abort_i) ? 10'h000 :
                                       id_uop_active                         ? {1'b1, id_uop_type, id_uop_config} : 10'h000;
      arv_dff #(.WIDTH(10), .ARST_EN(ARST_EN)) u_ex_uop_control (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_uop_en), .d_i(ex_uop_control_nxt), .q_o(ex_uop_control_reg));

      // Detect if the current uop instruction has a branch (used to cancel the current decode instruction and inject a branch)
      wire       ex_uop_has_branch_nxt = (ex_uop_kill_i | ex_uop_excp_abort_i) ? 1'b0 :
                                         id_uop_active                         ? id_uop_has_branch : 1'b0;
      arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_ex_uop_has_branch (
                              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_uop_en), .d_i(ex_uop_has_branch_nxt), .q_o(ex_uop_has_branch_reg));

      // Detect if the current uop instruction is a return branch (POPRET/POPRETZ only, not JT/JALT)
      // Used by the JALR shadow register to switch to x1/ra
      wire       ex_uop_ret_branch_nxt = (ex_uop_kill_i | ex_uop_excp_abort_i) ? 1'b0 :
                                         id_uop_active                         ? id_uop_ret_branch : 1'b0;
      arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_ex_uop_ret_branch (
                              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_uop_en), .d_i(ex_uop_ret_branch_nxt), .q_o(ex_uop_ret_branch_reg));

      assign     ex_uop_busy              = ex_uop_control_reg[9];
      assign     ex_uop_control_o         = ex_uop_control_reg;
      assign     ex_uop_has_branch        = ex_uop_has_branch_reg;
      assign     ex_uop_ret_branch        = ex_uop_ret_branch_reg;

      // Next-cycle is CM.PUSH
      assign     ex_c_cm_push_nxt_o       =  ex_uop_kill_i  ? 1'b0                            :
                                            ~ex_uop_ready_i ? (ex_uop_control_reg[8:5]==4'h0) :
                                             id_uop_active  ? id_c_cm_push                    : 1'b0;

    end else begin : NO_UOP_SEQUENCER

      assign     ex_uop_control_o         = 10'h000;
      assign     ex_c_cm_push_nxt_o       =  1'b0;
      assign     ex_uop_has_branch        =  1'b0;
      assign     ex_uop_ret_branch        =  1'b0;
      assign     ex_uop_busy              =  1'b0;

      wire [3:0] id_uop_type_unused       = id_uop_type;
      wire [4:0] id_uop_config_unused     = id_uop_config;
      wire       id_uop_has_branch_unused = id_uop_has_branch;
      wire       id_uop_ret_branch_unused = id_uop_ret_branch;
      wire       ex_uop_kill_unused       = ex_uop_kill_i;
      wire       ex_uop_excp_abort_unused = ex_uop_excp_abort_i;
    end
endgenerate

assign ex_uop_ret_branch_o = ex_uop_ret_branch;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                              OTHER SYSTEM INSTRUCTIONS: EBREAK/ECALL/MRET/SRET/WFI                                   //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Forward declaration
wire         id_instruction_request_sys;

// Decode instruction (handles both standard and compressed)
assign       id_opcode_ecall         =  id_std_opcode_system & (id_funct3==3'b000) & (id_funct12==12'b000000000000) & (id_reg_src1_sel==5'b00000) & (id_reg_dest_sel==5'b00000)  ;
assign       id_opcode_ebreak        = (id_std_opcode_system & (id_funct3==3'b000) & (id_funct12==12'b000000000001) & (id_reg_src1_sel==5'b00000) & (id_reg_dest_sel==5'b00000)) |
                                       (id_use_c_path        &  id_c_ebreak);
assign       id_opcode_mret          =  id_std_opcode_system & (id_funct3==3'b000) & (id_funct12==12'b001100000010) & (id_reg_src1_sel==5'b00000) & (id_reg_dest_sel==5'b00000);
assign       id_opcode_sret          =  id_std_opcode_system & (id_funct3==3'b000) & (id_funct12==12'b000100000010) & (id_reg_src1_sel==5'b00000) & (id_reg_dest_sel==5'b00000);
assign       id_opcode_mnret         =  id_std_opcode_system & (id_funct3==3'b000) & (id_funct12==12'b011100000010) & (id_reg_src1_sel==5'b00000) & (id_reg_dest_sel==5'b00000);
assign       id_opcode_wfi           =  id_std_opcode_system & (id_funct3==3'b000) & (id_funct12==12'b000100000101) & (id_reg_src1_sel==5'b00000) & (id_reg_dest_sel==5'b00000);


// MRET is only legal in M-mode.
// (SU_MODE_EN=0: priv_mode is M at all times, so MRET is always legal)
assign       id_opcode_mret_illegal  = id_opcode_mret   & SU_MODE_EN & (id_priv_mode_i!=2'b11);

// SRET is legal in M-mode and S-mode.
// It is illegal in U-mode and in S-mode when MSTATUS.TSR=1.
// When SU_MODE_EN=0 (M-only) SRET is always illegal: there's no S-mode for it to return from.
assign       id_opcode_sret_illegal  = id_opcode_sret   & ((~SU_MODE_EN                              ) | // always trap in M-only mode
                                                           ((id_priv_mode_i==2'b01) & cfg_trap_sret_i) | // trap in S-Mode if TSR is 1
                                                           (id_priv_mode_i==2'b00)                   ) ; // always trap in U-Mode

// MNRET is only legal when NMI_EN=1 and only in M-mode.
assign       id_opcode_mnret_illegal = id_opcode_mnret  & (~NMI_EN | (id_priv_mode_i!=2'b11));

// WFI is always legal in M mode. It is only legal in U and S modes if TW is 0.
// (SU_MODE_EN=0: priv_mode is M at all times, so WFI is always legal)
assign       id_opcode_wfi_illegal   = id_opcode_wfi    & SU_MODE_EN & cfg_timeout_wait_i & (id_priv_mode_i!=2'b11);

// Send commands to Trap handler
// Use id_instruction_request_sys (not id_instruction_request_o):
// SYSTEM funct3=000 opcodes don't read RS1/RS2, so opcode-gated stalls cannot fire for them.
assign       id_excp_ecall_o         = id_opcode_valid  & id_instruction_request_sys & id_opcode_ecall;
assign       id_excp_ebreak_o        = id_opcode_valid  & id_instruction_request_sys & id_opcode_ebreak;
assign       id_opcode_mret_o        = id_opcode_valid  & id_instruction_request_sys & id_opcode_mret  & ~id_opcode_mret_illegal;
assign       id_opcode_sret_o        = id_opcode_valid  & id_instruction_request_sys & id_opcode_sret  & ~id_opcode_sret_illegal;
assign       id_opcode_mnret_o       = id_opcode_valid  & id_instruction_request_sys & id_opcode_mnret & ~id_opcode_mnret_illegal & NMI_EN;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                              SHARED OPERANDS FOR ALU, LOAD-STORE UNITS AND CSR REGISTERS                             //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

assign       id_opcode_use_pc        = (id_opcode_auipc | id_opcode_jal | id_opcode_jalr);

// Operand1: outer chain holds only on ~id_instruction_request_o, with a final
// else => 0, so en = id_instruction_request_o. Inner branches all terminate.
wire         ex_operand1_en        =  id_instruction_request_o;
wire  [31:0] ex_operand1_nxt       = (id_alu_active | id_c_cm_jalt) ?
                                          ( id_opcode_lui                      ?  32'h00000000             :
                                           (id_opcode_use_pc | id_c_cm_jalt)   ?  id_pc_i                  :
                                                                                  id_reg_src1_rdata_w_fwd_i) :
                                       id_csr_active ?
                                          (!id_funct3[2]                       ?  id_reg_src1_rdata_w_fwd_i :
                                                                                 {22'h000000, 5'h00,           id_reg_src1_sel}) : // CSR immediate value
                                       id_ldst_active ? {22'h000000, id_reg_src2_sel, id_reg_src1_sel} : // SRC1/2 selects for load-store EX phase
                                       id_uop_active  ?  id_reg_src1_rdata_w_fwd_i :
                                                         32'h00000000;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_ex_operand1 (
                   .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_operand1_en), .d_i(ex_operand1_nxt), .q_o(ex_operand1_o));

// Operand2: same en = id_instruction_request_o, BUT the inner (id_alu_active|jalt)
// branch has no final else => implicit hold, so its default falls back to ex_operand2_o.
wire         ex_operand2_en        =  id_instruction_request_o;
wire  [31:0] ex_operand2_nxt       = (id_alu_active | id_c_cm_jalt) ?
                                          ( id_type_R                                ?  id_reg_src2_rdata_w_fwd_i :
                                           (id_opcode_jal | id_opcode_jalr | id_c_cm_jalt) ? (id_use_std_path ? 32'h00000004 : 32'h00000002) :
                                           (id_type_I | id_type_U)                   ?  id_operand_immediate :
                                                                                        ex_operand2_o) : // inner implicit hold (no final else)
                                       id_ldst_active ?  id_operand_immediate :
                                       id_csr_active  ?  id_operand_immediate :
                                       id_uop_active  ? (id_uop_pushpop ? {25'h0000000, id_uop_sp_adj} : id_reg_src2_rdata_w_fwd_i) :
                                                         32'h00000000;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_ex_operand2 (
                   .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_operand2_en), .d_i(ex_operand2_nxt), .q_o(ex_operand2_o));

// Selection of the destination register for the ALU and LOAD unit
// Holds only on ~id_instruction_request_o, final else => 0, so en = id_instruction_request_o.
wire         ex_reg_dest_sel_en    =  id_instruction_request_o;
wire   [4:0] ex_reg_dest_sel_nxt   = (id_alu_active | id_load_active | id_csr_active) ? id_reg_dest_sel :
                                       id_uop_active ? (id_c_cm_jalt ? 5'd1 : (id_uop_pushpop ? 5'd2 : id_uop_mv_dest2)) :
                                                       5'b00000;
arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_ex_reg_dest_sel (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_reg_dest_sel_en), .d_i(ex_reg_dest_sel_nxt), .q_o(ex_reg_dest_sel_o));

// PC pipeline: track instruction PC through EX stage for MEPC save on trap.
// Two hold conditions (explicit ~request and implicit request & ~opcode_valid),
// so en = id_instruction_request_o & id_opcode_valid, d = id_pc_i.
wire         ex_pc_en              =  id_instruction_request_o & id_opcode_valid;
arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_ex_pc (
             .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_pc_en), .d_i(id_pc_i), .q_o(ex_pc_o));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                BRANCH INSTRUCTIONS                                                   //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////   Timing optimizations applied in this section:                                                                      //////
//////                                                                                                                      //////
//////     A. id_request_fast (branch detect): omits all opcode-gated stalls from thebranch-detect expression.              //////
//////        Those stalls are mutually exclusive with JAL/JALR/BRANCH opcodes, so omitting them is functionally            //////
//////        correct and breaks the reconvergent fanout of id_use_std_path (inst_hrdata_i[0]) through the                  //////
//////        stall NOR - cutting one critical-path gate level from id_branch_detect_o.                                     //////
//////                                                                                                                      //////
//////     B. id_bt_c_b carry-select adder: CB-type immediate has id_c_imm_b[31:8] = {24{sign}}, so routing the sign bit    //////
//////        through a high-fanout buffer into a full 32-bit adder creates a long chain. Instead, three high-part          //////
//////        candidates are pre-computed from registered id_pc_i alone; only an 8-bit low sum sits on the critical path.   //////
//////        The final mux needs just the sign and the low carry.                                                          //////
//////                                                                                                                      //////
//////     C. id_branch_target_o flat AND-OR mux: avoids the N-stage cascaded MUX2 of a priority chain.                     //////
//////        Each (select, adder) pair meets at a single AND gate; all 8 are OR'd in a 2-level tree - 3 gate levels        //////
//////        total vs ~8-stage cascade.                                                                                    //////
//////        bt_s_stdbr is simply  id_std_opcode_branch & ~id_bt_hi  (a 2-input AND, one inverted input): a                //////
//////        standard branch opcode is mutually exclusive with jalr/jal/c-branch by opcode, so it only needs to            //////
//////        defer to the id_bt_hi (trap / UOP-JT) high-priority override - no accumulated exclusion chain, so             //////
//////        its depth is bounded by a single gate, not an accumulated 7-condition chain.                                  //////
//////                                                                                                                      //////
//////======================================================================================================================//////

// Forward declarations
wire         fetch_stall_from_ex;
wire         fetch_stall_from_trap;
wire         fetch_stall_from_jt_branch;
wire         fetch_stall_from_wfi;
wire         id_jalr_stall_rs1_wo_fwd;
wire         id_jalr_shadow_valid_fast;
wire         id_br_stall_w_fwd;
wire         id_branch_taken;

//-----------------------------------------------------------------------------
// 1. Branch detection & cancel
//-----------------------------------------------------------------------------

// id_request_fast: timing optimisation A - see section header above.
wire         id_request_fast         = ~(fetch_stall_from_ex   |
                                         fetch_stall_from_trap |
                                         fetch_stall_from_wfi  );

// Fast branches only: trap, ZCMT-JT and FENCE.I are on the slow path (id_slow_branch_o)
assign       id_branch_detect_o      =  (id_instruction_request_o & ex_uop_has_branch & ~ex_uop_kill_i)                                                         |  // UOP final branch (POPRET/POPRETZ): registered, safe
                                        (id_request_fast & id_instruction_valid_i & ( id_opcode_jal                                                             |  // JAL: no hazard stall possible
                                                                                     (id_opcode_jalr   & ~id_jalr_stall_rs1_wo_fwd & id_jalr_shadow_valid_fast) |  // JALR: stall if rs1 hazard or shadow miss
                                                                                     (id_opcode_branch & ~id_br_stall_w_fwd)));                                    // BRANCH: stall if rs1/rs2 hazard

// Branch cancel: registered signal, asserted 1 cycle after id_branch_detect_o
// when the conditional branch was speculatively taken but the condition is NOT met.
// Never cancel a trap redirect.
wire         id_branch_taken_reg;
wire         id_branch_dispatch_reg;

// INVARIANT: id_branch_taken_reg is captured UNCONDITIONALLY (no enable) -- it
// just tracks last-cycle id_branch_taken, so it holds a meaningful value only
// for one cycle after an actual speculative branch. That is safe ONLY because
// id_branch_cancel_o below qualifies it with id_branch_dispatch_reg, which IS
// gated (request & opcode_valid & opcode_branch & ~trap_branch_detect). A stray
// id_branch_taken_reg value in a non-branch / trap cycle therefore cannot raise
// a spurious cancel. Preserve the dispatch qualifier if you add an enable here.
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_id_branch_taken (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(id_branch_taken), .q_o(id_branch_taken_reg));

wire         id_branch_dispatch_nxt = (id_instruction_request_o & id_opcode_valid & id_opcode_branch & ~trap_branch_detect_i);
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_id_branch_dispatch (
                         .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(id_branch_dispatch_nxt), .q_o(id_branch_dispatch_reg));

assign       id_branch_cancel_o      =  (id_branch_dispatch_reg & ~id_branch_taken_reg);


//-----------------------------------------------------------------------------
// 2. Branch target adders
//
//   _std_jal  : standard JAL,            base = PC,          imm = id_std_imm_j (J-type,  21-bit)
//   _std_br   : standard BRANCH,         base = PC,          imm = id_std_imm_b (B-type,  13-bit)
//   _std_jalr : standard JALR,           base = jalr_shadow, imm = id_std_imm_i (I-type,  12-bit)
//   _c_j      : C.J / C.JAL,             base = PC,          imm = id_c_imm_j   (CJ-type, 12-bit)
//   _c_b      : C.BEQZ / C.BNEZ,         base = PC,          imm = id_c_imm_b   (CB-type,  9-bit) - carry-select (opt B)
//   _jalr_0   : C.JALR / C.JR / UOP-RET, base = jalr_shadow, imm = 0
//
// Adders are inlined directly (no sub-module boundary): the RTL reconvergence
// between carry chains and mux-select signals that previously required a separate
// sub-module has been resolved at the RTL level.
//-----------------------------------------------------------------------------

wire  [31:0] id_bt_std_jalr          = (id_jalr_shadow_rdata_i + id_std_imm_i) & 32'hFFFFFFFE;

// id_bt_std_jal: carry-select adder - timing optimisation, see section header above.
// id_std_imm_j[31:20] = {12{id_std_instruction[31]}}: all high bits are the same sign.
// Pre-compute three high-part candidates from registered id_pc_i (arrives early):
//   sign=0, lo_carry=0  ->  hi = PC[31:20]
//   sign=0, lo_carry=1  ->  hi = PC[31:20] + 1
//   sign=1, lo_carry=0  ->  hi = PC[31:20] − 1  (adding 12'hFFF)
//   sign=1, lo_carry=1  ->  hi = PC[31:20]      (12'hFFF + carry wraps to 0)
// The low 20-bit sum and its carry are the only things on the critical path.
wire  [20:0] id_bt_std_jal_lo21      = {1'b0, id_pc_i[19:0]} + {1'b0, id_std_imm_j[19:0]};
wire         id_bt_std_jal_lo_c      =   id_bt_std_jal_lo21[20];
wire  [11:0] id_bt_std_jal_hi_A      =   id_pc_i[31:20];
wire  [11:0] id_bt_std_jal_hi_B      =   id_pc_i[31:20] + 12'h001;
wire  [11:0] id_bt_std_jal_hi_C      =   id_pc_i[31:20] + 12'hFFF;
wire  [11:0] id_bt_std_jal_hi        = (~id_std_imm_j[20] & ~id_bt_std_jal_lo_c) ? id_bt_std_jal_hi_A :
                                       (~id_std_imm_j[20] &  id_bt_std_jal_lo_c) ? id_bt_std_jal_hi_B :
                                       ( id_std_imm_j[20] & ~id_bt_std_jal_lo_c) ? id_bt_std_jal_hi_C :
                                                                                   id_bt_std_jal_hi_A ;
wire  [31:0] id_bt_std_jal           = {id_bt_std_jal_hi, id_bt_std_jal_lo21[19:0]};

// id_bt_c_j: carry-select adder - timing optimisation, see section header above.
// id_c_imm_j[31:11] = {21{id_c_instruction[12]}}: all high bits are the same sign.
// Pre-compute three high-part candidates from registered id_pc_i (arrives early):
//   sign=0, lo_carry=0  ->  hi = PC[31:11]
//   sign=0, lo_carry=1  ->  hi = PC[31:11] + 1
//   sign=1, lo_carry=0  ->  hi = PC[31:11] − 1  (adding 21'h1FFFFF)
//   sign=1, lo_carry=1  ->  hi = PC[31:11]      (21'h1FFFFF + carry wraps to 0)
// The low 11-bit sum and its carry are the only things on the critical path.
wire  [11:0] id_bt_c_j_lo12          = {1'b0, id_pc_i[10:0]} + {1'b0, id_c_imm_j[10:0]};
wire         id_bt_c_j_lo_c          =   id_bt_c_j_lo12[11];
wire  [20:0] id_bt_c_j_hi_A          =   id_pc_i[31:11];
wire  [20:0] id_bt_c_j_hi_B          =   id_pc_i[31:11] + 21'h000001;
wire  [20:0] id_bt_c_j_hi_C          =   id_pc_i[31:11] + 21'h1FFFFF;
wire  [20:0] id_bt_c_j_hi            = (~id_c_imm_j[11] & ~id_bt_c_j_lo_c) ? id_bt_c_j_hi_A :
                                       (~id_c_imm_j[11] &  id_bt_c_j_lo_c) ? id_bt_c_j_hi_B :
                                       ( id_c_imm_j[11] & ~id_bt_c_j_lo_c) ? id_bt_c_j_hi_C :
                                                                             id_bt_c_j_hi_A ;
wire  [31:0] id_bt_c_j               = {id_bt_c_j_hi, id_bt_c_j_lo12[10:0]};

// id_bt_std_br: carry-select adder - timing optimisation D, see section header above.
// id_std_imm_b[31:12] = {20{id_std_instruction[31]}}: all high bits are the same sign.
// Pre-compute three high-part candidates from registered id_pc_i (arrives early):
//   sign=0, lo_carry=0  ->  hi = PC[31:12]
//   sign=0, lo_carry=1  ->  hi = PC[31:12] + 1
//   sign=1, lo_carry=0  ->  hi = PC[31:12] − 1  (adding 20'hFFFFF)
//   sign=1, lo_carry=1  ->  hi = PC[31:12]      (20'hFFFFF + carry wraps to 0)
// The low 12-bit sum and its carry are the only things on the critical path.
wire  [12:0] id_bt_std_br_lo13       = {1'b0, id_pc_i[11:0]} + {1'b0, id_std_imm_b[11:0]};
wire         id_bt_std_br_lo_c       =   id_bt_std_br_lo13[12];
wire  [19:0] id_bt_std_br_hi_A       =   id_pc_i[31:12];
wire  [19:0] id_bt_std_br_hi_B       =   id_pc_i[31:12] + 20'h00001;
wire  [19:0] id_bt_std_br_hi_C       =   id_pc_i[31:12] + 20'hFFFFF;
wire  [19:0] id_bt_std_br_hi         = (~id_std_imm_b[12] & ~id_bt_std_br_lo_c) ? id_bt_std_br_hi_A :
                                       (~id_std_imm_b[12] &  id_bt_std_br_lo_c) ? id_bt_std_br_hi_B :
                                       ( id_std_imm_b[12] & ~id_bt_std_br_lo_c) ? id_bt_std_br_hi_C :
                                                                                  id_bt_std_br_hi_A ;
wire  [31:0] id_bt_std_br            = {id_bt_std_br_hi, id_bt_std_br_lo13[11:0]};

// id_bt_c_b: carry-select adder - timing optimisation B, see section header above.
// id_c_imm_b[31:8] = {24{id_c_instruction[12]}}: all high bits are the same sign.
// Pre-compute three high-part candidates from registered id_pc_i (arrives early):
//   sign=0, lo_carry=0  ->  hi = PC[31:8]
//   sign=0, lo_carry=1  ->  hi = PC[31:8] + 1
//   sign=1, lo_carry=0  ->  hi = PC[31:8] − 1  (adding 24'hFFFFFF)
//   sign=1, lo_carry=1  ->  hi = PC[31:8]       (24'hFFFFFF + carry wraps to 0)
// The low 8-bit sum and its carry are the only things on the critical path.
wire   [8:0] id_bt_c_b_lo9           = {1'b0, id_pc_i[7:0]} + {1'b0, id_c_imm_b[7:0]};
wire         id_bt_c_b_lo_c          =   id_bt_c_b_lo9[8];
wire  [23:0] id_bt_c_b_hi_A          =   id_pc_i[31:8];
wire  [23:0] id_bt_c_b_hi_B          =   id_pc_i[31:8] + 24'h000001;
wire  [23:0] id_bt_c_b_hi_C          =   id_pc_i[31:8] + 24'hFFFFFF;
wire  [23:0] id_bt_c_b_hi            = (~id_c_imm_b[8] & ~id_bt_c_b_lo_c) ? id_bt_c_b_hi_A :
                                       (~id_c_imm_b[8] &  id_bt_c_b_lo_c) ? id_bt_c_b_hi_B :
                                       ( id_c_imm_b[8] & ~id_bt_c_b_lo_c) ? id_bt_c_b_hi_C :
                                                                            id_bt_c_b_hi_A ;
wire  [31:0] id_bt_c_b               = { id_bt_c_b_hi, id_bt_c_b_lo9[7:0]};

wire  [31:0] id_bt_jalr_0            =   id_jalr_shadow_rdata_i & 32'hFFFFFFFE;

//-----------------------------------------------------------------------------
// 3. Branch target output mux
//
// Priority (highest first): jalr_0 -> std-JALR -> C.JAL -> std-JAL -> C.BRANCH -> std-BRANCH
//-----------------------------------------------------------------------------

wire         id_bt_hi                = trap_branch_detect_i | (ex_uop_jt_branch_active_i & ZCMT_EN);
wire         id_bt_j0                = ex_uop_ret_branch    | id_c_opcode_jalr;
wire         id_bt_jalr_any          = id_bt_j0             | id_std_opcode_jalr;
wire         id_bt_jal_any           = id_c_opcode_jal      | id_std_opcode_jal;

wire         bt_s_trap               = trap_branch_detect_i;
wire         bt_s_uopjt              = (ex_uop_jt_branch_active_i & ZCMT_EN) & ~trap_branch_detect_i;
wire         bt_s_jalr0              = id_bt_j0             & ~id_bt_hi;
wire         bt_s_stdjr              = id_std_opcode_jalr   & ~id_bt_hi & ~id_bt_j0;
wire         bt_s_cjal               = id_c_opcode_jal      & ~id_bt_hi & ~id_bt_jalr_any;
wire         bt_s_stdjal             = id_std_opcode_jal    & ~id_bt_hi & ~id_bt_jalr_any & ~id_c_opcode_jal;
wire         bt_s_cbr                = id_c_opcode_branch   & ~id_bt_hi & ~id_bt_jalr_any & ~id_bt_jal_any;
wire         bt_s_stdbr              = id_std_opcode_branch & ~id_bt_hi;

// Fast 6-term OR tree: performance-critical branches only (jalr, jal, taken branches).
// All sources on this tree come from inst_hrdata_i via the decode data path.
assign       id_branch_target_o      = ({32{bt_s_jalr0  }} & id_bt_jalr_0  ) |
                                       ({32{bt_s_stdjr  }} & id_bt_std_jalr ) |
                                       ({32{bt_s_cjal   }} & id_bt_c_j      ) |
                                       ({32{bt_s_stdjal }} & id_bt_std_jal  ) |
                                       ({32{bt_s_cbr    }} & id_bt_c_b      ) |
                                       ({32{bt_s_stdbr  }} & id_bt_std_br   ) ;

// Slow branch path: trap, UOP-JT, FENCE.I.
// Fetch uses id_slow_branch_target_o to update if_pc one cycle after the detect,
// discarding the stale AHB address via the existing ignore_incoming / ~branch_target_fetched mechanism.
wire         id_slow_fence_i         = id_instruction_request_o & id_instruction_valid_i & id_opcode_fence_i & ~id_bt_hi;

// id_slow_branch_o serves two roles for arv_fetch.v: (1) redirect the fetch
// PC to id_slow_branch_target_o, and (2) freeze the AHB in the detect cycle
// (via fetch_freeze_ahb), so no spurious sequential prefetch is committed
// against the stale if_pc before the next-cycle redirect lands. Every slow-
// branch source (trap, UOP table-jump, FENCE.I) wants both behaviours; if a
// future "soft" redirect ever needs (1) without (2), split this into two signals.
assign       id_slow_branch_o        = bt_s_trap | bt_s_uopjt | id_slow_fence_i;

assign       id_slow_branch_target_o = ({32{bt_s_trap      }} & trap_branch_target_i      ) |
                                       ({32{bt_s_uopjt     }} & ex_uop_jt_branch_target_i ) |
                                       ({32{id_slow_fence_i}} & (id_pc_i + 32'd4)         ) ;


//-----------------------------------------------------------------------------
// 4. Link-register next-word addresses (id_branch_target_nxt_o)
//    Used to save PC+4 (or target+4) into the link register for JAL/JALR.
//    This path is not timing-critical (not on the inst_haddr feedback loop).
//-----------------------------------------------------------------------------

wire  [31:0] id_branch_nxt_std_jal   = id_pc_i                + id_std_imm_j + 32'd4;
wire  [31:0] id_branch_nxt_std_br    = id_pc_i                + id_std_imm_b + 32'd4;
wire  [31:0] id_branch_nxt_std_jalr  = id_jalr_shadow_rdata_i + id_std_imm_i + 32'd4;
wire  [31:0] id_branch_nxt_c_j       = id_pc_i                + id_c_imm_j   + 32'd4;
wire  [31:0] id_branch_nxt_c_b       = id_pc_i                + id_c_imm_b   + 32'd4;
wire  [31:0] id_branch_nxt_jalr_0    = id_jalr_shadow_rdata_i                + 32'd4;  // imm=0: C.JALR, C.JR, UOP-RET

// Split on C_EXT_EN in two generate branch to remove warning in synthesis.
generate
    if (C_EXT_EN == 1'b1) begin : g_id_branch_target_c
        // C-extension present: full cascade (Zcmt jt, Zcmp ret, c.jalr, c.jal, c.branch).
        wire   ex_uop_jt_branch_active_msk      =  ex_uop_jt_branch_active_i & ZCMT_EN;
        assign id_branch_target_nxt_o           =  trap_branch_detect_i        ? (trap_branch_target_i      + 32'd4) :
                                                   ex_uop_jt_branch_active_msk ? (ex_uop_jt_branch_target_i + 32'd4) :
                                                   ex_uop_ret_branch           ?  id_branch_nxt_jalr_0               :  // POPRET/POPRETZ: imm=0
                                                   id_c_opcode_jalr            ?  id_branch_nxt_jalr_0               :  // C.JALR/C.JR:    imm=0
                                                   id_std_opcode_jalr          ?  id_branch_nxt_std_jalr             :
                                                   id_c_opcode_jal             ?  id_branch_nxt_c_j                  :
                                                   id_std_opcode_jal           ?  id_branch_nxt_std_jal              :
                                                   id_c_opcode_branch          ?  id_branch_nxt_c_b                  :
                                                   id_opcode_fence_i           ? (id_pc_i + 32'd8)                   :  // FENCE.I: target+4 = PC+8
                                                                                  id_branch_nxt_std_br               ;
    end else begin : g_id_branch_target_no_c
        // C_EXTENSION=0: no compressed opcodes, no Zcmp/Zcmt
        assign id_branch_target_nxt_o           =  trap_branch_detect_i        ? (trap_branch_target_i      + 32'd4) :
                                                   id_std_opcode_jalr          ?  id_branch_nxt_std_jalr             :
                                                   id_std_opcode_jal           ?  id_branch_nxt_std_jal              :
                                                   id_opcode_fence_i           ? (id_pc_i + 32'd8)                   :  // FENCE.I: target+4 = PC+8
                                                                                  id_branch_nxt_std_br               ;
        wire [31:0] id_branch_nxt_c_j_unused    = id_branch_nxt_c_j;
        wire [31:0] id_branch_nxt_c_b_unused    = id_branch_nxt_c_b;
        wire [31:0] id_branch_nxt_jalr_0_unused = id_branch_nxt_jalr_0;
    end
endgenerate

// UOP branch outputs to CSR Trap handler
assign       ex_uop_has_branch_o     =  ex_uop_has_branch;
assign       ex_uop_take_branch_o    = (id_instruction_request_o & ex_uop_has_branch & ~ex_uop_kill_i);


//-----------------------------------------------------------------------------
// 5. Conditional branch taken/not-taken evaluation
//    The three primitive comparisons (equal, signed less-than, unsigned less-than)
//    are computed in parallel to optimize timing.
//-----------------------------------------------------------------------------

wire         id_branch_eq            = (id_branch_rs1_rdata_w_fwd_i    == id_branch_rs2_rdata_w_fwd_i);
wire         id_branch_ltu           = (id_branch_rs1_rdata_w_fwd_i     < id_branch_rs2_rdata_w_fwd_i);
wire         id_branch_lt            = (id_branch_rs1_rdata_w_fwd_i[31] ^ id_branch_rs2_rdata_w_fwd_i[31]) ? id_branch_rs1_rdata_w_fwd_i[31] : id_branch_ltu;

wire         id_branch_cmp_sel       = (id_funct3_br[2:1] == 2'b10) ? id_branch_lt  :
                                       (id_funct3_br[2:1] == 2'b11) ? id_branch_ltu :
                                                                      id_branch_eq  ;

wire         id_branch_funct3_ok     = (id_funct3_br[2] | ~id_funct3_br[1]);

assign       id_branch_taken         =  id_branch_funct3_ok & (id_branch_cmp_sel ^ id_funct3_br[0]);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                         HAZARD DETECTION & STALL CONTROL                                             //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//-----------------------------------------------------------------------------
// JALR stall path  (timing: pre-computed comparisons, no inst_bits in != 0 guard)
//
// Use (bits == dest) & (dest != 0) rather than (bits != 0) & (bits == dest):
// the != 0 guard uses the registered dest signal, not instruction bits, which
// eliminates the internal reconvergence from inst_hrdata through the stall NOR.
// Shadow-valid comparison is also pre-computed for both std and compressed paths
// and muxed at the last stage to keep inst_hrdata off the stall critical path.
//-----------------------------------------------------------------------------

wire         id_jalr_std_rs1_match_ex       = (id_instruction_i[19:15] == ex_reg_dest_sel_o) & (ex_reg_dest_sel_o != 5'h0);
wire         id_jalr_c_rs1_match_ex         = (id_instruction_i[11:7]  == ex_reg_dest_sel_o) & (ex_reg_dest_sel_o != 5'h0);
wire         id_jalr_std_rs1_match_wb       = (id_instruction_i[19:15] == wb_reg_dest_sel_i) & (wb_reg_dest_sel_i != 5'h0);
wire         id_jalr_c_rs1_match_wb         = (id_instruction_i[11:7]  == wb_reg_dest_sel_i) & (wb_reg_dest_sel_i != 5'h0);

wire         id_jalr_hazard_rs1_ex          = id_use_std_path ? id_jalr_std_rs1_match_ex : id_jalr_c_rs1_match_ex;
wire         id_jalr_hazard_rs1_wb          = id_use_std_path ? id_jalr_std_rs1_match_wb : id_jalr_c_rs1_match_wb;

wire         id_jalr_load_stall_rs1_wo_fwd  = (id_jalr_hazard_rs1_ex & ex_load_busy) | (id_jalr_hazard_rs1_wb & wb_load_busy_i);
wire         id_jalr_other_stall_rs1_wo_fwd =  id_jalr_hazard_rs1_ex & (ex_alu_busy | ex_csr_busy | ex_uop_busy);
assign       id_jalr_stall_rs1_wo_fwd       =  id_jalr_load_stall_rs1_wo_fwd | id_jalr_other_stall_rs1_wo_fwd;

// Pre-computed JALR shadow-valid comparison, independent of id_use_std_path mux.
wire         id_jalr_std_shadow_valid       = (id_instruction_i[19:15] == id_jalr_shadow_sel_i);
wire         id_jalr_c_shadow_valid         = (id_instruction_i[11:7]  == id_jalr_shadow_sel_i);
assign       id_jalr_shadow_valid_fast      = id_use_std_path ? id_jalr_std_shadow_valid : id_jalr_c_shadow_valid;

//-----------------------------------------------------------------------------
// BRANCH stall path  (timing: pre-computed comparisons, same technique as JALR)
//
// Compressed branches (C.BEQZ/C.BNEZ) use only rs1 (prime register, bits[9:7]).
// Standard branches use both rs1 (bits[19:15]) and rs2 (bits[24:20]).
// Both are pre-computed against the registered EX/WB destination.
//-----------------------------------------------------------------------------
wire         id_other_stall_w_fwd;

wire   [4:0] id_br_c_rs1_p_exp       = {2'b01, id_instruction_i[9:7]};   // prime-register, same as id_c_rs1_p_exp
wire         id_br_std_rs1_match_ex  = (id_instruction_i[19:15] == ex_reg_dest_sel_o) & (ex_reg_dest_sel_o != 5'h0);
wire         id_br_std_rs2_match_ex  = (id_instruction_i[24:20] == ex_reg_dest_sel_o) & (ex_reg_dest_sel_o != 5'h0);
wire         id_br_c_rs1_match_ex    = (     id_br_c_rs1_p_exp  == ex_reg_dest_sel_o);  // prime regs are never x0
wire         id_br_std_rs1_match_wb  = (id_instruction_i[19:15] == wb_reg_dest_sel_i) & (wb_reg_dest_sel_i != 5'h0);
wire         id_br_std_rs2_match_wb  = (id_instruction_i[24:20] == wb_reg_dest_sel_i) & (wb_reg_dest_sel_i != 5'h0);
wire         id_br_c_rs1_match_wb    = (     id_br_c_rs1_p_exp  == wb_reg_dest_sel_i);

wire         id_br_hazard_ex         = id_use_std_path ? (id_br_std_rs1_match_ex | id_br_std_rs2_match_ex) : id_br_c_rs1_match_ex;
wire         id_br_hazard_wb         = id_use_std_path ? (id_br_std_rs1_match_wb | id_br_std_rs2_match_wb) : id_br_c_rs1_match_wb;

wire         id_br_load_stall_w_fwd  = (id_br_hazard_ex & ex_load_busy) | (id_br_hazard_wb & wb_load_busy_i & ~wb_ldst_ready_i);
assign       id_br_stall_w_fwd       =  id_br_load_stall_w_fwd | id_other_stall_w_fwd;

//-----------------------------------------------------------------------------
// General rs1/rs2 hazard detection - EX and WB stages
// (timing: SOP form, per-class pre-computed comparisons)
//
// Pre-computing one comparison per register-source class against the registered
// EX/WB destination avoids routing the id_reg_src1_sel mux output (which depends
// on id_use_std_path = inst_hrdata[0]) through a 5-bit XOR on the critical path.
//
// The final hazard assignment is in SOP (sum-of-products) form:
//   id_use_std_path and all id_c_class_* signals are mutually exclusive
//   (std path: bits[1:0]==11; compressed classes: bits[1:0]!=11).
//   SOP is shallower than a priority chain: all ANDs fire in parallel (1 level)
//   then a single OR tree (1–2 levels), vs N cascaded mux stages.
//
// id_c_haz_rs1_rdrs1 is a hazard-specific variant of id_c_class_rs1_rdrs1:
//   it omits the (rd_rs1 != 0) check (bits[11:7]) and excludes C.MV (which does
//   not read rs1).  Safe because id_pc_rs1_rdrs1_haz_ex already returns 0 when
//   bits[11:7]=0 (ex_dest!=0 guard prevents a match against x0).
//-----------------------------------------------------------------------------

wire         id_pc_rs1_std_haz_ex    = (        id_instruction_i[19:15] == ex_reg_dest_sel_o) & (ex_reg_dest_sel_o != 5'h0);
wire         id_pc_rs1_prime_haz_ex  = ({2'b01, id_instruction_i[9:7]}  == ex_reg_dest_sel_o); // prime regs always non-zero
wire         id_pc_rs1_sp_haz_ex     = (                         5'd2   == ex_reg_dest_sel_o); // C.LWSP/SWSP/ADDI16SP: rs1=x2
wire         id_pc_rs1_rdrs1_haz_ex  = (        id_instruction_i[11:7]  == ex_reg_dest_sel_o) & (ex_reg_dest_sel_o != 5'h0);
wire         id_pc_rs1_mvs_haz_ex    = (             id_c_rs1_sreg_exp  == ex_reg_dest_sel_o); // CM.MVA01S: rs1=s*
wire         id_pc_rs1_a0_haz_ex     = (                        5'd10   == ex_reg_dest_sel_o); // CM.MVSA01: rs1=a0

wire         id_c_haz_rs1_rdrs1      = ZCA_EN & ((id_c_q2 & (id_c_funct3 == 3'b100) & (id_c_instruction[12] | (id_c_rs2 == 5'd0))) | // C.JR/C.JALR/C.EBREAK/C.ADD (not C.MV)
                                                 (id_c_q1 & (id_c_funct3 == 3'b000)                                              ) | // C.ADDI / C.NOP
                                                 (id_c_q2 & (id_c_funct3 == 3'b000) & ~id_c_instruction[12]                      )); // C.SLLI (incl. HINT)

wire         id_hazard_rs1_in_ex     = (id_use_std_path      & id_pc_rs1_std_haz_ex  ) |
                                       (id_c_class_rs1_prime & id_pc_rs1_prime_haz_ex) |
                                       (id_c_class_rs1_sp    & id_pc_rs1_sp_haz_ex   ) |
                                       (id_c_haz_rs1_rdrs1   & id_pc_rs1_rdrs1_haz_ex) |
                                       (id_c_cm_mva01s       & id_pc_rs1_mvs_haz_ex  ) |
                                       (id_c_cm_mvsa01       & id_pc_rs1_a0_haz_ex   ) ;

// Precomputed per-class rs2 comparisons against EX destination (raw bits, all in parallel)
wire         id_pc_rs2_std_haz_ex    = (        id_instruction_i[24:20] == ex_reg_dest_sel_o) & (ex_reg_dest_sel_o != 5'h0);
wire         id_pc_rs2_prime_haz_ex  = ({2'b01, id_instruction_i[4:2]}  == ex_reg_dest_sel_o); // prime regs always non-zero
wire         id_pc_rs2_rs2_haz_ex    = (        id_instruction_i[6:2]   == ex_reg_dest_sel_o) & (ex_reg_dest_sel_o != 5'h0); // C.SWSP/ADD/MV
wire         id_pc_rs2_mvs_haz_ex    = (              id_c_rs2_sreg_exp == ex_reg_dest_sel_o); // CM.MVA01S: rs2=s*
wire         id_pc_rs2_a1_haz_ex     = (                         5'd11  == ex_reg_dest_sel_o); // CM.MVSA01: rs2=a1

wire         id_hazard_rs2_in_ex     = (id_use_std_path      & id_pc_rs2_std_haz_ex  ) |
                                       (id_c_class_rs2_prime & id_pc_rs2_prime_haz_ex) |
                                       (id_c_class_rs2_rs2   & id_pc_rs2_rs2_haz_ex  ) |
                                       (id_c_cm_mva01s       & id_pc_rs2_mvs_haz_ex  ) |
                                       (id_c_cm_mvsa01       & id_pc_rs2_a1_haz_ex   ) ;

wire         id_hazard_in_ex         = (id_hazard_rs1_in_ex  | id_hazard_rs2_in_ex   ) ;

// Precomputed per-class rs1 comparisons against WB destination (raw bits, all in parallel)
wire         id_pc_rs1_std_haz_wb    = (        id_instruction_i[19:15] == wb_reg_dest_sel_i) & (wb_reg_dest_sel_i != 5'h0);
wire         id_pc_rs1_prime_haz_wb  = ({2'b01, id_instruction_i[9:7]}  == wb_reg_dest_sel_i);
wire         id_pc_rs1_sp_haz_wb     = (                          5'd2  == wb_reg_dest_sel_i);
wire         id_pc_rs1_rdrs1_haz_wb  = (         id_instruction_i[11:7] == wb_reg_dest_sel_i) & (wb_reg_dest_sel_i != 5'h0);
wire         id_pc_rs1_mvs_haz_wb    = (              id_c_rs1_sreg_exp == wb_reg_dest_sel_i);
wire         id_pc_rs1_a0_haz_wb     = (                         5'd10  == wb_reg_dest_sel_i);

// Detect hazard if the on-going destination register during WB phase is the same as one of the register source
wire         id_hazard_rs1_in_wb     = (id_use_std_path      & id_pc_rs1_std_haz_wb  ) |
                                       (id_c_class_rs1_prime & id_pc_rs1_prime_haz_wb) |
                                       (id_c_class_rs1_sp    & id_pc_rs1_sp_haz_wb   ) |
                                       (id_c_haz_rs1_rdrs1   & id_pc_rs1_rdrs1_haz_wb) |
                                       (id_c_cm_mva01s       & id_pc_rs1_mvs_haz_wb  ) |
                                       (id_c_cm_mvsa01       & id_pc_rs1_a0_haz_wb   ) ;

// Precomputed per-class rs2 comparisons against WB destination (raw bits, all in parallel)
wire         id_pc_rs2_std_haz_wb    = (        id_instruction_i[24:20] == wb_reg_dest_sel_i) & (wb_reg_dest_sel_i != 5'h0);
wire         id_pc_rs2_prime_haz_wb  = ({2'b01, id_instruction_i[4:2]}  == wb_reg_dest_sel_i);
wire         id_pc_rs2_rs2_haz_wb    = (        id_instruction_i[6:2]   == wb_reg_dest_sel_i) & (wb_reg_dest_sel_i != 5'h0);
wire         id_pc_rs2_mvs_haz_wb    = (              id_c_rs2_sreg_exp == wb_reg_dest_sel_i);
wire         id_pc_rs2_a1_haz_wb     = (                         5'd11  == wb_reg_dest_sel_i);

wire         id_hazard_rs2_in_wb     = (id_use_std_path      & id_pc_rs2_std_haz_wb  ) |
                                       (id_c_class_rs2_prime & id_pc_rs2_prime_haz_wb) |
                                       (id_c_class_rs2_rs2   & id_pc_rs2_rs2_haz_wb  ) |
                                       (id_c_cm_mva01s       & id_pc_rs2_mvs_haz_wb  ) |
                                       (id_c_cm_mvsa01       & id_pc_rs2_a1_haz_wb   ) ;

wire         id_hazard_in_wb         = (id_hazard_rs1_in_wb  | id_hazard_rs2_in_wb   ) ;


// If there is a hazard detected with a LOAD instruction:
//
//                 - if ID instruction with forward    --> we stall during the whole EX phase, and then during wait state WB phase
//                 - if ID instruction without forward --> we stall during the whole EX phase, and then during whole WB phase
wire         id_load_stall_w_fwd     = (id_hazard_in_ex      & ex_load_busy) | ( id_hazard_in_wb     & wb_load_busy_i & ~wb_ldst_ready_i);
//wire       id_load_stall_wo_fwd    = (id_hazard_in_ex      & ex_load_busy) | ( id_hazard_in_wb     & wb_load_busy_i);

wire         id_load_stall_rs1_w_fwd  = (id_hazard_rs1_in_ex & ex_load_busy) | ( id_hazard_rs1_in_wb & wb_load_busy_i & ~wb_ldst_ready_i);
wire         id_load_stall_rs1_wo_fwd = (id_hazard_rs1_in_ex & ex_load_busy) | ( id_hazard_rs1_in_wb & wb_load_busy_i);


// If there is a hazard detected with the other instruction:
//
//                 - if ID instruction with forward    --> we stall during wait state EX phase --> we always stall during EX wait state for all instructions even if no hazard
//                 - if ID instruction without forward --> we stall during the whole EX phase (not for STORE)
assign       id_other_stall_w_fwd    = (~ex_alu_ready_i | ~ex_csr_ready_i | ~ex_uop_ready_i | ~ex_ldst_ready_i);
//assign     id_other_stall_wo_fwd   = ((ex_alu_busy    |  ex_csr_busy    |  ex_uop_busy)   &  id_hazard_in_ex);

wire         id_other_stall_rs1_w_fwd  = (~ex_alu_ready_i | ~ex_csr_ready_i | ~ex_ldst_ready_i | ~ex_uop_ready_i);
wire         id_other_stall_rs1_wo_fwd = (id_hazard_rs1_in_ex & (ex_alu_busy | ex_csr_busy | ex_uop_busy));


// Combine it all
wire         id_stall_w_fwd          = (id_load_stall_w_fwd      | id_other_stall_w_fwd     );
//wire       id_stall_wo_fwd         = (id_load_stall_wo_fwd     | id_other_stall_wo_fwd    );
wire         id_stall_rs1_w_fwd      = (id_load_stall_rs1_w_fwd  | id_other_stall_rs1_w_fwd );
wire         id_stall_rs1_wo_fwd     = (id_load_stall_rs1_wo_fwd | id_other_stall_rs1_wo_fwd);


// Standard-path-specific load stall: only valid when id_use_std_path=1 (opimm/op/csr are std-only).
wire         id_std_load_stall_rs1_w_fwd = (id_pc_rs1_std_haz_ex & ex_load_busy) | (id_pc_rs1_std_haz_wb & wb_load_busy_i & ~wb_ldst_ready_i);

// Generate the STALL conditions for the Instruction-Fetch unit
assign       fetch_stall_from_ex     =  id_other_stall_w_fwd;                                                          // Whatever the instruction, stall if there is a wait state during the EX phase
wire         fetch_stall_from_jalr   = (id_opcode_jalr    & (id_jalr_stall_rs1_wo_fwd | ~id_jalr_shadow_valid_fast));  // JALR uses rs1 only, without forwarding + shadow miss stall
wire         fetch_stall_from_branch = (id_opcode_branch  &  id_br_stall_w_fwd   );                                    // Branch instructions use rs1 and rs2, with forwarding
wire         fetch_stall_from_opimm  = (id_opcode_opimm   &  id_stall_rs1_w_fwd  );                                    // OP-IMM includes compressed variants (C.ADDI etc.) - must use class-aware stall
wire         fetch_stall_from_opreg  = (id_opcode_op      &  id_stall_w_fwd      );                                    // OP includes compressed variants (C.ADD etc.) - must use class-aware stall
wire         fetch_stall_from_csr    = (id_opcode_csr     & (id_std_load_stall_rs1_w_fwd | id_other_stall_rs1_w_fwd)); // CSR has no compressed equivalent: raw bits[19:15] safe
wire         fetch_stall_from_fence  = (id_opcode_fence   & (~ex_ldst_ready_i | ~wb_ldst_ready_i | wb_load_busy_i));   // FENCE waits for all load/store operations to complete
wire         fetch_stall_from_fence_i= (id_opcode_fence_i & (~ex_ldst_ready_i | ~wb_ldst_ready_i | wb_load_busy_i));   // FENCE.I waits for all stores to drain before issuing buffer flush
wire         fetch_stall_from_uop    = (id_uop_pushpop    &  id_stall_rs1_wo_fwd )|                                    // PushPop: RS1=SP, no forwarding
                                       (id_uop_mv         &  id_stall_w_fwd      );                                    // MVA/MVSA: RS1+RS2 with forwarding

// Trap stall: CSR trap module stalls decode while waiting for pipeline drain
assign       fetch_stall_from_trap   = trap_stall_i;

// JT slow-branch stall: hold decode while JVT branch is pending so the
// post-cm.jt instruction cannot advance into EX before branch_confirmed clears
// the fetch buffer.
generate
    if (ZCMT_EN) begin : gen_jt_stall
        wire fetch_stall_from_jt_branch_r;
        arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_jt_branch_stall (
                              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(ex_uop_jt_branch_active_i), .q_o(fetch_stall_from_jt_branch_r));
        assign fetch_stall_from_jt_branch = ex_uop_jt_branch_active_i | fetch_stall_from_jt_branch_r;
    end else begin : gen_no_jt_stall
        assign fetch_stall_from_jt_branch = 1'b0;
    end
endgenerate

// MRET/SRET/MNRET stall: must wait for any CSR write in EX to commit before
// reading MEPC/SEPC/MNEPC (and MNSTATUS for MNRET privilege restore),
// otherwise the register value is stale (RAW hazard). The (& NMI_EN) guard on
// the MNRET term keeps it synthesized away when Smrnmi is disabled.
wire         fetch_stall_from_xret   = (id_opcode_mret | id_opcode_sret | (id_opcode_mnret & NMI_EN)) & ex_csr_busy;

// WFI stall: set on WFI decode, cleared by interrupt pending or reset.
// Set has PRIORITY over clear: en = set | wfi_wakeup_i, nxt = set ? 1 : (wakeup ? 0 : hold).
wire         wfi_active;
wire         wfi_active_set        =  id_opcode_valid & id_opcode_wfi & id_instruction_request_sys;
wire         wfi_active_en         =  wfi_active_set | wfi_wakeup_i;
wire         wfi_active_nxt        =  wfi_active_set ? 1'b1 : (wfi_wakeup_i ? 1'b0 : wfi_active);
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_wfi_active (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(wfi_active_en), .d_i(wfi_active_nxt), .q_o(wfi_active));

assign       fetch_stall_from_wfi    = wfi_active;
assign       id_wfi_active_o         = wfi_active;

assign       id_instruction_request_o = ~(fetch_stall_from_ex        |
                                          fetch_stall_from_jalr      |
                                          fetch_stall_from_branch    |
                                       // id_opcode_load             // no need to stall during ID as RS1 is consumed during EX phase. This case is handled locally in load-store unit
                                       // id_opcode_store            // no need to stall during ID as RS1 and RS2 are consumed during EX phase. This case is handled locally in load-store unit
                                          fetch_stall_from_opimm     |
                                          fetch_stall_from_opreg     |
                                          fetch_stall_from_csr       |
                                          fetch_stall_from_uop       |
                                          fetch_stall_from_fence     |
                                          fetch_stall_from_fence_i   |
                                          fetch_stall_from_xret      |
                                          fetch_stall_from_trap      |
                                          fetch_stall_from_jt_branch |
                                          fetch_stall_from_wfi       );

// SYSTEM opcodes with funct3=000 (ECALL/EBREAK/MRET/SRET/MNRET/WFI) don't use
// RS1/RS2 in decode, so opcode-gated stalls (JALR, branch, opimm, opreg, CSR,
// fence, UOP) are mutually exclusive with them and can never fire simultaneously.
// Pipeline-gated stalls (xret, trap, wfi, jt_branch) CAN fire regardless of the
// ID opcode and must all be included
assign       id_instruction_request_sys = ~(fetch_stall_from_ex        |
                                            fetch_stall_from_xret      |
                                            fetch_stall_from_trap      |
                                            fetch_stall_from_jt_branch |
                                            fetch_stall_from_wfi       );


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                     EXCEPTIONS, PERFORMANCE COUNTERS & CLOCK ENABLE                                  //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Illegal instruction Trap detection
assign       id_excp_illegal_inst_o = (id_instruction_request_o & id_instruction_valid_i & id_opcode_error);

// Instruction retired: asserted each cycle an instruction is dispatched from decode.
// Gated by (id_use_std_path | id_use_c_path) to suppress the UOP-branch shadow cycle:
// when ex_uop_has_branch=1 (CM.POPRET / CM.POPRETZ final RET cycle), both path enables
// are muted and the decoder is just being flushed -- without this gate id_inst_retired_o
// would fire spuriously and minstret would over-count by 1 per CM.POPRET/POPRETZ.
// (Reproducer: sim/rtl_sim/src/inst_zicntr_uop_count.{s,v})
assign       id_inst_retired_o      = id_instruction_request_o & id_instruction_valid_i
                                    & (id_use_std_path | id_use_c_path);

// HPM pipeline event bus
// [0] fetch stall:       instruction fetch not valid (instruction memory stalling)
// [1] LSU stall:         load/store unit not ready
// [2] ALU stall:         multi-cycle ALU op (MUL/DIV) not ready
// [3] CSR stall:         CSR access not ready (e.g. time req/gnt)
// [4] branch taken:      conditional branch dispatched and taken
// [5] branch not taken:  conditional branch dispatched and not taken
// [6] load:              load instruction dispatched
// [7] store:             store instruction dispatched
generate
    if (ZIHPM_NR > 0) begin : gen_hpm_events

        // Registered to break long combinational paths (e.g. through ALU forwarding).
        // HPM counters tolerate a 1-cycle latency on event signals.
        wire [7:0] id_hpm_events_reg;
        wire [7:0] id_hpm_events_nxt = { id_ldst_active & ~id_load_active,                                                  // [7] store
                                         id_load_active,                                                                    // [6] load
                                         id_branch_taken,                                                                   // [5] branch taken
                                         id_instruction_request_o & id_opcode_valid & id_opcode_branch,                     // [4] branch decision (taken or not taken)
                                        ~ex_csr_ready_i,                                                                    // [3] CSR stall
                                        ~ex_alu_ready_i,                                                                    // [2] ALU stall
                                        ~ex_ldst_ready_i,                                                                   // [1] LSU stall
                                        ~id_instruction_valid_i};                                                          // [0] fetch stall

        arv_dff #(.WIDTH(8), .ARST_EN(ARST_EN)) u_id_hpm_events (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(id_hpm_events_nxt), .q_o(id_hpm_events_reg));

       assign id_hpm_events_o[7:6] = id_hpm_events_reg[7:6];
       assign id_hpm_events_o[5]   = id_hpm_events_reg[4] & ~id_hpm_events_reg[5];
       assign id_hpm_events_o[4]   = id_hpm_events_reg[4] &  id_hpm_events_reg[5];
       assign id_hpm_events_o[3:0] = id_hpm_events_reg[3:0];

    end else begin : gen_hpm_events_disabled

       assign id_hpm_events_o = 8'h0;

    end
endgenerate

// Lint cleanup
wire [4:0] id_funct7_undecoded_unused = {id_funct7[6], id_funct7[4:1]};

endmodule // arv_decode

`default_nettype wire

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arvern
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arvern.v
// Module Description : RISC-V processor core
//                      (RV32I/E + Zicntr/Zihpm + M/B/C + Smrnmi NMI +
//                       Ss/Smdbltrp + S/M/U modes + PMP/Smepmp + WFI clock gating +
//                       external debug (Debug Spec 1.0) + Sdtrig)
//----------------------------------------------------------------------------
`default_nettype none

module  arvern (

// AHB CLOCK & RESET
    input  wire           hclk_i,                    // Main processor clock; all pipeline and CSR logic is synchronous to this clock
    input  wire           hresetn_i,                 // Active-low HART reset, synchronous or asynchronous per ASYNC_RST_EN (see integration guide)
    input  wire           dbgresetn_i,               // Active-low DEBUG-MODULE reset can be connected to hresetn_i if halt-on-reset feature is not needed. Unused when DEBUG_EN=0.
    output wire           hclk_en_o,                 // Clock enable output; deasserted during WFI sleep for SoC-level clock gating

// INSTRUCTION AHB BUS
    input  wire    [31:0] inst_hrdata_i,             // AHB read data from instruction memory
    input  wire           inst_hready_i,             // AHB ready: slave extends the transfer when low
    input  wire           inst_hresp_i,              // AHB error response: instruction access fault when high

    output wire    [31:0] inst_haddr_o,              // AHB byte address of the instruction fetch
    output wire     [2:0] inst_hburst_o,             // AHB burst type (always SINGLE for instruction fetch)
    output wire           inst_hmastlock_o,          // AHB locked transfer (always deasserted)
    output wire     [3:0] inst_hprot_o,              // AHB protection control (privilege/data/cacheable/bufferable)
    output wire     [2:0] inst_hsize_o,              // AHB transfer size (always word: 3'b010)
    output wire           inst_hsmode_o,             // Supervisor mode flag (combine with inst_hprot[1] to fully decode M/S/U); connect to HAUSER of the AHB interconnect
    output wire     [1:0] inst_htrans_o,             // AHB transfer type (IDLE or NONSEQ)
    output wire    [31:0] inst_hwdata_o,             // AHB write data (unused for instruction fetch, driven 0)
    output wire           inst_hwrite_o,             // AHB write enable (always low for instruction fetch)

// DATA AHB BUS
    input  wire    [31:0] data_hrdata_i,             // AHB read data from data memory or peripheral
    input  wire           data_hready_i,             // AHB ready: slave extends the transfer when low
    input  wire           data_hresp_i,              // AHB error response: raises a resumable NMI (mncause=0x80000003) when high

    output wire    [31:0] data_haddr_o,              // AHB byte address of the load/store
    output wire     [2:0] data_hburst_o,             // AHB burst type (always SINGLE)
    output wire           data_hmastlock_o,          // AHB locked transfer (always deasserted)
    output wire     [3:0] data_hprot_o,              // AHB protection control (privilege/data/cacheable/bufferable)
    output wire     [2:0] data_hsize_o,              // AHB transfer size (byte/halfword/word per instruction)
    output wire           data_hsmode_o,             // Supervisor mode flag (combine with data_hprot[1] to fully decode M/S/U); connect to HAUSER of the AHB interconnect
    output wire           data_hmaster_o,            // AHB transfer master: 0 = hart software access, 1 = debug module SBA access
    output wire     [1:0] data_htrans_o,             // AHB transfer type (IDLE or NONSEQ)
    output wire    [31:0] data_hwdata_o,             // AHB write data for store instructions
    output wire           data_hwrite_o,             // AHB write enable (high for stores, low for loads)

// INTERFACE TO CUSTOM CSR REGISTERS
    input  wire    [31:0] ccsr_rdata_i,              // Read data from custom CSR registers (sampled when ccsr_reg_sel_o is non-zero). When CCSR_EN=0 the custom-CSR interface is absent: tie this input to 0 (don't-care, never sampled).
    output wire    [10:0] ccsr_bank_o,               // CSR address bank select for custom register decoding
    output wire    [63:0] ccsr_reg_sel_o,            // One-hot register select within the custom CSR bank
    output wire    [31:0] ccsr_wdata_o,              // Write data for custom CSR registers
    output wire           ccsr_wen_o,                // Write enable for custom CSR registers

// EXTERNAL INTERRUPT INPUTS                         // Level-sensitive except irq_s_software_i (see below) - drive synchronous to hclk_i.
    input  wire           irq_m_software_i,          // Machine software interrupt (MSIP, MIP[3]);    connect to ACLINT MSWI register output for this hart
    input  wire           irq_s_software_i,          // Supervisor software interrupt (SSIP, MIP[1]); PULSE-SET: a one-cycle pulse (ACLINT SSWI model) sets the SSIP flop. Tie low if no S-mode SSWI source or if SU_MODE_EN=0 (M-only)
    input  wire           irq_m_timer_i,             // Machine timer interrupt (MTIP, MIP[7]);       connect to ACLINT MTIMER comparator output for this hart
    input  wire           irq_m_external_i,          // Machine external interrupt (MEIP, MIP[11]);   connect to PLIC M-mode context output for this hart
    input  wire           irq_s_external_i,          // Supervisor external interrupt (SEIP, MIP[9]); connect to PLIC S-mode context output; tie low if no S-mode PLIC context or if SU_MODE_EN=0 (M-only)
    input  wire    [15:0] irq_platform_i,            // Platform-designated interrupts (MIP[31:16]);  must be synchronous to hclk_i or synchronized externally; tie unused bits low if fewer than 16 platform IRQs

// OTHERS
    input  wire     [7:0] hartid_i,                  // Hart identifier; drives the mhartid CSR read value (zero-padded to mhartid[31:0]; only 256 harts addressable)
    input  wire    [31:0] reset_vector_i,            // Initial PC value after reset; loaded into the program counter on hresetn_i deassertion. Must be stable from before until at least one hclk_i edge after hresetn_i deasserts (typically a tie-off constant). Bits [1:0] are ignored (the reset PC is always word-aligned).

// LOCKUP STATUS
    output wire           lockup_o,                  // Smdbltrp critical-error signal: an M-mode double trap arrived with mnstatus.NMIE=0, so it could not divert to the RNMI handler. Execution has ceased and no architectural state changed. Sticky - only hresetn_i deasserts it. The platform response is platform-defined.

// NMI (SMRNMI)
    input  wire           nmi_i,                     // Non-maskable interrupt input (level-sensitive). No internal synchronizer - drive synchronous to hclk_i.

// TIME INTERFACE (ZICNTR)
    output wire           time_req_o,                // Level request: asserted while a time/timeh CSR read awaits the timer value; drops on the completion cycle. A new request is only issued after time_gnt_i has been observed low (4-phase).
    input  wire           time_gnt_i,                // Grant. Tie 1'b1 for a free-running hclk-synchronous counter (zero-stall reads). Pulse-grant (e.g. ahb_aclint) or hold-until-req-low timers both supported.
    input  wire    [63:0] time_val_i,                // 64-bit real-time counter (drives time/timeh CSR read data). Must be an hclk-domain register held stable through the cycle after the grant (pulse timers: held between refreshes). Read live on the registered-grant cycle; the timer owns any CDC.

// PLATFORM EVENTS (ZIHPM)
    input  wire     [7:0] hpm_platform_events_i,     // Platform-defined hardware performance monitoring event inputs (one bit per event)

// EXTERNAL DEBUG STATUS & RESET REQUEST
    output wire           dbg_debug_mode_o,          // 1 = hart is in Debug Mode
    output wire           dbg_halted_o,              // 1 = hart has halted (status to debugger)
    output wire           dbg_stoptime_o,            // dcsr.stoptime & Debug Mode: SoC should freeze mtime (0 when DEBUG_EN=0)
    output wire           dbg_ndmreset_o,            // dmcontrol.ndmreset (system-reset request)

// DEBUG MODULE INTERFACE (DMI) - APB4 slave, hclk domain (PCLK=hclk_i, PRESETn=dbgresetn_i)
    input  wire           dmi_psel_i,                // APB select
    input  wire           dmi_penable_i,             // APB enable (ACCESS phase)
    input  wire     [8:0] dmi_paddr_i,               // APB byte address (reg index = [8:2])
    input  wire           dmi_pwrite_i,              // 1=write, 0=read
    input  wire    [31:0] dmi_pwdata_i,              // APB write data
    input  wire     [2:0] dmi_pprot_i,               // APB protection (standard APB4 signal; ignored)
    output wire           dmi_pready_o,              // APB ready (1 wait state)
    output wire    [31:0] dmi_prdata_o,              // APB read data
    output wire           dmi_pslverr_o              // APB slave error (tied 0; future fault hook)

);

// USER PARAMETERs
//=================================================================================================================
parameter                 RV32E_EN            =  0;  // RV32E base ISA
                                                     //   0 = RV32I selected (32x integer registers)
                                                     //   1 = RV32E selected (16x integer registers)
//--------------------------------------------------------------------------------------------------------------
parameter                 SU_MODE_EN          =  0;  // S-mode + U-mode privilege modes
                                                     //   0 = M-mode only
                                                     //   1 = M + S + U modes present (full RISC-V priv. spec)
//--------------------------------------------------------------------------------------------------------------
parameter                 PMP_NR              =  0;  // Physical Memory Protection: writable entries, 0/4/8/16
                                                     // Smepmp is included whenever non-zero.
//--------------------------------------------------------------------------------------------------------------
parameter                 ZICNTR_EN           =  1;  // Zicntr extension enable (cycle, time, instret)
                                                     //   0 = absent (counter CSRs raise illegal-instruction, no counter logic)
                                                     //   1 = present (mcycle, minstret, mcounteren, + user shadows)
//--------------------------------------------------------------------------------------------------------------
parameter                 ZIHPM_NR            =  0;  // Zihpm: number of HPM counters (0-8)
//--------------------------------------------------------------------------------------------------------------
parameter                 B_EXTENSION         =  1;  // Bit manipulation extension level
                                                     //   0 = No bit manipulation
                                                     //   1 = Zbb (basic bit manipulation)
                                                     //   2 = Zbb + Zba (adds address generation)
                                                     //   3 = Zbb + Zba + Zbs (adds single-bit operations)
                                                     //   4 = Zbb + Zba + Zbs + Zbc (adds carry-less multiplication)
//--------------------------------------------------------------------------------------------------------------
parameter                 C_EXTENSION         =  1;  // Compressed instructions extension level
                                                     //   0 = No compression (C extension absent)
                                                     //   1 = Zca (base integer compressed instructions)
                                                     //   2 = Zca + Zcb (base + code-size reduction)
                                                     //   3 = Zca + Zcb + Zcmp (base + code-size + push/pop/moves)
                                                     //   4 = Zca + Zcb + Zcmp + Zcmt (base + code-size + push/pop/moves + table jumps)
//--------------------------------------------------------------------------------------------------------------
parameter                 M_EXTENSION         =  2;  // Integer Multiply/Divide extension
                                                     //   0 = No multiply/divide
                                                     //   1 = Zmmul (multiply only)
                                                     //   2 = M extension (multiply + divide)
//--------------------------------------------------------------------------------------------------------------
parameter                 MUL_TYPE            =  1;  // Multiplier type (valid only with Zmmul and M-extension)
                                                     //   0 = Reserved
                                                     //   1 = Single-cycle hardware multiplier
                                                     //   2 = Four-cycle hardware multiplier
                                                     //   3 = Sixteen-cycle hardware multiplier
//--------------------------------------------------------------------------------------------------------------
parameter                 DIV_TYPE            =  3;  // Divider type (valid only with M-extension)
                                                     //   0 = Reserved
                                                     //   1 = Radix-8 divider (12 cycles)
                                                     //   2 = Radix-4 divider (17 cycles)
                                                     //   3 = Radix-2 divider (33 cycles)
//--------------------------------------------------------------------------------------------------------------
parameter                 CCSR_EN             =  0;  // Enable Custom-CSR interface
                                                     //   0 = absent (CCSR port group unused; tie ccsr_rdata_i to 0)
                                                     //   1 = present
//--------------------------------------------------------------------------------------------------------------
parameter                 SINGLE_CYCLE_BRANCH =  1;  // Taken-branch latency (pure Fmax / IPC trade-off):
                                                     //   0 = one-bubble taken branch  (highest Fmax, lower IPC)
                                                     //   1 = zero-bubble taken branch (lower Fmax, highest IPC)
//--------------------------------------------------------------------------------------------------------------
parameter                 ASYNC_RST_EN        =  1;  // Reset style:
                                                     //   1 = async (negedge hresetn_i),
                                                     //   0 = sync (async term tied high -> sync-reset FF)
//--------------------------------------------------------------------------------------------------------------
parameter                 DEBUG_EN            =  0;  // External debug support (RISC-V Debug Spec 1.0, frozen-hart)
                                                     //   0 = absent (no Debug Module/DMI; debug CSRs 0x7B0-0x7B3 raise
                                                     //       illegal instruction; DMI/SBA/debug ports tied off)
                                                     //   1 = present (Debug Module + DMI bus exposed at top; abstract
                                                     //       Access Register for GPR/CSR; dcsr/dpc; System Bus
                                                     //       Access. Frozen-hart: resume via resumereq, no dret)
//--------------------------------------------------------------------------------------------------------------
parameter                 DM_TRIGGER_NR       =  0;  // Number of Sdtrig hardware triggers (0-8, 0 = no triggers)
                                                     // (only meaningful when DEBUG_EN = 1)
//=================================================================================================================


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                           PARAMETER CHECKS & DECLARATIONS                                            //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// DMI address width fed to arv_debug_dm
localparam          [5:0] DMI_ABITS = 6'd7;

// pragma translate_off
generate
    if ((RV32E_EN != 0) && (RV32E_EN != 1)) begin : CHECK_RV32E_EN
        initial $fatal(1, "arvern: RV32E_EN (%0d) must be 0 (RV32I) or 1 (RV32E).", RV32E_EN);
    end
    if ((SU_MODE_EN != 0) && (SU_MODE_EN != 1)) begin : CHECK_SU_MODE_EN
        initial $fatal(1, "arvern: SU_MODE_EN (%0d) must be 0 (M-only) or 1 (M+S+U).", SU_MODE_EN);
    end
    if ((ZICNTR_EN != 0) && (ZICNTR_EN != 1)) begin : CHECK_ZICNTR_EN
        initial $fatal(1, "arvern: ZICNTR_EN (%0d) must be 0 or 1.", ZICNTR_EN);
    end
    if ((ZIHPM_NR < 0) || (ZIHPM_NR > 8)) begin : CHECK_ZIHPM_NR
        initial $fatal(1, "arvern: ZIHPM_NR (%0d) is out of range [0,8].", ZIHPM_NR);
    end
    if ((PMP_NR != 0) && (PMP_NR != 4) && (PMP_NR != 8) && (PMP_NR != 16)) begin : CHECK_PMP_NR
        initial $fatal(1, "arvern: PMP_NR (%0d) must be 0, 4, 8 or 16.", PMP_NR);
    end
    if ((B_EXTENSION < 0) || (B_EXTENSION > 4)) begin : CHECK_B_EXTENSION
        initial $fatal(1, "arvern: B_EXTENSION (%0d) is out of range [0,4].", B_EXTENSION);
    end
    if ((C_EXTENSION < 0) || (C_EXTENSION > 4)) begin : CHECK_C_EXTENSION
        initial $fatal(1, "arvern: C_EXTENSION (%0d) is out of range [0,4].", C_EXTENSION);
    end
    if ((M_EXTENSION < 0) || (M_EXTENSION > 2)) begin : CHECK_M_EXTENSION
        initial $fatal(1, "arvern: M_EXTENSION (%0d) is out of range [0,2].", M_EXTENSION);
    end
    if ((MUL_TYPE < 1) || (MUL_TYPE > 3)) begin : CHECK_MUL_TYPE
        initial $fatal(1, "arvern: MUL_TYPE (%0d) is out of range [1,3].", MUL_TYPE);
    end
    if ((DIV_TYPE < 1) || (DIV_TYPE > 3)) begin : CHECK_DIV_TYPE
        initial $fatal(1, "arvern: DIV_TYPE (%0d) is out of range [1,3].", DIV_TYPE);
    end
    if ((CCSR_EN != 0) && (CCSR_EN != 1)) begin : CHECK_CCSR_EN
        initial $fatal(1, "arvern: CCSR_EN (%0d) must be 0 or 1.", CCSR_EN);
    end
    if ((ASYNC_RST_EN != 0) && (ASYNC_RST_EN != 1)) begin : CHECK_ASYNC_RST_EN
        initial $fatal(1, "arvern: ASYNC_RST_EN (%0d) must be 0 or 1.", ASYNC_RST_EN);
    end
    if ((SINGLE_CYCLE_BRANCH != 0) && (SINGLE_CYCLE_BRANCH != 1)) begin : CHECK_SINGLE_CYCLE_BRANCH
        initial $fatal(1, "arvern: SINGLE_CYCLE_BRANCH (%0d) must be 0 or 1.", SINGLE_CYCLE_BRANCH);
    end
    if ((DEBUG_EN != 0) && (DEBUG_EN != 1)) begin : CHECK_DEBUG_EN
        initial $fatal(1, "arvern: DEBUG_EN (%0d) must be 0 or 1.", DEBUG_EN);
    end
    if ((DM_TRIGGER_NR < 0) || (DM_TRIGGER_NR > 8)) begin : CHECK_DM_TRIGGER_NR
        initial $fatal(1, "arvern: DM_TRIGGER_NR (%0d) is out of range [0,8].", DM_TRIGGER_NR);
    end
    if (DMI_ABITS != 7) begin : CHECK_DMI_ABITS
        initial $fatal(1, "arvern: DMI_ABITS (%0d) must be 7 (the DM decodes dmi_paddr[8:2] only).", DMI_ABITS);
    end
endgenerate
// pragma translate_on

// PARAMETER-SANITIZATION PARADIGM (read before adding parameters or downstream logic):
// User parameters are NEVER consumed directly by submodules; every one is first normalized
// here into an `*_EN` / `*_PROC` / `*_USE` localparam, and only the normalized form is wired
// out. Out-of-range inputs are silently coerced by the normalization below; the sim-only
// $fatal range-checks above (translate_off) are the only elaboration-time diagnostics:
//   - Extension LEVELS (B/C/M_EXTENSION): saturating `>=` thresholds -> any too-large value
//     just enables all sub-tiers; safe by construction.
//   - MUL_TYPE / DIV_TYPE: explicit clamp to {1,2,3} via *_USE (out-of-range -> type 1).
//   - Booleans (CCSR/ZICNTR/SINGLE_CYCLE_BRANCH): `>=1` / `!=0` -> {0,1}. Smrnmi is unconditional.
//   - RV32E_EN: any non-zero -> RV32E.
//   - ZIHPM_NR: clamp to <=8 (see ZIHPM_NR_PROC note).
//   - DM_TRIGGER_NR: clamp to <=8 (DM_TRIGGER_NR_PROC); DM_TRIGGER_EN further requires DEBUG_EN.
// Rule: downstream code must reference the normalized localparams, never the raw parameters.

// Extension enables (sub-parameters derived from extension levels)
localparam                ZBB_EN                   = (B_EXTENSION >= 1) ? 1'b1   : 1'b0;                // Zbb extension (basic bit manipulation)
localparam                ZBA_EN                   = (B_EXTENSION >= 2) ? 1'b1   : 1'b0;                // Zba extension (address generation)
localparam                ZBS_EN                   = (B_EXTENSION >= 3) ? 1'b1   : 1'b0;                // Zbs extension (single-bit operations)
localparam                ZBC_EN                   = (B_EXTENSION >= 4) ? 1'b1   : 1'b0;                // Zbc extension (carry-less multiplication)
localparam                B_EXT_EN                 = ZBA_EN & ZBB_EN & ZBS_EN;                          // misa.B: complete ratified B ONLY (Zba & Zbb & Zbs; Zbc is NOT part of B)

localparam                C_EXT_EN                 = (C_EXTENSION >= 1) ? 1'b1   : 1'b0;                // Any compression enabled
localparam                ZCA_EN                   = (C_EXTENSION >= 1) ? 1'b1   : 1'b0;                // Zca extension (base compressed)
localparam                ZCB_EN                   = (C_EXTENSION >= 2) ? 1'b1   : 1'b0;                // Zcb extension (code-size reduction)
localparam                ZCMP_EN                  = (C_EXTENSION >= 3) ? 1'b1   : 1'b0;                // Zcmp extension (push/pop/double move)
localparam                ZCMT_EN                  = (C_EXTENSION >= 4) ? 1'b1   : 1'b0;                // Zcmt extension (table jumps)
localparam                UOP_EN                   = (C_EXTENSION >= 3) ? 1'b1   : 1'b0;                // UOP sequencer enabled with Zcmp and Zcmt

localparam                M_EXT_EN                 = (M_EXTENSION >= 2) ? 1'b1   : 1'b0;                // M extension enabled (multiply+divide)
localparam                MUL_EN                   = (M_EXTENSION >= 1) ? 1'b1   : 1'b0;                // Multiply enabled (Zmmul or M)
localparam                DIV_EN                   = (M_EXTENSION >= 2) ? 1'b1   : 1'b0;                // Divide enabled (M extension only)

// Clamp MUL_TYPE/DIV_TYPE to valid {1,2,3} - out-of-range falls back to type 1
localparam                MUL_TYPE_USE             = ((MUL_TYPE == 2) || (MUL_TYPE == 3)) ? MUL_TYPE : 1;
localparam                DIV_TYPE_USE             = ((DIV_TYPE == 2) || (DIV_TYPE == 3)) ? DIV_TYPE : 1;

localparam                MUL_1C_EN                = (MUL_TYPE_USE == 1) ? MUL_EN : 1'b0;               // Single-cycle multiplier
localparam                MUL_4C_EN                = (MUL_TYPE_USE == 2) ? MUL_EN : 1'b0;               // Four-cycle multiplier
localparam                MUL_16C_EN               = (MUL_TYPE_USE == 3) ? MUL_EN : 1'b0;               // Sixteen-cycle multiplier

localparam                DIV_12C_EN               = (DIV_TYPE_USE == 1) ? DIV_EN : 1'b0;               // Radix-8 divider (12 cycles)
localparam                DIV_17C_EN               = (DIV_TYPE_USE == 2) ? DIV_EN : 1'b0;               // Radix-4 divider (17 cycles)
localparam                DIV_33C_EN               = (DIV_TYPE_USE == 3) ? DIV_EN : 1'b0;               // Radix-2 divider (33 cycles)

localparam                RV32I_EN                 = (RV32E_EN    == 0) ? 1'b1    : 1'b0;               // RV32I selected (32x integer registers)
localparam                CCSR_EN_PROC             = (CCSR_EN     >= 1) ? 1'b1    : 1'b0;               // Enable Custom-CSR interface
localparam                SU_MODE_EN_PROC          = (SU_MODE_EN  >= 1) ? 1'b1    : 1'b0;               // Enable S+U privilege modes (0 = M-only)
localparam                ZICNTR_EN_PROC           = (ZICNTR_EN   >= 1) ? 1'b1    : 1'b0;               // Enable Zicntr extension
localparam                ZIHPM_NR_PROC            = (ZIHPM_NR    <  0) ? 4'h0    :
                                                     (ZIHPM_NR    >  8) ? 4'h8    : ZIHPM_NR[3:0];      // Zihpm: number of HPM counters (0-8),
                                                                                                        // two-sided clamp (mirrors DM_TRIGGER_NR_PROC):
                                                                                                        // a negative override clamps to 0 instead of
                                                                                                        // truncating to 4'hF

localparam                ASYNC_RST_EN_PROC        = (ASYNC_RST_EN== 0) ? 1'b0    : 1'b1;               // Reset style

localparam                DEBUG_EN_PROC            = (DEBUG_EN      >= 1) ? 1'b1  : 1'b0;               // Enable external debug support
localparam          [3:0] DM_TRIGGER_NR_PROC       = (DM_TRIGGER_NR <  0) ? 4'd0  :
                                                     (DM_TRIGGER_NR >  8) ? 4'd8  : DM_TRIGGER_NR[3:0]; // Sdtrig: number of triggers (0-8)
localparam                DM_TRIGGER_EN            = DEBUG_EN_PROC & (DM_TRIGGER_NR_PROC > 0);          // Sdtrig present only when external debug is on
                                                                                                        // AND at least one trigger is configured (so a
                                                                                                        // DEBUG_EN=0 build stays bit-identical regardless
                                                                                                        // of DM_TRIGGER_NR).

localparam                SINGLE_CYCLE_BRANCH_PROC = (SINGLE_CYCLE_BRANCH != 0)  ? 1'b1 : 1'b0;         // Clamp to 1-bit boolean

localparam          [4:0] PMP_NR_PROC              = (PMP_NR >= 16) ? 5'd16 :
                                                     (PMP_NR >=  8) ? 5'd8  :
                                                     (PMP_NR >=  4) ? 5'd4  : 5'd0;                     // snap DOWN to a legal count

localparam          [2:0] C_EXT_LEVEL_PROC         = (C_EXTENSION   <  0) ? 3'd0  :
                                                     (C_EXTENSION   >  4) ? 3'd4  : C_EXTENSION[2:0];   // marv_cfg[26:24]
localparam          [2:0] B_EXT_LEVEL_PROC         = (B_EXTENSION   <  0) ? 3'd0  :
                                                     (B_EXTENSION   >  4) ? 3'd4  : B_EXTENSION[2:0];   // marv_cfg[22:20]

// RTL version, reported in mimpid[31:8] as one byte per component:
//   24'h010000 = v1.0.0   24'h010203 = v1.2.3
// MINOR changes when firmware-visible behaviour changed since the previous version,
// PATCH when nothing did (RTL cleanup, lint fix, synthesis-only tweak). The arch-test
// configs declare the same value (IMP_ID_VALUE / platform.impid) and must move with it.
// mimpid[7:0] is reserved.
localparam         [23:0] RTL_VERSION              = 24'h010000;



//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                            INTERNAL WIRES/REGISTERS DECLARATION                                      //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Interface to the Instruction Decoder
wire                      id_instruction_request;
wire               [31:0] id_instruction;
wire                      id_instruction_valid;
wire                [1:0] id_priv_mode;
wire               [31:0] id_pc;
wire                      id_branch_detect;
wire                      id_branch_cancel;
wire               [31:0] id_branch_target;
wire               [31:0] id_branch_target_nxt;
wire                      id_slow_branch;
wire               [31:0] id_slow_branch_target;

// Interface to the Register bank for the ALU
wire               [31:0] ex_alu_reg_dest_wdata;
wire                      ex_alu_reg_dest_wr;
wire                [4:0] id_reg_src1_sel;
wire               [31:0] id_reg_src1_rdata_w_fwd;
wire                [4:0] id_reg_src2_sel;
wire               [31:0] id_reg_src2_rdata_w_fwd;
wire                [4:0] id_branch_rs1_fast_sel;
wire               [31:0] id_branch_rs1_rdata_w_fwd;
wire                [4:0] id_branch_rs2_fast_sel;
wire               [31:0] id_branch_rs2_rdata_w_fwd;

// Interface to the ALU
wire                [4:0] ex_dec_alu_mode;
wire                      ex_dec_alu_select;
wire               [16:0] ex_dec_alu_control;
wire               [31:0] ex_operand1;
wire               [31:0] ex_operand2;
wire                [4:0] ex_uop_ld_dest_sel;
wire                      ex_uop_mv_dest_ctrl;
wire                [4:0] ex_reg_dest_sel;
wire                [4:0] ex_reg_dest_sel_mux;
wire                [4:0] wb_reg_dest_sel;
wire                      wb_load_busy;
wire                      ex_alu_ready;

// Interface to the Register bank for the Load-Store unit
wire               [31:0] wb_load_reg_dest_wdata;
wire                      wb_load_reg_dest_wr;
wire                [4:0] ex_reg_src1_sel;
wire               [31:0] ex_reg_src1_rdata_wo_fwd;
wire                [4:0] ex_reg_src2_sel;
wire               [31:0] ex_reg_src2_rdata_wo_fwd;

// Interface to the Register bank for the CSR Registers
wire                      ex_csr_ready;
wire                [3:0] ex_csr_control;
wire               [31:0] ex_csr_reg_dest_wdata;
wire                      ex_csr_reg_dest_wr;
wire                [1:0] if_priv_mode;
wire                [1:0] priv_mode_ldst;
wire                      init_pc;
wire                      cfg_timeout_wait;
wire                      cfg_trap_sret;
wire                      if_stop_cmd;

// Interface to the Load-Store unit
wire                      ex_ldst_ready;
wire                      ex_ldst_ready_fetch;
wire                      ex_ldst_unresolved;
wire                      ex_pmp_refetch;
wire                      wb_ldst_ready;
wire                      wb_dph_ongoing;
wire                [4:0] ex_dec_ldst_control;
wire                [4:0] ex_uop_ldst_control;
wire               [31:0] ex_uop_ldst_immediate;

// Interface to the Micro-Operation Sequencer
wire                      ex_uop_ready;
wire                [9:0] ex_uop_control;
wire                      ex_c_cm_push_nxt;
wire               [31:0] ex_uop_src1_sel;
wire               [31:0] id_uop_src1_sel;
wire               [31:0] ex_uop_src2_sel;
wire                      id_uop_start;
wire                      id_uop_jt_start;
wire                [7:0] id_uop_ldst_start;
wire               [16:0] ex_uop_alu_control;
wire                [4:0] ex_uop_alu_mode;
wire                      ex_uop_alu_select;
wire                      ex_uop_a0_zero_en;

// Zcmt JVT and table jump signals
wire               [31:0] jvt_base;
wire               [31:0] ex_uop_jt_base;
wire                      ex_uop_jt_branch_active;
wire               [31:0] ex_uop_jt_branch_target;
wire                      ex_uop_jt_active;

// JALR shadow register
wire               [31:0] id_jalr_shadow_rdata;
wire                [4:0] id_jalr_shadow_sel;
wire                      id_opcode_jalr;
wire                      ex_uop_ret_branch;
wire                      ex_uop_has_branch;
wire                      ex_uop_take_branch;

// Exception (synchronous traps) Detection
wire                      id_opcode_mret;
wire                      id_opcode_sret;
wire                      id_opcode_mnret;
wire                      if_excp_inst_address_misaligned;
wire                      id_excp_inst_access_fault;
wire               [31:0] id_inst_fault_addr;
wire                      id_excp_illegal_inst;
wire                      id_excp_ebreak;
wire                      id_excp_ebreak_nodbg;
wire                      id_issue_active_nodbg;
wire                      id_excp_ecall;
wire                      ex_excp_load_address_misaligned;
wire                      ex_excp_load_access_fault;
wire                      ex_excp_store_access_fault;
wire        [16*8-1:0]    pmp_cfg;
wire       [16*32-1:0]    pmp_addr;
wire                      pmp_mml;
wire                      pmp_mmwp;
wire                      ex_excp_store_address_misaligned;
wire                      wb_bus_error_load;
wire                      wb_bus_error_store;

// Trap interface (CSR <-> Decode)
wire                      trap_stall;
wire                      ex_excp_squash;
wire                      trap_branch_detect;
wire               [31:0] trap_branch_target;
wire                      wfi_wakeup;
wire                      wfi_wakeup_live;
wire                      id_wfi_active;
wire                      debug_halt_active;
wire                      debug_issue_hold;
wire                      debug_ebreak_cfg;
wire                      trig_break_issue_kill;
wire                      ex_is_load;
wire                      ex_is_store;
wire                      trig_ls_fire;
wire                      dm_haltreq;
wire                      dm_resumereq;
wire                      dm_resethaltreq;
wire                      dm_gpr_wen;
wire                [4:0] dm_gpr_waddr;
wire               [31:0] dm_gpr_wdata;
wire                [4:0] dm_gpr_raddr;
wire                      dm_gpr_ren;
wire               [31:0] dm_gpr_rdata;
wire                      dm_csr_access;
wire                [1:0] dm_csr_sel;
wire                      dm_csr_wen;
wire               [31:0] dm_csr_wdata;
wire               [31:0] dm_csr_rdata;
wire                      dm_acsr_active;
wire               [11:0] dm_acsr_addr;
wire                      dm_acsr_wen;
wire               [31:0] dm_acsr_wdata;
wire               [31:0] dm_acsr_rdata;
wire                      dm_acsr_fault;

// Debug System Bus Access (SBA) AHB-Lite master, arbitrated onto the data port below.
wire                      dm_sb_busy;
wire                      dm_sb_req;
wire                      dm_sb_gnt;
wire                      dm_sb_active;
wire               [31:0] dm_sb_haddr;
wire                [1:0] dm_sb_htrans;
wire                      dm_sb_hwrite;
wire                [2:0] dm_sb_hsize;
wire                [2:0] dm_sb_hburst;
wire               [31:0] dm_sb_hwdata;

// LSU AHB data-bus outputs (internal copies, muxed with the SBA master onto the ports).
wire                [2:0] lsu_hburst;
wire                      lsu_hmastlock;
wire                [3:0] lsu_hprot;
wire                [2:0] lsu_hsize;
wire                      lsu_hsmode;
wire               [31:0] lsu_hwdata;
wire                      lsu_hwrite;

// LSU AHB data-bus response inputs (arbitrated view - see the SBA arbitration below).
wire                      lsu_hready;
wire                      lsu_hresp;

wire                      trap_kill_ex;
wire                      trap_kill_muldiv;
wire                      trap_kill_uop;
wire                      trap_kill_uop_hold;
wire                      ex_uop_excp_abort;
wire                      ex_uop_jt_fault;
wire                      ex_alu_is_killable;
wire                      ex_uop_is_killable;
wire                      ex_uop_kill_window;

// PC pipeline for MEPC save
wire               [31:0] ex_pc;
wire               [31:0] wb_pc;

// LSU AHB data-address: internal copy so the CSR module can sample EX-stage
// data address for MTVAL without reading back the module's own output port.
wire               [31:0] data_haddr;

// AHB HTRANS internal copies
wire                [1:0] inst_htrans;
wire                [1:0] data_htrans;

// Instruction retired (from decoder, for minstret)
wire                      id_inst_retired;
wire                [7:0] id_hpm_events;

// Data address pipeline for MTVAL save
wire               [31:0] wb_data_addr;
wire                      wb_uop_sourced;
wire                      wb_uop_seq_alive;
wire                      wb_uop_jt_sourced;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                              INSTRUCTION FETCH UNIT                                                  //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

arv_fetch #(.ARST_EN             (ASYNC_RST_EN_PROC       ),
            .PMP_NR              (PMP_NR_PROC             ),
            .C_EXT_EN            (C_EXT_EN                ),
            .SINGLE_CYCLE_BRANCH (SINGLE_CYCLE_BRANCH_PROC)) arv_fetch_inst (

// AHB CLOCK & RESET
    .hclk_i                             ( hclk_i                           ),
    .hresetn_i                          ( hresetn_i                        ),

// INSTRUCTION AHB BUS
    .inst_hrdata_i                      ( inst_hrdata_i                    ),
    .inst_hready_i                      ( inst_hready_i                    ),
    .inst_hresp_i                       ( inst_hresp_i                     ),

    .inst_haddr_o                       ( inst_haddr_o                     ),
    .inst_hburst_o                      ( inst_hburst_o                    ),
    .inst_hmastlock_o                   ( inst_hmastlock_o                 ),
    .inst_hprot_o                       ( inst_hprot_o                     ),
    .inst_hsize_o                       ( inst_hsize_o                     ),
    .inst_hsmode_o                      ( inst_hsmode_o                    ),
    .inst_htrans_o                      ( inst_htrans                      ),
    .inst_hwdata_o                      ( inst_hwdata_o                    ),
    .inst_hwrite_o                      ( inst_hwrite_o                    ),

// INTERFACE TO DECODER
    .id_branch_detect_i                 ( id_branch_detect                 ),
    .id_branch_cancel_i                 ( id_branch_cancel                 ),
    .id_branch_target_i                 ( id_branch_target                 ),
    .id_branch_target_nxt_i             ( id_branch_target_nxt             ),
    .id_slow_branch_i                   ( id_slow_branch                   ),
    .id_slow_branch_target_i            ( id_slow_branch_target            ),
    .ex_uop_has_branch_i                ( ex_uop_has_branch                ),
    .id_instruction_request_i           ( id_instruction_request           ),
    .id_instruction_o                   ( id_instruction                   ),
    .id_instruction_valid_o             ( id_instruction_valid             ),
    .id_pc_o                            ( id_pc                            ),
    .id_priv_mode_o                     ( id_priv_mode                     ),

// INTERFACE TO TRAP HANDLER
    .if_stop_cmd_i                      ( if_stop_cmd                      ),

// OTHERS
    .if_priv_mode_i                     ( if_priv_mode                     ),
    .reset_vector_i                     ( reset_vector_i                   ),
    .pmp_cfg_i                          ( pmp_cfg                          ),
    .pmp_addr_i                         ( pmp_addr                         ),
    .pmp_mml_i                          ( pmp_mml                          ),
    .pmp_mmwp_i                         ( pmp_mmwp                         ),
    .id_excp_inst_access_fault_o        ( id_excp_inst_access_fault        ),
    .id_inst_fault_addr_o               ( id_inst_fault_addr               ),
    .if_excp_inst_address_misaligned_o  ( if_excp_inst_address_misaligned  ),
    .init_pc_o                          ( init_pc                          )

);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                              INSTRUCTION DECODER                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

arv_decode #(.ARST_EN(ASYNC_RST_EN_PROC),
             .ZCA_EN      (ZCA_EN           ),
             .ZCB_EN      (ZCB_EN           ),
             .ZCMP_EN     (ZCMP_EN          ),
             .ZCMT_EN     (ZCMT_EN          ),
             .UOP_EN      (UOP_EN           ),
             .ZBA_EN      (ZBA_EN           ),
             .ZBB_EN      (ZBB_EN           ),
             .ZBS_EN      (ZBS_EN           ),
             .ZBC_EN      (ZBC_EN           ),
             .MUL_EN      (MUL_EN           ),
             .DIV_EN      (DIV_EN           ),
             .PMP_NR      (PMP_NR_PROC      ),
             .SU_MODE_EN  (SU_MODE_EN_PROC  ),
             .ZIHPM_NR    (ZIHPM_NR_PROC    )) arv_decode_inst (

// AHB CLOCK & RESET
    .hclk_i                             ( hclk_i                           ),
    .hresetn_i                          ( hresetn_i                        ),

// FROM/TO INSTRUCTION FETCH UNIT
    .id_instruction_i                   ( id_instruction                   ),
    .id_instruction_valid_i             ( id_instruction_valid             ),
    .id_priv_mode_i                     ( id_priv_mode                     ),
    .id_pc_i                            ( id_pc                            ),
    .id_branch_detect_o                 ( id_branch_detect                 ),
    .id_branch_cancel_o                 ( id_branch_cancel                 ),
    .id_branch_target_o                 ( id_branch_target                 ),
    .id_branch_target_nxt_o             ( id_branch_target_nxt             ),
    .id_slow_branch_o                   ( id_slow_branch                   ),
    .id_slow_branch_target_o            ( id_slow_branch_target            ),
    .id_instruction_request_o           ( id_instruction_request           ),

// INTEGER REGISTER READ DURING DECODE PHASE (FOR ALU & BRANCHES)
    .id_reg_src1_rdata_w_fwd_i          ( id_reg_src1_rdata_w_fwd          ),
    .id_reg_src2_rdata_w_fwd_i          ( id_reg_src2_rdata_w_fwd          ),
    .id_branch_rs1_rdata_w_fwd_i        ( id_branch_rs1_rdata_w_fwd        ),
    .id_branch_rs2_rdata_w_fwd_i        ( id_branch_rs2_rdata_w_fwd        ),
    .id_reg_src1_sel_o                  ( id_reg_src1_sel                  ),
    .id_reg_src2_sel_o                  ( id_reg_src2_sel                  ),
    .id_branch_rs1_fast_sel_o           ( id_branch_rs1_fast_sel           ),
    .id_branch_rs2_fast_sel_o           ( id_branch_rs2_fast_sel           ),

// JALR SHADOW REGISTER
    .id_jalr_shadow_rdata_i             ( id_jalr_shadow_rdata             ),
    .id_jalr_shadow_sel_i               ( id_jalr_shadow_sel               ),
    .id_opcode_jalr_o                   ( id_opcode_jalr                   ),
    .ex_uop_ret_branch_o                ( ex_uop_ret_branch                ),

// INTEGER REGISTER READ DURING EXECUTION PHASE (FOR LOAD-STORE)
    .ex_reg_src1_sel_o                  ( ex_reg_src1_sel                  ),
    .ex_reg_src2_sel_o                  ( ex_reg_src2_sel                  ),

// INTEGER REGISTER WRITE
    .wb_reg_dest_sel_i                  ( wb_reg_dest_sel                  ),
    .ex_reg_dest_sel_o                  ( ex_reg_dest_sel                  ),

// FROM/TO ALU
    .ex_alu_ready_i                     ( ex_alu_ready                     ),
    .ex_alu_control_o                   ( ex_dec_alu_control               ),
    .ex_alu_mode_o                      ( ex_dec_alu_mode                  ),
    .ex_alu_select_o                    ( ex_dec_alu_select                ),

// FROM/TO LOAD-STORE UNIT
    .ex_ldst_ready_i                    ( ex_ldst_ready                    ),
    .ex_ldst_ready_fetch_i              ( ex_ldst_ready_fetch              ),
    .wb_ldst_ready_i                    ( wb_ldst_ready                    ),
    .wb_load_busy_i                     ( wb_load_busy                     ),
    .ex_ldst_control_o                  ( ex_dec_ldst_control              ),

// FROM/TO CSR REGISTERS
    .cfg_timeout_wait_i                 ( cfg_timeout_wait                 ),
    .cfg_trap_sret_i                    ( cfg_trap_sret                    ),
    .ex_csr_ready_i                     ( ex_csr_ready                     ),
    .ex_csr_control_o                   ( ex_csr_control                   ),
    .ex_uop_has_branch_o                ( ex_uop_has_branch                ),
    .ex_uop_take_branch_o               ( ex_uop_take_branch               ),

// TO ALU, LOAD-STORE UNIT AND CSR REGISTERS
    .ex_operand1_o                      ( ex_operand1                      ),
    .ex_operand2_o                      ( ex_operand2                      ),

// TRAPS & IRQ RELATED
    .id_excp_ebreak_o                   ( id_excp_ebreak                   ),
    .id_excp_ebreak_nodbg_o             ( id_excp_ebreak_nodbg             ),
    .id_issue_active_nodbg_o            ( id_issue_active_nodbg            ),
    .id_excp_ecall_o                    ( id_excp_ecall                    ),
    .id_excp_illegal_inst_o             ( id_excp_illegal_inst             ),
    .id_opcode_mret_o                   ( id_opcode_mret                   ),
    .id_opcode_sret_o                   ( id_opcode_sret                   ),
    .id_opcode_mnret_o                  ( id_opcode_mnret                  ),

// FROM/TO UOP SEQUENCER
    .ex_uop_ready_i                     ( ex_uop_ready                     ),
    .ex_uop_kill_i                      ( trap_kill_uop                    ),
    .ex_uop_excp_abort_i                ( ex_uop_excp_abort                ),
    .ex_uop_jt_fault_i                  ( ex_uop_jt_fault                  ),
    .ex_pmp_refetch_o                   ( ex_pmp_refetch                   ),
    .ex_uop_control_o                   ( ex_uop_control                   ),
    .ex_c_cm_push_nxt_o                 ( ex_c_cm_push_nxt                 ),
    .id_uop_start_o                     ( id_uop_start                     ),
    .id_uop_jt_start_o                  ( id_uop_jt_start                  ),
    .id_uop_ldst_start_o                ( id_uop_ldst_start                ),
    .ex_uop_jt_branch_active_i          ( ex_uop_jt_branch_active          ),
    .ex_uop_jt_branch_target_i          ( ex_uop_jt_branch_target          ),

// TRAP INTERFACE FROM CSR
    .trap_stall_i                       ( trap_stall                       ),
    .ex_excp_squash_i                   ( ex_excp_squash                   ),
    .trap_branch_detect_i               ( trap_branch_detect               ),
    .trap_branch_target_i               ( trap_branch_target               ),
    .wfi_wakeup_i                       ( wfi_wakeup                       ),
    .id_wfi_active_o                    ( id_wfi_active                    ),
    .debug_stall_i                      ( debug_halt_active                ),
    .debug_issue_hold_i                 ( debug_issue_hold                 ),
    .debug_ebreak_cfg_i                 ( debug_ebreak_cfg                 ),
    .trig_break_issue_kill_i            ( trig_break_issue_kill            ),

// PC PIPELINE OUTPUT
    .ex_pc_o                            ( ex_pc                            ),

// INSTRUCTION RETIRED (for minstret)
    .id_inst_retired_o                  ( id_inst_retired                  ),

// HPM PIPELINE EVENTS
    .id_hpm_events_o                    ( id_hpm_events                    )

);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                             MICRO-OPERATION SEQUENCER                                                //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

generate
    if (UOP_EN) begin : WITH_UOP_SEQUENCER

        arv_uop_sequencer #(.ARST_EN(ASYNC_RST_EN_PROC),
                            .ZCMT_EN     (ZCMT_EN          )) arv_uop_sequencer_inst (

            .hclk_i                        ( hclk_i                           ),
            .hresetn_i                     ( hresetn_i                        ),

            // Control from Decoder
            .ex_uop_enable_i               ( ex_uop_control[9]                ),
            .ex_uop_type_i                 ( ex_uop_control[8:5]              ),
            .ex_uop_rlist_i                ( ex_uop_control[3:0]              ),
            .ex_c_cm_push_nxt_i            ( ex_c_cm_push_nxt                 ),
            .id_uop_start_i                ( id_uop_start                     ),
            .id_uop_jt_start_i             ( id_uop_jt_start                  ),
            .id_uop_ldst_start_i           ( id_uop_ldst_start                ),

            .kill_i                        ( trap_kill_uop                    ),
            .kill_hold_i                   ( trap_kill_uop_hold               ),
            .is_killable_o                 ( ex_uop_is_killable               ),
            .kill_window_o                 ( ex_uop_kill_window               ),

            .ex_uop_ready_o                ( ex_uop_ready                     ),

            // Direct control of Load-Store
            .ex_ldst_ready_i               ( ex_ldst_ready                    ),
            .wb_ldst_ready_i               ( wb_ldst_ready                    ),
            .wb_dph_ongoing_i              ( wb_dph_ongoing                   ),
            .ex_ldst_control_o             ( ex_uop_ldst_control              ),
            .ex_ldst_immediate_o           ( ex_uop_ldst_immediate            ),

            // Direct control of ALU
            .ex_alu_ready_i                ( ex_alu_ready                     ),
            .ex_alu_control_o              ( ex_uop_alu_control               ),
            .ex_alu_mode_o                 ( ex_uop_alu_mode                  ),
            .ex_alu_select_o               ( ex_uop_alu_select                ),

            // Register file interface
            .ex_uop_src1_sel_o             ( ex_uop_src1_sel                  ),
            .id_uop_src1_sel_o             ( id_uop_src1_sel                  ),
            .ex_uop_src2_sel_o             ( ex_uop_src2_sel                  ),
            .ex_uop_ld_dest_sel_o          ( ex_uop_ld_dest_sel               ),
            .ex_uop_mv_dest_ctrl_o         ( ex_uop_mv_dest_ctrl              ),

            // CM.POPRETZ: zero a0
            .ex_uop_a0_zero_en_o           ( ex_uop_a0_zero_en                ),

            // CM.JT / CM.JALT: JVT inputs
            .jvt_base_i                    ( jvt_base                         ),
            .wb_ldst_data_i                ( wb_load_reg_dest_wdata           ),
            .wb_ldst_wr_i                  ( wb_load_reg_dest_wr              ),
            .wb_bus_error_load_i           ( wb_bus_error_load                ),

            // CM.JT / CM.JALT: table jump outputs
            .ex_uop_jt_base_o              ( ex_uop_jt_base                   ),
            .ex_uop_jt_branch_active_o     ( ex_uop_jt_branch_active          ),
            .ex_uop_jt_branch_target_o     ( ex_uop_jt_branch_target          ),
            .ex_uop_jt_active_o            ( ex_uop_jt_active                 )

        );

    end else begin : NO_UOP_SEQUENCER

        assign ex_uop_ready                  =  1'b1;
        assign ex_uop_is_killable            =  1'b0;
        assign ex_uop_kill_window            =  1'b0;
        assign ex_uop_ldst_control           =  5'h00;
        assign ex_uop_ldst_immediate         = 32'h00000000;
        assign ex_uop_alu_control            = 17'h00000;
        assign ex_uop_alu_mode               =  5'h00;
        assign ex_uop_alu_select             =  1'b0;
        assign ex_uop_src1_sel               = 32'h00000000;
        assign id_uop_src1_sel               = 32'h00000000;
        assign ex_uop_src2_sel               = 32'h00000000;
        assign ex_uop_ld_dest_sel            =  5'h00;
        assign ex_uop_mv_dest_ctrl           =  1'b0;
        assign ex_uop_a0_zero_en             =  1'b0;
        assign ex_uop_jt_base                = 32'h00000000;
        assign ex_uop_jt_branch_active       =  1'b0;
        assign ex_uop_jt_branch_target       = 32'h00000000;
        assign ex_uop_jt_active              =  1'b0;

        wire  [9:0] ex_uop_control_unused    = ex_uop_control;
        wire        ex_c_cm_push_nxt_unused  = ex_c_cm_push_nxt;
        wire        id_uop_start_unused      = id_uop_start;
        wire        id_uop_jt_start_unused   = id_uop_jt_start;
        wire  [7:0] id_uop_ldst_start_unused = id_uop_ldst_start;
        wire [31:0] jvt_base_unused          = jvt_base;
        wire        trap_kill_uop_unused     = trap_kill_uop;
        wire        trap_kill_uop_hold_unused = trap_kill_uop_hold;
        wire        wb_dph_ongoing_unused    = wb_dph_ongoing;

    end
endgenerate


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                INTEGER REGISTERS                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

arv_int_registers #(.ARST_EN(ASYNC_RST_EN_PROC),
                    .RV32I_EN    (RV32I_EN         ),
                    .C_EXT_EN    (C_EXT_EN         )) arv_int_registers_inst (

// AHB CLOCK & RESET
    .hclk_i                             ( hclk_i                           ),
    .hresetn_i                          ( hresetn_i                        ),

// DESTINATION REGISTER CONTROL (FOR ALU, LOAD UNIT AND CSR INTERFACE)
    .ex_reg_dest_sel_i                  ( ex_reg_dest_sel                  ),
    .wb_reg_dest_sel_i                  ( wb_reg_dest_sel                  ),

// REGISTER WRITE DATA FROM ALU
    .ex_alu_reg_dest_wr_i               ( ex_alu_reg_dest_wr               ),
    .ex_alu_reg_dest_wdata_i            ( ex_alu_reg_dest_wdata            ),

// REGISTER WRITE DATA FROM LOAD-STORE UNIT
    .wb_load_reg_dest_wr_i              ( wb_load_reg_dest_wr              ),
    .wb_load_reg_dest_wdata_i           ( wb_load_reg_dest_wdata           ),

// REGISTER WRITE DATA FROM CSR REGISTERS
    .ex_csr_reg_dest_wr_i               ( ex_csr_reg_dest_wr               ),
    .ex_csr_reg_dest_wdata_i            ( ex_csr_reg_dest_wdata            ),

// UOP WRITE CONTROLS
    .ex_uop_a0_zero_en_i                ( ex_uop_a0_zero_en                ),
    .ex_uop_mv_dest_ctrl_i              ( ex_uop_mv_dest_ctrl              ),
    .ex_uop_mv_dest1_i                  ( ex_uop_control[4:0]              ),

// TRAP WRITE-BACK SUPPRESSION
    .trap_kill_ex_i                     ( trap_kill_ex                     ),

// REGISTER READ DURING DECODE PHASE (FOR ALU & BRANCHES)
    .id_reg_src1_sel_i                  ( id_reg_src1_sel                  ),
    .id_reg_src2_sel_i                  ( id_reg_src2_sel                  ),
    .id_branch_rs1_fast_sel_i           ( id_branch_rs1_fast_sel           ),
    .id_branch_rs2_fast_sel_i           ( id_branch_rs2_fast_sel           ),
    .id_reg_src1_rdata_w_fwd_o          ( id_reg_src1_rdata_w_fwd          ),
    .id_reg_src2_rdata_w_fwd_o          ( id_reg_src2_rdata_w_fwd          ),
    .id_branch_rs1_rdata_w_fwd_o        ( id_branch_rs1_rdata_w_fwd        ),
    .id_branch_rs2_rdata_w_fwd_o        ( id_branch_rs2_rdata_w_fwd        ),

// REGISTER READ DURING EXECUTION PHASE (FOR LOAD-STORE AND UOP SEQUENCER)
    .ex_uop_src1_sel_i                  ( ex_uop_src1_sel                  ),
    .id_uop_src1_sel_i                  ( id_uop_src1_sel                  ),
    .ex_uop_src2_sel_i                  ( ex_uop_src2_sel                  ),
    .ex_reg_src1_sel_i                  ( ex_reg_src1_sel                  ),
    .ex_reg_src2_sel_i                  ( ex_reg_src2_sel                  ),
    .ex_reg_src1_rdata_wo_fwd_o         ( ex_reg_src1_rdata_wo_fwd         ),
    .ex_reg_src2_rdata_wo_fwd_o         ( ex_reg_src2_rdata_wo_fwd         ),

// JALR SHADOW REGISTER
    .id_opcode_jalr_i                   ( id_opcode_jalr                   ),
    .ex_uop_ret_branch_i                ( ex_uop_ret_branch                ),
    .id_jalr_shadow_rdata_o             ( id_jalr_shadow_rdata             ),
    .id_jalr_shadow_sel_o               ( id_jalr_shadow_sel               ),

// EX DESTINATION REGISTER (MUX OF DECODER AND UOP OVERRIDE, FOR WAW DETECTION)
    .ex_reg_dest_sel_mux_o              ( ex_reg_dest_sel_mux              ),

// DEBUG-MODULE GPR SIDE-PORT
    .dm_gpr_wen_i                       ( dm_gpr_wen                       ),
    .dm_gpr_waddr_i                     ( dm_gpr_waddr                     ),
    .dm_gpr_wdata_i                     ( dm_gpr_wdata                     ),
    .dm_gpr_raddr_i                     ( dm_gpr_raddr                     ),
    .dm_gpr_ren_i                       ( dm_gpr_ren                       ),
    .dm_gpr_rdata_o                     ( dm_gpr_rdata                     )

);

//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                  CSR REGISTERS                                                       //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

arv_csr_top #(.ARST_EN(ASYNC_RST_EN_PROC       ),
              .B_EXT_EN            (B_EXT_EN                ),
              .C_EXT_EN            (C_EXT_EN                ),
              .ZCMT_EN             (ZCMT_EN                 ),
              .M_EXT_EN            (M_EXT_EN                ),
              .MUL_1C_EN           (MUL_1C_EN               ),
              .MUL_4C_EN           (MUL_4C_EN               ),
              .MUL_16C_EN          (MUL_16C_EN              ),
              .DIV_12C_EN          (DIV_12C_EN              ),
              .DIV_17C_EN          (DIV_17C_EN              ),
              .DIV_33C_EN          (DIV_33C_EN              ),
              .CCSR_EN             (CCSR_EN_PROC            ),
              .RV32I_EN            (RV32I_EN                ),
              .SU_MODE_EN          (SU_MODE_EN_PROC         ),
              .DEBUG_EN            (DEBUG_EN_PROC           ),
              .DM_TRIGGER_EN       (DM_TRIGGER_EN           ),
              .DM_TRIGGER_NR       (DM_TRIGGER_NR_PROC      ),
              .ZICNTR_EN           (ZICNTR_EN_PROC          ),
              .ZIHPM_NR            (ZIHPM_NR_PROC           ),
              .SINGLE_CYCLE_BRANCH (SINGLE_CYCLE_BRANCH_PROC),
              .RTL_VERSION         (RTL_VERSION             ),
              .C_EXT_LEVEL         (C_EXT_LEVEL_PROC        ),
              .B_EXT_LEVEL         (B_EXT_LEVEL_PROC        ),
              .PMP_NR              (PMP_NR_PROC             )) arv_csr_top_inst (

// AHB CLOCK & RESET
    .hclk_i                             ( hclk_i                           ),
    .hresetn_i                          ( hresetn_i                        ),

// INTERFACE FOR THE CSR INSTRUCTIONS
    .ex_dec_csr_control_i               ( ex_csr_control                   ),
    .ex_dec_csr_rs1_operand_i           ( ex_operand1                      ),
    .ex_dec_csr_reg_addr_i              ( ex_operand2[11:0]                ),

// REGISTER WRITE DATA TO INTEGER REGISTERS
    .ex_csr_reg_dest_wr_o               ( ex_csr_reg_dest_wr               ),
    .ex_csr_reg_dest_wdata_o            ( ex_csr_reg_dest_wdata            ),

// INTERFACE TO CUSTOM CSR REGISTERS
    .ccsr_rdata_i                       ( ccsr_rdata_i                     ),
    .ccsr_bank_o                        ( ccsr_bank_o                      ),
    .ccsr_reg_sel_o                     ( ccsr_reg_sel_o                   ),
    .ccsr_wdata_o                       ( ccsr_wdata_o                     ),
    .ccsr_wen_o                         ( ccsr_wen_o                       ),

// INTERFACE TO INSTRUCTION FETCH AND INST DECODER
    .id_opcode_mret_i                   ( id_opcode_mret                   ),
    .id_opcode_sret_i                   ( id_opcode_sret                   ),
    .id_opcode_mnret_i                  ( id_opcode_mnret                  ),
    .ex_csr_ready_o                     ( ex_csr_ready                     ),
    .cfg_timeout_wait_o                 ( cfg_timeout_wait                 ),
    .cfg_trap_sret_o                    ( cfg_trap_sret                    ),

// TRAP INTERFACE TO DECODE
    .trap_stall_o                       ( trap_stall                       ),
    .ex_excp_squash_o                   ( ex_excp_squash                   ),
    .trap_branch_detect_o               ( trap_branch_detect               ),
    .trap_branch_target_o               ( trap_branch_target               ),
    .wfi_wakeup_o                       ( wfi_wakeup                       ),
    .wfi_wakeup_live_o                  ( wfi_wakeup_live                  ),
    .id_wfi_active_i                    ( id_wfi_active                    ),

// EXTERNAL INTERRUPT INPUTS
    .irq_m_software_i                   ( irq_m_software_i                 ),
    .irq_s_software_i                   ( irq_s_software_i                 ),
    .irq_m_timer_i                      ( irq_m_timer_i                    ),
    .irq_m_external_i                   ( irq_m_external_i                 ),
    .irq_s_external_i                   ( irq_s_external_i                 ),
    .irq_platform_i                     ( irq_platform_i                   ),

// EXCEPTIONS (SYNCHRONOUS TRAPS)
    .if_excp_inst_address_misaligned_i  ( if_excp_inst_address_misaligned  ),
    .id_excp_inst_access_fault_i        ( id_excp_inst_access_fault        ),
    .id_inst_fault_addr_i               ( id_inst_fault_addr               ),
    .id_excp_illegal_inst_i             ( id_excp_illegal_inst             ),
    .id_excp_ebreak_i                   ( id_excp_ebreak                   ),
    .id_excp_ebreak_nodbg_i             ( id_excp_ebreak_nodbg             ),
    .id_issue_active_nodbg_i            ( id_issue_active_nodbg            ),
    .id_excp_ecall_i                    ( id_excp_ecall                    ),
    .ex_excp_load_address_misaligned_i  ( ex_excp_load_address_misaligned  ),
    .ex_excp_load_access_fault_i        ( ex_excp_load_access_fault        ),
    .ex_excp_store_access_fault_i       ( ex_excp_store_access_fault       ),
    .pmp_cfg_o                          ( pmp_cfg                          ),
    .pmp_addr_o                         ( pmp_addr                         ),
    .pmp_mml_o                          ( pmp_mml                          ),
    .pmp_mmwp_o                         ( pmp_mmwp                         ),
    .ex_excp_store_address_misaligned_i ( ex_excp_store_address_misaligned ),
    .wb_bus_error_load_i                ( wb_bus_error_load                ),
    .wb_bus_error_store_i               ( wb_bus_error_store               ),

// PIPELINE READY SIGNALS (FOR DRAIN DETECTION)
    .ex_alu_ready_i                     ( ex_alu_ready                     ),
    .ex_ldst_ready_i                    ( ex_ldst_ready                    ),
    .ex_ldst_unresolved_i               ( ex_ldst_unresolved               ),
    .ex_pmp_refetch_i                   ( ex_pmp_refetch                   ),
    .ex_uop_has_branch_i                ( ex_uop_has_branch                ),
    .ex_uop_ready_i                     ( ex_uop_ready                     ),
    .ex_uop_take_branch_i               ( ex_uop_take_branch               ),
    .id_instruction_valid_i             ( id_instruction_valid             ),
    .wb_ldst_ready_i                    ( wb_ldst_ready                    ),

// PIPELINE MONITORING & CONTROL IN CASE OF TRAP
    .if_stop_cmd_o                      ( if_stop_cmd                      ),
    .lockup_o                           ( lockup_o                         ),

// PC PIPELINE INPUTS (FOR MEPC SAVE)
    .id_pc_i                            ( id_pc                            ),
    .ex_pc_i                            ( ex_pc                            ),
    .wb_pc_i                            ( wb_pc                            ),

// DATA ADDRESS PIPELINE (FOR MTVAL SAVE)
    .ex_data_addr_i                     ( data_haddr                       ),
    .wb_data_addr_i                     ( wb_data_addr                     ),
    .wb_uop_sourced_i                   ( wb_uop_sourced                   ),

// SDTRIG LOAD/STORE DATA-ADDRESS WATCHPOINT TAPS
    .ex_is_load_i                       ( ex_is_load                       ),
    .ex_is_store_i                      ( ex_is_store                      ),
    .ex_size_i                          ( lsu_hsize                        ),
    .trig_ls_fire_o                     ( trig_ls_fire                     ),

// WRITE-BACK SUPPRESSION
    .trap_kill_ex_o                     ( trap_kill_ex                     ),

// IRQ KILL FOR MULTI-CYCLE OPERATIONS
    .ex_alu_is_killable_i               ( ex_alu_is_killable               ),
    .ex_uop_is_killable_i               ( ex_uop_is_killable               ),
    .ex_uop_kill_window_i               ( ex_uop_kill_window               ),
    .ex_uop_jt_active_i                 ( ex_uop_jt_active                 ),
    .wb_uop_seq_alive_i                 ( wb_uop_seq_alive                 ),
    .wb_uop_jt_sourced_i                ( wb_uop_jt_sourced                ),
    .id_uop_jt_start_i                  ( id_uop_jt_start                  ),
    .trap_kill_muldiv_o                 ( trap_kill_muldiv                 ),
    .trap_kill_uop_o                    ( trap_kill_uop                    ),
    .trap_kill_uop_hold_o               ( trap_kill_uop_hold               ),
    .ex_uop_excp_abort_o                ( ex_uop_excp_abort                ),
    .ex_uop_jt_fault_o                  ( ex_uop_jt_fault                  ),

// OTHERS
    .hartid_i                           ( hartid_i                         ),
    .init_pc_i                          ( init_pc                          ),
    .reset_vector_i                     ( reset_vector_i                   ),
    .if_priv_mode_o                     ( if_priv_mode                     ),
    .priv_mode_ldst_o                   ( priv_mode_ldst                   ),

// JVT CSR OUTPUT (ZCMT)
    .jvt_base_o                         ( jvt_base                         ),

// NMI (SMRNMI)
    .nmi_i                              ( nmi_i                            ),
// ZICNTR TIME INTERFACE
    .time_req_o                         ( time_req_o                       ),
    .time_gnt_i                         ( time_gnt_i                       ),
    .time_val_i                         ( time_val_i                       ),

// INSTRUCTION RETIRE (FOR MINSTRET)
    .inst_retired_i                     ( id_inst_retired                  ),

// HPM EVENTS
    .id_hpm_events_i                    ( id_hpm_events                    ),
    .hpm_platform_events_i              ( hpm_platform_events_i            ),

// EXTERNAL DEBUG (Sdext)
    .debug_req_i                        ( dm_haltreq                       ),
    .resume_req_i                       ( dm_resumereq                     ),
    .resethaltreq_i                     ( dm_resethaltreq                  ),
    .dm_csr_access_i                    ( dm_csr_access                    ),
    .dm_csr_sel_i                       ( dm_csr_sel                       ),
    .dm_csr_wen_i                       ( dm_csr_wen                       ),
    .dm_csr_wdata_i                     ( dm_csr_wdata                     ),
    .dm_csr_rdata_o                     ( dm_csr_rdata                     ),
    .dm_acsr_active_i                   ( dm_acsr_active                   ),
    .dm_acsr_wen_i                      ( dm_acsr_wen                      ),
    .dm_acsr_addr_i                     ( dm_acsr_addr                     ),
    .dm_acsr_wdata_i                    ( dm_acsr_wdata                    ),
    .dm_acsr_rdata_o                    ( dm_acsr_rdata                    ),
    .dm_acsr_fault_o                    ( dm_acsr_fault                    ),
    .debug_mode_o                       ( dbg_debug_mode_o                 ),
    .debug_halt_active_o                ( debug_halt_active                ),
    .debug_issue_hold_o                 ( debug_issue_hold                 ),
    .debug_ebreak_cfg_o                 ( debug_ebreak_cfg                 ),
    .trig_break_issue_kill_o            ( trig_break_issue_kill            ),
    .debug_halted_o                     ( dbg_halted_o                     ),
    .debug_stoptime_o                   ( dbg_stoptime_o                   )

);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                          DEBUG MODULE (DM) - DEBUG_EN only                                           //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
generate
if (DEBUG_EN_PROC) begin : g_debug_dm
    arv_debug_dm #(.ARST_EN   (ASYNC_RST_EN_PROC),
                   .DMI_ABITS (DMI_ABITS        ),
                   .RV32I_EN  (RV32I_EN         )) u_arv_debug_dm (
        .hclk_i                         ( hclk_i                             ),
        .dbgresetn_i                    ( dbgresetn_i                        ),
        .hart_resetn_i                  ( hresetn_i                          ),
        .dmi_psel_i                     ( dmi_psel_i                         ),
        .dmi_penable_i                  ( dmi_penable_i                      ),
        .dmi_paddr_i                    ( dmi_paddr_i                        ),
        .dmi_pwrite_i                   ( dmi_pwrite_i                       ),
        .dmi_pwdata_i                   ( dmi_pwdata_i                       ),
        .dmi_pprot_i                    ( dmi_pprot_i                        ),
        .dmi_pready_o                   ( dmi_pready_o                       ),
        .dmi_prdata_o                   ( dmi_prdata_o                       ),
        .dmi_pslverr_o                  ( dmi_pslverr_o                      ),
        .dm_haltreq_o                   ( dm_haltreq                         ),
        .dm_resumereq_o                 ( dm_resumereq                       ),
        .hart_halted_i                  ( dbg_halted_o                       ),
        .hart_debug_mode_i              ( dbg_debug_mode_o                   ),
        .dm_ndmreset_o                  ( dbg_ndmreset_o                     ),
        .dm_resethaltreq_o              ( dm_resethaltreq                    ),
        .dm_gpr_wen_o                   ( dm_gpr_wen                         ),
        .dm_gpr_waddr_o                 ( dm_gpr_waddr                       ),
        .dm_gpr_wdata_o                 ( dm_gpr_wdata                       ),
        .dm_gpr_raddr_o                 ( dm_gpr_raddr                       ),
        .dm_gpr_ren_o                   ( dm_gpr_ren                         ),
        .dm_gpr_rdata_i                 ( dm_gpr_rdata                       ),
        .dm_csr_access_o                ( dm_csr_access                      ),
        .dm_csr_sel_o                   ( dm_csr_sel                         ),
        .dm_csr_wen_o                   ( dm_csr_wen                         ),
        .dm_csr_wdata_o                 ( dm_csr_wdata                       ),
        .dm_csr_rdata_i                 ( dm_csr_rdata                       ),
        .dm_acsr_active_o               ( dm_acsr_active                     ),
        .dm_acsr_addr_o                 ( dm_acsr_addr                       ),
        .dm_acsr_wen_o                  ( dm_acsr_wen                        ),
        .dm_acsr_wdata_o                ( dm_acsr_wdata                      ),
        .dm_acsr_rdata_i                ( dm_acsr_rdata                      ),
        .dm_acsr_fault_i                ( dm_acsr_fault                      ),
        .dm_sb_busy_o                   ( dm_sb_busy                         ),
        .dm_sb_req_o                    ( dm_sb_req                          ),
        .dm_sb_gnt_i                    ( dm_sb_gnt                          ),
        .dm_sb_active_o                 ( dm_sb_active                       ),
        .dm_sb_haddr_o                  ( dm_sb_haddr                        ),
        .dm_sb_htrans_o                 ( dm_sb_htrans                       ),
        .dm_sb_hwrite_o                 ( dm_sb_hwrite                       ),
        .dm_sb_hsize_o                  ( dm_sb_hsize                        ),
        .dm_sb_hburst_o                 ( dm_sb_hburst                       ),
        .dm_sb_hwdata_o                 ( dm_sb_hwdata                       ),
        .dm_sb_hrdata_i                 ( data_hrdata_i                      ),
        .dm_sb_hready_i                 ( data_hready_i                      ),
        .dm_sb_hresp_i                  ( data_hresp_i                       )
    );
end else begin : g_no_debug_dm
    // DEBUG_EN=0: no DM. Tie off the DMI (APB) bus and the hart requests -> bit-identical core.
    // PREADY ties HIGH so a misintegrated APB master gets an immediate zero response instead of a bus hang.
    assign      dmi_pready_o        =  1'b1;
    assign      dmi_prdata_o        = 32'h00000000;
    assign      dmi_pslverr_o       =  1'b0;
    assign      dbg_ndmreset_o      =  1'b0;
    assign      dm_haltreq          =  1'b0;
    assign      dm_resumereq        =  1'b0;
    assign      dm_resethaltreq     =  1'b0;
    assign      dm_gpr_wen          =  1'b0;
    assign      dm_gpr_waddr        =  5'h00;
    assign      dm_gpr_wdata        = 32'h00000000;
    assign      dm_gpr_raddr        =  5'h00;
    assign      dm_gpr_ren          =  1'b0;
    assign      dm_csr_access       =  1'b0;
    assign      dm_csr_sel          =  2'b00;
    assign      dm_csr_wen          =  1'b0;
    assign      dm_csr_wdata        = 32'h00000000;
    assign      dm_acsr_active      =  1'b0;
    assign      dm_acsr_addr        = 12'h000;
    assign      dm_acsr_wen         =  1'b0;
    assign      dm_acsr_wdata       = 32'h00000000;
    assign      dm_sb_busy          =  1'b0;
    assign      dm_sb_req           =  1'b0;
    assign      dm_sb_active        =  1'b0;
    assign      dm_sb_haddr         = 32'h00000000;
    assign      dm_sb_htrans        =  2'b00;
    assign      dm_sb_hwrite        =  1'b0;
    assign      dm_sb_hsize         =  3'b000;
    assign      dm_sb_hburst        =  3'b000;
    assign      dm_sb_hwdata        = 32'h00000000;

    // LINT cleanup: unused signals in the no-DM case
    wire        dm_sb_busy_unused   = dm_sb_busy;
    wire        dmi_psel_unused     = dmi_psel_i;
    wire        dmi_penable_unused  = dmi_penable_i;
    wire  [8:0] dmi_paddr_unused    = dmi_paddr_i;
    wire        dmi_pwrite_unused   = dmi_pwrite_i;
    wire [31:0] dmi_pwdata_unused   = dmi_pwdata_i;
    wire  [2:0] dmi_pprot_unused    = dmi_pprot_i;
    wire        dbgresetn_unused    = dbgresetn_i;
    wire [31:0] dm_gpr_rdata_unused = dm_gpr_rdata;
    wire [31:0] dm_csr_rdata_unused = dm_csr_rdata;
    wire [31:0] dm_acsr_rdata_unused= dm_acsr_rdata;
    wire        dm_acsr_fault_unused= dm_acsr_fault;
    wire        dm_sb_gnt_unused    = dm_sb_gnt;
end
endgenerate


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                        ALU                                                           //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

arv_alu #(.ARST_EN(ASYNC_RST_EN_PROC),
          .MUL_EN      (MUL_EN          ),
          .DIV_EN      (DIV_EN          ),
          .ZBA_EN      (ZBA_EN          ),
          .ZBB_EN      (ZBB_EN          ),
          .ZBS_EN      (ZBS_EN          ),
          .ZBC_EN      (ZBC_EN          ),
          .ZCMP_EN     (ZCMP_EN         ),
          .MUL_1C_EN   (MUL_1C_EN       ),
          .MUL_4C_EN   (MUL_4C_EN       ),
          .MUL_16C_EN  (MUL_16C_EN      ),
          .DIV_12C_EN  (DIV_12C_EN      ),
          .DIV_17C_EN  (DIV_17C_EN      ),
          .DIV_33C_EN  (DIV_33C_EN      )) arv_alu_inst (

// AHB CLOCK & RESET
    .hclk_i                             ( hclk_i                           ),
    .hresetn_i                          ( hresetn_i                        ),

// REGISTER WRITE INTERFACE
    .ex_alu_reg_dest_wr_o               ( ex_alu_reg_dest_wr               ),
    .ex_alu_reg_dest_wdata_o            ( ex_alu_reg_dest_wdata            ),

// OPERANDS & CONTROL FROM/TO DECODER
    .ex_dec_alu_control_i               ( ex_dec_alu_control               ),
    .ex_dec_alu_mode_i                  ( ex_dec_alu_mode                  ),
    .ex_dec_alu_select_i                ( ex_dec_alu_select                ),
    .ex_operand1_i                      ( ex_operand1                      ),
    .ex_operand2_i                      ( ex_operand2                      ),
    .ex_alu_ready_o                     ( ex_alu_ready                     ),

// INTERFACE TO UOP SEQUENCER
    .ex_uop_alu_control_i               ( ex_uop_alu_control               ),
    .ex_uop_alu_mode_i                  ( ex_uop_alu_mode                  ),
    .ex_uop_alu_select_i                ( ex_uop_alu_select                ),

// IRQ KILL FOR MULTI-CYCLE MUL/DIV
    .kill_muldiv_i                      ( trap_kill_muldiv                 ),
    .ex_alu_is_killable_o               ( ex_alu_is_killable               )

);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                   LOAD/STORE UNIT                                                    //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

arv_load_store #(.ARST_EN(ASYNC_RST_EN_PROC),
                 .PMP_NR (PMP_NR_PROC      )) arv_load_store_inst (

// AHB CLOCK & RESET
    .hclk_i                             ( hclk_i                           ),
    .hresetn_i                          ( hresetn_i                        ),

// DATA AHB BUS (HREADY/HRESP are the arbitrated view: while the SBA master owns the
// port the LSU sees a wait state, which is bit-identical to a slow slave for the pipeline)
    .data_hrdata_i                      ( data_hrdata_i                    ),
    .data_hready_i                      ( lsu_hready                       ),
    .data_hresp_i                       ( lsu_hresp                        ),

    .data_haddr_o                       ( data_haddr                       ),
    .data_hburst_o                      ( lsu_hburst                       ),
    .data_hmastlock_o                   ( lsu_hmastlock                    ),
    .data_hprot_o                       ( lsu_hprot                        ),
    .data_hsize_o                       ( lsu_hsize                        ),
    .data_hsmode_o                      ( lsu_hsmode                       ),
    .data_htrans_o                      ( data_htrans                      ),
    .data_hwdata_o                      ( lsu_hwdata                       ),
    .data_hwrite_o                      ( lsu_hwrite                       ),

// OPERANDS (FROM REGISTER AND DECODER)
    .ex_store_reg_wdata_i               ( ex_reg_src2_rdata_wo_fwd         ),
    .ex_store_reg_wdata_sel_i           ( ex_reg_src2_sel                  ),
    .ex_ldst_reg_addr_i                 ( ex_reg_src1_rdata_wo_fwd         ),
    .ex_ldst_reg_addr_sel_i             ( ex_reg_src1_sel                  ),
    .ex_ldst_op_immediate_i             ( ex_operand2                      ),

// REGISTER WRITE DATA
    .wb_load_busy_o                     ( wb_load_busy                     ),
    .wb_load_reg_dest_wr_o              ( wb_load_reg_dest_wr              ),
    .wb_load_reg_dest_wdata_o           ( wb_load_reg_dest_wdata           ),
    .wb_reg_dest_sel_o                  ( wb_reg_dest_sel                  ),

// INTERFACE TO DECODER
    .ex_dec_ldst_control_i              ( ex_dec_ldst_control              ),
    .priv_mode_ldst_i                   ( priv_mode_ldst                   ),
    .priv_mode_jt_i                     ( if_priv_mode                     ),
    .ex_reg_dest_sel_i                  ( ex_reg_dest_sel                  ),
    .ex_reg_dest_sel_mux_i              ( ex_reg_dest_sel_mux              ),
    .ex_ldst_ready_o                    ( ex_ldst_ready                    ),
    .ex_ldst_ready_fetch_o              ( ex_ldst_ready_fetch              ),
    .ex_ldst_unresolved_o               ( ex_ldst_unresolved               ),
    .wb_ldst_ready_o                    ( wb_ldst_ready                    ),

// INTERFACE TO UOP SEQUENCER
    .wb_dph_ongoing_o                   ( wb_dph_ongoing                   ),
    .ex_uop_enable_i                    ( ex_uop_control[9]                ),
    .ex_uop_ready_i                     ( ex_uop_ready                     ),
    .ex_uop_jt_active_i                 ( ex_uop_jt_active                 ),
    .ex_uop_ldst_control_i              ( ex_uop_ldst_control              ),
    .ex_uop_ldst_immediate_i            ( ex_uop_ldst_immediate            ),
    .ex_uop_ld_dest_sel_i               ( ex_uop_ld_dest_sel               ),
    .ex_uop_jt_base_i                   ( ex_uop_jt_base                   ),

// ERROR DETECTION
    .pmp_cfg_i                          ( pmp_cfg                          ),
    .pmp_addr_i                         ( pmp_addr                         ),
    .pmp_mml_i                          ( pmp_mml                          ),
    .pmp_mmwp_i                         ( pmp_mmwp                         ),
    .ex_excp_load_access_fault_o        ( ex_excp_load_access_fault        ),
    .ex_excp_store_access_fault_o       ( ex_excp_store_access_fault       ),
    .ex_excp_load_address_misaligned_o  ( ex_excp_load_address_misaligned  ),
    .ex_excp_store_address_misaligned_o ( ex_excp_store_address_misaligned ),
    .wb_bus_error_load_o                ( wb_bus_error_load                ),
    .wb_bus_error_store_o               ( wb_bus_error_store               ),

// SDTRIG LOAD/STORE DATA-ADDRESS WATCHPOINT
    .ex_is_load_o                       ( ex_is_load                       ),
    .ex_is_store_o                      ( ex_is_store                      ),
    .trig_ls_fire_i                     ( trig_ls_fire                     ),

// WAW HAZARD DETECTION
    .ex_alu_reg_dest_wr_i               ( ex_alu_reg_dest_wr               ),
    .ex_csr_reg_dest_wr_i               ( ex_csr_reg_dest_wr               ),

// PC PIPELINE FOR MEPC SAVE
    .ex_pc_i                            ( ex_pc                            ),
    .wb_pc_o                            ( wb_pc                            ),

// DATA ADDRESS PIPELINE FOR MTVAL SAVE
    .wb_data_addr_o                     ( wb_data_addr                     ),
    .wb_uop_sourced_o                   ( wb_uop_sourced                   ),
    .wb_uop_seq_alive_o                 ( wb_uop_seq_alive                 ),
    .wb_uop_jt_sourced_o                ( wb_uop_jt_sourced                )

);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                    CLOCK GATING  &  SBA DATA-BUS ARBITRATION                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////


// Architectural clock-gating enable for the SoC-level ICG (which sits outside the core).
// The core is safe to clock-gate only when WFI is sleeping AND both AHB masters have
// fully drained (HTRANS=IDLE with HREADY=1, i.e. no in-flight DPH).
// Wakeup is combinatorial via wfi_wakeup_live (driven from the IRQ/NMI input pins).
wire     inst_bus_quiet     = (inst_htrans   == 2'b00) & inst_hready_i;
wire     data_bus_quiet     = (data_htrans_o == 2'b00) & data_hready_i;

wire     wfi_sleep_safe_r;
wire     wfi_sleep_safe_nxt =  id_wfi_active & inst_bus_quiet & data_bus_quiet;

arv_dff #(.WIDTH(1), .ARST_EN(ASYNC_RST_EN_PROC)) u_wfi_sleep_safe (
                               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                                    .d_i (wfi_sleep_safe_nxt),
                                                                    .q_o (wfi_sleep_safe_r));

// DMI keep-alive: PSEL is held across SETUP+ACCESS until PREADY, so it spans the whole
// transaction (request + response). This ungates hclk so a DMI access can wake a WFI-sleeping hart.
wire     dmi_keepalive      =  DEBUG_EN_PROC & dmi_psel_i;

// SBA keep-alive: an accepted SBA access outlives the DMI transaction that triggered it (the debugger polls sbcs.sbbusy afterwards).
// Without this term a WFI-sleeping hart would let the SoC re-gate hclk mid-access and hang the engine.
wire     sba_keepalive      =  DEBUG_EN_PROC & dm_sb_busy;

assign   hclk_en_o          =  wfi_wakeup_live | ~wfi_sleep_safe_r | dmi_keepalive | sba_keepalive;

// Data AHB bus arbitration between the hart's LSU and the Debug Module's System Bus Access
// (SBA) master, so SBA works with the hart halted OR running.
assign   dm_sb_gnt          =  dm_sb_req    & data_hready_i & (data_htrans == 2'b00);

assign   lsu_hready         = ~dm_sb_active & data_hready_i ;
assign   lsu_hresp          = ~dm_sb_active & data_hresp_i  ;

// The SBA master accesses as machine-mode data (hsmode=0, hprot[1]=privileged), unlocked.
assign   data_haddr_o       =  dm_sb_active ? dm_sb_haddr   : data_haddr;
assign   data_htrans_o      =  dm_sb_active ? dm_sb_htrans  : data_htrans;
assign   data_hwrite_o      =  dm_sb_active ? dm_sb_hwrite  : lsu_hwrite;
assign   data_hsize_o       =  dm_sb_active ? dm_sb_hsize   : lsu_hsize;
assign   data_hburst_o      =  dm_sb_active ? dm_sb_hburst  : lsu_hburst;
assign   data_hwdata_o      =  dm_sb_active ? dm_sb_hwdata  : lsu_hwdata;
assign   data_hprot_o       =  dm_sb_active ? 4'b0011       : lsu_hprot;  // SBA HPROT is constant {non-cache, non-buf, privileged (M), data}
assign   data_hsmode_o      =  dm_sb_active ? 1'b0          : lsu_hsmode;
assign   data_hmastlock_o   =  dm_sb_active ? 1'b0          : lsu_hmastlock;
// Debug-master sideband: tag the data-bus transfer as a Debug Module SBA access
assign   data_hmaster_o     =  dm_sb_active;
// Others
assign   inst_htrans_o      =  inst_htrans;


endmodule // arvern

`default_nettype wire

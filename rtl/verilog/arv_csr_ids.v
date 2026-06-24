//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_csr_ids
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_csr_ids.v
// Module Description : RISC-V CSRs: read-only ID registers (mvendorid / marchid / mimpid / mhartid / misa)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_csr_ids (

// CONTROL CSR REGISTERs
    input  wire     [7:0] hartid_i,
    input  wire           bank_misa_en_i,
    input  wire           bank_ids_en_i,
    input  wire    [63:0] register_sel_i,
    output wire    [31:0] ids_rdata_o

);

// USER PARAMETERs
//========================================
parameter                 C_EXT_EN            =  1'b0;        // Compressed instructions enabled
parameter                 M_EXT_EN            =  1'b0;        // M extension enabled (multiply+divide)
parameter                 B_EXT_EN            =  1'b0;        // B extension enabled (bit manipulation)
parameter                 ZCA_EN              =  1'b0;        // Zca extension enable
parameter                 ZCB_EN              =  1'b0;        // Zcb extension enable
parameter                 ZCMP_EN             =  1'b0;        // Zcmp extension enable
parameter                 ZCMT_EN             =  1'b0;        // Zcmt extension enable
parameter                 ZBB_EN              =  1'b0;        // Zbb extension enable
parameter                 ZBA_EN              =  1'b0;        // Zba extension enable
parameter                 ZBS_EN              =  1'b0;        // Zbs extension enable
parameter                 MUL_1C_EN           =  1'b0;        // Single-cycle multiplier
parameter                 MUL_4C_EN           =  1'b0;        // Four-cycle multiplier
parameter                 MUL_16C_EN          =  1'b0;        // Sixteen-cycle multiplier
parameter                 DIV_12C_EN          =  1'b0;        // Radix-8 divider (12 cycles)
parameter                 DIV_17C_EN          =  1'b0;        // Radix-4 divider (17 cycles)
parameter                 DIV_33C_EN          =  1'b0;        // Radix-2 divider (33 cycles)
parameter                 CCSR_EN             =  1'b1;        // Custom-CSR available
parameter                 NMI_EN              =  1'b0;        // Smrnmi extension enable (resumable NMI)
parameter                 SU_MODE_EN          =  1'b1;        // S+U privilege modes — drives misa[18] (S) and misa[20] (U)
parameter                 RV32I_EN            =  1'b1;        // RV32I base ISA (RV32E if 0)
parameter                 ZICNTR_EN           =  1'b0;        // Zicntr extension enable (cycle, time, instret)
parameter           [3:0] ZIHPM_NR            =  4'h0;        // Zihpm: number of HPM counters (0-8)
parameter                 SINGLE_CYCLE_BRANCH =  1'b1;        // 1=zero-bubble taken branch (max IPC); 0=one-bubble (max Fmax)
parameter                 ARST_EN             =  1'b1;        // Reset architecture: 1=asynchronous, 0=synchronous (advertised in mimpid[3])
parameter          [11:0] RTL_VERSION         = 12'h000;      // RTL release version exposed through mimpid[31:20]
parameter          [31:0] MVENDORID           = 32'h00000000; // JEDEC-encoded vendor ID
parameter          [31:0] MARCHID             = 32'h00000000; // arvern architecture ID

localparam          [3:0] ZIHPM_NR_FIELD      = (ZIHPM_NR > 4'd8) ? 4'd8 : ZIHPM_NR;

//////======================================================================================================================//////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////======================================================================================================================//////

wire               [31:0] mvendorid;
wire               [31:0] marchid;
wire               [31:0] mimpid;
wire               [31:0] mhartid;
wire               [31:0] mconfigptr;
wire               [31:0] misa;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                     ID REGISTERS                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// 0xF11 mvendorid : JEDEC manufacturer ID of the chip vendor integrator
assign                    mvendorid      =  MVENDORID;

// 0xF12 marchid : architecture ID of the core. Allocated by RISC-V International.
assign                    marchid        =  MARCHID;

assign                    mhartid        =  {24'h000000,
                                             hartid_i             // Hart instance ID
                                            };

assign                    mconfigptr     =   32'h00000000;        // Unsuported

// Compact 2-bit type encodings
wire                [1:0] mul_type_id    =  ({2{MUL_1C_EN }} & 2'd1) |  // 1 = single-cycle
                                            ({2{MUL_4C_EN }} & 2'd2) |  // 2 = four-cycle
                                            ({2{MUL_16C_EN}} & 2'd3) ;  // 3 = sixteen-cycle
wire                [1:0] div_type_id    =  ({2{DIV_12C_EN}} & 2'd1) |  // 1 = radix-8  (12 cycles)
                                            ({2{DIV_17C_EN}} & 2'd2) |  // 2 = radix-4  (17 cycles)
                                            ({2{DIV_33C_EN}} & 2'd3) ;  // 3 = radix-2  (33 cycles)

// Implementation ID of the Hart
assign                    mimpid         =  {RTL_VERSION,         // [31:20] :  RTL release version (12 bits)
                                             ZIHPM_NR_FIELD,      // [19:16] :  Zihpm HPM counter count (0-8)

                                             ZICNTR_EN,           // [15]    :  Zicntr extension enable (cycle, time, instret)
                                             SINGLE_CYCLE_BRANCH, // [14]    :  1=zero-bubble taken branch (max IPC); 0=one-bubble (max Fmax)
                                             NMI_EN,              // [13]    :  Smrnmi extension enable (resumable NMI)
                                             CCSR_EN,             // [12]    :  Custom-CSR interface available

                                             div_type_id,         // [11:10] :  Divider type    (0=none, 1=12cyc, 2=17cyc, 3=33cyc)
                                             mul_type_id,         // [ 9: 8] :  Multiplier type (0=none, 1=1cyc,  2=4cyc,  3=16cyc)

                                             ZCMT_EN,             // [ 7]    :  Zcmt extension enable
                                             ZCMP_EN,             // [ 6]    :  Zcmp extension enable
                                             ZCB_EN,              // [ 5]    :  Zcb extension enable
                                             ZCA_EN,              // [ 4]    :  Zca extension enable

                                             ARST_EN,             // [ 3]    :  Reset architecture (1=asynchronous, 0=synchronous)
                                             ZBS_EN,              // [ 2]    :  Zbs extension enable
                                             ZBA_EN,              // [ 1]    :  Zba extension enable
                                             ZBB_EN               // [ 0]    :  Zbb extension enable
                                            };

// Machine ISA Register
assign                    misa           =  {         2'b01,      // [31:30] : MXL : Native base integer ISA width (1: 32; 2: 64; 3: Reserved)
                                             4'b0000,             // [29:26] :  -  : Reserved
                                             1'b0,                // [25]    :  Z  : Reserved
                                             1'b0,                // [24]    :  Y  : Reserved

                                             1'b0,                // [23]    :  X  : Non-standard extensions present
                                             1'b0,                // [22]    :  W  : Reserved
                                             1'b0,                // [21]    :  V  : Vector extension
                                                      SU_MODE_EN, // [20]    :  U  : User mode implemented

                                             1'b0,                // [19]    :  T  : Reserved
                                                      SU_MODE_EN, // [18]    :  S  : Supervisor mode implemented
                                             1'b0,                // [17]    :  R  : Reserved
                                             1'b0,                // [16]    :  Q  : Quad-precisin floating point extension

                                             1'b0,                // [15]    :  P  : Tentatively reserved for Packed-SIMD extension
                                             1'b0,                // [14]    :  O  : Reserved
                                             1'b0,                // [13]    :  N  : Tentatively reserved for User-Level Interrupts extension
                                             M_EXT_EN,            // [12]    :  M  : Integer Multiply/Divide extension

                                             1'b0,                // [11]    :  L  : Reserved
                                             1'b0,                // [10]    :  K  : Reserved
                                             1'b0,                // [ 9]    :  J  : Reserved
                                             RV32I_EN,            // [ 8]    :  I  : RV32I/64I base ISA

                                             1'b0,                // [ 7]    :  H  : Hypervisor extension
                                             1'b0,                // [ 6]    :  G  : Reserved
                                             1'b0,                // [ 5]    :  F  : Single-precision floating-point extension
                                            ~RV32I_EN,            // [ 4]    :  E  : RV32E/64E base ISA

                                             1'b0,                // [ 3]    :  D  : Double-precision floating-point extension
                                             C_EXT_EN,            // [ 2]    :  C  : C Compressed extension (Zca/Zcb/Zcmp)
                                             B_EXT_EN,            // [ 1]    :  B  : B extension (bit manipulation)
                                             1'b0                 // [ 0]    :  A  : Atomic extension
                                            };


assign                    ids_rdata_o    =  (mvendorid  & {32{bank_ids_en_i  & register_sel_i['h11]}}) |  // 0xF11
                                            (marchid    & {32{bank_ids_en_i  & register_sel_i['h12]}}) |  // 0xF12
                                            (mimpid     & {32{bank_ids_en_i  & register_sel_i['h13]}}) |  // 0xF13
                                            (mhartid    & {32{bank_ids_en_i  & register_sel_i['h14]}}) |  // 0xF14
                                            (mconfigptr & {32{bank_ids_en_i  & register_sel_i['h15]}}) |  // 0xF15
                                            (misa       & {32{bank_misa_en_i & register_sel_i['h1 ]}}) ;  // 0x301


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                   LINT CLEANUP                                                       //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

wire [63:22] register_sel_63_22_unused = register_sel_i[63:22];
wire [16: 2] register_sel_16__2_unused = register_sel_i[16: 2];
wire         register_sel_0_unused     = register_sel_i[0];


endmodule // arv_csr_ids

`default_nettype wire

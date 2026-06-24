//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_alu
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_alu.v
// Module Description : RISC-V ALU (integer + optional B-extension bit manipulation)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_alu (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// REGISTER WRITE INTERFACE
    output wire           ex_alu_reg_dest_wr_o,
    output wire    [31:0] ex_alu_reg_dest_wdata_o,

// OPERANDS & CONTROL FROM/TO DECODER
    input  wire    [16:0] ex_dec_alu_control_i,
    input  wire     [4:0] ex_dec_alu_mode_i,
    input  wire           ex_dec_alu_select_i,
    input  wire    [31:0] ex_operand1_i,
    input  wire    [31:0] ex_operand2_i,
    output wire           ex_alu_ready_o,

// INTERFACE TO UOP SEQUENCER
    input  wire    [16:0] ex_uop_alu_control_i,
    input  wire     [4:0] ex_uop_alu_mode_i,
    input  wire           ex_uop_alu_select_i,

// IRQ KILL FOR MULTI-CYCLE MUL/DIV
    input  wire           kill_muldiv_i,
    output wire           ex_alu_is_killable_o

);

// USER PARAMETERs
//========================================
parameter                 ARST_EN        = 1;  // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 MUL_EN         = 0;  // Multiply enabled (Zmmul or M)
parameter                 DIV_EN         = 0;  // Divide enabled (M extension only)
parameter                 ZBB_EN         = 0;  // Zbb extension enable (basic bit manipulation)
parameter                 ZBA_EN         = 0;  // Zba extension enable (address generation)
parameter                 ZBS_EN         = 0;  // Zbs extension enable (single-bit operations)
parameter                 ZBC_EN         = 0;  // Zbc extension enable (carry-less multiplication)
parameter                 ZCB_EN         = 0;  // Zcb extension enable (code-size reduction)
parameter                 ZCMP_EN        = 0;  // Zcmp extension enable (compressed compare instructions)
parameter                 MUL_1C_EN      = 0;  // Single-cycle multiplier
parameter                 MUL_4C_EN      = 0;  // Four-cycle multiplier
parameter                 MUL_16C_EN     = 0;  // Sixteen-cycle multiplier
parameter                 DIV_12C_EN     = 0;  // Radix-8 divider (12 cycles)
parameter                 DIV_17C_EN     = 0;  // Radix-4 divider (17 cycles)
parameter                 DIV_33C_EN     = 0;  // Radix-2 divider (33 cycles)


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// ALU modes of operation
wire                      std_mode_en;
wire                      muldiv_mode_en;
wire                      zbb_mode_en;
wire                      zba_zbs_mode_en;
wire                      zbc_mode_en;
wire               [31:0] std_operand1;
wire               [31:0] std_operand2;
wire               [16:0] ex_alu_control;
wire                [4:0] ex_alu_mode;
wire                      ex_alu_select;

// Used by shared adder
wire                      op2_is_2scomp;
wire               [32:0] operand2_signed;
wire               [32:0] shared_adder;
wire               [31:0] result_add_sub;
wire               [31:0] result_slt;
wire               [31:0] result_sltu;

// Used by barrel shifters
wire                [4:0] shift_amount;
wire               [31:0] sra_signmask;
wire               [31:0] sra_signfill;
wire                      sra_enable;
wire               [31:0] result_sll;
wire               [31:0] result_srl;
wire               [31:0] result_srl_sra;

// Used by logical operations
wire               [31:0] result_mv;
wire               [31:0] result_and;
wire               [31:0] result_or;
wire               [31:0] result_xor;

// Used by ZBB operations
wire               [31:0] result_andn;
wire               [31:0] result_orn ;
wire               [31:0] result_xnor;
wire               [31:0] result_min;
wire               [31:0] result_max;
wire               [31:0] result_minu;
wire               [31:0] result_maxu;
wire               [31:0] result_rol;
wire               [31:0] result_ror;
wire               [31:0] result_clz;
wire               [31:0] result_ctz;
wire               [31:0] result_cpop;
wire               [31:0] result_zext_h;
wire               [31:0] result_rev8;
wire               [31:0] result_orc_b;
wire               [31:0] result_sext_b;
wire               [31:0] result_sext_h;

// Used by ZBA operations
wire               [31:0] result_sh1add;
wire               [31:0] result_sh2add;
wire               [31:0] result_sh3add;

// Used by ZBS operations
wire               [31:0] result_bset;
wire               [31:0] result_bclr;
wire               [31:0] result_binv;
wire               [31:0] result_bext;

// Used by ZBC operations
wire               [63:0] result_clmul_full;
wire               [31:0] result_clmul;
wire               [31:0] result_clmulh;
wire               [31:0] result_clmulr;

// Final result
wire                      muldiv_done;
wire               [31:0] result_std;
wire               [31:0] result_zbb;
wire               [31:0] result_zba;
wire               [31:0] result_zbs;
wire               [31:0] result_zbc;
wire               [31:0] result_muldiv;
wire               [31:0] result;
wire                      ex_alu_ready_int;
wire                      ex_alu_reg_dest_wr_int;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                              ALU OPERATING MODES                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Combine control signals from Decoder stage and from UOP sequencer
assign ex_alu_control  = ex_uop_alu_control_i | ex_dec_alu_control_i;
assign ex_alu_mode     = ex_uop_alu_mode_i    | ex_dec_alu_mode_i;
assign ex_alu_select   = ex_uop_alu_select_i  | ex_dec_alu_select_i;

// ALU operating modes
assign std_mode_en     = ex_alu_mode[0];                           // Standard mode
assign muldiv_mode_en  = ex_alu_mode[1] & (MUL_EN[0] | DIV_EN[0]); // Multiplication/Division mode
assign zbb_mode_en     = ex_alu_mode[2] & (ZBB_EN[0] | ZCB_EN[0]); // Zbb mode (including ZCB for C.SEXT.B, C.SEXT.H, C.ZEXT.H)
assign zba_zbs_mode_en = ex_alu_mode[3] & (ZBA_EN[0] | ZBS_EN[0]); // Zba + Zbs modes
assign zbc_mode_en     = ex_alu_mode[4] & (ZBC_EN[0]);             // Zbc mode (carry-less multiplication)



//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                             STANDARD ALU OPERATIONS                                                  //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Mask operands to save some power
assign std_operand1    = (ex_operand1_i & {32{std_mode_en | zbb_mode_en | zba_zbs_mode_en | zbc_mode_en}});  // Zbb, Zba, Zbs and Zbc also need operands
assign std_operand2    = (ex_operand2_i & {32{std_mode_en | zbb_mode_en | zba_zbs_mode_en | zbc_mode_en}});

//-----------------------------------------------------------
// 1. SHARED ADDER (ADD, SUB, SLT, SLTU)
//-----------------------------------------------------------

// Convert to 2's complement if SUB, SLT or SLTU (std mode) or MIN/MAX operations (Zbb mode).
// MIN/MAX/MINU/MAXU at lines below reuse result_slt/result_sltu, which only carry valid
// sign information when ex_alu_select=1 forces the 2's-complement subtract here.
assign op2_is_2scomp   = (ex_alu_select & (std_mode_en | zbb_mode_en));

// Build the 2's complement if the substraction is enabled
assign operand2_signed = {1'b0, ({32{op2_is_2scomp}} ^ std_operand2)} + {{32{1'b0}}, op2_is_2scomp};

// Shared adder
assign shared_adder    = {1'b0, std_operand1} + operand2_signed;

// Build the results
assign result_add_sub  = shared_adder[31:0];
assign result_slt      = {31'b0, (std_operand1[31] ^ std_operand2[31]) ? std_operand1[31] : shared_adder[31]};
assign result_sltu     = {31'b0, ~shared_adder[32] & (std_mode_en | zbb_mode_en)};  // Also needed for MAXU/MINU

//-----------------------------------------------------------
// 2. SHIFTS (SLL, SRL, SRA)
//-----------------------------------------------------------

assign shift_amount    =   std_operand2[4:0];

// Shifts base
assign result_sll      =  (std_operand1 << shift_amount);
assign result_srl      =  (std_operand1 >> shift_amount);

// Add missing sign extension mask for arithmetic shift
assign sra_signmask    = ~(32'hFFFFFFFF >> shift_amount);
assign sra_signfill    =  ({32{std_operand1[31]}} & sra_signmask);

// Final arithmetic right shift result
assign sra_enable      =   ex_alu_select;
assign result_srl_sra  = ((sra_signfill & {32{sra_enable}}) | result_srl);

//-----------------------------------------------------------
// 3. LOGIC (AND, OR, XOR)
//-----------------------------------------------------------

assign result_and      = (std_operand1 & std_operand2);
assign result_or       = (std_operand1 | std_operand2);
assign result_xor      = (std_operand1 ^ std_operand2);

//-----------------------------------------------------------
// 4. PASS-THROUGH (CM.MV* FROM UOP)
//-----------------------------------------------------------

assign result_mv       = ex_alu_select ? std_operand2 : std_operand1;

//-----------------------------------------------------------
// 5. RESULT STANDARD INSTRUCTIONS
//-----------------------------------------------------------

assign result_std      = ({32{ex_alu_control[0] & std_mode_en }} & result_add_sub) |  // ADD[I] / SUB
                         ({32{ex_alu_control[1] & std_mode_en }} & result_sll    ) |  // SLL[I]
                         ({32{ex_alu_control[2] & std_mode_en }} & result_slt    ) |  // SLT[I]
                         ({32{ex_alu_control[3] & std_mode_en }} & result_sltu   ) |  // SLT[I]U
                         ({32{ex_alu_control[4] & std_mode_en }} & result_xor    ) |  // XOR[I]
                         ({32{ex_alu_control[5] & std_mode_en }} & result_srl_sra) |  // SRL[I] / SRA[I]
                         ({32{ex_alu_control[6] & std_mode_en }} & result_or     ) |  // OR[I]
                         ({32{ex_alu_control[7] & std_mode_en }} & result_and    ) |  // AND[I]
            ({32{ZCMP_EN[0] & ex_alu_control[8] & std_mode_en }} & result_mv     ) ;  // CM.MV*


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                ZBB ALU OPERATIONS                                                    //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//-----------------------------------------------------------
// 1. LOGICAL OPERATIONS WITH NOT (ANDN, ORN, XNOR)
//-----------------------------------------------------------

assign result_andn     =   std_operand1 & ~std_operand2;
assign result_orn      =   std_operand1 | ~std_operand2;
assign result_xnor     =  ~result_xor;

//-----------------------------------------------------------
// 2. MIN/MAX OPERATIONS (MIN, MINU, MAX, MAXU)
//-----------------------------------------------------------
// Reuse SLT/SLTU comparison results

assign result_min      = result_slt[0]  ? std_operand1 : std_operand2;
assign result_max      = result_slt[0]  ? std_operand2 : std_operand1;
assign result_minu     = result_sltu[0] ? std_operand1 : std_operand2;
assign result_maxu     = result_sltu[0] ? std_operand2 : std_operand1;

//-----------------------------------------------------------
// 3. ROTATE OPERATIONS (ROL, ROR)
//-----------------------------------------------------------
// Reuse reuse SLL/SRL results

assign result_rol      = result_sll | (std_operand1 >> (32 - shift_amount));
assign result_ror      = result_srl | (std_operand1 << (32 - shift_amount));

//-----------------------------------------------------------
// 4. COUNT OPERATIONS (CLZ, CTZ, CPOP)
//-----------------------------------------------------------

function automatic [5:0] count_leading_zeros;
  input [31:0] value;
  integer      i;
  reg [5:0]    cnt;
  reg          found;
  begin
    count_leading_zeros = 6'd32;
    cnt   = 6'd32;
    found = 1'b0;
    for (i = 31; i >= 0; i = i - 1) begin
      cnt = cnt - 6'd1;
      if (value[i] && !found) begin
        count_leading_zeros = 6'd31 - cnt;
        found = 1'b1;
      end
    end
  end
endfunction

function automatic [5:0] count_trailing_zeros;
  input [31:0] value;
  integer      i;
  reg [5:0]    cnt;
  reg          found;
  begin
    count_trailing_zeros = 6'd32;
    cnt   = 6'd0;
    found = 1'b0;
    for (i = 0; i < 32; i = i + 1) begin
      if (value[i] && !found) begin
        count_trailing_zeros = cnt;
        found = 1'b1;
      end
      cnt = cnt + 6'd1;
    end
  end
endfunction

function automatic [5:0] count_population;
  input [31:0] value;
  integer i;
  begin
    count_population = 0;
    for (i = 0; i < 32; i = i + 1) begin
      if (value[i]) count_population = count_population + 6'd1;
    end
  end
endfunction

assign result_clz      = {26'b0, count_leading_zeros(std_operand1)};
assign result_ctz      = {26'b0, count_trailing_zeros(std_operand1)};
assign result_cpop     = {26'b0, count_population(std_operand1)};

//-----------------------------------------------------------
// 5. BYTE MANIPULATION OPERATIONS (ZEXT.H, REV8, ORC.B)
//-----------------------------------------------------------

assign result_sext_b   = {{24{std_operand1[7]}},         std_operand1[7:0]  };   // Sign-extend byte
assign result_sext_h   = {{16{std_operand1[15]}},        std_operand1[15:0] };   // Sign-extend halfword
assign result_zext_h   = {    16'b0,                     std_operand1[15:0] };   // Zero-extend halfword
assign result_rev8     = {    std_operand1[7:0],         std_operand1[15:8],
                              std_operand1[23:16],       std_operand1[31:24]};   // Reverse bytes
assign result_orc_b    = {{8{|std_operand1[31:24]}}, {8{|std_operand1[23:16]}},
                          {8{|std_operand1[15:8] }}, {8{|std_operand1[7:0]  }}}; // OR-combine bytes

//-----------------------------------------------------------
// 6. RESULT ZBB INSTRUCTIONS
//-----------------------------------------------------------

assign result_zbb      = ({32{ex_alu_control[0]  & zbb_mode_en &  ZBB_EN[0]             }} & result_andn  ) |  // ANDN
                         ({32{ex_alu_control[1]  & zbb_mode_en &  ZBB_EN[0]             }} & result_orn   ) |  // ORN
                         ({32{ex_alu_control[2]  & zbb_mode_en &  ZBB_EN[0]             }} & result_xnor  ) |  // XNOR
                         ({32{ex_alu_control[3]  & zbb_mode_en &  ZBB_EN[0]             }} & result_min   ) |  // MIN
                         ({32{ex_alu_control[4]  & zbb_mode_en &  ZBB_EN[0]             }} & result_minu  ) |  // MINU
                         ({32{ex_alu_control[5]  & zbb_mode_en &  ZBB_EN[0]             }} & result_max   ) |  // MAX
                         ({32{ex_alu_control[6]  & zbb_mode_en &  ZBB_EN[0]             }} & result_maxu  ) |  // MAXU
                         ({32{ex_alu_control[7]  & zbb_mode_en &  ZBB_EN[0]             }} & result_rol   ) |  // ROL
                         ({32{ex_alu_control[8]  & zbb_mode_en &  ZBB_EN[0]             }} & result_ror   ) |  // ROR / RORI
                         ({32{ex_alu_control[9]  & zbb_mode_en &  ZBB_EN[0]             }} & result_clz   ) |  // CLZ
                         ({32{ex_alu_control[10] & zbb_mode_en &  ZBB_EN[0]             }} & result_ctz   ) |  // CTZ
                         ({32{ex_alu_control[11] & zbb_mode_en &  ZBB_EN[0]             }} & result_cpop  ) |  // CPOP
                         ({32{ex_alu_control[12] & zbb_mode_en &  ZBB_EN[0]             }} & result_rev8  ) |  // REV8
                         ({32{ex_alu_control[13] & zbb_mode_en &  ZBB_EN[0]             }} & result_orc_b ) |  // ORC.B
                         ({32{ex_alu_control[14] & zbb_mode_en & (ZBB_EN[0] | ZCB_EN[0])}} & result_zext_h) |  // ZEXT.H
                         ({32{ex_alu_control[15] & zbb_mode_en & (ZBB_EN[0] | ZCB_EN[0])}} & result_sext_h) |  // SEXT.H
                         ({32{ex_alu_control[16] & zbb_mode_en & (ZBB_EN[0] | ZCB_EN[0])}} & result_sext_b) ;  // SEXT.B


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                ZBA ALU OPERATIONS                                                    //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//-----------------------------------------------------------
// 1. ADDRESS GENERATION OPERATIONS (SH1ADD, SH2ADD, SH3ADD)
//-----------------------------------------------------------
// These instructions are useful for array indexing and address calculation

assign result_sh1add   = std_operand2 + (std_operand1 << 1);  // rd = rs2 + (rs1 << 1)
assign result_sh2add   = std_operand2 + (std_operand1 << 2);  // rd = rs2 + (rs1 << 2)
assign result_sh3add   = std_operand2 + (std_operand1 << 3);  // rd = rs2 + (rs1 << 3)

//-----------------------------------------------------------
// 2. RESULT ZBA INSTRUCTIONS
//-----------------------------------------------------------

assign result_zba      = ({32{ex_alu_control[0] & zba_zbs_mode_en & ZBA_EN[0]}} & result_sh1add) |  // SH1ADD
                         ({32{ex_alu_control[1] & zba_zbs_mode_en & ZBA_EN[0]}} & result_sh2add) |  // SH2ADD
                         ({32{ex_alu_control[2] & zba_zbs_mode_en & ZBA_EN[0]}} & result_sh3add) ;  // SH3ADD


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                ZBS ALU OPERATIONS                                                    //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//-----------------------------------------------------------
// 1. SINGLE-BIT OPERATIONS (BSET, BCLR, BINV, BEXT)
//-----------------------------------------------------------

wire  [4:0] bit_index;
wire [31:0] bit_mask;

assign bit_index       = std_operand2[4:0];                 // Bit position (0-31)
assign bit_mask        = (32'h00000001 << bit_index);       // Create mask with single bit set

assign result_bset     = std_operand1 |  bit_mask;          // Set bit at position
assign result_bclr     = std_operand1 & ~bit_mask;          // Clear bit at position
assign result_binv     = std_operand1 ^  bit_mask;          // Invert bit at position
assign result_bext     = {31'b0, std_operand1[bit_index]};  // Extract bit at position

//-----------------------------------------------------------
// 2. RESULT ZBS INSTRUCTIONS
//-----------------------------------------------------------

assign result_zbs      = ({32{ex_alu_control[4] & zba_zbs_mode_en & ZBS_EN[0]}} & result_bset) |  // BSET / BSETI
                         ({32{ex_alu_control[5] & zba_zbs_mode_en & ZBS_EN[0]}} & result_bclr) |  // BCLR / BCLRI
                         ({32{ex_alu_control[6] & zba_zbs_mode_en & ZBS_EN[0]}} & result_binv) |  // BINV / BINVI
                         ({32{ex_alu_control[7] & zba_zbs_mode_en & ZBS_EN[0]}} & result_bext) ;  // BEXT / BEXTI

//-----------------------------------------------------------
// ZBC - CARRY-LESS MULTIPLICATION INSTRUCTIONS
//-----------------------------------------------------------

assign result_clmul_full = (std_operand2[0]  ? ({32'h00000000, std_operand1} <<  0) : 64'h0) ^
                           (std_operand2[1]  ? ({32'h00000000, std_operand1} <<  1) : 64'h0) ^
                           (std_operand2[2]  ? ({32'h00000000, std_operand1} <<  2) : 64'h0) ^
                           (std_operand2[3]  ? ({32'h00000000, std_operand1} <<  3) : 64'h0) ^
                           (std_operand2[4]  ? ({32'h00000000, std_operand1} <<  4) : 64'h0) ^
                           (std_operand2[5]  ? ({32'h00000000, std_operand1} <<  5) : 64'h0) ^
                           (std_operand2[6]  ? ({32'h00000000, std_operand1} <<  6) : 64'h0) ^
                           (std_operand2[7]  ? ({32'h00000000, std_operand1} <<  7) : 64'h0) ^
                           (std_operand2[8]  ? ({32'h00000000, std_operand1} <<  8) : 64'h0) ^
                           (std_operand2[9]  ? ({32'h00000000, std_operand1} <<  9) : 64'h0) ^
                           (std_operand2[10] ? ({32'h00000000, std_operand1} << 10) : 64'h0) ^
                           (std_operand2[11] ? ({32'h00000000, std_operand1} << 11) : 64'h0) ^
                           (std_operand2[12] ? ({32'h00000000, std_operand1} << 12) : 64'h0) ^
                           (std_operand2[13] ? ({32'h00000000, std_operand1} << 13) : 64'h0) ^
                           (std_operand2[14] ? ({32'h00000000, std_operand1} << 14) : 64'h0) ^
                           (std_operand2[15] ? ({32'h00000000, std_operand1} << 15) : 64'h0) ^
                           (std_operand2[16] ? ({32'h00000000, std_operand1} << 16) : 64'h0) ^
                           (std_operand2[17] ? ({32'h00000000, std_operand1} << 17) : 64'h0) ^
                           (std_operand2[18] ? ({32'h00000000, std_operand1} << 18) : 64'h0) ^
                           (std_operand2[19] ? ({32'h00000000, std_operand1} << 19) : 64'h0) ^
                           (std_operand2[20] ? ({32'h00000000, std_operand1} << 20) : 64'h0) ^
                           (std_operand2[21] ? ({32'h00000000, std_operand1} << 21) : 64'h0) ^
                           (std_operand2[22] ? ({32'h00000000, std_operand1} << 22) : 64'h0) ^
                           (std_operand2[23] ? ({32'h00000000, std_operand1} << 23) : 64'h0) ^
                           (std_operand2[24] ? ({32'h00000000, std_operand1} << 24) : 64'h0) ^
                           (std_operand2[25] ? ({32'h00000000, std_operand1} << 25) : 64'h0) ^
                           (std_operand2[26] ? ({32'h00000000, std_operand1} << 26) : 64'h0) ^
                           (std_operand2[27] ? ({32'h00000000, std_operand1} << 27) : 64'h0) ^
                           (std_operand2[28] ? ({32'h00000000, std_operand1} << 28) : 64'h0) ^
                           (std_operand2[29] ? ({32'h00000000, std_operand1} << 29) : 64'h0) ^
                           (std_operand2[30] ? ({32'h00000000, std_operand1} << 30) : 64'h0) ^
                           (std_operand2[31] ? ({32'h00000000, std_operand1} << 31) : 64'h0);

assign result_clmul    = result_clmul_full[31:0];
assign result_clmulh   = result_clmul_full[63:32];
assign result_clmulr   = result_clmul_full[62:31];

//-----------------------------------------------------------
// 2. RESULT ZBC INSTRUCTIONS
//-----------------------------------------------------------

assign result_zbc      = ({32{ex_alu_control[1] & zbc_mode_en & ZBC_EN[0]}} & result_clmul)  |  // CLMUL
                         ({32{ex_alu_control[3] & zbc_mode_en & ZBC_EN[0]}} & result_clmulh) |  // CLMULH
                         ({32{ex_alu_control[2] & zbc_mode_en & ZBC_EN[0]}} & result_clmulr) ;  // CLMULR


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                    32x32 MULTIPLIER:                                                                 //////
//////                                                      + 32x32 implementations,  1 cycle                               //////
//////                                                      + 16x16 implementations,  4 cycles                              //////
//////                                                      +  8x8  implementations, 16 cycles                              //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
////// - ex_alu_control[0] --> MUL   : low  32 bits of OP1_signed   * OP2_signed                                            //////
////// - ex_alu_control[1] --> MULH  : high 32 bits of OP1_signed   * OP2_signed                                            //////
////// - ex_alu_control[2] --> MULHSU: high 32 bits of OP1_signed   * OP2_unsigned                                          //////
////// - ex_alu_control[3] --> MULHU : high 32 bits of OP1_unsigned * OP2_unsigned                                          //////
//////                                                                                                                      //////
////// - ex_alu_control[4] --> DIV   : performs signed integer division of rs1 by rs2, rounding towards zero                //////
////// - ex_alu_control[5] --> DIVU  : performs unsigned integer division of rs1 by rs2, rounding towards zero              //////
////// - ex_alu_control[6] --> REM   : provides the remainder of the DIV division operation                                 //////
////// - ex_alu_control[7] --> REMU  : provides the remainder of the DIVU division operation                                //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////     Multiplier type (valid only with M-extension or Zmmul)                                                           //////
//////                                                                                                                      //////
//////                       MUL_1C_EN  = Single-cycle hardware multiplier                                                  //////
//////                       MUL_4C_EN  = Four-cycle hardware multiplier                                                    //////
//////                       MUL_16C_EN = Sixteen-cycle hardware multiplier                                                 //////
//////                                                                                                                      //////
//////----------------------------------------------------------------------------------------------------------------------//////
//////                                                                                                                      //////
//////     Divider type (valid only with M-extension)                                                                       //////
//////                                                                                                                      //////
//////                       DIV_12C_EN = Radix-8 divider (12 cycles)                                                       //////
//////                       DIV_17C_EN = Radix-4 divider (17 cycles)                                                       //////
//////                       DIV_33C_EN = Radix-2 divider (33 cycles)                                                       //////
//////                                                                                                                      //////
//////======================================================================================================================//////
generate
    if (MUL_EN) begin : WITH_MULDIV

        arv_alu_muldiv #(.ARST_EN     (ARST_EN     ),
                         .DIV_EN      (DIV_EN      ),
                         .MUL_1C_EN   (MUL_1C_EN   ),
                         .MUL_4C_EN   (MUL_4C_EN   ),
                         .MUL_16C_EN  (MUL_16C_EN  ),
                         .DIV_12C_EN  (DIV_12C_EN  ),
                         .DIV_17C_EN  (DIV_17C_EN  ),
                         .DIV_33C_EN  (DIV_33C_EN  )) arv_alu_muldiv_inst (

            .hclk_i            ( hclk_i                ),
            .hresetn_i         ( hresetn_i             ),

            .div_select_i      ( ex_alu_select         ),  // Special function bit for DIV select
            .enable_i          ( muldiv_mode_en        ),  // Enable when mode=MUL/DIV
            .ex_operand1_i     ( ex_operand1_i         ),
            .ex_operand2_i     ( ex_operand2_i         ),
            .ex_alu_control_i  ( ex_alu_control[7:0]   ),  // One-hot operation select
            .kill_i            ( kill_muldiv_i         ),  // IRQ kill for multi-cycle ops
            .is_killable_o     ( ex_alu_is_killable_o  ),

            .done_o            ( muldiv_done           ),
            .result_o          ( result_muldiv         )
        );

    end else begin : NO_MULDIV

        // Disable driving logic
        assign muldiv_done          = 1'b1;
        assign result_muldiv        = 32'h00000000;
        assign ex_alu_is_killable_o = 1'b0;

        // Unused (no muldiv unit in this configuration)
        wire   hclk_unused          = hclk_i;
        wire   hresetn_unused       = hresetn_i;
        wire   kill_muldiv_unused   = kill_muldiv_i;

    end
endgenerate


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                     STALL CONTROL AND WRITE TO THE REGBANK                                           //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// For the future (MUL or DIV instructions might need to stall)
// Mode 00=BASIC, 10=SEXT, 11=Zbb: single-cycle, ready immediately
// Mode 01=MUL/DIV: multi-cycle, wait for muldiv_done
assign   ex_alu_ready_int        =  (muldiv_mode_en & muldiv_done) |  // MUL/DIV can have wait state
                                    ~muldiv_mode_en                ;  // No wait state for all other operations

assign   ex_alu_reg_dest_wr_int  =   ex_alu_ready_o & (|ex_alu_mode) ;

// Combine the results from the different units
assign   result                  =   result_std    |
                                     result_zbb    |
                                     result_zba    |
                                     result_zbs    |
                                     result_zbc    |
                                     result_muldiv ;

// Data to be written to the register bank
assign   ex_alu_reg_dest_wdata_o = result;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                               FOR VERIFICATION, SPECIAL STALL CONTROL WITH RANDOM DELAY                              //////
//////                                                                                                                      //////
//////                  (For verification only, add an option to add dummy wait state to stress the design)                 //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
`ifdef ARV_VERIF_ALU_RANDOM_STALL
  `define ARV_VERIF_ALU_STALL
`endif
// synthesis translate_off
`ifdef ARV_VERIF_ALU_STALL
    wire      alu_start;
    integer   alu_delay;

    always @(negedge hclk_i or negedge hresetn_i)
        if (!hresetn_i)         alu_delay  <= -1;
     `ifdef ARV_VERIF_ALU_RANDOM_STALL
        else if (alu_start)     alu_delay  <= $urandom_range(0, 5+1);
     `else
        else if (alu_start)     alu_delay  <= 5;
     `endif
        else if (alu_delay!=-1) alu_delay  <= alu_delay-1;

    assign   alu_start             = (|ex_alu_mode) &  ((alu_delay==0)|(alu_delay==-1)) & ~muldiv_mode_en;
    assign   ex_alu_ready_o        = muldiv_mode_en ? ex_alu_ready_int       :
                                                      (((alu_delay==0)|(alu_delay==-1)) ? 1'b1 : ~(alu_start | ~((alu_delay==0)|(alu_delay==-1))));
    assign   ex_alu_reg_dest_wr_o  = muldiv_mode_en ? ex_alu_reg_dest_wr_int :
                                                        (alu_delay==0);

`else
// synthesis translate_on
    assign   ex_alu_ready_o        = ex_alu_ready_int;
    assign   ex_alu_reg_dest_wr_o  = ex_alu_reg_dest_wr_int;

// synthesis translate_off
`endif
// synthesis translate_on


endmodule // arv_alu

`default_nettype wire

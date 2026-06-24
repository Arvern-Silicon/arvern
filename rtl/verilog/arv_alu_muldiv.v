//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_alu_muldiv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_alu_muldiv.v
// Module Description : RISC-V ALU multiplier/divider
//                      (selectable 1/4/16-cycle MUL and 12/17/33-cycle DIV)
//----------------------------------------------------------------------------
`default_nettype none

module arv_alu_muldiv (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// OPERANDS AND CONTROL
    input  wire           div_select_i,
    input  wire           enable_i,
    input  wire    [31:0] ex_operand1_i,
    input  wire    [31:0] ex_operand2_i,
    input  wire    [7:0]  ex_alu_control_i,
    input  wire           kill_i,
    output wire           is_killable_o,

// RESULTS
    output wire           done_o,
    output wire    [31:0] result_o

);

// USER PARAMETERs
//========================================
parameter                 ARST_EN        =  1;       // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)

parameter                 DIV_EN         =  0;       // Divide enabled (M extension only)
parameter                 MUL_1C_EN      =  0;       // Single-cycle multiplier
parameter                 MUL_4C_EN      =  0;       // Four-cycle multiplier
parameter                 MUL_16C_EN     =  0;       // Sixteen-cycle multiplier

parameter                 DIV_12C_EN     =  0;       // Radix-8 divider (12 cycles)
parameter                 DIV_17C_EN     =  0;       // Radix-4 divider (17 cycles)
parameter                 DIV_33C_EN     =  0;       // Radix-2 divider (33 cycles)


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Multiplier declarations
wire                      mpy_mode_enable;
wire                      mpy_start;
wire                [5:0] mpy_counter_init;
wire               [63:0] mpy_result_full;
wire                      mpy_operand1_sign;
wire                      mpy_operand2_sign;
wire               [63:0] mpy_operand1;
wire               [63:0] mpy_operand2;
wire                      mpy_done;
wire               [63:0] mpy_acc;
wire               [63:0] mpy_acc_init;
wire               [63:0] mpy_acc_nxt;
wire               [31:0] result_mpy;

// Divider declarations
wire                      div_mode_enable;
wire                      div_start;
wire                [5:0] div_counter_init;
wire                      div_done;
wire               [34:0] div_partial_rem;
wire               [31:0] div_result_tmp;
wire               [34:0] div_partial_rem_init;
wire               [35:0] div_partial_rem_nxt;
wire               [31:0] div_result_tmp_init;
wire               [31:0] div_result_tmp_nxt;
wire               [31:0] div_result_rem_pre;
wire               [31:0] div_result_div_pre;
wire                      div_is_signed;
wire                      div_result_is_rem;
wire                      div_by_zero;
wire                      div_op1_is_neg;
wire                      div_op2_is_neg;
wire               [31:0] div_dividend;
wire               [31:0] div_divisor;
wire               [31:0] result_div;

//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                             SHARED MULTIPLIER-DIVIDER LOGIC                                          //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

wire  [5:0] shared_counter;
wire [66:0] shared_partial;
wire  [5:0] shared_counter_nxt;

generate
    //   This branch for Zmmul-only with single-cycle MUL.
    //   The shared counter / partial registers are stripped (no muldiv state machine).
    //   In this configuration, the MUL/DIV operations are not killable by exceptions.
    if (~DIV_EN && MUL_1C_EN) begin : NO_SHARED_BUF

        assign      shared_counter              = 6'h00;
        assign      shared_partial              = {67{1'b0}};
        assign      shared_counter_nxt          = 6'h00;

        wire        hclk_unused                 = hclk_i;
        wire        hresetn_unused              = hresetn_i;
        wire        mpy_start_unused            = mpy_start;
        wire  [5:0] mpy_counter_init_unused     = mpy_counter_init;
        wire [63:0] mpy_acc_init_unused         = mpy_acc_init;
        wire [63:0] mpy_acc_nxt_unused          = mpy_acc_nxt;
        wire        div_start_unused            = div_start;
        wire  [5:0] div_counter_init_unused     = div_counter_init;
        wire [34:0] div_partial_rem_init_unused = div_partial_rem_init;
        wire [34:0] div_partial_rem_nxt_unused  = div_partial_rem_nxt[34:0];
        wire [31:0] div_result_tmp_init_unused  = div_result_tmp_init;
        wire [31:0] div_result_tmp_nxt_unused   = div_result_tmp_nxt;
        wire  [2:0] shared_counter_unused       = shared_counter[2:0];
        wire  [5:0] shared_counter_nxt_unused   = shared_counter_nxt;
        wire        kill_unused                 = kill_i;
        assign      is_killable_o               = 1'b0;

    end else begin : WITH_SHARED_BUF

        // Prevent self-restart: after kill resets counter to 6'h3f, enable_i may still be high
        // for one cycle before ex_alu_mode_o flushes (decode clears it on the registered
        // trap_branch_detect, which lags trap_taken by one cycle). kill_r is the 1-cycle
        // delayed kill; it masks shared_counter_reg and shared_partial_reg for that extra
        // cycle, blocking the spurious mpy_start / div_start re-fire.
        wire        kill_r;

        arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_kill_r (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                           .d_i (kill_i),
                                                           .q_o (kill_r));

        wire        shared_disable     = !(mpy_mode_enable | div_mode_enable);

        wire  [5:0] shared_counter_reg;
        assign      shared_counter_nxt =  (shared_counter_reg - 6'd1);
        assign      shared_counter     =   shared_counter_reg;

        wire  [5:0] shared_counter_d   =  kill_i               ? 6'h3f             :
                                          kill_r               ? 6'h3f             :
                                          (mpy_done | div_done)? 6'h3f             :
                                          mpy_start            ? mpy_counter_init  :
                                          div_start            ? div_counter_init  :
                                                                 (shared_counter_nxt | {6{shared_disable}});

        arv_dff #(.WIDTH(6), .RST_VAL(6'h3f), .ARST_EN(ARST_EN)) u_shared_counter (
                                               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                                                    .d_i (shared_counter_d),
                                                                                    .q_o (shared_counter_reg));

        wire [66:0] shared_partial_reg;
        assign      shared_partial     =   shared_partial_reg;

        wire [66:0] shared_partial_d   =  kill_i      ? {67{1'b0}}                                 :
                                          kill_r      ? {67{1'b0}}                                 :
                                          mpy_start   ? {3'h0, mpy_acc_init}                       :
                                          div_start   ? {div_partial_rem_init, div_result_tmp_init}:
                                          mpy_mode_enable ? {3'h0, mpy_acc_nxt}                     :
                                                        {div_partial_rem_nxt[34:0], div_result_tmp_nxt};

        arv_dff #(.WIDTH(67), .ARST_EN(ARST_EN)) u_shared_partial (
                               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1),
                                                                    .d_i (shared_partial_d),
                                                                    .q_o (shared_partial_reg));

        // Multi-cycle op is killable when actively counting down (not idle 0x3f, not done).
        assign      is_killable_o = (mpy_mode_enable | div_mode_enable) & ~done_o & (shared_counter != 6'h3f);

    end
endgenerate


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                     MULTIPLIERS                                                      //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

//------------------------------------------------------------------------------------------------
// Common: sign extension and operand prep
//------------------------------------------------------------------------------------------------
// - ex_alu_control_i[0] --> MUL   : low  32 bits of OP1_signed   * OP2_signed
// - ex_alu_control_i[1] --> MULH  : high 32 bits of OP1_signed   * OP2_signed
// - ex_alu_control_i[2] --> MULHSU: high 32 bits of OP1_signed   * OP2_unsigned
// - ex_alu_control_i[3] --> MULHU : high 32 bits of OP1_unsigned * OP2_unsigned

assign  mpy_mode_enable   = ( enable_i & ~div_select_i);
assign  mpy_operand1_sign = (~ex_alu_control_i[3]   &  ex_operand1_i[31] & mpy_mode_enable);
assign  mpy_operand2_sign = (|ex_alu_control_i[1:0] &  ex_operand2_i[31] & mpy_mode_enable);

assign  mpy_operand1      = {{32{mpy_operand1_sign}}, (ex_operand1_i & {32{mpy_mode_enable}})};
assign  mpy_operand2      = {{32{mpy_operand2_sign}}, (ex_operand2_i & {32{mpy_mode_enable}})};

assign  mpy_acc           = shared_partial[63:0];

// No terminating `else` by design: exactly one of MUL_1C_EN/MUL_4C_EN/MUL_16C_EN
// is set when MUL is enabled, and all three are 0 when MUL is disabled. This is GUARANTEED by
// the top-level MUL_TYPE_USE clamp in the top level.
generate
    //------------------------------------------------------------------------------------------------
    // Single-cycle Multiplication
    //------------------------------------------------------------------------------------------------
    if (MUL_1C_EN) begin : MUL_SINGLE_CYCLE

        // Full 32x32 multiplier, single cycle
        assign      mpy_result_full     =  mpy_operand1 * mpy_operand2;
        assign      mpy_done            =  mpy_mode_enable;

        // Disable unused counter & accumulator
        assign      mpy_counter_init    = {2'h3, 4'hf};
        assign      mpy_start           =  1'b0;
        assign      mpy_acc_init        =  64'h0;
        assign      mpy_acc_nxt         =  64'h0;

        // Lint cleanup
        wire [63:0] mpy_acc_unused      =  mpy_acc;


    //------------------------------------------------------------------------------------------------
    // 4-cycles Multiplication
    //------------------------------------------------------------------------------------------------
    // Start     (Cycle 1): op1[15: 0] * op2[15: 0]  --> L * L  -->  11  <--  Shift  0
    // Counter 2 (Cycle 2): op1[31:16] * op2[15: 0]  --> H * L  -->  10  <--  Shift 16
    // Counter 1 (Cycle 3): op1[15: 0] * op2[31:16]  --> L * H  -->  01  <--  Shift 16
    // Counter 0 (Cycle 4): op1[31:16] * op2[31:16]  --> H * H  -->  00  <--  Shift 32
    //------------------------------------------------------------------------------------------------
    end else if (MUL_4C_EN) begin : MUL_4_CYCLES

        // Cycle counter management
        wire  [2:0] mpy_counter         =  shared_counter[2:0];
        assign      mpy_start           =  mpy_mode_enable   & (mpy_counter==3'h7);
        assign      mpy_done            =  mpy_mode_enable   & (mpy_counter==3'h0);
        assign      mpy_counter_init    = {3'h7, 3'h2};

        // Determine when the lower 16-bit half is active
        wire [32:0] op1_part            =  mpy_counter[0] ? {{17{1'b0}}, mpy_operand1[15:0]} : {{17{mpy_operand1[32]}}, mpy_operand1[31:16]};
        wire [32:0] op2_part            =  mpy_counter[1] ? {{17{1'b0}}, mpy_operand2[15:0]} : {{17{mpy_operand2[32]}}, mpy_operand2[31:16]};

        // 16×16 Partial multiplier
        wire [32:0] partial             =  op1_part * op2_part;

        // Shift the partial result to be added
        wire [15:0] signp               = {16{partial[32]}};

        wire [63:0] partial_shift__0    = /*shift__0*/ {16'h0000, 16'h0000, partial[31:0]} ;
        wire [63:0] partial_shift_16    = /*shift_16*/ {signp,    partial[31:0], 16'h0000} ;
        wire [63:0] partial_shift_32    = /*shift_32*/ {partial[31:0], 16'h0000, 16'h0000} ;

        // Accumulator management
        assign      mpy_acc_init        =  partial_shift__0;
        assign      mpy_acc_nxt         =  mpy_acc + partial_shift_16;

        // Result (duplicating the adder saves area as it shortens the timing path to the register bank)
        assign      mpy_result_full     =  mpy_acc + partial_shift_32;

        // Lint Cleanup
        wire [30:0] mpy_operand1_unused =  mpy_operand1[63:33];
        wire [30:0] mpy_operand2_unused =  mpy_operand2[63:33];


    //------------------------------------------------------------------------------------------------
    // 16-cycles Multiplication
    //------------------------------------------------------------------------------------------------
    // Start      (Cycle  1): op1[ 7: 0]  * op2[ 7: 0]  --> LL * LL  -->  1111  <-- shift  0
    // Counter 14 (Cycle  2): op1[15: 8]  * op2[ 7: 0]  --> LH * LL  -->  1110  <-- shift  8
    // Counter 13 (Cycle  3): op1[23:16]  * op2[ 7: 0]  --> HL * LL  -->  1101  <-- shift 16
    // Counter 12 (Cycle  4): op1[31:24]  * op2[ 7: 0]  --> HH * LL  -->  1100  <-- shift 24 (+sign)
    // Counter 11 (Cycle  5): op1[ 7: 0]  * op2[15: 8]  --> LL * LH  -->  1011  <-- shift  8
    // Counter 10 (Cycle  6): op1[15: 8]  * op2[15: 8]  --> LH * LH  -->  1010  <-- shift 16
    // Counter  9 (Cycle  7): op1[23:16]  * op2[15: 8]  --> HL * LH  -->  1001  <-- shift 24
    // Counter  8 (Cycle  8): op1[31:24]  * op2[15: 8]  --> HH * LH  -->  1000  <-- shift 32 (+sign)
    // Counter  7 (Cycle  9): op1[ 7: 0]  * op2[23:16]  --> LL * HL  -->  0111  <-- shift 16
    // Counter  6 (Cycle 10): op1[15: 8]  * op2[23:16]  --> LH * HL  -->  0110  <-- shift 24
    // Counter  5 (Cycle 11): op1[23:16]  * op2[23:16]  --> HL * HL  -->  0101  <-- shift 32
    // Counter  4 (Cycle 12): op1[31:24]  * op2[23:16]  --> HH * HL  -->  0100  <-- shift 40 (+sign)
    // Counter  3 (Cycle 13): op1[ 7: 0]  * op2[31:24]  --> LL * HH  -->  0011  <-- shift 24 (+sign)
    // Counter  2 (Cycle 14): op1[15: 8]  * op2[31:24]  --> LH * HH  -->  0010  <-- shift 32 (+sign)
    // Counter  1 (Cycle 15): op1[23:16]  * op2[31:24]  --> HL * HH  -->  0001  <-- shift 40 (+sign)
    // Counter  0 (Cycle 16): op1[31:24]  * op2[31:24]  --> HH * HH  -->  0000  <-- shift 48
    //------------------------------------------------------------------------------------------------
    end else if (MUL_16C_EN) begin : MUL_16_CYCLES

        // Cycle counter management
        wire  [3:0] mpy_counter         =  shared_counter[3:0];
        assign      mpy_start           =  mpy_mode_enable & (mpy_counter==4'hf);
        assign      mpy_done            =  mpy_mode_enable & (mpy_counter==4'h0);
        assign      mpy_counter_init    = {2'h3, 4'he};

        // Determine when each operand nibble is active
        wire [16:0] op2_part_long       =  mpy_counter[3] ? {1'b0, mpy_operand2[15:0]} : {mpy_operand2[32], mpy_operand2[31:16]};
        wire  [8:0] op2_part_short      =  mpy_counter[2] ? {1'b0, op2_part_long[7:0]} :  op2_part_long[16:8];

        wire [16:0] op1_part_long       =  mpy_counter[1] ? {1'b0, mpy_operand1[15:0]} : {mpy_operand1[32], mpy_operand1[31:16]};
        wire  [8:0] op1_part_short      =  mpy_counter[0] ? {1'b0, op1_part_long[7:0]} :  op1_part_long[16:8];

        wire [16:0] op2_part            = {{9{op2_part_short[8]}}, op2_part_short[7:0]};
        wire [16:0] op1_part            = {{9{op1_part_short[8]}}, op1_part_short[7:0]};

        // 8×8 Partial multiplier
        wire [16:0] partial             =  op1_part * op2_part;

        // Shift the partial result to be added
        wire        shift__8            = (mpy_counter==4'hE) | (mpy_counter==4'hB) ;
        wire        shift_16            = (mpy_counter==4'hD) | (mpy_counter==4'hA) | (mpy_counter==4'h7) ;
        wire        shift_24            = (mpy_counter==4'hC) | (mpy_counter==4'h9) | (mpy_counter==4'h6) | (mpy_counter==4'h3);
        wire        shift_32            = (mpy_counter==4'h8) | (mpy_counter==4'h5) | (mpy_counter==4'h2) ;
        wire        sel_sign            = (mpy_counter==4'hC) | (mpy_counter==4'h3) | (mpy_counter==4'h8) | (mpy_counter==4'h2);

        wire  [7:0] sign                = {8{partial[16] & sel_sign}};
        wire  [7:0] signp               = {8{partial[16]}};

        // Compute the next accumulated value
        wire [63:0] partial_shift_0     = /*shift__0*/ {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, partial[15:0]} ;
        wire [63:0] partial_shift       =   shift__8 ? {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, partial[15:0], 8'h00} :
                                            shift_16 ? {8'h00, 8'h00, 8'h00, 8'h00, partial[15:0], 8'h00, 8'h00} :
                                            shift_24 ? {sign , sign , sign , partial[15:0], 8'h00, 8'h00, 8'h00} :
                                            shift_32 ? {sign , sign , partial[15:0], 8'h00, 8'h00, 8'h00, 8'h00} :
                                          /*shift_40*/ {signp, partial[15:0], 8'h00, 8'h00, 8'h00, 8'h00, 8'h00} ;
        wire [63:0] partial_shift_48    = /*shift_48*/ {partial[15:0], 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00} ;

        // Accumulator management
        assign      mpy_acc_init        =  partial_shift_0;
        assign      mpy_acc_nxt         =  mpy_acc + partial_shift;

        // Result (duplicating the adder saves area as it shortens the timing path to the register bank)
        assign      mpy_result_full     =  mpy_acc + partial_shift_48;

        // Lint Cleanup
        wire [30:0] mpy_operand1_unused =  mpy_operand1[63:33];
        wire [30:0] mpy_operand2_unused =  mpy_operand2[63:33];

    end
endgenerate

//------------------------------------------------------------------------------------------------
// Common: result selection (MUL, MULH, MULHSU, MULHU)
//------------------------------------------------------------------------------------------------

assign  result_mpy = ({32{mpy_mode_enable & ~ex_alu_control_i[0]}} & mpy_result_full[63:32]) | // MULH, MULHSU, MULHU
                     ({32{mpy_mode_enable &  ex_alu_control_i[0]}} & mpy_result_full[31: 0]) ; // MUL


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                     DIVIDERS                                                         //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

generate
    //------------------------------------------------------------------------------------------------
    // No Hardware divider (Zmmul or none)
    //------------------------------------------------------------------------------------------------
    if (~DIV_EN) begin : NO_DIV

        assign      div_mode_enable            =  1'b0;
        assign      div_is_signed              =  1'b0;
        assign      div_result_is_rem          =  1'b0;
        assign      div_by_zero                =  1'b0;
        assign      div_op1_is_neg             =  1'b0;
        assign      div_op2_is_neg             =  1'b0;
        assign      div_start                  =  1'b0;
        assign      div_dividend               = 32'h00000000;
        assign      div_divisor                = 32'h00000000;
        assign      div_partial_rem            = 35'h000000000;
        assign      div_result_tmp             = 32'h00000000;
        assign      div_done                   = div_select_i;  // Don't block the CPU in case a DIV instruction is read

        assign      div_counter_init           =  6'h3f;
        assign      div_partial_rem_init       = 35'h000000000;
        assign      div_partial_rem_nxt        = 36'h000000000;
        assign      div_result_tmp_init        = 32'h00000000;
        assign      div_result_tmp_nxt         = 32'h00000000;
        assign      div_result_rem_pre         = 32'h00000000;
        assign      div_result_div_pre         = 32'h00000000;

        //%Warning-UNUSEDSIGNAL:
        wire [31:0] div_dividend_unused        = div_dividend;
        wire [31:0] div_divisor_unused         = div_divisor;
        wire        div_is_signed_unused       = div_is_signed;
        wire [34:0] div_partial_rem_unused     = div_partial_rem;
        wire [31:0] div_result_tmp_unused      = div_result_tmp;
        wire        div_partial_rem_nxt_unused = div_partial_rem_nxt[35];
        wire  [2:0] shared_partial_unused      = shared_partial[66:64];
        wire  [2:0] shared_counter_unused      = shared_counter[5:3];
        wire  [2:0] ex_alu_control_unused      = {ex_alu_control_i[7:6], ex_alu_control_i[4]};


    end else begin : DIV_OPERANDS
        //------------------------------------------------------------------------------------------------
        // Common: sign extension and operand prep
        //------------------------------------------------------------------------------------------------
        // - ex_alu_control_i[4] --> DIV   : performs signed integer division of rs1 by rs2, rounding towards zero
        // - ex_alu_control_i[5] --> DIVU  : performs unsigned integer division of rs1 by rs2, rounding towards zero
        // - ex_alu_control_i[6] --> REM   : provides the remainder of the DIV division operation
        // - ex_alu_control_i[7] --> REMU  : provides the remainder of the DIVU division operation

        assign      div_mode_enable    = ( enable_i & div_select_i) & DIV_EN;
        assign      div_is_signed      = (ex_alu_control_i[4] | ex_alu_control_i[6]) & div_mode_enable;
        assign      div_result_is_rem  = (ex_alu_control_i[6] | ex_alu_control_i[7]);
        assign      div_by_zero        = (ex_operand2_i==32'h00000000);

        assign      div_op1_is_neg     = (div_is_signed    & ex_operand1_i[31]);
        assign      div_op2_is_neg     = (div_is_signed    & ex_operand2_i[31]);

        assign      div_start          =  div_mode_enable  & (shared_counter==6'h3F);
        assign      div_done           =  div_mode_enable  & (shared_counter==6'h0);

        // Prepare Operands
        assign      div_dividend       = (({32{div_op1_is_neg}} ^ ex_operand1_i)+{31'h00000000, div_op1_is_neg}) & {32{div_mode_enable}};
        assign      div_divisor        = (({32{div_op2_is_neg}} ^ ex_operand2_i)+{31'h00000000, div_op2_is_neg}) & {32{div_mode_enable}};

        // Partial results
        assign      div_partial_rem    = shared_partial[66:32];
        assign      div_result_tmp     = shared_partial[31:0];
    end
endgenerate

// No terminating `else` by design): exactly one of DIV_12C_EN/DIV_17C_EN/DIV_33C_EN
// is set when DIV is enabled, all 0 when DIV is disabled. GUARANTEED by the top-level
// DIV_TYPE_USE clamp in top level.
generate
    //------------------------------------------------------------------------------------------------
    // 12-cycles Division
    //------------------------------------------------------------------------------------------------
    if (DIV_12C_EN) begin : DIV_12_CYCLES

        // Radix-8 division needs 1+12 cycles
        assign      div_counter_init            = 6'd10;

        // Build multiples of the divisor
        wire [34:0] div_divisor_x1              = {2'b00,                     1'b0, div_divisor} ; // 1×divisor
        wire [34:0] div_divisor_x2              = {2'b00,              div_divisor,        1'b0} ; // 2×divisor
        wire [34:0] div_divisor_x3              = (div_divisor_x2 + div_divisor_x1)              ; // 3×divisor
        wire [34:0] div_divisor_x4              = {1'b0,  div_divisor,        1'b0,        1'b0} ; // 4×divisor
        wire [34:0] div_divisor_x5              = (div_divisor_x4 + div_divisor_x1)              ; // 5×divisor
        wire [34:0] div_divisor_x6              = (div_divisor_x4 + div_divisor_x2)              ; // 6×divisor
        wire [34:0] div_divisor_x7              = (div_divisor_x6 + div_divisor_x1)              ; // 7×divisor

        // Candidate remainders
        wire [35:0] div_partial_rem_sub1        = ({1'b0, div_partial_rem} - {1'b0, div_divisor_x1});
        wire [35:0] div_partial_rem_sub2        = ({1'b0, div_partial_rem} - {1'b0, div_divisor_x2});
        wire [35:0] div_partial_rem_sub3        = ({1'b0, div_partial_rem} - {1'b0, div_divisor_x3});
        wire [35:0] div_partial_rem_sub4        = ({1'b0, div_partial_rem} - {1'b0, div_divisor_x4});
        wire [35:0] div_partial_rem_sub5        = ({1'b0, div_partial_rem} - {1'b0, div_divisor_x5});
        wire [35:0] div_partial_rem_sub6        = ({1'b0, div_partial_rem} - {1'b0, div_divisor_x6});
        wire [35:0] div_partial_rem_sub7        = ({1'b0, div_partial_rem} - {1'b0, div_divisor_x7});

        // Check carry bits (MSB == 0 means ≥0)
        wire        div_partial_rem_sub1_is_pos = ~div_partial_rem_sub1[35];
        wire        div_partial_rem_sub2_is_pos = ~div_partial_rem_sub2[35];
        wire        div_partial_rem_sub3_is_pos = ~div_partial_rem_sub3[35];
        wire        div_partial_rem_sub4_is_pos = ~div_partial_rem_sub4[35];
        wire        div_partial_rem_sub5_is_pos = ~div_partial_rem_sub5[35];
        wire        div_partial_rem_sub6_is_pos = ~div_partial_rem_sub6[35];
        wire        div_partial_rem_sub7_is_pos = ~div_partial_rem_sub7[35];

        // Generate the current quotient digit
        // Note that for the last cycle, we mask the q_digit LSB as we need only 32b in total
        wire  [2:0] div_partial_rem_sub_q_digit =  div_partial_rem_sub7_is_pos ? (3'b111 & {2'b11, ~div_done}):
                                                   div_partial_rem_sub6_is_pos ? (3'b110 & {2'b11, ~div_done}):
                                                   div_partial_rem_sub5_is_pos ? (3'b101 & {2'b11, ~div_done}):
                                                   div_partial_rem_sub4_is_pos ? (3'b100 & {2'b11, ~div_done}):
                                                   div_partial_rem_sub3_is_pos ? (3'b011 & {2'b11, ~div_done}):
                                                   div_partial_rem_sub2_is_pos ? (3'b010 & {2'b11, ~div_done}):
                                                   div_partial_rem_sub1_is_pos ? (3'b001 & {2'b11, ~div_done}):
                                                                                 (3'b000 & {2'b11, ~div_done});

        // Partial remainder
        assign      div_partial_rem_init        = {32'h00000000, div_dividend[31:29]};
        assign      div_partial_rem_nxt         = (div_partial_rem_sub_q_digit==3'b111) ? {div_partial_rem_sub7[32:0], div_result_tmp[31:29]} :
                                                  (div_partial_rem_sub_q_digit==3'b110) ? {div_partial_rem_sub6[32:0], div_result_tmp[31:29]} :
                                                  (div_partial_rem_sub_q_digit==3'b101) ? {div_partial_rem_sub5[32:0], div_result_tmp[31:29]} :
                                                  (div_partial_rem_sub_q_digit==3'b100) ? {div_partial_rem_sub4[32:0], div_result_tmp[31:29]} :
                                                  (div_partial_rem_sub_q_digit==3'b011) ? {div_partial_rem_sub3[32:0], div_result_tmp[31:29]} :
                                                  (div_partial_rem_sub_q_digit==3'b010) ? {div_partial_rem_sub2[32:0], div_result_tmp[31:29]} :
                                                  (div_partial_rem_sub_q_digit==3'b001) ? {div_partial_rem_sub1[32:0], div_result_tmp[31:29]} :
                                                                                          {div_partial_rem[32:0],      div_result_tmp[31:29]} ;

        // Division Result register
        assign      div_result_tmp_init         = {div_dividend[28:0],   3'b000};
        assign      div_result_tmp_nxt          = {div_result_tmp[28:0]  , div_partial_rem_sub_q_digit     } ;
        wire [31:0] div_result_tmp_nxt_last     = {div_result_tmp[29:0]  , div_partial_rem_sub_q_digit[2:1]} ; // for the last cycle we take 1 bit less

        // Format result for the output stage
        assign      div_result_rem_pre          =  div_partial_rem_nxt[35:4];
        assign      div_result_div_pre          =  div_result_tmp_nxt_last;

        // Lint Cleanup
        wire  [1:0] div_partial_rem_sub1_unused =  div_partial_rem_sub1[34:33];
        wire  [1:0] div_partial_rem_sub2_unused =  div_partial_rem_sub2[34:33];
        wire  [1:0] div_partial_rem_sub3_unused =  div_partial_rem_sub3[34:33];
        wire  [1:0] div_partial_rem_sub4_unused =  div_partial_rem_sub4[34:33];
        wire  [1:0] div_partial_rem_sub5_unused =  div_partial_rem_sub5[34:33];
        wire  [1:0] div_partial_rem_sub6_unused =  div_partial_rem_sub6[34:33];
        wire  [1:0] div_partial_rem_sub7_unused =  div_partial_rem_sub7[34:33];


    //------------------------------------------------------------------------------------------------
    // 17-cycles Division
    //------------------------------------------------------------------------------------------------
    end else if (DIV_17C_EN) begin : DIV_17_CYCLES

        // Radix-4 division needs 1+16 cycles
        assign      div_counter_init            =  6'd15;

        // Build multiples of the divisor
        wire [33:0] div_divisor_x1              = {1'b0,        1'b0,  div_divisor} ; // 1×divisor
        wire [33:0] div_divisor_x2              = {1'b0, div_divisor,         1'b0} ; // 2×divisor
        wire [33:0] div_divisor_x3              = (div_divisor_x1 + div_divisor_x2) ; // 3×divisor

        // Candidate remainders
        wire [34:0] div_partial_rem_sub1        = ({1'b0, div_partial_rem[33:0]} - {1'b0, div_divisor_x1});
        wire [34:0] div_partial_rem_sub2        = ({1'b0, div_partial_rem[33:0]} - {1'b0, div_divisor_x2});
        wire [34:0] div_partial_rem_sub3        = ({1'b0, div_partial_rem[33:0]} - {1'b0, div_divisor_x3});

        // Check carry bits (MSB == 0 means ≥0)
        wire        div_partial_rem_sub1_is_pos = ~div_partial_rem_sub1[34];
        wire        div_partial_rem_sub2_is_pos = ~div_partial_rem_sub2[34];
        wire        div_partial_rem_sub3_is_pos = ~div_partial_rem_sub3[34];

        // Generate the current quotient digit
        wire  [1:0] div_partial_rem_sub_q_digit =  div_partial_rem_sub3_is_pos ? 2'b11 :
                                                   div_partial_rem_sub2_is_pos ? 2'b10 :
                                                   div_partial_rem_sub1_is_pos ? 2'b01 :
                                                                                 2'b00 ;

        // Partial remainder
        assign      div_partial_rem_init        = {1'h0, 32'h00000000, div_dividend[31:30]};
        assign      div_partial_rem_nxt         =  div_partial_rem_sub3_is_pos ? {2'h0, div_partial_rem_sub3[31:0], div_result_tmp[31:30]} :
                                                   div_partial_rem_sub2_is_pos ? {2'h0, div_partial_rem_sub2[31:0], div_result_tmp[31:30]} :
                                                   div_partial_rem_sub1_is_pos ? {2'h0, div_partial_rem_sub1[31:0], div_result_tmp[31:30]} :
                                                                                 {2'h0, div_partial_rem[31:0],      div_result_tmp[31:30]} ;

        // Division Result register
        assign      div_result_tmp_init         = {div_dividend[29:0],   2'b00};
        assign      div_result_tmp_nxt          = {div_result_tmp[29:0], div_partial_rem_sub_q_digit};

        // Format result for the output stage
        assign      div_result_rem_pre          =  div_partial_rem_nxt[33:2];
        assign      div_result_div_pre          =  div_result_tmp_nxt;

        // Lint Cleanup
        wire        div_partial_rem_unused      =  div_partial_rem[34];
        wire        div_partial_rem_nxt_unused  =  div_partial_rem_nxt[35];
        wire  [1:0] div_partial_rem_sub1_unused =  div_partial_rem_sub1[33:32];
        wire  [1:0] div_partial_rem_sub2_unused =  div_partial_rem_sub2[33:32];
        wire  [1:0] div_partial_rem_sub3_unused =  div_partial_rem_sub3[33:32];


    //------------------------------------------------------------------------------------------------
    // 33-cycles Division
    //------------------------------------------------------------------------------------------------
    end else if (DIV_33C_EN) begin : DIV_33_CYCLES

        // Radix-2 division needs 1+32 cycles
        assign      div_counter_init            =  6'd31;

        // Remainder
        wire [32:0] div_partial_rem_sub         = (div_partial_rem[32:0] - {1'b0, div_divisor});

        // Check carry bit (MSB == 0 means ≥0)
        wire        div_partial_rem_sub_is_pos  = ~div_partial_rem_sub[32];

        // Partial remainder
        assign      div_partial_rem_init        = {2'h0, 32'h00000000, div_dividend[31]};
        assign      div_partial_rem_nxt         =  div_partial_rem_sub_is_pos ? {3'h0, div_partial_rem_sub[31:0], div_result_tmp[31]} :
                                                                                {3'h0, div_partial_rem[31:0],     div_result_tmp[31]} ;

        // Division Result register
        assign      div_result_tmp_init         = {div_dividend[30:0],   1'b0};
        assign      div_result_tmp_nxt          = {div_result_tmp[30:0], div_partial_rem_sub_is_pos};

        // Format result for the output stage
        assign      div_result_rem_pre          =  div_partial_rem_nxt[32:1];
        assign      div_result_div_pre          =  div_result_tmp_nxt;

        // Lint Cleanup
        wire  [1:0] div_partial_rem_unused      =  div_partial_rem[34:33];
        wire        div_partial_rem_nxt_unused  =  div_partial_rem_nxt[35];

    end
endgenerate

//------------------------------------------------------------------------------------------------
// Common: divider result selection (quotient vs remainder, sign re-inversion)
//------------------------------------------------------------------------------------------------

// For the remainder, we re-invert the sign if the dividend is negative (dividend==operand1)
wire        div_remainder_sign =  div_op1_is_neg;

// For the quotient, we re-invert the sign if only one of the operands is negative and if we are not dividing by zero
wire        div_quotient_sign  = (div_op1_is_neg ^ div_op2_is_neg) & ~div_by_zero ; // dividend==operand1 & divisor==operand2


wire [31:0] result_div_pre     = div_result_is_rem ? div_result_rem_pre : div_result_div_pre ;
wire        result_div_sign    = div_result_is_rem ? div_remainder_sign : div_quotient_sign  ;

assign      result_div         = (({32{result_div_sign}} ^ result_div_pre) + {{31{1'b0}}, result_div_sign }) & {32{div_mode_enable}};


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                              RESULT AND LINT CLEANUP                                                 //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

assign      result_o   = result_mpy | result_div;
assign      done_o     = mpy_done   | div_done  ;

// Unused clock and reset
wire        ex_alu_control_5_unused = ex_alu_control_i[5];
wire        ex_alu_control_2_unused = ex_alu_control_i[2];


endmodule

`default_nettype wire

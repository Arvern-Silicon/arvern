//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_uop_sequencer
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_uop_sequencer.v
// Module Description : Micro-op sequencer for Zcmp (PUSH/POP/POPRET/POPRETZ/MV)
//                      and Zcmt (CM.JT/CM.JALT) compound instructions
//----------------------------------------------------------------------------
`default_nettype none

module arv_uop_sequencer (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// CONTROL FROM DECODER
    input  wire           ex_uop_enable_i,
    input  wire     [3:0] ex_uop_type_i,
    input  wire     [3:0] ex_uop_rlist_i,
    input  wire           ex_c_cm_push_nxt_i,
    input  wire           id_uop_start_i,
    input  wire           id_uop_jt_start_i,
    input  wire     [7:0] id_uop_ldst_start_i,

// IRQ KILL
    input  wire           kill_i,
    output wire           is_killable_o,

// READY SIGNAL
    output wire           ex_uop_ready_o,

// DIRECT CONTROL OF LOAD-STORE UNIT
    input  wire           ex_ldst_ready_i,
    input  wire           wb_ldst_ready_i,
    input  wire           wb_dph_ongoing_i,
    output wire     [4:0] ex_ldst_control_o,
    output wire    [31:0] ex_ldst_immediate_o,

// DIRECT CONTROL OF ALU
    input  wire           ex_alu_ready_i,
    output wire    [16:0] ex_alu_control_o,
    output wire     [4:0] ex_alu_mode_o,
    output wire           ex_alu_select_o,

// REGISTER FILE INTERFACE (FOR REG_MOVE AND ALU OPS)
    output wire    [31:0] ex_uop_src1_sel_o,
    output wire    [31:0] id_uop_src1_sel_o,
    output wire    [31:0] ex_uop_src2_sel_o,
    output reg      [4:0] ex_uop_ld_dest_sel_o,
    output wire           ex_uop_mv_dest_ctrl_o,

// CM.POPRETZ: ZERO A0
    output wire           ex_uop_a0_zero_en_o,

// CM.JT / CM.JALT: JVT INPUTS
    input  wire    [31:0] jvt_base_i,
    input  wire    [31:0] wb_ldst_data_i,
    input  wire           wb_ldst_wr_i,
    input  wire           wb_excp_load_access_fault_i,

// CM.JT / CM.JALT: TABLE JUMP OUTPUTS
    output wire    [31:0] ex_uop_jt_base_o,
    output wire           ex_uop_jt_branch_active_o,
    output wire    [31:0] ex_uop_jt_branch_target_o,
    output wire           ex_uop_jt_active_o

);

// USER PARAMETERs
//================================================================
parameter                 ARST_EN      =  1'b1;       // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 ZCMT_EN      =  1'b0;       // Zcmt extension enable (table jumps)


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

wire                [3:0] uop_counter;
wire                      uop_start;
wire                      uop_done;
wire                      uop_alu_done;
wire                      uop_alu_wait;
wire                      uop_ret_done;
wire                      uop_ldst_wait;
wire                [3:0] uop_counter_init;
wire                [3:0] uop_counter_decr;
wire                [3:0] uop_push_pop_state;
wire               [15:0] uop_push_pop_1hot;

wire                      uop_counter_wait;
wire                      uop_load_store_en;
wire                      uop_sp_upd_active;
wire                      uop_branch_active;
wire                      ex_load_enable;
wire                      ex_store_enable;
wire                      uop_ret_active;
wire               [31:0] uop_ldst_imm_start;

wire                      jt_load_active;
wire                      jalt_alu_active;
wire                      jt_done;
wire                      jt_kill;
wire                      jt_is_killable;
wire                      jt_completed;
wire                      jt_fault_exit;


// Decode micro-op operations
wire                      ex_c_cm_push       = (ex_uop_type_i == 4'd0) ;
wire                      ex_c_cm_pop        = (ex_uop_type_i == 4'd1) ;
wire                      ex_c_cm_popret     = (ex_uop_type_i == 4'd2) ;
wire                      ex_c_cm_popretz    = (ex_uop_type_i == 4'd3) ;
wire                      ex_c_cm_mva01s     = (ex_uop_type_i == 4'd4) ;
wire                      ex_c_cm_mvsa01     = (ex_uop_type_i == 4'd5) ;
wire                      ex_c_cm_jt         = (ex_uop_type_i == 4'd6) & ZCMT_EN;
wire                      ex_c_cm_jalt       = (ex_uop_type_i == 4'd7) & ZCMT_EN;

wire                      ex_pushpop_active  = ex_uop_enable_i & (ex_c_cm_push | ex_c_cm_pop | ex_c_cm_popret | ex_c_cm_popretz);
wire                      ex_jt_active       = ex_uop_enable_i & (ex_c_cm_jt   | ex_c_cm_jalt);

// 2-phase register move via ALU pass-through (MVA01S / MVSA01)
wire                      ex_uop_mv_phase;
wire                      ex_mv_active       = ex_uop_enable_i & (ex_c_cm_mva01s | ex_c_cm_mvsa01);
wire                      ex_mv_done         = ex_mv_active & ex_uop_mv_phase & ex_alu_ready_i;  // Second CM.MV completes when ALU is ready


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                PUSH/POP SEQUENCER                                                    //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
//
// Counter for the PUSH/POP sequences
//
// 0xF-0x2 : Performing Load-Store operations
// 0x1     : Updating SP after push/pop sequence
// 0x0     : Performing RET operation
assign      uop_start           =  ex_pushpop_active & (uop_counter==4'hf);
wire        uop_pop_variant     = (ex_c_cm_pop | ex_c_cm_popret | ex_c_cm_popretz);
assign      uop_alu_done        =  ex_alu_ready_i    & (uop_counter==4'h1) & ~(wb_dph_ongoing_i & uop_pop_variant);
assign      uop_ret_done        =                      (uop_counter==4'h0);
assign      uop_done            = (ex_c_cm_popret  | ex_c_cm_popretz) ? uop_ret_done : uop_alu_done;
// This subtraction underflows when rlist < 3
// Zc spec 28.13 reserves those rlist encodings (4..15 are the only legal values), so the underflow
// is unreachable in conformant programs. Upstream the decoder filters reserved rlist into
// id_std_opcode_error, so a hostile rlist=0..3 traps as illegal before reaching the sequencer.
assign      uop_counter_init    = (ex_uop_rlist_i==4'hF) ? 4'hD : (ex_uop_rlist_i-4'h3);
assign      uop_counter_decr    = (uop_counter-4'h1);

assign      uop_alu_wait        = (~ex_alu_ready_i   & (uop_counter==4'h1)) ;
assign      uop_ldst_wait       = (~ex_ldst_ready_i  & (uop_counter> 4'h1)) |
                                  (~wb_ldst_ready_i  & (uop_counter==4'h1)  & (ex_c_cm_popret | ex_c_cm_popretz)) |
                                  ( wb_dph_ongoing_i & (uop_counter==4'h1)  & (ex_c_cm_popret | ex_c_cm_popretz | ex_c_cm_pop)); // atomicity gate
assign      uop_counter_wait    =   uop_ldst_wait    |  uop_alu_wait;

// Kill window: load/store phase with at least one more load/store remaining
// after this cycle. Counter=2 is the LAST load/store of the sequence (its
// DPH may still be in flight); counter=1 is the SP update; counter=0 is RET.
//
// FEATURE REACHABILITY (AHB-Lite-safe by design):
//   The pushpop IRQ-kill feature (`irqkill_uop_en`) is effectively unreachable
//   under continuous back-to-back AHB-Lite traffic, because `is_killable_o`
//   is further gated by `~wb_dph_ongoing_i` and `dph_ongoing` stays high
//   across every APH cycle while transactions are pipelined. Kill therefore
//   only fires when wait states inject an idle window (the bus reaches a
//   beat between transactions). This is CORRECT AHB-Lite-safe behaviour:
//   killing while a DPH is in flight would commit unintended data to a
//   register and/or strand the bus. Worst-case IRQ latency on a long
//   `cm.pop` under fast-SRAM is therefore the full natural duration of the
//   sequence. Do NOT widen this gate without adding an explicit "wait for
//   last in-flight DPH then kill" interlock -- the alternative is a
//   protocol violation.
wire        uop_in_kill_window  =  ex_pushpop_active & (uop_counter > 4'h2) & (uop_counter != 4'hf);
// AUDIT HOOK -- uop_kill defensive AND-term:
//   kill_i is already gated upstream by is_killable_o (= uop_is_killable |
//   jt_is_killable), and uop_is_killable already requires uop_in_kill_window.
//   So the AND here is redundant -- kill_i can only be 1 when
//   uop_in_kill_window=1 anyway. The redundant gate is kept as a defensive
//   belt against future widening of is_killable_o that might decouple it
//   from uop_in_kill_window.
wire        uop_kill            =  kill_i & uop_in_kill_window;

wire  [3:0] uop_counter_nxt     = ~ex_pushpop_active            ? 4'hf             :
                                   uop_kill                     ? 4'hf             :
                                  ~uop_counter_wait & uop_done  ? 4'hf             :
                                  ~uop_counter_wait & uop_start ? uop_counter_init :
                                  ~uop_counter_wait             ? uop_counter_decr :
                                                                  uop_counter      ;

arv_dff #(.WIDTH(4), .RST_VAL(4'hf), .ARST_EN(ARST_EN)) u_uop_counter (
                                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(uop_counter_nxt), .q_o(uop_counter));

// Decoding counter into a 1hot signal to simplify source register selection
assign      uop_push_pop_state  = uop_start ? ((ex_uop_rlist_i==4'hF) ? 4'hE : (ex_uop_rlist_i-4'h2)) : uop_counter;
assign      uop_push_pop_1hot   = (16'h0001 << uop_push_pop_state);

assign      uop_load_store_en   =  ex_pushpop_active    & (uop_counter>'h1)  & ~uop_kill;
assign      uop_sp_upd_active   =  uop_push_pop_1hot[1] & ~(wb_dph_ongoing_i & uop_pop_variant) & ex_pushpop_active;
assign      uop_branch_active   =  uop_push_pop_1hot[0];

// RET active for POPRET/POPRETZ at counter=0
assign      uop_ret_active      =  ex_pushpop_active & uop_branch_active;

// Source register selections
assign      id_uop_src1_sel_o   = {29'h0, 1'b0,              uop_ret_active, 1'b0}; // x1=ra
assign      ex_uop_src1_sel_o   = {29'h0, uop_load_store_en, 1'b0,           1'b0}; // x2=sp

assign      ex_uop_src2_sel_o   = {4'h0,                            // x28-x31
                                   uop_push_pop_1hot[14],           // x27      - s11
                                   uop_push_pop_1hot[13],           // x26      - s10
                                   uop_push_pop_1hot[12],           // x25      - s9
                                   uop_push_pop_1hot[11],           // x24      - s8
                                   uop_push_pop_1hot[10],           // x23      - s7
                                   uop_push_pop_1hot[9],            // x22      - s6
                                   uop_push_pop_1hot[8],            // x21      - s5
                                   uop_push_pop_1hot[7],            // x20      - s4
                                   uop_push_pop_1hot[6],            // x19      - s3
                                   uop_push_pop_1hot[5],            // x18      - s2
                                   8'h00,                           // x10-x17
                                   uop_push_pop_1hot[4],            // x9       - s1
                                   uop_push_pop_1hot[3],            // x8       - s0
                                   6'h00,                           // x2-x7
                                   uop_push_pop_1hot[2],            // x1       - ra
                                   1'b0                             // x0
};

// Load destination register for CM.POP operations
always @(*) begin
    case (uop_push_pop_state)
        4'd2:    ex_uop_ld_dest_sel_o = 5'd1;   // ra  (x1)
        4'd3:    ex_uop_ld_dest_sel_o = 5'd8;   // s0  (x8)
        4'd4:    ex_uop_ld_dest_sel_o = 5'd9;   // s1  (x9)
        4'd5:    ex_uop_ld_dest_sel_o = 5'd18;  // s2  (x18)
        4'd6:    ex_uop_ld_dest_sel_o = 5'd19;  // s3  (x19)
        4'd7:    ex_uop_ld_dest_sel_o = 5'd20;  // s4  (x20)
        4'd8:    ex_uop_ld_dest_sel_o = 5'd21;  // s5  (x21)
        4'd9:    ex_uop_ld_dest_sel_o = 5'd22;  // s6  (x22)
        4'd10:   ex_uop_ld_dest_sel_o = 5'd23;  // s7  (x23)
        4'd11:   ex_uop_ld_dest_sel_o = 5'd24;  // s8  (x24)
        4'd12:   ex_uop_ld_dest_sel_o = 5'd25;  // s9  (x25)
        4'd13:   ex_uop_ld_dest_sel_o = 5'd26;  // s10 (x26)
        4'd14:   ex_uop_ld_dest_sel_o = 5'd27;  // s11 (x27)
        default: ex_uop_ld_dest_sel_o = 5'd0;   // x0
    endcase
end


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       CM.MVA01S / CM.MVSA01 - 2-PHASE MOVE                                           //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Phase FSM: phase 0 -> ALU writes operand1->dest1; phase 1 -> ALU writes operand2 -> dest2
// Advance phase only when ALU completes (handles random ALU stalls in verification)
wire  ex_uop_mv_phase_nxt = ~ex_mv_active   ?  1'b0            :
                             ex_alu_ready_i ? ~ex_uop_mv_phase :
                                               ex_uop_mv_phase ;

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_ex_uop_mv_phase (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(ex_uop_mv_phase_nxt), .q_o(ex_uop_mv_phase));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                          CM.JT / CM.JALT TABLE JUMP SEQUENCER                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
localparam JT_IDLE = 2'd0;   // Waiting for first cycle / address phase accepted
localparam JT_LOAD = 2'd1;   // Waiting for AHB address phase acceptance
localparam JT_DPH  = 2'd2;   // Waiting for AHB data phase (load result)
localparam JT_ALU  = 2'd3;   // Waiting for ALU (cm.jalt PC+2 computation)

generate
    if (ZCMT_EN) begin : WITH_ZMT

        // Control to activate branch in decoder -- fires ONLY after JVT load data arrives.
        // Setting on id_uop_start_i was premature: jt_branch_target=0 at that point, causing
        // id_slow_branch_o to redirect fetch to address 0x00000000.
        wire        jt_branch_active;
        wire        jt_branch_active_clr = (~ex_uop_enable_i | jt_done | jt_kill);    // clear takes priority
        wire        jt_branch_active_set = (wb_ldst_wr_i & ex_jt_active);             // set only when load data valid
        wire        jt_branch_active_en  =  jt_branch_active_clr | jt_branch_active_set;
        wire        jt_branch_active_nxt =  jt_branch_active_clr ? 1'b0 : 1'b1;

        arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_jt_branch_active (
                               .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(jt_branch_active_en),
                                                                    .d_i (jt_branch_active_nxt),
                                                                    .q_o (jt_branch_active));

        // Prevents the JT FSM from restarting while decode stall holds ex_uop_enable_i high.
        wire        jt_completed_r;
        wire        jt_completed_clr = (~ex_uop_enable_i | jt_kill);
        wire        jt_completed_en  =  jt_completed_clr | jt_done;
        wire        jt_completed_nxt =  jt_completed_clr ? 1'b0 : 1'b1;

        arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_jt_completed_r (
                             .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(jt_completed_en),
                                                                  .d_i (jt_completed_nxt),
                                                                  .q_o (jt_completed_r));
        assign jt_completed = jt_completed_r;


        // Capture load result when it arrives (this is the target of the branch)
        wire [31:0] jt_branch_target;
        wire        jt_branch_target_clr = (~ex_jt_active | jt_done);
        wire        jt_branch_target_en  =  jt_branch_target_clr | wb_ldst_wr_i;
        wire [31:0] jt_branch_target_nxt =  jt_branch_target_clr ? 32'h0 : wb_ldst_data_i;

        arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_jt_branch_target (
                                .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(jt_branch_target_en),
                                                                     .d_i (jt_branch_target_nxt),
                                                                     .q_o (jt_branch_target));

        // TABLE JUMP FSM
        wire  [1:0] jt_state;
        reg   [1:0] jt_state_nxt;
        always @(*) begin
            jt_state_nxt = jt_state;                                                                                  // default: hold
            if (~ex_jt_active | jt_kill)                      jt_state_nxt     = JT_IDLE;
            else begin
                case (jt_state)
                    JT_IDLE: if (!jt_completed)               jt_state_nxt     = ex_ldst_ready_i ? JT_DPH : JT_LOAD; // First cycle: if AHB accepts immediately -> JT_DPH, else -> JT_LOAD
                    JT_LOAD: if (ex_ldst_ready_i)             jt_state_nxt     = JT_DPH;                             // Wait for AHB address phase
                    JT_DPH:  if (wb_excp_load_access_fault_i) jt_state_nxt     = JT_IDLE;                            // JVT load faulted: trap will fire (MCAUSE=5), bail out
                             else if (wb_ldst_wr_i)           jt_state_nxt     = JT_ALU;                             // cm.jalt -> JT_ALU, cm.jt -> done
                    JT_ALU:  if (ex_alu_ready_i | ex_c_cm_jt) jt_state_nxt     = JT_IDLE;                            // cm.jalt -> ALU computed PC+2 done, cm.jt -> done
                endcase
            end
        end
        arv_dff #(.WIDTH(2), .RST_VAL(JT_IDLE), .ARST_EN(ARST_EN)) u_jt_state (
                                          .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(jt_state_nxt), .q_o(jt_state));

        // Kill JT/JALT: safe during address phase (states 0,1) before load data arrives
        assign jt_kill                   = kill_i & ex_jt_active & (jt_state <= JT_LOAD);

        // JVT-load access-fault exit: lets ex_uop_ready_o pulse so the UOP control
        // flop clears and the pipeline drains the synchronous trap (MCAUSE=5).
        assign jt_fault_exit             = wb_excp_load_access_fault_i & ex_jt_active & (jt_state == JT_DPH);

        // Some utilities
        assign jt_load_active            =  ex_jt_active & ((jt_state == JT_LOAD) |  (jt_state == JT_IDLE));
        assign jalt_alu_active           =  ex_c_cm_jalt &  (jt_state == JT_ALU)  ;                                   // ALU activates 1 cycle after load data (registered JT_ALU state)
        assign jt_done                   =  ex_jt_active &  (jt_state == JT_ALU)  & (ex_alu_ready_i | ex_c_cm_jt);    // cm.jalt: done when ALU ready

        // Output assignments
        assign ex_uop_jt_base_o          = {jvt_base_i[31:6], 6'b0} & {32{jt_load_active}};
        assign ex_uop_jt_branch_target_o =  jt_branch_target;
        assign ex_uop_jt_branch_active_o =  jt_branch_active;
        assign ex_uop_jt_active_o        =  ex_jt_active;

        // JT/JALT killable during address phase (states 0,1) when no DPH in flight
        assign jt_is_killable            =  ex_jt_active & (jt_state <= JT_LOAD) & !wb_dph_ongoing_i;

        // Lint
        wire [5:0] jvt_base_unused       = jvt_base_i[5:0];

    end else begin : NO_ZMT

        assign jt_kill                   =  1'b0;
        assign jt_load_active            =  1'b0;
        assign jalt_alu_active           =  1'b0;
        assign jt_done                   =  1'b0;
        assign jt_completed              =  1'b0;
        assign jt_is_killable            =  1'b0;
        assign jt_fault_exit             =  1'b0;

        assign ex_uop_jt_base_o          = 32'h00000000;
        assign ex_uop_jt_branch_target_o = 32'h00000000;
        assign ex_uop_jt_branch_active_o =  1'b0;
        assign ex_uop_jt_active_o        =  1'b0;

        // Lint
        wire [31:0] jvt_base_unused                    = jvt_base_i;
        wire [31:0] wb_ldst_data_i_unused              = wb_ldst_data_i;
        wire        wb_ldst_wr_i_unused                = wb_ldst_wr_i;
        wire        wb_excp_load_access_fault_i_unused = wb_excp_load_access_fault_i;

    end
endgenerate


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                               LOAD/STORE CONTROL                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Load-Store control signals
assign      ex_load_enable       =  ex_c_cm_pop | ex_c_cm_popret | ex_c_cm_popretz | ex_jt_active;
assign      ex_store_enable      =  ex_c_cm_push;
assign      ex_ldst_control_o    = {5{uop_load_store_en | jt_load_active}} & {1'b0,              // Load-type
                                                                              2'h2,              // Size (always word)
                                                                              ex_load_enable,    // Load
                                                                              ex_store_enable};  // Store

// Immediate value for load-store operations
assign      uop_ldst_imm_start   =  id_uop_jt_start_i ? {22'h000000, id_uop_ldst_start_i, 2'b0}            :
                                                        {{24{id_uop_ldst_start_i[7]}}, id_uop_ldst_start_i};

wire        ex_ldst_imm_clr  = ~(uop_load_store_en | jt_load_active);
wire        ex_ldst_imm_step = ~uop_counter_wait & (uop_push_pop_1hot[2] | ex_pushpop_active);
wire        ex_ldst_imm_en   = id_uop_start_i | ex_ldst_imm_clr | ex_ldst_imm_step;
wire [31:0] ex_ldst_imm_nxt  =
    id_uop_start_i                                  ? uop_ldst_imm_start                       :
    ex_ldst_imm_clr                                 ? 32'h00000000                             :
    (~uop_counter_wait & uop_push_pop_1hot[2])      ? 32'h00000000                             :
    (~uop_counter_wait & ex_pushpop_active)         ? (ex_ldst_immediate_o + 32'hfffffffc)     :
                                                      ex_ldst_immediate_o                      ;

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_ex_ldst_immediate (
                         .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ex_ldst_imm_en), .d_i(ex_ldst_imm_nxt), .q_o(ex_ldst_immediate_o));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       ALU CONTROL (SHARED BETWEEN POP/PUSH AND MV)                                   //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Select ADD operations in case of CM.POP/PUSH/JALT, select MV operation in case of CM.MV*
assign      ex_alu_control_o     = {8'h00, ex_mv_active, 7'h00, uop_sp_upd_active | jalt_alu_active};

// Only use ALU in standard mode
assign      ex_alu_mode_o        = {4'h0, uop_sp_upd_active | ex_mv_active | jalt_alu_active};

// select signed operand2 in case of push (for correct negative offset calculation), select operand2 (SP) for MV ops
wire        ex_alu_select_nxt    = (ex_c_cm_push_nxt_i & (uop_counter_nxt==4'h1)) | ex_uop_mv_phase_nxt;

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_ex_alu_select (
                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(ex_alu_select_nxt), .q_o(ex_alu_select_o));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                       INTEGER REGISTER WRITE CONTROL                                                 //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// CM.POPRETZ: assert during the branch state (counter=0) to trigger zero write to a0 (x10)
assign     ex_uop_a0_zero_en_o   = ( ex_c_cm_popretz & uop_branch_active);

// Control signal to select between the different destinations for the CM.MV* instructions
// First phase we select the destination from uop, second phase we select the destination from the decoder
// (note that using the decoder destination last allows us to reuse the hazard detection logic from the decoder)
assign     ex_uop_mv_dest_ctrl_o = (~ex_uop_mv_phase & ex_mv_active);


assign     ex_uop_ready_o        = (~ex_uop_enable_i | uop_done | ex_mv_done | jt_done | jt_completed | uop_kill | jt_kill | jt_fault_exit);

// UOP killable: pushpop in the safe kill window AND no DPH in flight.
wire       uop_is_killable       = uop_in_kill_window & !wb_dph_ongoing_i;
assign     is_killable_o         = uop_is_killable | jt_is_killable;

wire       uop_push_pop_1hot_unused = uop_push_pop_1hot[15];


endmodule

`default_nettype wire

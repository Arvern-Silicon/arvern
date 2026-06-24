//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_fetch
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_fetch.v
// Module Description : RISC-V instruction fetch unit
//                      (PC management, branch redirect, instruction AHB master)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_fetch (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// INSTRUCTION AHB BUS
    input  wire    [31:0] inst_hrdata_i,
    input  wire           inst_hready_i,
    input  wire           inst_hresp_i,

    output wire    [31:0] inst_haddr_o,
    output wire     [2:0] inst_hburst_o,
    output wire           inst_hmastlock_o,
    output wire     [3:0] inst_hprot_o,
    output wire     [2:0] inst_hsize_o,
    output wire           inst_hsmode_o,
    output wire     [1:0] inst_htrans_o,
    output wire    [31:0] inst_hwdata_o,
    output wire           inst_hwrite_o,

// INTERFACE TO DECODER
    input  wire           id_branch_detect_i,
    input  wire           id_branch_cancel_i,
    input  wire    [31:0] id_branch_target_i,
    input  wire    [31:0] id_branch_target_nxt_i,
    input  wire           id_slow_branch_i,
    input  wire    [31:0] id_slow_branch_target_i,
    input  wire           ex_uop_has_branch_i,
    input  wire           id_instruction_request_i,
    output wire    [31:0] id_instruction_o,
    output wire           id_instruction_valid_o,
    output wire    [31:0] id_pc_o,
    output wire     [1:0] id_priv_mode_o,

// INTERFACE TO TRAP HANDLER
    input  wire           if_stop_cmd_i,

// OTHERS
    input  wire     [1:0] if_priv_mode_i,
    input  wire    [31:0] reset_vector_i,
    output wire           id_excp_inst_access_fault_o,
    output wire    [31:0] id_inst_fault_addr_o,
    output wire           if_excp_inst_address_misaligned_o,
    output wire           init_pc_o

);

// USER PARAMETERs
//=================================================================================================================
parameter                 ARST_EN             = 1'b1;  // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 C_EXT_EN            = 1'b1;  // Compressed instructions enable
parameter                 SINGLE_CYCLE_BRANCH = 1'b1;  // Taken-branch latency:
                                                       //   0 = one-bubble taken branch  (highest Fmax, lower IPC)
                                                       //   1 = zero-bubble taken branch (lower Fmax, highest IPC)
//=================================================================================================================


//////======================================================================================================================//////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////======================================================================================================================//////

wire               [31:2] if_pc;
wire               [29:0] if_pc_nxt_base;
wire               [29:0] if_pc_nxt;
wire               [31:0] id_pc_reg;
wire                      fetch_freeze;
wire                      fetch_freeze_ahb;
wire                      id_ready;
wire                      incr_pc;
wire                      aph_ongoing;
wire                      aph_valid;
wire                      dph_last;
wire                      dph_error_1st;
wire                      dph_error;
wire                      dph_ongoing_nxt;
wire                      dph_ongoing;
reg                 [5:0] inst_buf_valid_nxt;
wire                [5:0] inst_buf_valid;
reg                [95:0] inst_buf_nxt;
wire               [95:0] inst_buf;
wire                      ignore_incoming;
wire                      buf_will_be_full;
wire                      consume_inst;
wire                      buffered_inst_incomplete;
wire                      incoming_inst_incomplete;

// Speculative branch state
wire                      branch_pending;                                                  // High for exactly 1 cycle after id_branch_detect_i
wire               [31:0] branch_target_saved;                                             // Saved branch target address
wire               [31:2] branch_if_pc_saved;                                              // Saved AHB fetch PC
wire                      branch_target_fetched;                                           // Branch target address was accepted by AHB

wire                      branch_confirmed       = branch_pending   & ~id_branch_cancel_i; // Branch pending and NOT cancelled (taken)
wire                      branch_cancelled       = branch_pending   &  id_branch_cancel_i; // Branch pending and cancelled (not taken)

// id_slow_branch_i is asserted by the decoder ONLY for non-conditional slow redirects (trap, UOP table-jump, FENCE.I)
// Regular conditional branches always take the fast path here.
wire                      id_any_branch_detect   = id_slow_branch_i | id_branch_detect_i;

// Buffer-only path: in SINGLE_CYCLE_BRANCH=0 the decoder reads instructions from the
// registered inst_buf rather than bypassing inst_hrdata, breaking the
// inst_hrdata -> id_branch_target -> inst_haddr combinational loop. Costs one bubble
// on a taken branch (the buffer must refill from the branch target) in exchange for
// the higher Fmax achievable with the loop broken.
wire                      eff_buf_only           = ~SINGLE_CYCLE_BRANCH;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                             AHB STATE MACHINE                                                        //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Combinational output that reflects branch_target_saved during confirm
// This allows zero-bubble consumption of branch target data from AHB
assign id_pc_o = branch_confirmed ? branch_target_saved : id_pc_reg;

// On confirm, treat buffer as empty (stale sequential data being flushed)
wire [5:0] effective_buf_valid    = branch_confirmed ? 6'b000000 : inst_buf_valid;

// Compressed instruction detection (bits[1:0] != 2'b11 indicates 16-bit compressed format)
// id_pc_o[1] automatically reflects branch_target_saved[1] during confirm
wire incoming_lower_is_compressed = C_EXT_EN & (inst_hrdata_i[1:0]   != 2'b11) & ~id_pc_o[1];
wire incoming_upper_is_compressed = C_EXT_EN & (inst_hrdata_i[17:16] != 2'b11) &  id_pc_o[1];
wire buffered_is_compressed       = C_EXT_EN & (inst_buf[1:0]        != 2'b11);

// Instruction access fault freeze: stop AHB after error until trap redirect
//
// The clear on id_any_branch_detect is deliberately BROAD (any branch detect,
// including a SPECULATIVELY-taken conditional branch that is later cancelled),
// not just a confirmed trap/branch redirect. This does NOT drop a real pending
// fault, because the clear is self-healing:
//   - speculative branch CONFIRMED (taken): the erroring fetch was the
//     abandoned not-taken/sequential prefetch -> discarding the fault is the
//     architecturally correct outcome (that path never executes).
//   - speculative branch CANCELLED (mispredicted): execution resumes on the
//     fall-through, which is the path that contained the erroring fetch. The
//     erroring fetch buffered NOTHING (incoming_inst is gated ~dph_error), so
//     the decoder cannot make forward progress without RE-FETCHing that address
wire                      fetch_fault_freeze;
// Priority: any-branch clears (self-healing) > AHB error sets > hold.
wire fetch_fault_freeze_en  = id_any_branch_detect | dph_error;
wire fetch_fault_freeze_nxt = id_any_branch_detect ? 1'b0 :              // Any branch clears (self-healing - see above)
                              dph_error            ? 1'b1 :              // Freeze on AHB error
                                                     fetch_fault_freeze;

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_fetch_fault_freeze (
                         .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(fetch_fault_freeze_en),
                                                              .d_i (fetch_fault_freeze_nxt),
                                                              .q_o (fetch_fault_freeze));

// Combine all fetch freeze conditions
// Stop AHB when: decoder not requesting, system stop, buffer full, or AHB error.
// `dph_error` is REGISTERED -- it goes high on the AHB-Lite 2nd-ERROR cycle
// (one cycle after `dph_error_1st`), which is exactly the cycle a trailing
// sequential prefetch would otherwise commit at the HREADY=1 accept edge.
// Gating fetch_freeze_ahb with the registered signal is what blocks that
// would-be prefetch at the bus boundary.
// id_slow_branch_i suppresses the address phase in the detect cycle: the slow path
// updates if_pc at the clock edge, so the AHB must not issue a fetch from the stale
// if_pc (which could be an unmapped address at the end of ROM).
assign fetch_freeze               = if_stop_cmd_i;
assign fetch_freeze_ahb           = (fetch_freeze | buf_will_be_full | fetch_fault_freeze | dph_error | id_slow_branch_i);

// AHB Interface: Address Phase (Instruction-Fetch stage in the CPU pipeline)
assign aph_ongoing                = ~fetch_freeze_ahb & ~init_pc_o;              // Unless we freeze, just keep fetching
assign aph_valid                  = (aph_ongoing &  inst_hready_i);

// AHB Interface: Data Phase    (Instruction-Decode stage in the CPU pipeline)
assign dph_last                   = (dph_ongoing &  inst_hready_i);
assign dph_ongoing_nxt            =  aph_valid   ? 1'b1 :
                                     dph_last    ? 1'b0 : dph_ongoing;

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_dph_ongoing (
                  .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(dph_ongoing_nxt), .q_o(dph_ongoing));

// AHB Interface: Error Detection is done during the first cycle so it can be registered to shorten timing path.
assign dph_error_1st              = (dph_ongoing & inst_hresp_i  & ~inst_hready_i);
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_dph_error (
                .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(dph_error_1st), .q_o(dph_error));

// Detect when new instruction is fetched. In case of freeze, save it
assign id_ready                   = (inst_hready_i & dph_ongoing);


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                          SPECULATIVE BRANCH STATE                                                    //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Branch pending: high for exactly 1 cycle after id_branch_detect_i
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_branch_pending (
                     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(id_any_branch_detect), .q_o(branch_pending));

// Save branch state on detection for confirm/cancel resolution
//    + branch_target_saved  : branch target address (used on confirm to update id_pc_o)
//    + branch_if_pc_saved   : sequential AHB PC (used on cancel to restore AHB fetch address)
//    + branch_target_fetched: whether branch target address was accepted by AHB (distinguishes data source)
// All three update together, gated by id_any_branch_detect (priority hold otherwise).
wire [31:0] branch_target_saved_nxt   = id_slow_branch_i ? {id_slow_branch_target_i[31:1], 1'b0} : {id_branch_target_i[31:1], 1'b0};
wire [31:2] branch_if_pc_saved_nxt    = branch_cancelled ? branch_if_pc_saved : if_pc;
wire        branch_target_fetched_nxt = id_slow_branch_i ? 1'b0 : aph_valid;

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_branch_target_saved (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(id_any_branch_detect), .d_i(branch_target_saved_nxt),   .q_o(branch_target_saved));
arv_dff #(.WIDTH(30), .ARST_EN(ARST_EN)) u_branch_if_pc_saved (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(id_any_branch_detect), .d_i(branch_if_pc_saved_nxt),    .q_o(branch_if_pc_saved));
arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_branch_target_fetched (
                            .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(id_any_branch_detect), .d_i(branch_target_fetched_nxt), .q_o(branch_target_fetched));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                                  PROGRAM COUNTER                                                     //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Drive PC initialization after a reset (resets HIGH, then self-clears next cycle)
arv_dff #(.WIDTH(1), .RST_VAL(1'b1), .ARST_EN(ARST_EN)) u_init_pc (
                              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(1'b0), .q_o(init_pc_o));

// Compute PC increment based on haddr
assign  incr_pc        = (inst_hready_i & aph_ongoing);

// Sequential address for the non-branch cases
assign  if_pc_nxt_base = branch_cancelled ?  branch_if_pc_saved      : if_pc         ;
assign  if_pc_nxt      = incr_pc          ? (if_pc_nxt_base + 30'd1) : if_pc_nxt_base;

// When a branch target is accepted by AHB in the same cycle it is computed (id_branch_detect_i & incr_pc),
// use the precomputed next-word address id_branch_target_nxt_i[31:2] (= branch_target + 4)
// instead of computing +1 inside fetch.
wire [31:2] if_pc_nxt_reg = init_pc_o                    ? reset_vector_i[31:2]        :
                            id_slow_branch_i            ? id_slow_branch_target_i[31:2] :
                           (id_branch_detect_i &  incr_pc) ? id_branch_target_nxt_i[31:2] :
                           (id_branch_detect_i & ~incr_pc) ? id_branch_target_i[31:2]     :
                                                          if_pc_nxt;
arv_dff #(.WIDTH(30), .ARST_EN(ARST_EN)) u_if_pc (
             .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(if_pc_nxt_reg), .q_o(if_pc));

// Lint cleanup
wire [1:0] id_branch_target_nxt_unused   = id_branch_target_nxt_i[1:0];
wire       id_slow_branch_target_unused  = id_slow_branch_target_i[0];
wire       id_branch_target_lsb_unused   = id_branch_target_i[0];

// This PC increments as instructions are consumed by the decoder
// On confirm, effective_buf_valid forces AHB path
wire id_next_inst_is_c = C_EXT_EN & (effective_buf_valid[0] ? buffered_is_compressed : (incoming_lower_is_compressed | incoming_upper_is_compressed));
wire id_incr_by_2      = consume_inst & id_instruction_valid_o &  id_next_inst_is_c;
wire id_incr_by_4      = consume_inst & id_instruction_valid_o & ~id_next_inst_is_c;

// id_pc_reg: base register for id_pc_o
// id_pc_o = branch_confirmed ? branch_target_saved : id_pc_reg  (combinational, defined above)
// On confirm+consume: id_incr uses id_pc_o (= branch_target_saved), so id_pc_reg advances from target
// On confirm without consume: branch_confirmed fallback sets id_pc_reg to target
wire        id_pc_reg_en  = init_pc_o | id_incr_by_2 | id_incr_by_4 | branch_confirmed;
wire [31:0] id_pc_reg_nxt = init_pc_o        ? reset_vector_i       :
                            id_incr_by_2     ? id_pc_o + 32'd2      :   // Compressed instruction: 16 bits
                            id_incr_by_4     ? id_pc_o + 32'd4      :   // Standard instruction: 32 bits
                            branch_confirmed ? branch_target_saved  :   // Confirm without consumption
                                               id_pc_reg;

arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_id_pc_reg (
                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(id_pc_reg_en), .d_i(id_pc_reg_nxt), .q_o(id_pc_reg));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                            INSTRUCTION AHB INTERFACE                                                 //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////

// Address and transfer control
// Priority: new branch detect > cancel restore > sequential
// New branch detect must beat cancel to handle back-to-back branches
// (e.g., not-taken BEQ followed immediately by taken BEQ)
// Slow branches (trap, UOP-JT, FENCE.I) suppress this path: inst_haddr_o falls through
// to {if_pc} for one bubble cycle while if_pc is loaded with the slow target.
assign   inst_haddr_o           =  id_branch_detect_i ? {id_branch_target_i[31:2], 2'b00} :
                                   branch_cancelled   ? {branch_if_pc_saved,       2'b00} :
                                                        {if_pc,                    2'b00} ;

assign   inst_htrans_o          =  2'b10 & {2{aph_ongoing}};                  // NONSEQ

// Static signals on the instruciton bus
assign   inst_hburst_o          =  3'b000;                                    // Single transfer burst
assign   inst_hmastlock_o       =  1'b0;                                      // Unlocked sequence
assign   inst_hprot_o           = {1'b0, 1'b0, |if_priv_mode_i, 1'b0};        // {Non-cacheable; Non-bufferable; Privileged/User access; Opcode-Fetch}
assign   inst_hsmode_o          = (if_priv_mode_i==2'b01);                    // Supervisor-mode access
assign   inst_hsize_o           =  3'b010;                                    // 32-bit access
assign   inst_hwrite_o          =  1'b0;                                      // Read access
assign   inst_hwdata_o          = 32'h00000000;


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                            INSTRUCTION BUFFERS                                                       //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
//
//
//                             Clk0        Clk1           Clk2          Clk3          Clk4          Clk5          Clk6          Clk7          Clk8
//                        |           |             |             |             |             |             |             |             |             |
//  hclk_i                  ───┐      ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐
//                             └──────┘      └──────┘      └──────┘      └──────┘      └──────┘      └──────┘      └──────┘      └──────┘      └──────
//
//  id_pc_o[31:0]                  2000003C         |   20000040  |   20000044  |                       20000048                        |   2000004C
//                          ────────────────────────|─────────────|─────────────|───────────────────────────────────────────────────────|─────────────
//
//  id_instruction_request_i          ┌─────────────────────────────────────────┐                     = 0                 ┌───────────────────────────
//                           ─────────┘                   = 1                   └─────────────────────────────────────────┘
//
//  id_instruction_valid_o  ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
//                                                                                   = 1
//
//  id_instruction_o[31:0]         006F0F33         |   006C0E93  |   03DF0F33  |                       002F1F13                        |   01E48F33
//                          ────────────────────────|─────────────|─────────────|───────────────────────────────────────────────────────|─────────────
//
//                        |           |             |             |             |             |             |             |             |             |
//                             Clk0        Clk1           Clk2          Clk3          Clk4          Clk5          Clk6          Clk7          Clk8
//
//
//--------------------------------------------------------------------------------------------------------------
//
// This 96-bit (six-halfword) shift register handles compressed (16-bit) and standard (32-bit) instruction alignment.
// Instructions are consumed from the bottom [31:0] or [15:0], new data enters from the top.
//
// Buffer organization:  [95:80]  [79:64]  [63:48]  [47:32]  [31:16]  [15:0]
//                      valid[5] valid[4] valid[3] valid[2] valid[1] valid[0]
//
//--------------------------------------------------------------------------------------------------------------

// Ignore incoming AHB data:
//  - On branch cancel with branch_target_fetched: branch target data in flight must be ignored
//  - On branch confirm with ~branch_target_fetched: sequential data in flight must be ignored
//
//   The setter for branch_confirmed & ~branch_target_fetched requires dph_ongoing to be 1.
//   (i.e., a real fetch is in flight that we need to block on its return).
//
wire ignore_incoming_set = (branch_cancelled & ~id_ready &  branch_target_fetched) |
                           (branch_confirmed & ~id_ready & ~branch_target_fetched & dph_ongoing);
wire ignore_incoming_en  = id_ready | ignore_incoming_set;
wire ignore_incoming_nxt = id_ready           ? 1'b0 :
                           ignore_incoming_set ? 1'b1 :
                                                 ignore_incoming;

arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_ignore_incoming (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(ignore_incoming_en), .d_i(ignore_incoming_nxt), .q_o(ignore_incoming));

// Control signals
assign consume_inst  = eff_buf_only ? (id_instruction_request_i & id_instruction_valid_o) : id_instruction_request_i;

// New instruction incoming from AHB:
//  - On cancel cycle: block branch target data (arrived from speculative fetch)
//  - On confirm cycle: block sequential data (stale, buffer will be flushed)
wire   incoming_inst = id_ready & ~ignore_incoming & ~dph_error & ~fetch_fault_freeze
                     & ~(branch_cancelled &  branch_target_fetched)
                     & ~(branch_confirmed & ~branch_target_fetched);

// Next-state logic for valid bits and data buffer
always @(*) begin

    // Default: hold current state; clear on branch confirm (incoming blocked by ignore_incoming, stale data must not persist)
    inst_buf_valid_nxt = branch_confirmed ? 6'b000000 : inst_buf_valid;
    inst_buf_nxt       = inst_buf;

    case (effective_buf_valid)
        //----------------------------------------------------------------------------------------------
        // STATE 000000: Empty buffer
        //----------------------------------------------------------------------------------------------
        6'b000000: begin
            if      (incoming_inst & ~consume_inst & ~incoming_inst_incomplete & ~incoming_upper_is_compressed) begin
                inst_buf_valid_nxt = 6'b000011;                                         // Nothing consumed
                inst_buf_nxt       = {64'h0000000000000000, inst_hrdata_i};              // Save NEW[31:0] to BUF_NXT[31:0]
            end
            else if (incoming_inst & ~consume_inst & ~incoming_inst_incomplete &  incoming_upper_is_compressed) begin
                // Bypass mode (SINGLE_CYCLE_BRANCH=1) or PC[1]=1: lower HW already bypassed to decoder or below current PC -- save upper only
                // Buffer-only mode (SINGLE_CYCLE_BRANCH=0) & PC[1]=0: no bypass, lower HW is the current instruction -- save both
                inst_buf_valid_nxt = (~eff_buf_only | id_pc_o[1]) ? 6'b000001                                        : 6'b000011;
                inst_buf_nxt       = (~eff_buf_only | id_pc_o[1]) ? {80'h00000000000000000000, inst_hrdata_i[31:16]} : {64'h0000000000000000, inst_hrdata_i};
            end
            else if (incoming_inst & ~consume_inst &  incoming_inst_incomplete) begin
                inst_buf_valid_nxt = 6'b000001;                                         // Nothing consumed
                inst_buf_nxt       = {80'h00000000000000000000, inst_hrdata_i[31:16]};  // Save NEW[31:16] to BUF_NXT[15:0]
            end
            else if (incoming_inst &  consume_inst & (incoming_inst_incomplete | incoming_lower_is_compressed)) begin
                inst_buf_valid_nxt = 6'b000001;                                         // Consume NEW[15:0]
                inst_buf_nxt       = {80'h00000000000000000000, inst_hrdata_i[31:16]};  // Save NEW[31:16] to BUF_NXT[15:0]
            end
            else if (incoming_inst &  consume_inst & ~incoming_lower_is_compressed) begin
                inst_buf_valid_nxt = 6'b000000;                                         // Consume NEW[31:0]
                inst_buf_nxt       = 96'h000000000000000000000000;                      // Nothing saved
            end
            else begin
                inst_buf_valid_nxt = 6'b000000;                                         // Stay empty
                inst_buf_nxt       = 96'h000000000000000000000000;                      //
            end
        end

        //----------------------------------------------------------------------------------------------
        // STATE 000001: One 16-bit halfword at [15:0]
        //----------------------------------------------------------------------------------------------
        6'b000001: begin
            if (incoming_inst & ~consume_inst) begin
                inst_buf_valid_nxt = 6'b000111;                                         // Nothing consumed
                inst_buf_nxt       = {48'h000000000000, inst_hrdata_i, inst_buf[15:0]}; // Save NEW[31:0] to BUF_NXT[47:16]
            end
            else if (incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000001;                                         // Consume {NEW[15:0], BUF[15:0]}
                inst_buf_nxt       = {80'h00000000000000000000, inst_hrdata_i[31:16]};  // Save NEW[31:16] to BUF_NXT[15:0]
            end
            else if (incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000011;                                         // Consume BUF[15:0]
                inst_buf_nxt       = {64'h0000000000000000, inst_hrdata_i};             // Save NEW[31:0] to BUF_NXT[31:0]
            end
            else if (~incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000001;                                         // Not enough data to consume
                inst_buf_nxt       = inst_buf;                                          //
            end
            else if (~incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000000;                                         // Consume BUF[15:0]
                inst_buf_nxt       = 96'h000000000000000000000000;                      //
            end
            else begin
                inst_buf_valid_nxt = 6'b000001;                                         // No change
                inst_buf_nxt       = inst_buf;                                          //
            end
        end

        //----------------------------------------------------------------------------------------------
        // STATE 000011: One 32-bit word at [31:0]
        //----------------------------------------------------------------------------------------------
        6'b000011: begin
            if (incoming_inst & ~consume_inst) begin
                inst_buf_valid_nxt = 6'b001111;                                         // Nothing consumed
                inst_buf_nxt       = {32'h00000000, inst_hrdata_i, inst_buf[31:0]};     // Save NEW[31:0] to BUF_NXT[63:32]
            end
            else if (incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000011;                                         // Consume BUF[31:0]
                inst_buf_nxt       = {64'h0000000000000000, inst_hrdata_i};             // Save NEW[31:0] to BUF_NXT[31:0]
            end
            else if (incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000111;                                         // Consume BUF[15:0]
                inst_buf_nxt       = {48'h000000000000, inst_hrdata_i, inst_buf[31:16]};// Shift 16, Save NEW[31:0] to BUF_NXT[47:16]
            end
            else if (~incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000000;                                         // Consume BUF[31:0]
                inst_buf_nxt       = 96'h000000000000000000000000;                      //
            end
            else if (~incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000001;                                         // Consume BUF[15:0]
                inst_buf_nxt       = {80'h00000000000000000000, inst_buf[31:16]};       // Shift 16
            end
            else begin
                inst_buf_valid_nxt = 6'b000011;                                         // No change
                inst_buf_nxt       = inst_buf;                                          //
            end
        end

        //----------------------------------------------------------------------------------------------
        // STATE 000111: Three halfwords (48 bits) at [47:0]
        //----------------------------------------------------------------------------------------------
        6'b000111: begin
            if (incoming_inst & ~consume_inst) begin
                inst_buf_valid_nxt = 6'b011111;                                         // Nothing consumed
                inst_buf_nxt       = {16'h0000, inst_hrdata_i, inst_buf[47:0]};         // Save NEW[31:0] to BUF_NXT[79:48]
            end
            else if (incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000111;                                         // Consume BUF[31:0], add NEW
                inst_buf_nxt       = {48'h000000000000, inst_hrdata_i, inst_buf[47:32]};// Shift 32, Save NEW[31:0] to BUF_NXT[47:16]
            end
            else if (incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b001111;                                         // Consume BUF[15:0], add NEW
                inst_buf_nxt       = {32'h00000000, inst_hrdata_i, inst_buf[47:16]};    // Shift 16, Save NEW[31:0] to BUF_NXT[63:32]
            end
            else if (~incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000001;                                         // Consume BUF[31:0]
                inst_buf_nxt       = {80'h00000000000000000000, inst_buf[47:32]};       // Shift 32
            end
            else if (~incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000011;                                         // Consume BUF[15:0]
                inst_buf_nxt       = {64'h0000000000000000, inst_buf[47:16]};           // Shift 16
            end
            else begin
                inst_buf_valid_nxt = 6'b000111;                                         // No change
                inst_buf_nxt       = inst_buf;                                          //
            end
        end

        //----------------------------------------------------------------------------------------------
        // STATE 001111: Four halfwords (64 bits) at [63:0]
        //----------------------------------------------------------------------------------------------
        6'b001111: begin
            if (incoming_inst & ~consume_inst) begin
                inst_buf_valid_nxt = 6'b111111;                                         // Nothing consumed
                inst_buf_nxt       = {inst_hrdata_i, inst_buf[63:0]};                   // Save NEW[31:0] to BUF_NXT[95:64]
            end
            else if (incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b001111;                                         // Consume BUF[31:0], add NEW
                inst_buf_nxt       = {32'h00000000, inst_hrdata_i, inst_buf[63:32]};    // Shift 32, Save NEW[31:0] to BUF_NXT[63:32]
            end
            else if (incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b011111;                                         // Consume BUF[15:0], add NEW
                inst_buf_nxt       = {16'h0000, inst_hrdata_i, inst_buf[63:16]};        // Shift 16, Save NEW[31:0] to BUF_NXT[79:48]
            end
            else if (~incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000011;                                         // Consume BUF[31:0]
                inst_buf_nxt       = {64'h0000000000000000, inst_buf[63:32]};           // Shift 32
            end
            else if (~incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000111;                                         // Consume BUF[15:0]
                inst_buf_nxt       = {48'h000000000000, inst_buf[63:16]};               // Shift 16
            end
            else begin
                inst_buf_valid_nxt = 6'b001111;                                         // No change
                inst_buf_nxt       = inst_buf;                                          //
            end
        end

        //----------------------------------------------------------------------------------------------
        // STATE 011111: Five halfwords (80 bits) at [79:0]
        //----------------------------------------------------------------------------------------------
        6'b011111: begin
            if (incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b011111;                                         // Consume BUF[31:0], add NEW
                inst_buf_nxt       = {16'h0000, inst_hrdata_i, inst_buf[79:32]};        // Shift 32, Save NEW[31:0] to BUF_NXT[79:48]
            end
            else if (incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b111111;                                         // Consume BUF[15:0], add NEW
                inst_buf_nxt       = {inst_hrdata_i, inst_buf[79:16]};                  // Shift 16, Save NEW[31:0] to BUF_NXT[95:64]
            end
            else if (~incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b000111;                                         // Consume BUF[31:0]
                inst_buf_nxt       = {48'h000000000000, inst_buf[79:32]};               // Shift 32
            end
            else if (~incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b001111;                                         // Consume BUF[15:0]
                inst_buf_nxt       = {32'h00000000, inst_buf[79:16]};                   // Shift 16
            end
            else begin
                inst_buf_valid_nxt = 6'b011111;                                         // No change
                inst_buf_nxt       = inst_buf;                                          //
            end
        end

        //----------------------------------------------------------------------------------------------
        // STATE 111111: Full buffer -- six halfwords (96 bits) at [95:0]
        //----------------------------------------------------------------------------------------------
        6'b111111: begin
            if (incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b111111;                                         // Consume BUF[31:0], absorb incoming
                inst_buf_nxt       = {inst_hrdata_i, inst_buf[95:32]};                  // Shift 32, load incoming
            end
            else if (incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b011111;                                         // Consume BUF[15:0], drop incoming (buffer still has 5 slots)
                inst_buf_nxt       = {16'h0000, inst_buf[95:16]};                       // Shift 16, drop incoming (would overflow)
            end
            else if (~incoming_inst & consume_inst & ~buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b001111;                                         // Consume BUF[31:0]
                inst_buf_nxt       = {32'h00000000, inst_buf[95:32]};                   // Shift 32
            end
            else if (~incoming_inst & consume_inst & buffered_is_compressed) begin
                inst_buf_valid_nxt = 6'b011111;                                         // Consume BUF[15:0]
                inst_buf_nxt       = {16'h0000, inst_buf[95:16]};                       // Shift 16
            end
            else begin
                inst_buf_valid_nxt = 6'b111111;                                         // No change
                inst_buf_nxt       = inst_buf;                                          //
            end
        end

        //----------------------------------------------------------------------------------------------
        // Other states (shouldn't occur)
        //----------------------------------------------------------------------------------------------
        default: begin
            inst_buf_valid_nxt = inst_buf_valid;
            inst_buf_nxt       = inst_buf;
        end
    endcase
end

// Buffer full detection - stop AHB when upper buffer slots will be occupied.
// Override on branch detect / branch_pending (need to fetch target immediately).
assign buf_will_be_full  =  (inst_buf_valid_nxt[5] |   inst_buf_valid_nxt[4]                  ) &
                           ~(id_any_branch_detect  | (~inst_buf_valid_nxt[4] & branch_pending)) ;


//--------------------------------------------------------------------------------------------------------------
// Buffer data and valid bit registers
//--------------------------------------------------------------------------------------------------------------

arv_dff #(.WIDTH(6), .ARST_EN(ARST_EN)) u_inst_buf_valid (
                     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(inst_buf_valid_nxt), .q_o(inst_buf_valid));

arv_dff #(.WIDTH(96), .ARST_EN(ARST_EN)) u_inst_buf (
                     .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(1'b1), .d_i(inst_buf_nxt),       .q_o(inst_buf));


//////======================================================================================================================//////
//////======================================================================================================================//////
//////                                                                                                                      //////
//////                                            INSTRUCTION TO DECODER                                                    //////
//////                                                                                                                      //////
//////======================================================================================================================//////
//////======================================================================================================================//////
// Note: decoder always reads compressed instructions from bits [15:0]

// Buffer-only mode (SINGLE_CYCLE_BRANCH=0): inst_hrdata_i never bypasses to the decoder.
//   All instruction data comes from the registered inst_buf, which breaks the
//   inst_hrdata_i -> [branch decode] -> inst_haddr_o loop since id_branch_detect_i is
//   derived from inst_buf (registered), not inst_hrdata_i.
//   Trade-off: 1 extra bubble cycle when the buffer is empty (e.g. after a branch).
//
// Bypass mode (SINGLE_CYCLE_BRANCH=1): when the buffer is empty, inst_hrdata_i feeds the
//   decoder directly, hiding the AHB round-trip latency.

// Split on SINGLE_CYCLE_BRANCH in two generate branch to remove warning in synthesis.
generate
    if (SINGLE_CYCLE_BRANCH == 1'b0) begin : g_id_instruction_buf_only
        // Buffer-only (SINGLE_CYCLE_BRANCH=0): always read from registered buffer
        assign id_instruction_o = inst_buf[31:0];

    end else begin : g_id_instruction_bypass
        // Bypass (SINGLE_CYCLE_BRANCH=1): buffer path with AHB-data bypass when buffer empty.
        wire   id_pc_b1_msk     =  (C_EXT_EN & id_pc_o[1]);
        assign id_instruction_o =  // Case where we have LSBs of a 32b instruction in the buffer but still missing the MSB
                                   (~branch_confirmed & ~buffered_is_compressed & (inst_buf_valid[1:0]==2'b01)) ? {inst_hrdata_i[15:0], inst_buf[15:0]}        :

                                   // Else we give the whole buffer (if there is something in the buffer)
                                   (~branch_confirmed & inst_buf_valid[0])                                      ?  inst_buf[31:0]                              :

                                   // Buffer empty, address 16b-aligned: present upper half (compressed or don't-care for 32b incomplete)
                                     id_pc_b1_msk                                                               ? {inst_hrdata_i[31:16], inst_hrdata_i[31:16]} :

                                   // Buffer empty, address 32b-aligned: bypass AHB data directly
                                                                                                                   inst_hrdata_i;
    end
endgenerate

// Check for incomplete instruction:
assign buffered_inst_incomplete = (inst_buf_valid[1:0]==2'b01)                & ~buffered_is_compressed      ; // Only lower 16 bits available but instruction is non-compressed
assign incoming_inst_incomplete = (effective_buf_valid[0]==1'b0) & id_pc_o[1] & ~incoming_upper_is_compressed; // Buffer empty, address 16b aligned, incoming instruction is non-compressed

// Instruction valid:
// Bypass mode (SINGLE_CYCLE_BRANCH=1): buffer path OR bypass path (incoming AHB data when buffer empty)
// Buffer-only mode (SINGLE_CYCLE_BRANCH=0): buffer path only -- buffer must hold data before decoder sees an instruction
assign id_instruction_valid_o   =  ~if_excp_inst_address_misaligned_o &
                                  (eff_buf_only ?  (inst_buf_valid[0] & ~branch_confirmed & ~buffered_inst_incomplete)
                                                : ((inst_buf_valid[0] & ~branch_confirmed & ~buffered_inst_incomplete) |
                                                   (incoming_inst     & ~incoming_inst_incomplete)                    ));


// Privileged mode: latched at end of address phase.
// Privilege mode changes (traps, MRET, SRET) flush the pipeline via the branch mechanism
arv_dff #(.WIDTH(2), .RST_VAL(2'b11), .ARST_EN(ARST_EN)) u_id_priv_mode (
                                    .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(aph_valid), .d_i(if_priv_mode_i), .q_o(id_priv_mode_o));


//////======================================================================================================================//////

// Error Detection
// Misalignment: For C extension, only bit[0] matters (2-byte aligned OK); otherwise 4-byte aligned required
assign   if_excp_inst_address_misaligned_o = (C_EXT_EN ? id_pc_o[0] : (id_pc_o[1:0]!=2'b00));

// Instruction access fault: PRECISE-EXCEPTION deferral.
//
// dph_error / fetch_fault_freeze become sticky-pending on the AHB error, but the
// fault must NOT be reported until every pre-fault parcel still buffered between
// the decode head and the erroring fetch has retired in program order.
//
// Two disjoint drain conditions release the deferred fault:
//   - fetch_buf_drained        (inst_buf_valid == 000000): all pre-fault parcels
//     retired; the next thing the decoder would see is the erroring fetch itself.
//   - buffered_inst_incomplete (inst_buf_valid[1:0] == 2'b01 & ~compressed):
//     a STRADDLING 32-bit instruction whose lower parcel sits at A in valid
//     memory while its upper parcel fetch (A+2) errored.
//
// UOP-final-branch hold (~ex_uop_has_branch_i): a CM.POPRET / CM.POPRETZ /
// CM.JT / CM.JALT is an UNCONDITIONAL UOP-final branch whose own branch
// resolves only after its multi-cycle micro-op sequence (e.g. the POPRET
// stack pop) completes, several cycles after dispatch.
wire     fault_pending                     =  dph_error | fetch_fault_freeze;
wire     fetch_buf_drained                 = (inst_buf_valid == 6'b000000);
assign   id_excp_inst_access_fault_o       =  fault_pending & (fetch_buf_drained | buffered_inst_incomplete) & ~ex_uop_has_branch_i;

// Faulting-fetch byte address for mtval (RISC-V Priv. spec 3.1.16):
//   "the virtual address of the portion of the instruction that caused the fault".
assign   id_inst_fault_addr_o              =  id_pc_o + (buffered_inst_incomplete ? 32'd2 : 32'd0);

endmodule // arv_fetch

`default_nettype wire

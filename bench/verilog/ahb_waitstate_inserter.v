//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    ahb_waitstate_inserter
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : ahb_waitstate_inserter.v
// Module Description : Slave-side wait-state injector (random or fixed) for stress testing.
//----------------------------------------------------------------------------

`include "timescale.v"

module ahb_waitstate_inserter #(
// PARAMETERs
//======================================
    parameter              HAUSER_W = 1,              // Width of the HAUSER bus (min value is 1)

// HREADY_HOLDS_APH selects how the buffered address phase reacts to the
// bus HREADY handed to this subordinate (hready_i):
//
//   1 (default) - AHB-Lite reference style (IHI0033C slave example): the
//                 address-phase register is clocked by HREADY. A cycle with
//                 HREADY=1 and no valid transfer (hsel=0 or IDLE) clears the
//                 held transfer. Behind a compliant fabric this is a no-op,
//                 because HREADY is 0 for the whole of our own wait state.
//                 Behind a fabric that hands us HREADY=1 while we stall, the
//                 transfer being served is forgotten and the read returns
//                 garbage -- which is exactly what the regression must see.
//   0           - Legacy self-timed style: capture on hsel & hready & htrans[1]
//                 only, never cleared. Immune to a wrong HREADY by
//                 construction (ahb_rom_controller / ahb_sram_controller
//                 style).
    parameter              HREADY_HOLDS_APH = 1
) (

// AHB CLOCK & RESET
    input  wire            hclk_i,
    input  wire            hresetn_i,
    output wire            hclk_en_o,

    input  wire     [31:0] number_ws_i,
    input  wire            random_ws_en_i,

// AHB INTERFACE (TO FABRIC OR MANAGER)
    input  wire     [31:0] haddr_i,
    input  wire [HAUSER_W-1:0] hauser_i,
    input  wire      [3:0] hprot_i,
    input  wire            hready_i,
    input  wire      [2:0] hsize_i,
    input  wire      [1:0] htrans_i,
    input  wire     [31:0] hwdata_i,
    input  wire            hwrite_i,
    input  wire            hsel_i,
    output wire     [31:0] hrdata_o,
    output wire            hreadyout_o,
    output wire            hresp_o,

// AHB INTERFACE (TO AHB SUBORDINATE)
    output wire     [31:0] s_haddr_o,
    output wire [HAUSER_W-1:0] s_hauser_o,
    output wire      [3:0] s_hprot_o,
    output wire            s_hready_o,
    output wire      [2:0] s_hsize_o,
    output wire      [1:0] s_htrans_o,
    output wire     [31:0] s_hwdata_o,
    output wire            s_hwrite_o,
    output wire            s_hsel_o,
    input  wire     [31:0] s_hrdata_i,
    input  wire            s_hreadyout_i,
    input  wire            s_hresp_i
);


//=============================================================================
// 1)  INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION
//=============================================================================

wire                   enable_wait_states;

wire                   aph_valid;
reg             [31:0] aph_wait_nxt;
reg             [31:0] aph_wait_cnt;

wire                   ahb_buffer_sel;
wire                   aph_transparent;
wire                   dph_transparent;

reg             [31:0] buf_haddr;
reg     [HAUSER_W-1:0] buf_hauser;
reg              [3:0] buf_hprot;
reg                    buf_hready;
reg              [2:0] buf_hsize;
reg              [1:0] buf_htrans;
reg                    buf_hwrite;
reg                    buf_hsel;

// ERR-WORD INJECTION HOOK (verification feature -- inert by default).
// Set hierarchically from a test's .v stimulus, e.g.:
//   ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_addr = 32'h8000F004;
//   ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_ws   = 32'd3;
//   ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_en   = 1'b1;
// A READ of the word at err_word_addr is squashed downstream and answered with
// err_word_ws OKAY wait cycles followed by a standard 2-cycle AHB ERROR.
// Intended for zero-wait-state (base variant) runs; see doc/verification_guide.md §6, "err_word hook".
reg                    err_word_en   = 1'b0;         // default: feature disabled
reg             [31:0] err_word_addr = 32'hFFFFFFFF; // word compare on [31:2]
reg             [31:0] err_word_ws   = 32'd0;        // OKAY wait cycles before ERROR

localparam       [1:0] ERR_IDLE = 2'd0,
                       ERR_WAIT = 2'd1,
                       ERR_PH1  = 2'd2,
                       ERR_PH2  = 2'd3;

reg              [1:0] err_state;
reg             [31:0] err_cnt;
wire                   err_aph_match;
wire                   err_active;


//=============================================================================
// 2)  DETECT IF WAIT STATE AND BUFFER SIGNALS
//=============================================================================

assign enable_wait_states = (number_ws_i!=0);

// Detect end of address phase
assign  aph_valid         = hsel_i && hready_i && htrans_i[1];

// Wait state control
always @(posedge hclk_i or negedge hresetn_i) begin
    if (!hresetn_i) begin
        aph_wait_nxt    <= enable_wait_states ? (random_ws_en_i ? $urandom_range(0, number_ws_i+1) : number_ws_i) : 0;
        aph_wait_cnt    <= 0;
    
    end else if (aph_valid) begin
        aph_wait_nxt    <= enable_wait_states ? (random_ws_en_i ? $urandom_range(0, number_ws_i+1) : number_ws_i) : 0;
        aph_wait_cnt    <= aph_wait_nxt;

    end else if (aph_wait_cnt!=0) begin
        aph_wait_cnt    <= aph_wait_cnt-1;
    end
end

// Control the address phase muxes and data phase muxes
assign  ahb_buffer_sel   = (aph_wait_cnt==1);
assign  aph_transparent  = (aph_wait_cnt==0) && (aph_wait_nxt==0);
assign  dph_transparent  = (aph_wait_cnt==0);

// State register
always @(posedge hclk_i or negedge hresetn_i) begin
    if (!hresetn_i) begin
        buf_haddr       <=  32'h00000000; 
        buf_hauser      <=  {HAUSER_W{1'b0}};
        buf_hprot       <=   4'b0000;
        buf_hready      <=   1'b1;
        buf_hsize       <=   3'b000;
        buf_htrans      <=   2'b00;
        buf_hwrite      <=   1'b0;
        buf_hsel        <=   1'b0;
    end else if (aph_valid && !err_aph_match) begin   // err-word: never buffer a squashed aph
        buf_haddr       <=  haddr_i;
        buf_hauser      <=  hauser_i;
        buf_hprot       <=  hprot_i;
        buf_hready      <=  hready_i;
        buf_hsize       <=  hsize_i;
        buf_htrans      <=  htrans_i;
        buf_hwrite      <=  hwrite_i;
        buf_hsel        <=  hsel_i;
    end else if (HREADY_HOLDS_APH && hready_i) begin
        // Reference-style subordinate: HREADY=1 with no transfer presented
        // loads "no transfer" into the address-phase register.
        buf_hsel        <=  1'b0;
        buf_htrans      <=  2'b00;
    end
end

assign  hclk_en_o        =  aph_valid | (aph_wait_cnt!=0) | err_active;


//=============================================================================
// 2a) PROTOCOL CHECK: A STALLING SUBORDINATE MUST SEE HREADY=0
//=============================================================================
// IHI0033C: the HREADY input of a subordinate is the combined bus HREADY,
// and the subordinate holding the data phase with HREADYOUT=0 *is* the bus.
// So whenever this model drives hreadyout_o=0, the HREADY the fabric hands
// back on hready_i must be 0 in the same cycle. Independent of the
// HREADY_HOLDS_APH style above. Counted per instance; the bench can sum the
// counters into its error total (`<inst>.hready_viol_cnt`).

integer hready_viol_cnt;
initial hready_viol_cnt = 0;

always @(posedge hclk_i) begin
    if (hresetn_i && !hreadyout_o && hready_i) begin
        hready_viol_cnt = hready_viol_cnt + 1;
        if (hready_viol_cnt <= 8)
            $display("ERROR: %m: subordinate stalling (hreadyout_o=0) but fabric drives hready_i=1 %t", $time);
        else if (hready_viol_cnt == 9)
            $display("ERROR: %m: ... further hready_i violations not printed");
    end
end

//=============================================================================
// 2b)  ERR-WORD INJECTION FSM  (inert while err_word_en==0)
//=============================================================================

// Address-phase READ hitting the armed word (writes never match, so tests can
// build code at the armed address before arming, and data stores never trip it).
assign  err_aph_match = err_word_en && hsel_i && hready_i && htrans_i[1] &&
                        !hwrite_i   && (haddr_i[31:2] == err_word_addr[31:2]);
assign  err_active    = (err_state != ERR_IDLE);

always @(posedge hclk_i or negedge hresetn_i) begin
    if (!hresetn_i) begin
        err_state <= ERR_IDLE;
        err_cnt   <= 32'd0;
    end else begin
        case (err_state)
            // ERR_PH2 completes with hreadyout=1, so a new address phase can
            // finish in that cycle and immediately re-trigger (fetch retry of
            // the same armed word) -- handle IDLE and PH2 identically.
            ERR_IDLE,
            ERR_PH2: begin
                if (err_aph_match) begin
                    if (err_word_ws == 32'd0) begin
                        err_state <= ERR_PH1;
                    end else begin
                        err_cnt   <= err_word_ws;
                        err_state <= ERR_WAIT;
                    end
                end else if (err_state == ERR_PH2) begin
                    err_state <= ERR_IDLE;
                end
            end
            ERR_WAIT: begin                       // err_word_ws OKAY wait cycles
                if (err_cnt <= 32'd1) err_state <= ERR_PH1;
                err_cnt <= err_cnt - 32'd1;
            end
            ERR_PH1: err_state <= ERR_PH2;        // ERROR cycle 1 (hreadyout=0)
            default: err_state <= ERR_IDLE;
        endcase
    end
end


//=============================================================================
// 3)  CONTROL MUXES FOR ADDRESS/DATA PHASE SIGNALS
//=============================================================================

// Address Phase signals
assign   s_haddr_o       =  (aph_transparent ?  haddr_i       :  (ahb_buffer_sel ?  buf_haddr   :  32'h00000000   )); 
assign   s_hauser_o      =  (aph_transparent ?  hauser_i      :  (ahb_buffer_sel ?  buf_hauser  : {HAUSER_W{1'b0}}));
assign   s_hprot_o       =  (aph_transparent ?  hprot_i       :  (ahb_buffer_sel ?  buf_hprot   :   4'b0000       ));
// HREADY into the subordinate: the bus HREADY whenever the subordinate may be in a data
// phase (dph_transparent) -- a multi-cycle response such as the two-cycle ERROR depends
// on it -- and the buffered value only while the delayed address phase is replayed.
assign   s_hready_o      =  (dph_transparent ?  hready_i      :  (ahb_buffer_sel ?  buf_hready  :   1'b1          ));
assign   s_hsize_o       =  (aph_transparent ?  hsize_i       :  (ahb_buffer_sel ?  buf_hsize   :   3'b000        ));
assign   s_htrans_o      = ((aph_transparent ?  htrans_i      :  (ahb_buffer_sel ?  buf_htrans  :   2'b00         )) & {2{~err_aph_match}}); // err-word: squash the erroring aph
assign   s_hwrite_o      =  (aph_transparent ?  hwrite_i      :  (ahb_buffer_sel ?  buf_hwrite  :   1'b0          ));
assign   s_hsel_o        = ((aph_transparent ?  hsel_i        :  (ahb_buffer_sel ?  buf_hsel    :   1'b0          )) &     ~err_aph_match ); // err-word: squash the erroring aph

// Data Phase signals
assign   s_hwdata_o      =  (dph_transparent ?  hwdata_i      :   32'h00000000   );
assign   hrdata_o        =  err_active ?  32'h00000000                                  : (dph_transparent ?  s_hrdata_i    :   32'h00000000   );
assign   hresp_o         =  err_active ? ((err_state==ERR_PH1) | (err_state==ERR_PH2)) : (dph_transparent ?  s_hresp_i     :    1'b0          );
assign   hreadyout_o     =  err_active ?  (err_state==ERR_PH2)                         : (dph_transparent ?  s_hreadyout_i :    1'b0          );


endmodule

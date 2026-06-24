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

module ahb_waitstate_inserter #(
// PARAMETERs
//======================================
    parameter              HAUSER_W = 1               // Width of the HAUSER bus (min value is 1)
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
    end else if (aph_valid) begin
        buf_haddr       <=  haddr_i; 
        buf_hauser      <=  hauser_i;
        buf_hprot       <=  hprot_i;
        buf_hready      <=  hready_i;
        buf_hsize       <=  hsize_i;
        buf_htrans      <=  htrans_i;
        buf_hwrite      <=  hwrite_i;
        buf_hsel        <=  hsel_i;
    end
end

assign  hclk_en_o        =  aph_valid | (aph_wait_cnt!=0);


//=============================================================================
// 3)  CONTROL MUXES FOR ADDRESS/DATA PHASE SIGNALS
//=============================================================================

// Address Phase signals
assign   s_haddr_o       =  (aph_transparent ?  haddr_i       :  (ahb_buffer_sel ?  buf_haddr   :  32'h00000000   )); 
assign   s_hauser_o      =  (aph_transparent ?  hauser_i      :  (ahb_buffer_sel ?  buf_hauser  : {HAUSER_W{1'b0}}));
assign   s_hprot_o       =  (aph_transparent ?  hprot_i       :  (ahb_buffer_sel ?  buf_hprot   :   4'b0000       ));
assign   s_hready_o      =  (aph_transparent ?  hready_i      :  (ahb_buffer_sel ?  buf_hready  :   1'b1          ));
assign   s_hsize_o       =  (aph_transparent ?  hsize_i       :  (ahb_buffer_sel ?  buf_hsize   :   3'b000        ));
assign   s_htrans_o      =  (aph_transparent ?  htrans_i      :  (ahb_buffer_sel ?  buf_htrans  :   2'b00         ));
assign   s_hwrite_o      =  (aph_transparent ?  hwrite_i      :  (ahb_buffer_sel ?  buf_hwrite  :   1'b0          ));
assign   s_hsel_o        =  (aph_transparent ?  hsel_i        :  (ahb_buffer_sel ?  buf_hsel    :   1'b0          ));  

// Data Phase signals
assign   s_hwdata_o      =  (dph_transparent ?  hwdata_i      :   32'h00000000   );
assign   hrdata_o        =  (dph_transparent ?  s_hrdata_i    :   32'h00000000   );
assign   hresp_o         =  (dph_transparent ?  s_hresp_i     :    1'b0          );
assign   hreadyout_o     =  (dph_transparent ?  s_hreadyout_i :    1'b0          );


endmodule

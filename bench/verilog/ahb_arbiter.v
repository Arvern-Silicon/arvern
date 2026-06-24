//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    ahb_arbiter
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : ahb_arbiter.v
// Module Description : Behavioural 2-master AHB arbiter for the testbench.
//----------------------------------------------------------------------------

module  ahb_arbiter (

// AHB CLOCK & RESET
    input  wire       hclk_i,
    input  wire       hresetn_i,

// ARBITER INTERFACES
    input  wire [1:0] request_i,
    output wire [1:0] grant_o
);


//=============================================================================
// 1)  INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION
//=============================================================================

reg             last_grant;
wire            last_grant_nxt;


//=============================================================================
// 2)  ARBITER LOGIC
//=============================================================================

assign          grant_o        = (request_i == 2'b01) ? 2'b01 : ((request_i == 2'b10) ? 2'b10 : ((request_i == 2'b11) ? {~last_grant, last_grant} : 2'b00     ));
assign          last_grant_nxt = (request_i == 2'b01) ? 1'b0  : ((request_i == 2'b10) ? 1'b1  : ((request_i == 2'b11) ?  ~last_grant              : last_grant));

always @(posedge hclk_i or negedge hresetn_i)
    if (!hresetn_i) last_grant <= 1'b1;
    else            last_grant <= last_grant_nxt;

endmodule

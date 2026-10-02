//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_dff_sinit
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_dff_sinit.v
// Module Description : arv_dff plus a synchronous init: on top of the primary
//                      reset (rst_n_i, async/sync per ARST_EN), an active-high
//                      sinit_i synchronously reloads RST_VAL. Lets a datapath-
//                      derived soft reset ride clock-sampled logic (scannable,
//                      glitch-immune) instead of a gated async reset.
//----------------------------------------------------------------------------
`default_nettype none

module  arv_dff_sinit #(
    parameter               WIDTH   = 1,             // register width
    parameter   [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}, // reset / init value
    parameter               ARST_EN = 1'b1           // 1=async active-low reset, 0=synchronous reset
) (
    input  wire             clk_i,                   // clock
    input  wire             rst_n_i,                 // active-low reset (async assert if ARST_EN=1, else sync)
    input  wire             sinit_i,                 // active-high synchronous init to RST_VAL
    input  wire             en_i,                    // load enable (hold when 0)
    input  wire [WIDTH-1:0] d_i,                     // next-state
    output reg  [WIDTH-1:0] q_o                      // registered output
);

generate
    if (ARST_EN) begin : g_async_rst
        // Async-reset flop; sinit_i is sampled synchronously on the clock edge.
        always @(posedge clk_i or negedge rst_n_i)
            if      (rst_n_i == 1'b0) q_o <= RST_VAL;
            else if (sinit_i == 1'b1) q_o <= RST_VAL;
            else if (en_i    == 1'b1) q_o <= d_i;
    end else begin : g_sync_rst
        // No async edge term -> sync-reset flop; rst_n_i and sinit_i both clock-sampled.
        always @(posedge clk_i)
            if      (rst_n_i == 1'b0) q_o <= RST_VAL;
            else if (sinit_i == 1'b1) q_o <= RST_VAL;
            else if (en_i    == 1'b1) q_o <= d_i;
    end
endgenerate

endmodule // arv_dff_sinit

`default_nettype wire

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    osc
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : osc.v
// Module Description : Behavioural gateable free-running oscillator model
//                      for the aRVern testbench. Used to drive the SoC's
//                      main AHB-frequency oscillator and the ACLINT's
//                      always-on low-frequency oscillator.
//----------------------------------------------------------------------------

`include "timescale.v"

module  osc #(
    parameter integer HALF_PERIOD  = 500,   // Half-period in timescale units (full clock period = 2 * HALF_PERIOD)
    parameter integer PHASE_OFFSET = 0      // One-shot initial delay before the loop starts, in timescale units
) (
    input  wire enable_i,   // Synchronous enable, sampled into en_q on negedge clk_o
    input  wire resetn_i,   // Active-low global reset (asynchronously presets en_q to 1)
    input  wire wake_i,     // Asynchronous wake-up      (asynchronously presets en_q to 1)
    output reg  clk_o       // Oscillator output: paused low while en_q is 0, toggling while en_q is 1
);


// Falling-edge sampled enable register with async preset on resetn_i=0 and wake_i=1.
reg     en_q;
always @(negedge clk_o or negedge resetn_i or posedge wake_i) begin
    if (!resetn_i)   en_q = 1'b1;
    else if (wake_i) en_q = 1'b1;
    else             en_q = enable_i;
end

// Forever loop drives clk_o directly. wait(en_q) pauses the loop at clk_o=0 while
// the oscillator is gated; an async preset of en_q (reset/wake) wakes the wait and
// the next half period begins cleanly from low.
initial begin
    clk_o = 1'b0;
    #(PHASE_OFFSET);
    forever begin
        wait(en_q);
        #(HALF_PERIOD);
        clk_o = 1'b1;
        #(HALF_PERIOD);
        clk_o = 1'b0;
    end
end

endmodule

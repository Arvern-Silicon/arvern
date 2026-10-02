//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    reset_gen
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : reset_gen.v
// Module Description : Testbench reset generator. Takes a single raw async
//                      power-on reset pulse (porn_async_i, active-low) and
//                      produces the synchronized resets the DUT + testbench need.
//
//                      Models the SoC halt-on-reset (resethaltreq) contract, in
//                      which an ndmreset resets ONLY the hart:
//                        - porn      : power-on-only reset for ALWAYS-ON FLOPS in the
//                                      free_clk domain (the ACLINT mtime real-time
//                                      counter). Synchronized to free_clk, survives an
//                                      ndmreset. Everything else in the system (AHB
//                                      interconnect/memory/peripherals/checkers) resets
//                                      on ndmreset via hresetn - spec-correct ("reset
//                                      all but the DM"); SRAM/ROM array contents survive
//                                      on their own (the models clear arrays only at init).
//                      The CLOCK SOURCES (oscillators) are reset directly by porn_async_i,
//                      NOT by porn: porn is synchronized to the very clock the oscillator
//                      generates, so feeding it back as the oscillator's reset would be
//                      circular. A clock source is not a flop in its own domain -> raw
//                      async reset. porn_async_i is POR-only, so clocks survive ndmreset too.
//                        - hresetn   : the HART reset = POR | ndmreset. Drives the
//                                      DUT's hresetn_i (and hart-associated checkers),
//                                      so the debugger's dmcontrol.ndmreset
//                                      (dbg_ndmreset) resets the hart while everything
//                                      else keeps running.
//                        - dbgresetn : the Debug-Module reset = POR-only. Drives the
//                                      DUT's dbgresetn_i, so the DM (and resethaltreq)
//                                      survive an ndmreset and the debugger stays
//                                      connected. (Same value as porn, kept as a
//                                      distinct port for semantic clarity.)
//                        - resetn_lf : the low-frequency-domain reset (POR-only).
//                      When dbg_ndmreset=0, hresetn == porn (transparent to every
//                      non-reset-halt test).
//
//                      Each output is asynchronously ASSERTED on ~porn_async_i and
//                      released through a 2-FF synchronizer on the falling edge of
//                      its own clock (clk_lf for resetn_lf, free_clk for the rest).
//----------------------------------------------------------------------------

module reset_gen (
    input  wire porn_async_i,    // raw async power-on reset, active-low
    input  wire clk_lf,          // low-frequency clock
    input  wire free_clk,        // always-on AHB-domain clock
    input  wire dbg_ndmreset,    // DM ndmreset request (dmcontrol[1]) -> resets the hart only

    output wire resetn_lf,       // LF-domain reset        (POR-only, synced to clk_lf)
    output wire porn,            // system reset           (POR-only, synced to free_clk; survives ndmreset)
    output wire hresetn,         // HART reset = POR | ndmreset (synced to free_clk)
    output wire dbgresetn        // DEBUG-module reset     (POR-only; survives ndmreset)
);

// AHB-domain 2-FF reset synchronizer -> the synchronized power-on reset to the free_clk domain.
reg [1:0] porn_sync;
always @(negedge free_clk or negedge porn_async_i)
  if (!porn_async_i) porn_sync    <= 2'b00;
  else               porn_sync    <= {porn_sync[0], 1'b1};

assign porn      = porn_sync[1];
assign dbgresetn = porn_sync[1];


// LF-domain 2-FF reset synchronizer (async assert on ~porn_async_i, release on negedge clk_lf).
reg [1:0] porn_lf_sync;
always @(negedge clk_lf or negedge porn_async_i)
  if (!porn_async_i) porn_lf_sync <= 2'b00;
  else               porn_lf_sync <= {porn_lf_sync[0], 1'b1};

assign resetn_lf = porn_lf_sync[1];


// Hart reset = POR | ndmreset. The hart's hresetn_i is driven by this signal, so the debugger's
reg [1:0] hresetn_sync;
always @(negedge free_clk or negedge porn_async_i)
  if (!porn_async_i) hresetn_sync    <= 2'b00;
  else               hresetn_sync    <= {hresetn_sync[0], ~dbg_ndmreset};

assign hresetn   = porn & ~dbg_ndmreset;


endmodule

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_csr_hpm
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_csr_hpm.v
// Module Description : RISC-V CSRs: Zihpm hardware performance monitors (mhpmcounter3-10 / mhpmevent3-10)
//----------------------------------------------------------------------------
`default_nettype none

module  arv_csr_hpm (

// AHB CLOCK & RESET
    input  wire           hclk_i,
    input  wire           hresetn_i,

// BANK ENABLES (DRIVEN BY arv_csr_top)
    input  wire           bank_mcycle_i,       // 0xB00-0xB3F: mhpmcounter3-10
    input  wire           bank_mcycleh_i,      // 0xB80-0xBBF: mhpmcounterh3-10
    input  wire           bank_mtrap_setup_i,  // 0x300-0x33F: mhpmevent3-10, mcounteren[10:3], mcountinhibit[10:3]
    input  wire           bank_counter_i,      // 0xC00-0xC3F: hpmcounter3-10 (read-only shadows)
    input  wire           bank_counterh_i,     // 0xC80-0xCBF: hpmcounterh3-10 (read-only shadows)

    input  wire    [63:0] register_sel_i,
    input  wire    [31:0] register_value_nxt_i,
    input  wire           disable_write_i,

// CORE AND PLATFORM EVENT INPUTS
    input  wire     [9:0] core_events_i,       // [9:0]  internal pipeline events
    input  wire     [7:0] platform_events_i,   // [7:0]  external platform events

// OUTPUTS
    output wire     [7:0] mcounteren_hpm_o,    // [7:0] mcounteren bits [10:3] for HPM counters 3-10
    output wire    [31:0] hpm_rdata_o          // [31:0] CSR read data

);

parameter                 ARST_EN      = 1;    // Reset style: 1=async (negedge hresetn_i), 0=sync (async term tied high -> sync-reset FF)
parameter                 ZIHPM_NR     = 0;    // Number of HPM counters implemented: 0-8


//////======================================================================================================================//////
//////                                       ZIHPM IMPLEMENTATION                                                           //////
//////======================================================================================================================//////

generate
    if (ZIHPM_NR > 0) begin : gen_hpm

        //------------------------------------------------------------------
        // Counter, event selector, and control registers
        //------------------------------------------------------------------
        wire [31:0] mhpmcounter_lo [0:7];
        wire [31:0] mhpmcounter_hi [0:7];
        wire  [4:0] mhpmevent_reg  [0:7];
        wire  [7:0] mcounteren_hpm_reg;
        wire  [7:0] mcountinhibit_hpm_reg;

        //------------------------------------------------------------------
        // mcounteren[10:3] and mcountinhibit[10:3] write logic
        // (bits [2:0] are managed by arv_csr_cntr)
        //
        // WARL mask: only bits corresponding to implemented counters
        // (0..ZIHPM_NR-1) are writable; upper bits are hardwired to 0.
        //------------------------------------------------------------------
        localparam [7:0] HPM_WARL_MASK = (ZIHPM_NR == 0) ? 8'h00 :
                                         (ZIHPM_NR == 1) ? 8'h01 :
                                         (ZIHPM_NR == 2) ? 8'h03 :
                                         (ZIHPM_NR == 3) ? 8'h07 :
                                         (ZIHPM_NR == 4) ? 8'h0F :
                                         (ZIHPM_NR == 5) ? 8'h1F :
                                         (ZIHPM_NR == 6) ? 8'h3F :
                                         (ZIHPM_NR == 7) ? 8'h7F : 8'hFF;

        // SPLIT-OWNERSHIP CONTRACT (see arv_csr_cntr.v:~94): mcounteren @0x306 /
        // mcountinhibit @0x320 are partitioned. THIS module owns bits [10:3]
        // (mhpmcounter3-10 enables/inhibits); arv_csr_cntr owns bits [2:0]
        // (CY/TM/IR). Both decode the same write-enable independently.
        wire mcounteren_wr    = bank_mtrap_setup_i & register_sel_i[6]  & ~disable_write_i;
        wire mcountinhibit_wr = bank_mtrap_setup_i & register_sel_i[32] & ~disable_write_i;

        arv_dff #(.WIDTH(8), .ARST_EN(ARST_EN)) u_mcounteren_hpm (
                              .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcounteren_wr),
                                                                   .d_i (register_value_nxt_i[10:3] & HPM_WARL_MASK),
                                                                   .q_o (mcounteren_hpm_reg));

        arv_dff #(.WIDTH(8), .ARST_EN(ARST_EN)) u_mcountinhibit_hpm (
                                 .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mcountinhibit_wr),
                                                                      .d_i (register_value_nxt_i[10:3] & HPM_WARL_MASK),
                                                                      .q_o (mcountinhibit_hpm_reg));

        //------------------------------------------------------------------
        // Read mux helper: single-counter read contribution (no loop
        // variable). Select bits are pre-decoded in the generate loop as
        // genvar expressions (elaboration-time constants, no VER-318).
        //------------------------------------------------------------------
        function automatic [31:0] hpm_ctr_rdata;
            input [31:0] ctr_lo;
            input [31:0] ctr_hi;
            input  [4:0] ctr_event;
            input        b_mcycle;
            input        b_mcycleh;
            input        b_counter;
            input        b_counterh;
            input        b_trap_setup;
            input        sel_ctr;   // register_sel_i[i+3]  pre-decoded by genvar
            input        sel_evt;   // register_sel_i[i+35] pre-decoded by genvar
            reg [31:0] rdata;
            begin
                rdata = 32'h0;
                if (b_mcycle     & sel_ctr)  rdata = rdata | ctr_lo;
                if (b_mcycleh    & sel_ctr)  rdata = rdata | ctr_hi;
                if (b_counter    & sel_ctr)  rdata = rdata | ctr_lo;
                if (b_counterh   & sel_ctr)  rdata = rdata | ctr_hi;
                if (b_trap_setup & sel_evt)  rdata = rdata | {27'h0, ctr_event};
                hpm_ctr_rdata = rdata;
            end
        endfunction

        wire [31:0] hpm_ctr_rdata_wire [0:7];

        //------------------------------------------------------------------
        // Per-counter logic: event mux, counter, event selector register
        //------------------------------------------------------------------
        genvar i;
        for (i = 0; i < 8; i = i + 1) begin : gen_ctr

            wire mhpmcounter_wr  = bank_mcycle_i      & register_sel_i[i+4'd3]  & ~disable_write_i & HPM_WARL_MASK[i];
            wire mhpmcounterh_wr = bank_mcycleh_i     & register_sel_i[i+4'd3]  & ~disable_write_i & HPM_WARL_MASK[i];
            wire mhpmevent_wr    = bank_mtrap_setup_i & register_sel_i[i+6'd35] & ~disable_write_i & HPM_WARL_MASK[i];

            // Event selection mux
            wire hpm_event_pulse = (mhpmevent_reg[i] == 5'h00) ? 1'b0                  :
                                   (mhpmevent_reg[i] == 5'h01) ? core_events_i[0]      :   // fetch stall
                                   (mhpmevent_reg[i] == 5'h02) ? core_events_i[1]      :   // LSU stall
                                   (mhpmevent_reg[i] == 5'h03) ? core_events_i[2]      :   // ALU stall
                                   (mhpmevent_reg[i] == 5'h04) ? core_events_i[3]      :   // CSR stall
                                   (mhpmevent_reg[i] == 5'h05) ? core_events_i[4]      :   // branch taken
                                   (mhpmevent_reg[i] == 5'h06) ? core_events_i[5]      :   // branch not taken
                                   (mhpmevent_reg[i] == 5'h07) ? core_events_i[6]      :   // load
                                   (mhpmevent_reg[i] == 5'h08) ? core_events_i[7]      :   // store
                                   (mhpmevent_reg[i] == 5'h09) ? core_events_i[8]      :   // exception
                                   (mhpmevent_reg[i] == 5'h0A) ? core_events_i[9]      :   // interrupt
                                   (mhpmevent_reg[i] == 5'h0B) ? platform_events_i[0]  :
                                   (mhpmevent_reg[i] == 5'h0C) ? platform_events_i[1]  :
                                   (mhpmevent_reg[i] == 5'h0D) ? platform_events_i[2]  :
                                   (mhpmevent_reg[i] == 5'h0E) ? platform_events_i[3]  :
                                   (mhpmevent_reg[i] == 5'h0F) ? platform_events_i[4]  :
                                   (mhpmevent_reg[i] == 5'h10) ? platform_events_i[5]  :
                                   (mhpmevent_reg[i] == 5'h11) ? platform_events_i[6]  :
                                   (mhpmevent_reg[i] == 5'h12) ? platform_events_i[7]  : 1'b0;

            // Combinatorial live inhibit: csrrc/csrrs takes effect in the same EX cycle,
            // not one cycle later via the registered path.
            wire hpm_inhibit_live = mcountinhibit_wr ? (register_value_nxt_i[i+4'd3] & HPM_WARL_MASK[i]) :
                                                        mcountinhibit_hpm_reg[i];
            wire hpm_count_en     = hpm_event_pulse  & ~hpm_inhibit_live;

            // mhpmcounter low half
            wire        mhpmcounter_lo_en  = mhpmcounter_wr | hpm_count_en;
            wire [31:0] mhpmcounter_lo_nxt = mhpmcounter_wr ? register_value_nxt_i :
                                                              (mhpmcounter_lo[i] + 1'b1);
            arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mhpmcounter_lo (
                                   .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mhpmcounter_lo_en),
                                                                        .d_i (mhpmcounter_lo_nxt),
                                                                        .q_o (mhpmcounter_lo[i]));

            // mhpmcounter high half (carry from low).
            // The (~mhpmcounter_wr) gate on the carry suppresses a spurious hi
            // increment when the user writes lo the same cycle as a count event
            // fires with old lo == 0xFFFFFFFF (write wins on lo; the event is
            // absorbed by the write, so no carry).
            wire        mhpmcounter_hi_en  = mhpmcounterh_wr | (hpm_count_en & ~mhpmcounter_wr);
            wire [31:0] mhpmcounter_hi_nxt = mhpmcounterh_wr ? register_value_nxt_i :
                                                               (mhpmcounter_hi[i] + {31'b0, (mhpmcounter_lo[i] == 32'hFFFFFFFF)});
            arv_dff #(.WIDTH(32), .ARST_EN(ARST_EN)) u_mhpmcounter_hi (
                                   .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mhpmcounter_hi_en),
                                                                        .d_i (mhpmcounter_hi_nxt),
                                                                        .q_o (mhpmcounter_hi[i]));

            // mhpmevent event selector
            // Note: mhpmevent_reg is registered while hpm_inhibit_live is combinational.
            // On the cycle a new event selector is being written, hpm_event_pulse still
            // uses the OLD selector (mhpmevent_reg, registered). 1-cycle latency in both
            // directions:
            //   - After enable: the counter misses the first event on the cycle of CSRW
            //     (selector takes effect next cycle).
            //   - After disable: the counter takes one extra event on the cycle of CSRW
            //     (old selector still active).
            // Acceptable trade-off: keeping mhpmevent combinational would extend the
            // 20-way event mux into the CSR write path's critical timing.
            arv_dff #(.WIDTH(5), .ARST_EN(ARST_EN)) u_mhpmevent (
                             .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mhpmevent_wr),
                                                                  .d_i (register_value_nxt_i[4:0]),
                                                                  .q_o (mhpmevent_reg[i]));

            // Read data contribution for this counter
            assign hpm_ctr_rdata_wire[i] = hpm_ctr_rdata( mhpmcounter_lo[i], mhpmcounter_hi[i], mhpmevent_reg[i],
                                                          bank_mcycle_i,     bank_mcycleh_i,
                                                          bank_counter_i,    bank_counterh_i,
                                                          bank_mtrap_setup_i,
                                                          register_sel_i[i+4'd3], register_sel_i[i+6'd35]
                                                        );

        end // gen_ctr

        //------------------------------------------------------------------
        // Read mux: fixed 8-way OR with constant indices - no ZIHPM_NR
        // used as array bound or index, eliminating VER-318.
        // Unused counter slots always read as 0 (registers never written,
        // event selector stays 0 after reset, hpm_count_en stays low).
        //------------------------------------------------------------------
        assign hpm_rdata_o = ({32{bank_mtrap_setup_i & register_sel_i[6'd6]}}  & {21'h0, mcounteren_hpm_reg,    3'h0}) |
                             ({32{bank_mtrap_setup_i & register_sel_i[6'd32]}} & {21'h0, mcountinhibit_hpm_reg, 3'h0}) |
                               hpm_ctr_rdata_wire[0] | hpm_ctr_rdata_wire[1] |
                               hpm_ctr_rdata_wire[2] | hpm_ctr_rdata_wire[3] |
                               hpm_ctr_rdata_wire[4] | hpm_ctr_rdata_wire[5] |
                               hpm_ctr_rdata_wire[6] | hpm_ctr_rdata_wire[7];

        assign mcounteren_hpm_o = mcounteren_hpm_reg;

        // Suppress unused input warning.
        wire  [2:0] register_sel__2__0_unused = register_sel_i[2:0];
        wire [20:0] register_sel_31_11_unused = register_sel_i[31:11];
        wire  [1:0] register_sel_34_33_unused = register_sel_i[34:33];
        wire [20:0] register_sel_63_43_unused = register_sel_i[63:43];


    end else begin : gen_hpm_disabled

        //------------------------------------------------------------------
        // Disabled: tie off outputs, suppress unused input warnings
        //------------------------------------------------------------------
        wire        bank_mcycle_unused      = bank_mcycle_i;
        wire        bank_mcycleh_unused     = bank_mcycleh_i;
        wire        bank_mtrap_setup_unused = bank_mtrap_setup_i;
        wire        bank_counter_unused     = bank_counter_i;
        wire        bank_counterh_unused    = bank_counterh_i;
        wire [63:0] register_sel_unused     = register_sel_i;
        wire [31:0] register_value_unused   = register_value_nxt_i;
        wire        disable_write_unused    = disable_write_i;
        wire  [9:0] core_events_unused      = core_events_i;
        wire  [7:0] platform_events_unused  = platform_events_i;

        assign      hpm_rdata_o             = 32'h0;
        assign      mcounteren_hpm_o        =  8'h0;

    end
endgenerate


endmodule // arv_csr_hpm

`default_nettype wire

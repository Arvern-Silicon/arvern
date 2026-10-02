//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_csr_pmp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_csr_pmp.v
// Module Description : RISC-V CSRs: Physical Memory Protection (16 entries) + Smepmp (mseccfg)
//----------------------------------------------------------------------------
// SIXTEEN entries always exist architecturally; PMP_NR selects how many are
// WRITABLE and the rest are hardwired read-only zero. Priv 3.7.1 permits exactly
// this: "All PMP CSR fields are WARL and may be read-only zero", and 3.7.1.1 p68
// makes a zero entry behaviourally absent -- "When A=0, this PMP entry is disabled
// and matches no addresses" -- so it needs no comparator either. Software probes
// the usable count by WARL (2.3.3 p21): entries at or above PMP_NR MUST read back
// zero after a write attempt, which is why they carry no flop at all.
//
// Granularity G = 0: no low pmpaddr bits are read-only, so all four A encodings
// including NA4 are selectable. The TOP two bits are read-only zero: pmpaddr holds
// address[33:2] and this core's physical address space is 32 bits, so address
// [33:32] can never match. The granularity probe (3.7.1.1 p69) reads the LOW bits,
// so narrowing the top is invisible to it.
//
// This module holds STATE and WARL only. The address matchers live with the
// consumers: the load/store checker in arv_load_store.v and the fetch checker in
// arv_fetch.v. That split is deliberate -- see the note on SBA below.
//
// SBA: the Debug Module's system-bus master is muxed onto the data port at
// arvern.v (data_haddr_o = dm_sb_active ? dm_sb_haddr : data_haddr), so a checker
// placed in the LSU is upstream of that mux and debugger accesses bypass PMP by
// construction. Debug Spec 3.10 requires exactly that: SBA accesses reach the bus
// "without involving a hart", and access control is left to the platform. Do NOT
// re-express this as a ~dm_sb_active qualifier somewhere -- placement cannot be
// dropped by a refactor, a qualifier can.
//----------------------------------------------------------------------------
`default_nettype none

module  arv_csr_pmp (

// AHB CLOCK & RESET
    input  wire             hclk_i,
    input  wire             hresetn_i,

// BANK ENABLES (DRIVEN BY arv_csr_top)
    input  wire             bank_pmp_i,          // 0x380-0x3BF (pmpcfg0-3 @ sel 32-35, pmpaddr0-15 @ sel 48-63)
    input  wire             bank_mseccfg_i,      // 0x740-0x77F (mseccfg @ sel 7, mseccfgh @ sel 23)

    input  wire      [63:0] register_sel_i,
    input  wire      [31:0] register_value_nxt_i,
    input  wire             disable_write_i,

// ENTRY STATE (TO THE FETCH AND LOAD/STORE CHECKERS)
    output wire  [16*8-1:0] pmp_cfg_o,         // 16 x {L, 2'b0, A[1:0], X, W, R}
    output wire [16*32-1:0] pmp_addr_o,        // 16 x pmpaddr (address[33:2])
    output wire             pmp_mml_o,           // mseccfg.MML
    output wire             pmp_mmwp_o,          // mseccfg.MMWP

    output wire      [31:0] pmp_rdata_o

);

// USER PARAMETERs
//========================================
parameter                   PMP_NR       =  0;          // Writable PMP entries: 0, 4, 8 or 16 (16 always exist; the rest are read-only zero)
parameter                   ARST_EN      =  1'b1;       // Reset architecture: 1=asynchronous, 0=synchronous

//////======================================================================================================================//////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////======================================================================================================================//////

// Out-of-range values snap DOWN to the next legal count rather than up: a build
// asking for more protection than it gets is a worse failure than one asking for
// less than it could have.
localparam                  PMP_NR_USE   = (PMP_NR >= 16) ? 16 :
                                           (PMP_NR >=  8) ?  8 :
                                           (PMP_NR >=  4) ?  4 : 0;

wire                 [31:0] pmpcfg_rd   [0:3];
wire                 [31:0] pmpaddr_rd  [0:15];
wire                  [7:0] cfg         [0:15];
wire                 [31:0] addr        [0:15];
wire                        mseccfg_mml;
wire                        mseccfg_mmwp;
wire                        mseccfg_rlb;

genvar g;

generate
if (PMP_NR_USE != 0) begin : g_pmp

    //======================================================================
    // 1) mseccfg -- Smepmp. Unconditional whenever PMP is present.
    //======================================================================
    // All three bits are one-way (Priv 6.2, p84):
    //   MML  sticky-SET    MMWP sticky-SET    RLB  stuck-CLEAR once any rule is locked
    // Exit is only by PMP reset, which this core does not implement separately from
    // hart reset -- so a hard reset is the only way back, which the spec permits.
    wire       mseccfg_wr    = bank_mseccfg_i & register_sel_i[7] & ~disable_write_i;

    // RLB: "When mseccfg.RLB is 0 and pmpcfg.L is 1 in any rule or entry (including
    // DISABLED entries), then mseccfg.RLB remains 0 and any further modifications
    // to mseccfg.RLB are ignored" -- so the lock scan covers all 16 cfg bytes
    // regardless of their A field.
    wire       any_rule_locked = |{cfg[15][7], cfg[14][7], cfg[13][7], cfg[12][7],
                                   cfg[11][7], cfg[10][7], cfg[ 9][7], cfg[ 8][7],
                                   cfg[ 7][7], cfg[ 6][7], cfg[ 5][7], cfg[ 4][7],
                                   cfg[ 3][7], cfg[ 2][7], cfg[ 1][7], cfg[ 0][7]};

    wire       rlb_writable  = mseccfg_rlb | ~any_rule_locked;

    wire       mml_nxt       = mseccfg_mml  | register_value_nxt_i[0];   // sticky set
    wire       mmwp_nxt      = mseccfg_mmwp | register_value_nxt_i[1];   // sticky set
    wire       rlb_nxt       = rlb_writable ? register_value_nxt_i[2] : mseccfg_rlb;

    arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_mseccfg_mml (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mseccfg_wr),
                                                           .d_i (mml_nxt),  .q_o(mseccfg_mml));
    arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_mseccfg_mmwp (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mseccfg_wr),
                                                           .d_i (mmwp_nxt), .q_o(mseccfg_mmwp));
    arv_dff #(.WIDTH(1), .ARST_EN(ARST_EN)) u_mseccfg_rlb (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(mseccfg_wr),
                                                           .d_i (rlb_nxt),  .q_o(mseccfg_rlb));

    //======================================================================
    // 2) The 16 entries
    //======================================================================
    for (g = 0; g < PMP_NR_USE; g = g + 1) begin : g_entry

        // ---- lock ---------------------------------------------------------
        // Priv 3.7.1: a locked entry's pmpcfg AND pmpaddr are read-only. Smepmp
        // 6.2 adds the escape: RLB=1 permits modifying locked rules.
        wire       locked      = cfg[g][7] & ~mseccfg_rlb;

        // TOR: entry g's range starts at pmpaddr[g-1], so a locked TOR entry also
        // freezes the PRECEDING address register (Priv 3.7.1). Entry 0's TOR base
        // is 0, not a register, so there is nothing to freeze below it.
        // Generate-time, not a ternary: a runtime `(g<15) ? cfg[g+1] : 0` evaluates
        // BOTH arms and indexes cfg[16] at g=15. Verilator accepts that; Icarus
        // aborts on the out-of-bounds access.
        wire       tor_locked_by_next;
        if (g < 15) begin : g_tor_above
            assign tor_locked_by_next = cfg[g+1][7] & (cfg[g+1][4:3] == 2'b01) & ~mseccfg_rlb;
        end
        else begin : g_tor_top
            assign tor_locked_by_next = 1'b0;   // nothing above entry 15 to lock it
        end

        // ---- pmpcfg -------------------------------------------------------
        wire       cfg_sel     = register_sel_i[32 + (g >> 2)];
        wire [7:0] cfg_wdata   = register_value_nxt_i[8*(g % 4) +: 8];

        // Bits [6:5] are reserved WARL and read as zero. R/W/X and A are kept as
        // written: RW=01 is NOT suppressed, because under Smepmp MML that encoding
        // means Shared-Region (6.2) rather than being reserved.
        wire [7:0] cfg_nxt     = {cfg_wdata[7], 2'b00, cfg_wdata[4:0]};

        // Smepmp 6.2 item 4b: with MML set, "adding a rule with executable
        // privileges that either is M-mode-only or a locked Shared-Region is not
        // possible and such pmpcfg writes are ignored". Those are the locked
        // encodings the 6.2.1 table grants M-mode execute -- LRWX 1001, 1010, 1011
        // and 1101 -- expressed here as the same term the checker uses. RLB lifts
        // it, which is how a boot sequence installs them.
        wire       nxt_m_exec  = (~cfg_nxt[0] & (cfg_nxt[1] | cfg_nxt[2])) |
                                 ( cfg_nxt[0] & ~cfg_nxt[1] & cfg_nxt[2]);
        wire       mml_ignore  = mseccfg_mml & ~mseccfg_rlb & cfg_nxt[7] & nxt_m_exec;

        wire       cfg_wr      = bank_pmp_i & cfg_sel & ~disable_write_i & ~locked & ~mml_ignore;
        wire [1:0] cfg_wdata_rsvd_unused = cfg_wdata[6:5];   // reserved WARL, dropped on write

        arv_dff #(.WIDTH(8), .ARST_EN(ARST_EN)) u_pmpcfg (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(cfg_wr),
                                                           .d_i (cfg_nxt), .q_o(cfg[g]));

        // ---- pmpaddr ------------------------------------------------------
        wire       addr_wr     = bank_pmp_i & register_sel_i[48 + g] & ~disable_write_i
                                            & ~locked & ~tor_locked_by_next;

        // Only address[31:2] is storable: [31:30] of pmpaddr map to address[33:32],
        // which a 32-bit-physical core cannot generate, so they are read-only zero.
        wire [29:0] addr_q;
        arv_dff #(.WIDTH(30), .ARST_EN(ARST_EN)) u_pmpaddr (
                      .clk_i(hclk_i), .rst_n_i(hresetn_i), .en_i(addr_wr),
                                                           .d_i (register_value_nxt_i[29:0]), .q_o(addr_q));
        assign addr[g]         = {2'b00, addr_q};
        assign pmpaddr_rd[g]   = addr[g];
        assign pmp_cfg_o [8*g  +: 8]  = cfg[g];
        assign pmp_addr_o[32*g +: 32] = addr[g];
    end

    // Entries above PMP_NR: read-only zero, no flop, no comparator. A write is
    // dropped and reads back zero, which is exactly what the WARL probe expects.
    for (g = PMP_NR_USE; g < 16; g = g + 1) begin : g_entry_rozero
        assign cfg[g]                 = 8'h00;
        assign addr[g]                = 32'h00000000;
        assign pmpaddr_rd[g]          = addr[g];
        assign pmp_cfg_o [8*g  +: 8]  = cfg[g];
        assign pmp_addr_o[32*g +: 32] = addr[g];
    end

    for (g = 0; g < 4; g = g + 1) begin : g_cfgword
        assign pmpcfg_rd[g] = {cfg[4*g+3], cfg[4*g+2], cfg[4*g+1], cfg[4*g+0]};
    end

end
else begin : g_no_pmp

    // PMP_EN = 0: every pmp* and mseccfg CSR is RAZ/WI and no state exists. The
    // core must be bit-identical to a build without this module at all.
    assign mseccfg_mml  = 1'b0;
    assign mseccfg_mmwp = 1'b0;
    assign mseccfg_rlb  = 1'b0;

    for (g = 0; g < 16; g = g + 1) begin : g_entry_off
        assign cfg[g]                 = 8'h00;
        assign addr[g]                = 32'h00000000;
        assign pmpaddr_rd[g]          = addr[g];
        assign pmp_cfg_o [8*g  +: 8]  = cfg[g];
        assign pmp_addr_o[32*g +: 32] = addr[g];
    end
    for (g = 0; g < 4; g = g + 1) begin : g_cfgword_off
        assign pmpcfg_rd[g] = {cfg[4*g+3], cfg[4*g+2], cfg[4*g+1], cfg[4*g+0]};
    end

    // Sink wires: with PMP absent nothing here is driven or consumed, and the
    // *_unused convention documents that as deliberate rather than an oversight.
    wire        hclk_unused          = hclk_i;
    wire        hresetn_unused       = hresetn_i;
    wire        bank_pmp_unused      = bank_pmp_i;
    wire        bank_mseccfg_unused  = bank_mseccfg_i;
    wire        disable_write_unused = disable_write_i;
    wire [31:0] reg_value_unused     = register_value_nxt_i;

end
endgenerate

// Lint: tie off the register_sel_i bits this bank never decodes. pmpcfg0-3 are at
// 32-35, pmpaddr0-15 at 48-63, mseccfg at 7 and mseccfgh at 23.
wire [11:0] register_sel_47_36_unused = register_sel_i[47:36];
wire [23:0] register_sel_31__8_unused = register_sel_i[31: 8];
wire  [6:0] register_sel_6___0_unused = register_sel_i[ 6: 0];

//////======================================================================================================================//////
//////                                                    READ MUX                                                          //////
//////======================================================================================================================//////

// mseccfgh (0x757) is the RV32 alias of mseccfg[63:32]. Every field defined here
// lives in the low half, so the upper half reads zero -- but the address must be
// decoded, not absent: Priv 3.1.19 requires it to exist when XLEN=32.
wire [31:0] mseccfg_rd  = {29'h00000000, mseccfg_rlb, mseccfg_mmwp, mseccfg_mml};

assign pmp_rdata_o = ({32{bank_pmp_i     & register_sel_i[32]}} & pmpcfg_rd [ 0]) |
                     ({32{bank_pmp_i     & register_sel_i[33]}} & pmpcfg_rd [ 1]) |
                     ({32{bank_pmp_i     & register_sel_i[34]}} & pmpcfg_rd [ 2]) |
                     ({32{bank_pmp_i     & register_sel_i[35]}} & pmpcfg_rd [ 3]) |
                     ({32{bank_pmp_i     & register_sel_i[48]}} & pmpaddr_rd[ 0]) |
                     ({32{bank_pmp_i     & register_sel_i[49]}} & pmpaddr_rd[ 1]) |
                     ({32{bank_pmp_i     & register_sel_i[50]}} & pmpaddr_rd[ 2]) |
                     ({32{bank_pmp_i     & register_sel_i[51]}} & pmpaddr_rd[ 3]) |
                     ({32{bank_pmp_i     & register_sel_i[52]}} & pmpaddr_rd[ 4]) |
                     ({32{bank_pmp_i     & register_sel_i[53]}} & pmpaddr_rd[ 5]) |
                     ({32{bank_pmp_i     & register_sel_i[54]}} & pmpaddr_rd[ 6]) |
                     ({32{bank_pmp_i     & register_sel_i[55]}} & pmpaddr_rd[ 7]) |
                     ({32{bank_pmp_i     & register_sel_i[56]}} & pmpaddr_rd[ 8]) |
                     ({32{bank_pmp_i     & register_sel_i[57]}} & pmpaddr_rd[ 9]) |
                     ({32{bank_pmp_i     & register_sel_i[58]}} & pmpaddr_rd[10]) |
                     ({32{bank_pmp_i     & register_sel_i[59]}} & pmpaddr_rd[11]) |
                     ({32{bank_pmp_i     & register_sel_i[60]}} & pmpaddr_rd[12]) |
                     ({32{bank_pmp_i     & register_sel_i[61]}} & pmpaddr_rd[13]) |
                     ({32{bank_pmp_i     & register_sel_i[62]}} & pmpaddr_rd[14]) |
                     ({32{bank_pmp_i     & register_sel_i[63]}} & pmpaddr_rd[15]) |
                     ({32{bank_mseccfg_i & register_sel_i[ 7]}} & mseccfg_rd    ) ;
                     // mseccfgh (sel 23) reads zero: all defined fields are in the low half

assign pmp_mml_o   = mseccfg_mml;
assign pmp_mmwp_o  = mseccfg_mmwp;

endmodule // arv_csr_pmp

`default_nettype wire

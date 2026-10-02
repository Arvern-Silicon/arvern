//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_pmp_check
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_pmp_check
// Module Description : PMP address matcher and permission check (combinational)
//----------------------------------------------------------------------------
// One instance per checked port: the load/store checker in arv_load_store.v and
// the fetch checker in arv_fetch.v. Purely combinational -- it holds no state and
// reads the entries from arv_csr_pmp.
//
// Matching uses address[33:2] only, which is exact rather than approximate: every
// access this core performs is naturally aligned (a misaligned one traps and is
// never issued) and is at most 4 bytes, while the smallest PMP region is a 4-byte
// aligned NA4. An aligned access of 4 bytes or fewer therefore lies wholly inside
// one 4-byte aligned block and cannot straddle a region boundary, so the low two
// address bits cannot change the verdict.
//
// A misaligned address is still checked here, and an access fault outranks the
// misalignment in the trap priority. Both orders are permitted (Priv "Synchronous
// exception priority" lists load/store misaligned as optionally above the access
// fault and otherwise lowest), and the access is never performed under either.
//----------------------------------------------------------------------------
`default_nettype none

module  arv_pmp_check (

// ENTRY STATE (FROM arv_csr_pmp)
    input  wire  [16*8-1:0] pmp_cfg_i,         // 16 x {L, 2'b0, A[1:0], X, W, R}
    input  wire [16*32-1:0] pmp_addr_i,        // 16 x pmpaddr (address[33:2])
    input  wire             pmp_mml_i,         // mseccfg.MML
    input  wire             pmp_mmwp_i,        // mseccfg.MMWP

// ACCESS UNDER TEST
    input  wire      [31:0] addr_i,            // byte address
    input  wire       [1:0] priv_i,            // effective privilege (MPRV-aware for load/store)
    input  wire             acc_read_i,
    input  wire             acc_write_i,
    input  wire             acc_exec_i,

    output wire             fault_o            // 1 = access denied

);

// USER PARAMETERs
//========================================
parameter                   PMP_NR       =  0;         // Writable PMP entries: 0, 4, 8 or 16

//////======================================================================================================================//////
//////                                       INTERNAL WIRES/REGISTERS/PARAMETERS DECLARATION                                //////
//////======================================================================================================================//////

localparam                  PMP_NR_USE   = (PMP_NR >= 16) ? 16 :
                                           (PMP_NR >=  8) ?  8 :
                                           (PMP_NR >=  4) ?  4 : 0;

localparam           [1:0]  PRIV_M       = 2'b11;

genvar g;

generate
if (PMP_NR_USE == 0) begin : g_no_pmp

    // "If no PMP entries are implemented, all accesses are allowed" (Priv 3.7.1).
    wire no_pmp_unused = pmp_mml_i | pmp_mmwp_i | acc_read_i | acc_write_i | acc_exec_i |
                         (|addr_i) | (|priv_i) | (|pmp_cfg_i) | (|pmp_addr_i);
    assign fault_o = 1'b0;

end else begin : g_pmp

    //======================================================================
    // 1) Unpack the entries that can be non-zero
    //======================================================================
    // Entries at or above PMP_NR_USE are read-only zero, so their A field is OFF
    // and they match nothing. Building no comparator for them is what makes the
    // parameter an area knob rather than a decoration.
    wire  [7:0] cfg  [0:PMP_NR_USE-1];
    wire [31:0] addr [0:PMP_NR_USE-1];

    for (g = 0; g < PMP_NR_USE; g = g + 1) begin : g_unpack
        assign cfg[g]  = pmp_cfg_i [g*8  +:  8];
        assign addr[g] = pmp_addr_i[g*32 +: 32];

        // Bits [6:5] are reserved and read as zero; the matcher takes A and the
        // permission takes L/X/W/R, so nothing reads them.
        wire [1:0] cfg_rsvd_unused = cfg[g][6:5];
    end

    //======================================================================
    // 2) Address match, per entry
    //======================================================================
    wire [31:0] addr34 = {2'b00, addr_i[31:2]};        // address[33:2], as pmpaddr holds it

    wire [15:0] match;

    // TOR bounds are SHARED. Entry g spans [pmpaddr[g-1], pmpaddr[g]), so its lower
    // bound is the negation of entry g-1's upper bound. Computing one comparison
    // per entry instead of two halves the magnitude comparators -- 16 rather than
    // 32 -- for the same result and the same depth.
    // The comparison is written as the borrow of a subtraction so that
    // FPGA synthesis places it on the carry chain rather than on a LUT tree.
    wire [PMP_NR_USE-1:0] lt;
    for (g = 0; g < PMP_NR_USE; g = g + 1) begin : g_lt
        wire [32:0] lt_diff = {1'b0, addr34} - {1'b0, addr[g]};
        assign lt[g] = lt_diff[32];
        wire [31:0] lt_diff_unused = lt_diff[31:0];
    end

    for (g = 0; g < PMP_NR_USE; g = g + 1) begin : g_match

        wire  [1:0] a_fld = cfg[g][4:3];

        // pmpaddr[-1] reads as zero, so entry 0 has only an upper bound.
        wire        m_tor = (g == 0) ? lt[0] : (lt[g] & ~lt[(g == 0) ? 0 : (g - 1)]);

        // NA4 is NAPOT with a zero mask, so one comparator covers both. For NAPOT
        // the trailing ones of pmpaddr select the don't-care bits: x ^ (x+1) sets
        // exactly those, plus the lowest zero. The mask is CSR-derived, so it is
        // settled long before the address arrives.
        wire [31:0] napot = (a_fld == 2'b11) ? (addr[g] ^ (addr[g] + 32'h1)) : 32'h0;
        wire        m_na  = ((addr34 ^ addr[g]) & ~napot) == 32'h0;

        assign match[g]   = (a_fld == 2'b01) ? m_tor :
                            (a_fld == 2'b00) ? 1'b0  : m_na;
    end
    for (g = PMP_NR_USE; g < 16; g = g + 1) begin : g_nomatch
        assign match[g]   = 1'b0;
    end

    //======================================================================
    // 3) Permission, per entry -- independent of the address
    //======================================================================
    // The permission of an entry depends only on its own cfg, the privilege and
    // mseccfg. Resolving it per entry lets it settle in parallel with the
    // comparators instead of behind the match mux, which keeps the whole MML
    // table off the address path. That matters on the fetch side, where the
    // address arrives from the branch-target adder.
    wire        is_m = (priv_i == PRIV_M);
    wire [15:0] allow;

    for (g = 0; g < PMP_NR_USE; g = g + 1) begin : g_perm

        wire e_l = cfg[g][7];
        wire e_x = cfg[g][2];
        wire e_w = cfg[g][1];
        wire e_r = cfg[g][0];

        // MML=0: an unlocked rule does not bind M-mode; otherwise the plain R/W/X.
        wire bypass = is_m & ~e_l;

        // MML=1 re-reads L/R/W/X as the 16-row table of Priv 6.2.1 (A is untouched).
        // R=0,W=1 is the Shared-Region marker, which is why that encoding is legal
        // to write rather than suppressed as reserved.
        wire mm_r = e_l ? (e_r | (e_w & e_x)) : (~e_r &  e_w);
        wire mm_w = e_l ? (e_r &  e_w & ~e_x) : (~e_r &  e_w);
        wire mm_x = e_l ? ((~e_r & (e_w | e_x)) | (e_r & ~e_w & e_x)) : 1'b0;

        wire ms_r = e_l ? (e_r &  e_w &  e_x) : (e_r |  e_w);
        wire ms_w = e_l ?  1'b0               : (e_w & (e_r |  e_x));
        wire ms_x = e_l ? (~e_r & e_w)        : (e_x & (e_r | ~e_w));

        wire p_r  = pmp_mml_i ? (is_m ? mm_r : ms_r) : (bypass | e_r);
        wire p_w  = pmp_mml_i ? (is_m ? mm_w : ms_w) : (bypass | e_w);
        wire p_x  = pmp_mml_i ? (is_m ? mm_x : ms_x) : (bypass | e_x);

        assign allow[g] = (~acc_read_i  | p_r) &
                          (~acc_write_i | p_w) &
                          (~acc_exec_i  | p_x);
    end
    for (g = PMP_NR_USE; g < 16; g = g + 1) begin : g_noperm
        assign allow[g] = 1'b0;
    end

    //======================================================================
    // 4) Lowest-numbered match wins
    //======================================================================
    // A pairwise priority tree over (match, allow): each node keeps the lower
    // half's permission when that half matches, the upper half's otherwise. It
    // resolves the winner's permission in log depth without isolating the
    // winning entry first, and `matched` is the OR at its root.
    //
    //   (m, a) = (m_lo | m_hi, m_lo ? a_lo : a_hi)
    wire  [7:0] tr_m1, tr_a1;
    wire  [3:0] tr_m2, tr_a2;
    wire  [1:0] tr_m3, tr_a3;
    for (g = 0; g < 8; g = g + 1) begin : g_tree1
        assign tr_m1[g] = match[(2*g)] | match[(2*g)+1];
        assign tr_a1[g] = match[(2*g)] ? allow[(2*g)] : allow[(2*g)+1];
    end
    for (g = 0; g < 4; g = g + 1) begin : g_tree2
        assign tr_m2[g] = tr_m1[(2*g)] | tr_m1[(2*g)+1];
        assign tr_a2[g] = tr_m1[(2*g)] ? tr_a1[(2*g)] : tr_a1[(2*g)+1];
    end
    for (g = 0; g < 2; g = g + 1) begin : g_tree3
        assign tr_m3[g] = tr_m2[(2*g)] | tr_m2[(2*g)+1];
        assign tr_a3[g] = tr_m2[(2*g)] ? tr_a2[(2*g)] : tr_a2[(2*g)+1];
    end
    wire        matched = tr_m3[0] | tr_m3[1];
    wire        granted = tr_m3[0] ? tr_a3[0] : tr_a3[1];

    //======================================================================
    // 5) Permission when nothing matches
    //======================================================================
    // S/U is denied: entries are implemented here, so the allow-all case does not
    // apply. M-mode is allowed unless MMWP makes the rules an allowlist -- except
    // that MML alone already withdraws M-mode execute, which is the whole point of
    // Machine Mode Lockdown.
    wire        nomatch_ok = is_m & ~pmp_mmwp_i & ~(pmp_mml_i & acc_exec_i);

    assign fault_o = ~(matched ? granted : nomatch_ok);

    wire        addr_lsb_unused = |addr_i[1:0];

    if (PMP_NR_USE < 16) begin : g_unused_hi
        wire    entries_hi_unused = (|pmp_cfg_i [(16*8)-1  : PMP_NR_USE*8 ]) |
                                    (|pmp_addr_i[(16*32)-1 : PMP_NR_USE*32]) ;
    end

end
endgenerate

endmodule

`default_nettype wire

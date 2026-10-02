//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_sba
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: System Bus Access (SBA) over the DMI bus (Debug Module).
//   Drives the hclk-domain DMI bus (no DTM) and the DM's own AHB master via the
//   sbcs (0x38) / sbaddress0 (0x39) / sbdata0 (0x3C) registers while the hart is
//   halted (frozen-hart; the SBA master is muxed onto the data port). Exercises
//   the full SBA feature set:
//     A. basic 32-bit READ of two firmware sentinels;
//     B. basic 32-bit WRITE + read-back (and a post-resume firmware cross-check
//        that the write reached real memory);
//     C. autoincrement + readonaddr + readondata block read of three words, with
//        sbaddress0 confirmed to have advanced by 3 words;
//     D. sub-word 8-bit + 16-bit writes and reads (byte-lane right-justify);
//     E. alignment error  -> sberror=3 (W1C clear);
//     F. unsupported size -> sberror=4 (W1C clear);
//     G. bus error (unmapped address) -> sberror=2 (W1C clear).
//   Helpers (sba_*) live in bench/verilog/debug_dmi_tasks.v.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

// data_hmaster sideband invariants (checked at end of test):
//   - while the hart is NOT in Debug Mode, no active data transfer may be tagged
//     as a debug-master access (software accesses must read hmaster=0);
//   - at least one SBA access must tag the bus hmaster=1.
reg hmaster_sw_violation;   // a hart (software) transfer was wrongly tagged hmaster=1
reg hmaster_dbg_seen;       // an SBA (debug) transfer correctly tagged hmaster=1
initial begin hmaster_sw_violation = 1'b0; hmaster_dbg_seen = 1'b0; end
always @(posedge dut_hclk) begin
    if (data_htrans[1]) begin                                   // an active (NONSEQ) data transfer
        if (data_hmaster) hmaster_dbg_seen = 1'b1;
        if (data_hmaster && (dbg_debug_mode !== 1'b1)) hmaster_sw_violation = 1'b1;
    end
end

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_SBCS       = 7'h38;
localparam [6:0] DMI_SBADDRESS0 = 7'h39;
localparam [6:0] DMI_SBDATA0    = 7'h3c;

// SRAM layout
localparam [31:0] BASE  = 32'h80004000;
localparam [31:0] WORD0 = 32'hCAFEBABE;   // [BASE+0x00]
localparam [31:0] WORD1 = 32'h12345678;   // [BASE+0x04]
localparam [31:0] WORD2 = 32'hDEADBEEF;   // SBA-written over [BASE+0x08]

// sbcs masks
localparam [31:0] SBCS_SBVERSION = 32'hE0000000; // [31:29]

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // Reset peripherals
    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG DMI SBA: system bus read/write of a halted hart over the DMI  |");
    $display(" ====================================================================");

    // Wait for the firmware to seed SRAM and start spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111), SRAM seeded %t ns", $time);

    // Bring the DM out of reset and halt the hart.
    dmi_write(7'h10, 32'h00000001);                  // dmcontrol = dmactive
    dmi_write(7'h10, 32'h10000001);                  // ackhavereset (clear sticky)
    dm_halt;

    // sbcs sanity: sbversion=1, sbaccess32/16/8 supported.
    dmi_read(DMI_SBCS);
    if ((dmi_readval & SBCS_SBVERSION) !== 32'h20000000) begin
        $display("ERROR: sbcs.sbversion != 1 (sbcs=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  sbcs.sbversion = 1 (sbcs=%h) %t ns", dmi_readval, $time);
    if ((dmi_readval & 32'h00000007) !== 32'h00000007) begin
        $display("ERROR: sbcs sbaccess8/16/32 support bits not all set (sbcs=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  sbcs reports 8/16/32-bit access supported %t ns", $time);

    //========================================================================
    // A. Basic 32-bit reads of the firmware sentinels
    //========================================================================
    sba_read32(BASE + 32'h0);
    if (sba_rdata !== WORD0) begin
        $display("ERROR: SBA read [BASE+0]=%h (expected %h) %t ns", sba_rdata, WORD0, $time);
        error = error + 1;
    end else $display("PASS:  SBA read [BASE+0]=%h %t ns", sba_rdata, $time);

    sba_read32(BASE + 32'h4);
    if (sba_rdata !== WORD1) begin
        $display("ERROR: SBA read [BASE+4]=%h (expected %h) %t ns", sba_rdata, WORD1, $time);
        error = error + 1;
    end else $display("PASS:  SBA read [BASE+4]=%h %t ns", sba_rdata, $time);

    //========================================================================
    // B. Basic 32-bit write + read-back
    //========================================================================
    sba_write32(BASE + 32'h8, WORD2);                // overwrite the 0x0BADF00D seed
    sba_read32 (BASE + 32'h8);
    if (sba_rdata !== WORD2) begin
        $display("ERROR: SBA read-back [BASE+8]=%h (expected %h) %t ns", sba_rdata, WORD2, $time);
        error = error + 1;
    end else $display("PASS:  SBA write/read-back [BASE+8]=%h %t ns", sba_rdata, $time);

    //========================================================================
    // C. Autoincrement block read: readonaddr + readondata + autoincrement.
    //    Writing sbaddress triggers read of word0; each sbdata read returns the
    //    previous word and arms the next; sbaddress advances by 4 each access.
    //========================================================================
    sba_cfg(1'b1, 1'b1, 1'b1, 3'd2);                 // readonaddr, readondata, autoincr, 32-bit
    dmi_write(DMI_SBADDRESS0, BASE + 32'h0);         // triggers read of [BASE+0]
    sba_wait_idle;

    dmi_read(DMI_SBDATA0);                            // returns word0, arms read of [BASE+4]
    if (dmi_readval !== WORD0) begin
        $display("ERROR: autoincr read[0]=%h (expected %h) %t ns", dmi_readval, WORD0, $time);
        error = error + 1;
    end else $display("PASS:  autoincr read[0]=%h %t ns", dmi_readval, $time);
    sba_wait_idle;

    dmi_read(DMI_SBDATA0);                            // returns word1, arms read of [BASE+8]
    if (dmi_readval !== WORD1) begin
        $display("ERROR: autoincr read[1]=%h (expected %h) %t ns", dmi_readval, WORD1, $time);
        error = error + 1;
    end else $display("PASS:  autoincr read[1]=%h %t ns", dmi_readval, $time);
    sba_wait_idle;

    sba_cfg(1'b0, 1'b0, 1'b1, 3'd2);                 // drop readondata so the final read doesn't re-trigger
    dmi_read(DMI_SBDATA0);                            // returns word2 (= SBA-written 0xDEADBEEF)
    if (dmi_readval !== WORD2) begin
        $display("ERROR: autoincr read[2]=%h (expected %h) %t ns", dmi_readval, WORD2, $time);
        error = error + 1;
    end else $display("PASS:  autoincr read[2]=%h %t ns", dmi_readval, $time);

    dmi_read(DMI_SBADDRESS0);                         // must have advanced 3 words: BASE+0xC
    if (dmi_readval !== (BASE + 32'hC)) begin
        $display("ERROR: sbaddress0 after autoincr=%h (expected %h) %t ns", dmi_readval, BASE + 32'hC, $time);
        error = error + 1;
    end else $display("PASS:  sbaddress0 autoincremented to %h %t ns", dmi_readval, $time);

    //========================================================================
    // D. Sub-word access: 8-bit + 16-bit writes, byte-lane right-justified reads.
    //    Build the word 0x80004010 = 0xBEEF00AB from a byte then a halfword.
    //========================================================================
    sba_write32(BASE + 32'h10, 32'h00000000);        // clear the scratch word

    sba_cfg(1'b0, 1'b0, 1'b0, 3'd0);                 // 8-bit write
    dmi_write(DMI_SBADDRESS0, BASE + 32'h10);
    dmi_write(DMI_SBDATA0,    32'h000000AB);          // [0x10] = 0xAB
    sba_wait_idle;

    sba_cfg(1'b0, 1'b0, 1'b0, 3'd1);                 // 16-bit write
    dmi_write(DMI_SBADDRESS0, BASE + 32'h12);
    dmi_write(DMI_SBDATA0,    32'h0000BEEF);          // [0x12..0x13] = 0xBEEF
    sba_wait_idle;

    sba_read32(BASE + 32'h10);                        // word now 0xBEEF00AB (LE)
    if (sba_rdata !== 32'hBEEF00AB) begin
        $display("ERROR: sub-word build [BASE+0x10]=%h (expected BEEF00AB) %t ns", sba_rdata, $time);
        error = error + 1;
    end else $display("PASS:  sub-word writes built [BASE+0x10]=%h %t ns", sba_rdata, $time);

    sba_cfg(1'b1, 1'b0, 1'b0, 3'd0);                 // 8-bit read of byte lane 3 (addr[1:0]=11)
    dmi_write(DMI_SBADDRESS0, BASE + 32'h13);
    sba_wait_idle;
    dmi_read(DMI_SBDATA0);
    if (dmi_readval !== 32'h000000BE) begin
        $display("ERROR: 8-bit read [BASE+0x13]=%h (expected 000000BE) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  8-bit read right-justified [BASE+0x13]=%h %t ns", dmi_readval, $time);

    sba_cfg(1'b1, 1'b0, 1'b0, 3'd1);                 // 16-bit read of half at offset 2
    dmi_write(DMI_SBADDRESS0, BASE + 32'h12);
    sba_wait_idle;
    dmi_read(DMI_SBDATA0);
    if (dmi_readval !== 32'h0000BEEF) begin
        $display("ERROR: 16-bit read [BASE+0x12]=%h (expected 0000BEEF) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  16-bit read right-justified [BASE+0x12]=%h %t ns", dmi_readval, $time);

    //========================================================================
    // E. Alignment error: a 32-bit access to a misaligned address -> sberror=3.
    //========================================================================
    sba_clr_err;
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd2);                 // 32-bit, readonaddr
    dmi_write(DMI_SBADDRESS0, BASE + 32'h1);          // misaligned for 32-bit
    sba_get_sberr;
    if (sba_sberr !== 3'd3) begin
        $display("ERROR: misaligned 32-bit access sberror=%0d (expected 3) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  alignment error sets sberror=3 %t ns", $time);

    // Spec corollary: while sberror!=0 NO new access is initiated. sbdata still
    // holds the stale 0x0000BEEF from Phase D; a valid aligned read of [BASE+0]
    // must be SUPPRESSED, so sbdata must NOT become WORD0 (0xcafebabe).
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd2);                 // 32-bit, aligned, valid target
    dmi_write(DMI_SBADDRESS0, BASE + 32'h0);          // would read WORD0 if not suppressed
    sba_wait_idle;
    dmi_read(DMI_SBDATA0);
    if (dmi_readval === WORD0) begin
        $display("ERROR: access initiated while sberror!=0 (sbdata=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  access suppressed while sberror!=0 (sbdata stale=%h) %t ns", dmi_readval, $time);

    sba_clr_err;
    sba_get_sberr;
    if (sba_sberr !== 3'd0) begin
        $display("ERROR: sberror did not W1C-clear (still %0d) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  sberror cleared by W1C %t ns", $time);

    // ...and the SAME read succeeds once sberror is cleared (proves it was the
    // suppression gate, not a bad address).
    sba_read32(BASE + 32'h0);
    if (sba_rdata !== WORD0) begin
        $display("ERROR: post-clear read [BASE+0]=%h (expected %h) %t ns", sba_rdata, WORD0, $time);
        error = error + 1;
    end else $display("PASS:  same read succeeds once sberror cleared (=%h) %t ns", sba_rdata, $time);

    //========================================================================
    // F. Unsupported size: sbaccess=3 (64-bit) -> sberror=4.
    //========================================================================
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd3);                 // 64-bit (unsupported), readonaddr
    dmi_write(DMI_SBADDRESS0, BASE + 32'h0);
    sba_get_sberr;
    if (sba_sberr !== 3'd4) begin
        $display("ERROR: unsupported-size access sberror=%0d (expected 4) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  unsupported size sets sberror=4 %t ns", $time);
    sba_clr_err;

    //========================================================================
    // G. Bus error: a 32-bit access to an unmapped address -> AHB HRESP error
    //    -> sberror=2 (address).
    //========================================================================
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd2);                 // 32-bit, readonaddr
    dmi_write(DMI_SBADDRESS0, 32'h10000000);          // unmapped -> HRESP error
    sba_wait_idle;                                    // access runs then faults
    sba_get_sberr;
    if (sba_sberr !== 3'd2) begin
        $display("ERROR: bus error sberror=%0d (expected 2=address) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  bus error sets sberror=2 (address) %t ns", $time);
    sba_clr_err;

    //========================================================================
    // Resume + firmware cross-check that the SBA write reached real memory.
    //========================================================================
    dm_resume;

    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, WORD2);     // [BASE+8] read back by firmware = SBA-written 0xDEADBEEF
    check_cpu_reg(21, WORD0);     // sentinel word0 intact

    // data_hmaster sideband: debug accesses tagged, software accesses never tagged.
    if (!hmaster_dbg_seen) begin
        $display("ERROR: data_hmaster never asserted during an SBA access %t ns", $time);
        error = error + 1;
    end else $display("PASS:  data_hmaster=1 tagged the SBA (debug) bus accesses %t ns", $time);
    if (hmaster_sw_violation) begin
        $display("ERROR: data_hmaster=1 on a hart (software) access outside Debug Mode %t ns", $time);
        error = error + 1;
    end else $display("PASS:  data_hmaster=0 on all hart (software) accesses %t ns", $time);

`ifndef FUSED_AHB
    if (sba_hmaster_cnt == 0) begin
        $display("ERROR: no SBA transfer reached a subordinate with HMASTER=9 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  %0d SBA transfer(s) reached a subordinate with HMASTER=9 %t ns", sba_hmaster_cnt, $time);
`endif

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_sba_running
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SBA on a RUNNING hart -> works, arbitrated onto the data port
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read and sba_* helpers (bench/verilog/debug_dmi_tasks.v).
//   The DM's system bus master shares the hart's data AHB port but ARBITRATES
//   for it (it is granted a cycle where the LSU is not issuing an address
//   phase), so system bus access no longer requires a halted hart:
//     - RUNNING READ  : sbcs.sbreadonaddr=1, write sbaddress0=<planted SRAM
//                       word> -> sberror=0 and sbdata0 returns the real word;
//     - LIVENESS      : the firmware loop counter (x5) must keep advancing
//                       across the accesses - proof the hart never halted and
//                       that arbitration is not starving either side;
//     - RUNNING WRITE : write sbdata0 -> lands in memory (read back over SBA
//                       now, and by the firmware after resume);
//     - RUNNING BLOCK : autoincrement + readonaddr + readondata block read, so
//                       several accesses arbitrate back-to-back against the
//                       hart's own load/store traffic;
//     - ERRORS        : a misaligned access still reports sberror=3 with no bus
//                       cycle while running, and W1C-clears;
//     - FAULT ISOLATION: an SBA access to an unmapped address takes an AHB
//                       HRESP error -> sberror=2 on the SBA side only. It must
//                       NOT raise a data load/store access fault in the hart
//                       (the bench monitor_excp_* checkers fail the test if it
//                       does), must not knock the firmware out of its loop, and
//                       must not corrupt the hart's own load data (x24);
//     - HALTED        : the same accesses still work once halted (regression on
//                       the original halted-only path);
//     - RESUME        : the firmware re-reads all three words -> final
//                       architectural check of what actually landed.
//   sbcs field positions (Debug Spec 1.0, cross-checked against
//   bench/verilog/debug_dmi_tasks.v): sbbusyerror[22] (W1C), sbbusy[21],
//   sbreadonaddr[20], sbaccess[19:17], sbautoincrement[16], sbreadondata[15],
//   sberror[14:12] (W1C).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
integer ctr_before, ctr_mid, ctr_after;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_SBCS       = 7'h38;
localparam [6:0] DMI_SBADDRESS0 = 7'h39;
localparam [6:0] DMI_SBDATA0    = 7'h3c;

// SRAM layout (planted by the firmware)
localparam [31:0] BASE    = 32'h80004000;
localparam [31:0] WORD0   = 32'hFEEDC0DE;   // planted at [BASE+0x00], never written
localparam [31:0] WR_RUN  = 32'hBAADF00D;   // SBA write over [BASE+0x04] while RUNNING
localparam [31:0] WR_HALT = 32'hD00DFEED;   // SBA write over [BASE+0x08] while HALTED

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
    $display("|  DEBUG SBA RUNNING: system bus access on a RUNNING hart, the SBA    |");
    $display("|  master arbitrating for the shared data AHB port                    |");
    $display(" ====================================================================");

    // Wait for the firmware to plant the SRAM words and start its bus-heavy loop.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111), SRAM planted %t ns", $time);

    // Bring the DM out of reset; do NOT halt the hart.
    dmi_write(7'h10, 32'h00000001);                  // dmcontrol = dmactive
    dmi_write(7'h10, 32'h10000001);                  // ackhavereset (clear sticky)

    // sanity: no error pending before the accesses
    sba_get_sberr;
    if (sba_sberr !== 3'd0) begin
        $display("ERROR: sberror=%0d before any SBA access (expected 0) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  sberror=0 before the running-hart accesses %t ns", $time);

    ctr_before = probes_cpu.x05;                       // firmware loop counter, pre-SBA

    //========================================================================
    // RUNNING READ: readonaddr + sbaddress0 write while the hart is executing
    // its store/load loop. Must return the real memory word, sberror=0.
    //========================================================================
    sba_read32(BASE + 32'h0);
    if (sba_rdata !== WORD0) begin
        $display("ERROR: running SBA read [BASE+0]=%h (expected planted %h) %t ns", sba_rdata, WORD0, $time);
        error = error + 1;
    end else $display("PASS:  running-hart SBA read returned the planted word %h %t ns", sba_rdata, $time);
    sba_get_sberr;
    if (sba_sberr !== 3'd0) begin
        $display("ERROR: sberror=%0d after the running read (expected 0) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  sberror=0 on the running-hart read %t ns", $time);

    // the hart must never have halted: dmstatus must still report allrunning
    dmi_read(7'h11);                                  // dmstatus
    if ((dmi_readval & 32'h00000800) === 32'h0) begin  // allrunning[11]
        $display("ERROR: dmstatus.allrunning=0 during running-hart SBA (hart stopped?) [%h] %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  dmstatus.allrunning=1 throughout the SBA access %t ns", $time);

    //========================================================================
    // LIVENESS: the firmware loop counter must keep advancing - the hart is
    // still executing, not wedged behind the debugger's use of the data bus.
    // Bounded WAIT rather than an instantaneous sample: one loop iteration is
    // 7 instructions with 2 bus accesses, which in the heavy wait-state
    // variants takes longer than a whole SBA transfer, so "advanced by now"
    // is a timing-dependent claim while "advances within N cycles" is not.
    //========================================================================
    to = 0;
    while ((probes_cpu.x05 <= ctr_before) && (to < 20000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x05 <= ctr_before) begin
        $display("ERROR: loop counter x5 stuck at %0d for %0d cycles after the SBA read %t ns", ctr_before, to, $time);
        error = error + 1;
    end else $display("PASS:  hart kept executing across the SBA read (x5 %0d -> %0d, %0d cycles) %t ns", ctr_before, probes_cpu.x05, to, $time);
    ctr_mid = probes_cpu.x05;

    //========================================================================
    // RUNNING WRITE: sbdata0 write while running -> must reach memory.
    //========================================================================
    sba_write32(BASE + 32'h4, WR_RUN);
    sba_get_sberr;
    if (sba_sberr !== 3'd0) begin
        $display("ERROR: sberror=%0d after the running write (expected 0) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  sberror=0 on the running-hart write %t ns", $time);

    sba_read32(BASE + 32'h4);
    if (sba_rdata !== WR_RUN) begin
        $display("ERROR: running SBA write/read-back [BASE+4]=%h (expected %h) %t ns", sba_rdata, WR_RUN, $time);
        error = error + 1;
    end else $display("PASS:  running-hart SBA write/read-back [BASE+4]=%h %t ns", sba_rdata, $time);

    //========================================================================
    // RUNNING BLOCK READ: autoincrement + readonaddr + readondata. Several
    // accesses arbitrate back-to-back against the hart's own bus traffic.
    //========================================================================
    sba_cfg(1'b1, 1'b1, 1'b1, 3'd2);                 // readonaddr, readondata, autoincr, 32-bit
    dmi_write(DMI_SBADDRESS0, BASE + 32'h0);         // triggers read of [BASE+0]
    sba_wait_idle;

    dmi_read(DMI_SBDATA0);                            // returns word0, arms read of [BASE+4]
    if (dmi_readval !== WORD0) begin
        $display("ERROR: running autoincr read[0]=%h (expected %h) %t ns", dmi_readval, WORD0, $time);
        error = error + 1;
    end else $display("PASS:  running autoincr read[0]=%h %t ns", dmi_readval, $time);
    sba_wait_idle;

    sba_cfg(1'b0, 1'b0, 1'b1, 3'd2);                 // drop readondata so the final read doesn't re-trigger
    dmi_read(DMI_SBDATA0);                            // returns word1 (= the running SBA write)
    if (dmi_readval !== WR_RUN) begin
        $display("ERROR: running autoincr read[1]=%h (expected %h) %t ns", dmi_readval, WR_RUN, $time);
        error = error + 1;
    end else $display("PASS:  running autoincr read[1]=%h %t ns", dmi_readval, $time);

    dmi_read(DMI_SBADDRESS0);                         // must have advanced 2 words: BASE+8
    if (dmi_readval !== (BASE + 32'h8)) begin
        $display("ERROR: sbaddress0 after running autoincr=%h (expected %h) %t ns", dmi_readval, BASE + 32'h8, $time);
        error = error + 1;
    end else $display("PASS:  sbaddress0 autoincremented to %h while running %t ns", dmi_readval, $time);

    //========================================================================
    // ERRORS still work while running: a misaligned 32-bit access reports
    // sberror=3 and starts no bus cycle; W1C clears it.
    //========================================================================
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd2);                 // 32-bit, readonaddr=1
    dmi_write(DMI_SBADDRESS0, BASE + 32'h1);          // misaligned -> sberror=3
    sba_get_sberr;
    if (sba_sberr !== 3'd3) begin
        $display("ERROR: running misaligned SBA: sberror=%0d (expected 3=alignment) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  running misaligned SBA sets sberror=3 %t ns", $time);

    sba_clr_err;
    sba_get_sberr;
    if (sba_sberr !== 3'd0) begin
        $display("ERROR: sberror did not W1C-clear while running (still %0d) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  sberror W1C-cleared while running %t ns", $time);

    //========================================================================
    // FAULTING SBA while running: a 32-bit access to an unmapped address gets
    // an AHB HRESP error -> sberror=2 on the SBA side ONLY. The error response
    // must not leak into the hart's load/store unit: no data load/store access
    // fault may be raised (the bench's monitor_excp_* checkers fail the test if
    // one is, error_on_exception=1), the firmware must stay in its spin loop
    // (x31 unchanged - a trap would have redirected it), and its own load data
    // must stay intact (x24 accumulator, checked after resume).
    //========================================================================
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd2);                 // 32-bit, readonaddr=1
    dmi_write(DMI_SBADDRESS0, 32'h10000000);          // unmapped -> HRESP error
    sba_wait_idle;                                    // access runs then faults
    sba_get_sberr;
    if (sba_sberr !== 3'd2) begin
        $display("ERROR: running SBA bus error: sberror=%0d (expected 2=address) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  running SBA bus error sets sberror=2 (address) %t ns", $time);

    if (probes_cpu.x31 !== 32'h11111111) begin
        $display("ERROR: hart left the spin loop (x31=%h) after the faulting SBA access - it trapped %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end else $display("PASS:  hart still in its spin loop after the faulting SBA access (no trap) %t ns", $time);

    sba_clr_err;
    sba_get_sberr;
    if (sba_sberr !== 3'd0) begin
        $display("ERROR: sberror did not W1C-clear after the running bus error (still %0d) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  sberror W1C-cleared after the running bus error %t ns", $time);

    // a normal access still works right after the faulting one
    sba_read32(BASE + 32'h0);
    if (sba_rdata !== WORD0) begin
        $display("ERROR: SBA read after the bus error [BASE+0]=%h (expected %h) %t ns", sba_rdata, WORD0, $time);
        error = error + 1;
    end else $display("PASS:  SBA read still works after the bus error (=%h) %t ns", sba_rdata, $time);

    // hart still alive after all of the above (bounded wait, as above)
    ctr_after = probes_cpu.x05;
    to = 0;
    while ((probes_cpu.x05 <= ctr_after) && (to < 20000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x05 <= ctr_after) begin
        $display("ERROR: loop counter x5 stuck at %0d for %0d cycles after the full SBA sequence %t ns", ctr_after, to, $time);
        error = error + 1;
    end else $display("PASS:  hart still executing after the full SBA sequence (x5 %0d -> %0d, %0d cycles) %t ns", ctr_after, probes_cpu.x05, to, $time);

    //========================================================================
    // HALTED: the same accesses still work (regression on the original path).
    //========================================================================
    dm_halt;

    sba_read32(BASE + 32'h0);
    if (sba_rdata !== WORD0) begin
        $display("ERROR: halted SBA read [BASE+0]=%h (expected %h) %t ns", sba_rdata, WORD0, $time);
        error = error + 1;
    end else $display("PASS:  halted SBA read returns the planted word %h %t ns", sba_rdata, $time);

    sba_write32(BASE + 32'h8, WR_HALT);              // overwrite the seed
    sba_read32 (BASE + 32'h8);
    if (sba_rdata !== WR_HALT) begin
        $display("ERROR: halted SBA write/read-back [BASE+8]=%h (expected %h) %t ns", sba_rdata, WR_HALT, $time);
        error = error + 1;
    end else $display("PASS:  halted SBA write/read-back [BASE+8]=%h %t ns", sba_rdata, $time);
    sba_get_sberr;
    if (sba_sberr !== 3'd0) begin
        $display("ERROR: sberror=%0d after the halted accesses (expected 0) %t ns", sba_sberr, $time);
        error = error + 1;
    end else $display("PASS:  sberror=0 on the halted accesses %t ns", $time);

    //========================================================================
    // Resume + firmware cross-check.
    //========================================================================
    dm_resume;

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, WORD0);     // [BASE+0] untouched
    check_cpu_reg(21, WR_RUN);    // [BASE+4] = the SBA write performed while RUNNING
    check_cpu_reg(23, WR_HALT);   // [BASE+8] = the SBA write performed while HALTED
    check_cpu_reg(24, 32'h0);     // every spin-loop load returned its own store: no SBA
                                  // read data (or ERROR response) ever leaked into the LSU

`ifndef FUSED_AHB
    if (sba_hmaster_cnt == 0) begin
        $display("ERROR: no SBA transfer reached a subordinate with HMASTER=9 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  %0d SBA transfer(s) reached a subordinate with HMASTER=9 %t ns", sba_hmaster_cnt, $time);
`endif

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_reset_pmp_lock_all
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: every implemented PMP entry locked, every pmpcfg / pmpaddr
//   write ignored, then an ndmreset clears all of them
//   (see debug_reset_pmp_lock_all.s)
//   Priv 3.7.1: "If PMP entry i is locked, writes to pmpicfg and pmpaddri
//   are ignored. Additionally, if PMP entry i is locked and pmpicfg.A is set
//   to TOR, writes to pmpaddri-1 are ignored." Priv 6.2: "PMP reset: ... all
//   PMP settings of the hart, including locked rules/settings, are
//   re-initialized". Debug 1.0 dmcontrol.ndmreset: "To perform a hardware
//   platform reset the debugger writes 1, and then writes 0".
//
//   N = 16 / 8 / 4 for PMP_NR >= 16 / >= 8 / otherwise.
//   First boot  (x31 = 11111111): pmpcfgK = 0x8F8F8F8F for 4K < N else 0,
//               pmpaddrN-1 = 0x20800000, every other pmpaddr 0; the same
//               values after csrw x0 / csrc L-bits / pmpaddr rewrites.
//   ndmreset    dmcontrol.ndmreset written 1 then 0 over the DMI.
//   Second boot (x31 = deadbeef): all pmpcfg / pmpaddr read 0; entry N-1
//               cfg byte, pmpaddrN-1 and pmpaddrN-2 writable; no trap.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

integer to, ne;
reg [31:0] exp_val;

localparam [6:0]  DMI_DMCONTROL  = 7'h10;
localparam [6:0]  DMI_DMSTATUS   = 7'h11;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;
localparam [31:0] DMS_ALLHAVERST = 32'h00080000;

localparam [31:0] BOOT_MAGIC     = 32'h5EC0B00F;
localparam [31:0] TOP_ADDR       = 32'h20800000;

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

    ne = (PMP_NR >= 16) ? 16 : ((PMP_NR >= 8) ? 8 : 4);

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG RESET PMP LOCK ALL: %0d locked entries cleared by ndmreset   |", ne);
    $display(" ====================================================================");

    //========================================================================
    // FIRST BOOT: every entry locked, every write ignored
    //========================================================================
    wait (probes_cpu.x31 === 32'h11111111);
    repeat(40) @(posedge free_clk);

    check_mem_value(`SPAD(32'h00), BOOT_MAGIC);
    for (kk = 0; kk < 4; kk = kk + 1) begin
        exp_val = ((4*kk) < ne) ? 32'h8F8F8F8F : 32'h00000000;
        $display("INFO:  pmpcfg%0d after lock / csrw x0 / csrc L", kk);
        check_mem_value(`SPAD(32'h040 + 4*kk), exp_val);
        check_mem_value(`SPAD(32'h050 + 4*kk), exp_val);
        check_mem_value(`SPAD(32'h060 + 4*kk), exp_val);
    end
    for (ii = 0; ii < 16; ii = ii + 1) begin
        exp_val = (ii == (ne-1)) ? TOP_ADDR : 32'h00000000;
        $display("INFO:  pmpaddr%0d after lock / rewrite", ii);
        check_mem_value(`SPAD(32'h080 + 4*ii), exp_val);
        check_mem_value(`SPAD(32'h0C0 + 4*ii), exp_val);
    end
    check_mem_value(`SPAD(32'h08), 32'h00000000);   // no trap

    //========================================================================
    // ndmreset: DM activated in its own write, POR havereset acked, pulse
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    to = 0;
    dmi_read(DMI_DMCONTROL);
    while (((dmi_readval & DMC_DMACTIVE) === 32'h0) && (to < 50)) begin
        dmi_read(DMI_DMCONTROL);
        to = to + 1;
    end
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_ndmreset_pulse;
    $display("INFO:  ndmreset pulsed %t ns", $time);

    //========================================================================
    // SECOND BOOT: everything back at 0 and writable
    //========================================================================
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 60000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: second boot did not reach 0xdeadbeef (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    for (kk = 0; kk < 4; kk = kk + 1) begin
        $display("INFO:  pmpcfg%0d after ndmreset", kk);
        check_mem_value(`SPAD(32'h100 + 4*kk), 32'h00000000);
    end
    for (ii = 0; ii < 16; ii = ii + 1) begin
        $display("INFO:  pmpaddr%0d after ndmreset", ii);
        check_mem_value(`SPAD(32'h140 + 4*ii), 32'h00000000);
    end
    $display("INFO:  entry %0d writable again (cfg, pmpaddr%0d, pmpaddr%0d), then cleared", ne-1, ne-1, ne-2);
    check_mem_value(`SPAD(32'h180), 32'h09000000);
    check_mem_value(`SPAD(32'h184), 32'h00001234);
    check_mem_value(`SPAD(32'h188), 32'h00000456);
    check_mem_value(`SPAD(32'h18C), 32'h00000000);
    check_mem_value(`SPAD(32'h190), 32'h00000000);
    check_mem_value(`SPAD(32'h194), 32'h00000000);
    check_mem_value(`SPAD(32'h08), 32'h00000000);   // no trap on either boot

    dmi_read(DMI_DMSTATUS);
    if ((dmi_readval & DMS_ALLHAVERST) === 32'h0) begin
        $display("ERROR: dmstatus.allhavereset = 0 after the ndmreset %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dmstatus.allhavereset = 1 after the ndmreset %t ns", $time);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

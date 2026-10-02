//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_reset_sticky_state
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Smepmp sticky bits and locked PMP rules hold until a reset,
//   and an ndmreset clears them (see debug_reset_sticky_state.s)
//   Priv 6.2: MML/MMWP "once set it cannot be unset until a PMP reset";
//   "PMP reset: A reset process where all PMP settings of the hart,
//   including locked rules/settings, are re-initialized to a set of safe
//   defaults". Debug 1.0 dmcontrol.ndmreset: "This bit controls the reset
//   signal from the DM to the rest of the hardware platform ... To perform
//   a hardware platform reset the debugger writes 1, and then writes 0".
//
//   First boot  (x31 = 11111111): MML|MMWP set, rules locked, every clear /
//               rewrite attempt ignored; minstret > 400 (ZICNTR_EN).
//   ndmreset    dmcontrol.ndmreset written 1 then 0 over the DMI.
//   Second boot (x31 = deadbeef): mseccfg, pmpcfg0, pmpaddr0..2 read 0,
//               minstret < 100, the formerly locked byte / pmpaddr and
//               mseccfg.RLB are writable again, no trap on either boot.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

integer to;

localparam [6:0]  DMI_DMCONTROL  = 7'h10;
localparam [6:0]  DMI_DMSTATUS   = 7'h11;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;
localparam [31:0] DMS_ALLHAVERST = 32'h00080000;

localparam [31:0] BOOT_MAGIC     = 32'h5EC0B007;

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
    $display("|  DEBUG RESET STICKY STATE: Smepmp / PMP locks cleared by ndmreset  |");
    $display(" ====================================================================");

    //========================================================================
    // FIRST BOOT: sticky / locked state established, writes ignored
    //========================================================================
    wait (probes_cpu.x31 === 32'h11111111);
    repeat(40) @(posedge free_clk);

    check_cpu_reg(10, 32'h009B8D00);   // a0: pmpcfg0 after locking
    check_cpu_reg(11, 32'h00000003);   // a1: mseccfg = MML|MMWP
    check_cpu_reg(14, 32'h00000003);   // a4: mseccfg after clear attempts
    check_cpu_reg(15, 32'h009B8D00);   // a5: pmpcfg0 after <- 0
    check_cpu_reg(16, 32'h08004000);   // a6: locked pmpaddr1
    check_cpu_reg(17, 32'h08000000);   // a7: pmpaddr0 below the locked TOR entry
    check_cpu_reg(18, 32'h20001FFF);   // s2: locked pmpaddr2
    check_cpu_reg(19, 32'h00000000);   // s3: no trap
    if (ZICNTR_EN != 0) begin
        $display("INFO:  first boot time = 0x%h, minstret = %0d %t ns", probes_cpu.x12, probes_cpu.x13, $time);
        if (probes_cpu.x13 <= 32'd400) begin
            $display("ERROR: first boot minstret = %0d (expected > 400) %t ns", probes_cpu.x13, $time);
            error = error + 1;
        end else $display("PASS:  first boot minstret = %0d (> 400) %t ns", probes_cpu.x13, $time);
    end
    check_mem_value(`SPAD(32'h00), BOOT_MAGIC);

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
    // SECOND BOOT: everything back at its reset value and writable
    //========================================================================
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 20000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: second boot did not reach 0xdeadbeef (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    check_cpu_reg(20, 32'h00000000);   // s4: mseccfg
    check_cpu_reg(21, 32'h00000000);   // s5: pmpcfg0
    check_cpu_reg(22, 32'h00000000);   // s6: pmpaddr0
    check_cpu_reg(23, 32'h00000000);   // s7: pmpaddr1
    check_cpu_reg(24, 32'h00000000);   // s8: pmpaddr2
    check_cpu_reg(26, 32'h00000900);   // s10: formerly locked cfg byte written
    check_cpu_reg(27, 32'h00001234);   // s11: formerly locked pmpaddr1 written
    check_cpu_reg(10, 32'h00000004);   // a0: mseccfg.RLB accepted again
    check_cpu_reg(11, 32'h00000000);   // a1: mseccfg.RLB cleared
    check_cpu_reg(12, 32'h00000000);   // a2: no trap
    if (ZICNTR_EN != 0) begin
        if (probes_cpu.x25 >= 32'd100) begin
            $display("ERROR: second boot minstret = %0d (expected < 100: counter reset) %t ns", probes_cpu.x25, $time);
            error = error + 1;
        end else $display("PASS:  second boot minstret = %0d (< 100) %t ns", probes_cpu.x25, $time);
    end
    check_mem_value(`SPAD(32'h08), 32'h00000000);

    dmi_read(DMI_DMSTATUS);
    if ((dmi_readval & DMS_ALLHAVERST) === 32'h0) begin
        $display("ERROR: dmstatus.allhavereset = 0 after the ndmreset %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dmstatus.allhavereset = 1 after the ndmreset %t ns", $time);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

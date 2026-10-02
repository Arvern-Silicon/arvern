//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_critical_error_pc_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: critical-error PC reported for walking PC address bits
//   See debug_critical_error_pc_walk.s. The executable-SRAM alias is armed for
//   the whole test. Per sample (62, one per boot):
//     - lockup_o = 1, no Debug Mode (cetrig = 0)
//     - the firmware's published target equals this bench's expectation
//     - haltreq halts the hart; abstract-read dpc == target PC
//       (debug_interface.md: a hart in the critical-error state "can be
//       halted; dpc names the instruction it stopped on")
//     - ndmreset = 1: lockup_o = 0 while held (critical-error state "cleared
//       by reset only"); ndmreset = 0: the hart reboots
//   Final boot reaches deadbeef with the sample index at 62.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

`define SPAD(byte_off)  ((byte_off)/4)

integer to, idx, nerr_dpc;

reg [31:0] exp_pc, pub_pc, dpc_val, sync_val;

localparam integer NSAMPLES = 62;

localparam [6:0]  DMI_DATA0       = 7'h04;
localparam [6:0]  DMI_DMCONTROL   = 7'h10;
localparam [6:0]  DMI_DMSTATUS    = 7'h11;
localparam [6:0]  DMI_ABSTRACTCS  = 7'h16;
localparam [6:0]  DMI_COMMAND     = 7'h17;

localparam [31:0] DMC_DMACTIVE    = 32'h00000001;
localparam [31:0] DMC_NDMRESET    = 32'h00000002;
localparam [31:0] DMC_ACKHAVERST  = 32'h10000000;
localparam [31:0] DMC_HALTREQ     = 32'h80000000;

localparam [31:0] DMS_ALLHALTED   = 32'h00000200;
localparam [31:0] DMS_ALLHAVERST  = 32'h00080000;

localparam [31:0] ACS_BUSY        = 32'h00001000;
localparam [31:0] ACS_CMDERR      = 32'h00000700;

// Access Register read: aarsize=2 | transfer=1 | regno = dpc (0x7b1)
localparam [31:0] CMD_RD_DPC      = 32'h00220000 | 32'h000007b1;

// Target PC of sample i (same table as the firmware).
function [31:0] sample_pc;
   input integer i;
   integer k;
   reg [31:0] v;
   begin
      if (i < 31) begin
         k = i + 1;
         if (k < 12)       v = 32'h00010000 | (32'h1 << k);
         else if (k == 25) v = 32'h02010000;
         else if (k == 29) v = 32'h21000000;
         else              v = 32'h1 << k;
      end else begin
         k = i - 30;
         v = 32'hFFFFFFFE & ~(32'h1 << k);
         if ((k <= 8) || (k >= 16)) v = v & 32'hFFFF7FFF;
      end
      if (C_EXTENSION == 0) v = v & 32'hFFFFFFFC;
      sample_pc = v;
   end
endfunction

task chk;
   input [8*64:1] what;
   input [31:0]   got;
   input [31:0]   exp;
   begin
      if (got !== exp) begin
         $display("ERROR: %0s = %h (expected %h) %t ns", what, got, exp, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s = %h %t ns", what, got, $time);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);
    ahb_bus_system_inst.sram_x_alias_en = 1'b1;

    error_on_exception = 0;             // every sample's ecall + the final boot's

    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    $display("");
    $display(" ====================================================================");
    $display("|  CRITICAL ERROR PC WALK: dpc of a locked-up hart, PC bits walked   |");
    $display(" ====================================================================");

    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    to = 0;
    dmi_read(DMI_DMCONTROL);
    while (((dmi_readval & DMC_DMACTIVE) === 32'h0) && (to < 50)) begin
        dmi_read(DMI_DMCONTROL);
        to = to + 1;
    end
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);   // POR havereset acked

    nerr_dpc = 0;
    for (idx = 0; idx < NSAMPLES; idx = idx + 1) begin
        exp_pc   = sample_pc(idx);
        sync_val = 32'h11110000 | idx;
        $display("");
        $display("--- sample %0d: PC 0x%h ---", idx, exp_pc);

        // Level waits: under a slow DTM the boot may already be locked up.
        to = 0;
        while ((probes_cpu.x31 !== sync_val) && (to < 5000)) begin
            @(posedge free_clk);
            to = to + 1;
        end
        chk("x31 sample sync", probes_cpu.x31, sync_val);
        to = 0;
        while ((lockup !== 1'b1) && (to < 2000)) begin
            @(posedge free_clk);
            to = to + 1;
        end
        repeat(5) @(posedge free_clk);
        chk("lockup_o", {31'd0, lockup}, 32'd1);
        chk("dbg_debug_mode (cetrig=0)", {31'd0, dbg_debug_mode}, 32'd0);

        pub_pc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C04)];
        chk("firmware target == bench table", pub_pc, exp_pc);

        // Halt the dead hart and read dpc.
        dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
        to = 0;
        dmi_read(DMI_DMSTATUS);
        while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
            dmi_read(DMI_DMSTATUS);
            to = to + 1;
        end
        chk("dmstatus.allhalted", (dmi_readval & DMS_ALLHALTED) >> 9, 32'd1);
        chk("dbg_debug_mode after haltreq", {31'd0, dbg_debug_mode}, 32'd1);

        dmi_write(DMI_COMMAND, CMD_RD_DPC);
        to = 0;
        dmi_read(DMI_ABSTRACTCS);
        while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
            dmi_read(DMI_ABSTRACTCS);
            to = to + 1;
        end
        chk("abstractcs.cmderr", (dmi_readval & ACS_CMDERR) >> 8, 32'd0);
        dmi_read(DMI_DATA0);
        dpc_val = dmi_readval;
        if (dpc_val !== exp_pc) nerr_dpc = nerr_dpc + 1;
        chk("dpc == PC of the instruction the hart died on", dpc_val, exp_pc);

        // ndmreset pulse, haltreq dropped so the hart reboots.
        dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_NDMRESET);
        repeat(8) @(posedge free_clk);
        chk("lockup_o while ndmreset=1", {31'd0, lockup}, 32'd0);
        dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    end

    //=================================================================
    // Final boot
    //=================================================================
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 20000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    chk("final boot x31", probes_cpu.x31, 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    $display("");
    $display("dpc mismatches: %0d of %0d samples", nerr_dpc, NSAMPLES);
    chk("lockup_o at the end", {31'd0, lockup}, 32'd0);
    check_mem_value(`SPAD(32'h0C00), NSAMPLES);

    dmi_read(DMI_DMSTATUS);
    chk("dmstatus.allhavereset before the ack", (dmi_readval & DMS_ALLHAVERST) >> 19, 32'd1);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dmi_read(DMI_DMSTATUS);
    chk("dmstatus.allhavereset after the ack", (dmi_readval & DMS_ALLHAVERST) >> 19, 32'd0);

    ahb_bus_system_inst.sram_x_alias_en = 1'b0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

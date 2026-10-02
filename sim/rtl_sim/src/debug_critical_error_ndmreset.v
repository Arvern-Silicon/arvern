//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_critical_error_ndmreset
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: recovery from the Smdbltrp critical-error state by an ndmreset
//   The critical-error state (lockup_o) is cleared by reset only. Debug 1.0:
//   "When harts have been reset, they must set a sticky havereset state bit";
//   dmcontrol.ndmreset "To perform a hardware platform reset the debugger
//   writes 1, and then writes 0". debug_interface.md: anyunavail/allunavail
//   "= hart held in reset by ndmreset"; havereset "is set on power-on, on an
//   ndmreset ... sticky until ackhavereset".
//
//   A  boot 1 enters the critical-error state: lockup_o = 1, no Debug Mode.
//   B  DM activated, POR havereset acked: allhavereset = 0.
//   C  ndmreset = 1: allunavail = 1, lockup_o = 0 while the hart is in reset.
//   D  ndmreset = 0: lockup_o stays 0, allhavereset = anyhavereset = 1.
//   E  boot 2 runs from the reset vector to deadbeef (boot counter 2, one
//      handled ecall, boot 1 never ran past its ecall); allhavereset still
//      1 until ackhavereset, then 0.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

integer to;

localparam [6:0]  DMI_DMCONTROL   = 7'h10;
localparam [6:0]  DMI_DMSTATUS    = 7'h11;

localparam [31:0] DMC_DMACTIVE    = 32'h00000001;
localparam [31:0] DMC_NDMRESET    = 32'h00000002;
localparam [31:0] DMC_ACKHAVERST  = 32'h10000000;

localparam [31:0] DMS_ALLUNAVAIL  = 32'h00002000;
localparam [31:0] DMS_ANYHAVERST  = 32'h00040000;
localparam [31:0] DMS_ALLHAVERST  = 32'h00080000;

task chk;
   input [8*56:1] what;
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

    error_on_exception = 0;             // boot 1's ecall and boot 2's handled ecall

    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    $display("");
    $display(" ====================================================================");
    $display("|  CRITICAL ERROR RECOVERY: ndmreset clears lockup_o, hart reboots    |");
    $display(" ====================================================================");

    //=================================================================
    // A: critical error on boot 1
    //=================================================================
    wait (probes_cpu.x31 === 32'h11111111);
    to = 0;
    while ((lockup !== 1'b1) && (to < 2000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    repeat(5) @(posedge free_clk);
    chk("A: lockup_o after the unexpected trap", {31'd0, lockup}, 32'd1);
    chk("A: dbg_debug_mode (cetrig=0)",        {31'd0, dbg_debug_mode}, 32'd0);

    //=================================================================
    // B: DM up, POR havereset acknowledged
    //=================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    to = 0;
    dmi_read(DMI_DMCONTROL);
    while (((dmi_readval & DMC_DMACTIVE) === 32'h0) && (to < 50)) begin
        dmi_read(DMI_DMCONTROL);
        to = to + 1;
    end
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dmi_read(DMI_DMSTATUS);
    chk("B: dmstatus.allhavereset after the POR ack", (dmi_readval & DMS_ALLHAVERST) >> 19, 32'd0);

    //=================================================================
    // C: ndmreset held
    //=================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_NDMRESET);
    repeat(8) @(posedge free_clk);
    dmi_read(DMI_DMSTATUS);
    chk("C: dmstatus.allunavail while ndmreset=1", (dmi_readval & DMS_ALLUNAVAIL) >> 13, 32'd1);
    chk("C: lockup_o while the hart is in reset", {31'd0, lockup}, 32'd0);

    //=================================================================
    // D: ndmreset released
    //=================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    repeat(5) @(posedge free_clk);
    chk("D: lockup_o after the ndmreset", {31'd0, lockup}, 32'd0);
    dmi_read(DMI_DMSTATUS);
    chk("D: dmstatus.allhavereset after the ndmreset", (dmi_readval & DMS_ALLHAVERST) >> 19, 32'd1);
    chk("D: dmstatus.anyhavereset after the ndmreset", (dmi_readval & DMS_ANYHAVERST) >> 18, 32'd1);
    to = 0;
    while (((dmi_readval & DMS_ALLUNAVAIL) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    chk("D: dmstatus.allunavail after the release",   (dmi_readval & DMS_ALLUNAVAIL) >> 13, 32'd0);

    //=================================================================
    // E: boot 2 completes; havereset sticky until acknowledged
    //=================================================================
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 20000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: boot 2 did not reach 0xdeadbeef (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    chk("E: lockup_o at the end of boot 2", {31'd0, lockup}, 32'd0);
    check_mem_value(`SPAD(32'h00), 32'd2);   // two boots from the reset vector
    check_mem_value(`SPAD(32'h04), 32'd1);   // boot 2's ecall handled once
    check_mem_value(`SPAD(32'h0C), 32'd0);   // boot 1 never ran past its ecall

    dmi_read(DMI_DMSTATUS);
    chk("E: dmstatus.allhavereset before the ack", (dmi_readval & DMS_ALLHAVERST) >> 19, 32'd1);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dmi_read(DMI_DMSTATUS);
    chk("E: dmstatus.allhavereset after ackhavereset", (dmi_readval & DMS_ALLHAVERST) >> 19, 32'd0);
    chk("E: dmstatus.anyhavereset after ackhavereset", (dmi_readval & DMS_ANYHAVERST) >> 18, 32'd0);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

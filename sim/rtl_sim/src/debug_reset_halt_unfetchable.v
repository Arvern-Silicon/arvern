//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_reset_halt_unfetchable
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdext halt-on-reset when the reset vector cannot be fetched.
//   The ROM's err-word hook answers the fetch of the reset vector with an AHB ERROR.
//   With resethaltreq set, an ndmreset must halt the hart ONCE out of reset (cause 5,
//   dpc = reset vector: Debug 1.0 "halt ... as soon as it comes out of reset"; the
//   request acts on a reset, not on every resume). The debugger then removes the
//   fault, leaves resethaltreq SET and resumes: the hart must run (its second boot
//   reaches 0xdeadbeef, see the .s), not halt again with cause 5.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

reg [31:0] dcsr_val, dpc_val, ins_val, dms_val;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

// dmcontrol field constants
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset

// dmstatus field masks
localparam [31:0] DMS_ALLHALTED     = 32'h00000200; // [9]
localparam [31:0] DMS_ALLRUNNING    = 32'h00000800; // [11]
localparam [31:0] DMS_HASRESETHALT  = 32'h00000020; // [5]  hasresethaltreq
localparam [31:0] DMS_ALLHAVERESET  = 32'h00080000; // [19] allhavereset

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0, aarsize=2, transfer=1)
//   regno = the 12-bit CSR address directly
localparam [31:0] CMD_RD_DCSR     = 32'h00200000 | 32'h00020000 | 32'h000007b0; // = 0x002207b0
localparam [31:0] CMD_RD_DPC      = 32'h00200000 | 32'h00020000 | 32'h000007b1; // = 0x002207b1
localparam [31:0] CMD_RD_MINSTRET = 32'h00200000 | 32'h00020000 | 32'h00000b02; // = 0x00220b02

localparam [31:0] EXPECTED_RESET_PC = 32'h20000000; // value dpc must hold after reset-halt (= tb RESET_VECTOR / .text base)
localparam [31:0] X5_MARKER     = 32'h1234ABCD; // reset-vector instruction marker
localparam [31:0] X18_SENTINEL  = 32'hA5A5A5A5;

// Issue an abstract command and wait for abstractcs.busy to clear; the final
// abstractcs value (incl. cmderr) is left in dmi_readval. data0 read-back, when
// needed, is a separate dmi_read(DMI_DATA0).
task abs_run;
   input [31:0] cmd;
   begin
      dmi_write(DMI_COMMAND, cmd);
      to = 0;
      dmi_read(DMI_ABSTRACTCS);
      while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
         dmi_read(DMI_ABSTRACTCS);
         to = to + 1;
      end
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);
    error_on_exception = 0;                            // the reset-vector fetch fault is intended

    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG RESET-HALT: unfetchable reset vector, one halt per reset     |");
    $display(" ====================================================================");

    @(probes_cpu.x31==32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    ahb_bus_system_inst.ahb_waitstate_inserter_rom_inst.err_word_addr = EXPECTED_RESET_PC;
    ahb_bus_system_inst.ahb_waitstate_inserter_rom_inst.err_word_ws   = 32'd0;
    ahb_bus_system_inst.ahb_waitstate_inserter_rom_inst.err_word_en   = 1'b1;

    dm_reset_halt;                                     // resethaltreq set, ndmreset pulse

    abs_run(CMD_RD_DCSR);
    dmi_read(DMI_DATA0);
    dcsr_val = dmi_readval;
    if (((dcsr_val >> 6) & 32'h7) !== 32'd5) begin
        $display("ERROR: dcsr.cause=%0d (expected 5=resethaltreq) %t ns", (dcsr_val >> 6) & 32'h7, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.cause=5 on the unfetchable reset vector %t ns", $time);
    abs_run(CMD_RD_DPC);
    dmi_read(DMI_DATA0);
    dpc_val = dmi_readval;
    if (dpc_val !== EXPECTED_RESET_PC) begin
        $display("ERROR: dpc=%h (expected reset vector %h) %t ns", dpc_val, EXPECTED_RESET_PC, $time);
        error = error + 1;
    end else $display("PASS:  dpc = reset vector %t ns", $time);

    ahb_bus_system_inst.ahb_waitstate_inserter_rom_inst.err_word_en   = 1'b0;   // vector fetchable again
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_resume;                                         // resethaltreq still set

    repeat(60) @(posedge free_clk);
    dmi_read(DMI_DMSTATUS);
    if ((dmi_readval & 32'h00000200) !== 32'h0) begin
        $display("ERROR: hart halted again after resume (resethaltreq must act once per reset) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart running after resume, no second reset-halt %t ns", $time);

    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 20000)) begin @(posedge free_clk); to = to + 1; end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: firmware did not finish its second boot (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end else $display("PASS:  firmware re-booted from the reset vector %t ns", $time);

    dm_clr_resethaltreq;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_stopcount
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DMI dcsr.stopcount freezes mcycle while halted (Debug Spec 1.0)
//   Drives the hclk-domain DMI bus (no DTM) via the dmi_write/dmi_read helpers.
//   Halts the spinning hart, then via the Debug Module abstract "Access Register"
//   command proves the dcsr.stopcount semantics on the machine cycle counter:
//
//     dcsr.stopcount (CSR 0x7b0, bit 10) = 1  -> mcycle (CSR 0xB00) STOPS counting
//                                                while the hart is in Debug Mode.
//     dcsr.stopcount                     = 0  -> mcycle keeps counting in Debug Mode.
//
//   Sequence (all while halted in Debug Mode):
//     1. halt via dmcontrol.haltreq; confirm allhalted + dbg_debug_mode.
//     2. read-modify-write dcsr to SET stopcount (preserving prv[1:0] so the hart
//        resumes back into M-mode); read mcycle -> cyc_a; wait; read mcycle ->
//        cyc_b. Assert cyc_b == cyc_a (FROZEN). <-- headline check.
//     3. read-modify-write dcsr to CLEAR stopcount; read mcycle -> cyc_c; wait;
//        read mcycle -> cyc_d. Assert cyc_d > cyc_c (ADVANCING). <-- headline check.
//     4. resume; confirm allrunning; firmware reaches 0xdeadbeef (proves resume).
//
//   dcsr / mcycle are reached by the same abstract Access Register routing used by
//   debug_dmi_csr for mscratch (regno = the 12-bit CSR address directly). The
//   data0 read-back uses no dedicated task: it is dmi_read(DMI_DATA0) followed by
//   inspecting dmi_readval.
//
//   NOTE (negative control): if the RTL stopcount gate is removed, mcycle keeps
//   counting during halt and the FROZEN assertion (cyc_b == cyc_a) fails loudly.
//   The ADVANCING assertion assumes mcountinhibit.CY=0 (reset default); if mcycle
//   does not advance here, confirm mcountinhibit first.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

reg [31:0] cyc_a, cyc_b, cyc_c, cyc_d;
reg [31:0] ins_a, ins_b;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

// dmcontrol field constants
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_HALTREQ    = 32'h80000000;  // [31] haltreq
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;  // [30] resumereq
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset

// dmstatus field masks
localparam [31:0] DMS_ALLHALTED    = 32'h00000200; // [9]
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800; // [11]
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000; // [17]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0, aarsize=2, transfer=1)
//   regno = the 12-bit CSR address directly
localparam [31:0] CMD_RD_DCSR     = 32'h00200000 | 32'h00020000 |              32'h000007b0; // = 0x002207b0
localparam [31:0] CMD_WR_DCSR     = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h000007b0; // = 0x002307b0
localparam [31:0] CMD_RD_MCYCLE   = 32'h00200000 | 32'h00020000 |              32'h00000b00; // = 0x00220b00
localparam [31:0] CMD_RD_MINSTRET = 32'h00200000 | 32'h00020000 |              32'h00000b02; // = 0x00220b02

// dcsr fields
localparam [31:0] DCSR_STOPCOUNT = 32'h00000400; // [10] stopcount

localparam [31:0] X18_SENTINEL = 32'hA5A5A5A5;

// Issue an abstract command and wait for abstractcs.busy to clear; the final
// abstractcs value (incl. cmderr) is left in dmi_readval. (data0 read-back, when
// needed, is a separate dmi_read(DMI_DATA0); there is no dedicated task for it.)
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

    // Reset peripherals
    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG DMI STOPCOUNT: dcsr.stopcount freezes mcycle while halted     |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);  // clear sticky havereset

    // --- halt the hart via dmcontrol.haltreq, poll dmstatus.allhalted ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: hart did not halt on dmcontrol.haltreq (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart halted via DMI haltreq (allhalted=1, %0d polls) %t ns", to, $time);

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode (abstract CSR access permitted) %t ns", $time);

    //========================================================================
    // PHASE 1: dcsr.stopcount = 1 -> mcycle FROZEN while halted.
    //   Read-modify-write dcsr so prv[1:0] (and step) are preserved.
    //========================================================================
    abs_run(CMD_RD_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);                                  // dmi_readval = current dcsr
    dmi_write(DMI_DATA0, dmi_readval | DCSR_STOPCOUNT);   // set stopcount, keep the rest
    abs_run(CMD_WR_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr write (set stopcount) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.stopcount set (read-modify-write, prv preserved) %t ns", $time);

    // first mcycle sample
    abs_run(CMD_RD_MCYCLE);
    @(posedge dut_hclk);                                  // let counter/data0 settle
    dmi_read(DMI_DATA0);
    cyc_a = dmi_readval;
    // also sample minstret once (non-discriminating: no instr retire while halted)
    abs_run(CMD_RD_MINSTRET);
    @(posedge dut_hclk);
    dmi_read(DMI_DATA0);
    ins_a = dmi_readval;

    // burn a meaningful number of core clocks while still halted
    repeat (200) @(posedge dut_hclk);

    // second mcycle sample — must be identical (frozen)
    abs_run(CMD_RD_MCYCLE);
    @(posedge dut_hclk);
    dmi_read(DMI_DATA0);
    cyc_b = dmi_readval;
    abs_run(CMD_RD_MINSTRET);
    @(posedge dut_hclk);
    dmi_read(DMI_DATA0);
    ins_b = dmi_readval;

    if (cyc_b !== cyc_a) begin
        $display("ERROR: mcycle ADVANCED while stopcount=1 (cyc_a=%h cyc_b=%h) -- NOT frozen %t ns", cyc_a, cyc_b, $time);
        error = error + 1;
    end else $display("PASS:  mcycle FROZEN with stopcount=1 (cyc_a=cyc_b=%h) %t ns", cyc_a, $time);

    // minstret can never advance while halted (abstract access retires nothing);
    // this is a consistency check only, explicitly NOT a stopcount discriminator.
    if (ins_b !== ins_a) begin
        $display("ERROR: minstret changed while halted (ins_a=%h ins_b=%h) -- unexpected %t ns", ins_a, ins_b, $time);
        error = error + 1;
    end else $display("PASS:  minstret stable while halted (ins=%h) [non-discriminating] %t ns", ins_a, $time);

    //========================================================================
    // PHASE 2: dcsr.stopcount = 0 -> mcycle ADVANCES while halted.
    //========================================================================
    abs_run(CMD_RD_DCSR);
    dmi_read(DMI_DATA0);                                  // dmi_readval = current dcsr
    dmi_write(DMI_DATA0, dmi_readval & ~DCSR_STOPCOUNT);  // clear stopcount, keep the rest
    abs_run(CMD_WR_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr write (clear stopcount) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.stopcount cleared (read-modify-write, prv preserved) %t ns", $time);

    abs_run(CMD_RD_MCYCLE);
    @(posedge dut_hclk);
    dmi_read(DMI_DATA0);
    cyc_c = dmi_readval;

    repeat (200) @(posedge dut_hclk);

    abs_run(CMD_RD_MCYCLE);
    @(posedge dut_hclk);
    dmi_read(DMI_DATA0);
    cyc_d = dmi_readval;

    if (cyc_d === cyc_c) begin
        $display("ERROR: mcycle did NOT advance with stopcount=0 (cyc_c=cyc_d=%h) -- check mcountinhibit %t ns", cyc_c, $time);
        error = error + 1;
    end else if (cyc_d < cyc_c) begin
        // only legitimate if a 32-bit wrap occurred; not expected over ~200 cycles
        $display("ERROR: mcycle went backwards with stopcount=0 (cyc_c=%h cyc_d=%h) %t ns", cyc_c, cyc_d, $time);
        error = error + 1;
    end else $display("PASS:  mcycle ADVANCING with stopcount=0 (cyc_c=%h -> cyc_d=%h) %t ns", cyc_c, cyc_d, $time);

    //========================================================================
    // RESUME + final check
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                 // drop haltreq
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ); // request resume

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) begin
        $display("ERROR: no allresumeack after resumereq %t ns", $time);
        error = error + 1;
    end else $display("PASS:  allresumeack set after resume (%0d polls) %t ns", to, $time);

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart not running after resume (allrunning=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart running after resume (allrunning=1) %t ns", $time);

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware must resume from dpc (prv preserved = M-mode) and reach done ---
    @(probes_cpu.x31==32'hdeadbeef);
    // sentinel must be untouched by any of the abstract accesses
    check_cpu_reg(18, X18_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_reset_halt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdext halt-on-reset (resethaltreq) FIRING test (Debug Spec 1.0).
//   Drives the hclk-domain DMI bus (no DTM) via the dmi_write/dmi_read and the
//   dm_* halt-on-reset helper tasks (bench/verilog/debug_dmi_tasks.v). Proves the
//   Debug Module's resethaltreq state halts the hart out of reset BEFORE it
//   executes any instruction, and that the state only acts on the NEXT reset.
//
//   The firmware boots normally (resethaltreq=0 at power-on), signals x31=0x11111111
//   and spins. Then this TB exercises the four halt-on-reset properties:
//
//   A. RESET-HALT FIRES with cause=5 (dm_reset_halt: set resethaltreq, pulse
//      ndmreset, poll allhalted). While halted, via abstract Access-Register reads:
//        - dcsr.cause (bits 8:6) == 5  (resethaltreq)
//        - dpc == 0x20000000           (the reset vector = PC of the first instr)
//        - minstret (CSR 0xB02) == 0   <-- KEY: ZERO instructions retired since the
//                                          reset -> "halted before executing any"
//        - dmstatus.allhavereset (bit 19) == 1  (a reset occurred, needs ack)
//   B. HASRESETHALTREQ: dmstatus bit 5 == 1 (feature supported/advertised).
//   C. RESUME RUNS IT: clrresethaltreq + resume; the hart re-runs the reset vector
//      (re-executing the first instruction) and diverges (SRAM phase flag) to reach
//      the 0xdeadbeef end sentinel — proving resume works.
//   D. ONE-SHOT / NO SPURIOUS HALT: while the hart is RUNNING, set resethaltreq
//      again WITHOUT ndmreset -> the hart must NOT halt (stays running, reaches
//      0xdeadbeef). Proves resethaltreq acts only on a reset, not when set.
//
//   dcsr = CSR 0x7b0, dpc = 0x7b1, minstret = CSR 0xB02, reached by the same
//   abstract Access-Register routing used by debug_dmi_stopcount (regno = the
//   12-bit CSR address directly; data0 read-back is a plain dmi_read(DMI_DATA0)).
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

    // Reset peripherals
    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG RESET-HALT: resethaltreq halts the hart out of reset (cause=5) |");
    $display(" ====================================================================");

    // Wait for the firmware to boot NORMALLY (resethaltreq=0 at power-on) and spin.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware booted normally and is spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) and clear the power-on havereset ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);  // ack sticky POR havereset

    //========================================================================
    // CHECK B: dmstatus.hasresethaltreq (bit 5) == 1 (feature supported)
    //========================================================================
    dmi_read(DMI_DMSTATUS);
    if ((dmi_readval & DMS_HASRESETHALT) === 32'h0) begin
        $display("ERROR: dmstatus.hasresethaltreq=0 -- halt-on-reset not advertised %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dmstatus.hasresethaltreq=1 (halt-on-reset supported) %t ns", $time);

    //========================================================================
    // CHECK A: arm resethaltreq + pulse ndmreset -> hart halts OUT OF RESET.
    //   dm_reset_halt sets resethaltreq (latched), pulses ndmreset (resets the
    //   hart only; SRAM/ROM survive), then polls dmstatus.allhalted.
    //========================================================================
    dm_reset_halt;

    // The halted-out-of-reset hart must be in Debug Mode for abstract access.
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted after reset-halt %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode out of reset (abstract access permitted) %t ns", $time);

    // dmstatus.allhavereset (bit 19) must be set: a reset occurred and needs ack.
    dmi_read(DMI_DMSTATUS);
    if ((dmi_readval & DMS_ALLHAVERESET) === 32'h0) begin
        $display("ERROR: dmstatus.allhavereset=0 after ndmreset (expected 1) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  dmstatus.allhavereset=1 after ndmreset %t ns", $time);

    // dcsr.cause (bits 8:6) must be 5 (resethaltreq).
    abs_run(CMD_RD_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d on dcsr read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);
    dcsr_val = dmi_readval;
    if (((dcsr_val >> 6) & 32'h7) !== 32'd5) begin
        $display("ERROR: dcsr.cause=%0d after reset-halt (expected 5=resethaltreq) [dcsr=%h] %t ns",
                 (dcsr_val >> 6) & 32'h7, dcsr_val, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.cause=5 (resethaltreq) [dcsr=%h] %t ns", dcsr_val, $time);

    // dpc must equal the reset vector (the PC of the first instruction).
    abs_run(CMD_RD_DPC);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d on dpc read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);
    dpc_val = dmi_readval;
    if (dpc_val !== EXPECTED_RESET_PC) begin
        $display("ERROR: dpc=%h after reset-halt (expected reset vector %h) %t ns", dpc_val, EXPECTED_RESET_PC, $time);
        error = error + 1;
    end else $display("PASS:  dpc=%h == reset vector (halted at the first instruction) %t ns", dpc_val, $time);

    // minstret == 0 -- THE KEY discriminator: zero instructions retired since reset.
    // Only meaningful when Zicntr is implemented. With ZICNTR_EN=0 minstret is a
    // non-existent CSR that correctly raises illegal-instruction (surfacing as
    // abstract-command cmderr=3), so this check is gated out for that config.
    if (ZICNTR_EN == 1) begin
        abs_run(CMD_RD_MINSTRET);
        if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
            $display("ERROR: cmderr=%0d on minstret read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
            error = error + 1;
        end
        dmi_read(DMI_DATA0);
        ins_val = dmi_readval;
        if (ins_val !== 32'h0) begin
            $display("ERROR: minstret=%h after reset-halt (expected 0) -- hart executed instruction(s) before halt %t ns", ins_val, $time);
            error = error + 1;
        end else $display("PASS:  minstret=0 -> ZERO instructions retired since reset (halted before executing any) %t ns", $time);
    end else begin
        $display("SKIP:  minstret check (ZICNTR_EN=0: minstret not implemented; cannot count retired instructions) %t ns", $time);
    end

    // ack the ndmreset-induced havereset (haltreq stays 0 -> hart stays halted).
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    //========================================================================
    // CHECK C: clrresethaltreq + resume -> hart re-runs the reset vector and
    //   reaches the done sentinel.
    //========================================================================
    dm_clr_resethaltreq;                       // clear latched resethaltreq (keep dmactive)
    dm_resume;                                 // drop haltreq, resumereq, poll allrunning

    //========================================================================
    // CHECK D: ONE-SHOT. While the hart is RUNNING, set resethaltreq again
    //   WITHOUT an ndmreset. It must NOT halt (resethaltreq only acts on reset).
    //========================================================================
    dm_set_resethaltreq;                       // setresethaltreq while running
    repeat (50) @(posedge free_clk);           // let any (buggy) halt propagate
    dmi_read(DMI_DMSTATUS);
    dms_val = dmi_readval;
    if ((dms_val & DMS_ALLHALTED) !== 32'h0) begin
        $display("ERROR: hart HALTED after setresethaltreq while running (no reset) -- not one-shot %t ns", $time);
        error = error + 1;
    end else if ((dms_val & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart neither running nor halted after setresethaltreq (dmstatus=%h) %t ns", dms_val, $time);
        error = error + 1;
    end else $display("PASS:  setresethaltreq while running did NOT halt the hart (still running) %t ns", $time);

    dm_clr_resethaltreq;                       // disarm before end

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware must reach the done sentinel: proves resume ran the reset
    //     vector instruction and the one-shot set did not stop it ---
    //     Use a LEVEL wait: the re-run reaches 0xdeadbeef right after resume,
    //     BEFORE this line is reached (after the one-shot check), so an
    //     edge-sensitive @(x31==...) would miss the already-settled value.
    wait (probes_cpu.x31==32'hdeadbeef);
    $display("PASS:  firmware reached 0xdeadbeef (resume ran the reset vector; one-shot did not halt) %t ns", $time);

    // reset-vector instruction executed on the re-run (x5 marker set); sentinel intact.
    check_cpu_reg(5,  X5_MARKER);
    check_cpu_reg(18, X18_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

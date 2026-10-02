//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_ebreak_enter
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: EBREAK enters Debug Mode when dcsr.ebreakm=1 (RISC-V Sdext)
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read/dm_halt/dm_resume helpers. Proves the Sdext ebreakm
//   entry path end-to-end:
//
//     1. halt the spinning hart via dmcontrol.haltreq; confirm allhalted +
//        dbg_debug_mode.
//     2. abstract read-modify-write dcsr (0x7b0): SET ebreakm (bit 15) while
//        PRESERVING prv[1:0] (so the hart resumes back into M-mode). Read dcsr
//        back to confirm ebreakm=1 and prv unchanged.
//     3. dm_resume the hart.
//     4. the firmware finishes the loop and executes a forced 32-bit EBREAK in
//        M-mode. Poll dmstatus.allhalted (BOUNDED watchdog) -> it must become 1
//        AGAIN: the EBREAK re-entered Debug Mode instead of trapping. A core that
//        ignores ebreakm never re-halts, so the watchdog times out and FAILS.
//     5. abstract-read dpc (0x7b1) and GPR x6 (regno 0x1006). Assert dpc == x6:
//        dpc points AT the EBREAK instruction.
//     6. abstract-read GPR x20 (regno 0x1014). Assert it is still the GOOD value
//        0x600D600D -> the normal M-mode breakpoint handler did NOT run.
//     7. resume cleanly without re-triggering the EBREAK: abstract-write
//        dpc = dpc + 4 (step over the 32-bit EBREAK), then dm_resume.
//     8. firmware runs past after_ebreak and reaches 0xdeadbeef; final
//        check_cpu_reg confirms x20 (GOOD) and x18 (sentinel) intact.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

reg [31:0] dcsr_val, dpc_val, x6_val, x20_val;

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
localparam [31:0] DMS_ALLHALTED  = 32'h00000200; // [9]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0)
//   [22:20] aarsize=2 (32-bit) -> 0x00200000 ; [17] transfer=1 -> 0x00020000
//   [16] write ; [15:0] regno (CSR = 12-bit CSR address ; GPR = 0x1000 + n)
localparam [31:0] CMD_RD_DCSR = 32'h00200000 | 32'h00020000 |              32'h000007b0; // 0x002207b0
localparam [31:0] CMD_WR_DCSR = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h000007b0; // 0x002307b0
localparam [31:0] CMD_RD_DPC  = 32'h00200000 | 32'h00020000 |              32'h000007b1; // 0x002207b1
localparam [31:0] CMD_WR_DPC  = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h000007b1; // 0x002307b1
localparam [31:0] CMD_RD_X6   = 32'h00200000 | 32'h00020000 |              32'h00001006; // 0x00221006
localparam [31:0] CMD_RD_X20  = 32'h00200000 | 32'h00020000 |              32'h00001014; // 0x00221014

// dcsr fields
localparam [31:0] DCSR_EBREAKM = 32'h00008000; // [15] ebreakm
localparam [31:0] DCSR_PRV     = 32'h00000003; // [1:0] prv

localparam [31:0] X18_SENTINEL = 32'hA5A5A5A5;
localparam [31:0] X20_GOOD     = 32'h600D600D;

// Issue an abstract command and wait for abstractcs.busy to clear; the final
// abstractcs value (incl. cmderr) is left in dmi_readval. A data0 read-back,
// when needed, is a separate dmi_read(DMI_DATA0).
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

    // The EBREAK is intentional. The exception monitor watches the raw decode
    // signal id_excp_ebreak_i, which can momentarily pulse on the entry cycle
    // (e.g. under -rsalu, while the multi-cycle stall briefly defers debug entry)
    // even though it is masked from being taken as a trap (dbg_ebreak_enter) and
    // the hart enters Debug Mode instead. Disable error-on-exception like the
    // other intentional-exception tests (inst_std_ebreak); the dpc/x20/re-halt
    // checks below are the real validation that NO M-mode trap was taken.
    error_on_exception = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG EBREAK ENTER: dcsr.ebreakm=1 -> EBREAK enters Debug Mode     |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1), clear sticky havereset ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    // --- halt the hart via dmcontrol.haltreq, confirm allhalted ---
    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode (abstract CSR access permitted) %t ns", $time);

    //========================================================================
    // SET dcsr.ebreakm via read-modify-write (preserve prv[1:0] so the hart
    // resumes into M-mode).
    //========================================================================
    abs_run(CMD_RD_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);                                  // dmi_readval = current dcsr
    dcsr_val = dmi_readval;
    dmi_write(DMI_DATA0, dcsr_val | DCSR_EBREAKM);        // set ebreakm, keep the rest
    abs_run(CMD_WR_DCSR);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dcsr write (set ebreakm) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.ebreakm set (read-modify-write, prv preserved) %t ns", $time);

    // read dcsr back: ebreakm must be 1, prv must be unchanged (resume into M-mode)
    abs_run(CMD_RD_DCSR);
    dmi_read(DMI_DATA0);
    if ((dmi_readval & DCSR_EBREAKM) === 32'h0) begin
        $display("ERROR: dcsr.ebreakm read back 0 after set (dcsr=%h) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.ebreakm reads back 1 (dcsr=%h) %t ns", dmi_readval, $time);
    if ((dmi_readval & DCSR_PRV) !== (dcsr_val & DCSR_PRV)) begin
        $display("ERROR: dcsr.prv changed by RMW (was %0d now %0d) %t ns",
                 (dcsr_val & DCSR_PRV), (dmi_readval & DCSR_PRV), $time);
        error = error + 1;
    end else $display("PASS:  dcsr.prv preserved by RMW (prv=%0d) %t ns", (dmi_readval & DCSR_PRV), $time);

    //========================================================================
    // RESUME -> firmware finishes the loop and hits the forced 32-bit EBREAK.
    // With ebreakm=1 the EBREAK must re-ENTER Debug Mode (allhalted=1 again).
    //========================================================================
    dm_resume;

    // BOUNDED watchdog: a core that honors ebreakm re-halts within a few
    // thousand core cycles; a broken core never re-halts -> this loop times
    // out and the test FAILS rather than spinning forever.
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 20000)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: EBREAK did NOT enter Debug Mode (allhalted still 0 after %0d polls) %t ns", to, $time);
        error = error + 1;
    end else $display("PASS:  EBREAK re-entered Debug Mode (allhalted=1 again, %0d polls) %t ns", to, $time);

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted after EBREAK re-halt %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode after EBREAK %t ns", $time);

    //========================================================================
    // dpc must point AT the EBREAK instruction: dpc == x6 (captured by the
    // firmware just before the EBREAK).
    //========================================================================
    abs_run(CMD_RD_DPC);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dpc read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);
    dpc_val = dmi_readval;

    abs_run(CMD_RD_X6);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after x6 read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);
    x6_val = dmi_readval;

    if (dpc_val !== x6_val) begin
        $display("ERROR: dpc=%h does NOT match EBREAK address x6=%h %t ns", dpc_val, x6_val, $time);
        error = error + 1;
    end else $display("PASS:  dpc=%h points AT the EBREAK (== x6) %t ns", dpc_val, $time);

    //========================================================================
    // The normal M-mode breakpoint handler must NOT have run: x20 still GOOD.
    //========================================================================
    abs_run(CMD_RD_X20);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after x20 read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);
    x20_val = dmi_readval;
    if (x20_val !== X20_GOOD) begin
        $display("ERROR: x20=%h (expected GOOD %h) -- M-mode ebreak handler ran %t ns", x20_val, X20_GOOD, $time);
        error = error + 1;
    end else $display("PASS:  x20=%h GOOD -- M-mode ebreak handler did NOT run %t ns", X20_GOOD, $time);

    //========================================================================
    // RESUME cleanly: step dpc over the 32-bit EBREAK (dpc = dpc + 4) so the
    // hart does not immediately re-trigger it, then resume.
    //========================================================================
    dmi_write(DMI_DATA0, dpc_val + 32'd4);
    abs_run(CMD_WR_DPC);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after dpc write (dpc+4) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  dpc advanced to %h (step over EBREAK) %t ns", dpc_val + 32'd4, $time);

    dm_resume;

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware must run past after_ebreak and reach the end on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, X20_GOOD);       // EBREAK never reached the M-mode handler
    check_cpu_reg(18, X18_SENTINEL);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

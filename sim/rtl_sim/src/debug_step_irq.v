//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_step_irq
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG single-step vs a pending interrupt (Sdext dcsr.stepie=0)
//   Reproducer for Pass-2 functional finding F-1: the one-cycle
//   registered-debug_mode_q vs combinational-debug_entry gate mismatch lets an
//   interrupt commit DURING Debug-Mode entry at a single-step boundary.
//
//   Sequence (all over the hclk-domain DMI bus, no DTM):
//     1. halt the spinning hart (dmcontrol.haltreq), confirm Debug Mode
//     2. redirect the jalr spin base x12 -> &step_start (so step 1 progresses)
//     3. set dcsr.step by RMW (stepie stays 0 -> IRQs masked for the step span)
//     4. snapshot baseline mstatus (MIE=1) and mcause (0) via abstract CSR read
//     5. raise the machine external IRQ WHILE halted (now pending + enabled)
//     6. single-step ONE instruction (the jalr) -> the race window
//     7. re-read mstatus / mcause / mepc via abstract access:
//          CORRECT : dcsr.cause=4, mstatus.MIE still 1, mcause=0, mepc=0
//          BUGGY   : mstatus.MIE cleared, mcause=0x8000000b, mepc written
//        (the IRQ committed while entering Debug Mode -> architectural corruption)
//     8. recovery: clear dcsr.step, free-run; the pending IRQ must be delivered
//        exactly once AFTER resume (x20 -> 0xBEEF, firmware reaches 0xdeadbeef).
//        On the buggy core mstatus.MIE was clobbered to 0, so the free-run IRQ
//        never arrives -> the bounded wait for 0xdeadbeef fails too (defense in
//        depth); the abstract mstatus/mcause checks are the primary signal.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

reg [31:0] target_addr;   // firmware x13 = &step_start (redirect target)
reg [31:0] mstatus_base;  // mstatus snapshot before the step (MIE must be set)
reg [31:0] mstatus_now;   // mstatus after the step (MIE must be unchanged)
reg [31:0] mcause_now;    // mcause after the step (must be 0 = no trap taken)
reg [31:0] mepc_now;      // mepc after the step (must be 0 = no trap taken)
reg [31:0] dcsr_now;      // dcsr read-back
reg [2:0]  cause_now;     // dcsr.cause[8:6]

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
localparam [31:0] DMS_ALLHALTED  = 32'h00000200;  // [9]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000;       // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700;       // [10:8] cmderr (W1C)

// Access Register command words (cmdtype=0, aarsize=2, transfer=1)
//   CSR regno = the 12-bit CSR address; GPR regno = 0x1000 + gpr_index
localparam [31:0] CMD_RD_DCSR    = 32'h002207b0;
localparam [31:0] CMD_WR_DCSR    = 32'h002307b0;
localparam [31:0] CMD_RD_X13     = 32'h0022100d;
localparam [31:0] CMD_WR_X12     = 32'h0023100c;
localparam [31:0] CMD_RD_MSTATUS = 32'h00220300;
localparam [31:0] CMD_RD_MCAUSE  = 32'h00220342;
localparam [31:0] CMD_RD_MEPC    = 32'h00220341;

// field constants
localparam [31:0] DCSR_STEP     = 32'h00000004;    // dcsr[2] step
localparam [31:0] MSTATUS_MIE   = 32'h00000008;    // mstatus[3] global IRQ enable
localparam [31:0] MCAUSE_MEXT   = 32'h8000000b;    // machine external interrupt

// Issue an abstract command and wait for abstractcs.busy to clear; the final
// abstractcs value (incl. cmderr) is left in dmi_readval.
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

// Check abstractcs.cmderr==0 in dmi_readval (post-abs_run abstractcs value).
// MUST be called before any dmi_read(DMI_DATA0) that overwrites dmi_readval.
task chk_cmderr;
   input [8*32:1] where;
   begin
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after %0s %t ns", (dmi_readval & ACS_CMDERR) >> 8, where, $time);
         error = error + 1;
      end
   end
endtask

// Read dcsr (0x7b0) into dcsr_now and extract cause_now = dcsr.cause[8:6].
task read_dcsr;
   begin
      abs_run(CMD_RD_DCSR);
      chk_cmderr("dcsr read");
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      dcsr_now  = dmi_readval;
      cause_now = dcsr_now[8:6];
   end
endtask

// Read an arbitrary CSR (abstract) into `val`.
task read_csr;
   input  [31:0] cmd;
   input  [8*32:1] where;
   output [31:0] val;
   begin
      abs_run(cmd);
      chk_cmderr(where);
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      val = dmi_readval;
   end
endtask

// Single-step the hart one instruction: drop haltreq (so re-halt is NOT due to a
// held haltreq), assert resumereq, then poll dmstatus.allhalted for the AUTO
// re-halt.
task do_step;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                 // drop haltreq
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ); // step one instruction
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
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
    $display("|  DEBUG STEP vs IRQ: pending IRQ must NOT commit during step entry  |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning on the self-jump.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1) ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);  // clear sticky havereset

    // --- halt the hart via dmcontrol.haltreq (no IRQ pending yet -> clean entry) ---
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
    end else $display("PASS:  hart in Debug Mode (abstract access permitted) %t ns", $time);

    //========================================================================
    // Redirect the jalr base x12 -> &step_start so the first step progresses
    // into the straight-line run (learn the target from firmware x13).
    //========================================================================
    abs_run(CMD_RD_X13);
    chk_cmderr("x13 read");
    dmi_read(DMI_DATA0);
    target_addr = dmi_readval;
    if (target_addr === 32'h0) begin
        $display("ERROR: x13 (&step_start) reads 0 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  redirect target &step_start = %h (from x13) %t ns", target_addr, $time);

    dmi_write(DMI_DATA0, target_addr);     // inject redirect target into x12
    abs_run(CMD_WR_X12);
    chk_cmderr("x12 write");

    //========================================================================
    // Enable single-step: RMW dcsr to SET step (bit 2), preserving prv (and
    // the rest). stepie is left 0 -> IRQs are masked for the span of the step.
    //========================================================================
    abs_run(CMD_RD_DCSR);
    chk_cmderr("dcsr read (pre-set step)");
    dmi_read(DMI_DATA0);                                 // dmi_readval = current dcsr
    dmi_write(DMI_DATA0, dmi_readval | DCSR_STEP);       // set step, keep the rest
    abs_run(CMD_WR_DCSR);
    chk_cmderr("dcsr write (set step)");
    read_dcsr;
    if ((dcsr_now & DCSR_STEP) === 32'h0) begin
        $display("ERROR: dcsr.step did not set (dcsr=%h) %t ns", dcsr_now, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.step set, stepie=0 (dcsr=%h) %t ns", dcsr_now, $time);

    //========================================================================
    // Baseline: capture mstatus (MIE must be 1) and mcause (must be 0) BEFORE
    // the step, so a change is unambiguously attributable to the step.
    //========================================================================
    read_csr(CMD_RD_MSTATUS, "mstatus base", mstatus_base);
    if ((mstatus_base & MSTATUS_MIE) === 32'h0) begin
        $display("ERROR: baseline mstatus.MIE=0 (firmware did not enable IRQs?) mstatus=%h %t ns", mstatus_base, $time);
        error = error + 1;
    end else $display("PASS:  baseline mstatus.MIE=1 (mstatus=%h) %t ns", mstatus_base, $time);

    read_csr(CMD_RD_MCAUSE, "mcause base", mcause_now);
    if (mcause_now !== 32'h0)
        $display("NOTE:  baseline mcause=%h (nonzero from prior boot; delta is what matters) %t ns", mcause_now, $time);

    //========================================================================
    // Raise the machine external IRQ WHILE halted -> now pending + enabled.
    // Held masked by the frozen hart (trap_pending_set & ~dbg_mode) until the
    // step resumes; then masked for the step span by dcsr.stepie=0.
    //========================================================================
    irq_m_external = 1'b1;
    repeat (4) @(posedge free_clk);
    $display("Raised machine external IRQ while halted (pending) %t ns", $time);

    //========================================================================
    // THE RACE: single-step ONE instruction (the jalr). A correct core keeps
    // the IRQ pending across the step boundary; a buggy core commits it during
    // Debug-Mode entry.
    //========================================================================
    do_step;
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: step did not auto re-halt (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  step auto re-halted (allhalted=1) %t ns", $time);

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: hart not in Debug Mode after step %t ns", $time);
        error = error + 1;
    end

    read_dcsr;
    if (cause_now !== 3'd4) begin
        $display("ERROR: step dcsr.cause=%0d (expected 4=step) %t ns", cause_now, $time);
        error = error + 1;
    end else $display("PASS:  step dcsr.cause=4 (step) %t ns", $time);

    //========================================================================
    // PRIMARY CHECK — the IRQ must NOT have committed during entry.
    //   mstatus.MIE unchanged (still 1), mcause==0, mepc==0.
    //========================================================================
    read_csr(CMD_RD_MSTATUS, "mstatus post-step", mstatus_now);
    if ((mstatus_now & MSTATUS_MIE) === 32'h0) begin
        $display("ERROR: mstatus.MIE CLEARED by the step (mstatus=%h) -- IRQ committed during Debug-Mode entry (F-1) %t ns", mstatus_now, $time);
        error = error + 1;
    end else $display("PASS:  mstatus.MIE still set after step (mstatus=%h) -- no interrupt committed %t ns", mstatus_now, $time);

    read_csr(CMD_RD_MCAUSE, "mcause post-step", mcause_now);
    if (mcause_now === MCAUSE_MEXT) begin
        $display("ERROR: mcause=%h (machine external IRQ) -- interrupt was taken during step entry (F-1) %t ns", mcause_now, $time);
        error = error + 1;
    end else $display("PASS:  mcause=%h (no external-IRQ trap recorded) %t ns", mcause_now, $time);

    read_csr(CMD_RD_MEPC, "mepc post-step", mepc_now);
    if (mepc_now !== 32'h0) begin
        $display("ERROR: mepc=%h nonzero -- a trap was taken during the step (F-1) %t ns", mepc_now, $time);
        error = error + 1;
    end else $display("PASS:  mepc=0 (no trap epc recorded during step) %t ns", $time);

    //========================================================================
    // RECOVERY — clear dcsr.step and free-run. The still-pending IRQ must be
    // delivered EXACTLY ONCE after resume (not during the step). On a buggy
    // core mstatus.MIE was clobbered to 0, so the IRQ never arrives and the
    // bounded wait below fails (defense in depth).
    //========================================================================
    abs_run(CMD_RD_DCSR);
    chk_cmderr("dcsr read (pre-clear step)");
    dmi_read(DMI_DATA0);
    dmi_write(DMI_DATA0, dmi_readval & ~DCSR_STEP);      // clear step, keep the rest
    abs_run(CMD_WR_DCSR);
    chk_cmderr("dcsr write (clear step)");

    dm_resume;   // full free-run (step cleared)

    // The pending IRQ fires post-resume; handler sets x20 and masks MEIE.
    to = 0;
    while ((probes_cpu.x20 !== 32'h0000BEEF) && (to < 2000)) begin @(posedge free_clk); to = to + 1; end
    if (probes_cpu.x20 !== 32'h0000BEEF) begin
        $display("ERROR: pending IRQ never delivered after resume (x20=%h) -- state corrupted during step (F-1) %t ns", probes_cpu.x20, $time);
        error = error + 1;
    end else $display("PASS:  pending IRQ delivered once after resume (x20=0xBEEF, %0d cyc) %t ns", to, $time);
    irq_m_external = 1'b0;

    //========================================================================
    // FINAL — firmware finishes on its own.
    //========================================================================
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 4000)) begin @(posedge free_clk); to = to + 1; end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: firmware did not reach 0xdeadbeef (x31=%h) %t ns", probes_cpu.x31, $time);
        error = error + 1;
    end

    check_cpu_reg(5,  32'h00000011);   // stepped addi landed
    check_cpu_reg(18, 32'hA5A5A5A5);   // sentinel untouched
    check_cpu_reg(20, 32'h0000BEEF);   // IRQ taken exactly once, after resume

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

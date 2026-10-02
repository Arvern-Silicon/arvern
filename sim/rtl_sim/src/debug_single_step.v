//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_single_step
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DMI single-step — dcsr.step (Sdext, Debug Spec 1.0)
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read helpers. Halts the spinning hart, sets dcsr.step
//   (CSR 0x7b0 bit 2) by read-modify-write (preserving dcsr.prv), then walks the
//   hart ONE instruction at a time, asserting after EACH step that:
//       - the hart auto-re-halted on its own (allhalted=1) WITHOUT the testbench
//         re-asserting haltreq (dcsr.cause==4 == step),
//       - dpc advanced by exactly one instruction (== prev+4 AND != prev), and
//       - EXACTLY ONE instruction's side effect occurred (the stepped target GPR
//         holds its value; the NEXT target is still at its pre-step value).
//
//   Deterministic park without writing dpc: the firmware spins on a self-jump
//   `jalr x0,0(x12)` (x12=&spin_self). While halted the testbench abstract-WRITES
//   x12 = &step_start (read from the firmware's x13), so the FIRST step executes
//   the jalr and redirects control flow to step_start. The walk is therefore over
//   {jalr, addi x5, addi x6, addi x7}:
//       step 1 (jalr): dpc -> step_start (== x13), dpc != parked PC, NO GPR change.
//       step 2 (addi): dpc -> step_start+4,  x5=0x11, x6 still 0.
//       step 3 (addi): dpc -> step_start+8,  x6=0x22, x7 still 0.
//       step 4 (addi): dpc -> step_start+12, x7=0x33, x28 still 0.
//   The repeated +4 / one-side-effect steps catch the "ran two", "stuck dpc"
//   (infinite-step) and "skipped/replayed" failure modes a single step would miss.
//
//   Finally dcsr.step is CLEARED (read-modify-write) and the hart is resumed free:
//   reaching 0xdeadbeef on its own proves dcsr.step was truly cleared (otherwise
//   it would single-step forever) AND that the prv-preserving RMWs left it in
//   M-mode. Ground truth is the side-effect + dpc advance per step; the dmstatus
//   bits corroborate. cmderr is checked after every abstract command (a non-zero
//   cmderr blocks all later abstract commands and would silently false-pass).
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

reg [31:0] pc_parked;   // dpc at the initial halt (= spin_self, the jalr)
reg [31:0] target_addr; // firmware x13 = &step_start (redirect target)
reg [31:0] dpc_now;     // dpc read after the current step
reg [31:0] dpc_prev;    // dpc read after the previous step
reg [31:0] dcsr_now;    // dcsr read-back
reg [2:0]  cause_now;   // dcsr.cause[8:6]

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
//   CSR regno = the 12-bit CSR address; GPR regno = 0x1000 + gpr_index
localparam [31:0] CMD_RD_DCSR = 32'h00200000 | 32'h00020000 |              32'h000007b0; // = 0x002207b0
localparam [31:0] CMD_WR_DCSR = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h000007b0; // = 0x002307b0
localparam [31:0] CMD_RD_DPC  = 32'h00200000 | 32'h00020000 |              32'h000007b1; // = 0x002207b1
localparam [31:0] CMD_RD_X13  = 32'h00200000 | 32'h00020000 |              32'h0000100d; // = 0x0022100d
localparam [31:0] CMD_WR_X12  = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h0000100c; // = 0x0023100c

// dcsr fields
localparam [31:0] DCSR_STEP = 32'h00000004; // [2] step

localparam [31:0] X18_SENTINEL = 32'hA5A5A5A5;

// step-run target final values (and per-step partial values)
localparam [31:0] X5_VAL  = 32'h00000011;
localparam [31:0] X6_VAL  = 32'h00000022;
localparam [31:0] X7_VAL  = 32'h00000033;
localparam [31:0] X28_VAL = 32'h00000044;
localparam [31:0] X29_VAL = 32'h00000055;

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

// Check abstractcs.cmderr==0 in dmi_readval (the post-abs_run abstractcs value).
// MUST be called before any dmi_read(DMI_DATA0) that would overwrite dmi_readval.
task chk_cmderr;
   input [8*32:1] where;
   begin
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after %0s %t ns", (dmi_readval & ACS_CMDERR) >> 8, where, $time);
         error = error + 1;
      end
   end
endtask

// Read dpc (0x7b1) into dpc_now.
task read_dpc;
   begin
      abs_run(CMD_RD_DPC);
      chk_cmderr("dpc read");
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      dpc_now = dmi_readval;
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

// Single-step the hart one instruction: drop haltreq (so re-halt is NOT due to a
// held haltreq), assert resumereq, then poll dmstatus.allhalted for the AUTO
// re-halt. (dm_resume polls allrunning and would false-error here because the
// hart re-halts before the slow DMI poll ever samples allrunning=1.)
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
    $display("|  DEBUG SINGLE-STEP: dcsr.step walks the halted hart one instr at a time |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning on the self-jump.
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
    end else $display("PASS:  hart in Debug Mode (abstract access permitted) %t ns", $time);

    //========================================================================
    // Record the parked PC (task: PC0). dpc holds the address of the next
    // instruction to execute = spin_self (the jalr) at the initial halt.
    //========================================================================
    read_dpc;
    pc_parked = dpc_now;
    if (pc_parked === 32'h0) begin
        $display("ERROR: parked dpc reads 0 (expected the spin_self PC) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  parked dpc (PC0) = %h %t ns", pc_parked, $time);

    //========================================================================
    // Learn the redirect target (firmware x13 = &step_start) and rewrite the
    // jalr base x12 to it, so the first step jumps into the step run.
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
    if (probes_cpu.x12 !== target_addr) begin
        $display("ERROR: abstract write of x12 did not land (x12=%h, want %h) %t ns", probes_cpu.x12, target_addr, $time);
        error = error + 1;
    end else $display("PASS:  x12 (jalr base) rewritten to %h while halted %t ns", target_addr, $time);

    //========================================================================
    // Enable single-step: read-modify-write dcsr to SET step (bit 2),
    // preserving prv[1:0] (and the rest) so the hart stays in M-mode.
    //========================================================================
    abs_run(CMD_RD_DCSR);
    chk_cmderr("dcsr read (pre-set step)");
    dmi_read(DMI_DATA0);                                 // dmi_readval = current dcsr
    dmi_write(DMI_DATA0, dmi_readval | DCSR_STEP);       // set step, keep the rest
    abs_run(CMD_WR_DCSR);
    chk_cmderr("dcsr write (set step)");
    // confirm the bit actually set
    read_dcsr;
    if ((dcsr_now & DCSR_STEP) === 32'h0) begin
        $display("ERROR: dcsr.step did not set (dcsr=%h) %t ns", dcsr_now, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.step set (dcsr=%h, prv preserved) %t ns", dcsr_now, $time);

    //========================================================================
    // STEP 1 — the jalr: redirects control flow to step_start.
    //   dpc -> target_addr (== x13), dpc != parked PC, cause==4, NO GPR change.
    //========================================================================
    dpc_prev = pc_parked;
    do_step;
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: step 1 (jalr) did not auto re-halt (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  step 1 (jalr) auto re-halted without TB haltreq (allhalted=1) %t ns", $time);
    if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0)   // corroboration only (not load-bearing)
        $display("NOTE:  step 1 allresumeack not observed (corroboration only) %t ns", $time);

    read_dcsr;
    if (cause_now !== 3'd4) begin
        $display("ERROR: step 1 dcsr.cause=%0d (expected 4=step) %t ns", cause_now, $time);
        error = error + 1;
    end else $display("PASS:  step 1 dcsr.cause=4 (step) %t ns", $time);

    read_dpc;
    if (dpc_now !== target_addr) begin
        $display("ERROR: step 1 dpc=%h after jalr (expected step_start=%h) %t ns", dpc_now, target_addr, $time);
        error = error + 1;
    end else $display("PASS:  step 1 jalr redirected: dpc=%h == step_start %t ns", dpc_now, $time);
    if (dpc_now === dpc_prev) begin
        $display("ERROR: step 1 dpc did not advance (stuck at %h) %t ns", dpc_now, $time);
        error = error + 1;
    end else $display("PASS:  step 1 dpc advanced (%h -> %h) %t ns", dpc_prev, dpc_now, $time);

    // baseline: no step-run instruction has executed yet -> all targets still 0
    if ((probes_cpu.x05 !== 32'h0) || (probes_cpu.x06 !== 32'h0) ||
        (probes_cpu.x07 !== 32'h0) || (probes_cpu.x28 !== 32'h0) || (probes_cpu.x29 !== 32'h0)) begin
        $display("ERROR: step 1 (jalr) altered a step-run target (x5=%h x6=%h x7=%h x28=%h x29=%h) %t ns",
                 probes_cpu.x05, probes_cpu.x06, probes_cpu.x07, probes_cpu.x28, probes_cpu.x29, $time);
        error = error + 1;
    end else $display("PASS:  step 1 (jalr) had no GPR side effect (all targets still 0) %t ns", $time);
    dpc_prev = dpc_now;

    //========================================================================
    // STEP 2 — addi x5,x0,0x11 : dpc->PC0_step+4, x5=0x11, x6 still 0.
    //========================================================================
    do_step;
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: step 2 (addi x5) did not auto re-halt (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  step 2 (addi x5) auto re-halted (allhalted=1) %t ns", $time);
    read_dcsr;
    if (cause_now !== 3'd4) begin
        $display("ERROR: step 2 dcsr.cause=%0d (expected 4=step) %t ns", cause_now, $time);
        error = error + 1;
    end else $display("PASS:  step 2 dcsr.cause=4 (step) %t ns", $time);
    read_dpc;
    if (dpc_now !== (dpc_prev + 32'd4)) begin
        $display("ERROR: step 2 dpc=%h (expected prev+4=%h) %t ns", dpc_now, dpc_prev + 32'd4, $time);
        error = error + 1;
    end else $display("PASS:  step 2 dpc advanced +4 (%h -> %h) %t ns", dpc_prev, dpc_now, $time);
    if (dpc_now === dpc_prev) begin
        $display("ERROR: step 2 dpc stuck at %h %t ns", dpc_now, $time);
        error = error + 1;
    end
    if (probes_cpu.x05 !== X5_VAL) begin
        $display("ERROR: step 2 x5=%h after addi (expected %h) -- step did not retire it %t ns", probes_cpu.x05, X5_VAL, $time);
        error = error + 1;
    end else $display("PASS:  step 2 retired exactly addi x5 (x5=%h) %t ns", probes_cpu.x05, $time);
    if (probes_cpu.x06 !== 32'h0) begin
        $display("ERROR: step 2 ran too far: x6=%h already set (expected still 0) %t ns", probes_cpu.x06, $time);
        error = error + 1;
    end else $display("PASS:  step 2 stopped after one instr (next target x6 still 0) %t ns", $time);
    dpc_prev = dpc_now;

    //========================================================================
    // STEP 3 — addi x6,x0,0x22 : dpc->+4, x6=0x22, x7 still 0.
    //========================================================================
    do_step;
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: step 3 (addi x6) did not auto re-halt (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  step 3 (addi x6) auto re-halted (allhalted=1) %t ns", $time);
    read_dcsr;
    if (cause_now !== 3'd4) begin
        $display("ERROR: step 3 dcsr.cause=%0d (expected 4=step) %t ns", cause_now, $time);
        error = error + 1;
    end else $display("PASS:  step 3 dcsr.cause=4 (step) %t ns", $time);
    read_dpc;
    if (dpc_now !== (dpc_prev + 32'd4)) begin
        $display("ERROR: step 3 dpc=%h (expected prev+4=%h) %t ns", dpc_now, dpc_prev + 32'd4, $time);
        error = error + 1;
    end else $display("PASS:  step 3 dpc advanced +4 (%h -> %h) %t ns", dpc_prev, dpc_now, $time);
    if (dpc_now === dpc_prev) begin
        $display("ERROR: step 3 dpc stuck at %h %t ns", dpc_now, $time);
        error = error + 1;
    end
    if (probes_cpu.x06 !== X6_VAL) begin
        $display("ERROR: step 3 x6=%h after addi (expected %h) %t ns", probes_cpu.x06, X6_VAL, $time);
        error = error + 1;
    end else $display("PASS:  step 3 retired exactly addi x6 (x6=%h) %t ns", probes_cpu.x06, $time);
    if (probes_cpu.x07 !== 32'h0) begin
        $display("ERROR: step 3 ran too far: x7=%h already set (expected still 0) %t ns", probes_cpu.x07, $time);
        error = error + 1;
    end else $display("PASS:  step 3 stopped after one instr (next target x7 still 0) %t ns", $time);
    // x5 must remain at its step-2 value (not re-executed / corrupted)
    if (probes_cpu.x05 !== X5_VAL) begin
        $display("ERROR: step 3 disturbed x5=%h (expected %h) %t ns", probes_cpu.x05, X5_VAL, $time);
        error = error + 1;
    end
    dpc_prev = dpc_now;

    //========================================================================
    // STEP 4 — addi x7,x0,0x33 : dpc->+4, x7=0x33, x28 still 0.
    //========================================================================
    do_step;
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: step 4 (addi x7) did not auto re-halt (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  step 4 (addi x7) auto re-halted (allhalted=1) %t ns", $time);
    read_dcsr;
    if (cause_now !== 3'd4) begin
        $display("ERROR: step 4 dcsr.cause=%0d (expected 4=step) %t ns", cause_now, $time);
        error = error + 1;
    end else $display("PASS:  step 4 dcsr.cause=4 (step) %t ns", $time);
    read_dpc;
    if (dpc_now !== (dpc_prev + 32'd4)) begin
        $display("ERROR: step 4 dpc=%h (expected prev+4=%h) %t ns", dpc_now, dpc_prev + 32'd4, $time);
        error = error + 1;
    end else $display("PASS:  step 4 dpc advanced +4 (%h -> %h) %t ns", dpc_prev, dpc_now, $time);
    if (dpc_now === dpc_prev) begin
        $display("ERROR: step 4 dpc stuck at %h %t ns", dpc_now, $time);
        error = error + 1;
    end
    if (probes_cpu.x07 !== X7_VAL) begin
        $display("ERROR: step 4 x7=%h after addi (expected %h) %t ns", probes_cpu.x07, X7_VAL, $time);
        error = error + 1;
    end else $display("PASS:  step 4 retired exactly addi x7 (x7=%h) %t ns", probes_cpu.x07, $time);
    if (probes_cpu.x28 !== 32'h0) begin
        $display("ERROR: step 4 ran too far: x28=%h already set (expected still 0) %t ns", probes_cpu.x28, $time);
        error = error + 1;
    end else $display("PASS:  step 4 stopped after one instr (next target x28 still 0) %t ns", $time);
    dpc_prev = dpc_now;

    //========================================================================
    // CLEAR dcsr.step (read-modify-write, preserve prv) and resume FREE.
    //   The hart resumes from dpc (addi x28) and must run to 0xdeadbeef on its
    //   own -> proves step was actually cleared (else it would step forever).
    //========================================================================
    abs_run(CMD_RD_DCSR);
    chk_cmderr("dcsr read (pre-clear step)");
    dmi_read(DMI_DATA0);
    dmi_write(DMI_DATA0, dmi_readval & ~DCSR_STEP);      // clear step, keep the rest
    abs_run(CMD_WR_DCSR);
    chk_cmderr("dcsr write (clear step)");
    read_dcsr;
    if ((dcsr_now & DCSR_STEP) !== 32'h0) begin
        $display("ERROR: dcsr.step did not clear (dcsr=%h) %t ns", dcsr_now, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.step cleared (dcsr=%h) %t ns", dcsr_now, $time);

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // full free-run resume (step cleared -> dm_resume's allrunning poll is valid now)
    dm_resume;

    //========================================================================
    // FINAL — firmware finishes the step run and the trailer on its own.
    //========================================================================
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(5,  X5_VAL);     // single-stepped
    check_cpu_reg(6,  X6_VAL);     // single-stepped
    check_cpu_reg(7,  X7_VAL);     // single-stepped
    check_cpu_reg(28, X28_VAL);    // free-run after step cleared
    check_cpu_reg(29, X29_VAL);    // free-run after step cleared
    check_cpu_reg(18, X18_SENTINEL); // sentinel untouched by any abstract access

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

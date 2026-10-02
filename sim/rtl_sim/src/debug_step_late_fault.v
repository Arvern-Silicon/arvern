//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_step_late_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG single-step over a late-faulting load (Sdext dcsr.step)
//   Same DMI flow as debug_single_step: halt the spinning hart, rewrite the
//   jalr base to &step_start, set dcsr.step and walk:
//       step 1 (jalr)        : dpc -> step_start, no GPR change
//       step 2 (lw a0,0(a1)) : dpc -> step_start+4, a0 = 0x80000101
//       step 3 (lw a4,0(a0)) : MISALIGNED. Expected per Debug Spec 1.0: the
//                              exception is taken and the hart halts at the
//                              handler entry -> dpc == mtvec, dcsr.cause == 4,
//                              mcause == 4, mtval == 0x80000101,
//                              mepc == step_start+4, a4 keeps its sentinel.
//                              Bug signature: dpc == step_start+8, mcause
//                              unchanged, no handler entry.
//       step 4 (csrr x20,mcause): dpc -> mtvec+4, x20 == 4
//       step 5 (csrr x21,mtval) : dpc -> mtvec+8, x21 == 0x80000101
//   then dcsr.step is cleared and the hart free-runs to 0xdeadbeef; the
//   firmware-recorded cause/mtval/mepc/entry count and the sentinel are
//   checked at the end.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

reg [31:0] pc_parked;
reg [31:0] target_addr;
reg [31:0] mtvec_val;
reg [31:0] dpc_now;
reg [31:0] dpc_prev;
reg [31:0] dcsr_now;
reg [2:0]  cause_now;
reg [31:0] csr_val;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_HALTREQ    = 32'h80000000;
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;

localparam [31:0] DMS_ALLHALTED    = 32'h00000200;
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800;
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000;

localparam [31:0] ACS_BUSY   = 32'h00001000;
localparam [31:0] ACS_CMDERR = 32'h00000700;

// Access Register command words (cmdtype=0, aarsize=2, transfer=1)
localparam [31:0] CMD_RD_DCSR   = 32'h002207b0;
localparam [31:0] CMD_WR_DCSR   = 32'h002307b0;
localparam [31:0] CMD_RD_DPC    = 32'h002207b1;
localparam [31:0] CMD_RD_X13    = 32'h0022100d;
localparam [31:0] CMD_WR_X12    = 32'h0023100c;
localparam [31:0] CMD_RD_MTVEC  = 32'h00220305;
localparam [31:0] CMD_RD_MEPC   = 32'h00220341;
localparam [31:0] CMD_RD_MCAUSE = 32'h00220342;
localparam [31:0] CMD_RD_MTVAL  = 32'h00220343;

localparam [31:0] DCSR_STEP = 32'h00000004;

localparam [31:0] X18_SENTINEL    = 32'hA5A5A5A5;
localparam [31:0] RD_SENTINEL     = 32'hDEAD0000;
localparam [31:0] MISALIGNED_ADDR = 32'h80000101;
localparam [31:0] X5_VAL          = 32'h00000011;
localparam [31:0] X6_VAL          = 32'h00000022;

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

task chk_cmderr;
   input [8*32:1] where;
   begin
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after %0s %t ns", (dmi_readval & ACS_CMDERR) >> 8, where, $time);
         error = error + 1;
      end
   end
endtask

task read_dpc;
   begin
      abs_run(CMD_RD_DPC);
      chk_cmderr("dpc read");
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      dpc_now = dmi_readval;
   end
endtask

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

// Single-step: drop haltreq, assert resumereq, poll allhalted for the auto re-halt.
task do_step;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
   end
endtask

// Common post-step checks: auto re-halt, dcsr.cause==4, dpc == expected.
task chk_step;
   input [8*32:1] what;
   input [31:0]   dpc_exp;
   begin
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: %0s did not auto re-halt (allhalted=0) %t ns", what, $time);
         error = error + 1;
      end else $display("PASS:  %0s auto re-halted (allhalted=1) %t ns", what, $time);
      read_dcsr;
      if (cause_now !== 3'd4) begin
         $display("ERROR: %0s dcsr.cause=%0d (expected 4=step) %t ns", what, cause_now, $time);
         error = error + 1;
      end else $display("PASS:  %0s dcsr.cause=4 (step) %t ns", what, $time);
      read_dpc;
      if (dpc_now !== dpc_exp) begin
         $display("ERROR: %0s dpc=%h (expected %h) %t ns", what, dpc_now, dpc_exp, $time);
         error = error + 1;
      end else $display("PASS:  %0s dpc=%h as expected %t ns", what, dpc_now, $time);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    error_on_exception = 0;   // the stepped misaligned load is meant to trap

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG STEP LATE FAULT: dcsr.step over a load-use-hazard misaligned lw   |");
    $display(" ====================================================================");

    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    // --- halt the hart ---
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
    end

    read_dpc;
    pc_parked = dpc_now;
    $display("PASS:  parked dpc = %h %t ns", pc_parked, $time);

    read_csr(CMD_RD_MTVEC, "mtvec read", mtvec_val);
    $display("       mtvec = %h (trap handler entry)", mtvec_val);

    // --- redirect the jalr to step_start ---
    abs_run(CMD_RD_X13);
    chk_cmderr("x13 read");
    dmi_read(DMI_DATA0);
    target_addr = dmi_readval;
    if (target_addr === 32'h0) begin
        $display("ERROR: x13 (&step_start) reads 0 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  redirect target &step_start = %h (from x13) %t ns", target_addr, $time);

    dmi_write(DMI_DATA0, target_addr);
    abs_run(CMD_WR_X12);
    chk_cmderr("x12 write");
    if (probes_cpu.x12 !== target_addr) begin
        $display("ERROR: abstract write of x12 did not land (x12=%h, want %h) %t ns", probes_cpu.x12, target_addr, $time);
        error = error + 1;
    end

    // --- set dcsr.step (RMW, preserve prv) ---
    abs_run(CMD_RD_DCSR);
    chk_cmderr("dcsr read (pre-set step)");
    dmi_read(DMI_DATA0);
    dmi_write(DMI_DATA0, dmi_readval | DCSR_STEP);
    abs_run(CMD_WR_DCSR);
    chk_cmderr("dcsr write (set step)");
    read_dcsr;
    if ((dcsr_now & DCSR_STEP) === 32'h0) begin
        $display("ERROR: dcsr.step did not set (dcsr=%h) %t ns", dcsr_now, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.step set (dcsr=%h) %t ns", dcsr_now, $time);

    //========================================================================
    // STEP 1 -- jalr: dpc -> step_start, no GPR change
    //========================================================================
    do_step;
    chk_step("step 1 (jalr)", target_addr);
    if ((probes_cpu.x10 !== 32'h0) || (probes_cpu.x14 !== RD_SENTINEL) || (probes_cpu.x05 !== 32'h0)) begin
        $display("ERROR: step 1 (jalr) altered a step-run target (a0=%h a4=%h x5=%h) %t ns",
                 probes_cpu.x10, probes_cpu.x14, probes_cpu.x05, $time);
        error = error + 1;
    end
    dpc_prev = dpc_now;

    //========================================================================
    // STEP 2 -- lw a0,0(a1): dpc -> step_start+4, a0 = 0x80000101
    //========================================================================
    do_step;
    chk_step("step 2 (lw a0)", target_addr + 32'd4);
    if (probes_cpu.x10 !== MISALIGNED_ADDR) begin
        $display("ERROR: step 2 a0=%h after lw (expected %h) %t ns", probes_cpu.x10, MISALIGNED_ADDR, $time);
        error = error + 1;
    end else $display("PASS:  step 2 retired lw a0 (a0=%h) %t ns", probes_cpu.x10, $time);
    if (probes_cpu.x14 !== RD_SENTINEL) begin
        $display("ERROR: step 2 ran too far: a4=%h (expected sentinel) %t ns", probes_cpu.x14, $time);
        error = error + 1;
    end
    if (probes_cpu.x23 !== 32'h0) begin
        $display("ERROR: step 2 entered the trap handler prematurely (x23=%0d) %t ns", probes_cpu.x23, $time);
        error = error + 1;
    end
    dpc_prev = dpc_now;

    //========================================================================
    // STEP 3 -- lw a4,0(a0): MISALIGNED -> exception must be taken.
    //   dpc == mtvec, dcsr.cause == 4, mcause == 4, mtval == 0x80000101,
    //   mepc == step_start+4, a4 still sentinel.
    //========================================================================
    do_step;
    chk_step("step 3 (lw a4, misaligned)", mtvec_val);
    if (dpc_now === (dpc_prev + 32'd4))
        $display("ERROR: step 3 BUG SIGNATURE: dpc=%h is the instruction AFTER the faulting lw -- exception skipped %t ns", dpc_now, $time);

    read_csr(CMD_RD_MCAUSE, "mcause read", csr_val);
    if (csr_val !== 32'h00000004) begin
        $display("ERROR: step 3 mcause=%h (expected 4 = load address misaligned) %t ns", csr_val, $time);
        error = error + 1;
    end else $display("PASS:  step 3 mcause=4 %t ns", $time);
    read_csr(CMD_RD_MTVAL, "mtval read", csr_val);
    if (csr_val !== MISALIGNED_ADDR) begin
        $display("ERROR: step 3 mtval=%h (expected %h) %t ns", csr_val, MISALIGNED_ADDR, $time);
        error = error + 1;
    end else $display("PASS:  step 3 mtval=%h %t ns", csr_val, $time);
    read_csr(CMD_RD_MEPC, "mepc read", csr_val);
    if (csr_val !== dpc_prev) begin
        $display("ERROR: step 3 mepc=%h (expected &crit_lw=%h) %t ns", csr_val, dpc_prev, $time);
        error = error + 1;
    end else $display("PASS:  step 3 mepc=%h == &crit_lw %t ns", csr_val, $time);
    if (probes_cpu.x14 !== RD_SENTINEL) begin
        $display("ERROR: step 3 faulting lw wrote rd (a4=%h, expected sentinel %h) %t ns", probes_cpu.x14, RD_SENTINEL, $time);
        error = error + 1;
    end else $display("PASS:  step 3 a4 keeps its sentinel %t ns", $time);
    if (probes_cpu.x05 !== 32'h0) begin
        $display("ERROR: step 3 ran too far: x5=%h already set %t ns", probes_cpu.x05, $time);
        error = error + 1;
    end
    dpc_prev = dpc_now;

    //========================================================================
    // STEP 4 -- csrr x20,mcause (handler): dpc -> mtvec+4, x20 == 4
    //========================================================================
    do_step;
    chk_step("step 4 (csrr x20,mcause)", mtvec_val + 32'd4);
    if (probes_cpu.x20 !== 32'h00000004) begin
        $display("ERROR: step 4 handler recorded mcause=%h (expected 4) %t ns", probes_cpu.x20, $time);
        error = error + 1;
    end else $display("PASS:  step 4 handler recorded mcause=4 %t ns", $time);
    dpc_prev = dpc_now;

    //========================================================================
    // STEP 5 -- csrr x21,mtval (handler): dpc -> mtvec+8, x21 == 0x80000101
    //========================================================================
    do_step;
    chk_step("step 5 (csrr x21,mtval)", mtvec_val + 32'd8);
    if (probes_cpu.x21 !== MISALIGNED_ADDR) begin
        $display("ERROR: step 5 handler recorded mtval=%h (expected %h) %t ns", probes_cpu.x21, MISALIGNED_ADDR, $time);
        error = error + 1;
    end else $display("PASS:  step 5 handler recorded mtval=%h %t ns", probes_cpu.x21, $time);

    //========================================================================
    // CLEAR dcsr.step and free-run to the end marker
    //========================================================================
    abs_run(CMD_RD_DCSR);
    chk_cmderr("dcsr read (pre-clear step)");
    dmi_read(DMI_DATA0);
    dmi_write(DMI_DATA0, dmi_readval & ~DCSR_STEP);
    abs_run(CMD_WR_DCSR);
    chk_cmderr("dcsr write (clear step)");
    read_dcsr;
    if ((dcsr_now & DCSR_STEP) !== 32'h0) begin
        $display("ERROR: dcsr.step did not clear (dcsr=%h) %t ns", dcsr_now, $time);
        error = error + 1;
    end

    random_irq_enable = 0;
    dm_resume;

    //========================================================================
    // FINAL -- firmware finishes the handler and the trailer on its own
    //========================================================================
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 5000)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: firmware never reached the end marker after resume %t ns", $time);
        error = error + 1;
    end
    $display("--- handler-recorded mcause x20 (expect 4) ---");
    check_cpu_reg(20, 32'h00000004);
    $display("--- handler-recorded mtval x21 (expect 0x80000101) ---");
    check_cpu_reg(21, MISALIGNED_ADDR);
    $display("--- handler-recorded mepc x22 (expect &crit_lw) ---");
    check_cpu_reg(22, target_addr + 32'd4);
    $display("--- handler entries x23 (expect 1) ---");
    check_cpu_reg(23, 32'h00000001);
    $display("--- faulting-load rd a4 (expect sentinel) ---");
    check_cpu_reg(14, RD_SENTINEL);
    check_cpu_reg(10, MISALIGNED_ADDR);
    check_cpu_reg(5,  X5_VAL);
    check_cpu_reg(6,  X6_VAL);
    check_cpu_reg(18, X18_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

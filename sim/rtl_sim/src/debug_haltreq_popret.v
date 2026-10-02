//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_haltreq_popret
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: debug entry across CM.POPRET must land on the RETURN target
//   Debug 1.0: dpc is "the next instruction that should be executed"; after a
//   cm.popret that is `ra`, never the instruction physically behind the popret
//   (the firmware's PAD, which sets x16 and must never run).
//
//   PHASE 1  haltreq sweep. For offset = 0..39: wait for the per-iteration
//            marker, wait `offset` cycles, write dmcontrol.haltreq, poll
//            allhalted, abstract-read dpc. dpc must be inside the leaf
//            [leaf, pad) or inside the loop [loop, loop_end); dpc inside
//            [pad, pad_end) is the bug signature. x16 must stay 0. Resume.
//            At least one halt must land inside the leaf (coverage).
//   PHASE 2  single-step {jalr, call, cm.push, addi, cm.popret}: dpc after
//            each step == the firmware-published next-instruction label; the
//            popret step must give dpc == step_ret, sp restored, x16 == 0.
//   PHASE 3a firmware-armed breakpoint trigger on &pad: four leaf calls, no
//            trap (x22 == 0).
//   PHASE 3b debugger-armed action=1 trigger on the return target p3b_ret:
//            fires with dcsr.cause=2, dpc == &p3b_ret, side effect not taken.
//   PHASE 3c debugger-armed action=1 trigger on &pad: two leaf calls must not
//            enter Debug Mode.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
integer off;
integer halts_in_leaf, halts_in_loop, halts_bad;
integer cyc;
reg        c_halted;

reg [31:0] dpc_now, dpc_prev, dcsr_now, acmd_rdata;
reg [2:0]  cause_now;
reg [31:0] a_leaf, a_pad, a_pad_end, a_loop, a_loop_end;
reg [31:0] a_spin2, a_step_entry, a_leaf_body, a_popret, a_step_ret;
reg [31:0] a_spin3, a_p3b_entry, a_p3b_ret, a_spin4, a_p3c_entry;
reg [31:0] sp_before;

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

// abstractcs field masks
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (cmdtype=0, aarsize=2, transfer=1)
localparam [31:0] CMD_RD_DCSR    = 32'h00220000 | 32'h000007b0;
localparam [31:0] CMD_WR_DCSR    = 32'h00230000 | 32'h000007b0;
localparam [31:0] CMD_RD_DPC     = 32'h00220000 | 32'h000007b1;
localparam [31:0] CMD_WR_X12     = 32'h00230000 | 32'h0000100c;
localparam [31:0] CMD_WR_TSELECT = 32'h00230000 | 32'h000007a0;
localparam [31:0] CMD_WR_TDATA1  = 32'h00230000 | 32'h000007a1;
localparam [31:0] CMD_WR_TDATA2  = 32'h00230000 | 32'h000007a2;

// dcsr fields
localparam [31:0] DCSR_STEP  = 32'h00000004; // [2] step
localparam [31:0] DCSR_CAUSE = 32'h000001C0; // [8:6]

// debugger-armed execute trigger: type6 | dmode | action=1 | execute | m | match=0
localparam [31:0] ARM_TDATA1 = 32'h68001044;

localparam integer N_OFF = 40;   // haltreq offsets swept (cycles after the marker)

// The pad must never execute: flag it the moment x16 changes.
always @(probes_cpu.x16) begin
    if (hresetn && (probes_cpu.x16 !== 32'h0)) begin
        $display("ERROR: pad behind cm.popret EXECUTED (x16=%h): the popret return was dropped %t ns", probes_cpu.x16, $time);
        error = error + 1;
    end
end

// Issue an abstract command and wait for abstractcs.busy to clear.
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

task abs_wr;
   input [31:0] cmd;
   input [31:0] val;
   begin
      dmi_write(DMI_DATA0, val);
      abs_run(cmd);
      chk_cmderr("abstract write");
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

// Read dcsr (0x7b0) into dcsr_now / cause_now.
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

// Poll dmstatus.allhalted (bounded); leaves dmstatus in dmi_readval.
task poll_halted;
   input integer budget;
   begin
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < budget)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
   end
endtask

// Single step: drop haltreq, resumereq, wait for the auto re-halt.
task do_step;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);
      poll_halted(200);
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: step did not auto re-halt (allhalted=0) %t ns", $time);
         error = error + 1;
      end
      read_dcsr;
      if (cause_now !== 3'd4) begin
         $display("ERROR: step dcsr.cause=%0d (expected 4=step) %t ns", cause_now, $time);
         error = error + 1;
      end
      read_dpc;
   end
endtask

// Check a stepped dpc against the published next-instruction label.
task chk_step_dpc;
   input [8*40:1] what;
   input [31:0]   expect_pc;
   begin
      if (dpc_now !== expect_pc) begin
         $display("ERROR: step %0s: dpc=%h (expected %h) %t ns", what, dpc_now, expect_pc, $time);
         if (dpc_now === a_pad)
            $display("ERROR:   dpc names the PAD behind cm.popret (popret_pc+2), not the return target");
         error = error + 1;
      end else $display("PASS:  step %0s: dpc=%h %t ns", what, dpc_now, $time);
   end
endtask

// Halt at a spin label, verify dpc, redirect the spin base x12 to `target`.
task halt_at_spin_and_redirect;
   input [8*16:1] tag;
   input [31:0]   spin_pc;
   input [31:0]   target;
   begin
      dm_halt;
      if (dbg_debug_mode !== 1'b1) begin
         $display("ERROR: %0s hart not in Debug Mode after dm_halt %t ns", tag, $time);
         error = error + 1;
      end
      read_dpc;
      if (dpc_now !== spin_pc) begin
         $display("ERROR: %0s parked dpc=%h (expected spin %h) %t ns", tag, dpc_now, spin_pc, $time);
         error = error + 1;
      end else $display("PASS:  %0s parked at spin dpc=%h %t ns", tag, dpc_now, $time);
      abs_wr(CMD_WR_X12, target);
      if (probes_cpu.x12 !== target) begin
         $display("ERROR: %0s x12 redirect did not land (x12=%h, want %h) %t ns", tag, probes_cpu.x12, target, $time);
         error = error + 1;
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

    // Phase 3a's breakpoint trap would be a FAILURE, but it must not also be
    // counted by the exception monitor before the firmware counter reports it.
    error_on_exception = 0;
    random_irq_enable  = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG HALTREQ POPRET: debug entry across cm.popret -> return tgt  |");
    $display(" ====================================================================");

    wait(probes_cpu.x31 === 32'h55555555);
    a_leaf       = probes_cpu.x17;  a_pad      = probes_cpu.x18;  a_pad_end = probes_cpu.x19;
    a_loop       = probes_cpu.x20;  a_loop_end = probes_cpu.x21;
    a_spin2      = probes_cpu.x23;  a_step_entry = probes_cpu.x24;
    a_leaf_body  = probes_cpu.x25;  a_popret   = probes_cpu.x26;  a_step_ret = probes_cpu.x27;
    a_spin3      = probes_cpu.x06;  a_p3b_entry = probes_cpu.x08; a_p3b_ret  = probes_cpu.x28;
    a_spin4      = probes_cpu.x07;  a_p3c_entry = probes_cpu.x09;
    $display("labels: leaf=%h body=%h popret=%h pad=%h..%h loop=%h..%h",
             a_leaf, a_leaf_body, a_popret, a_pad, a_pad_end, a_loop, a_loop_end);
    if (a_pad !== a_popret + 32'd2) begin
        $display("ERROR: layout: pad (%h) is not popret_pc+2 (%h) %t ns", a_pad, a_popret, $time);
        error = error + 1;
    end

    // bring the DM out of reset
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    //========================================================================
    // PHASE 1: haltreq sweep
    //========================================================================
    $display("");
    $display("--- Phase 1: haltreq swept 0..%0d cycles after the per-iteration marker ---", N_OFF-1);
    halts_in_leaf = 0; halts_in_loop = 0; halts_bad = 0;
    for (off = 0; off < N_OFF; off = off + 1) begin
        wait(probes_cpu.x31 !== 32'h11111111);
        wait(probes_cpu.x31 === 32'h11111111);
        repeat (off) @(posedge free_clk);
        dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
        poll_halted(200);
        if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
            $display("ERROR: off=%0d hart did not halt (allhalted=0) %t ns", off, $time);
            error = error + 1;
        end
        read_dpc;
        if ((dpc_now >= a_pad) && (dpc_now < a_pad_end)) begin
            $display("ERROR: off=%0d dpc=%h names the PAD behind cm.popret (popret_pc+2): return dropped %t ns", off, dpc_now, $time);
            error = error + 1;
            halts_bad = halts_bad + 1;
        end else if ((dpc_now >= a_leaf) && (dpc_now < a_pad)) begin
            $display("PASS:  off=%0d dpc=%h inside the leaf (iter %0d) %t ns", off, dpc_now, probes_cpu.x13, $time);
            halts_in_leaf = halts_in_leaf + 1;
        end else if ((dpc_now >= a_loop) && (dpc_now < a_loop_end)) begin
            $display("PASS:  off=%0d dpc=%h inside the loop (iter %0d) %t ns", off, dpc_now, probes_cpu.x13, $time);
            halts_in_loop = halts_in_loop + 1;
        end else begin
            $display("ERROR: off=%0d dpc=%h is neither in the leaf nor in the loop %t ns", off, dpc_now, $time);
            error = error + 1;
            halts_bad = halts_bad + 1;
        end
        if (probes_cpu.x16 !== 32'h0) begin
            $display("ERROR: off=%0d pad marker x16=%h while halted %t ns", off, probes_cpu.x16, $time);
            error = error + 1;
        end
        dm_resume;
    end
    $display("Phase 1 summary: %0d halts in the leaf, %0d in the loop, %0d bad", halts_in_leaf, halts_in_loop, halts_bad);
    if (halts_in_leaf == 0) begin
        $display("ERROR: no halt landed inside the leaf: the sweep did not cover cm.push/cm.popret %t ns", $time);
        error = error + 1;
    end

    wait(probes_cpu.x31 === 32'h66666666);
    check_cpu_reg(13, 32'd200);         // all iterations ran
    check_cpu_reg(14, 32'd200);         // leaf body once per iteration
    check_cpu_reg(11, 32'h0);           // SP balanced
    check_cpu_reg(16, 32'h0);           // pad never executed

    //========================================================================
    // PHASE 2: single-step through the leaf
    //========================================================================
    $display("");
    $display("--- Phase 2: single-step {jalr, call, cm.push, addi, cm.popret} ---");
    repeat (10) @(posedge free_clk);
    halt_at_spin_and_redirect("P2", a_spin2, a_step_entry);
    sp_before = probes_cpu.x02;

    // set dcsr.step (RMW, keep prv)
    abs_run(CMD_RD_DCSR); chk_cmderr("dcsr read"); dmi_read(DMI_DATA0);
    abs_wr(CMD_WR_DCSR, dmi_readval | DCSR_STEP);
    read_dcsr;
    if ((dcsr_now & DCSR_STEP) === 32'h0) begin
        $display("ERROR: dcsr.step did not set (dcsr=%h) %t ns", dcsr_now, $time);
        error = error + 1;
    end

    do_step; chk_step_dpc("1 jalr -> step_entry", a_step_entry);
    do_step; chk_step_dpc("2 call -> leaf",       a_leaf);
    do_step; chk_step_dpc("3 cm.push -> body",    a_leaf_body);
    if (probes_cpu.x02 !== sp_before - 32'd16) begin
        $display("ERROR: after cm.push step sp=%h (expected %h) %t ns", probes_cpu.x02, sp_before - 32'd16, $time);
        error = error + 1;
    end
    do_step; chk_step_dpc("4 addi -> popret",     a_popret);
    if (probes_cpu.x14 !== 32'd201) begin
        $display("ERROR: after addi step x14=%0d (expected 201) %t ns", probes_cpu.x14, $time);
        error = error + 1;
    end
    do_step; chk_step_dpc("5 cm.popret -> step_ret (return target)", a_step_ret);
    if (probes_cpu.x02 !== sp_before) begin
        $display("ERROR: after cm.popret step sp=%h (expected %h restored) %t ns", probes_cpu.x02, sp_before, $time);
        error = error + 1;
    end else $display("PASS:  after cm.popret step sp restored (%h) %t ns", probes_cpu.x02, $time);
    if (probes_cpu.x16 !== 32'h0) begin
        $display("ERROR: pad marker x16=%h after the cm.popret step %t ns", probes_cpu.x16, $time);
        error = error + 1;
    end

    // clear step, resume free
    abs_run(CMD_RD_DCSR); chk_cmderr("dcsr read"); dmi_read(DMI_DATA0);
    abs_wr(CMD_WR_DCSR, dmi_readval & ~DCSR_STEP);
    read_dcsr;
    if ((dcsr_now & DCSR_STEP) !== 32'h0) begin
        $display("ERROR: dcsr.step did not clear (dcsr=%h) %t ns", dcsr_now, $time);
        error = error + 1;
    end
    dm_resume;

    wait(probes_cpu.x31 === 32'h77777777);
    $display("PASS:  step phase done, firmware running free %t ns", $time);

    //========================================================================
    // PHASE 3a: firmware-armed breakpoint on &pad must never fire
    //========================================================================
    $display("");
    $display("--- Phase 3a: hart-side breakpoint trigger on the pad, 4 calls ---");
    wait(probes_cpu.x31 === 32'h88888888);
    check_cpu_reg(22, 32'h0);           // no breakpoint trap
    check_cpu_reg(16, 32'h0);           // pad never executed
    check_cpu_reg(14, 32'd205);         // 201 + 4 calls

    //========================================================================
    // PHASE 3b: debugger-armed action=1 trigger on the return target
    //========================================================================
    $display("");
    $display("--- Phase 3b: enter-Debug trigger on the call's return target ---");
    repeat (10) @(posedge free_clk);
    halt_at_spin_and_redirect("P3b", a_spin3, a_p3b_entry);
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA2, a_p3b_ret);
    abs_wr(CMD_WR_TDATA1, ARM_TDATA1);
    dm_resume;

    poll_halted(20000);
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: 3b trigger on the return target did not enter Debug Mode %t ns", $time);
        error = error + 1;
    end else begin
        read_dcsr;
        if (cause_now !== 3'd2) begin
            $display("ERROR: 3b dcsr.cause=%0d (expected 2=trigger) %t ns", cause_now, $time);
            error = error + 1;
        end
        read_dpc;
        if (dpc_now !== a_p3b_ret) begin
            $display("ERROR: 3b dpc=%h (expected return target %h) %t ns", dpc_now, a_p3b_ret, $time);
            error = error + 1;
        end else $display("PASS:  3b trigger fired at the return target dpc=%h %t ns", dpc_now, $time);
        if (probes_cpu.x29 !== 32'h0) begin
            $display("ERROR: 3b side effect taken before the fire (x29=%h) %t ns", probes_cpu.x29, $time);
            error = error + 1;
        end
        if (probes_cpu.x16 !== 32'h0) begin
            $display("ERROR: 3b pad marker x16=%h %t ns", probes_cpu.x16, $time);
            error = error + 1;
        end
    end
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, 32'h0);       // disarm (clears dmode)
    dm_resume;

    wait(probes_cpu.x31 === 32'h99999999);
    check_cpu_reg(29, 32'h3B3B3B3B);    // the return target executed after the resume

    //========================================================================
    // PHASE 3c: debugger-armed action=1 trigger on &pad must never fire
    //========================================================================
    $display("");
    $display("--- Phase 3c: enter-Debug trigger on the pad, 2 calls ---");
    repeat (10) @(posedge free_clk);
    halt_at_spin_and_redirect("P3c", a_spin4, a_p3c_entry);
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA2, a_pad);
    abs_wr(CMD_WR_TDATA1, ARM_TDATA1);
    dm_resume;

    c_halted = 1'b0;
    cyc = 0;
    while ((probes_cpu.x31 !== 32'hAAAAAAAA) && !c_halted && (cyc < 20000)) begin
        @(posedge free_clk);
        cyc = cyc + 1;
        if (dbg_debug_mode === 1'b1) c_halted = 1'b1;
    end
    if (c_halted) begin
        read_dpc;
        $display("ERROR: 3c trigger on the PAD fired (Debug Mode entered, dpc=%h): the pad is never executed %t ns", dpc_now, $time);
        error = error + 1;
        abs_wr(CMD_WR_TSELECT, 32'h0);
        abs_wr(CMD_WR_TDATA1, 32'h0);
        dm_resume;
        wait(probes_cpu.x31 === 32'hAAAAAAAA);
    end else if (cyc >= 20000) begin
        $display("ERROR: 3c firmware did not reach the done marker %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  3c trigger on the pad never fired across 2 calls %t ns", $time);
        // cleanup: disarm
        dm_halt;
        abs_wr(CMD_WR_TSELECT, 32'h0);
        abs_wr(CMD_WR_TDATA1, 32'h0);
        dm_resume;
    end

    //========================================================================
    // Done
    //========================================================================
    wait(probes_cpu.x31 === 32'hdeadbeef);
    check_cpu_reg(16, 32'h0);           // pad never executed
    check_cpu_reg(22, 32'h0);           // no unexpected trap
    check_cpu_reg(14, 32'd208);         // 205 + 1 (3b) + 2 (3c)
    check_cpu_reg(11, 32'h0);           // SP balanced at the end
    check_cpu_reg(5,  32'hA5A5A5A5);    // sentinel

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

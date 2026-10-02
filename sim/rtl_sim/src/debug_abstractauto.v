//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_abstractauto
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: abstractauto.autoexecdata[0] (DMI 0x18 bit 0) - RISC-V Debug 1.0
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Halts the spinning hart, then:
//     - WARL     : abstractauto (0x18) bit0 is R/W and all other bits are
//                  WARL-0: write 1->reads 1, write 0->reads 0, write
//                  0xFFFFFFFF->reads exactly 0x00000001;
//     - WRITE-AE : with autoexecdata0=1, a WRITE of data0 auto-replays the last
//                  command (write x5 from data0) -> x5 tracks each data0 write;
//     - READ-AE  : with autoexecdata0=1, a READ of data0 auto-replays the last
//                  command (read x6 into data0) -> a corrupted data0 is
//                  overwritten by the re-executed read (observed cleanly with
//                  autoexec turned back off);
//     - CMDERR=4 : with autoexecdata0=1 and the hart RESUMED (running), a data0
//                  access sets cmderr=4 (halt/resume) exactly like a direct
//                  command; W1C-clear and re-halt recover the DM;
//     - RESUME   : hart resumes and finishes its loop; injected/neighbor
//                  sentinels (x5/x6/x7) are all cross-checked.
//
//   ORDERING PITFALL: because a data0 access is itself the auto-exec trigger,
//   every *observing* access is done with autoexecdata0=0 so the verification
//   read/write does not itself re-fire the command. Inline comments flag this
//   at each step.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
reg [31:0] cap;   // scratch for a captured data0 value (read triggers)

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0       = 7'h04;
localparam [6:0] DMI_DMCONTROL   = 7'h10;
localparam [6:0] DMI_DMSTATUS    = 7'h11;
localparam [6:0] DMI_ABSTRACTCS  = 7'h16;
localparam [6:0] DMI_COMMAND     = 7'h17;
localparam [6:0] DMI_ABSTRACTAUTO = 7'h18;

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

// abstractauto: only bit0 (autoexecdata[0]) implemented; all other bits WARL-0
localparam [31:0] AUTO_DATA0 = 32'h00000001;

// Access Register command words (command[0x17], cmdtype=0)
//   [22:20] aarsize=2 (32-bit) -> 0x00200000 ; [17] transfer=1 -> 0x00020000 ;
//   [16] write -> 0x00010000 ; [15:0] regno = 0x1000 + gpr (x5->0x1005 ; x6->0x1006)
localparam [31:0] CMD_WRITE_X5 = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h00001005; // 0x00231005
localparam [31:0] CMD_READ_X5  = 32'h00200000 | 32'h00020000 | 32'h00001005;                // 0x00221005
localparam [31:0] CMD_WRITE_X6 = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h00001006; // 0x00231006
localparam [31:0] CMD_READ_X6  = 32'h00200000 | 32'h00020000 | 32'h00001006;                // 0x00221006

localparam [31:0] X5_INIT     = 32'h51515151;  // firmware init (must be overwritten by DMI)
localparam [31:0] X5_FIRST    = 32'h11111111;  // first DMI-driven write of x5
localparam [31:0] X5_AUTOEXEC = 32'h22222222;  // value auto-replayed into x5 via data0 write
localparam [31:0] X6_KNOWN    = 32'h6C6C6C6C;  // DMI-injected known source for read-autoexec
localparam [31:0] X7_SENTINEL = 32'h73737373;  // neighbor, never accessed
localparam [31:0] DATA0_GARBAGE = 32'hDEADDEAD; // planted in data0 before the read-replay

// Issue an abstract command via the command register and wait for busy clear;
// the final abstractcs (incl. cmderr) is left in dmi_readval. Used only while
// autoexecdata0=0 so writing 0x17 is the sole trigger.
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
      if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
         $display("ERROR: abstractcs.busy stuck after command %h %t ns", cmd, $time);
         error = error + 1;
      end
   end
endtask

// Poll abstractcs.busy clear, leaving the final abstractcs in dmi_readval. Used
// after an auto-exec trigger (a data0 access), where the trigger is NOT a 0x17
// write so abs_run cannot be reused.
task ae_wait;
   begin
      to = 0;
      dmi_read(DMI_ABSTRACTCS);
      while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
         dmi_read(DMI_ABSTRACTCS);
         to = to + 1;
      end
      if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
         $display("ERROR: abstractcs.busy stuck after auto-exec trigger %t ns", $time);
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

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG ABSTRACTAUTO: autoexecdata0 (DMI 0x18 bit0) - a data0 access |");
    $display("|  auto-replays the last abstract command (RISC-V Debug 1.0)          |");
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
    end else $display("PASS:  hart in Debug Mode (abstract access permitted) %t ns", $time);

    //========================================================================
    // STEP 1: abstractauto WARL - bit0 R/W, all other bits read 0.
    //   Writing/reading 0x18 is NOT a data0 access, so nothing auto-fires here.
    //========================================================================
    dmi_write(DMI_ABSTRACTAUTO, AUTO_DATA0);          // set autoexecdata0=1
    dmi_read(DMI_ABSTRACTAUTO);
    if (dmi_readval !== AUTO_DATA0) begin
        $display("ERROR: abstractauto read %h after write 1 (expected 0x00000001) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  abstractauto.autoexecdata0 reads 1 after write 1 %t ns", $time);

    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000);        // clear autoexecdata0
    dmi_read(DMI_ABSTRACTAUTO);
    if (dmi_readval !== 32'h00000000) begin
        $display("ERROR: abstractauto read %h after write 0 (expected 0) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  abstractauto.autoexecdata0 reads 0 after write 0 %t ns", $time);

    dmi_write(DMI_ABSTRACTAUTO, 32'hFFFFFFFF);        // WARL: only bit0 sticks
    dmi_read(DMI_ABSTRACTAUTO);
    if (dmi_readval !== AUTO_DATA0) begin
        $display("ERROR: abstractauto read %h after write 0xFFFFFFFF (expected 0x00000001; upper bits WARL-0) %t ns", dmi_readval, $time);
        error = error + 1;
    end else $display("PASS:  abstractauto upper bits are WARL-0 (read 0x00000001 after all-ones write) %t ns", $time);

    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000);        // leave autoexec OFF entering step 2
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);            // clear any residual cmderr (W1C)

    //========================================================================
    // STEP 2: WRITE-autoexec.
    //   2a. Establish "last command" = write x5 from data0 (autoexec OFF, so the
    //       0x17 write is the only trigger). x5 init 0x51515151 differs from the
    //       injected 0x11111111 -> the check discriminates a real DMI write.
    //========================================================================
    dmi_write(DMI_DATA0, X5_FIRST);                   // autoexec OFF: plain data0 load, no fire
    abs_run(CMD_WRITE_X5);                            // write x5 <- data0 (0x11111111)
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after establishing write-x5 command (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    if (probes_cpu.x05 !== X5_FIRST) begin
        $display("ERROR: x5=%h after direct write-x5 (expected %h) %t ns", probes_cpu.x05, X5_FIRST, $time);
        error = error + 1;
    end else $display("PASS:  direct write-x5 landed 0x%h (last command established) %t ns", X5_FIRST, $time);

    //   2b. Arm autoexecdata0=1. Writing 0x18 is not a data0 access -> no fire.
    dmi_write(DMI_ABSTRACTAUTO, AUTO_DATA0);
    $display("INFO:  autoexecdata0 armed; last command = write x5 from data0 %t ns", $time);

    //   2c. Write data0=0x22222222. This data0 ACCESS auto-replays write-x5:
    //       data0 loads 0x22222222, then the replayed command reads data0 into
    //       x5 -> x5 becomes 0x22222222. Poll busy, check cmderr=0.
    dmi_write(DMI_DATA0, X5_AUTOEXEC);                // <-- the auto-exec trigger
    ae_wait;                                          // wait busy clear (auto-fired command ran)
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after auto-exec data0 write (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  auto-exec data0 write completed with cmderr=0 %t ns", $time);

    // Backdoor regfile probe: robust, unaffected by autoexec.
    if (probes_cpu.x05 !== X5_AUTOEXEC) begin
        $display("ERROR: x5=%h after auto-exec data0 write (expected %h; write command did NOT re-fire) %t ns", probes_cpu.x05, X5_AUTOEXEC, $time);
        error = error + 1;
    end else $display("PASS:  data0 write auto-replayed write-x5: x5=0x%h %t ns", X5_AUTOEXEC, $time);

    //   PITFALL AVOIDANCE: turn autoexec OFF before the verifying DMI read of x5,
    //   so the read-x5 command below does not itself re-trigger write-x5.
    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000);
    abs_run(CMD_READ_X5);                             // read x5 -> data0
    dmi_read(DMI_DATA0);                              // autoexec OFF: plain observe, no fire
    if (dmi_readval !== X5_AUTOEXEC) begin
        $display("ERROR: DMI read-back of x5 returned %h (expected %h) %t ns", dmi_readval, X5_AUTOEXEC, $time);
        error = error + 1;
    end else $display("PASS:  DMI read-back confirms x5=0x%h (write-autoexec verified) %t ns", X5_AUTOEXEC, $time);

    //========================================================================
    // STEP 3: READ-autoexec (the read-access trigger path).
    //   Recipe that is both robust AND discriminating against a DM that ignores
    //   autoexec: pre-corrupt data0, fire via a READ, then observe with a
    //   SECOND (autoexec-off) read - never assert on the triggering read's own
    //   return value (pre/post-replay timing of that value is ambiguous).
    //========================================================================
    //   Inject a KNOWN source into x6 (autoexec OFF), then set last command =
    //   read x6. After the read command, data0 holds X6_KNOWN.
    dmi_write(DMI_DATA0, X6_KNOWN);
    abs_run(CMD_WRITE_X6);                            // write x6 <- data0 (0x6C6C6C6C)
    if (probes_cpu.x06 !== X6_KNOWN) begin
        $display("ERROR: x6=%h after direct write-x6 (expected %h) %t ns", probes_cpu.x06, X6_KNOWN, $time);
        error = error + 1;
    end else $display("PASS:  known source x6=0x%h injected %t ns", X6_KNOWN, $time);

    abs_run(CMD_READ_X6);                            // last command := read x6 -> data0=X6_KNOWN
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after establishing read-x6 command (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end

    //   Pre-corrupt data0 with garbage (autoexec still OFF, so this write does NOT
    //   fire; writing 0x04 does not change the last command latched in 0x17).
    dmi_write(DMI_DATA0, DATA0_GARBAGE);
    dmi_read(DMI_DATA0);                              // (autoexec OFF) confirm garbage is present
    if (dmi_readval !== DATA0_GARBAGE) begin
        $display("ERROR: data0=%h after planting garbage (expected %h) %t ns", dmi_readval, DATA0_GARBAGE, $time);
        error = error + 1;
    end else $display("PASS:  data0 pre-corrupted with 0x%h (autoexec off, no fire) %t ns", DATA0_GARBAGE, $time);

    //   Arm autoexec and TRIGGER via a data0 READ. Do NOT assert on this read's
    //   own return value - only that it completes cleanly (cmderr=0). The read
    //   re-executes read-x6, which refreshes data0 from x6 (=X6_KNOWN).
    dmi_write(DMI_ABSTRACTAUTO, AUTO_DATA0);          // autoexec ON
    dmi_read(DMI_DATA0);                              // <-- the read-access auto-exec trigger
    cap = dmi_readval;                                // captured for info only (timing-ambiguous)
    ae_wait;                                          // wait busy clear (re-executed read-x6 ran)
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after read-autoexec trigger (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  read-access auto-exec trigger completed cmderr=0 (triggering read returned 0x%h) %t ns", cap, $time);

    //   PITFALL AVOIDANCE: turn autoexec OFF, THEN observe data0 with a plain
    //   read. If data0 now holds X6_KNOWN (not the planted garbage), only a real
    //   re-execution of read-x6 could have overwritten it -> read-autoexec proven.
    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000);        // autoexec OFF
    dmi_read(DMI_DATA0);                              // plain observe, no fire
    if (dmi_readval !== X6_KNOWN) begin
        $display("ERROR: data0=%h after read-autoexec (expected %h; read command did NOT re-fire) %t ns", dmi_readval, X6_KNOWN, $time);
        error = error + 1;
    end else $display("PASS:  read-autoexec re-ran read-x6: garbage overwritten, data0=0x%h %t ns", X6_KNOWN, $time);

    //========================================================================
    // STEP 4: cmderr=4 under autoexec while the hart is RUNNING.
    //   Establish a valid last command (read x6) with autoexec OFF, arm autoexec,
    //   resume the hart, then a data0 access must set cmderr=4 (halt/resume:
    //   command attempted while hart not halted) - exactly like a direct command.
    //========================================================================
    abs_run(CMD_READ_X6);                            // last command := read x6 (cmderr should be 0)
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);           // ensure cmderr clear (else trigger is ignored)
    dmi_write(DMI_ABSTRACTAUTO, AUTO_DATA0);         // autoexec ON

    // resume the hart (drop haltreq, assert resumereq), poll allrunning
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart not running before cmderr=4 check (allrunning=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart running; a data0 access must now cmderr=4 %t ns", $time);

    // Data0 access while running: auto-exec fires the command but the hart is not
    // halted -> abstract command aborts with cmderr=4 (halt/resume).
    dmi_write(DMI_DATA0, 32'hABCDABCD);              // <-- auto-exec trigger while running
    ae_wait;                                          // busy must clear (command aborted)
    if (((dmi_readval & ACS_CMDERR) >> 8) !== 3'd4) begin
        $display("ERROR: cmderr=%0d after data0 access while running (expected 4=halt/resume) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=4 (halt/resume) on auto-exec data0 access while running %t ns", $time);

    // Clear cmderr (W1C) and confirm it reads back 0.
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);
    dmi_read(DMI_ABSTRACTCS);
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr did not clear via W1C (still %0d) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr cleared by W1C after the running-access error %t ns", $time);

    // Disarm autoexec so nothing re-fires during the clean re-halt / final run.
    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000);

    // Re-halt to prove the DM recovered cleanly from the running-command error.
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: hart did not re-halt after cmderr=4 recovery (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart re-halted cleanly after cmderr=4 recovery (%0d polls) %t ns", to, $time);

    //========================================================================
    // RESUME + final architectural checks
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
        $display("ERROR: no allresumeack after final resumereq %t ns", $time);
        error = error + 1;
    end else $display("PASS:  allresumeack set after final resume (%0d polls) %t ns", to, $time);

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart not running after final resume (allrunning=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart running after final resume (allrunning=1) %t ns", $time);

    // prevent IRQs from disturbing the final architectural checks
    random_irq_enable = 0;

    // --- firmware must complete the loop and reach the end on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    // x5 = auto-exec-replayed value (write-autoexec produced 0x22222222)
    check_cpu_reg(5, X5_AUTOEXEC);
    // x6 = DMI-injected known source (read-autoexec never modified it)
    check_cpu_reg(6, X6_KNOWN);
    // x7 neighbor: never touched by any abstract/auto-exec access
    check_cpu_reg(7, X7_SENTINEL);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_acmd_postincr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Access Register aarpostincrement (command bit 19) is SUPPORTED
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Halts the spinning hart, then:
//     - NO-INCR  : an Access Register read of x6 with aarpostincrement=0, replayed
//                  via abstractauto, keeps returning the SAME register (regno never
//                  advances) -> constant 0x66666666 across successive data0 reads;
//     - READ-STR : an Access Register read of x5 with aarpostincrement=1 completes
//                  with cmderr=0 (NOT cmderr=2 -- the behaviour change: the optional
//                  post-increment variant is now implemented). With abstractauto=1,
//                  successive data0 reads STREAM x5,x6,x7 as regno advances
//                  0x1005->0x1006->0x1007;
//     - WRITE-STR: an Access Register write of x5 with aarpostincrement=1 completes
//                  with cmderr=0; with abstractauto=1, successive data0 writes land
//                  in x5,x6,x7 in turn (regno advancing), verified by backdoor probe
//                  and by autoexec-off read-back;
//     - RESUME   : hart resumes, finishes its loop, and the debug-written x5/x6/x7
//                  values survive.
//
//   ORDERING PITFALL (read-stream): a data0 READ is itself the auto-exec trigger,
//   and whether that read returns the value latched by the previous execution or
//   the value refreshed by the replay it triggers is timing-ambiguous. So exactly
//   like debug_abstractauto, every ASSERTED read-stream value is observed with a
//   plain (autoexec-off) settle read AFTER the post-incrementing replay has landed;
//   the triggering read's own return is captured for info only. WRITE-stream has no
//   such ambiguity (a data0 write lands the value, then the replay consumes it), so
//   it is verified directly by backdoor probe + autoexec-off read-back.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
reg [31:0] cap;   // scratch for a captured (timing-ambiguous) triggering-read value

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0        = 7'h04;
localparam [6:0] DMI_DMCONTROL    = 7'h10;
localparam [6:0] DMI_DMSTATUS     = 7'h11;
localparam [6:0] DMI_ABSTRACTCS   = 7'h16;
localparam [6:0] DMI_COMMAND      = 7'h17;
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

// abstractauto: only bit0 (autoexecdata[0]) implemented
localparam [31:0] AUTO_DATA0 = 32'h00000001;

// Access Register command words (command[0x17], cmdtype=0)
//   [22:20] aarsize=2 (32-bit) -> 0x00200000 ; [19] aarpostincrement -> 0x00080000 ;
//   [17] transfer=1 -> 0x00020000 ; [16] write -> 0x00010000 ; [15:0] regno = 0x1000+gpr
//     x5 -> 0x1005 ; x6 -> 0x1006 ; x7 -> 0x1007
localparam [31:0] CMD_READ_X5         = 32'h00200000 | 32'h00020000 | 32'h00001005; // 0x00221005
localparam [31:0] CMD_READ_X6         = 32'h00200000 | 32'h00020000 | 32'h00001006; // 0x00221006
localparam [31:0] CMD_READ_X7         = 32'h00200000 | 32'h00020000 | 32'h00001007; // 0x00221007
localparam [31:0] CMD_READ_X5_POSTINC = CMD_READ_X5 | 32'h00080000;                 // 0x002A1005 (bit19)
localparam [31:0] CMD_WRITE_X5_POSTINC= 32'h00200000 | 32'h00080000 | 32'h00020000
                                      | 32'h00010000 | 32'h00001005;                 // 0x002B1005 (bit19)

// firmware-loaded read-stream sentinels
localparam [31:0] X5_SENTINEL = 32'h55555555;
localparam [31:0] X6_SENTINEL = 32'h66666666;
localparam [31:0] X7_SENTINEL = 32'h77777777;

// debugger-written write-stream values (distinct from the sentinels)
localparam [31:0] W5_VALUE = 32'hA5A5A5A5;
localparam [31:0] W6_VALUE = 32'hB6B6B6B6;
localparam [31:0] W7_VALUE = 32'hC7C7C7C7;

// Issue an abstract command via the command register and wait for busy clear; the
// final abstractcs (incl. cmderr) is left in dmi_readval. Used only while
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
    $display("|  DEBUG ACMD POSTINCR: aarpostincrement (bit 19) is SUPPORTED -      |");
    $display("|  post-increment + abstractauto streams consecutive GPRs (Debug 1.0) |");
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
    end else $display("PASS:  hart in Debug Mode (abstract GPR access permitted) %t ns", $time);

    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);   // clear any residual cmderr (W1C) before we start

    //========================================================================
    // PHASE A: NO-INCREMENT control - aarpostincrement=0 must NOT advance regno.
    //   Establish "last command" = read x6 (postincr=0), arm autoexec, then every
    //   replayed data0 read returns the SAME register. x6=0x66666666 is constant,
    //   so no read-trigger ambiguity: assert directly on each autoexec-on read.
    //   (A post-incrementing command here would instead walk x6,x7,... .)
    //========================================================================
    abs_run(CMD_READ_X6);                    // last command := read x6 (postincr=0)
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after read-x6 (postincr=0) (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);                      // autoexec still off: plain observe
    if (dmi_readval !== X6_SENTINEL) begin
        $display("ERROR: read x6 returned %h (expected %h) %t ns", dmi_readval, X6_SENTINEL, $time);
        error = error + 1;
    end else $display("PASS:  read x6 (postincr=0) returned sentinel %h %t ns", X6_SENTINEL, $time);

    dmi_write(DMI_ABSTRACTAUTO, AUTO_DATA0);  // arm autoexecdata0
    for (ii = 0; ii < 3; ii = ii + 1) begin
        dmi_read(DMI_DATA0);                  // auto-exec trigger: re-runs read x6 (no advance)
        cap = dmi_readval;
        ae_wait;
        if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
            $display("ERROR: cmderr=%0d on no-incr replay #%0d (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, ii, $time);
            error = error + 1;
        end
        // regno must NOT have advanced: every replay still reads x6.
        if (cap !== X6_SENTINEL) begin
            $display("ERROR: no-incr replay #%0d returned %h (expected constant %h; regno advanced with postincr=0!) %t ns", ii, cap, X6_SENTINEL, $time);
            error = error + 1;
        end else $display("PASS:  no-incr replay #%0d still reads x6=%h (regno frozen) %t ns", ii, X6_SENTINEL, $time);
    end
    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000); // disarm before next phase
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);     // clear residual cmderr (W1C)

    //========================================================================
    // PHASE B: READ-STREAM - aarpostincrement=1 read of x5, then abstractauto
    //   replays walk regno x5->x6->x7. HEADLINE: cmderr=0 on the bit19 command
    //   (this DM now IMPLEMENTS the optional variant; the previous contract was
    //   cmderr=2 "not supported"). Asserted values observed with autoexec-off
    //   settle reads AFTER each post-incrementing replay lands (ordering pitfall).
    //========================================================================
    abs_run(CMD_READ_X5_POSTINC);            // read x5 -> data0 ; regno post-incr x5->x6
    if (((dmi_readval & ACS_CMDERR) >> 8) !== 3'd0) begin
        $display("ERROR: cmderr=%0d after aarpostincrement=1 READ (expected 0; bit19 must be SUPPORTED now, not rejected with 2) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=0 on aarpostincrement=1 READ (post-increment supported) %t ns", $time);

    dmi_read(DMI_DATA0);                      // autoexec off: settle read #1 (regno unchanged)
    if (dmi_readval !== X5_SENTINEL) begin
        $display("ERROR: read-stream value #1 = %h (expected x5 %h) %t ns", dmi_readval, X5_SENTINEL, $time);
        error = error + 1;
    end else $display("PASS:  read-stream #1 = x5 %h %t ns", X5_SENTINEL, $time);

    // Replay #1: advance to x6. Arm autoexec, trigger via a data0 read (return is
    // timing-ambiguous -> captured for info only), then disarm and settle-read.
    dmi_write(DMI_ABSTRACTAUTO, AUTO_DATA0);
    dmi_read(DMI_DATA0);                      // <-- trigger: re-runs read regno=x6 ; data0<-x6, regno->x7
    cap = dmi_readval;
    ae_wait;
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after read-stream replay to x6 (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000);
    dmi_read(DMI_DATA0);                      // settle read #2 (autoexec off, no fire)
    if (dmi_readval !== X6_SENTINEL) begin
        $display("ERROR: read-stream value #2 = %h (expected x6 %h; regno did not advance 0x1005->0x1006) (trigger returned %h) %t ns", dmi_readval, X6_SENTINEL, cap, $time);
        error = error + 1;
    end else $display("PASS:  read-stream #2 = x6 %h (regno advanced 0x1005->0x1006) %t ns", X6_SENTINEL, $time);

    // Replay #2: advance to x7.
    dmi_write(DMI_ABSTRACTAUTO, AUTO_DATA0);
    dmi_read(DMI_DATA0);                      // <-- trigger: re-runs read regno=x7 ; data0<-x7, regno->x8
    cap = dmi_readval;
    ae_wait;
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after read-stream replay to x7 (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000);
    dmi_read(DMI_DATA0);                      // settle read #3 (autoexec off, no fire)
    if (dmi_readval !== X7_SENTINEL) begin
        $display("ERROR: read-stream value #3 = %h (expected x7 %h; regno did not advance 0x1006->0x1007) (trigger returned %h) %t ns", dmi_readval, X7_SENTINEL, cap, $time);
        error = error + 1;
    end else $display("PASS:  read-stream #3 = x7 %h (regno advanced 0x1006->0x1007) %t ns", X7_SENTINEL, $time);

    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);   // clear residual cmderr (W1C) before write phase

    //========================================================================
    // PHASE C: WRITE-STREAM - aarpostincrement=1 write of x5, then abstractauto
    //   replays walk regno x5->x6->x7. A data0 WRITE lands the value then the replay
    //   consumes it (no read-trigger ambiguity); verified by backdoor regfile probe
    //   and confirmed with autoexec-off read-backs.
    //========================================================================
    dmi_write(DMI_DATA0, W5_VALUE);          // autoexec off: plain data0 load, no fire
    abs_run(CMD_WRITE_X5_POSTINC);           // x5 <- data0 (W5) ; regno post-incr x5->x6
    if (((dmi_readval & ACS_CMDERR) >> 8) !== 3'd0) begin
        $display("ERROR: cmderr=%0d after aarpostincrement=1 WRITE (expected 0; bit19 supported) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  cmderr=0 on aarpostincrement=1 WRITE (post-increment supported) %t ns", $time);
    if (probes_cpu.x05 !== W5_VALUE) begin
        $display("ERROR: x5=%h after write-stream #1 (expected %h) %t ns", probes_cpu.x05, W5_VALUE, $time);
        error = error + 1;
    end else $display("PASS:  write-stream #1 landed x5=%h %t ns", W5_VALUE, $time);

    // Arm autoexec: a data0 WRITE now lands then replays the WRITE at the advancing regno.
    dmi_write(DMI_ABSTRACTAUTO, AUTO_DATA0);

    dmi_write(DMI_DATA0, W6_VALUE);          // <-- trigger: data0<-W6 then x6<-data0 ; regno x6->x7
    ae_wait;
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after write-stream to x6 (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    if (probes_cpu.x06 !== W6_VALUE) begin
        $display("ERROR: x6=%h after write-stream #2 (expected %h; regno did not advance 0x1005->0x1006) %t ns", probes_cpu.x06, W6_VALUE, $time);
        error = error + 1;
    end else $display("PASS:  write-stream #2 landed x6=%h (regno advanced 0x1005->0x1006) %t ns", W6_VALUE, $time);

    dmi_write(DMI_DATA0, W7_VALUE);          // <-- trigger: data0<-W7 then x7<-data0 ; regno x7->x8
    ae_wait;
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: cmderr=%0d after write-stream to x7 (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    if (probes_cpu.x07 !== W7_VALUE) begin
        $display("ERROR: x7=%h after write-stream #3 (expected %h; regno did not advance 0x1006->0x1007) %t ns", probes_cpu.x07, W7_VALUE, $time);
        error = error + 1;
    end else $display("PASS:  write-stream #3 landed x7=%h (regno advanced 0x1006->0x1007) %t ns", W7_VALUE, $time);

    // ORDERING: disarm autoexec BEFORE any verifying data0 access. After the x7
    // write the effective regno = x8 (the firmware loop counter) and the last
    // command is WRITE-postincr; a data0 access with autoexec still on would
    // clobber x8. Keep this disarm ahead of the read-backs below.
    dmi_write(DMI_ABSTRACTAUTO, 32'h00000000);

    // Autoexec-off read-backs confirm the streamed writes independently of the probe.
    abs_run(CMD_READ_X5);  dmi_read(DMI_DATA0);
    if (dmi_readval !== W5_VALUE) begin
        $display("ERROR: read-back x5=%h (expected %h) %t ns", dmi_readval, W5_VALUE, $time);
        error = error + 1;
    end else $display("PASS:  read-back confirms x5=%h %t ns", W5_VALUE, $time);
    abs_run(CMD_READ_X6);  dmi_read(DMI_DATA0);
    if (dmi_readval !== W6_VALUE) begin
        $display("ERROR: read-back x6=%h (expected %h) %t ns", dmi_readval, W6_VALUE, $time);
        error = error + 1;
    end else $display("PASS:  read-back confirms x6=%h %t ns", W6_VALUE, $time);
    abs_run(CMD_READ_X7);  dmi_read(DMI_DATA0);
    if (dmi_readval !== W7_VALUE) begin
        $display("ERROR: read-back x7=%h (expected %h) %t ns", dmi_readval, W7_VALUE, $time);
        error = error + 1;
    end else $display("PASS:  read-back confirms x7=%h %t ns", W7_VALUE, $time);

    //========================================================================
    // RESUME + final check
    //========================================================================
    dmi_write(DMI_ABSTRACTCS, ACS_CMDERR);                 // clear any residual cmderr (W1C)
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

    // --- firmware must complete the loop and reach the end on its own ---
    @(probes_cpu.x31==32'hdeadbeef);
    // The debug-written write-stream values must survive resume: the firmware only
    // set x5/x6/x7 once (before the spin loop) and never touches them again.
    check_cpu_reg(5, W5_VALUE);
    check_cpu_reg(6, W6_VALUE);
    check_cpu_reg(7, W7_VALUE);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

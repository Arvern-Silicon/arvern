//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_hit0
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdtrig mcontrol6 hit0 STATUS bit (Debug Spec 1.0, MXLEN=32)
//   Companion testbench for debug_trigger_hit0.s. Proves the mcontrol6.hit0 bit
//   (tdata1 bit 22) reports WHICH trigger fired and entered Debug Mode, and that
//   the debugger can clear it while leaving the trigger configured.
//
//   The .v is the debugger: it halts the spinning hart over DMI, arms the
//   action=1 (enter-Debug) triggers via the abstract Access Register (action=1
//   requires dmode=1 -> debugger-only), resumes, and after the trigger
//   AUTO-ENTERS Debug Mode inspects tdata1.hit0 (bit 22) per trigger.
//
//   Assertion discipline (mirrors debug_triggers): expected tdata1 words are NOT
//   hardcoded -- the ARMED readback is captured and every check is asserted
//   RELATIVE to it. So `armed0`/`armed1`/`armed_p2` are the WARL-massaged values
//   the core actually returns; on fire we assert hit0 flipped to 1 and NOTHING
//   ELSE changed ((v & ~HIT0) == armed), and the non-firing trigger is bit-for-
//   bit unchanged. Clearing writes the captured armed word back (bit22 already 0)
//   and asserts full equality -> hit0 cleared AND config intact in one shot.
//
//   PHASE 1 (EXECUTE, the priority): trigger 0 @ &trig_tgt_A, trigger 1 @
//     &trig_tgt_B, both armed action=1. Hart reaches A first -> only trigger 0
//     fires. KEY: trigger0.hit0==1, trigger1.hit0==0. Clear + config-intact.
//     BOTH triggers disarmed before resume (trigger 1 would re-enter Debug at B).
//   PHASE 2 (STORE watchpoint): trigger 0 armed as a store watchpoint on
//     &P2_DATA; on fire trigger0.hit0==1, cleared, config intact.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

// Debugger-driven test: many sequential DMI round-trips (arm, fire, read-back,
// clear, disarm) across two halt/resume/fire cycles. Under stacked wait-state
// variants the cumulative cycle count overruns the default watchdog -> opt into
// the long tier (same as the other cycle-heavy trigger-firing tests).
`define VERY_LONG_TIMEOUT

`define SPAD(byte_off)  ((byte_off)/4)

reg [31:0] dcsr_val, dpc_val, addr_a;
reg [31:0] armed0, armed1, armed_p2, v;

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
localparam [31:0] DMS_ALLHALTED  = 32'h00000200;  // [9]

// abstractcs field masks
localparam [31:0] ACS_BUSY   = 32'h00001000;       // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700;       // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0, aarsize=2, transfer=1)
//   base = 0x00220000 ; +0x00010000 sets the write bit ; low 16 = regno
//   (CSR regno = 12-bit CSR address ; GPR regno = 0x1000 + n)
localparam [31:0] CMD_WR_TSELECT = 32'h00230000 | 32'h000007a0;
localparam [31:0] CMD_WR_TDATA1  = 32'h00230000 | 32'h000007a1;
localparam [31:0] CMD_RD_TDATA1  = 32'h00220000 | 32'h000007a1;
localparam [31:0] CMD_RD_DCSR    = 32'h00220000 | 32'h000007b0;
localparam [31:0] CMD_RD_DPC     = 32'h00220000 | 32'h000007b1;
localparam [31:0] CMD_RD_X6      = 32'h00220000 | 32'h00001006;

// tdata1 (mcontrol6) status/config bits under test
localparam [31:0] HIT0 = 32'h00400000;   // [22] hit0 (the firing-trigger flag)
localparam [31:0] HIT1 = 32'h02000000;   // [25] hit1 (unimplemented -> stays 0)

// Debugger arming words (action=1 REQUIRES dmode=1):
//   EXECUTE : type6 | dmode | action=1 | m | execute | match=0
//   STORE   : type6 | dmode | action=1 | m | store   | match=0 (size=any)
localparam [31:0] ARM_EXEC_TDATA1  = 32'h68001044;
localparam [31:0] ARM_STORE_TDATA1 = 32'h68001042;

// dcsr.cause field (bits[8:6]); cause==2 (trigger) -> field value 0x80
localparam [31:0] DCSR_CAUSE = 32'h000001C0;
localparam [31:0] DCSR_CAUSE_TRIGGER = 32'h00000080;

reg [31:0] acmd_rdata;

// Issue an abstract command, wait busy clear; abstractcs left in dmi_readval.
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

// Abstract CSR/GPR write of `val` (expect cmderr==0).
task abs_wr;
   input [31:0] cmd;
   input [31:0] val;
   begin
      dmi_write(DMI_DATA0, val);
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after abstract write (cmd=%h val=%h) %t ns",
                  (dmi_readval & ACS_CMDERR) >> 8, cmd, val, $time);
         error = error + 1;
      end
   end
endtask

// Abstract CSR/GPR read (expect cmderr==0); data -> acmd_rdata.
task abs_rd;
   input [31:0] cmd;
   begin
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after abstract read (cmd=%h) %t ns",
                  (dmi_readval & ACS_CMDERR) >> 8, cmd, $time);
         error = error + 1;
      end
      dmi_read(DMI_DATA0);
      acmd_rdata = dmi_readval;
   end
endtask

// Select trigger `idx` then read its tdata1 into `v` (tselect discipline).
task read_trig_tdata1;
   input [31:0] idx;
   begin
      abs_wr(CMD_WR_TSELECT, idx);
      abs_rd(CMD_RD_TDATA1);
      v = acmd_rdata;
   end
endtask

// After a fire: poll dmstatus.allhalted (auto-entry to Debug Mode), assert
// Debug Mode + dcsr.cause==2 (trigger).
task expect_fire_entry;
   begin
      dm_resume;
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200000)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: trigger did NOT enter Debug Mode (allhalted=0 after %0d polls) %t ns", to, $time);
         error = error + 1;
      end else $display("PASS:  trigger entered Debug Mode (allhalted=1, %0d polls) %t ns", to, $time);
      if (dbg_debug_mode !== 1'b1) begin
         $display("ERROR: dbg_debug_mode not asserted after trigger fire %t ns", $time);
         error = error + 1;
      end else $display("PASS:  hart in Debug Mode after trigger fire %t ns", $time);
      abs_rd(CMD_RD_DCSR);
      dcsr_val = acmd_rdata;
      if ((dcsr_val & DCSR_CAUSE) !== DCSR_CAUSE_TRIGGER) begin
         $display("ERROR: dcsr.cause=%0d (expected 2 trigger) dcsr=%h %t ns",
                  (dcsr_val & DCSR_CAUSE) >> 6, dcsr_val, $time);
         error = error + 1;
      end else $display("PASS:  dcsr.cause=2 (trigger) dcsr=%h %t ns", dcsr_val, $time);
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

    // No M-mode trap is expected in this test (all triggers are action=1 =
    // enter-Debug, never action=0 breakpoints). Keep the exception monitor armed
    // (any unexpected trap fails) and just silence random IRQs.
    random_irq_enable = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG TRIGGER HIT0: Sdtrig mcontrol6 hit0 status bit (which fired) |");
    $display(" ====================================================================");

    //========================================================================
    // PHASE 1 : two EXECUTE triggers armed; only trigger 0 (@ &trig_tgt_A) fires.
    //========================================================================
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware pre-loaded both execute triggers, spinning (x31=0x11111111) %t ns", $time);

    // Bring the DM out of reset and halt the spinning hart.
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart halted in Debug Mode (abstract arming permitted) %t ns", $time);

    // Capture &trig_tgt_A (firmware stashed it in x6) for the dpc compare.
    abs_rd(CMD_RD_X6);
    addr_a = acmd_rdata;
    $display("INFO:  &trig_tgt_A (x6) = %h %t ns", addr_a, $time);

    //--- Arm trigger 0 (execute @ A); capture the WARL-massaged armed word -----
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, ARM_EXEC_TDATA1);
    abs_rd(CMD_RD_TDATA1);
    armed0 = acmd_rdata;
    if (armed0[31:28] !== 4'h6) begin
        $display("ERROR: trigger 0 type=%h (expected 6 mcontrol6) tdata1=%h %t ns", armed0[31:28], armed0, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 armed (type=6, tdata1=%h) %t ns", armed0, $time);
    if ((armed0 & HIT0) !== 32'h0) begin
        $display("ERROR: trigger 0 hit0 NOT clear right after arming (tdata1=%h) %t ns", armed0, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 hit0=0 initially (armed, not yet fired) %t ns", $time);
    if ((armed0 & HIT1) !== 32'h0) begin
        $display("ERROR: trigger 0 hit1 (bit25) set -- expected unimplemented=0 (tdata1=%h) %t ns", armed0, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 hit1=0 (unimplemented) %t ns", $time);

    //--- Arm trigger 1 (execute @ B); capture its armed word -------------------
    abs_wr(CMD_WR_TSELECT, 32'h1);
    abs_wr(CMD_WR_TDATA1, ARM_EXEC_TDATA1);
    abs_rd(CMD_RD_TDATA1);
    armed1 = acmd_rdata;
    if ((armed1 & HIT0) !== 32'h0) begin
        $display("ERROR: trigger 1 hit0 NOT clear right after arming (tdata1=%h) %t ns", armed1, $time);
        error = error + 1;
    end else $display("PASS:  trigger 1 hit0=0 initially (armed, will NOT fire) %t ns", $time);
    if ((armed1 & HIT1) !== 32'h0) begin
        $display("ERROR: trigger 1 hit1 (bit25) set -- expected unimplemented=0 (tdata1=%h) %t ns", armed1, $time);
        error = error + 1;
    end else $display("PASS:  trigger 1 hit1=0 (unimplemented) %t ns", $time);

    //--- Resume; hart reaches A first -> only trigger 0 fires + enters Debug ----
    expect_fire_entry;

    // dpc must point AT the matching (NOT executed) instruction == &trig_tgt_A:
    // confirms it is trigger 0 (@ A), not trigger 1 (@ B), that fired.
    abs_rd(CMD_RD_DPC);
    dpc_val = acmd_rdata;
    if (dpc_val !== addr_a) begin
        $display("ERROR: dpc=%h != &trig_tgt_A=%h (wrong trigger fired?) %t ns", dpc_val, addr_a, $time);
        error = error + 1;
    end else $display("PASS:  dpc=%h == &trig_tgt_A (trigger 0 fired) %t ns", dpc_val, $time);

    //--- KEY CHECK 1: trigger 0 (the one that fired) has hit0==1 ----------------
    read_trig_tdata1(32'h0);
    if ((v & HIT0) === 32'h0) begin
        $display("ERROR: trigger 0 FIRED but hit0=0 (tdata1=%h) -- hit0 not set on fire %t ns", v, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 hit0=1 (the firing trigger is flagged) tdata1=%h %t ns", v, $time);
    if ((v & ~HIT0) !== armed0) begin
        $display("ERROR: trigger 0 fire changed more than hit0 (now %h, armed %h, masked %h) %t ns",
                 v, armed0, (v & ~HIT0), $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 fire changed ONLY hit0 (config intact) %t ns", $time);
    if ((v & HIT1) !== 32'h0) begin
        $display("ERROR: trigger 0 hit1 (bit25) set after fire (tdata1=%h) %t ns", v, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 hit1=0 after fire (unimplemented) %t ns", $time);

    //--- KEY CHECK 2: trigger 1 (did NOT fire) still has hit0==0 ----------------
    read_trig_tdata1(32'h1);
    if ((v & HIT0) !== 32'h0) begin
        $display("ERROR: trigger 1 did NOT fire but hit0=1 (tdata1=%h) -- hit0 not per-trigger %t ns", v, $time);
        error = error + 1;
    end else $display("PASS:  trigger 1 hit0=0 (only the firing trigger sets its hit0) %t ns", $time);
    if (v !== armed1) begin
        $display("ERROR: trigger 1 tdata1 changed by trigger 0 firing (now %h, armed %h) %t ns", v, armed1, $time);
        error = error + 1;
    end else $display("PASS:  trigger 1 tdata1 fully unchanged (%h) %t ns", v, $time);

    //--- KEY CHECK 3: debugger clears hit0; config must survive -----------------
    // Writing the captured armed word back (bit22 already 0) clears hit0 while
    // keeping type/dmode/action/match/execute -> equality proves BOTH at once.
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, armed0);
    abs_rd(CMD_RD_TDATA1);
    v = acmd_rdata;
    if ((v & HIT0) !== 32'h0) begin
        $display("ERROR: hit0 still set after debugger cleared it (tdata1=%h) %t ns", v, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 hit0 cleared by debugger write (tdata1=%h) %t ns", v, $time);
    if (v !== armed0) begin
        $display("ERROR: clearing hit0 disturbed trigger 0 config (now %h, armed %h) %t ns", v, armed0, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 still configured after hit0 clear (type/action/match/execute intact) %t ns", $time);

    //--- Disarm BOTH triggers before resume (trigger 1 armed action=1 would ----
    //    re-enter Debug at B with no debugger servicing it -> hang) -------------
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, 32'h0);
    abs_wr(CMD_WR_TSELECT, 32'h1);
    abs_wr(CMD_WR_TDATA1, 32'h0);
    $display("PASS:  both execute triggers disarmed (dmode cleared) %t ns", $time);
    dm_resume;

    //========================================================================
    // PHASE 2 : STORE data-address watchpoint hit0 (load/store path).
    //========================================================================
    @(probes_cpu.x31==32'h22222222);
    $display("Firmware pre-loaded the store watchpoint, spinning (x31=0x22222222) %t ns", $time);

    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 (Phase 2) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart halted in Debug Mode (Phase 2) %t ns", $time);

    //--- Arm trigger 0 as a store watchpoint (action=1); capture armed word -----
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, ARM_STORE_TDATA1);
    abs_rd(CMD_RD_TDATA1);
    armed_p2 = acmd_rdata;
    if ((armed_p2 & HIT0) !== 32'h0) begin
        $display("ERROR: store watchpoint hit0 NOT clear right after arming (tdata1=%h) %t ns", armed_p2, $time);
        error = error + 1;
    end else $display("PASS:  store watchpoint hit0=0 initially (tdata1=%h) %t ns", armed_p2, $time);

    //--- Resume; the store watchpoint fires + enters Debug ---------------------
    expect_fire_entry;

    //--- KEY: store watchpoint hit0==1 -----------------------------------------
    read_trig_tdata1(32'h0);
    if ((v & HIT0) === 32'h0) begin
        $display("ERROR: store watchpoint FIRED but hit0=0 (tdata1=%h) %t ns", v, $time);
        error = error + 1;
    end else $display("PASS:  store watchpoint hit0=1 (load/store path flags hit0) tdata1=%h %t ns", v, $time);
    if ((v & ~HIT0) !== armed_p2) begin
        $display("ERROR: store watchpoint fire changed more than hit0 (now %h, armed %h) %t ns", v, armed_p2, $time);
        error = error + 1;
    end else $display("PASS:  store watchpoint fire changed ONLY hit0 (config intact) %t ns", $time);

    //--- Clear hit0 + config intact --------------------------------------------
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, armed_p2);
    abs_rd(CMD_RD_TDATA1);
    v = acmd_rdata;
    if ((v & HIT0) !== 32'h0) begin
        $display("ERROR: store watchpoint hit0 still set after clear (tdata1=%h) %t ns", v, $time);
        error = error + 1;
    end else $display("PASS:  store watchpoint hit0 cleared (tdata1=%h) %t ns", v, $time);
    if (v !== armed_p2) begin
        $display("ERROR: clearing hit0 disturbed store watchpoint config (now %h, armed %h) %t ns", v, armed_p2, $time);
        error = error + 1;
    end else $display("PASS:  store watchpoint still configured after hit0 clear %t ns", $time);

    //--- Disarm + resume; the sw then executes ---------------------------------
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, 32'h0);
    dm_resume;

    //========================================================================
    // Firmware finishes; confirm both firing instructions eventually executed.
    //========================================================================
    @(probes_cpu.x31==32'hdeadbeef);
    repeat(10) @(posedge free_clk);

    check_mem_value(`SPAD(32'h40), 32'h000000AA);   // A x5 final (executed after disarm)
    check_mem_value(`SPAD(32'h44), 32'h2B2B2B2B);   // P2_DATA final store (after disarm)

    //========================================================================
    // END OF TEST
    //========================================================================
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

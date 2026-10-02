//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_triggers
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdtrig trigger-CSR register-file conformance (Debug Spec 1.0)
//   Companion testbench for debug_triggers.s. Tests the trigger CSR FILE only
//   (storage / WARL / access rules); triggers do NOT fire yet (no match logic).
//
//   TWO access paths, both exercised:
//     - HART-SIDE: the firmware drives M-mode csrr/csrw of the trigger CSRs and
//       writes every readback into an SRAM scratchpad. This .v inspects that
//       scratchpad after the firmware reaches 0xdeadbeef (checks A,B,C,D,F,G,H).
//     - DEBUGGER-SIDE: this .v halts the hart and uses the Debug Module abstract
//       "Access Register" command (regno = the 12-bit CSR address directly) to
//       read/write the trigger CSRs while frozen (tselect/tdata1/tdata2/tinfo
//       round-trips), and runs the dmode write-protection interlock (check E)
//       across TWO halts straddling a resume.
//
//   Check E (dmode write-protection), end-to-end:
//     halt#1 -> debugger sets dmode=1 on trigger 0 (+ a tdata2 sentinel) and
//               captures the WARL-massaged readback.
//     resume -> firmware (M-mode) attempts to overwrite trigger 0; the writes
//               must be DROPPED (no trap, storage unchanged) -> scratchpad 0x40/0x44.
//     halt#2 -> debugger confirms trigger 0 is STILL the locked value (M writes
//               were dropped), then proves the debugger CAN still modify it.
//
//   NOTE on error_on_exception: set to 0 at the TOP of the initial block (before
//   the first sync). Check H deliberately raises an illegal-instruction trap
//   during early firmware setup, well before any handshake; disarming the monitor
//   up front avoids a false ERROR. The firmware trap counter (scratchpad 0x3C,
//   asserted == 1) is the recovered safety net: any UNEXPECTED extra trap (e.g. a
//   dmode-locked csrw wrongly faulting) makes the count != 1 and fails the test.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
integer trig_nr;

// Comprehensive dual-path (hart-side csrr/csrw + debugger-side abstract Access
// Register) A-H conformance walk does many sequential DMI round-trips; under
// stacked wait-state variants (-rwsrom+-rwsram+-rwsper+-rsalu) the cumulative
// cycle count overruns the default testbench watchdog. Opt into the long tier
// (same as the cycle-heavy inst_m_div / inst_m_mul tests).
`define VERY_LONG_TIMEOUT

`define SPAD(byte_off)  ((byte_off)/4)   // parens: callers pass expressions, e.g. 0x48 + ii*16

// Scratchpad word reader (a temp avoids part-selecting a memory element inline).
reg [31:0] mval;
reg [31:0] clampv;
reg [31:0] locked_tdata1, locked_tdata2;
reg [31:0] acmd_rdata;

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
localparam [31:0] DMS_ALLHALTED  = 32'h00000200; // [9]
localparam [31:0] DMS_ALLRUNNING = 32'h00000800; // [11]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0, aarsize=2, transfer=1)
//   regno = the 12-bit CSR address directly; +0x00010000 sets the write bit.
localparam [31:0] CMD_RD_TSELECT = 32'h00220000 | 32'h000007a0; // 0x002207a0
localparam [31:0] CMD_WR_TSELECT = 32'h00230000 | 32'h000007a0; // 0x002307a0
localparam [31:0] CMD_RD_TDATA1  = 32'h00220000 | 32'h000007a1; // 0x002207a1
localparam [31:0] CMD_WR_TDATA1  = 32'h00230000 | 32'h000007a1; // 0x002307a1
localparam [31:0] CMD_RD_TDATA2  = 32'h00220000 | 32'h000007a2; // 0x002207a2
localparam [31:0] CMD_WR_TDATA2  = 32'h00230000 | 32'h000007a2; // 0x002307a2
localparam [31:0] CMD_RD_TINFO   = 32'h00220000 | 32'h000007a4; // 0x002207a4

// tdata1 (mcontrol6) sentinels driven by the debugger
localparam [31:0] DBG_TDATA1_DMODE = 32'h68000041; // type6 | dmode | m | load
localparam [31:0] DBG_TDATA1_CLEAN = 32'h60000001; // type6 | load (dmode=0) -- leaves it clean
localparam [31:0] DBG_TDATA2_RT    = 32'hA5A50FF0; // plain 32-bit round-trip value
localparam [31:0] E_SENTINEL_DBG   = 32'h5EC0DE00; // locked tdata2 value (halt#1)
localparam [31:0] E_SENTINEL_DBG2  = 32'h5EC0DE11; // re-write proving debugger can still modify

// firmware-side expected per-trigger tdata2 values (mirror debug_triggers.s)
localparam [31:0] TRIG0_T2 = 32'h8000ABC0;
localparam [31:0] TRIG1_T2 = 32'hCAFE0008;

localparam [31:0] X18_SENTINEL = 32'hA5A5A5A5;

//---------------------------------------------------------------------------
// Abstract-command helpers (issue + wait busy clear; abstractcs left in
// dmi_readval). abs_rd additionally captures data0 into acmd_rdata.
//---------------------------------------------------------------------------
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

task abs_wr;                       // abstract CSR write of `val`; expect cmderr=0
   input [31:0] cmd;
   input [31:0] val;
   begin
      dmi_write(DMI_DATA0, val);
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after abstract CSR write (cmd=%h val=%h) %t ns",
                  (dmi_readval & ACS_CMDERR) >> 8, cmd, val, $time);
         error = error + 1;
      end
   end
endtask

task abs_rd;                       // abstract CSR read; expect cmderr=0; data -> acmd_rdata
   input [31:0] cmd;
   begin
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after abstract CSR read (cmd=%h) %t ns",
                  (dmi_readval & ACS_CMDERR) >> 8, cmd, $time);
         error = error + 1;
      end
      dmi_read(DMI_DATA0);
      acmd_rdata = dmi_readval;
   end
endtask

task do_halt;                      // halt the hart, poll allhalted, assert Debug Mode
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: hart did not halt (allhalted=0) %t ns", $time);
         error = error + 1;
      end else $display("PASS:  hart halted (allhalted=1, %0d polls) %t ns", to, $time);
      if (dbg_debug_mode !== 1'b1) begin
         $display("ERROR: dbg_debug_mode not asserted while halted %t ns", $time);
         error = error + 1;
      end else $display("PASS:  hart in Debug Mode (abstract trigger-CSR access permitted) %t ns", $time);
   end
endtask

task do_resume;                    // drop haltreq, resumereq, poll allrunning
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);
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

    // Check H deliberately traps (csrr dcsr) during early firmware setup, before
    // any sync handshake. Disarm the exception->error monitor up front; the
    // firmware trap counter (== 1) is the recovered safety net.
    error_on_exception = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG TRIGGERS: Sdtrig trigger-CSR file conformance (hart + DM)    |");
    $display(" ====================================================================");

    //========================================================================
    // Phase 1: wait for the firmware to finish all hart-side checks (A-H) and
    // start spinning, then halt for the debugger-side round-trips + E setup.
    //========================================================================
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware finished hart-side trigger-CSR checks, spinning (x31=0x11111111) %t ns", $time);

    do_halt;

    //--- DEBUGGER-SIDE round-trips: tselect ---------------------------------
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_rd(CMD_RD_TSELECT);
    if (acmd_rdata !== 32'h0) begin
        $display("ERROR: debugger tselect=0 read back %h (expected 0) %t ns", acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  debugger tselect=0 round-trip %t ns", $time);

    abs_wr(CMD_WR_TSELECT, 32'h1);
    abs_rd(CMD_RD_TSELECT);
    if (acmd_rdata !== 32'h1) begin
        $display("ERROR: debugger tselect=1 read back %h (expected 1; >=2 triggers?) %t ns", acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  debugger tselect=1 round-trip %t ns", $time);

    //--- DEBUGGER-SIDE round-trips: tdata2 (clean 32-bit) on trigger 0 -------
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA2, DBG_TDATA2_RT);
    abs_rd(CMD_RD_TDATA2);
    if (acmd_rdata !== DBG_TDATA2_RT) begin
        $display("ERROR: debugger tdata2 round-trip read %h (expected %h) %t ns", acmd_rdata, DBG_TDATA2_RT, $time);
        error = error + 1;
    end else $display("PASS:  debugger tdata2 round-trip (%h) %t ns", DBG_TDATA2_RT, $time);

    //--- DEBUGGER-SIDE round-trips: tdata1 (debugger MAY set dmode=1) --------
    abs_wr(CMD_WR_TDATA1, DBG_TDATA1_DMODE);
    abs_rd(CMD_RD_TDATA1);
    if ((acmd_rdata[31:28] !== 4'h6) && (acmd_rdata[31:28] !== 4'h0)) begin
        $display("ERROR: debugger tdata1 type=%h (expected 6 or 0) %t ns", acmd_rdata[31:28], $time);
        error = error + 1;
    end else $display("PASS:  debugger tdata1 type=%h (supported) %t ns", acmd_rdata[31:28], $time);
    if (acmd_rdata[27] !== 1'b1) begin
        $display("ERROR: debugger could not set tdata1.dmode=1 (readback %h) %t ns", acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  debugger set tdata1.dmode=1 (Debug-Mode write) %t ns", $time);

    //--- DEBUGGER-SIDE: tinfo read (bit 6 = mcontrol6 supported) -------------
    abs_rd(CMD_RD_TINFO);
    if (acmd_rdata[6] !== 1'b1) begin
        $display("ERROR: debugger tinfo bit6 not set (readback %h) %t ns", acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  debugger tinfo bit6 set (mcontrol6 supported, %h) %t ns", acmd_rdata, $time);

    //--- CHECK E setup: LOCK trigger 0 with dmode=1 + a tdata2 sentinel ------
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, DBG_TDATA1_DMODE);
    abs_rd(CMD_RD_TDATA1);
    locked_tdata1 = acmd_rdata;                     // capture WARL-massaged value
    if (locked_tdata1[27] !== 1'b1) begin
        $display("ERROR: trigger 0 dmode not latched before lock (%h) %t ns", locked_tdata1, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 locked (dmode=1, tdata1=%h) %t ns", locked_tdata1, $time);
    abs_wr(CMD_WR_TDATA2, E_SENTINEL_DBG);
    abs_rd(CMD_RD_TDATA2);
    locked_tdata2 = acmd_rdata;
    if (locked_tdata2 !== E_SENTINEL_DBG) begin
        $display("ERROR: trigger 0 tdata2 lock read %h (expected %h) %t ns", locked_tdata2, E_SENTINEL_DBG, $time);
        error = error + 1;
    end else $display("PASS:  trigger 0 tdata2 locked = %h %t ns", E_SENTINEL_DBG, $time);

    //--- resume: firmware now attempts (and must DROP) M-mode writes ---------
    do_resume;

    //========================================================================
    // Phase 2: firmware ran its dropped-write leg; re-halt and confirm the
    // M-mode writes were ignored, then prove the debugger can still modify it.
    //========================================================================
    @(probes_cpu.x31==32'h22222222);
    $display("Firmware finished dropped-write leg, spinning (x31=0x22222222) %t ns", $time);

    do_halt;

    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_rd(CMD_RD_TDATA1);
    if (acmd_rdata !== locked_tdata1) begin
        $display("ERROR: M-mode write reached dmode-locked tdata1 (now %h, locked %h) %t ns", acmd_rdata, locked_tdata1, $time);
        error = error + 1;
    end else $display("PASS:  dmode-locked tdata1 unchanged by M-mode write (%h) %t ns", acmd_rdata, $time);
    abs_rd(CMD_RD_TDATA2);
    if (acmd_rdata !== locked_tdata2) begin
        $display("ERROR: M-mode write reached dmode-locked tdata2 (now %h, locked %h) %t ns", acmd_rdata, locked_tdata2, $time);
        error = error + 1;
    end else $display("PASS:  dmode-locked tdata2 unchanged by M-mode write (%h) %t ns", acmd_rdata, $time);

    // Debugger CAN still modify the dmode-locked trigger.
    abs_wr(CMD_WR_TDATA2, E_SENTINEL_DBG2);
    abs_rd(CMD_RD_TDATA2);
    if (acmd_rdata !== E_SENTINEL_DBG2) begin
        $display("ERROR: debugger could not modify dmode-locked tdata2 (now %h, expected %h) %t ns", acmd_rdata, E_SENTINEL_DBG2, $time);
        error = error + 1;
    end else $display("PASS:  debugger modified dmode-locked tdata2 -> %h %t ns", E_SENTINEL_DBG2, $time);

    // Leave trigger 0 clean (dmode back to 0).
    abs_wr(CMD_WR_TDATA1, DBG_TDATA1_CLEAN);

    do_resume;

    //========================================================================
    // Phase 3: firmware finishes; inspect the hart-side scratchpad (A-H + E).
    //========================================================================
    random_irq_enable = 0;
    @(probes_cpu.x31==32'hdeadbeef);
    repeat(10) @(posedge free_clk);

    // GPR sentinel must have survived every abstract access.
    check_cpu_reg(18, X18_SENTINEL);

    //--- A: tselect round-trip + WARL clamp ---------------------------------
    check_mem_value(`SPAD(32'h00), 32'h00000000);   // tselect=0 -> 0
    check_mem_value(`SPAD(32'h04), 32'h00000001);   // tselect=1 -> 1 (>=2 triggers)

    clampv = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
    if (clampv === 32'h000000FF) begin
        $display("ERROR: A clamp: tselect=0xFF read back 0xFF (not clamped) %t ns", $time);
        error = error + 1;
    end else if (clampv >= 32'h00000008) begin
        $display("ERROR: A clamp: tselect=0xFF read back %h (not a legal index < 8) %t ns", clampv, $time);
        error = error + 1;
    end else $display("PASS:  A clamp: tselect=0xFF WARL-clamped to legal index %0d %t ns", clampv, $time);

    mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
    if (mval !== clampv) begin
        $display("ERROR: A clamp idempotency: re-write of %h read back %h %t ns", clampv, mval, $time);
        error = error + 1;
    end else $display("PASS:  A clamp idempotency: clamped index %0d is a legal (idempotent) index %t ns", clampv, $time);

    //--- B: per-trigger storage independence (tdata2 = clean evidence) -------
    check_mem_value(`SPAD(32'h14), TRIG0_T2);       // trig0 tdata2
    check_mem_value(`SPAD(32'h1C), TRIG1_T2);       // trig1 tdata2 (distinct)
    check_mem_value(`SPAD(32'h24), TRIG0_T2);       // trig0 tdata2 re-read (independent)

    // Secondary: trig0 tdata1 stable across the trig1 writes, and the two
    // triggers actually hold different tdata1 (proves separate storage).
    mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
    clampv = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)]; // reuse clampv as temp
    if (mval !== clampv) begin
        $display("ERROR: B: trig0 tdata1 changed after trig1 writes (%h -> %h) %t ns", mval, clampv, $time);
        error = error + 1;
    end else $display("PASS:  B: trig0 tdata1 stable across trig1 writes (%h) %t ns", mval, $time);
    clampv = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)]; // trig1 tdata1
    if (mval === clampv) begin
        $display("ERROR: B: trig0 and trig1 tdata1 identical (%h) -- not independent storage %t ns", mval, $time);
        error = error + 1;
    end else $display("PASS:  B: trig0 (%h) and trig1 (%h) tdata1 are independent %t ns", mval, clampv, $time);

    //--- C: tdata1.type WARL (type=0xF -> 6 or 0, never 0xF) -----------------
    mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];
    if ((mval[31:28] !== 4'h6) && (mval[31:28] !== 4'h0)) begin
        $display("ERROR: C: tdata1.type WARL: wrote 0xF, read type=%h (expected 6 or 0) %t ns", mval[31:28], $time);
        error = error + 1;
    end else $display("PASS:  C: tdata1.type WARL: wrote 0xF -> read supported type %h %t ns", mval[31:28], $time);

    //--- D: WARL dmode=0 & action=1 prevented -------------------------------
    mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)];
    if ((mval[27] === 1'b0) && (mval[15:12] === 4'h1)) begin
        $display("ERROR: D: illegal combo latched: dmode=0 & action=1 (tdata1=%h) %t ns", mval, $time);
        error = error + 1;
    end else $display("PASS:  D: dmode=0 & action=1 prevented (tdata1=%h, dmode=%b action=%h) %t ns", mval, mval[27], mval[15:12], $time);

    //--- F: tinfo bit 6 set --------------------------------------------------
    mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];
    if (mval[6] !== 1'b1) begin
        $display("ERROR: F: tinfo bit6 not set (mcontrol6 should be supported) tinfo=%h %t ns", mval, $time);
        error = error + 1;
    end else $display("PASS:  F: tinfo bit6 set (mcontrol6 supported) tinfo=%h %t ns", mval, $time);

    //--- G: tdata3 RAZ/WI ----------------------------------------------------
    check_mem_value(`SPAD(32'h34), 32'h00000000);

    //--- H: D-mode-only CSR isolation guard ---------------------------------
    check_mem_value(`SPAD(32'h38), 32'h00000002);   // mcause = 2 (illegal instruction)
    check_mem_value(`SPAD(32'h3C), 32'h00000001);   // exactly one trap (the dcsr csrr)

    //--- E (firmware leg): dmode-locked M-mode writes were dropped ----------
    mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)];
    if (mval !== locked_tdata1) begin
        $display("ERROR: E: firmware M-mode write changed dmode-locked tdata1 (now %h, locked %h) %t ns", mval, locked_tdata1, $time);
        error = error + 1;
    end else $display("PASS:  E: dmode-locked tdata1 survived firmware M-mode write (%h) %t ns", mval, $time);
    check_mem_value(`SPAD(32'h44), E_SENTINEL_DBG); // tdata2 unchanged by firmware

    // G: the firmware discovers how many triggers this build implements and
    // sweeps slots 1..NR-1, so this section follows DM_TRIGGER_NR automatically.
    trig_nr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)];
    $display("");
    $display("--- section G: %0d trigger(s) implemented ---", trig_nr);
    if (trig_nr < 2 || trig_nr > 8)
       begin
          $display("ERROR: implausible trigger count %0d read from the scratchpad %t ns", trig_nr, $time);
          error = error + 1;
       end
    else
       for (ii = 1; ii < trig_nr; ii = ii + 1)
          begin
             check_mem_value(`SPAD(32'h4C + (ii-1)*16 +  0), 32'hAAAAAAAA);
             // mcontrol6.s/u (bits 4:3) are WARL 0 when the hart has no S/U-mode (Debug 1.0)
             check_mem_value(`SPAD(32'h4C + (ii-1)*16 +  4), SU_MODE_EN ? 32'h600100DF : 32'h600100C7);
             check_mem_value(`SPAD(32'h4C + (ii-1)*16 +  8), 32'h55555555);
             check_mem_value(`SPAD(32'h4C + (ii-1)*16 + 12), 32'h60020000);
          end

    //========================================================================
    // END OF TEST
    //========================================================================
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

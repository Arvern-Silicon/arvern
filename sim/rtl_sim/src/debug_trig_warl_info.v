//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trig_warl_info
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdtrig tinfo value + mcontrol6 chain-bit WARL (Debug Spec 1.0)
//   Drives the hclk-domain DMI bus exposed at the arvern boundary (no DTM) via
//   the dmi_write/dmi_read testbench helpers. Halts the spinning hart and uses
//   the DM abstract "Access Register" command with regno = the 12-bit CSR
//   address directly (same routing as debug_dmi_csr / debug_triggers) on the
//   trigger CSRs tselect (0x7A0), tdata1 (0x7A1) and tinfo (0x7A4):
//     - TINFO : with tselect=0, tinfo must read exactly 0x01000040
//               (version[31:24]=1 = Debug Spec 1.0; info bit 6 = mcontrol6
//               type 6 supported; no other trigger type advertised);
//     - CHAIN : write tdata1 with an otherwise-legal mcontrol6 pattern that
//               has the chain bit (bit 11) set (type=6, execute=1, chain=1,
//               no m/s/u priv bits so the trigger can never fire). Read back:
//               chain MUST be 0 (WARL read-only zero: this implementation
//               does not support trigger chaining), while type=6 and
//               execute=1 are retained per their WARL rules;
//     - the trigger is then disarmed (tdata1 = type6, no load/store/execute)
//       and the hart resumed: the firmware completes its loop untouched.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
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
localparam [31:0] DMS_ALLHALTED    = 32'h00000200; // [9]
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800; // [11]
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000; // [17]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0, aarsize=2, transfer=1)
//   regno = the 12-bit CSR address directly; +0x00010000 sets the write bit.
localparam [31:0] CMD_RD_TSELECT = 32'h00220000 | 32'h000007a0; // 0x002207a0
localparam [31:0] CMD_WR_TSELECT = 32'h00230000 | 32'h000007a0; // 0x002307a0
localparam [31:0] CMD_RD_TDATA1  = 32'h00220000 | 32'h000007a1; // 0x002207a1
localparam [31:0] CMD_WR_TDATA1  = 32'h00230000 | 32'h000007a1; // 0x002307a1
localparam [31:0] CMD_RD_TINFO   = 32'h00220000 | 32'h000007a4; // 0x002207a4

// Expected tinfo: version[31:24]=1 (Debug Spec 1.0), info bit6 (mcontrol6 type 6).
localparam [31:0] TINFO_EXPECT = 32'h01000040;

// mcontrol6 (tdata1 type=6) write pattern for the chain WARL check:
//   type[31:28]=6 -> 0x60000000 ; chain[11]=1 -> 0x800 ; execute[2]=1 -> 0x4.
//   dmode=0, action=0, no m/s/u priv bits -> the trigger can never fire even
//   while armed, so this is inert for the firmware.
localparam [31:0] TDATA1_CHAIN_WR = 32'h60000000 | 32'h00000800 | 32'h00000004; // = 0x60000804
// disarm pattern: type=6, everything else 0 (no load/store/execute)
localparam [31:0] TDATA1_DISARM   = 32'h60000000;

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
    $display("|  DEBUG TRIG WARL/INFO: tinfo == 0x01000040 (v1, mcontrol6) and      |");
    $display("|  mcontrol6.chain is WARL read-only ZERO (no trigger chaining)       |");
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
    end else $display("PASS:  hart in Debug Mode (abstract trigger-CSR access permitted) %t ns", $time);

    //========================================================================
    // Select trigger 0 and confirm the selection round-trips.
    //========================================================================
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_rd(CMD_RD_TSELECT);
    if (acmd_rdata !== 32'h0) begin
        $display("ERROR: tselect=0 read back %h (expected 0) %t ns", acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  tselect=0 round-trip %t ns", $time);

    //========================================================================
    // TINFO: must read exactly 0x01000040
    //   version[31:24] = 1 (Debug Spec 1.0), info[15:0] = 0x0040 (only bit 6
    //   set: mcontrol6 / type 6 is the one supported trigger type).
    //========================================================================
    abs_rd(CMD_RD_TINFO);
    if (acmd_rdata !== TINFO_EXPECT) begin
        $display("ERROR: tinfo=%h (expected exactly %h: version=1, mcontrol6-only) %t ns", acmd_rdata, TINFO_EXPECT, $time);
        error = error + 1;
    end else $display("PASS:  tinfo=%h (version=1, mcontrol6 supported) %t ns", acmd_rdata, $time);

    //========================================================================
    // CHAIN WARL: write tdata1 = type6 | chain | execute (0x60000804).
    //   chain (bit 11) must read back 0 (read-only zero: chaining not
    //   implemented); execute (bit 2) and type=6 must be retained.
    //========================================================================
    abs_wr(CMD_WR_TDATA1, TDATA1_CHAIN_WR);
    abs_rd(CMD_RD_TDATA1);

    if (acmd_rdata[31:28] !== 4'h6) begin
        $display("ERROR: tdata1.type=%h after mcontrol6 write (expected 6) [tdata1=%h] %t ns", acmd_rdata[31:28], acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  tdata1.type=6 retained (mcontrol6) %t ns", $time);

    if (acmd_rdata[11] !== 1'b0) begin
        $display("ERROR: mcontrol6.chain read back 1 (must be WARL read-only 0: chaining unsupported) [tdata1=%h] %t ns", acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  mcontrol6.chain WARL read-only 0 (wrote 1, read 0) %t ns", $time);

    if (acmd_rdata[2] !== 1'b1) begin
        $display("ERROR: mcontrol6.execute=0 after write (legal field must be retained) [tdata1=%h] %t ns", acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  mcontrol6.execute=1 retained alongside the dropped chain bit %t ns", $time);

    //========================================================================
    // TYPE WARL / ENUMERABILITY: tdata1.type must read 6 for an implemented
    //   trigger even when it is fully disarmed. Type 0 is the Debug Spec's
    //   "there is no trigger at this tselect" and ENDS a debugger's enumeration
    //   loop, so a disarmed trigger reporting 0 would make every trigger
    //   invisible (OpenOCD: "Found 0 triggers", no hardware breakpoints).
    //   Checked for BOTH disarm spellings: the canonical type6-only pattern and
    //   a bare tdata1=0 write (type is WARL-forced back to 6).
    //========================================================================
    abs_wr(CMD_WR_TDATA1, TDATA1_DISARM);
    abs_rd(CMD_RD_TDATA1);
    if (acmd_rdata !== TDATA1_DISARM) begin
        $display("ERROR: disarmed tdata1=%h (expected %h: type=6, nothing armed) %t ns", acmd_rdata, TDATA1_DISARM, $time);
        error = error + 1;
    end else $display("PASS:  disarmed tdata1=%h -- type=6 retained, trigger stays enumerable %t ns", acmd_rdata, $time);

    abs_wr(CMD_WR_TDATA1, 32'h0);
    abs_rd(CMD_RD_TDATA1);
    if (acmd_rdata[31:28] !== 4'h6) begin
        $display("ERROR: tdata1.type=%h after a tdata1=0 write (expected WARL-forced 6; 0 = 'no trigger here') [tdata1=%h] %t ns", acmd_rdata[31:28], acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  tdata1=0 write -> type WARL-forced to 6 (trigger still discoverable) %t ns", $time);

    if (acmd_rdata[2:0] !== 3'b000) begin
        $display("ERROR: tdata1=0 write left execute/store/load=%b (expected disarmed) [tdata1=%h] %t ns", acmd_rdata[2:0], acmd_rdata, $time);
        error = error + 1;
    end else $display("PASS:  tdata1=0 write disarms execute/store/load %t ns", $time);

    // Leave the trigger disarmed before resuming (no load/store/execute, no priv bits).
    abs_wr(CMD_WR_TDATA1, TDATA1_DISARM);

    //========================================================================
    // RESUME + final check
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
    check_cpu_reg(20, 32'h0000D09E);   // post-resume marker => the hart really resumed
    check_cpu_reg(18, X18_SENTINEL);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

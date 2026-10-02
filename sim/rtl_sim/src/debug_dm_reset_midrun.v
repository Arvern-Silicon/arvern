//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dm_reset_midrun
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Debug Module reset (dbgresetn) asserted while the hart runs
//   and an SBA transfer is in flight
//   debug_interface.md §4: "dbgresetn_i | the Debug Module only
//   (dmcontrol/dmstatus/abstract engine/SBA/APB bus)" and "hresetn_i | the
//   hart"; "dmactive (dmcontrol[0]) is a second, soft-reset level: while
//   dmactive=0, all DM/SBA architectural state is held at its reset value;
//   dmactive itself and the APB response flops reset on dbgresetn alone".
//   debug_interface.md §6: "Set dmactive=1 in its own write and poll it back
//   as 1"; sbcs "sbversion[31:29]=1 ... sbaccess[19:17] (R/W, reset 2) ...
//   sbasize[11:5]=32 (RO) · sbaccess32/16/8[2:0]=1 (RO)"; abstractcs
//   "datacount = 1, progbufsize = 0"; abstractauto bits [31:1] WARL-0;
//   cmderr 4 "a command was issued while the hart was not halted".
//   Debug 1.0 dmcontrol.dmactive: "0 (inactive): The module's state,
//   including authentication mechanism, takes its reset values"; sbaddress0
//   "Reset 0"; sbcs.sbaccess "Reset 2".
//   Contract note: Debug 1.0 3.2 says "The Debug Module's own state and
//   registers should only be reset at power-up and while dmactive in dmcontrol
//   is 0. If there is another mechanism to reset the DM, this mechanism must
//   also reset all the harts accessible to the DM." debug_interface.md §4
//   only describes dbgresetn asserted together with hresetn ("Power-on /
//   full-chip reset: assert both hresetn_i and dbgresetn_i together") or
//   held high across ndmreset. A DM-only reset with the hart running is
//   therefore outside the documented contract; "the hart keeps running
//   untouched" is the robustness expectation of this test.
//   An SBA write in flight is therefore interrupted with the documented soft
//   reset instead (R2): "Clearing dmactive while an SBA transfer is on the bus
//   lets that transfer finish before the SBA state resets" -> the new value.
//
//   The SRAM_NX wait states are raised to 30 for each in-flight round, so the
//   SBA data phase is still stalled when dbgresetn is forced low (checked:
//   the SBA address phase was accepted and data_hready is low at the force).
//   R1: SBA READ in flight (sbcs/sbaddress0/data0/abstractauto/cmderr all
//       away from reset values) -> reset values after re-activation; halt,
//       SBA read/write and resume work afterwards
//   R2: SBA WRITE in flight, dmactive cleared (not dbgresetn) -> reset values;
//       the write completes with the new value
//   R3: sberror=4 and cmderr=4 latched, no transfer -> both cleared
//   Throughout: the hart keeps running (loop counter advances across each
//   reset, never in Debug Mode outside the explicit halt), no RNMI, no trap,
//   and at the end sum(array) == iteration count.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

integer to, save_ws, save_rnd;
reg [31:0] v, cnt_before, cnt_after, word_old, word_new;
reg        sba_ap_seen;
reg        use_dmactive;
reg        watch_run;
reg        dbg_mode_unexpected;

localparam [6:0]  DMI_DATA0        = 7'h04;
localparam [6:0]  DMI_DMCONTROL    = 7'h10;
localparam [6:0]  DMI_DMSTATUS     = 7'h11;
localparam [6:0]  DMI_ABSTRACTCS   = 7'h16;
localparam [6:0]  DMI_COMMAND      = 7'h17;
localparam [6:0]  DMI_ABSTRACTAUTO = 7'h18;
localparam [6:0]  DMI_SBCS         = 7'h38;
localparam [6:0]  DMI_SBADDRESS0   = 7'h39;
localparam [6:0]  DMI_SBDATA0      = 7'h3c;

localparam [31:0] DMC_DMACTIVE     = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST   = 32'h10000000;
localparam [31:0] ACS_BUSY         = 32'h00001000;
localparam [31:0] ACS_CMDERR       = 32'h00000700;

localparam [31:0] SBCS_RESET       = 32'h20040407;   // sbversion 1, sbaccess 2, sbasize 32, access 8/16/32
localparam [31:0] ACS_FIELDS       = 32'h1F00170F;   // progbufsize, busy, cmderr, datacount (relaxedpriv excluded)
localparam [31:0] ACS_RESET        = 32'h00000001;   // datacount 1, progbufsize 0, cmderr 0, busy 0

localparam [31:0] RD_ADDR          = 32'h81000040;
localparam [31:0] WR_ADDR          = 32'h81000044;

// SBA address phase accepted on the data port
initial sba_ap_seen = 1'b0;
initial use_dmactive = 1'b0;
always @(posedge dut_hclk)
    if ((data_htrans[1] === 1'b1) && (data_hmaster === 1'b1) && (data_hready === 1'b1))
        sba_ap_seen <= 1'b1;

// the hart must never enter Debug Mode outside the explicit halt
initial begin watch_run = 1'b0; dbg_mode_unexpected = 1'b0; end
always @(posedge free_clk)
    if (watch_run && (dbg_debug_mode === 1'b1))
        dbg_mode_unexpected <= 1'b1;

task chk;
   input [8*48:1] what;
   input [31:0]   got;
   input [31:0]   exp;
   begin
      if (got !== exp) begin
         $display("ERROR: %0s = %h (expected %h) %t ns", what, got, exp, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s = %h %t ns", what, got, $time);
   end
endtask

task activate;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      to = 0;
      dmi_read(DMI_DMCONTROL);
      while (((dmi_readval & DMC_DMACTIVE) === 32'h0) && (to < 50)) begin
         dmi_read(DMI_DMCONTROL);
         to = to + 1;
      end
      chk("dmcontrol.dmactive after activation", dmi_readval & DMC_DMACTIVE, DMC_DMACTIVE);
   end
endtask

// Put cmderr at 4: an abstract command while the hart runs.
task cmderr_running;
   begin
      dmi_write(DMI_COMMAND, 32'h00221005);
      dmi_read(DMI_ABSTRACTCS);
      chk("cmderr for a command on a running hart", (dmi_readval & ACS_CMDERR) >> 8, 32'd4);
   end
endtask

// Stall SRAM_NX so the SBA data phase outlasts the triggering DMI write.
task slow_nx;
   begin
      save_ws  = s_sram_nx_number_ws;
      save_rnd = s_sram_nx_random_ws_en;
      s_sram_nx_number_ws    = 30;
      s_sram_nx_random_ws_en = 0;
      // the inserter draws each access's wait count at the previous address
      // phase: load it for the very next access too
      ahb_bus_system_inst.ahb_waitstate_inserter_sram_nx_inst.aph_wait_nxt = 30;
   end
endtask

task restore_nx;
   begin
      s_sram_nx_number_ws    = save_ws;
      s_sram_nx_random_ws_en = save_rnd;
   end
endtask

// Wait for the SBA address phase started by the caller, then pulse dbgresetn
// while its data phase is stalled. Checks the hart loop advances across it.
task dm_reset_pulse;
   input check_in_flight;
   begin
      if (check_in_flight) begin
         to = 0;
         while ((sba_ap_seen !== 1'b1) && (to < 400)) begin
            @(negedge free_clk);
            to = to + 1;
         end
         @(negedge free_clk);
         if ((sba_ap_seen === 1'b1) && (data_hready === 1'b0))
            $display("PASS:  SBA transfer in flight at dbgresetn assertion (address phase accepted, data phase stalled) %t ns", $time);
         else begin
            $display("ERROR: SBA transfer not in flight at dbgresetn assertion (ap_seen=%b hready=%b) %t ns", sba_ap_seen, data_hready, $time);
            error = error + 1;
         end
      end else
         @(negedge free_clk);
      cnt_before = probes_cpu.x21;
      if (use_dmactive)
         dmi_write(DMI_DMCONTROL, 32'h0);      // soft reset: dmactive=0
      else begin
         force dbgresetn = 1'b0;
         repeat (10) @(negedge free_clk);
         release dbgresetn;
      end
      repeat (60) @(negedge free_clk);          // let the stalled data phase end
      to = 0;
      while ((probes_cpu.x21 === cnt_before) && (to < 5000)) begin
         @(negedge free_clk);
         to = to + 1;
      end
      cnt_after = probes_cpu.x21;
      if (cnt_after !== cnt_before)
         $display("PASS:  hart loop kept running across the DM reset (x21 %0d -> %0d) %t ns", cnt_before, cnt_after, $time);
      else begin
         $display("ERROR: hart loop did not advance after the DM reset (x21 stuck at %0d) %t ns", cnt_before, $time);
         error = error + 1;
      end
   end
endtask

// Registers after the DM reset: dmcontrol first (dmactive=0), then the rest
// once re-activated.
task chk_reset_values;
   input [8*4:1] tag;
   begin
      dmi_read(DMI_DMCONTROL);
      chk("dmcontrol after dbgresetn", dmi_readval, 32'h0);
      activate;
      dmi_read(DMI_SBCS);
      chk("sbcs after dbgresetn", dmi_readval, SBCS_RESET);
      dmi_read(DMI_SBADDRESS0);
      chk("sbaddress0 after dbgresetn", dmi_readval, 32'h0);
      dmi_read(DMI_ABSTRACTCS);
      $display("INFO:  %0s abstractcs after dbgresetn = %h %t ns", tag, dmi_readval, $time);
      chk("abstractcs busy/cmderr/progbufsize/datacount", dmi_readval & ACS_FIELDS, ACS_RESET);
      dmi_read(DMI_ABSTRACTAUTO);
      chk("abstractauto after dbgresetn", dmi_readval, 32'h0);
      dmi_read(DMI_DATA0);
      $display("INFO:  %0s data0 after dbgresetn = %h (reset value not documented) %t ns", tag, dmi_readval, $time);
      dmi_read(DMI_DMSTATUS);
      $display("INFO:  %0s dmstatus after dbgresetn = %h (havereset not asserted: Debug 1.0 allows either) %t ns", tag, dmi_readval, $time);
      chk("dmstatus[13:8] after dbgresetn (running)", dmi_readval & 32'h00003F00, 32'h00000C00);
      if (dbg_debug_mode !== 1'b0) begin
         $display("ERROR: %0s hart in Debug Mode after the DM reset %t ns", tag, $time);
         error = error + 1;
      end
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    $display("");
    $display(" ======================================================");
    $display("|  DEBUG DM RESET MID-RUN: dbgresetn with SBA in flight |");
    $display(" ======================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    activate;
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    watch_run = 1'b1;

    //--------------------------------------------------------------------
    // R1: SBA read in flight, DM state away from reset values
    //--------------------------------------------------------------------
    $display("----- R1: SBA read in flight -----");
    sba_write32(RD_ADDR, 32'h13572468);
    dmi_write(DMI_DATA0, 32'hDA7A0000);
    cmderr_running;
    dmi_write(DMI_ABSTRACTAUTO, 32'h1);           // cmderr != 0: no command runs
    dmi_read(DMI_ABSTRACTAUTO);
    chk("R1: abstractauto set before reset", dmi_readval, 32'h1);
    slow_nx;
    sba_cfg(1'b1, 1'b0, 1'b1, 3'd2);              // readonaddr, autoincrement, 32-bit
    sba_ap_seen = 1'b0;
    dmi_write(DMI_SBADDRESS0, RD_ADDR);           // starts the read
    dm_reset_pulse(1'b1);
    restore_nx;
    chk_reset_values("R1");

    // the DM is fully usable again: halt, SBA, resume
    watch_run = 1'b0;
    dm_halt;
    sba_read32(RD_ADDR);
    chk("R1: SBA read after re-activation", sba_rdata, 32'h13572468);
    sba_write32(RD_ADDR + 32'h8, 32'h24681357);
    sba_read32(RD_ADDR + 32'h8);
    chk("R1: SBA write/read-back after re-activation", sba_rdata, 32'h24681357);
    dmi_read(DMI_ABSTRACTCS);
    chk("R1: cmderr after the halted-hart SBA", (dmi_readval & ACS_CMDERR) >> 8, 32'd0);
    dm_resume;
    watch_run = 1'b1;

    //--------------------------------------------------------------------
    // R2: SBA write in flight
    //--------------------------------------------------------------------
    $display("----- R2: SBA write in flight -----");
    word_old = 32'h0DD0DD00;
    word_new = 32'hE11EE11E;
    sba_write32(WR_ADDR, word_old);
    slow_nx;
    sba_cfg(1'b0, 1'b0, 1'b1, 3'd2);              // autoincrement, 32-bit
    dmi_write(DMI_SBADDRESS0, WR_ADDR);
    sba_ap_seen = 1'b0;
    dmi_write(DMI_SBDATA0, word_new);             // starts the write
    use_dmactive = 1'b1;
    dm_reset_pulse(1'b1);
    use_dmactive = 1'b0;
    restore_nx;
    chk_reset_values("R2");
    sba_read32(WR_ADDR);                          // SBA works on the running hart
    chk("R2: write finished across dmactive=0", sba_rdata, word_new);
    sba_get_sberr;
    chk("R2: sberror after the post-reset SBA read", {29'd0, sba_sberr}, 32'd0);

    //--------------------------------------------------------------------
    // R3: sberror and cmderr latched, no transfer in flight
    //--------------------------------------------------------------------
    $display("----- R3: errors latched -----");
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd3);              // 64-bit: unsupported
    dmi_write(DMI_SBADDRESS0, RD_ADDR);
    sba_get_sberr;
    chk("R3: sberror before reset", {29'd0, sba_sberr}, 32'd4);
    cmderr_running;
    dm_reset_pulse(1'b0);
    chk_reset_values("R3");

    //--------------------------------------------------------------------
    // End: release the firmware loop over SBA (hart running)
    //--------------------------------------------------------------------
    sba_write32(32'h80000100, 32'h1);
    random_irq_enable = 0;
    wait (probes_cpu.x31 === 32'hdeadbeef);
    watch_run = 1'b0;
    repeat(40) @(posedge free_clk);

    if (probes_cpu.x20 === probes_cpu.x21)
        $display("PASS:  array sum == iteration count (%0d): no hart access lost or corrupted %t ns", probes_cpu.x21, $time);
    else begin
        $display("ERROR: array sum %0d != iteration count %0d %t ns", probes_cpu.x20, probes_cpu.x21, $time);
        error = error + 1;
    end
    check_mem_value(`SPAD(32'h104), 32'd0);       // RNMI count
    check_mem_value(`SPAD(32'h108), 32'd0);       // trap count
    if (dbg_mode_unexpected) begin
        $display("ERROR: hart entered Debug Mode outside the explicit halt %t ns", $time);
        error = error + 1;
    end else
        $display("PASS:  hart never entered Debug Mode outside the explicit halt %t ns", $time);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

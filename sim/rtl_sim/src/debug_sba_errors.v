//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_sba_errors
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SBA error paths (Debug 1.0 sbcs / sbaddress0 / sbdata0)
//   sbaccess: "If sbaccess has an unsupported value when the DM starts a bus
//   access, the access is not performed and sberror is set to 4."
//   sberror: "While this field is non-zero, no more system bus accesses can be
//   initiated by the Debug Module." (R/W1C)
//   sbbusyerror: "Set when the debugger attempts to read data while a read is
//   in progress, or when the debugger initiates a new access while one is
//   already in progress (while sbbusy is set). It remains set until it's
//   explicitly cleared by the debugger. While this field is set, no more system
//   bus accesses can be initiated by the Debug Module." (R/W1C)
//   sbaddress0 / sbdata0: "When the system bus manager is busy, writes to this
//   register will set sbbusyerror and don't do anything else." / "If the bus
//   manager is busy then accesses set sbbusyerror, and don't do anything else."
//   sbautoincrement / step 3: "If the read succeeded and sbautoincrement is
//   set, increment sbaddress."
//
//   Part 1 (sbcs advertises sbaccess64/128 = 0): for sbaccess = 3 and 4, an
//     sbcs write alone raises nothing; a write (sbdata0), a readonaddr read
//     (sbaddress0) and a readondata read (sbdata0) each set sberror=4 with no
//     SBA transfer on the data bus and no sbaddress0 autoincrement; a further
//     trigger while sberror!=0 also makes no transfer; W1C clears it; memory is
//     unchanged and 32-bit accesses work again.
//   Part 2: the non-executable SRAM gets 60 wait states so an SBA access stays
//     busy across several DMI transactions (sbbusy=1 is checked first). A
//     second sbdata0 write, an sbaddress0 write and an sbdata0 read while busy
//     each set sbbusyerror and are dropped (memory, sbaddress0, read data show
//     the first access only); no access starts while sbbusyerror=1; W1C clears
//     it and accesses work again.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

localparam [6:0]  DMI_SBCS       = 7'h38;
localparam [6:0]  DMI_SBADDRESS0 = 7'h39;
localparam [6:0]  DMI_SBDATA0    = 7'h3c;

localparam [31:0] NX             = 32'h81000000;
localparam [31:0] SBCS_BUSYERR   = 32'h00400000;   // [22]
localparam [31:0] SBCS_BUSY      = 32'h00200000;   // [21]
localparam [31:0] SBCS_ERR       = 32'h00007000;   // [14:12]

// SBA-tagged data-bus address phases (accepted NONSEQ/SEQ with data_hmaster=1)
integer    sbe_bus_cnt;
initial    sbe_bus_cnt = 0;
always @(posedge free_clk)
   if (data_htrans[1] && data_hready && data_hmaster) sbe_bus_cnt = sbe_bus_cnt + 1;

integer    cnt0, sz, orig_ws, orig_rnd;
reg [31:0] v;

task chk;
   input [8*44:1] what;
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

// Read sbcs and check the sberror / sbbusyerror fields.
task chk_sbcs_err;
   input [8*44:1] what;
   input [2:0]    exp_err;
   input          exp_busyerr;
   begin
      dmi_read(DMI_SBCS);
      v = dmi_readval;
      if ((v[14:12] !== exp_err) || (v[22] !== exp_busyerr)) begin
         $display("ERROR: %0s: sberror=%0d sbbusyerror=%b (expected %0d / %b), sbcs=%h %t ns",
                  what, v[14:12], v[22], exp_err, exp_busyerr, v, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s: sberror=%0d sbbusyerror=%b %t ns", what, v[14:12], v[22], $time);
   end
endtask

task chk_no_transfer;
   input [8*44:1] what;
   begin
      repeat (10) @(posedge free_clk);
      if (sbe_bus_cnt !== cnt0) begin
         $display("ERROR: %0s: %0d SBA transfer(s) reached the data bus (expected none) %t ns", what, sbe_bus_cnt - cnt0, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s: no SBA transfer on the data bus %t ns", what, $time);
   end
endtask

// Require sbbusy=1 right after starting an access (the wait states make it
// long enough); otherwise the sbbusyerror checks below would be vacuous.
task chk_busy_precond;
   input [8*44:1] what;
   begin
      dmi_read(DMI_SBCS);
      if ((dmi_readval & SBCS_BUSY) === 32'h0) begin
         $display("ERROR: %0s: sbbusy=0 right after the access started (wait-state setup ineffective) %t ns", what, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s: sbbusy=1 while the access is on the bus %t ns", what, $time);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    $display("");
    $display(" ================================================");
    $display("|  DEBUG SBA: unsupported size and sbbusyerror   |");
    $display(" ================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(7'h10, 32'h00000001);
    dmi_write(7'h10, 32'h10000001);
    dm_halt;

    dmi_read(DMI_SBCS);
    chk("sbcs.sbaccess128/64 (not supported)", {30'd0, dmi_readval[4:3]}, 32'd0);

    sba_write32(NX + 32'h0, 32'h11111111);
    sba_write32(NX + 32'h4, 32'h22222222);
    chk_sbcs_err("baseline", 3'd0, 1'b0);

    //====================================================================
    // Part 1: sbaccess = 3 (64-bit) and 4 (128-bit)
    //====================================================================
    for (sz = 3; sz <= 4; sz = sz + 1) begin
        $display("---- sbaccess = %0d ----", sz);

        // sbcs write alone: no access started -> no error
        sba_cfg(1'b0, 1'b0, 1'b1, sz[2:0]);
        dmi_read(DMI_SBCS);
        chk("sbcs.sbaccess read-back", {29'd0, dmi_readval[19:17]}, sz);
        chk_sbcs_err("sbcs write alone", 3'd0, 1'b0);

        // (a) write triggered by sbdata0 (autoincrement on)
        dmi_write(DMI_SBADDRESS0, NX + 32'h0);           // readonaddr=0: no access
        cnt0 = sbe_bus_cnt;
        dmi_write(DMI_SBDATA0, 32'hBAD0_0000 | sz);
        sba_wait_idle;
        chk_sbcs_err("sbdata0 write, unsupported size", 3'd4, 1'b0);
        chk_no_transfer("sbdata0 write, unsupported size");
        dmi_read(DMI_SBADDRESS0);
        chk("sbaddress0 not auto-incremented (write)", dmi_readval, NX + 32'h0);
        dmi_write(DMI_SBDATA0, 32'hBAD1_0000 | sz);      // sberror!=0: nothing starts
        chk_no_transfer("sbdata0 write while sberror=4");
        sba_clr_err;
        chk_sbcs_err("after W1C", 3'd0, 1'b0);

        // (b) read triggered by sbaddress0 (readonaddr, autoincrement on)
        sba_cfg(1'b1, 1'b0, 1'b1, sz[2:0]);
        cnt0 = sbe_bus_cnt;
        dmi_write(DMI_SBADDRESS0, NX + 32'h4);
        sba_wait_idle;
        chk_sbcs_err("readonaddr read, unsupported size", 3'd4, 1'b0);
        chk_no_transfer("readonaddr read, unsupported size");
        dmi_read(DMI_SBADDRESS0);
        chk("sbaddress0 not auto-incremented (read)", dmi_readval, NX + 32'h4);
        sba_clr_err;
        chk_sbcs_err("after W1C", 3'd0, 1'b0);

        // (c) read triggered by an sbdata0 read (readondata)
        sba_cfg(1'b0, 1'b1, 1'b0, sz[2:0]);
        cnt0 = sbe_bus_cnt;
        dmi_read(DMI_SBDATA0);
        sba_wait_idle;
        chk_sbcs_err("readondata read, unsupported size", 3'd4, 1'b0);
        chk_no_transfer("readondata read, unsupported size");
        sba_clr_err;
        chk_sbcs_err("after W1C", 3'd0, 1'b0);

        // supported accesses work again, memory untouched by the failed writes;
        // the successful read is also the positive control of the bus counter
        cnt0 = sbe_bus_cnt;
        sba_read32(NX + 32'h0);
        chk("[NX+0] after failed writes", sba_rdata, 32'h11111111);
        if (!(sbe_bus_cnt > cnt0)) begin
            $display("ERROR: bench SBA transfer counter did not count a successful SBA read (monitor broken, no-transfer checks void) %t ns", $time);
            error = error + 1;
        end else
            $display("PASS:  bench SBA transfer counter sees a successful SBA read %t ns", $time);
        sba_read32(NX + 32'h4);
        chk("[NX+4]", sba_rdata, 32'h22222222);
        chk_sbcs_err("32-bit reads after recovery", 3'd0, 1'b0);
    end

    //====================================================================
    // Part 2: sbbusyerror (60 wait states on the non-executable SRAM)
    //====================================================================
    orig_ws  = s_sram_nx_number_ws;
    orig_rnd = s_sram_nx_random_ws_en;
    s_sram_nx_random_ws_en = 0;
    s_sram_nx_number_ws    = 60;
    // The inserter draws each access's wait count at the previous address
    // phase: two accesses make the 60-cycle setting effective.
    sba_read32(NX + 32'h0);
    sba_read32(NX + 32'h0);

    // (a) second sbdata0 write while the first write is busy
    sba_cfg(1'b0, 1'b0, 1'b0, 3'd2);
    dmi_write(DMI_SBADDRESS0, NX + 32'hC);
    dmi_write(DMI_SBDATA0, 32'hAAAA0001);
    chk_busy_precond("sbdata0 write");
    dmi_write(DMI_SBDATA0, 32'hBBBB0002);                // must be dropped
    sba_wait_idle;
    chk_sbcs_err("sbdata0 write while busy", 3'd0, 1'b1);
    cnt0 = sbe_bus_cnt;
    dmi_write(DMI_SBDATA0, 32'hCCCC0003);                // sbbusyerror=1: nothing starts
    chk_no_transfer("sbdata0 write while sbbusyerror=1");
    chk_sbcs_err("sbbusyerror is sticky", 3'd0, 1'b1);
    sba_clr_err;
    chk_sbcs_err("after W1C", 3'd0, 1'b0);
    sba_read32(NX + 32'hC);
    chk("[NX+C] holds the first write only", sba_rdata, 32'hAAAA0001);

    // (b) sbaddress0 write while a readonaddr read is busy
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd2);
    dmi_write(DMI_SBADDRESS0, NX + 32'h0);
    chk_busy_precond("readonaddr read");
    dmi_write(DMI_SBADDRESS0, NX + 32'h4);               // must be dropped
    sba_wait_idle;
    chk_sbcs_err("sbaddress0 write while busy", 3'd0, 1'b1);
    dmi_read(DMI_SBADDRESS0);
    chk("sbaddress0 keeps the first address", dmi_readval, NX + 32'h0);
    sba_clr_err;
    chk_sbcs_err("after W1C", 3'd0, 1'b0);
    dmi_read(DMI_SBDATA0);                               // readondata=0 after W1C
    chk("sbdata0 = data of the first read", dmi_readval, 32'h11111111);

    // (c) sbdata0 read while a read is in progress
    sba_cfg(1'b1, 1'b0, 1'b0, 3'd2);
    dmi_write(DMI_SBADDRESS0, NX + 32'h4);
    chk_busy_precond("readonaddr read (2)");
    dmi_read(DMI_SBDATA0);                               // read while busy
    sba_wait_idle;
    chk_sbcs_err("sbdata0 read while busy", 3'd0, 1'b1);
    sba_clr_err;
    chk_sbcs_err("after W1C", 3'd0, 1'b0);
    dmi_read(DMI_SBDATA0);
    chk("sbdata0 = completed read data", dmi_readval, 32'h22222222);

    // recovery with the original wait states
    s_sram_nx_number_ws    = orig_ws;
    s_sram_nx_random_ws_en = orig_rnd;
    sba_write32(NX + 32'h10, 32'h5555AAAA);
    sba_read32(NX + 32'h10);
    chk("[NX+10] write/read after recovery", sba_rdata, 32'h5555AAAA);
    chk_sbcs_err("final", 3'd0, 1'b0);

    // firmware cross-check through the hart's own loads
    dmi_write(7'h04, 32'h1);
    dmi_write(7'h17, 32'h0023101d);                      // x29 = 1
    dm_resume;
    wait (probes_cpu.x31 === 32'hdeadbeef);
    repeat(40) @(posedge free_clk);                      // the last load may still be in its data phase
    check_cpu_reg(20, 32'h5555AAAA);
    check_cpu_reg(21, 32'h11111111);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

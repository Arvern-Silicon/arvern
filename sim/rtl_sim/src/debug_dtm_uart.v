//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dtm_uart
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: END-TO-END external debug over a real UART transport.
//   The DMI bus is driven by the arv_dtm UART DTM (shipping arv_dtm,
//   transport selected at elaboration by DTM_TYPE=UART), and this stimulus talks to
//   it over the serial link via the UART host BFM (debug_dtm_uart_tasks.v), whose
//   dmi_write/dmi_read primitives feed the transport-agnostic dm_halt/dm_resume/
//   sba_* helpers unchanged. This is an INTEGRATION SANITY pass over each debug
//   feature (run control, abstract GPR, abstract CSR, SBA) end-to-end through the
//   real transport + real Debug Module; corner cases live in the direct-DMI
//   debug_dmi_* tests and the standalone arv_dtm bench.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

// dmcontrol / dmstatus fields
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset
localparam [31:0] DMS_ALLHALTED  = 32'h00000200;  // [9]

// abstractcs fields
localparam [31:0] ACS_BUSY   = 32'h00001000;      // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700;      // [10:8] cmderr (W1C)

// Access Register command words (aarsize=2 32-bit, transfer=1)
//   GPR  regno = 0x1000 + index ; CSR regno = 12-bit CSR address
localparam [31:0] CMD_RD_X18      = 32'h00220000 | 32'h00001012;  // read  x18
localparam [31:0] CMD_WR_X20      = 32'h00230000 | 32'h00001014;  // write x20
localparam [31:0] CMD_RD_MSCRATCH = 32'h00220000 | 32'h00000340;  // read  mscratch(0x340)
localparam [31:0] CMD_WR_MSCRATCH = 32'h00230000 | 32'h00000340;  // write mscratch(0x340)

// Expected values / debugger-injected values
localparam [31:0] X18_SENTINEL  = 32'hA5A5A5A5;
localparam [31:0] X20_INJECT    = 32'hCAFE0000;
localparam [31:0] X20_FINAL     = 32'hCAFE0123;   // injected + firmware post-resume +0x123
localparam [31:0] MSCRATCH_SEED = 32'hC5A17E5C;   // firmware's seed
localparam [31:0] MSCRATCH_DBG  = 32'h0BADF00D;   // value the debugger writes
localparam [31:0] SBA_ADDR      = 32'h80004020;   // scratch RAM word (SRAM base 0x80004000)
localparam [31:0] SBA_VAL       = 32'h5BA00001;

// Poll abstractcs.busy clear; leaves the last abstractcs read in dmi_readval.
task abs_wait_done;
   input [127:0] tag;
   begin
      to = 0;
      dmi_read(DMI_ABSTRACTCS);
      while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
         dmi_read(DMI_ABSTRACTCS);
         to = to + 1;
      end
      if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
         $display("ERROR: %0s abstractcs.busy stuck %t ns", tag, $time);
         error = error + 1;
      end
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: %0s cmderr=%0d (expected 0) %t ns", tag, (dmi_readval & ACS_CMDERR) >> 8, $time);
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
    $display("|  DEBUG DTM UART: end-to-end debug over a real UART transport        |");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning (x31=0x11111111) %t ns", $time);

    // Open the serial link: the DTM auto-measures the host baud from a leading 0x80
    // and echoes it back. Must precede any DMI transaction.
    uart_autobaud_sync;

    //========================================================================
    // 1. Run control: dmactive, halt the hart over the DTM/DMI
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);   // clear sticky havereset
    dm_halt;                                                    // haltreq -> poll allhalted

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while halted %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode over UART DTM %t ns", $time);

    //========================================================================
    // 2. Abstract GPR read: x18 sentinel via data0
    //========================================================================
    dmi_write(DMI_COMMAND, CMD_RD_X18);
    abs_wait_done("gpr-read");
    dmi_read(DMI_DATA0);
    if (dmi_readval !== X18_SENTINEL) begin
        $display("ERROR: abstract read x18=%h (expected %h) %t ns", dmi_readval, X18_SENTINEL, $time);
        error = error + 1;
    end else $display("PASS:  abstract GPR read x18=%h over UART %t ns", X18_SENTINEL, $time);

    //========================================================================
    // 3. Abstract GPR write: inject x20, cross-check the register file
    //========================================================================
    dmi_write(DMI_DATA0, X20_INJECT);
    dmi_write(DMI_COMMAND, CMD_WR_X20);
    abs_wait_done("gpr-write");
    if (probes_cpu.x20 !== X20_INJECT) begin
        $display("ERROR: regfile x20=%h after abstract write (expected %h) %t ns", probes_cpu.x20, X20_INJECT, $time);
        error = error + 1;
    end else $display("PASS:  abstract GPR write x20=%h reached regfile %t ns", X20_INJECT, $time);

    //========================================================================
    // 4. Abstract CSR read: mscratch seed
    //========================================================================
    dmi_write(DMI_COMMAND, CMD_RD_MSCRATCH);
    abs_wait_done("csr-read");
    dmi_read(DMI_DATA0);
    if (dmi_readval !== MSCRATCH_SEED) begin
        $display("ERROR: abstract read mscratch=%h (expected %h) %t ns", dmi_readval, MSCRATCH_SEED, $time);
        error = error + 1;
    end else $display("PASS:  abstract CSR read mscratch=%h over UART %t ns", MSCRATCH_SEED, $time);

    //========================================================================
    // 5. Abstract CSR write: mscratch <- debugger value (firmware reads back later)
    //========================================================================
    dmi_write(DMI_DATA0, MSCRATCH_DBG);
    dmi_write(DMI_COMMAND, CMD_WR_MSCRATCH);
    abs_wait_done("csr-write");
    $display("PASS:  abstract CSR write mscratch<=%h issued %t ns", MSCRATCH_DBG, $time);

    //========================================================================
    // 6. System Bus Access: write a RAM word via the DM's AHB master, read it back
    //========================================================================
    sba_write32(SBA_ADDR, SBA_VAL);
    sba_read32 (SBA_ADDR);
    if (sba_rdata !== SBA_VAL) begin
        $display("ERROR: SBA read-back [%h]=%h (expected %h) %t ns", SBA_ADDR, sba_rdata, SBA_VAL, $time);
        error = error + 1;
    end else $display("PASS:  SBA write+read-back [%h]=%h over UART %t ns", SBA_ADDR, SBA_VAL, $time);

    //========================================================================
    // 7. Resume the hart over the DTM/DMI
    //========================================================================
    dm_resume;

    //========================================================================
    // 8. Firmware completes and proves every debugger write landed
    //========================================================================
    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, X20_FINAL);      // GPR write survived + hart resumed & ran
    check_cpu_reg(18, X18_SENTINEL);   // read sentinel untouched
    check_cpu_reg(21, MSCRATCH_DBG);   // firmware read mscratch -> debugger's value
    check_cpu_reg(22, SBA_VAL);        // firmware read [SBA_ADDR] -> SBA-written value

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

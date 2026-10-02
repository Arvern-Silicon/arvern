//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_sba_addr_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: System Bus Access address walk (walking ones / zeros inside
//   the mapped SRAMs, sbaddress0 auto-increment, unmapped address)
//   debug_interface.md §6 SBA: "sbasize[11:5]=32 (RO)"; "a sbaddress0 write
//   with sbreadonaddr starts a read; a sbdata0 write starts a write";
//   "sbautoincrement adds the access size in bytes after each access that
//   completes without error"; "sberror: ... 2 = address (aRVern maps any AHB
//   HRESP error to 2)".
//   Debug 1.0 3.14.23: "If the read succeeded and sbautoincrement is set,
//   increment sbaddress."
//   Bench map (CLAUDE.md): executable SRAM 0x8000_0000 (64 KB), non-executable
//   SRAM 0x8100_0000 (64 KB); 0x8001_0000 is past the executable SRAM and
//   decodes to no subordinate.
//
//   A: SRAM_X walking ones   0x80000000 and 0x80000000|(1<<k), k = 2..15
//   B: SRAM_NX walking ones  0x81000000|(1<<k) and walking zeros
//      0x81000000|(0xFFFC & ~(1<<k)), k = 2..15
//      Every address of A+B is written first (data = addr ^ 0x5A5AA5A5), then
//      all are read back: an aliased address bit would overwrite a word.
//   C: 32-bit auto-increment WRITES (sbdata0 writes): sbaddress0 += 4 each,
//      data read back
//   D: 8-bit and 16-bit auto-increment writes: sbaddress0 += 1 / += 2
//   E: 16-bit auto-increment READS (readonaddr + readondata): sbaddress0 += 2
//   F: unmapped 0x80010000, auto-increment on: read and write both set
//      sberror = 2 and leave sbaddress0 unchanged
//   Then the firmware reads [0x80008000] and [0x81000004] after resume.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

integer to, k, n;
reg [31:0] a, v;
reg [31:0] addr_tab [0:63];

localparam [6:0]  DMI_DATA0      = 7'h04;
localparam [6:0]  DMI_DMCONTROL  = 7'h10;
localparam [6:0]  DMI_ABSTRACTCS = 7'h16;
localparam [6:0]  DMI_COMMAND    = 7'h17;
localparam [6:0]  DMI_SBCS       = 7'h38;
localparam [6:0]  DMI_SBADDRESS0 = 7'h39;
localparam [6:0]  DMI_SBDATA0    = 7'h3c;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;
localparam [31:0] ACS_BUSY       = 32'h00001000;
localparam [31:0] ACS_CMDERR     = 32'h00000700;

localparam [31:0] PAT            = 32'h5A5AA5A5;
localparam [31:0] UNMAPPED       = 32'h80010000;

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

task sberr_chk;
   input [8*48:1] what;
   input [2:0]    exp;
   begin
      sba_get_sberr;
      chk(what, {29'd0, sba_sberr}, {29'd0, exp});
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    $display("");
    $display(" ======================================================");
    $display("|  DEBUG SBA ADDRESS WALK                               |");
    $display(" ======================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;

    dmi_read(DMI_SBCS);
    chk("sbcs.sbasize", {25'd0, dmi_readval[11:5]}, 32'd32);
    sba_clr_err;

    //--------------------------------------------------------------------
    // A + B: build the address list
    //--------------------------------------------------------------------
    n = 0;
    addr_tab[n] = 32'h80000000; n = n + 1;
    for (k = 2; k < 16; k = k + 1) begin
        addr_tab[n] = 32'h80000000 | (32'h1 << k); n = n + 1;
    end
    for (k = 2; k < 16; k = k + 1) begin
        addr_tab[n] = 32'h81000000 | (32'h1 << k); n = n + 1;
    end
    for (k = 2; k < 16; k = k + 1) begin
        addr_tab[n] = 32'h81000000 | (32'h0000FFFC & ~(32'h1 << k)); n = n + 1;
    end

    for (ii = 0; ii < n; ii = ii + 1)
        sba_write32(addr_tab[ii], addr_tab[ii] ^ PAT);
    sberr_chk("A/B: sberror after the write walk", 3'd0);

    jj = 0;
    for (ii = 0; ii < n; ii = ii + 1) begin
        sba_read32(addr_tab[ii]);
        if (sba_rdata !== (addr_tab[ii] ^ PAT)) begin
            $display("ERROR: walk read [%h] = %h (expected %h: aliased or lost write) %t ns",
                     addr_tab[ii], sba_rdata, addr_tab[ii] ^ PAT, $time);
            error = error + 1;
            jj = jj + 1;
        end
    end
    if (jj == 0)
        $display("PASS:  A/B: %0d walking-one/zero addresses read back their own data %t ns", n, $time);
    sberr_chk("A/B: sberror after the read walk", 3'd0);

    //--------------------------------------------------------------------
    // C: 32-bit auto-increment writes
    //--------------------------------------------------------------------
    sba_cfg(1'b0, 1'b0, 1'b1, 3'd2);
    dmi_write(DMI_SBADDRESS0, 32'h81000240);
    for (ii = 0; ii < 4; ii = ii + 1) begin
        dmi_write(DMI_SBDATA0, 32'hC0DE0000 + ii);
        sba_wait_idle;
    end
    dmi_read(DMI_SBADDRESS0);
    chk("C: sbaddress0 after 4 word writes", dmi_readval, 32'h81000250);
    for (ii = 0; ii < 4; ii = ii + 1) begin
        sba_read32(32'h81000240 + 4*ii);
        chk("C: auto-increment write data", sba_rdata, 32'hC0DE0000 + ii);
    end

    //--------------------------------------------------------------------
    // D: 8-bit and 16-bit auto-increment writes
    //--------------------------------------------------------------------
    sba_write32(32'h81000340, 32'h0);
    sba_write32(32'h81000344, 32'h0);
    sba_cfg(1'b0, 1'b0, 1'b1, 3'd0);
    dmi_write(DMI_SBADDRESS0, 32'h81000340);
    for (ii = 0; ii < 4; ii = ii + 1) begin
        dmi_write(DMI_SBDATA0, 32'h11 * (ii + 1));
        sba_wait_idle;
    end
    dmi_read(DMI_SBADDRESS0);
    chk("D: sbaddress0 after 4 byte writes", dmi_readval, 32'h81000344);
    sba_cfg(1'b0, 1'b0, 1'b1, 3'd1);
    dmi_write(DMI_SBADDRESS0, 32'h81000344);
    dmi_write(DMI_SBDATA0, 32'h0000BEEF);
    sba_wait_idle;
    dmi_write(DMI_SBDATA0, 32'h0000CAFE);
    sba_wait_idle;
    dmi_read(DMI_SBADDRESS0);
    chk("D: sbaddress0 after 2 halfword writes", dmi_readval, 32'h81000348);
    sba_read32(32'h81000340);
    chk("D: byte-built word", sba_rdata, 32'h44332211);
    sba_read32(32'h81000344);
    chk("D: halfword-built word", sba_rdata, 32'hCAFEBEEF);

    //--------------------------------------------------------------------
    // E: 16-bit auto-increment reads (readonaddr + readondata)
    //--------------------------------------------------------------------
    sba_cfg(1'b1, 1'b1, 1'b1, 3'd1);
    dmi_write(DMI_SBADDRESS0, 32'h81000344);        // reads 0xBEEF
    sba_wait_idle;
    dmi_read(DMI_SBDATA0);                          // returns 0xBEEF, starts 0x81000346
    chk("E: first halfword", dmi_readval, 32'h0000BEEF);
    sba_wait_idle;
    sba_cfg(1'b0, 1'b0, 1'b1, 3'd1);                // no further read on the next access
    dmi_read(DMI_SBDATA0);
    chk("E: second halfword", dmi_readval, 32'h0000CAFE);
    dmi_read(DMI_SBADDRESS0);
    chk("E: sbaddress0 after 2 halfword reads", dmi_readval, 32'h81000348);

    //--------------------------------------------------------------------
    // F: unmapped address with auto-increment
    //--------------------------------------------------------------------
    sba_clr_err;
    sba_cfg(1'b1, 1'b0, 1'b1, 3'd2);
    dmi_write(DMI_SBADDRESS0, UNMAPPED);            // read
    sba_wait_idle;
    sberr_chk("F: sberror on unmapped read", 3'd2);
    dmi_read(DMI_SBADDRESS0);
    chk("F: sbaddress0 unchanged after failed read", dmi_readval, UNMAPPED);
    sba_clr_err;

    sba_cfg(1'b0, 1'b0, 1'b1, 3'd2);
    dmi_write(DMI_SBADDRESS0, UNMAPPED);
    dmi_write(DMI_SBDATA0, 32'h12345678);           // write
    sba_wait_idle;
    sberr_chk("F: sberror on unmapped write", 3'd2);
    dmi_read(DMI_SBADDRESS0);
    chk("F: sbaddress0 unchanged after failed write", dmi_readval, UNMAPPED);
    sba_clr_err;
    sberr_chk("F: sberror cleared", 3'd0);

    // the walk words the firmware re-reads are still intact
    sba_read32(32'h80008000);
    chk("[0x80008000] before resume", sba_rdata, 32'h80008000 ^ PAT);

    //--------------------------------------------------------------------
    // Release and resume: the firmware re-reads two walk words
    //--------------------------------------------------------------------
    dmi_write(DMI_DATA0, 32'h1);
    dmi_write(DMI_COMMAND, 32'h0023101d);           // x29 = 1
    dmi_read(DMI_ABSTRACTCS);
    chk("abstractcs.cmderr after x29 write", dmi_readval & ACS_CMDERR, 32'h0);
    dm_resume;

    random_irq_enable = 0;
    wait (probes_cpu.x31 === 32'hdeadbeef);
    check_cpu_reg(20, 32'h80008000 ^ PAT);
    check_cpu_reg(21, 32'h81000004 ^ PAT);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

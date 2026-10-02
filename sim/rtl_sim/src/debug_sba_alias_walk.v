//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_sba_alias_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: System Bus Access over the high address bits (bench SRAM alias)
//   debug_interface.md §6 SBA: "sbasize[11:5]=32 (RO)"; "a sbaddress0 write
//   with sbreadonaddr starts a read; a sbdata0 write starts a write";
//   "sberror: ... 2 = address (aRVern maps any AHB HRESP error to 2)".
//   Debug 1.0 sbcs.sberror: "2: A bus error occurred", W1C.
//   Bench (ahb_decoder.v): with sram_x_alias_en = 1 every address >= 0x1000
//   that selects no subordinate reaches the executable SRAM, decoded on its
//   low 16 bits.
//
//   A  alias on. For k = 12..30, addr = (1<<k) | 0x800, except k = 25 ->
//      0x02010800 (above the ACLINT window) and k = 29 -> 0x21000800 (above
//      the ROM window). Per k: 32-bit SBA write of addr ^ PAT, SBA read of
//      addr (readonaddr) returns it, sberror = 0, and the backing SRAM word
//      at (addr & 0xFFFF) holds it. Every k >= 16 lands on SRAM offset 0x800,
//      so each pair is written and read back before the next.
//   B  SBA read of 0x80000800 returns the k = 30 word.
//   C  alias off: write and read of 0x40000800 -> sberror = 2, W1C clears
//      it; SRAM offset 0x800 unchanged.
//   Then the firmware reads [0x80000800] after resume.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define VERY_LONG_TIMEOUT

integer to, k, nerr;
reg [31:0] a, d, last_d, m;

localparam [6:0]  DMI_DATA0      = 7'h04;
localparam [6:0]  DMI_DMCONTROL  = 7'h10;
localparam [6:0]  DMI_ABSTRACTCS = 7'h16;
localparam [6:0]  DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;
localparam [31:0] ACS_CMDERR     = 32'h00000700;

localparam [31:0] PAT            = 32'h5A5AA5A5;
localparam [31:0] UNMAPPED       = 32'h40000800;

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
    $display("|  DEBUG SBA ALIAS WALK: address bits 12..30            |");
    $display(" ======================================================");

    wait (probes_cpu.x31 === 32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;
    sba_clr_err;

    //--------------------------------------------------------------------
    // A: aliased walk, one write/read pair per address bit
    //--------------------------------------------------------------------
    ahb_bus_system_inst.sram_x_alias_en = 1'b1;
    nerr = 0;
    for (k = 12; k < 31; k = k + 1) begin
        if (k == 25)      a = 32'h02010800;
        else if (k == 29) a = 32'h21000800;
        else              a = (32'h1 << k) | 32'h00000800;
        d = a ^ PAT;
        sba_write32(a, d);
        sba_read32(a);
        sba_get_sberr;
        m = ahb_bus_system_inst.sram_x_inst.mem[(a & 32'h0000FFFF) >> 2];
        if ((sba_rdata !== d) || (sba_sberr !== 3'd0) || (m !== d)) begin
            $display("ERROR: A: k=%0d [%h] read %h sberror %0d SRAM[+%h] %h (expected %h, 0) %t ns",
                     k, a, sba_rdata, sba_sberr, a & 32'h0000FFFF, m, d, $time);
            error = error + 1;
            nerr = nerr + 1;
            sba_clr_err;
        end
        last_d = d;
    end
    if (nerr == 0)
        $display("PASS:  A: 19 aliased addresses (bits 12..30) written and read back through SBA %t ns", $time);

    //--------------------------------------------------------------------
    // B: the last word landed in the executable SRAM
    //--------------------------------------------------------------------
    sba_read32(32'h80000800);
    chk("B: SBA read of 0x80000800 (k=30 word)", sba_rdata, last_d);
    sberr_chk("B: sberror", 3'd0);

    //--------------------------------------------------------------------
    // C: alias off -> the same kind of address is unmapped
    //--------------------------------------------------------------------
    ahb_bus_system_inst.sram_x_alias_en = 1'b0;
    sba_write32(UNMAPPED, 32'h12345678);
    sberr_chk("C: sberror on an unmapped write", 3'd2);
    sba_clr_err;
    sberr_chk("C: sberror after W1C", 3'd0);
    sba_read32(UNMAPPED);
    sberr_chk("C: sberror on an unmapped read", 3'd2);
    sba_clr_err;
    sberr_chk("C: sberror after W1C", 3'd0);
    chk("C: SRAM offset 0x800 untouched by the unmapped write",
        ahb_bus_system_inst.sram_x_inst.mem[32'h800 >> 2], last_d);

    //--------------------------------------------------------------------
    // Release and resume: the firmware re-reads 0x80000800
    //--------------------------------------------------------------------
    dmi_write(DMI_DATA0, 32'h1);
    dmi_write(DMI_COMMAND, 32'h0023101d);         // x29 = 1
    dmi_read(DMI_ABSTRACTCS);
    chk("abstractcs.cmderr after x29 write", dmi_readval & ACS_CMDERR, 32'h0);
    dm_resume;

    random_irq_enable = 0;
    wait (probes_cpu.x31 === 32'hdeadbeef);
    check_cpu_reg(20, last_d);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_csr_xepc_xcause_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: XEPC/XCAUSE WARL - trap CSR write/read-back rules
//   mepc/sepc: bit 0 always 0, bit 1 also 0 without C (Priv §3.1.14), all
//   other bits round-trip; mtval/stval full-width round-trip (Priv §3.1.16);
//   mcause/scause keep supported codes (WLRL, Priv §3.1.15), all-ones write
//   does not trap; mtinst/medelegh RAZ/WI; mtval2 MRW with S/U, RAZ/WI
//   without. No access may trap.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)
`define SLOT(idx)       (`SPAD(32'h100) + (idx)*8)

reg [8*24-1:0] pr_name;
reg [31:0]     epc_mask;

// Non-trapping probe: mcause slot untouched, rd as expected
task pr_ok;
   input integer    idx;
   input [31:0]     exp_rd;
   reg   [31:0]     r_cause, r_rd;
   begin
      r_cause = ahb_bus_system_inst.sram_x_inst.mem[`SLOT(idx)+0];
      r_rd    = ahb_bus_system_inst.sram_x_inst.mem[`SLOT(idx)+4];
      if ((r_cause !== 32'hEEEEEEEE) || (r_rd !== exp_rd)) begin
         $display("ERROR: probe %0d (%0s) -- expected no trap, rd=0x%h / got mcause-slot=0x%h rd=0x%h %t ns",
                  idx, pr_name, exp_rd, r_cause, r_rd, $time);
         error = error + 1;
      end else begin
         $display("PASS:  probe %0d (%0s) -- no trap, rd=0x%h", idx, pr_name, r_rd);
      end
   end
endtask

// csrw probe (rd = x0 -> sentinel) followed by csrr probe
task wr_rd;
   input integer    idx;
   input [31:0]     exp_rd;
   begin
      pr_ok(idx,     32'h5A5A5A5A);
      pr_ok(idx + 1, exp_rd);
   end
endtask

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      error_on_exception = 0;
      random_irq_enable  = 0;

      epc_mask = (C_EXTENSION >= 1) ? 32'hFFFFFFFE : 32'hFFFFFFFC;

      wait ((probes_cpu.x31 === 32'hdeadbeef) || (probes_cpu.x31 === 32'h0BADBADB));
      repeat(40) @(posedge free_clk);

      if (probes_cpu.x31 === 32'h0BADBADB) begin
         $display("ERROR: unexpected trap, mcause=0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)], $time);
         error = error + 1;
      end

      $display("");
      $display("--- mepc: IALIGN mask 0x%h (C_EXTENSION=%0d) ---", epc_mask, C_EXTENSION);
      pr_name = "mepc 0xFFFFFFFF";  wr_rd( 0, 32'hFFFFFFFF & epc_mask);
      pr_name = "mepc 0xAAAAAAAA";  wr_rd( 2, 32'hAAAAAAAA & epc_mask);
      pr_name = "mepc 0x55555555";  wr_rd( 4, 32'h55555555 & epc_mask);

      $display("--- mtval: full-width round trip ---");
      pr_name = "mtval 0xFFFFFFFF"; wr_rd( 6, 32'hFFFFFFFF);
      pr_name = "mtval 0xAAAAAAAA"; wr_rd( 8, 32'hAAAAAAAA);
      pr_name = "mtval 0x55555555"; wr_rd(10, 32'h55555555);

      $display("--- mcause: supported codes read back ---");
      pr_name = "mcause 0x0000000B"; wr_rd(12, 32'h0000000B);
      pr_name = "mcause 0x80000007"; wr_rd(14, 32'h80000007);
      pr_name = "mcause 0x8000001F"; wr_rd(16, 32'h8000001F);
      pr_name = "mcause 0x00000002"; wr_rd(18, 32'h00000002);
      pr_name = "mcause all-ones w"; pr_ok(20, 32'h5A5A5A5A);
      pr_name = "mcause 0x80000003"; wr_rd(21, 32'h80000003);

      $display("--- mtinst / medelegh: RAZ/WI ---");
      pr_name = "mtinst w all-ones"; pr_ok(23, 32'h5A5A5A5A);
      pr_name = "mtinst r";          pr_ok(24, 32'h00000000);
      pr_name = "mtinst csrrw";      pr_ok(25, 32'h00000000);
      pr_name = "medelegh";          wr_rd(26, 32'h00000000);

      $display("--- mtval2 (SU_MODE_EN=%0d) ---", SU_MODE_EN);
      pr_name = "mtval2 0xA5A5A5A5"; wr_rd(28, (SU_MODE_EN != 0) ? 32'hA5A5A5A5 : 32'h00000000);

      if (SU_MODE_EN != 0) begin
         $display("--- sepc: IALIGN mask 0x%h ---", epc_mask);
         pr_name = "sepc 0xFFFFFFFF";  wr_rd(30, 32'hFFFFFFFF & epc_mask);
         pr_name = "sepc 0xAAAAAAAA";  wr_rd(32, 32'hAAAAAAAA & epc_mask);
         pr_name = "sepc 0x55555555";  wr_rd(34, 32'h55555555 & epc_mask);

         $display("--- stval: full-width round trip ---");
         pr_name = "stval 0xFFFFFFFF"; wr_rd(36, 32'hFFFFFFFF);
         pr_name = "stval 0xAAAAAAAA"; wr_rd(38, 32'hAAAAAAAA);
         pr_name = "stval 0x55555555"; wr_rd(40, 32'h55555555);

         $display("--- scause: supported codes read back ---");
         pr_name = "scause 0x80000009"; wr_rd(42, 32'h80000009);
         pr_name = "scause 0x00000008"; wr_rd(44, 32'h00000008);
         pr_name = "scause 0x8000001F"; wr_rd(46, 32'h8000001F);
         pr_name = "scause all-ones w"; pr_ok(48, 32'h5A5A5A5A);
         pr_name = "scause 0x80000001"; wr_rd(49, 32'h80000001);
      end

      $display("");
      check_mem_value(`SPAD(32'h00), 32'd0);           // no trap at all
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

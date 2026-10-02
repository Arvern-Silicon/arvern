//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_marv_cfg
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: marv_cfg (0xFFF) -- every field checked against its parameter
//
//   Each field is compared INDIVIDUALLY so a failure names the field rather
//   than printing a 32-bit mismatch. A whole-word compare would pass just as
//   often and tell you nothing about which parameter was mis-wired.
//
//   Runs across the RTL sweep, so the level fields are exercised at more than
//   one value -- which is what would have caught the old Zbc gap, where
//   B_EXTENSION=3 and =4 produced identical bits.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] cfg, imp, cfg_after;
reg [31:0] exp_mul, exp_div;

task chk;                                   // one field, named
   input [255:0] name;
   input  [31:0] got;
   input  [31:0] want;
   begin
      if (got !== want) begin
         $display("ERROR: marv_cfg.%0s = %0d, expected %0d %t ns", name, got, want, $time);
         error = error + 1;
      end else begin
         $display("PASS:  marv_cfg.%0s = %0d %t ns", name, got, $time);
      end
   end
endtask

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      cfg       = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      imp       = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
      cfg_after = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];

      $display("");
      $display(" ====================================================================");
      $display("|   marv_cfg (0xFFF) = 0x%h                                   |", cfg);
      $display(" ====================================================================");
      $display("");

      // mul/div type encodings mirror arv_csr_ids.v
      exp_mul = (MUL_TYPE == 1) ? 32'd1 : (MUL_TYPE == 2) ? 32'd2 : (MUL_TYPE == 3) ? 32'd3 : 32'd0;
      exp_div = (DIV_TYPE == 1) ? 32'd1 : (DIV_TYPE == 2) ? 32'd2 : (DIV_TYPE == 3) ? 32'd3 : 32'd0;
      if (M_EXTENSION == 0) begin exp_mul = 32'd0; exp_div = 32'd0; end
      if (M_EXTENSION == 1) begin                  exp_div = 32'd0; end   // Zmmul: no divider

      //---------------- fields, one at a time ----------------
      chk("C_EXTENSION",         (cfg >> 24) & 32'h7,  C_EXTENSION);
      chk("B_EXTENSION",         (cfg >> 20) & 32'h7,  B_EXTENSION);
      chk("mul_type",            (cfg >> 18) & 32'h3,  exp_mul);
      chk("div_type",            (cfg >> 16) & 32'h3,  exp_div);
      chk("ZIHPM_NR",            (cfg >> 12) & 32'hF,  ZIHPM_NR);
      chk("DM_TRIGGER_NR",       (cfg >>  8) & 32'hF,  DEBUG_EN ? DM_TRIGGER_NR : 0);
      // marv_cfg[7:6] encodes the WRITABLE entry count, not a boolean: 16 entries
      // always exist architecturally and the surplus are read-only zero.
      chk("PMP_NR",              (cfg >>  6) & 32'h3,
          (PMP_NR == 16) ? 32'd3 : (PMP_NR == 8) ? 32'd2 : (PMP_NR == 4) ? 32'd1 : 32'd0);
      chk("SINGLE_CYCLE_BRANCH", (cfg >>  5) & 32'h1,  SINGLE_CYCLE_BRANCH);
      chk("ASYNC_RST_EN",        (cfg >>  4) & 32'h1,  ASYNC_RST_EN);
      chk("ZICNTR_EN",           (cfg >>  3) & 32'h1,  ZICNTR_EN);
      chk("SU_MODE_EN",          (cfg >>  2) & 32'h1,  SU_MODE_EN);
      chk("DEBUG_EN",            (cfg >>  1) & 32'h1,  DEBUG_EN);
      chk("CCSR_EN",             (cfg      ) & 32'h1,  CCSR_EN);

      //---------------- reserved bits must read zero ----------------
      // [27] and [23] are the C / B growth bits, which sit ABOVE the field they
      // extend.
      $display("");
      chk("rsvd[31:28]",(cfg >> 28) & 32'hF, 32'd0);
      chk("rsvd[27]",   (cfg >> 27) & 32'h1, 32'd0);
      chk("rsvd[23]",   (cfg >> 23) & 32'h1, 32'd0);

      //---------------- mimpid carries version ONLY ----------------
      $display("");
      $display("--- mimpid = 0x%h : version only, no configuration ---", imp);
      if ((imp & 32'h000000FF) !== 32'h0) begin
         $display("ERROR: mimpid[7:0] must be reserved-zero, got 0x%h %t ns", imp & 32'hFF, $time);
         error = error + 1;
      end else $display("PASS:  mimpid[7:0] reserved zero %t ns", $time);

      if (imp[31:8] === 24'h000000) begin
         $display("ERROR: mimpid version field is zero -- RTL_VERSION not plumbed %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  mimpid = v%0d.%0d.%0d %t ns",
                  imp[31:24], imp[23:16], imp[15:8], $time);
      end

      //---------------- read-only ----------------
      $display("");
      $display("--- marv_cfg is read-only: a write must not change it ---");
      if (cfg_after !== cfg) begin
         $display("ERROR: marv_cfg changed from 0x%h to 0x%h after a write %t ns", cfg, cfg_after, $time);
         error = error + 1;
      end else $display("PASS:  marv_cfg unchanged after an attempted write %t ns", $time);

      //=================================================================
      // END OF TEST
      //=================================================================
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

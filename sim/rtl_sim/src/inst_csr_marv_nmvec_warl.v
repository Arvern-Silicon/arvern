//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_marv_nmvec_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: marv_nmvec (0x7FD) -- RNMI vector CSR
//   A  reset value == reset_vector + 4 (checked as a relationship, not a
//      hardcoded address)
//   B  the UNWRITTEN vector is used: RNMI #1 lands at reset_vector+4
//   C  WARL round trip; [1:0] read back zero
//   D  a written vector relocates delivery: RNMI #2 lands elsewhere
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] nmvec_rst, rstvec, alt_addr, rb, rb_align;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|        marv_nmvec (0x7FD): RNMI vector CSR                         |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE A -- reset value is reset_vector + 4
      //=================================================================
      nmvec_rst = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      rstvec    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
      alt_addr  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];

      $display("--- reset value: marv_nmvec == reset_vector + 4 ---");
      $display("    reset_vector = 0x%h   marv_nmvec = 0x%h", rstvec, nmvec_rst);
      if (nmvec_rst !== (rstvec + 32'd4)) begin
         $display("ERROR: marv_nmvec reset 0x%h, expected 0x%h %t ns",
                  nmvec_rst, rstvec + 32'd4, $time);
         error = error + 1;
      end else $display("PASS:  marv_nmvec resets one slot past the reset entry %t ns", $time);

      //=================================================================
      // PHASE B -- the UNWRITTEN vector is the one actually used
      //=================================================================
      repeat(10) @(posedge free_clk);
      @(negedge free_clk);  nmi = 1'b1;
      repeat(2) @(negedge free_clk);  nmi = 1'b0;

      @(probes_cpu.x31 == 32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- RNMI #1 delivered through the UNTOUCHED reset vector ---");
      check_mem_value(`SPAD(32'h10), 32'h00000001);   // rnmi_handler ran
      check_mem_value(`SPAD(32'h14), 32'h00000000);   // alt handler did not

      //=================================================================
      // PHASE C -- WARL
      //=================================================================
      @(probes_cpu.x31 == 32'h33333333);
      repeat(3) @(posedge free_clk);

      rb       = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
      rb_align = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

      $display("");
      $display("--- round trip: written value reads back exactly ---");
      if (rb !== alt_addr) begin
         $display("ERROR: wrote 0x%h, read 0x%h %t ns", alt_addr, rb, $time);
         error = error + 1;
      end else $display("PASS:  marv_nmvec = 0x%h %t ns", rb, $time);

      $display("");
      $display("--- [1:0] are read-only zero (wrote value|3) ---");
      if (rb_align !== (alt_addr & 32'hFFFFFFFC)) begin
         $display("ERROR: misaligned write read back 0x%h, expected 0x%h %t ns",
                  rb_align, alt_addr & 32'hFFFFFFFC, $time);
         error = error + 1;
      end else $display("PASS:  low bits dropped, reads 0x%h %t ns", rb_align, $time);

      //=================================================================
      // PHASE D -- a written vector relocates delivery
      //=================================================================
      repeat(10) @(posedge free_clk);
      @(negedge free_clk);  nmi = 1'b1;
      repeat(2) @(negedge free_clk);  nmi = 1'b0;

      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- RNMI #2 delivered to the WRITTEN vector, not the reset one ---");
      check_mem_value(`SPAD(32'h14), 32'h00000001);   // alt handler ran
      check_mem_value(`SPAD(32'h10), 32'h00000001);   // original did NOT run again

      //=================================================================
      // END OF TEST
      //=================================================================
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_reset_vector
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: reset-vector read-only CSR (0xFFE).
//
//   The TB drives reset_vector_i = 0x20000000 (see tb_arvern.v). Firmware reads
//   the 0xFFE CSR and also captures its reset PC via auipc; this TB checks both
//   equal the driven reset vector.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

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

      $display("");
      $display(" ====================================================================");
      $display("|              RESET-VECTOR READ-ONLY CSR (0xFFE)                    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- reset_vector CSR (0xFFE) readback ---");
      check_mem_value(`SPAD(32'h00), 32'h20000000);   // must equal driven reset_vector_i

      $display("");
      $display("--- auipc-derived reset PC (cross-check) ---");
      check_mem_value(`SPAD(32'h04), 32'h20000000);   // reset entry PC == reset vector

      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_slli_hint
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.SLLI rd=0  (RVC HINT space)
//   Three rd=0 C.SLLI variants — all are RVC HINTs and MUST NOT trap.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

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
      $display(" PHASE 1: init");
      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      $display("");
      $display(" PHASE 2: c.slli x0, 0  (HINT, must NOT trap)");
      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // still no trap
      check_mem_value(`SPAD(32'h08), 32'h00000001);   // progress marker


      $display("");
      $display(" PHASE 3: c.slli x0, 1  (HINT, must NOT trap)");
      wait(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000002);


      $display("");
      $display(" PHASE 4: c.slli x0, 16  (HINT, must NOT trap)");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000003);


      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

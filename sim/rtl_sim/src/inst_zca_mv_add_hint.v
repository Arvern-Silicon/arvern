//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_mv_add_hint
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: C.MV / C.ADD rd=0  (RVC HINT space)
//   Four rd=0 variants — all are RVC HINTs and MUST NOT trap:
//   - c.mv  x0, x10
//   - c.mv  x0, x11
//   - c.add x0, x10
//   - c.add x0, x11
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
      check_mem_value(`SPAD(32'h00), 32'h00000000);    // no trap
      check_cpu_reg(10, 32'hCAFEBABE);                  // a0 seed
      check_cpu_reg(11, 32'hDEADC0DE);                  // a1 seed


      $display("");
      $display(" PHASE 2: c.mv x0, x10  (HINT, must NOT trap; x0 stays 0)");
      wait(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000001);
      check_cpu_reg(0, 32'h00000000);


      $display("");
      $display(" PHASE 3: c.mv x0, x11  (HINT, must NOT trap; x0 stays 0)");
      wait(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000002);
      check_cpu_reg(0, 32'h00000000);


      $display("");
      $display(" PHASE 4: c.add x0, x10  (HINT, must NOT trap; x0 stays 0)");
      wait(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000003);
      check_cpu_reg(0, 32'h00000000);


      $display("");
      $display(" PHASE 5: c.add x0, x11  (HINT, must NOT trap; x0 stays 0)");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000004);
      check_cpu_reg(0, 32'h00000000);


      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

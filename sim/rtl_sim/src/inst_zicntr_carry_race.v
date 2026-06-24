//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_carry_race
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: COUNTER CARRY RACE
//   integer ii;
//   integer jj;
//   integer kk;
//   integer ahb_master;
//   integer allow_peripheral_accesses;
//
//   `define SPAD(byte_off)  (byte_off/4)
//
//   initial
//   begin
//   @(posedge free_clk);
//   @(posedge hresetn);
//
//   @(negedge free_clk);
//   force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
//   force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
//   @(negedge free_clk);
//   release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
//   release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;
//
//   error_on_exception = 0;
//
//
//   $display(" PHASE 1: init");
//   wait(probes_cpu.x31 == 32'h11111111);
//   repeat(3) @(posedge free_clk);
//
//
//   $display(" PHASE 2: minstret carry race");
//   wait(probes_cpu.x31 == 32'h22222222);
//   repeat(3) @(posedge free_clk);
//   $display("--- minstreth after csrw minstret @ lo=0xFFFFFFFF (expect 0 post-fix; 1 pre-fix) ---");
//   check_mem_value(`SPAD(32'h00), 32'h00000000);
//
//
//   $display(" PHASE 3: mcycle carry race");
//   wait(probes_cpu.x31 == 32'hdeadbeef);
//   repeat(3) @(posedge free_clk);
//   $display("--- mcycleh after csrw mcycle @ lo=0xFFFFFFFF (expect 0 post-fix; 1 pre-fix) ---");
//   check_mem_value(`SPAD(32'h04), 32'h00000000);
//
//
//   repeat(20) @(posedge free_clk);
//   stimulus_done = 1;
//   end
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


      $display(" PHASE 1: init");
      wait(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);


      $display(" PHASE 2: minstret carry race");
      wait(probes_cpu.x31 == 32'h22222222);
      repeat(3) @(posedge free_clk);
      $display("--- minstreth after csrw minstret @ lo=0xFFFFFFFF (expect 0 post-fix; 1 pre-fix) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      $display(" PHASE 3: mcycle carry race");
      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);
      $display("--- mcycleh after csrw mcycle @ lo=0xFFFFFFFF (expect 0 post-fix; 1 pre-fix) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);


      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

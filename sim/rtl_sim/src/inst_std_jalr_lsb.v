//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_jalr_lsb
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: JALR LSB-CLEAR (no misalign exception)
//   Pass criteria:
//   - trap_count == 0  (a set bit[0] in (rs1+imm) must NOT fault)
//   - every masked target was reached (proof markers x18..x22 == 1)
//   - link registers correct for JALR/C.JALR phases (x23,x24,x26,x25 == 1)
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

      // No trap is expected, but install the relaxed policy so that a
      // (buggy) misaligned-fetch trap is captured rather than aborting
      // the run -- the non-zero trap_count check below will flag it.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init
      //=================================================================
      $display("");
      $display(" PHASE 1: init");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // trap_count = 0


      //=================================================================
      // PHASE 2: JALR rs1=func2|1, imm=0 -> masked target, link in ra
      //=================================================================
      $display("");
      $display(" PHASE 2: JALR (func2|1)+0  -> mask LSB");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // STILL no trap
      check_cpu_reg(18, 32'h00000001);                // reached masked target
      check_cpu_reg(23, 32'h00000001);                // link register correct


      //=================================================================
      // PHASE 3: JALR rs1=func3, imm=1 -> masked target, link in ra
      //=================================================================
      $display("");
      $display(" PHASE 3: JALR func3 + 1  -> mask LSB");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_cpu_reg(19, 32'h00000001);                // reached masked target
      check_cpu_reg(24, 32'h00000001);                // link register correct


      //=================================================================
      // PHASE 4: JALR rs1=func4_base, imm=+5 -> (base+5)&~1 = func4
      //=================================================================
      $display("");
      $display(" PHASE 4: JALR func4_base + 5  -> mask LSB");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_cpu_reg(20, 32'h00000001);                // reached masked target
      check_cpu_reg(26, 32'h00000001);                // link register correct


      //=================================================================
      // PHASE 5: C.JR with odd rs1 -> masked target (no link)
      //=================================================================
      $display("");
      $display(" PHASE 5: C.JR (func5|1)  -> mask LSB");
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_cpu_reg(21, 32'h00000001);                // reached masked target


      //=================================================================
      // PHASE 6: C.JALR with odd rs1 -> masked target, link in ra
      //=================================================================
      $display("");
      $display(" PHASE 6: C.JALR (func6|1)  -> mask LSB");
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      // FINAL: absolutely no trap may have occurred anywhere.
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // trap_count == 0
      check_cpu_reg(22, 32'h00000001);                // reached masked target
      check_cpu_reg(25, 32'h00000001);                // link register correct


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

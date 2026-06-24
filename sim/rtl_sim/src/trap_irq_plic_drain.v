//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_plic_drain
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PLIC pending-set drain ordering (4 sources, strict priority)
//   Four sources are asserted together; the PLIC must claim them in
//   descending priority order (4 first, then 3, then 2, then 1). The
//   handler logs each claimed ID; the testbench verifies the log against
//   the expected sequence.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

// Auto-drop: handler stores claimed ID at scratchpad[0x80]; TB drops the
// matching source line.
always @(posedge free_clk) begin
   case (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h80)])
      32'd1   : plic_irq_src[1] <= 1'b0;
      32'd2   : plic_irq_src[2] <= 1'b0;
      32'd3   : plic_irq_src[3] <= 1'b0;
      32'd4   : plic_irq_src[4] <= 1'b0;
      default : ;
   endcase
end

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
      use_plic           = 1'b1;


      //=================================================================
      // PHASE 1: PLIC configured
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|         PHASE 1: PLIC CONFIGURED (4 sources, pri 1/3/5/7)          |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: assert all 4 sources together, expect drain in pri order
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|         PHASE 2: 4 sources asserted -> drain in priority order     |");
      $display(" ====================================================================");
      $display("Asserting plic_irq_src[1..4]; expected claim order = 4,3,2,1");

      // Assert all four at the SAME posedge so pending latches them together.
      plic_irq_src[1] = 1'b1;
      plic_irq_src[2] = 1'b1;
      plic_irq_src[3] = 1'b1;
      plic_irq_src[4] = 1'b1;

      @(probes_cpu.x31==32'h44444444);
      repeat(5) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000004);   // 4 traps fired
      check_mem_value(`SPAD(32'h20), 32'h00000004);   // claim_log[0] = 4 (pri 7)
      check_mem_value(`SPAD(32'h24), 32'h00000003);   // claim_log[1] = 3 (pri 5)
      check_mem_value(`SPAD(32'h28), 32'h00000002);   // claim_log[2] = 2 (pri 3)
      check_mem_value(`SPAD(32'h2C), 32'h00000001);   // claim_log[3] = 1 (pri 1)
      $display("PASS:  4-deep pending set drained in strict priority order %t ns",
               $time);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

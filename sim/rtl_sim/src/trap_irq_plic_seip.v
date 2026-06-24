//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_plic_seip
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PLIC -> S-mode external IRQ (delegated SEI via PLIC ctx 1)
//   Firmware drops to S-mode, testbench asserts plic_irq_src[1]; the PLIC's
//   S-context (ctx 1) drives irq_s_external_o, which the core takes as a
//   delegated SEI trap (SCAUSE = 0x80000009). The S-handler reads the
//   ctx-1 claim register and writes complete.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

// Auto-drop the PLIC source whose ID is written to scratchpad[0x80] by the
// trap handler (only source 1 used by this test).
always @(posedge free_clk) begin
   if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h80)] == 32'd1)
      plic_irq_src[1] <= 1'b0;
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
      use_plic = 1'b1;


      //=================================================================
      // PHASE 1: PLIC ctx 1 configured + delegation set + jumping to S
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|     PHASE 1: PLIC ctx 1 PROGRAMMED, DELEGATION SET, MRET TO S      |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: S-mode running, assert source -> SEI trap delegated
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|         PHASE 2: SEI VIA PLIC ctx 1 (S-MODE HANDLER)               |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h21212121);
      repeat(3) @(posedge free_clk);

      $display("Asserting plic_irq_src[1] -- PLIC ctx 1 should fire irq_s_external...");
      plic_irq_src[1] = 1'b1;

      @(probes_cpu.x31==32'h44444444);
      repeat(5) @(posedge free_clk);

      $display("");
      $display("--- Trap count + SCAUSE + claim ID ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // s_trap_count = 1
      check_mem_value(`SPAD(32'h04), 32'h80000009);   // SCAUSE = SEI
      check_mem_value(`SPAD(32'h0C), 32'h00000001);   // claimed ID = 1
      $display("PASS:  PLIC -> S-mode delegated SEI loop closed %t ns", $time);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

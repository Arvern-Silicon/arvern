//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_plic_threshold
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PLIC threshold gating
//   Three phases, each with the source held high long enough for any
//   wrongly-fired IRQ to be observed:
//     Phase 2: priority == threshold (== 5)            -> NO trap
//     Phase 3: priority <  threshold (5 <  7)          -> NO trap
//     Phase 4: priority >  threshold (5 >  4)          -> trap fires
//
//   Firmware writes 0xBADBAD0N to x31 if it observes an unexpected trap
//   during phases 2 or 3; the testbench treats that as a failure marker.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

// Auto-drop the PLIC source whose ID is written to scratchpad[0x80] by
// the trap handler. Only source 1 is used by this test.
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
      // PHASE 1: PLIC configured (priority=5, threshold=5)
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: PLIC CONFIGURED                           |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: priority == threshold (5 == 5) -> NO trap
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|         PHASE 2: priority == threshold (5 == 5) -> NO TRAP         |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h21212121);
      repeat(3) @(posedge free_clk);

      $display("Asserting plic_irq_src[1] -- threshold gate should mask IRQ...");
      plic_irq_src[1] = 1'b1;

      // Firmware delay (~700 cycles) + checks trap_count then advances.
      // We just wait for the advance and confirm we never entered the handler.
      @(probes_cpu.x31==32'h22222222);
      plic_irq_src[1] = 1'b0;
      repeat(5) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);  // trap_count still 0
      $display("PASS:  Phase 2 - no MEI trap with priority == threshold %t ns", $time);


      //=================================================================
      // PHASE 3: priority < threshold (5 < 7) -> NO trap
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|         PHASE 3: priority < threshold  (5 <  7) -> NO TRAP         |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h31313131);
      repeat(3) @(posedge free_clk);

      plic_irq_src[1] = 1'b1;

      @(probes_cpu.x31==32'h33333333);
      plic_irq_src[1] = 1'b0;
      repeat(5) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);  // still 0
      $display("PASS:  Phase 3 - no MEI trap with priority < threshold %t ns", $time);


      //=================================================================
      // PHASE 4: priority > threshold (5 > 4) -> TRAP
      //   Source is NOT re-asserted: phase 3 left pending[1]=1 in the
      //   gateway (level drop does not clear pending), so lowering the
      //   threshold to 4 immediately unmasks the pending source and the
      //   IRQ fires.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|         PHASE 4: priority > threshold  (5 >  4) -> TRAP            |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h41414141);

      @(probes_cpu.x31==32'h44444444);
      repeat(5) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);  // trap fired
      check_mem_value(`SPAD(32'h04), 32'h8000000B);  // MCAUSE = MEI
      check_mem_value(`SPAD(32'h0C), 32'h00000001);  // claimed ID = 1
      $display("PASS:  Phase 4 - MEI trap fired with priority > threshold %t ns", $time);


      // Sentinel: if firmware caught an unexpected trap it would have
      // written 0xBADBAD0N to x31 and reached this state; flag it.
      if (probes_cpu.x31 == 32'hBADBAD02 ||
          probes_cpu.x31 == 32'hBADBAD03) begin
         $display("ERROR: firmware saw an unexpected trap (x31=0x%h) %t ns",
                  probes_cpu.x31, $time);
         error = error + 1;
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

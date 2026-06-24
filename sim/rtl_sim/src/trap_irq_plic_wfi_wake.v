//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_plic_wfi_wake
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PLIC wakes the core out of WFI sleep
//   When the firmware reaches the WFI, the testbench delays a few cycles
//   to let the core actually enter sleep, then asserts plic_irq_src[1].
//   The PLIC's clock-enable includes `|irq_src_i`, so the source rising
//   re-opens the SoC clock; the gateway latches pending, target fires,
//   core wakes, MEI trap is taken, handler claims/completes.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

// Drop the PLIC source line when the handler stores the claimed ID at
// scratchpad[0x80] (this test only ever claims source 1).
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
      use_plic           = 1'b1;


      //=================================================================
      // PHASE 1: PLIC configured
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: PLIC CONFIGURED, MIE/MEIE ARMED               |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: firmware executes WFI; assert source after a delay
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 2: WFI -> PLIC SOURCE -> WAKE + TRAP             |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h21212121);

      // Generous delay so the core fully enters WFI sleep and dut_hclk
      // gates off before the source asserts.
      repeat(20) @(posedge free_clk);

      $display("Asserting plic_irq_src[1] -- expect core to wake from WFI...");
      plic_irq_src[1] = 1'b1;


      //=================================================================
      // PHASE 3: post-wake checks
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 3: post-wake verification                        |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h44444444);
      repeat(5) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);   // 1 trap
      check_mem_value(`SPAD(32'h04), 32'h8000000B);   // MCAUSE = MEI
      check_mem_value(`SPAD(32'h0C), 32'h00000001);   // claimed ID = 1
      $display("PASS:  WFI -> PLIC wake -> MEI trap -> mainline resumed %t ns",
               $time);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

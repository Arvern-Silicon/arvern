//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_triple
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IRQ TRIPLE
//   Verify 3 simultaneous interrupts (software+timer+external) are handled
//   in RISC-V priority order: External(11) > Timer(7) > Software(3).
//
//   IRQ signals are driven simultaneously by this testbench stimulus.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  (byte_off/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Disable error-on-exception (interrupts trigger exception monitors)
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Verify scratchpad is zeroed (trap_count should be 0)
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      // Check callee-saved registers
      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: Assert all 3 IRQs simultaneously
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: THREE SIMULTANEOUS INTERRUPTS             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      repeat(5) @(posedge free_clk);

      // Assert all 3 interrupts simultaneously
      irq_m_timer    = 1'b1;
      irq_m_software = 1'b1;
      irq_m_external = 1'b1;

      // Wait for firmware to handle all 3 and signal done
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Deassert all 3
      irq_m_timer    = 1'b0;
      irq_m_software = 1'b0;
      irq_m_external = 1'b0;

      // Check trap_count = 3
      $display("");
      $display("--- Trap count verification ---");
      check_mem_value(`SPAD(32'h00), 32'h00000003);


      //=================================================================
      // PHASE 3: Verify priority order
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: VERIFY PRIORITY ORDER                     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Verify 1st handled = External (0x8000000B) -- highest priority
      $display("");
      $display("--- 1st interrupt (highest priority: External) ---");
      check_mem_value(`SPAD(32'h54), 32'h8000000B);

      // Verify 2nd handled = Software (0x80000003) -- spec priority: MEI > MSI > MTI
      $display("");
      $display("--- 2nd interrupt (Software) ---");
      check_mem_value(`SPAD(32'h58), 32'h80000003);

      // Verify 3rd handled = Timer (0x80000007) -- lowest priority
      $display("");
      $display("--- 3rd interrupt (lowest priority: Timer) ---");
      check_mem_value(`SPAD(32'h5C), 32'h80000007);

      // Summarize priority order (RISC-V spec 3.1.9: MEI > MSI > MTI)
      $display("");
      $display("--- Priority order summary ---");
      begin : check_priority_order
         reg [31:0] mc1, mc2, mc3;
         mc1 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)];
         mc2 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h58)];
         mc3 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h5C)];

         if (mc1 == 32'h8000000B && mc2 == 32'h80000003 && mc3 == 32'h80000007) begin
            $display("PASS:  Correct priority order: External(0x%h) > Software(0x%h) > Timer(0x%h) %t ns", mc1, mc2, mc3, $time);
         end else begin
            $display("ERROR: Wrong priority order -- got: 0x%h, 0x%h, 0x%h (expected 0x8000000B, 0x80000003, 0x80000007) %t ns", mc1, mc2, mc3, $time);
            error = error + 1;
         end
      end


      // Check callee-saved registers preserved after 3 interrupts
      $display("");
      $display("--- Callee-saved registers after 3 interrupts ---");
      check_cpu_reg(18, 32'hAAAAAAAA);   // s2
      check_cpu_reg(19, 32'hBBBBBBBB);   // s3
      check_cpu_reg(20, 32'hCCCCCCCC);   // s4
      check_cpu_reg(21, 32'hDDDDDDDD);   // s5
      check_cpu_reg(22, 32'hEEEEEEEE);   // s6


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

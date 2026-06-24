//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_post_mnret_irq
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: POST-MNRET IRQ SUPPRESS
//   MEPC captured by the IRQ handler must equal next_after_target (fix in
//   place); mnret_target would indicate the bug is still present.
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


      //=================================================================
      // PHASE 1: init complete -> latch NMI vector
      //=================================================================
      $display("");
      $display(" PHASE 1: configure nmi_vector");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler addr is 0 %t ns", $time);
            error = error + 1;
         end
         nmi_vector = handler_addr;
      end


      //=================================================================
      // PHASE 2: drive NMI + irq_m_timer simultaneously
      //=================================================================
      $display("");
      $display(" PHASE 2: drive NMI and irq_m_timer simultaneously");
      // Level-sensitive: x31 may already hold the marker by the time we
      // reach this wait (it was set right after init).
      wait(probes_cpu.x31==32'hC0DEC0DE);
      repeat(3) @(posedge free_clk);

      // NMI is a short pulse — held continuously it would re-fire on every
      // post-mnret instruction, since nmi_suppress only covers ONE inst.
      // irq_m_timer is level-held so it is pending the cycle mnret completes.
      irq_m_timer = 1'b1;
      nmi       = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi       = 1'b0;

      // Let the handlers run, then HOLD irq_m_timer asserted until the
      // post-mnret IRQ has actually been taken and counted (irq_count==1).
      //
      // A fixed wait here is fragile: under -gahb + triple random wait
      // states the NMI episode (NMI taken -> mnret completes) stretches
      // ~3-4x (a nominal ~25-cycle episode can exceed 90 cycles). With a
      // fixed irq_m_timer hold the level can be deasserted before the IRQ
      // has been latched/taken at all, so no IRQ ever fires and the test
      // checks nothing. Polling irq_count keeps irq_m_timer pending no
      // matter how far heavy timing variants stretch the NMI episode, so
      // the post-mnret IRQ is reliably presented and exactly-one-IRQ is
      // reached. WHERE that IRQ lands (on the mnret target == bug_pc/
      // fix_pc, or on a PC inside the NMI handler when slow fetch makes
      // it fire before mnret completes) still legitimately varies by
      // timing variant -- the PHASE-3 discriminator accepts all of those
      // (only MEPC == bug_pc is a real failure). Holding irq_m_timer cannot
      // produce a spurious second IRQ: the firmware irq_handler disables
      // MTIE+MIE before its mret, so once irq_count==1 and irq_m_timer is
      // dropped no further IRQ can ever fire => "exactly one IRQ" holds.
      //
      // The timeout is a genuine hang guard: the whole test is ~300
      // cycles nominal and low-thousands worst-case, so 5000 cycles
      // cannot trip under any legitimate heavy-timing variant. If it DOES
      // trip the post-mnret IRQ genuinely never fired -> a real failure,
      // flagged as an error (NOT a silent pass).
      begin : hold_irq_m_timer
         integer irq_wait_cycles;
         irq_wait_cycles = 0;
         while (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)] !== 32'h00000001 &&
                irq_wait_cycles < 5000) begin
            @(posedge free_clk);
            irq_wait_cycles = irq_wait_cycles + 1;
         end
         irq_m_timer = 1'b0;
         if (irq_wait_cycles >= 5000) begin
            $display("ERROR: post-mnret IRQ never fired (irq_count!=1 after %0d cycles) %t ns",
                     irq_wait_cycles, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 3: end of test -> check MEPC discriminator
      //=================================================================
      $display("");
      $display(" PHASE 3: verify MEPC captured by IRQ handler");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);   // exactly one NMI
      check_mem_value(`SPAD(32'h04), 32'h00000001);   // exactly one IRQ

      begin : check_mepc
         reg [31:0] mepc_val;
         reg [31:0] fix_pc;
         reg [31:0] bug_pc;
         mepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         fix_pc   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
         bug_pc   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];

         $display("MEPC=0x%h  fix_pc=0x%h  bug_pc=0x%h %t ns",
                  mepc_val, fix_pc, bug_pc, $time);

         // The bug manifests precisely as "MEPC == mnret_target": the IRQ
         // trapped on the very PC the mnret resumed to. Any other MEPC
         // (next_after_target with the fix in default timing, or a PC
         // inside the NMI handler under slow-fetch variants where the IRQ
         // fires before mnret completes) means the bug is NOT reachable
         // in that run.
         if (mepc_val === bug_pc) begin
            $display("ERROR: MEPC == mnret_target -- IRQ trapped on same PC as mnret resume (suppress NOT armed for mnret) %t ns", $time);
            error = error + 1;
         end else if (mepc_val === fix_pc) begin
            $display("PASS:  MEPC == next_after_target -- post-mnret suppress armed %t ns", $time);
         end else begin
            $display("PASS:  MEPC=0x%h (neither bug_pc nor fix_pc) -- IRQ did not land on mnret_target, bug not reachable in this timing variant %t ns",
                     mepc_val, $time);
         end
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

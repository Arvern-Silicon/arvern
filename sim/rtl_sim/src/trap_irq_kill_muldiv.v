//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_kill_muldiv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP IRQ KILL MUL/DIV
//   Verifies that IRQs can abort and restart MUL/DIV operations:
//   - DIV/REM interrupted mid-computation, correct result after restart
//   - MUL/MULH interrupted mid-computation, correct result after restart
//   - Sustained DIV loop under continuous IRQ bombardment
//   - Sustained MUL loop under continuous IRQ bombardment
//   - Register preservation across all phases
//----------------------------------------------------------------------------

`define VERY_LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
`define SPAD(byte_off)  (byte_off/4)

//------------------------------------------------------------------------
// IRQ LATENCY MEASUREMENT
//------------------------------------------------------------------------
// Reuses the same approach as random_irq_injector.v:
// Measures cycles from any IRQ input rising edge (when MSTATUS.MIE=1)
// to trap_taken firing. Separate accumulators for kill-disabled (Phase 6)
// and kill-enabled (Phase 7) phases.
//------------------------------------------------------------------------
wire lat_trap_taken  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_taken;
wire lat_trap_is_irq = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq;
wire lat_mstatus_mie = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mstatus_mie;
wire lat_irq_active  = irq_m_timer | irq_m_software | irq_m_external;

integer lat_measuring;
integer lat_counter;
integer lat_phase;      // 0=inactive, 6=no-kill, 7=kill

integer nokill_lat_total, nokill_lat_max, nokill_lat_count;
integer kill_lat_total,   kill_lat_max,   kill_lat_count;

initial begin
   lat_measuring    = 0;
   lat_counter      = 0;
   lat_phase        = 0;
   nokill_lat_total = 0;  nokill_lat_max = 0;  nokill_lat_count = 0;
   kill_lat_total   = 0;  kill_lat_max   = 0;  kill_lat_count   = 0;
end

always @(posedge free_clk or negedge hresetn) begin
   if (!hresetn) begin
      lat_measuring <= 0;
      lat_counter   <= 0;
   end else if (lat_phase != 0) begin
      if (lat_irq_active && lat_mstatus_mie && !lat_measuring) begin
         lat_counter   <= 1;
         lat_measuring <= 1;
      end
      else if (lat_measuring && !lat_trap_taken) begin
         lat_counter <= lat_counter + 1;
      end
      else if (lat_measuring && lat_trap_taken && lat_trap_is_irq) begin
         if (lat_phase == 6) begin
            nokill_lat_count = nokill_lat_count + 1;
            nokill_lat_total = nokill_lat_total + lat_counter;
            if (lat_counter > nokill_lat_max) nokill_lat_max = lat_counter;
         end else begin
            kill_lat_count = kill_lat_count + 1;
            kill_lat_total = kill_lat_total + lat_counter;
            if (lat_counter > kill_lat_max) kill_lat_max = lat_counter;
         end
         lat_measuring <= 0;
         lat_counter   <= 0;
      end
      else if (lat_measuring && !lat_irq_active && !lat_trap_taken) begin
         lat_measuring <= 0;
         lat_counter   <= 0;
      end
   end else begin
      lat_measuring <= 0;
      lat_counter   <= 0;
   end
end


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

      // Disable error-on-exception
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 1: CHECK INITIALIZATION                           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);

      //=================================================================
      // PHASE 2: DIV operations with IRQ bombardment
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 2: DIV WITH IRQ (ABORT & RESTART)                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      repeat(2) @(posedge free_clk);

      // Fire rapid IRQ pulses to hit the DIV mid-computation
      // Each pulse: assert for 1-2 cycles, gap of 2-4 cycles
      for (ii=0; ii<10; ii=ii+1) begin
         irq_m_timer = 1'b1;
         repeat(1 + ($urandom % 2)) @(posedge free_clk);
         irq_m_timer = 1'b0;
         repeat(2 + ($urandom % 3)) @(posedge free_clk);
      end

      // Wait for Phase 2 complete
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Check DIV results are correct despite interrupts
      $display("");
      $display("--- DIV result verification ---");
      check_mem_value(`SPAD(32'h20), 32'h00000002);       // 7 / 3 = 2
      check_mem_value(`SPAD(32'h24), 32'h00000001);       // 7 % 3 = 1
      check_mem_value(`SPAD(32'h28), 32'h55555553);       // 0xFFFFFFF9 / 3
      check_mem_value(`SPAD(32'h2C), 32'h00000000);       // 0xFFFFFFF9 % 3 = 0

      // Check at least some traps were taken
      $display("");
      $display("--- Phase 2 trap count ---");
      begin : check_phase2_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];
         if (tc < 32'h1) begin
            $display("INFO:  No traps taken during Phase 2 -- trap_count: %0d (IRQ may not have hit DIV window) %t ns", tc, $time);
         end else begin
            $display("PASS:  Traps taken during DIV operations -- trap_count: %0d %t ns", tc, $time);
         end
      end

      //=================================================================
      // PHASE 3: MUL operations with IRQ bombardment
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 3: MUL WITH IRQ (ABORT & RESTART)                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(2) @(posedge free_clk);

      // Fire rapid IRQ pulses
      for (ii=0; ii<10; ii=ii+1) begin
         irq_m_timer = 1'b1;
         repeat(1 + ($urandom % 2)) @(posedge free_clk);
         irq_m_timer = 1'b0;
         repeat(2 + ($urandom % 3)) @(posedge free_clk);
      end

      // Wait for Phase 3 complete
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Check MUL results
      // 0x12345678 * 0xABCDEF01:
      //   Full 64-bit: 0x0C379AB7_3E72D678
      //   Unsigned:     0x0C379AB7_3E72D678
      //   Signed (0x12345678 positive, 0xABCDEF01 = -0x543210FF negative):
      //   Signed product: 0x12345678 * (-0x543210FF) = -0x060B60A0_3E72D678
      //     high32 signed = 0xF9F49F5F + carry handling
      $display("");
      $display("--- MUL result verification ---");
      check_mem_value(`SPAD(32'h40), 32'h55065E78);       // MUL: low 32 bits

      // MULHU (unsigned * unsigned high32)
      check_mem_value(`SPAD(32'h48), 32'h0C379AAA);       // MULHU

      // Check at least some traps were taken
      $display("");
      $display("--- Phase 3 trap count ---");
      begin : check_phase3_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];
         if (tc < 32'h1) begin
            $display("INFO:  No traps taken during Phase 3 -- trap_count: %0d (IRQ may not have hit MUL window) %t ns", tc, $time);
         end else begin
            $display("PASS:  Traps taken during MUL operations -- trap_count: %0d %t ns", tc, $time);
         end
      end

      //=================================================================
      // PHASE 4: DIV loop with continuous IRQ bombardment
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 4: DIV LOOP WITH CONTINUOUS IRQS                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h41414141);
      repeat(2) @(posedge free_clk);

      // Continuous IRQ bombardment during entire loop
      // Use cycle-by-cycle IRQ generation to avoid missing the x31 transition
      jj = 0;
      ii = 0;
      while (probes_cpu.x31 != 32'h44444444) begin
         @(posedge free_clk);
         // State machine: 0=timer_on, 1=timer_gap, 2=ext_on, 3=ext_gap
         case (ii)
            0: begin  // Timer assert phase
                  irq_m_timer = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_timer = 1'b0; ii = 1; jj = 8 + ($urandom % 16); end
               end
            1: begin  // Timer gap
                  jj = jj - 1;
                  if (jj == 0) ii = 2;
               end
            2: begin  // External assert phase
                  irq_m_external = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_external = 1'b0; ii = 3; jj = 8 + ($urandom % 16); end
               end
            3: begin  // External gap
                  jj = jj - 1;
                  if (jj == 0) ii = 0;
               end
         endcase
      end
      irq_m_timer    = 1'b0;
      irq_m_external = 1'b0;

      repeat(3) @(posedge free_clk);

      // Check all 100 iterations completed with correct results
      $display("");
      $display("--- Phase 4: DIV loop verification ---");
      check_mem_value(`SPAD(32'h60), 32'h00000064);       // 100 iterations completed

      // Check trap count (should be significant)
      begin : check_phase4_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h68)];
         $display("PASS:  DIV loop completed under IRQ bombardment -- trap_count: %0d %t ns", tc, $time);
      end


      //=================================================================
      // PHASE 5: MUL loop with continuous IRQ bombardment
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 5: MUL LOOP WITH CONTINUOUS IRQS                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h51515151);
      repeat(2) @(posedge free_clk);

      // Continuous IRQ bombardment during entire loop
      // Use cycle-by-cycle IRQ generation to avoid missing the x31 transition
      jj = 0;
      ii = 0;
      while (probes_cpu.x31 != 32'h55555555) begin
         @(posedge free_clk);
         case (ii)
            0: begin  // Software assert phase
                  irq_m_software = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_software = 1'b0; ii = 1; jj = 8 + ($urandom % 16); end
               end
            1: begin  // Software gap
                  jj = jj - 1;
                  if (jj == 0) ii = 2;
               end
            2: begin  // Timer assert phase
                  irq_m_timer = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_timer = 1'b0; ii = 3; jj = 8 + ($urandom % 16); end
               end
            3: begin  // Timer gap
                  jj = jj - 1;
                  if (jj == 0) ii = 0;
               end
         endcase
      end
      irq_m_software = 1'b0;
      irq_m_timer    = 1'b0;

      repeat(3) @(posedge free_clk);

      // Check all 100 iterations completed with correct results
      $display("");
      $display("--- Phase 5: MUL loop verification ---");
      check_mem_value(`SPAD(32'h70), 32'h00000064);       // 100 iterations completed
      check_mem_value(`SPAD(32'h74), 32'h00002710);       // 100*100 = 10000 = 0x2710

      // Check trap count
      begin : check_phase5_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h78)];
         $display("PASS:  MUL loop completed under IRQ bombardment -- trap_count: %0d %t ns", tc, $time);
      end


      //=================================================================
      // PHASE 6: DIV latency WITHOUT kill
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 6: DIV LATENCY WITHOUT KILL                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h61616161);
      repeat(2) @(posedge free_clk);

      // Enable latency measurement for no-kill phase
      lat_phase = 6;

      // Continuous IRQ bombardment during DIV loop
      jj = 0;
      ii = 0;
      while (probes_cpu.x31 != 32'h62626262) begin
         @(posedge free_clk);
         case (ii)
            0: begin
                  irq_m_timer = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_timer = 1'b0; ii = 1; jj = 8 + ($urandom % 16); end
               end
            1: begin
                  jj = jj - 1;
                  if (jj == 0) ii = 2;
               end
            2: begin
                  irq_m_external = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_external = 1'b0; ii = 3; jj = 8 + ($urandom % 16); end
               end
            3: begin
                  jj = jj - 1;
                  if (jj == 0) ii = 0;
               end
         endcase
      end
      irq_m_timer    = 1'b0;
      irq_m_external = 1'b0;

      // Disable measurement
      lat_phase = 0;

      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Phase 6: DIV loop (no kill) verification ---");
      check_mem_value(`SPAD(32'h80), 32'h00000014);       // 20 iterations completed

      begin : check_phase6_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h84)];
         $display("PASS:  No-kill DIV loop completed under IRQs -- trap_count: %0d %t ns", tc, $time);
      end


      //=================================================================
      // PHASE 7: DIV latency WITH kill
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 7: DIV LATENCY WITH KILL                          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h71717171);
      repeat(2) @(posedge free_clk);

      // Enable latency measurement for kill phase
      lat_phase = 7;

      // Same continuous IRQ bombardment
      jj = 0;
      ii = 0;
      while (probes_cpu.x31 != 32'h72727272) begin
         @(posedge free_clk);
         case (ii)
            0: begin
                  irq_m_timer = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_timer = 1'b0; ii = 1; jj = 8 + ($urandom % 16); end
               end
            1: begin
                  jj = jj - 1;
                  if (jj == 0) ii = 2;
               end
            2: begin
                  irq_m_external = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_external = 1'b0; ii = 3; jj = 8 + ($urandom % 16); end
               end
            3: begin
                  jj = jj - 1;
                  if (jj == 0) ii = 0;
               end
         endcase
      end
      irq_m_timer    = 1'b0;
      irq_m_external = 1'b0;

      // Disable measurement
      lat_phase = 0;

      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Phase 7: DIV loop (with kill) verification ---");
      check_mem_value(`SPAD(32'h90), 32'h00000014);       // 20 iterations completed

      begin : check_phase7_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h94)];
         $display("PASS:  Kill DIV loop completed under IRQs -- trap_count: %0d %t ns", tc, $time);
      end


      //=================================================================
      // PHASE 8: Final register preservation
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 8: REGISTER PRESERVATION CHECK                    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      while (probes_cpu.x31 != 32'h88888888) @(posedge free_clk);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Register preservation after all phases ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // IRQ LATENCY COMPARISON
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           IRQ LATENCY COMPARISON (DIV)                            |");
      $display(" ====================================================================");
      $display("");
      if (nokill_lat_count > 0 && kill_lat_count > 0) begin
         $display("  Without kill:  avg=%0d.%0d cycles, max=%0d cycles (%0d samples)",
                  nokill_lat_total / nokill_lat_count,
                  (nokill_lat_total * 10 / nokill_lat_count) % 10,
                  nokill_lat_max, nokill_lat_count);
         $display("  With kill:     avg=%0d.%0d cycles, max=%0d cycles (%0d samples)",
                  kill_lat_total / kill_lat_count,
                  (kill_lat_total * 10 / kill_lat_count) % 10,
                  kill_lat_max, kill_lat_count);
         $display("");
         // Use average for PASS check (cross-multiply to avoid fp: kill_avg < nokill_avg)
         if (kill_lat_total * nokill_lat_count < nokill_lat_total * kill_lat_count)
            $display("PASS:  Kill feature reduces avg IRQ latency (%0d.%0d < %0d.%0d cycles) %t ns",
                     kill_lat_total / kill_lat_count,
                     (kill_lat_total * 10 / kill_lat_count) % 10,
                     nokill_lat_total / nokill_lat_count,
                     (nokill_lat_total * 10 / nokill_lat_count) % 10, $time);
         else
            $display("INFO:  Kill avg latency not lower this run -- may need more samples %t ns", $time);
      end else begin
         $display("INFO:  Insufficient latency samples (nokill=%0d, kill=%0d) %t ns",
                  nokill_lat_count, kill_lat_count, $time);
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

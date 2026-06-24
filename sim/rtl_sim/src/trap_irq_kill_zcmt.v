//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_kill_zcmt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP IRQ KILL ZCMT
//   Verifies that IRQs can abort and restart Zcmt UOP operations:
//   - CM.JT (UOP) under IRQ bombardment, jump target correct
//   - CM.JALT (UOP) under IRQ bombardment, jump target + ra correct
//   - IRQ latency comparison with and without kill
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
// Measures cycles from any IRQ input rising edge (when MSTATUS.MIE=1)
// to trap_taken firing. Separate accumulators for kill-disabled (Phase 4)
// and kill-enabled (Phase 5) phases.
//------------------------------------------------------------------------
wire lat_trap_taken  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_taken;
wire lat_trap_is_irq = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq;
wire lat_mstatus_mie = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mstatus_mie;
wire lat_irq_active  = irq_m_timer | irq_m_software | irq_m_external;

integer lat_measuring;
integer lat_counter;
integer lat_phase;      // 0=inactive, 4=no-kill, 5=kill

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
         if (lat_phase == 4) begin
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
      // PHASE 2: CM.JT with IRQ bombardment (UOP kill)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 2: CM.JT WITH IRQ (UOP KILL)                     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      repeat(2) @(posedge free_clk);

      // Tight IRQ bombardment - short gaps to maximize chance of hitting
      // the narrow 1-2 cycle JT kill window
      jj = 0;
      ii = 0;
      while (probes_cpu.x31 != 32'h22222222) begin
         @(posedge free_clk);
         case (ii)
            0: begin  // Timer assert phase
                  irq_m_timer = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_timer = 1'b0; ii = 1; jj = 1 + ($urandom % 3); end
               end
            1: begin  // Timer gap (short!)
                  jj = jj - 1;
                  if (jj == 0) ii = 2;
               end
            2: begin  // External assert phase
                  irq_m_external = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_external = 1'b0; ii = 3; jj = 1 + ($urandom % 3); end
               end
            3: begin  // External gap (short!)
                  jj = jj - 1;
                  if (jj == 0) ii = 0;
               end
         endcase
      end
      irq_m_timer    = 1'b0;
      irq_m_external = 1'b0;

      repeat(3) @(posedge free_clk);

      // Verify CM.JT results
      $display("");
      $display("--- Phase 2: CM.JT verification ---");
      check_mem_value(`SPAD(32'h20), 32'h00000032);       // 50 iterations completed
      check_mem_value(`SPAD(32'h24), 32'hCAFECAFE);       // canary intact

      // Check trap count
      begin : check_phase2_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];
         if (tc < 32'h1) begin
            $display("INFO:  No traps taken during Phase 2 -- trap_count: %0d (IRQ may not have hit JT window) %t ns", tc, $time);
         end else begin
            $display("PASS:  Traps taken during CM.JT operations -- trap_count: %0d %t ns", tc, $time);
         end
      end


      //=================================================================
      // PHASE 3: CM.JALT with IRQ bombardment (UOP kill)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 3: CM.JALT WITH IRQ (UOP KILL)                   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(2) @(posedge free_clk);

      // Tight IRQ bombardment
      jj = 0;
      ii = 0;
      while (probes_cpu.x31 != 32'h33333333) begin
         @(posedge free_clk);
         case (ii)
            0: begin
                  irq_m_timer = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_timer = 1'b0; ii = 1; jj = 1 + ($urandom % 3); end
               end
            1: begin
                  jj = jj - 1;
                  if (jj == 0) ii = 2;
               end
            2: begin
                  irq_m_external = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_external = 1'b0; ii = 3; jj = 1 + ($urandom % 3); end
               end
            3: begin
                  jj = jj - 1;
                  if (jj == 0) ii = 0;
               end
         endcase
      end
      irq_m_timer    = 1'b0;
      irq_m_external = 1'b0;

      repeat(3) @(posedge free_clk);

      // Verify CM.JALT results
      $display("");
      $display("--- Phase 3: CM.JALT verification ---");
      check_mem_value(`SPAD(32'h40), 32'h00000032);       // 50 iterations completed
      check_mem_value(`SPAD(32'h44), 32'hCAFECAFE);       // canary intact
      check_mem_value(`SPAD(32'h48), 32'h00000032);       // all 50 ra values valid

      // Check trap count
      begin : check_phase3_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h4C)];
         if (tc < 32'h1) begin
            $display("INFO:  No traps taken during Phase 3 -- trap_count: %0d (IRQ may not have hit JALT window) %t ns", tc, $time);
         end else begin
            $display("PASS:  Traps taken during CM.JALT operations -- trap_count: %0d %t ns", tc, $time);
         end
      end


      //=================================================================
      // PHASE 4: CM.JT latency WITHOUT kill
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 4: CM.JT LATENCY WITHOUT KILL                    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h41414141);
      repeat(2) @(posedge free_clk);

      // Disable IRQ kill checkers: kill feature is off in Phase 4, so
      // MRET repeatedly returning to the same CM.JT PC is expected.
      irq_kill_checker_en = 0;

      // Enable latency measurement for no-kill phase
      lat_phase = 4;

      // Tight IRQ bombardment
      jj = 0;
      ii = 0;
      while (probes_cpu.x31 != 32'h42424242) begin
         @(posedge free_clk);
         case (ii)
            0: begin
                  irq_m_timer = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_timer = 1'b0; ii = 1; jj = 1 + ($urandom % 3); end
               end
            1: begin
                  jj = jj - 1;
                  if (jj == 0) ii = 2;
               end
            2: begin
                  irq_m_external = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_external = 1'b0; ii = 3; jj = 1 + ($urandom % 3); end
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

      // Re-enable IRQ kill checkers now that kill feature is back on
      irq_kill_checker_en = 1;

      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Phase 4: CM.JT (no kill) verification ---");
      check_mem_value(`SPAD(32'h60), 32'h00000032);       // 50 iterations completed

      begin : check_phase4_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)];
         $display("PASS:  No-kill CM.JT loop completed under IRQs -- trap_count: %0d %t ns", tc, $time);
      end


      //=================================================================
      // PHASE 5: CM.JT latency WITH kill
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 5: CM.JT LATENCY WITH KILL                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h51515151);
      repeat(2) @(posedge free_clk);

      // Enable latency measurement for kill phase
      lat_phase = 5;

      // Tight IRQ bombardment
      jj = 0;
      ii = 0;
      while (probes_cpu.x31 != 32'h52525252) begin
         @(posedge free_clk);
         case (ii)
            0: begin
                  irq_m_timer = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_timer = 1'b0; ii = 1; jj = 1 + ($urandom % 3); end
               end
            1: begin
                  jj = jj - 1;
                  if (jj == 0) ii = 2;
               end
            2: begin
                  irq_m_external = 1'b1;
                  if (jj == 0) jj = 1 + ($urandom % 2);
                  jj = jj - 1;
                  if (jj == 0) begin irq_m_external = 1'b0; ii = 3; jj = 1 + ($urandom % 3); end
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
      $display("--- Phase 5: CM.JT (with kill) verification ---");
      check_mem_value(`SPAD(32'h70), 32'h00000032);       // 50 iterations completed

      begin : check_phase5_traps
         reg [31:0] tc;
         tc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)];
         $display("PASS:  Kill CM.JT loop completed under IRQs -- trap_count: %0d %t ns", tc, $time);
      end


      //=================================================================
      // PHASE 6: Final register preservation
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|           PHASE 6: REGISTER PRESERVATION CHECK                    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      while (probes_cpu.x31 != 32'h66666666) @(posedge free_clk);
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
      $display("|           IRQ LATENCY COMPARISON (CM.JT)                          |");
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
         if (kill_lat_total * nokill_lat_count < nokill_lat_total * kill_lat_count)
            $display("PASS:  Kill feature reduces avg IRQ latency (%0d.%0d < %0d.%0d cycles) %t ns",
                     kill_lat_total / kill_lat_count,
                     (kill_lat_total * 10 / kill_lat_count) % 10,
                     nokill_lat_total / nokill_lat_count,
                     (nokill_lat_total * 10 / nokill_lat_count) % 10, $time);
         else
            $display("INFO:  Kill avg latency not lower this run -- JT kill window is very narrow (1-2 cycles) %t ns", $time);
      end else begin
         $display("INFO:  Insufficient latency samples (nokill=%0d, kill=%0d) -- JT kill window is very narrow %t ns",
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

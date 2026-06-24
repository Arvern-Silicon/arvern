//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    random_irq_injector
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : random_irq_injector.v
// Module Description : Randomly pulses timer / software / external IRQ lines for stress testing.
//----------------------------------------------------------------------------

`ifdef RANDOM_IRQ

// CPU internal signals for IRQ injection gating and latency measurement
wire irq_any_active  = irq_m_timer | irq_m_software | irq_m_external;
wire trap_taken_sig  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_taken;
wire trap_is_irq_sig = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq;
wire mstatus_mie_sig = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mstatus_mie;

// Kill signals for tracking killable instruction statistics
wire kill_muldiv_sig       = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_kill_muldiv_o;
wire kill_uop_sig          = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_kill_uop_o;
wire kill_suppress_muldiv  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_suppress;
wire kill_suppress_uop     = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.uop_kill_suppress;

integer random_irq_count;

initial
   begin
      random_irq_count = 0;

      // Wait for system to come out of reset and firmware to initialize
      // the trap handler (give it time to set up MTVEC, MSCRATCH, MIE)
      @(posedge hresetn);
      repeat(20) @(posedge free_clk);

      random_irq_enable = 1;
      $display("");
      $display("=== Random IRQ injection ENABLED ===");
      $display("");

      // Continuous random IRQ injection loop
      forever begin

         // Random gap between IRQ pulses (5 to 30 cycles)
         repeat(5 + ($urandom % 26)) @(posedge free_clk);

         // Skip injection when disabled by stimulus or when an IRQ is
         // currently being serviced (MIE=0). This ensures every injected
         // IRQ can actually be taken, giving clean latency measurements.
         if (!random_irq_enable || !mstatus_mie_sig) begin
            @(posedge free_clk);
         end else begin

            // Randomly select which IRQ to fire (0=timer, 1=software, 2=external)
            random_irq_count = random_irq_count + 1;
            case ($urandom % 3)
               0: begin
                  irq_m_timer = 1'b1;
                  repeat(1 + ($urandom % 3)) @(posedge free_clk);
                  irq_m_timer = 1'b0;
               end
               1: begin
                  irq_m_software = 1'b1;
                  repeat(1 + ($urandom % 3)) @(posedge free_clk);
                  irq_m_software = 1'b0;
               end
               2: begin
                  irq_m_external = 1'b1;
                  repeat(1 + ($urandom % 3)) @(posedge free_clk);
                  irq_m_external = 1'b0;
               end
            endcase

         end
      end
   end

//------------------------------------------------------------------------
// IRQ LATENCY HISTOGRAM
//------------------------------------------------------------------------
// Measures cycles from any IRQ input rising edge (when MSTATUS.MIE=1)
// to trap_taken firing. Tracks distribution in histogram bins.
//------------------------------------------------------------------------

// Histogram: bin[i] counts how many IRQs had latency of i cycles
// Bin 0 is unused (latency is at least 1 cycle)
// Bin 32+ catches anything above 31 cycles
localparam IRQ_LAT_BINS = 64;
integer irq_lat_histogram [0:IRQ_LAT_BINS-1];
integer irq_lat_counter;
integer irq_lat_measuring;
integer irq_lat_total;
integer irq_lat_max;
integer irq_lat_count;
integer irq_lat_ii;

initial begin
   for (irq_lat_ii = 0; irq_lat_ii < IRQ_LAT_BINS; irq_lat_ii = irq_lat_ii + 1)
      irq_lat_histogram[irq_lat_ii] = 0;
   irq_lat_counter   = 0;
   irq_lat_measuring = 0;
   irq_lat_total     = 0;
   irq_lat_max       = 0;
   irq_lat_count     = 0;
end

always @(posedge free_clk or negedge hresetn) begin
   if (!hresetn) begin
      irq_lat_counter   <= 0;
      irq_lat_measuring <= 0;
   end else begin
      // Start measuring when IRQ arrives while MIE is enabled
      if (irq_any_active && mstatus_mie_sig && !irq_lat_measuring) begin
         irq_lat_counter   <= 1;
         irq_lat_measuring <= 1;
      end
      // Count cycles while measuring
      else if (irq_lat_measuring && !trap_taken_sig) begin
         irq_lat_counter <= irq_lat_counter + 1;
      end
      // Trap taken: record latency
      else if (irq_lat_measuring && trap_taken_sig && trap_is_irq_sig) begin
         irq_lat_count = irq_lat_count + 1;
         irq_lat_total = irq_lat_total + irq_lat_counter;
         if (irq_lat_counter > irq_lat_max)
            irq_lat_max = irq_lat_counter;
         if (irq_lat_counter < IRQ_LAT_BINS)
            irq_lat_histogram[irq_lat_counter] = irq_lat_histogram[irq_lat_counter] + 1;
         else
            irq_lat_histogram[IRQ_LAT_BINS-1] = irq_lat_histogram[IRQ_LAT_BINS-1] + 1;
         irq_lat_measuring <= 0;
         irq_lat_counter   <= 0;
      end
      // IRQ deasserted before trap_taken (pulse too short or MIE went low)
      else if (irq_lat_measuring && !irq_any_active && !trap_taken_sig) begin
         irq_lat_measuring <= 0;
         irq_lat_counter   <= 0;
      end
   end
end

//------------------------------------------------------------------------
// IRQ KILL STATISTICS
//------------------------------------------------------------------------
// Tracks how many killable multi-cycle instructions were killed by IRQs
// vs how many times livelock protection suppressed a second kill
// (forcing the instruction to complete naturally before taking the IRQ).
//------------------------------------------------------------------------

integer irq_kill_muldiv_count;
integer irq_kill_uop_count;
integer irq_kill_suppressed_count;

initial begin
   irq_kill_muldiv_count     = 0;
   irq_kill_uop_count        = 0;
   irq_kill_suppressed_count = 0;
end

always @(posedge free_clk) begin
   if (kill_muldiv_sig | kill_uop_sig) begin
      if (kill_muldiv_sig)
         irq_kill_muldiv_count = irq_kill_muldiv_count + 1;
      if (kill_uop_sig)
         irq_kill_uop_count = irq_kill_uop_count + 1;
   end
   if (trap_taken_sig && trap_is_irq_sig) begin
      if (!kill_muldiv_sig && !kill_uop_sig && (kill_suppress_muldiv || kill_suppress_uop))
         irq_kill_suppressed_count = irq_kill_suppressed_count + 1;
   end
end

// Print IRQ count and latency histogram at end of simulation
initial begin
   wait(stimulus_done);
   $display("");
   $display("=== Random IRQ injection: %0d IRQs generated ===", random_irq_count);
   $display("");
   if (irq_lat_count > 0) begin
      $display("=== IRQ Latency Histogram (cycles from IRQ assert to trap_taken) ===");
      $display("    Measured IRQs: %0d", irq_lat_count);
      $display("    Average:       %0d.%0d cycles", irq_lat_total / irq_lat_count,
                                                     (irq_lat_total * 10 / irq_lat_count) % 10);
      $display("    Maximum:       %0d cycles", irq_lat_max);
      $display("");
      $display("    Cycles | Count");
      $display("    -------+------");
      for (irq_lat_ii = 1; irq_lat_ii < IRQ_LAT_BINS; irq_lat_ii = irq_lat_ii + 1) begin
         if (irq_lat_histogram[irq_lat_ii] > 0) begin
            if (irq_lat_ii == IRQ_LAT_BINS-1)
               $display("    %3d+   | %0d", irq_lat_ii, irq_lat_histogram[irq_lat_ii]);
            else
               $display("    %3d    | %0d", irq_lat_ii, irq_lat_histogram[irq_lat_ii]);
         end
      end
      $display("    -------+------");
      $display("");
   end
   if (irq_kill_muldiv_count > 0 || irq_kill_uop_count > 0 || irq_kill_suppressed_count > 0) begin
      $display("=== IRQ Kill Statistics ===");
      $display("    Muldiv killed:     %0d", irq_kill_muldiv_count);
      $display("    UOP killed:        %0d", irq_kill_uop_count);
      $display("    Kill suppressed:   %0d  (livelock protection)", irq_kill_suppressed_count);
      $display("");
   end
end

`endif

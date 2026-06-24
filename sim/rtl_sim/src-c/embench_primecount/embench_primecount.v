//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      embench_primecount
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------

`define NO_TIMEOUT

time mclk_start_time, mclk_end_time;
real mclk_period, mclk_frequency;
time benchmark_start_time, benchmark_end_time;
real benchmark_cycles, benchmark_cycles_scaled;
integer local_scale_factor;
integer benchmark_score;

initial
   begin
      $display(" ===============================================");
      $display("|       EMBENCH IOT BENCHMARK: PRIMECOUNT       |");
      $display(" ===============================================");
      local_scale_factor = 170;  // Extracted from benchmark C code

      repeat(5) @(posedge free_clk);
      stimulus_done = 0;

      // Measure clock period
      repeat(10) @(posedge free_clk);
      $timeformat(-9, 3, " ns", 10);
      @(posedge free_clk);
      mclk_start_time = $time;
      @(posedge free_clk);
      mclk_end_time = $time;
      @(posedge free_clk);
      mclk_period    = mclk_end_time - mclk_start_time;
      mclk_frequency = 1000 / mclk_period;
      $display("\nINFO-VERILOG: arvern clock frequency %f MHz", mclk_frequency);

      $display("\nINFO-VERILOG: Waiting for benchmark to start...");
      $timeformat(-3, 3, " ms", 10);
      $display("");
      $display("INFO-VERILOG: Be patient... there could be up to 4 seconds of simulation time until until the benchmark starts.");
      $display("");

      // Detect beginning of run (P1_OUT0 goes high)
      @(posedge periph1_reg_00_out[0]);
      $timeformat(-9, 3, " ns", 10);
      benchmark_start_time = $time;
      $timeformat(-3, 3, " ms", 10);
      $display("");
      $display("INFO-VERILOG: Benchmark started at %t", benchmark_start_time);
      $display("");
      $display("INFO-VERILOG: Be patient... there could be up to 5 seconds to simulate");
      $display("");

      // Detect end of run (P1_OUT0 goes low)
      @(negedge periph1_reg_00_out[0]);
      benchmark_end_time = $time;
      $display("INFO-VERILOG: Benchmark ended at %t", benchmark_end_time);

      // Compute results
      $timeformat(-9, 0, " ns", 10);
      benchmark_cycles        = (benchmark_end_time - benchmark_start_time) / mclk_period;
      benchmark_cycles_scaled = benchmark_cycles/(local_scale_factor*mclk_frequency);
      benchmark_score         = (benchmark_end_time - benchmark_start_time)/1000000;

      // Report results
      $timeformat(-3, 3, " ms", 10);
      $display("\nINFO-VERILOG: ========== BENCHMARK RESULTS ===========");
      $display("INFO-VERILOG: Execution time      : %t", (benchmark_end_time - benchmark_start_time));
      $display("INFO-VERILOG: Clock cycles        : %0d", benchmark_cycles);
      $display("INFO-VERILOG: Clock frequency     : %f MHz", mclk_frequency);
      $display("INFO-VERILOG: ========================================");
      $display("INFO-VERILOG: Embench Speed Result: %0d", benchmark_score);
      $display("INFO-VERILOG: ========================================\n");

      // Wait for verification self-check to be written to P1_OUT1 (P1_OUT2 is set when the P1_OUT1 results are ready to be read)
      @(posedge periph1_reg_02_out[0]);

      // Check verification result
      if (periph1_reg_01_out[0] == 1'b1) begin
         $display(" ===============================================");
         $display("|        BENCHMARK VERIFICATION PASSED          |");
         $display(" ===============================================");
      end else begin
         $display(" ===============================================");
         $display("|        BENCHMARK VERIFICATION FAILED          |");
         $display(" ===============================================");
         error += 1;
      end

      repeat(100) @(posedge free_clk);
      stimulus_done = 1;

   end

// Display stuff from the C-program (printf)
always @(posedge periph0_reg_01_out[0])
  begin
     $write("%s", periph0_reg_00_out[7:0]);
     $fflush();
  end

// Display simulation progress
initial
  begin
     #40000000;
     while (1)
       begin
          $display("INFO-VERILOG: Simulated time %t", $time);
          #40000000;
       end
  end

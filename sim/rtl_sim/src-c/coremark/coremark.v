//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      coremark
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
real mclk_period,     mclk_frequency;

time coremark_start_time, coremark_end_time;
real coremark_per_sec;
real coremark_per_mhz;

integer Number_Of_Iterations;

initial
   begin
      $display(" ===============================================");
      $display("|                 START SIMULATION              |");
      $display(" ===============================================");

      repeat(5) @(posedge free_clk);
      stimulus_done = 0;

      //---------------------------------------
      // Number of benchmark iteration
      // (Must match the C-code value)
      //---------------------------------------

      Number_Of_Iterations = 3;


      //---------------------------------------
      // Measure clock period
      //---------------------------------------
      repeat(10) @(posedge free_clk);
      $timeformat(-9, 3, " ns", 10);
      @(posedge free_clk);
      mclk_start_time = $time;
      @(posedge free_clk);
      mclk_end_time = $time;
      @(posedge free_clk);
      mclk_period    = mclk_end_time-mclk_start_time;
      mclk_frequency = 1000/mclk_period;
      $display("\nINFO-VERILOG: arvern System clock frequency %f MHz", mclk_frequency);

      //---------------------------------------
      // Detect when CoreMark starts executing
      //---------------------------------------
      @(posedge periph2_reg_00_out[0]);
      $display("\nINFO-VERILOG: CoreMark is now running for %d iterations", Number_Of_Iterations);

      //---------------------------------------
      // Measure CoreMark run time
      //---------------------------------------

      // Detect beginning of run
      @(posedge periph1_reg_00_out[0]);
      coremark_start_time = $time;
      $timeformat(-3, 3, " ms", 10);
      $display("INFO-VERILOG: CoreMark loop started at %t ", coremark_start_time);
      $display("");
      $display("INFO-VERILOG: Be patient... there could be up to 1.5 seconds to simulate");
      $display("");

      // Detect end of run
      @(negedge periph1_reg_00_out[0]);
      coremark_end_time = $time;
      $timeformat(-3, 3, " ms", 10);
      $display("INFO-VERILOG: Coremark loop ended at %t ",   coremark_end_time);

      // Compute results
      $timeformat(-9, 3, " ns", 10);
      coremark_per_sec = coremark_end_time - coremark_start_time;
      coremark_per_sec = 1000000000 / coremark_per_sec;
      coremark_per_sec = Number_Of_Iterations*coremark_per_sec;
      coremark_per_mhz = coremark_per_sec / mclk_frequency;

      // Report results
      $display("\INFO-VERILOG: CoreMark ticks      : %d",     periph0_reg_15_in);
      $display("\INFO-VERILOG: CoreMark per second : %f",     coremark_per_sec);
      $display("\INFO-VERILOG: CoreMark per MHz    : %f\n\n", coremark_per_mhz);

      //---------------------------------------
      // Wait for the end of C-code execution
      //---------------------------------------
      @(negedge periph2_reg_00_out[0]);
      $display("\nINFO-VERILOG: CoreMark is now done");

      stimulus_done = 1;

   end

// Display stuff from the C-program
always @(posedge periph0_reg_01_out[0])
  begin
     $write("%s", periph0_reg_00_out[7:0]);
     $fflush();
  end

// Display some info to show simulation progress
initial
  begin
     @(posedge periph1_reg_00_out[0]);
     #3000000;
     while (periph1_reg_00_out[0])
       begin
	      $display("INFO-VERILOG: Simulated time %t ", $time);
	      #3000000;
       end
  end


// Time tick counter
always @(negedge free_clk or negedge hresetn)
  if (!hresetn)                   periph0_reg_15_in <= 32'h0000_0000;
  else if (periph1_reg_00_out[0]) periph0_reg_15_in <= periph0_reg_15_in + 32'h1;

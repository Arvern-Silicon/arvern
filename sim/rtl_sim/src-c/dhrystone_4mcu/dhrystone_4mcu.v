//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      dhrystone_4mcu
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------

`define NO_TIMEOUT
`define WITH_TIMESCALE

time mclk_start_time, mclk_end_time;
real mclk_period,     mclk_frequency;

time dhry_start_time, dhry_end_time;
real dhry_per_sec,    dhry_mips,     dhry_mips_per_mhz;

integer Number_Of_Runs;

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

      $display(" ===============================================");
      $display("|                 START SIMULATION              |");
      $display(" ===============================================");

      repeat(5) @(posedge free_clk);
      stimulus_done = 0;

      //---------------------------------------
      // Number of benchmark iteration
      // (Must match the C-code value)
      //---------------------------------------

      Number_Of_Runs = 500;


      //---------------------------------------
      // Measure clock period
      //---------------------------------------
      repeat(100) @(posedge free_clk);
      $timeformat(-9, 3, " ns", 10);
      @(posedge free_clk);
      mclk_start_time = $time;
      @(posedge free_clk);
      mclk_end_time = $time;
      @(posedge free_clk);
      mclk_period    = mclk_end_time-mclk_start_time;
      mclk_frequency = 1000/mclk_period;
      $display("\nINFO-VERILOG: arvern System clock frequency %f MHz\n", mclk_frequency);

      //---------------------------------------
      // Measure Dhrystone run time
      //---------------------------------------

      // Detect beginning of run
      @(posedge periph1_reg_00_out[0]);
      dhry_start_time = $time;
      $timeformat(-3, 3, " ms", 10);
      $display("\nINFO-VERILOG: Dhrystone loop started at %t ", dhry_start_time);
      $display("");
      $display("INFO-VERILOG: Be patient... there is roughly 200ms to simulate");
      $display("");

      // Detect end of run
      @(negedge periph1_reg_00_out[0]);
      $display("");
      dhry_end_time = $time;
      $timeformat(-3, 3, " ms", 10);
      $display("INFO-VERILOG: Dhrystone loop ended   at %t ",   dhry_end_time);

      // Compute results
      $timeformat(-9, 3, " ns", 10);
      dhry_per_sec      = (Number_Of_Runs*1000000000)/(dhry_end_time - dhry_start_time);
      dhry_mips         = dhry_per_sec / 1757;
      dhry_mips_per_mhz = dhry_mips / mclk_frequency;

      // Report results
      $display("\INFO-VERILOG: Dhrystone per second : %f",   dhry_per_sec);
      $display("\INFO-VERILOG: DMIPS                : %f",   dhry_mips);
      $display("\INFO-VERILOG: DMIPS/MHz            : %f\n", dhry_mips_per_mhz);

      //---------------------------------------
      // Wait for the end of C-code execution
      //---------------------------------------
      @(posedge periph1_reg_01_out[0]);

      repeat(50000) @(posedge free_clk);
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

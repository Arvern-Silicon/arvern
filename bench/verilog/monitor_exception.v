//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    monitor_exception
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : monitor_exception.v
// Module Description : Counts and reports synchronous exceptions seen by the CPU.
//----------------------------------------------------------------------------

module monitor_exception (
    input  wire [8*64-1:0] msg_string_i,
    input  wire            excp_strobe_i,
    input  wire            free_clk_i,
    input  wire            error_on_exception_i  // When 1, exceptions increment error counter; when 0, exceptions are just logged
);

integer           excp_cnt;

wire              trigger = (~free_clk_i & excp_strobe_i);

initial           excp_cnt = 0;

always @(posedge trigger)
   begin
      // Always monitor and count exceptions
      excp_cnt = excp_cnt + 1;

      // Conditionally treat exception as an error
      if (error_on_exception_i) begin
         // Display as ERROR - this exception is treated as an error
         $display("ERROR-VERILOG: [Exception detected] %0s [%0d] (%t)", msg_string_i, excp_cnt, $time);

         // Increment global error counter
         tb_arvern.error = tb_arvern.error + 1;

         // If the counter reaches 15, stop the simulation
         // In such a case, we probably encountered an issue rather than a stimulus testing the exception on purpose
         if (excp_cnt>15) begin
             $display("");
             $display(" ===============================================");
             $display("|               SIMULATION FAILED               |");
             $display("|            (more than 15 exceptions)          |");
             $display("| %0s |", msg_string_i);
             $display(" ===============================================");
             $display("");
             $finish;
         end
      end else begin
         // Display as INFO - this exception is being monitored but not treated as an error
         $display("INFO-VERILOG: [Exception detected] %0s [%0d] (%t)", msg_string_i, excp_cnt, $time);
      end
   end

endmodule

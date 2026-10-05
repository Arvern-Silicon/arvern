//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_bus_err_estat_w1c_race
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: a marv_estat W1C in the cycle of a second data-bus error must
// not leave overrun set without valid (see the .s).
//----------------------------------------------------------------------------
`define SPAD(byte_off)  ((byte_off)/4)

integer k;
integer captured;
reg [31:0] estat;
reg [31:0] eaddr;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|   marv_estat W1C IN THE CYCLE OF A SECOND DATA-BUS ERROR            |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(40) @(posedge free_clk);

      captured = 0;
      for (k = 0; k < 8; k = k + 1) begin
         estat = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40 + 8*k)];
         eaddr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44 + 8*k)];
         $display("INFO:  k=%0d  marv_estat=0x%h  marv_eaddr=0x%h", k, estat, eaddr);
         if (estat[2] & ~estat[0]) begin
            $display("ERROR: k=%0d -- RNMI with overrun=1 and valid=0 (second fault's evidence lost)", k);
            error = error + 1;
         end
         if (estat[0]) begin
            captured = captured + 1;
            if (eaddr !== 32'h00000008) begin
               $display("ERROR: k=%0d -- valid=1 but marv_eaddr=0x%h, expected the second fault (0x8)", k, eaddr);
               error = error + 1;
            end
         end
      end
      // Random ROM wait states slow the handler's own fetches, so the clear can
      // trail every second error (all trials then see the plain-overrun case)
`ifdef ROM_RANDOM_WS
      if (captured == 0)
         $display("INFO:  no trial captured the second fault (random ROM wait states)");
`else
      if (captured == 0) begin
         $display("ERROR: no trial captured the second fault");
         error = error + 1;
      end
`endif

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_halt_drain_ldst
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: the hart's drain-qualified halted status never drops between a
// halt and the next resume request, whatever load/store is in flight at the
// halt (see the .s). dmstatus.allhalted is that status.
//----------------------------------------------------------------------------
`define VERY_LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;
integer it, to, glitches;
reg     resume_sent;
reg     halted_q;
wire    hart_halted = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.debug_halted_o;

initial begin
   resume_sent = 1'b1;
   halted_q    = 1'b0;
   glitches    = 0;
end

always @(posedge free_clk) begin
   if (halted_q & ~hart_halted & ~resume_sent) begin
      glitches = glitches + 1;
      $display("ERROR: halted status dropped without a resume request %t ns", $time);
   end
   if (hart_halted & ~halted_q) resume_sent = 1'b0;
   halted_q <= hart_halted;
end

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|   HALTED REPORTED ONLY ONCE THE LOAD/STORE STREAM HAS DRAINED       |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      dmi_write(7'h10, 32'h00000001);
      for (it = 0; it < 32; it = it + 1) begin
         repeat (3 + (it % 11)) @(posedge free_clk);
         dmi_write(7'h10, 32'h80000001);             // haltreq
         to = 0;
         dmi_read(7'h11);
         while (((dmi_readval & 32'h00000200) === 32'h0) && (to < 200)) begin
            dmi_read(7'h11); to = to + 1;
         end
         repeat (20) @(posedge free_clk);
         dmi_write(7'h10, 32'h00000001);
         resume_sent = 1'b1;
         dmi_write(7'h10, 32'h40000001);             // resumereq
         to = 0;
         dmi_read(7'h11);
         while (((dmi_readval & 32'h00000800) === 32'h0) && (to < 200)) begin
            dmi_read(7'h11); to = to + 1;
         end
      end

      ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0)] = 32'h1;
      @(probes_cpu.x31==32'hdeadbeef);
      $display("INFO:  32 halts, %0d halted-status drops without a resume request", glitches);
      if (glitches != 0) error = error + 1;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

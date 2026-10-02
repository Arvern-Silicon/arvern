//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zca_buf_full_branch
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Taken branch with the fetch buffer nearly full.
//
//   arv_fetch stops fetching once the buffer will hold 5+ halfwords. Reaching the
//   deep buffer states at all needs the decoder stalled while fetch keeps running,
//   so each block starts with a multi-cycle divide and then drains a dense run of
//   16-bit instructions into a taken branch.
//
//   This is the only stimulus that drives the buffer to six halfwords (state
//   111111) and then redirects it. The register checks confirm every block
//   executed exactly once and nothing was dropped or double-counted, which is what
//   a mis-shifted buffer would produce.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// The register checks alone would pass even if the buffer never filled, so track
// the fill levels the test exists to reach and fail if they were not entered.
reg buf_5hw_seen, buf_6hw_seen, deep_incoming_seen;

initial begin
   buf_5hw_seen       = 1'b0;
   buf_6hw_seen       = 1'b0;
   deep_incoming_seen = 1'b0;
end

always @(posedge free_clk) begin
   if (dut.arv_fetch_inst.inst_buf_valid == 6'b011111) buf_5hw_seen <= 1'b1;
   if (dut.arv_fetch_inst.inst_buf_valid == 6'b111111) buf_6hw_seen <= 1'b1;

   // The "data lands on an already-deep buffer" arms of the fetch case statement are
   // waived as unreachable (waivers_cov.md). Guard that premise here: if a fetch
   // ever completes with the case selector at 5 or 6 halfwords, the waiver is wrong.
   if ((dut.arv_fetch_inst.effective_buf_valid == 6'b011111 ||
        dut.arv_fetch_inst.effective_buf_valid == 6'b111111) &&
        dut.arv_fetch_inst.incoming_inst) deep_incoming_seen <= 1'b1;
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

      $display("");
      $display(" ====================================================================");
      $display("|          TAKEN BRANCH WITH THE FETCH BUFFER NEARLY FULL            |");
      $display(" ====================================================================");
      $display("");

      wait (probes_cpu.x31 == 32'h11111111);

      wait (probes_cpu.x31 == 32'hDEADBEEF);

      // 8 unconditional blocks + 4 conditional = 12 taken branches.
      // Padding: (1+2+..+8) + (1+3+5+7) = 36 + 16 = 52 c.addi executions.
      check_cpu_reg(18, 32'd12);           // blocks completed
      check_cpu_reg(19, 32'd52);           // padding instructions executed
      check_cpu_reg(20, 32'hCAFE0000);     // sentinel survived every redirect
      check_cpu_reg(21, 32'd12);           // taken branches

      check_cpu_reg(31, 32'hDEADBEEF);     // Test complete marker

      $display("");
      if (!buf_5hw_seen)
         begin $display("ERROR: buffer never reached 5 halfwords (011111) %t ns", $time); error = error + 1; end
      else $display("PASS:  buffer reached 5 halfwords (011111) %t ns", $time);

      if (!buf_6hw_seen)
         begin $display("ERROR: buffer never reached 6 halfwords (111111) %t ns", $time); error = error + 1; end
      else $display("PASS:  buffer reached 6 halfwords (111111) %t ns", $time);

      if (deep_incoming_seen)
         begin $display("ERROR: fetch completed with the buffer at 5/6 halfwords -- arv_fetch.v:556/560/582/586 are reachable, revisit their coverage waivers %t ns", $time); error = error + 1; end
      else $display("PASS:  no fetch completed with the buffer at 5/6 halfwords %t ns", $time);

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

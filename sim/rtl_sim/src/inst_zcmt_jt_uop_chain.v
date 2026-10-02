//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zcmt_jt_uop_chain
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Table jump landing directly on another micro-op instruction.
//
//   The firmware runs micro-ops in the branch shadow of cm.jt / cm.jalt and lands
//   on targets that themselves begin with a micro-op -- the tightest back-to-back
//   dispatch the ISA allows.
//
//   The JT_IDLE arm's `if (!jt_completed)` guard is waived as unreachable
//   (waivers_cov.md). This monitors that premise: jt_completed is only ever high
//   in the cycle after jt_done, when ex_jt_active is already low, so the case is
//   not evaluated. If that ever stops holding the waiver is wrong.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define JT_SEQ dut.WITH_UOP_SEQUENCER.arv_uop_sequencer_inst

reg jt_guard_seen;
initial jt_guard_seen = 1'b0;

// JT_IDLE (2'd0) with the table jump active and already completed --
// the condition guarded by `if (!jt_completed)` in the JT_IDLE arm.
always @(posedge free_clk)
   if ((`JT_SEQ.WITH_ZMT.jt_state == 2'd0) &&
        `JT_SEQ.ex_jt_active && `JT_SEQ.jt_completed)
      jt_guard_seen <= 1'b1;

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
      $display("|        TABLE JUMP LANDING DIRECTLY ON ANOTHER MICRO-OP             |");
      $display(" ====================================================================");
      $display("");

      wait (probes_cpu.x31 == 32'h11111111);

      wait (probes_cpu.x31 == 32'hDEADBEEF || probes_cpu.x31 == 32'hBADC0DE0);

      check_cpu_reg(30, 32'h00000000);     // error code
      check_cpu_reg(18, 32'd4);            // cm.jt links taken
      check_cpu_reg(19, 32'd2);            // cm.jalt links taken
      check_cpu_reg(31, 32'hDEADBEEF);     // Test complete marker

      $display("");
      if (jt_guard_seen)
         begin $display("ERROR: JT_IDLE reached with jt_completed set -- arv_uop_sequencer.v:351 is reachable, revisit its coverage waiver %t ns", $time); error = error + 1; end
      else $display("PASS:  jt_completed never observed in the JT_IDLE arm %t ns", $time);
      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

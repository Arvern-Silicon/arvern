//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_zcmp_pop_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CM.POP LOAD ACCESS-FAULT ABORT
//   Discriminators (read from scratchpad after recovery):
//   The load access fault is now an RNMI (mncause=0x80000003), not mcause=5.
//   nmi_count     @ 0x24 -- must equal 1: the sequencer must not keep issuing
//                           transfers whose error responses re-trigger delivery
//   mncause       @ 0x28 -- expect 0x80000003 (bus error)
//   trap_count    @ 0x00 -- must be 0: mtvec is a NEGATIVE CONTROL, cause 5/7
//                           are RESERVED
//   last MCAUSE   @ 0x04 -- must be 0 for the same reason
//   s0 captured   @ 0x10 -- expect 0xA0A0A0A0 (pre-pop sentinel)
//   s2 captured   @ 0x18 -- expect 0xA2A2A2A2 (pre-pop sentinel): an aborted
//                           cm.pop must not write its destination registers
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // We expect at least one access-fault trap in this test by design.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init complete
      //=================================================================
      $display("");
      $display(" PHASE 1: init complete");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : program_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler address not published %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
         end
      end

      @(probes_cpu.x31==32'h22222222);
      $display(" mnstatus.NMIE armed -- the bus error must now be DELIVERED");


      //=================================================================
      // PHASE 2: cm.pop with sp=0 -> wait for recovery
      //=================================================================
      $display("");
      $display(" PHASE 2: cm.pop {ra,s0-s2}, 16 at sp=0");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 3: end-of-test sentinel + scratchpad checks
      //
      // Use wait() (level) not @() (edge) -- x31 may already be 0xdeadbeef
      // by the time we reach this wait.
      //=================================================================
      $display("");
      $display(" PHASE 3: scratchpad checks");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(10) @(posedge free_clk);

      // Must deliver EXACTLY one RNMI (the very first load's error).
      // The original bug this test was written for: the sequencer keeps issuing
      // AHB transfers after the abort, and each error response re-triggers
      // delivery. Asynchronous reporting does not change that obligation.
      $display("");
      $display("--- exactly one RNMI, cause = bus error ---");
      check_mem_value(`SPAD(32'h24), 32'h00000001);
      check_mem_value(`SPAD(32'h28), 32'h80000003);

      // mtvec is a negative control: mcause 5/7 are RESERVED,
      // so no synchronous trap may be taken at all.
      $display("");
      $display("--- mtvec must NEVER be entered ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      // s0 / s2 must still hold their pre-pop sentinel values.
      check_mem_value(`SPAD(32'h10), 32'hA0A0A0A0);
      check_mem_value(`SPAD(32'h18), 32'hA2A2A2A2);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

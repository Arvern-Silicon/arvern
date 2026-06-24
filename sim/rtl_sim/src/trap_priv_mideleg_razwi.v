//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_mideleg_razwi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SU_MODE PRIV - mideleg/medeleg RAZ/WI under SU_MODE_EN=0
//   Verify mideleg (0x303) and medeleg (0x302) silently drop writes and
//   always read 0. No trap may fire on either access.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

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

      // No trap expected; trap_count is the authoritative no-trap check.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: mideleg RAZ/WI
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 2: MIDELEG (0x303) RAZ/WI                              |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- mideleg readback after write 0xFFFFFFFF (expect 0) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000000);


      //=================================================================
      // PHASE 3: medeleg RAZ/WI
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 3: MEDELEG (0x302) RAZ/WI                              |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- medeleg readback after write 0xFFFFFFFF (expect 0) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000000);


      //=================================================================
      // FINAL: trap_count must still be 0 (RAZ/WI accesses don't trap)
      //=================================================================
      $display("");
      $display("--- trap_count = 0 (mideleg/medeleg accesses didn't trap) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

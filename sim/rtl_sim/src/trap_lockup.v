//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_lockup
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: LOCKUP
//   Lockup state verification:
//   - Exception from M-mode context -> enters M-mode handler
//   - Second exception inside M-mode handler -> go_to_lockup fires
//   - lockup_o asserted, fetch permanently stalled
//   - Verified: m_trap_count=1, MCAUSE=2, lockup_o stays high
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

      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Scratchpad zeroed before lockup ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // PHASE 2: Lockup entry
      // After x31=0x11111111: firmware executes .word 0xFFFFFFFF in
      // M-mode -> M-mode handler entered (in_m_excp_trap=1) -> handler
      // executes second .word 0xFFFFFFFF -> go_to_lockup=1 -> in_lockup=1
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: LOCKUP ENTRY (double M-mode exception)                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for lockup_o to assert...");

      @(posedge lockup);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- lockup_o assertion ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o not asserted after double M-mode exception %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o asserted -- CPU entered lockup state %t ns", $time);
      end

      $display("");
      $display("--- M-mode trap count (expect 1: handler entered once before lockup) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE (expect 2 = illegal instruction) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000002);


      //=================================================================
      // PHASE 3: Verify CPU is frozen (lockup_o stays asserted)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 3: VERIFY FETCH FROZEN (lockup_o remains asserted)        |");
      $display(" ====================================================================");
      $display("");

      repeat(50) @(posedge free_clk);

      $display("");
      $display("--- lockup_o persistence (50 cycles later) ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o de-asserted unexpectedly -- CPU should stay frozen %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o remains asserted -- no spurious exit from lockup %t ns", $time);
      end

      $display("");
      $display("--- Scratchpad unchanged after lockup (trap count still 1) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(10) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

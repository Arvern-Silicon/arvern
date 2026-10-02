//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_smrnmi_mnpp_after_mnret
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SMRNMI - mnstatus.MNPP IS REWRITTEN TO M BY MNRET
//   Lock-in test for the accepted deviation of the same name in
//   doc/spec_compliance_notes.md. MNPP holds the privilege at RNMI entry
//   (checked: M for an RNMI taken in M, U for one taken in U), but MNRET
//   rewrites it to M, so it cannot be used to recover the pre-RNMI privilege
//   after the return. sail-riscv leaves it unchanged; the field is WARL and
//   Smrnmi says nothing about the post-MNRET value.
//
//   The testbench asserts the NMI pin twice (once while the hart runs in
//   M-mode, once while it runs in U-mode) and checks the four mnstatus
//   snapshots the firmware leaves in the scratchpad.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

// mnstatus field positions (Smrnmi): NMIE bit 3, MNPP bits 12:11.
`define MNPP(w)  (((w) >> 11) & 2'b11)
`define NMIE(w)  (((w) >>  3) & 1'b1)

task check_mnstatus(input [255:0] what, input [31:0] word,
                    input [1:0] exp_mnpp, input exp_nmie);
   begin
      if (`MNPP(word) !== exp_mnpp) begin
         $display("ERROR: %0s: MNPP=%0d (expected %0d), mnstatus=0x%h %t ns",
                  what, `MNPP(word), exp_mnpp, word, $time);
         error = error + 1;
      end else if (`NMIE(word) !== exp_nmie) begin
         $display("ERROR: %0s: NMIE=%0d (expected %0d), mnstatus=0x%h %t ns",
                  what, `NMIE(word), exp_nmie, word, $time);
         error = error + 1;
      end else begin
         $display("PASS:  %0s: MNPP=%0d NMIE=%0d (mnstatus=0x%h) %t ns",
                  what, `MNPP(word), `NMIE(word), word, $time);
      end
   end
endtask

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

      // RNMI entry and the ECALLs look like traps to the monitor.
      error_on_exception = 0;

      //=================================================================
      // PHASE 1: RNMI taken from M-mode
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 1: RNMI FROM M-MODE -> MNPP = M                             |");
      $display(" ====================================================================");
      $display("Waiting for the firmware (armed sentinel)...");
      wait (probes_cpu.x31 == 32'h11111111);

      repeat(5) @(posedge free_clk);
      @(negedge free_clk);
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI #1 asserted (3 cycles) and deasserted %t ns", $time);

      //=================================================================
      // PHASE 2: RNMI taken from U-mode
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: RNMI FROM U-MODE -> MNPP = U                             |");
      $display(" ====================================================================");
      $display("Waiting for the firmware (re-armed sentinel)...");
      wait (probes_cpu.x31 == 32'h22222222);

      repeat(5) @(posedge free_clk);
      @(negedge free_clk);
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI #2 asserted (3 cycles) and deasserted %t ns", $time);

      //=================================================================
      // PHASE 3: both deliveries done - check the four snapshots
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: MNPP READ-BACK                                           |");
      $display(" ====================================================================");
      wait (probes_cpu.x31 == 32'hdeadbeef);
      repeat(40) @(posedge free_clk);          // drain the posted stores

      random_irq_enable = 0;

      check_mem_value(`SPAD(32'h00), 32'h00000002);   // two RNMI deliveries
      check_mem_value(`SPAD(32'h04), 32'h00000002);   // two ECALLs
      check_mem_value(`SPAD(32'h20), 32'h00000001);
      check_mem_value(`SPAD(32'h24), 32'h00000002);

      // Entry privilege is captured correctly...
      check_mnstatus("RNMI #1 handler (entered from M)",
                     ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)], 2'b11, 1'b0);
      check_mnstatus("RNMI #2 handler (entered from U)",
                     ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)], 2'b00, 1'b0);

      // ...and MNRET rewrites it to M in both cases - the deviation this test
      // locks in. The first handler wrote MNPP=U before returning, the second
      // left it at the captured U; after MNRET both read M.
      $display("--- MNRET rewrites MNPP to M (accepted deviation; sail leaves it) ---");
      check_mnstatus("after mnret #1 (handler had written MNPP=U)",
                     ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)], 2'b11, 1'b1);
      check_mnstatus("after mnret #2 (MNPP left at the captured U)",
                     ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)], 2'b11, 1'b1);

      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

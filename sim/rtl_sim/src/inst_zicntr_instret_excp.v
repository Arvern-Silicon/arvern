//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_instret_excp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR -- minstret must not count trapping instructions
//   Each probe measures (minstret at handler entry) - (minstret just before the
//   faulting instruction). Only the reading csrr itself may be counted, so a
//   compliant core reports 1. Reporting 2 means the faulting instruction was
//   counted -- the pre-fix behaviour.
//
//   The interrupt probe is the negative control: a spurious undo applied to
//   interrupts would show up as one LESS than the expected delta.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

task check_no_undo(input integer slot, input [255:0] what);
   reg [31:0] d;
   begin
      d = ahb_bus_system_inst.sram_x_inst.mem[slot];
      $display("     %0s: delta = %0d", what, d);
      if (d < 2) begin
         $display("ERROR: delta %0d means the RNMI un-retired the access -- an", d);
         $display("       asynchronous report must not roll back a retired instruction %t ns", $time);
         error = error + 1;
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

      error_on_exception = 0;   // the exceptions ARE the subject matter
      use_aclint         = 1;   // MSIP for the interrupt negative control

      // The illegal-instruction probe is a hand-written .word 0x00000000, which
      // has no entry in the disassembly the instruction_pc_checker is built from,
      // so it reports a false mismatch (1 error => SIMULATION FAILED) even though
      // every memory check passes. Same precedent as trap_no_c_misencoded.v and
      // inst_zca_lui.v. Restored before stimulus_done.
      tb_arvern.checker_enable = 0;

      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CONFIGURED                                |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : program_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler address not published %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
         end
      end

      @(probes_cpu.x31==32'h1E1E1E1E);

      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: SYNC EXCEPTIONS MUST NOT INCREMENT MINSTRET (delta = 1)  |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- ID stage: ECALL (expect 1) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- ID stage: EBREAK (expect 1) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000001);

      $display("");
      $display("--- ID stage: illegal instruction (expect 1) ---");
      check_mem_value(`SPAD(32'h08), 32'h00000001);

      $display("");
      $display("--- EX stage: load address misaligned (expect 1) ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000001);

      $display("");
      $display("--- EX stage: store address misaligned (expect 1) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000001);

      // Causes 5 and 7 are RNMIs now, and minstret_undo is gated on
      // ~trap_is_nmi -- so these two must NOT be un-retired. Asserting the
      // property rather than the exact delta: how many younger instructions
      // committed before the async report lands is a function of bus timing.
      $display("");
      $display("--- WB stage: bus errors are RNMIs -- must NOT un-retire ---");
      check_no_undo(`SPAD(32'h14), "load access fault");
      check_no_undo(`SPAD(32'h18), "store access fault");

      $display("--- PRECISION PROBE (diagnostic): instruction after a WB-class fault ---");
      $display("     after load access fault : s6 = %0d  (4 = ran once, 8 = committed then re-ran)",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)]);
      $display("     after store access fault: s7 = %0d  (4 = ran once, 8 = committed then re-ran)",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h3C)]);

      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: NEGATIVE CONTROL -- AN IRQ MUST NOT UN-RETIRE             |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      // 3, not 2: aRVern recognises the unmasked IRQ one instruction after the
      // csrs, so the following nop retires too. Taking an asynchronous interrupt
      // a little late is architecturally fine. The POINT of the check is that it
      // is not 2 -- a decrement wrongly applied to interrupts would land there.
      $display("--- Interrupt: must NOT be un-retired (expect 3; a spurious undo gives 2) ---");
      check_mem_value(`SPAD(32'h1C), 32'h00000003);

      @(probes_cpu.x31==32'hdeadbeef);
      tb_arvern.checker_enable = 1;   // restore default
      random_irq_enable = 0;
      repeat(10) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ldfault_vs_ecall
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: precise-exception ordering -- load access fault vs. ECALL.
//
//   An older load taking an AHB bus error (mcause=5) is immediately followed
//   by an ECALL (mcause=11). On correct RTL the load fault traps FIRST
//   (mcause=5, mepc=&lw, rd not written), the handler skips the lw, and the
//   ecall then traps (mcause=11, mepc=&ecall): two traps in program order.
//   On buggy RTL the younger ECALL raises its exception while the load's
//   error response is still in flight and the load fault is silently
//   dropped: a single trap with mcause=11.
//
//   Firmware records each trap's (mcause, mepc) in scratchpad slots and the
//   expected mepc addresses; this testbench checks counts, causes, mepc
//   values, and that the faulting load never wrote its destination register.
//
//   Phase A = back-to-back lw;ecall (the race).
//   Phase B = control: lw ; 4x nop ; ecall -- must pass even on buggy RTL,
//   documenting that the Phase A failure is a race-window issue.
//
//   Fail signature on buggy RTL (Phase A checks):
//     scratch[0x70] (phase A trap count) = 1 instead of 2
//     scratch[0x10] (first mcause)       = 11 instead of 5
//     scratch[0x14] (first mepc)         = &ecall instead of &lw
//     scratch[0x18]/[0x1C] (second trap) = 0 (never recorded)
//----------------------------------------------------------------------------

task check_mepc_is(input integer got_slot, input integer exp_slot, input [63:0] what);
   begin
      if (ahb_bus_system_inst.sram_x_inst.mem[got_slot] !==
          ahb_bus_system_inst.sram_x_inst.mem[exp_slot]) begin
         $display("ERROR: MEPC 0x%h != expected %0s 0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[got_slot], what,
                  ahb_bus_system_inst.sram_x_inst.mem[exp_slot], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MEPC = %0s = 0x%h %t ns", what,
                  ahb_bus_system_inst.sram_x_inst.mem[got_slot], $time);
      end
   end
endtask

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

      // This test deliberately triggers load-access-faults and ecalls;
      // tell the monitor not to flag them as test errors.
      error_on_exception = 0;

      //=================================================================
      // PHASE 1: Initialization
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hFFFFFFFF);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);   // no trap yet

      begin : program_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h78)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler address not published %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
         end
      end

      @(probes_cpu.x31==32'hEEEEEEEE);

      //=================================================================
      // PHASE A: back-to-back lw(fault) ; ecall -- precise ordering
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|      PHASE A: LOAD ACCESS FAULT vs ECALL (back-to-back race)       |");
      $display(" ====================================================================");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Phase A: exactly ONE synchronous trap, the ECALL ---");
      check_mem_value(`SPAD(32'h70), 32'h00000001);
      check_mem_value(`SPAD(32'h10), 32'h0000000B);
      check_mepc_is(`SPAD(32'h14), `SPAD(32'h64), "&ecall");

      $display("");
      $display("--- ...and the bus error arrives separately, as an RNMI ---");
      check_mem_value(`SPAD(32'h7C), 32'h00000001);
      check_mem_value(`SPAD(32'h80), 32'h80000003);


      //=================================================================
      // PHASE B: control -- lw(fault) ; 4x nop ; ecall
      //   Ordering unambiguous even on buggy RTL: documents that the
      //   Phase A failure is a race-window issue.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|      PHASE B: CONTROL (lw fault spaced 4 nops before ecall)        |");
      $display(" ====================================================================");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Total synchronous traps (2 forced + 1 ECALL from Phase B) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      $display("");
      $display("--- Phase B: the ECALL again, and a second RNMI ---");
      check_mem_value(`SPAD(32'h20), 32'h0000000B);
      check_mem_value(`SPAD(32'h7C), 32'h00000002);
      check_mepc_is(`SPAD(32'h24), `SPAD(32'h6C), "&ecall");

      //=================================================================
      // END OF TEST: faulting loads must never have written t3 (x28).
      //   s2 (x18) = t3 sampled right after Phase A,
      //   s3 (x19) = t3 sampled right after Phase B,
      //   t3 (x28) itself is untouched after Phase B.
      //=================================================================
      wait(probes_cpu.x31 === 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Faulting load must not update its destination register ---");
      // Still true after the flip: dph_valid is gated on !hresp, so an errored
      // load never strobes the register write.
      check_cpu_reg(18, 32'hBADBAD05);   // s2: t3 after Phase A
      check_cpu_reg(19, 32'hBADBAD05);   // s3: t3 after Phase B
      check_cpu_reg(28, 32'hBADBAD05);   // t3 still holds the sentinel

      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

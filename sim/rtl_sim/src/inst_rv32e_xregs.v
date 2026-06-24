//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_rv32e_xregs
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: RV32E UPPER-REGISTER BEHAVIOUR
//   CONTRACT TEST -- locks in arvern's EMPIRICALLY-VERIFIED (waveform-
//   traced) handling of a SPEC-PERMITTED case (NOT a deviation). RISC-V
//   RV32E makes x16..x31 encodings *reserved* => behaviour UNSPECIFIED (no
//   trap mandated by the base ISA), so no-trap is permitted -- same class as
//   reserved OP/OP-IMM funct7. A platform/profile MAY mandate the trap
//   this contract would flip there (decode-side trap added).
//
//   VERIFIED THREE-PART CONTRACT:
//   (1) referencing x16..x31 NEVER raises illegal-instruction (trap_count
//   stays 0);
//   (2) the register file IS RV32E-aware -- a NON-forwarded read of an
//   upper reg yields 0;
//   (3) decode/forwarding is NOT RV32E-aware -- an adjacent write->read of
//   the SAME upper reg forwards the written value; the value is a pure
//   bypass artefact and is NOT persisted (a later, out-of-window read
//   of the same reg reads 0).
//
//   SYNC MAP:
//   SYNC A   x15 == 0x11111111  handler installed, trap_count zeroed.
//   .v checks ONLY trap_count==0 here (no
//   result regs sampled -- avoids the old
//   sentinel-phase race).
//   FINAL    x15 == 0xdeadbeef  LEVEL wait. .v asserts trap_count==0 AND
//   x5,x6,x7,x8,x9 (see PASS criteria).
//
//   PASS criteria (all sampled at FINAL):
//   - scratchpad trap_count (word @ 0x00) == 0  (contract part 1, no trap)
//   - x5 == 0x00000123  read x16 right after write -> FORWARDED (part 3)
//   - x6 == 0x00000000  read x24, no in-flight write -> regfile-0 (part 2)
//   - x7 == 0x00000000  read x31 before any write   -> regfile-0 (part 2)
//   - x8 == 0x00000456  read x31 right after write  -> FORWARDED (part 3)
//   - x9 == 0x00000000  read x16 again, out of fwd window, no recent
//   write -> regfile-0: PROVES non-persistence (the
//   0x123 x5 saw was never stored) (parts 2+3)
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

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // This test deliberately exercises upper-register encodings. The
      // contract is that they do NOT trap, but disable the testbench's
      // auto-abort-on-exception so a (failing) spurious trap does not
      // kill the run before we can assert trap_count == 0.
      error_on_exception = 0;


      $display("");
      $display(" ====================================================================");
      $display("|   RV32E XREGS CONTRACT: SYNC A -- handler installed, count zeroed  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h11111111);   // SYNC A: handler installed
      repeat(3) @(posedge free_clk);

      // Only assertion at SYNC A: trap_count starts at 0. No result
      // registers are sampled here -- the probe sequence has not run
      // yet, and sampling x5..x9 at a checkpoint they get mutated
      // around was the old sentinel-phase race.
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // trap_count == 0


      $display("");
      $display(" ====================================================================");
      $display("|   RV32E XREGS CONTRACT: FINAL -- forwarded vs regfile-0 vs         |");
      $display("|                          non-persistent upper-register reads      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      wait(probes_cpu.x15==32'hdeadbeef);   // FINAL SYNC (LEVEL wait)
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Contract part 1: no illegal-instruction trap ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // trap_count == 0

      $display("");
      $display("--- Contract part 3: adjacent write->read of same upper reg");
      $display("    FORWARDS the written value (pure bypass artefact) ---");
      check_cpu_reg(5, 32'h00000123);   // read x16 right after write -> fwd
      check_cpu_reg(8, 32'h00000456);   // read x31 right after write -> fwd

      $display("");
      $display("--- Contract part 2: register file is RV32E-aware --");
      $display("    a NON-forwarded read of an upper reg yields 0 ---");
      check_cpu_reg(6, 32'h00000000);   // read x24, no in-flight write -> 0
      check_cpu_reg(7, 32'h00000000);   // read x31 before any write    -> 0

      $display("");
      $display("--- Contract parts 2+3: NON-PERSISTENCE -- x16 read again,");
      $display("    out of the forwarding window, no recent write -> 0");
      $display("    (the 0x123 x5 saw was never architecturally stored) ---");
      check_cpu_reg(9, 32'h00000000);   // read x16 again, out of window -> 0

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

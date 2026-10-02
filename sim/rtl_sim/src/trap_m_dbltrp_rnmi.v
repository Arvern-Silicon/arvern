//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_m_dbltrp_rnmi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Smdbltrp double trap diverted to the RNMI handler (NMIE=1)
//   Phase A  double trap -> RNMI: mncause=2 (interrupt bit CLEAR), mnepc = the
//            faulting PC, and mepc/mcause still hold phase A's ECALL -- proof
//            the M trap stack was not written.
//   Phase C  handler clears MDT -> nested trap goes to mtvec, no divert.
//   Phase D  pin NMI after the divert: mncause = 0x80000002 (bit 31 set again).
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] rnmi_addr, expect_mnepc, expect_mepc;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      //=================================================================
      // Program the RNMI vector from the address the firmware published
      //=================================================================
      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|      Smdbltrp: M-mode double trap diverted to the RNMI handler      |");
      $display(" ====================================================================");
      $display("");

      rnmi_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];
      if (rnmi_addr == 32'h0) begin
         $display("ERROR: rnmi_handler address not published %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  nmi_vector programmed to 0x%h %t ns", rnmi_addr, $time);
      end

      @(probes_cpu.x31 == 32'h22222222);
      $display("mnstatus.NMIE armed -- a double trap must now DIVERT, not lock up %t ns", $time);

      //=================================================================
      // PHASE A -- the divert itself
      //=================================================================
      @(probes_cpu.x31 == 32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- phase A: ECALL -> handler faults with MDT set -> RNMI ---");

      $display("");
      $display("--- the RNMI handler ran exactly once ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- mncause = 2, interrupt bit CLEAR (Priv 8.3) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000002);

      begin : mnepc_check
         expect_mnepc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         $display("");
         $display("--- mnepc names the faulting instruction inside the handler ---");
         check_mem_value(`SPAD(32'h08), expect_mnepc);
      end

      begin : m_stack_check
         expect_mepc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];
         $display("");
         $display("--- mepc still holds phase A's ECALL: the M stack was NOT written ---");
         check_mem_value(`SPAD(32'h0C), expect_mepc);
         $display("");
         $display("--- mcause still 11 (ECALL-from-M), not 2 ---");
         check_mem_value(`SPAD(32'h10), 32'h0000000B);
      end

      $display("");
      $display("--- lockup_o must be LOW: NMIE was armed, so no critical error ---");
      if (lockup !== 1'b0) begin
         $display("ERROR: lockup_o asserted although the double trap was divertible %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o low %t ns", $time);
      end

      //=================================================================
      // PHASE C -- a handler that clears MDT takes ordinary nested traps
      //=================================================================
      @(probes_cpu.x31 == 32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|   PHASE C: handler clears MDT -> nested trap delivered to mtvec     |");
      $display(" ====================================================================");
      $display("");

      $display("--- handler C entered twice (original fault + nested fault) ---");
      check_mem_value(`SPAD(32'h14), 32'h00000002);

      $display("");
      $display("--- RNMI count still 1: the nested trap did NOT divert ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      //=================================================================
      // PHASE D -- pin NMI after the divert: mncause is an interrupt again
      //=================================================================
      wait(probes_cpu.x31 == 32'h55555555);
      repeat(5) @(posedge free_clk);
      nmi = 1'b1;
      repeat(5) @(posedge free_clk);
      nmi = 1'b0;

      wait(probes_cpu.x31 == 32'h66666666);
      repeat(40) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|   PHASE D: pin NMI after the divert -> mncause = 0x80000002        |");
      $display(" ====================================================================");
      $display("");
      $display("--- handler D entered once ---");
      check_mem_value(`SPAD(32'h2C), 32'h00000001);
      $display("");
      $display("--- mncause = 0x80000002: interrupt bit set again (Priv 8.3) ---");
      check_mem_value(`SPAD(32'h28), 32'h80000002);
      if ((ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)] & 32'h1808) !== 32'h1800) begin
         $display("ERROR: mnstatus at handler D entry 0x%h: expected MNPP=M, NMIE=0 %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)], $time);
         error = error + 1;
      end else
         $display("PASS:  mnstatus at handler D entry MNPP=M, NMIE=0 %t ns", $time);
      $display("");
      $display("--- divert RNMI count unchanged ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31 == 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

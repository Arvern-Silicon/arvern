//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_aclint_setssip
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ACLINT SSWI SETSSIP end-to-end (S-mode self-IPI)
//   With use_aclint=1, the ACLINT's irq_s_software_o is routed to the
//   core. M-mode sets mideleg.SSI=1, enables SIE.SSIE + SSTATUS.SIE, and
//   MRETs to S-mode. S-mode firmware writes SETSSIP[0]=1 -> ahb_aclint
//   emits a 1-cycle edge -> core latches MIP.SSIP -> takes the S-mode
//   SSI trap (scause = 0x80000001 because delegated) -> handler clears
//   MIP.SSIP via CSRC and SRETs.
//
//   The M-mode handler is the safety-net diagnostic path: if it fires,
//   delegation isn't working. The TB checks that M-mode handler count
//   stays 0 and logs the M-side mcause/mepc for diagnostics.
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
      use_aclint         = 1'b1;


      //=================================================================
      // PHASE 1: M-mode configures + drops to S-mode (SSI delegated)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|     PHASE 1: M-MODE CONFIG + MRET TO S-MODE (SSI DELEGATED)        |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      $display("PASS:  Phase 1 - SSI delegated to S-mode, dropping to S %t ns", $time);


      //=================================================================
      // PHASE 2: S-mode SETSSIP -> SSI trap (S-mode) -> handler clears
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 2: S-MODE SETSSIP -> SSI TRAP -> HANDLER CLEAR         |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- S-mode trap count + last SCAUSE ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // s_trap_count = 1
      check_mem_value(`SPAD(32'h04), 32'h80000001);   // SCAUSE = SSI (1, MSB set)

      $display("");
      $display("--- M-mode trap count (must be 0 -- delegation should fire S) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000000);   // m_trap_count = 0
      // 0x14 / 0x18 are diagnostic-only

      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_smode_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: S-MODE WARL CSRs + SIE/SIP MIDELEG MASK
//   Checks that scounteren / senvcfg / menvcfg / menvcfgh / satp are now
//   accessible (no illegal-instruction trap), and that SIE read is masked by
//   mideleg per Privileged spec §3.1.9.
//
//   menvcfgh (Ssdbltrp): only bit 27 (DTE) is writable, resets to
//   0x08000000 (DTE=1); all other bits read 0.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

// A counter-enable bit for a counter that is not implemented is read-only zero,
// the same rule arv_csr_hpm.v applies to mcounteren's HPM bits.
localparam [7:0]  SCOUNTEREN_HPM_MASK = (ZIHPM_NR >= 8) ? 8'hFF : ((8'h01 << ZIHPM_NR) - 8'h01);
localparam [2:0]  SCOUNTEREN_STD_MASK = (ZICNTR_EN != 0) ? 3'b111 : 3'b000;
localparam [10:0] SCOUNTEREN_MASK     = {SCOUNTEREN_HPM_MASK, SCOUNTEREN_STD_MASK};

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


      //=================================================================
      // Wait for end-of-test sentinel
      //=================================================================
      $display("");
      $display(" Waiting for end-of-test sentinel");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(10) @(posedge free_clk);


      //=================================================================
      // Verify each WARL behavior
      //=================================================================

      // scounteren: a counter-enable bit for a counter that is not implemented
      // is read-only zero (same rule arv_csr_hpm.v applies to mcounteren), so
      // the 0x7E5 mid-write latches only where a counter actually exists:
      // bits 2:0 follow Zicntr, bits 10:3 follow ZIHPM_NR.
      check_mem_value(`SPAD(32'h00), 32'h000007E5 & {21'h0, SCOUNTEREN_MASK});

      // senvcfg / menvcfg / satp -- WARL hardwired zero
      check_mem_value(`SPAD(32'h04), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000000);
      check_mem_value(`SPAD(32'h10), 32'h00000000);

      // menvcfgh (Ssdbltrp): reset value DTE=1
      check_mem_value(`SPAD(32'h0C), 32'h08000000);
      // menvcfgh after write 0xFFFFFFFF: only bit 27 latches
      check_mem_value(`SPAD(32'h20), 32'h08000000);
      // menvcfgh after write 0: DTE writable both ways
      check_mem_value(`SPAD(32'h24), 32'h00000000);
      // menvcfgh after restoring DTE=1
      check_mem_value(`SPAD(32'h28), 32'h08000000);

      // SIE with mideleg=0 must read 0
      check_mem_value(`SPAD(32'h14), 32'h00000000);

      // SIE with mideleg=0x222 must read 0x222 (delegated bits visible)
      check_mem_value(`SPAD(32'h18), 32'h00000222);

      // trap_count == 0 -- none of the CSR accesses should have trapped
      check_mem_value(`SPAD(32'h1C), 32'h00000000);

      // sscratch is a plain 32-bit R/W CSR: all bits must store, both ways.
      check_mem_value(`SPAD(32'h2C), 32'hAAAAAAAA);
      check_mem_value(`SPAD(32'h30), 32'h55555555);
      check_mem_value(`SPAD(32'h34), 32'hFFFFFFFF);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

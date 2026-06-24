//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_aclint_mtimer
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ACLINT MTIMER end-to-end (MTIP via MTIMECMP)
//   Selects the ACLINT outputs for MSIP/MTIP/SSIP via use_aclint=1, then
//   waits for the firmware to:
//     - Read MTIME (LO-then-HI atomic-snapshot contract)
//     - Program MTIMECMP = mtime + 0x80
//     - Enable MIE.MTIE + MSTATUS.MIE
//     - Take exactly one MTI trap (mcause = 0x80000007) once the LF
//       comparator fires and the hclk_aon synchronizer propagates
//     - Park MTIMECMP at all-ones in the handler to drop MTIP and MRET
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

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
      // PHASE 1: firmware configures ACLINT MTIMER
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: ACLINT MTIMER CONFIGURED                  |");
      $display(" ====================================================================");
      $display("Waiting for the firmware to program MTIMECMP and enable MIE.MTIE...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : show_snapshot
         reg [31:0] lo;
         reg [31:0] hi;
         lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         hi = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         $display("Firmware-sampled MTIME = 0x%h_%h", hi, lo);
      end
      $display("PASS:  Phase 1 - firmware configured ACLINT MTIMER %t ns", $time);


      //=================================================================
      // PHASE 2: wait for the MTI trap
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: MTI TAKEN VIA ACLINT MTIMER               |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- Trap count + last MCAUSE ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // trap_count = 1
      check_mem_value(`SPAD(32'h04), 32'h80000007);   // MCAUSE = MTI

      stimulus_done = 1;
   end

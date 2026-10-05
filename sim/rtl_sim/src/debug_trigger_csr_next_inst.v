//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_csr_next_inst
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: execute-trigger CSR writes take effect for the very next
// instruction, in both directions (see the .s).
//----------------------------------------------------------------------------
`define SPAD(byte_off)  ((byte_off)/4)

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|   TRIGGER CSR WRITES SEEN BY THE VERY NEXT INSTRUCTION             |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(40) @(posedge free_clk);
      $display("INFO:  breakpoints taken: %0d (expected 2)", probes_cpu.x08);
      $display("INFO:  mepc #1 = 0x%h (tgt4 = 0x%h), mepc #2 = 0x%h (tgt5 = 0x%h)",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)], probes_cpu.x10,
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)], probes_cpu.x11);
      check_cpu_reg(8, 32'd2);
      check_mem_value(`SPAD(32'h00), probes_cpu.x10);
      check_mem_value(`SPAD(32'h04), probes_cpu.x11);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

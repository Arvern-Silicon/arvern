//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_mnret_below_m
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MNRET executed below M-mode raises illegal instruction
//   Priv §8.4: "MNRET is an M-mode-only instruction". S- and U-mode MNRET
//   trap with cause 2 (mtval/stval 0), to M when medeleg[2]=0 and to S when
//   medeleg[2]=1; execution continues after the handler skips it; mnepc and
//   mnstatus.NMIE are untouched and bad_landing (the seeded mnepc) is never
//   reached.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] base;
reg [31:0] exp_id;
reg [31:0] exp_pp;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      wait(probes_cpu.x31 == 32'h11111111);
      $display("MNRET below M: init done %t ns", $time);

      wait(probes_cpu.x31 == 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|       MNRET in S / U: illegal instruction, execution continues     |");
      $display(" ====================================================================");

      for (kk = 0; kk < 4; kk = kk + 1)
         begin
            base   = 32'h100 + kk*32;
            exp_id = (kk < 2) ? 32'd1 : 32'd2;          // 1 = M handler, 2 = S handler
            exp_pp = (kk % 2 == 0) ? 32'd1 : 32'd0;     // S-origin cases 0/2, U-origin 1/3
            $display("");
            $display("--- case %0d: from %s, medeleg[2]=%0d ---", kk, (exp_pp ? "S" : "U"), (kk >= 2));
            check_mem_value(`SPAD(base + 0),  exp_id);
            check_mem_value(`SPAD(base + 4),  32'h00000002);
            check_mem_value(`SPAD(base + 8),  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(base + 20)]);
            check_mem_value(`SPAD(base + 12), 32'h00000000);
            check_mem_value(`SPAD(base + 16), exp_pp);
            check_mem_value(`SPAD(base + 24), 32'h600D0000 | kk);
            check_mem_value(`SPAD(base + 28), 32'h00000001);
         end

      $display("");
      $display("--- no MNRET executed, no unexpected cause ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h04), 32'h00000000);
      check_mem_value(`SPAD(32'h08), ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)]);
      if ((ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)] & 32'h8) !== 32'h8) begin
         $display("ERROR: mnstatus.NMIE cleared (mnstatus=0x%h) %t ns", ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)], $time);
         error = error + 1;
      end else
         $display("PASS:  mnstatus.NMIE still 1 %t ns", $time);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

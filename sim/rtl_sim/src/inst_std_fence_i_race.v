//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_fence_i_race
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: FENCE.I store-to-ifetch race -- minimum-distance self-modifying code
//
//   The firmware patches ADDI x10,x0,K and jumps to it with nothing but the
//   FENCE.I in between, 64 times per round with a different K each time. If a
//   fetch ever beats the store to memory the stale word executes and x10 holds
//   the PREVIOUS K, which the firmware detects and records.
//
//   A mismatch is a real Zifencei ordering failure, not a tolerance issue:
//   FENCE.I is architecturally required to order prior data writes against
//   subsequent instruction fetches, and those use separate AHB buses.
//
//   This stimulus pins the bus latencies itself rather than relying on random
//   timing variants, because the window is only ~3 cycles wide and needs to be
//   attacked deliberately: ROM latency delays the store's path to the bus,
//   SRAM_X latency moves the write's completion relative to the patch fetch.
//   The random enables are cleared so the sweep is deterministic under every
//   variant the matrix runs.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

integer    rnd;
integer    rom_ws  [0:5];
integer    sram_ws [0:5];
reg [31:0] miss_count, first_bad_k, observed_x10, bad_round;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // (ROM, SRAM_X) wait-state pairs, one per firmware round.
      rom_ws[0]  =  0;  sram_ws[0] = 0;   // baseline -- the 3-cycle margin
      rom_ws[1]  =  0;  sram_ws[1] = 3;   // slow write completion
      rom_ws[2]  =  3;  sram_ws[2] = 0;   // slow fetch stream
      rom_ws[3]  =  6;  sram_ws[3] = 0;
      rom_ws[4]  =  6;  sram_ws[4] = 3;
      rom_ws[5]  =  2;  sram_ws[5] = 5;   // write completion far behind the fetch

      for (rnd = 0; rnd < 6; rnd = rnd + 1) begin
         wait(probes_cpu.x31 == 32'h00000100 + rnd);
         @(negedge free_clk);
         s_rom_random_ws_en    = 0;
         s_sram_x_random_ws_en = 0;
         s_rom_number_ws       = rom_ws[rnd];
         s_sram_x_number_ws    = sram_ws[rnd];
         $display("round %0d: ROM ws=%0d, SRAM_X ws=%0d %t ns",
                  rnd, rom_ws[rnd], sram_ws[rnd], $time);
      end

      wait(probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      miss_count   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      first_bad_k  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
      observed_x10 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
      bad_round    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

      $display("");
      $display(" ====================================================================");
      $display("|   FENCE.I store-to-ifetch race: 6 rounds x 20 iterations          |");
      $display(" ====================================================================");
      $display("");

      if (miss_count !== 32'h0) begin
         $display("ERROR: FENCE.I did not order the store against the instruction fetch");
         $display("       %0d of 120 iterations executed a STALE instruction word", miss_count);
         $display("       first failure in round %0d at K=%0d: x10 read back 0x%h (expected 0x%h)",
                  bad_round, first_bad_k, observed_x10, first_bad_k);
         $display("       -- prior store still upstream of the data bus when the");
         $display("          instruction fetch of the patched address went out %t ns", $time);
         error = error + 1;
      end
      else begin
         $display("PASS:  all 120 patched words executed the value just stored %t ns", $time);
      end

      // The last iteration must still be visible in the register file: guards
      // against the firmware falling out of the loop early and reporting a
      // vacuous zero mismatch count.
      check_cpu_reg(10, 32'd20);

      //=================================================================
      // END OF TEST
      //=================================================================
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

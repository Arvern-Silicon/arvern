//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_aclint_mtime_write
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MTIME is read-write -- the `time` CSR follows a written MTIME
//   With use_aclint=1 the core's time_req_o / time_gnt_i / time_val_i port is
//   wired to the ACLINT, so `csrr time` returns MTIME. The firmware writes
//   MTIME through the ACLINT AHB window and reads it back over that CSR port,
//   which is a different path from the AHB read (its own shadow, its own slot
//   in the read FSM) -- so this covers the write reaching the LF counter, not
//   just an AHB register echoing back.
//
//   The counter never stops, so the low half is checked as a window rather
//   than an exact value: >= what was written, and close to it. A write that
//   never reached the LF domain would read back near zero.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

localparam [31:0] MTIME_WR_HI = 32'h00000055;
localparam [31:0] MTIME_WR_LO = 32'h20000000;

// Generous: the LF clock is slow relative to hclk, so the drift over the few
// hundred cycles between the write and the readback is small. The point of the
// bound is to separate "took the written value" from "read something else".
localparam [31:0] MTIME_DRIFT_MAX = 32'd10000;

reg [31:0] t0_lo;
reg [31:0] t0_hi;

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

      use_aclint = 1'b1;   // route the time CSR to the ACLINT

      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CONFIGURED                                |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);

      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: MTIME WRITTEN -- THE time CSR MUST FOLLOW IT             |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      t0_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      t0_hi = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

      $display("");
      $display("--- timeh after the write (expect 0x%h) ---", MTIME_WR_HI);
      check_mem_value(`SPAD(32'h04), MTIME_WR_HI);

      $display("");
      $display("--- time after the write (expect 0x%h + drift) ---", MTIME_WR_LO);
      if (t0_lo < MTIME_WR_LO) begin
         $display("ERROR: time is BELOW the written MTIME -- wrote 0x%h read 0x%h",
                  MTIME_WR_LO, t0_lo);
         error = error + 1;
      end else if ((t0_lo - MTIME_WR_LO) > MTIME_DRIFT_MAX) begin
         $display("ERROR: time is too far from the written MTIME -- wrote 0x%h read 0x%h (drift %0d)",
                  MTIME_WR_LO, t0_lo, (t0_lo - MTIME_WR_LO));
         error = error + 1;
      end else begin
         $display("PASS:  time followed the written MTIME -- 0x%h_%h (drift %0d LF ticks)",
                  t0_hi, t0_lo, (t0_lo - MTIME_WR_LO));
      end

      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: MTIME MUST STILL BE COUNTING AFTER THE WRITE             |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- second sample strictly greater than the first (expect 1) ---");
      $display("     first  = 0x%h_%h",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)]);
      $display("     second = 0x%h_%h",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)]);
      check_mem_value(`SPAD(32'h10), 32'h00000001);

      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: ORDERING -- time read racing a posted MTIME store        |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // DIAGNOSTIC. The store to MTIME is posted on the AHB data bus while the
      // time CSR is served by the ACLINT's separate Zicntr port. The read
      // hold-off can only start once the ACLINT has SEEN the write, so a CSR
      // read issued in the shadow of the store can overtake it entirely.
      $display("");
      $display("--- time read with no gap after the store (wrote 0x30000000) ---");
      $display("     time = 0x%h  (near 0x30000000 = store won; anything else = the read overtook it)",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)]);

      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(10) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_mcounteren
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR MCOUNTEREN GATING
//   mcounteren + scounteren gating of counter shadow CSRs (S-mode core).
//   U-mode read permitted iff mcounteren[i]=1 AND scounteren[i]=1.
//   S-mode read permitted iff mcounteren[i]=1 (scounteren ignored for S).
//   M-mode always permitted.
//
//   Each sub-phase is verified by its OWN trap-count DELTA (after-before),
//   never a global sticky mcause.  DENY: delta==1 (CANARY) & mcause==2
//   (supplementary).  ALLOW / S-mode-allow: delta==0 & value correct.
//   The DENY-B (mcen=1,scen=0) delta==1 check is the canary: it FAILS on a
//   buggy mcounteren-only implementation that wrongly allows the U-mode read
//   (no trap fired → delta==0), even though stale mcause still reads 2.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
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

      // Illegal-instruction exceptions are expected — do not fail on them
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: CY bit (mcounteren[0] / scounteren[0]) — cycle & cycleh
      //   DENY-A : mcen=0, scen=1 → fresh trap (delta==1), mcause==2
      //   DENY-B : mcen=1, scen=0 → fresh trap (delta==1), mcause==2
      //            *** CANARY: delta==0 on buggy mcounteren-only RTL ***
      //   ALLOW  : mcen=1, scen=1 → no trap (delta==0), nonzero read
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 1: MCOUNTEREN+SCOUNTEREN CY BIT — cycle AND cycleh         |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : check_phase1
         reg [31:0] trap_count;
         reg [31:0] cyc_dA_d, cyc_dA_m, cyc_dB_d, cyc_dB_m, cyc_al_d, cyc_al_v;
         reg [31:0] cyh_dA_d, cyh_dA_m, cyh_dB_d, cyh_dB_m, cyh_al_d, cyh_al_v;

         trap_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         cyc_dA_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         cyc_dA_m   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         cyc_dB_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
         cyc_dB_m   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];
         cyc_al_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         cyc_al_v   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];
         cyh_dA_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         cyh_dA_m   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];
         cyh_dB_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];
         cyh_dB_m   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)];
         cyh_al_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];
         cyh_al_v   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)];

         $display("illegal_trap_count (running, expect 4): %0d  %t ns", trap_count, $time);
         $display("cycle  deny-A delta/mcause (1/2): %0d / 0x%h", cyc_dA_d, cyc_dA_m);
         $display("cycle  deny-B delta/mcause (1/2): %0d / 0x%h", cyc_dB_d, cyc_dB_m);
         $display("cycle  allow  delta/value  (0/>0): %0d / 0x%h", cyc_al_d, cyc_al_v);
         $display("cycleh deny-A delta/mcause (1/2): %0d / 0x%h", cyh_dA_d, cyh_dA_m);
         $display("cycleh deny-B delta/mcause (1/2): %0d / 0x%h", cyh_dB_d, cyh_dB_m);
         $display("cycleh allow  delta/value  (0/* ): %0d / 0x%h", cyh_al_d, cyh_al_v);

         // ---- cycle DENY-A : mcen=0, scen=1 ----
         if (cyc_dA_d === 32'd1)
            $display("PASS:  cycle  deny-A delta=1 (fresh trap)  %t ns", $time);
         else begin
            $display("ERROR: cycle  deny-A delta=%0d, expected 1  %t ns", cyc_dA_d, $time);
            error = error + 1;
         end
         if (cyc_dA_m === 32'd2)
            $display("PASS:  cycle  deny-A mcause=2  %t ns", $time);
         else begin
            $display("ERROR: cycle  deny-A mcause=0x%h, expected 2  %t ns", cyc_dA_m, $time);
            error = error + 1;
         end

         // ---- cycle DENY-B : mcen=1, scen=0  (CANARY) ----
         if (cyc_dB_d === 32'd1)
            $display("PASS:  cycle  deny-B delta=1 (fresh trap; CANARY for scounteren gate)  %t ns",
                     $time);
         else begin
            $display("ERROR: cycle  deny-B delta=%0d, expected 1 — U-mode read wrongly ALLOWED (mcounteren-only RTL?)  %t ns",
                     cyc_dB_d, $time);
            error = error + 1;
         end
         if (cyc_dB_m === 32'd2)
            $display("PASS:  cycle  deny-B mcause=2 (supplementary)  %t ns", $time);
         else begin
            $display("ERROR: cycle  deny-B mcause=0x%h, expected 2  %t ns", cyc_dB_m, $time);
            error = error + 1;
         end

         // ---- cycle ALLOW : mcen=1, scen=1 ----
         if (cyc_al_d === 32'd0)
            $display("PASS:  cycle  allow delta=0 (no trap)  %t ns", $time);
         else begin
            $display("ERROR: cycle  allow delta=%0d, expected 0 (read wrongly DENIED?)  %t ns",
                     cyc_al_d, $time);
            error = error + 1;
         end
         if (cyc_al_v !== 32'd0)
            $display("PASS:  cycle  allow val=0x%h (nonzero, read succeeded)  %t ns", cyc_al_v, $time);
         else begin
            $display("ERROR: cycle  allow val=0 (expected nonzero)  %t ns", $time);
            error = error + 1;
         end

         // ---- cycleh DENY-A : mcen=0, scen=1 ----
         if (cyh_dA_d === 32'd1)
            $display("PASS:  cycleh deny-A delta=1 (fresh trap)  %t ns", $time);
         else begin
            $display("ERROR: cycleh deny-A delta=%0d, expected 1  %t ns", cyh_dA_d, $time);
            error = error + 1;
         end
         if (cyh_dA_m === 32'd2)
            $display("PASS:  cycleh deny-A mcause=2  %t ns", $time);
         else begin
            $display("ERROR: cycleh deny-A mcause=0x%h, expected 2  %t ns", cyh_dA_m, $time);
            error = error + 1;
         end

         // ---- cycleh DENY-B : mcen=1, scen=0  (CANARY) ----
         if (cyh_dB_d === 32'd1)
            $display("PASS:  cycleh deny-B delta=1 (fresh trap; CANARY for scounteren gate)  %t ns",
                     $time);
         else begin
            $display("ERROR: cycleh deny-B delta=%0d, expected 1 — U-mode read wrongly ALLOWED (mcounteren-only RTL?)  %t ns",
                     cyh_dB_d, $time);
            error = error + 1;
         end
         if (cyh_dB_m === 32'd2)
            $display("PASS:  cycleh deny-B mcause=2 (supplementary)  %t ns", $time);
         else begin
            $display("ERROR: cycleh deny-B mcause=0x%h, expected 2  %t ns", cyh_dB_m, $time);
            error = error + 1;
         end

         // ---- cycleh ALLOW : mcen=1, scen=1 ----
         if (cyh_al_d === 32'd0)
            $display("PASS:  cycleh allow delta=0 (no trap)  %t ns", $time);
         else begin
            $display("ERROR: cycleh allow delta=%0d, expected 0  %t ns", cyh_al_d, $time);
            error = error + 1;
         end
         $display("PASS:  cycleh allow val=0x%h (mcen=1,scen=1 succeeded)  %t ns", cyh_al_v, $time);

         // Running trap_count sanity (secondary; per-phase deltas are authoritative)
         if (trap_count === 32'd4)
            $display("PASS:  illegal_trap_count = 4 (running, cycle/cycleh deny-A,deny-B)  %t ns",
                     $time);
         else begin
            $display("ERROR: illegal_trap_count = %0d, expected 4 (running)  %t ns",
                     trap_count, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 2: IR bit (mcounteren[2] / scounteren[2]) — instret & instreth
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: MCOUNTEREN+SCOUNTEREN IR BIT — instret AND instreth     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      begin : check_phase2
         reg [31:0] trap_count;
         reg [31:0] ir_dA_d, ir_dA_m, ir_dB_d, ir_dB_m, ir_al_d, ir_al_v;
         reg [31:0] irh_dA_d, irh_dA_m, irh_dB_d, irh_dB_m, irh_al_d, irh_al_v;

         trap_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         ir_dA_d    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)];
         ir_dA_m    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h3C)];
         ir_dB_d    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)];
         ir_dB_m    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)];
         ir_al_d    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)];
         ir_al_v    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h4C)];
         irh_dA_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];
         irh_dA_m   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)];
         irh_dB_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h58)];
         irh_dB_m   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h5C)];
         irh_al_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)];
         irh_al_v   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)];

         $display("illegal_trap_count (running, expect 8): %0d  %t ns", trap_count, $time);
         $display("instret  deny-A delta/mcause (1/2): %0d / 0x%h", ir_dA_d, ir_dA_m);
         $display("instret  deny-B delta/mcause (1/2): %0d / 0x%h", ir_dB_d, ir_dB_m);
         $display("instret  allow  delta/value  (0/>0): %0d / 0x%h", ir_al_d, ir_al_v);
         $display("instreth deny-A delta/mcause (1/2): %0d / 0x%h", irh_dA_d, irh_dA_m);
         $display("instreth deny-B delta/mcause (1/2): %0d / 0x%h", irh_dB_d, irh_dB_m);
         $display("instreth allow  delta/value  (0/* ): %0d / 0x%h", irh_al_d, irh_al_v);

         // ---- instret DENY-A ----
         if (ir_dA_d === 32'd1)
            $display("PASS:  instret  deny-A delta=1 (fresh trap)  %t ns", $time);
         else begin
            $display("ERROR: instret  deny-A delta=%0d, expected 1  %t ns", ir_dA_d, $time);
            error = error + 1;
         end
         if (ir_dA_m === 32'd2)
            $display("PASS:  instret  deny-A mcause=2  %t ns", $time);
         else begin
            $display("ERROR: instret  deny-A mcause=0x%h, expected 2  %t ns", ir_dA_m, $time);
            error = error + 1;
         end

         // ---- instret DENY-B  (CANARY) ----
         if (ir_dB_d === 32'd1)
            $display("PASS:  instret  deny-B delta=1 (fresh trap; CANARY for scounteren gate)  %t ns",
                     $time);
         else begin
            $display("ERROR: instret  deny-B delta=%0d, expected 1 — U-mode read wrongly ALLOWED (mcounteren-only RTL?)  %t ns",
                     ir_dB_d, $time);
            error = error + 1;
         end
         if (ir_dB_m === 32'd2)
            $display("PASS:  instret  deny-B mcause=2 (supplementary)  %t ns", $time);
         else begin
            $display("ERROR: instret  deny-B mcause=0x%h, expected 2  %t ns", ir_dB_m, $time);
            error = error + 1;
         end

         // ---- instret ALLOW ----
         if (ir_al_d === 32'd0)
            $display("PASS:  instret  allow delta=0 (no trap)  %t ns", $time);
         else begin
            $display("ERROR: instret  allow delta=%0d, expected 0  %t ns", ir_al_d, $time);
            error = error + 1;
         end
         if (ir_al_v !== 32'd0)
            $display("PASS:  instret  allow val=0x%h (nonzero, read succeeded)  %t ns", ir_al_v, $time);
         else begin
            $display("ERROR: instret  allow val=0 (expected nonzero)  %t ns", $time);
            error = error + 1;
         end

         // ---- instreth DENY-A ----
         if (irh_dA_d === 32'd1)
            $display("PASS:  instreth deny-A delta=1 (fresh trap)  %t ns", $time);
         else begin
            $display("ERROR: instreth deny-A delta=%0d, expected 1  %t ns", irh_dA_d, $time);
            error = error + 1;
         end
         if (irh_dA_m === 32'd2)
            $display("PASS:  instreth deny-A mcause=2  %t ns", $time);
         else begin
            $display("ERROR: instreth deny-A mcause=0x%h, expected 2  %t ns", irh_dA_m, $time);
            error = error + 1;
         end

         // ---- instreth DENY-B  (CANARY) ----
         if (irh_dB_d === 32'd1)
            $display("PASS:  instreth deny-B delta=1 (fresh trap; CANARY for scounteren gate)  %t ns",
                     $time);
         else begin
            $display("ERROR: instreth deny-B delta=%0d, expected 1 — U-mode read wrongly ALLOWED (mcounteren-only RTL?)  %t ns",
                     irh_dB_d, $time);
            error = error + 1;
         end
         if (irh_dB_m === 32'd2)
            $display("PASS:  instreth deny-B mcause=2 (supplementary)  %t ns", $time);
         else begin
            $display("ERROR: instreth deny-B mcause=0x%h, expected 2  %t ns", irh_dB_m, $time);
            error = error + 1;
         end

         // ---- instreth ALLOW ----
         if (irh_al_d === 32'd0)
            $display("PASS:  instreth allow delta=0 (no trap)  %t ns", $time);
         else begin
            $display("ERROR: instreth allow delta=%0d, expected 0  %t ns", irh_al_d, $time);
            error = error + 1;
         end
         $display("PASS:  instreth allow val=0x%h (mcen=1,scen=1 succeeded)  %t ns", irh_al_v, $time);

         if (trap_count === 32'd8)
            $display("PASS:  illegal_trap_count = 8 (running, cumulative)  %t ns", $time);
         else begin
            $display("ERROR: illegal_trap_count = %0d, expected 8 (running)  %t ns",
                     trap_count, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 3: TM bit (mcounteren[1] / scounteren[1]) — time & timeh
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 3: MCOUNTEREN+SCOUNTEREN TM BIT — time AND timeh           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      begin : check_phase3
         reg [31:0] trap_count;
         reg [31:0] tm_dA_d, tm_dA_m, tm_dB_d, tm_dB_m, tm_al_d, tm_al_v;
         reg [31:0] tmh_dA_d, tmh_dA_m, tmh_dB_d, tmh_dB_m, tmh_al_d, tmh_al_v;

         trap_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         tm_dA_d    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h68)];
         tm_dA_m    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h6C)];
         tm_dB_d    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h70)];
         tm_dB_m    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h74)];
         tm_al_d    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h78)];
         tm_al_v    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h7C)];
         tmh_dA_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h80)];
         tmh_dA_m   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h84)];
         tmh_dB_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h88)];
         tmh_dB_m   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h8C)];
         tmh_al_d   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h90)];
         tmh_al_v   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h94)];

         $display("illegal_trap_count (running, expect 12): %0d  %t ns", trap_count, $time);
         $display("time  deny-A delta/mcause (1/2): %0d / 0x%h", tm_dA_d, tm_dA_m);
         $display("time  deny-B delta/mcause (1/2): %0d / 0x%h", tm_dB_d, tm_dB_m);
         $display("time  allow  delta/value  (0/>0): %0d / 0x%h", tm_al_d, tm_al_v);
         $display("timeh deny-A delta/mcause (1/2): %0d / 0x%h", tmh_dA_d, tmh_dA_m);
         $display("timeh deny-B delta/mcause (1/2): %0d / 0x%h", tmh_dB_d, tmh_dB_m);
         $display("timeh allow  delta/value  (0/* ): %0d / 0x%h", tmh_al_d, tmh_al_v);

         // ---- time DENY-A ----
         if (tm_dA_d === 32'd1)
            $display("PASS:  time  deny-A delta=1 (fresh trap)  %t ns", $time);
         else begin
            $display("ERROR: time  deny-A delta=%0d, expected 1  %t ns", tm_dA_d, $time);
            error = error + 1;
         end
         if (tm_dA_m === 32'd2)
            $display("PASS:  time  deny-A mcause=2  %t ns", $time);
         else begin
            $display("ERROR: time  deny-A mcause=0x%h, expected 2  %t ns", tm_dA_m, $time);
            error = error + 1;
         end

         // ---- time DENY-B  (CANARY) ----
         if (tm_dB_d === 32'd1)
            $display("PASS:  time  deny-B delta=1 (fresh trap; CANARY for scounteren gate)  %t ns",
                     $time);
         else begin
            $display("ERROR: time  deny-B delta=%0d, expected 1 — U-mode read wrongly ALLOWED (mcounteren-only RTL?)  %t ns",
                     tm_dB_d, $time);
            error = error + 1;
         end
         if (tm_dB_m === 32'd2)
            $display("PASS:  time  deny-B mcause=2 (supplementary)  %t ns", $time);
         else begin
            $display("ERROR: time  deny-B mcause=0x%h, expected 2  %t ns", tm_dB_m, $time);
            error = error + 1;
         end

         // ---- time ALLOW ----
         if (tm_al_d === 32'd0)
            $display("PASS:  time  allow delta=0 (no trap)  %t ns", $time);
         else begin
            $display("ERROR: time  allow delta=%0d, expected 0  %t ns", tm_al_d, $time);
            error = error + 1;
         end
         if (tm_al_v !== 32'd0)
            $display("PASS:  time  allow val=0x%h (nonzero, read succeeded)  %t ns", tm_al_v, $time);
         else begin
            $display("ERROR: time  allow val=0 (expected nonzero)  %t ns", $time);
            error = error + 1;
         end

         // ---- timeh DENY-A ----
         if (tmh_dA_d === 32'd1)
            $display("PASS:  timeh deny-A delta=1 (fresh trap)  %t ns", $time);
         else begin
            $display("ERROR: timeh deny-A delta=%0d, expected 1  %t ns", tmh_dA_d, $time);
            error = error + 1;
         end
         if (tmh_dA_m === 32'd2)
            $display("PASS:  timeh deny-A mcause=2  %t ns", $time);
         else begin
            $display("ERROR: timeh deny-A mcause=0x%h, expected 2  %t ns", tmh_dA_m, $time);
            error = error + 1;
         end

         // ---- timeh DENY-B  (CANARY) ----
         if (tmh_dB_d === 32'd1)
            $display("PASS:  timeh deny-B delta=1 (fresh trap; CANARY for scounteren gate)  %t ns",
                     $time);
         else begin
            $display("ERROR: timeh deny-B delta=%0d, expected 1 — U-mode read wrongly ALLOWED (mcounteren-only RTL?)  %t ns",
                     tmh_dB_d, $time);
            error = error + 1;
         end
         if (tmh_dB_m === 32'd2)
            $display("PASS:  timeh deny-B mcause=2 (supplementary)  %t ns", $time);
         else begin
            $display("ERROR: timeh deny-B mcause=0x%h, expected 2  %t ns", tmh_dB_m, $time);
            error = error + 1;
         end

         // ---- timeh ALLOW ----
         if (tmh_al_d === 32'd0)
            $display("PASS:  timeh allow delta=0 (no trap)  %t ns", $time);
         else begin
            $display("ERROR: timeh allow delta=%0d, expected 0  %t ns", tmh_al_d, $time);
            error = error + 1;
         end
         $display("PASS:  timeh allow val=0x%h (mcen=1,scen=1 succeeded)  %t ns", tmh_al_v, $time);

         if (trap_count === 32'd12)
            $display("PASS:  illegal_trap_count = 12 (running, cumulative)  %t ns", $time);
         else begin
            $display("ERROR: illegal_trap_count = %0d, expected 12 (running)  %t ns",
                     trap_count, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE S: S-mode read with mcounteren[0]=1, scounteren[0]=0.
      // scounteren must NOT gate S-mode → both cycle and cycleh reads
      // succeed: pS_delta==0 (no new trap) and cycle value nonzero.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE S: S-MODE ALLOW (mcen=1,scen=0) — scounteren NOT S-gate    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      begin : check_phaseS
         reg [31:0] s_delta;
         reg [31:0] s_cyc;
         reg [31:0] s_cyh;

         s_delta = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h98)];
         s_cyc   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h9C)];
         s_cyh   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'hA0)];

         $display("S-mode delta (expect 0): %0d", s_delta);
         $display("S-mode cycle  value (expect >0): 0x%h", s_cyc);
         $display("S-mode cycleh value            : 0x%h", s_cyh);

         // Per-phase delta must be 0: S-mode read was allowed (scounteren=0
         // does NOT gate S-mode).
         if (s_delta === 32'd0)
            $display("PASS:  S-mode delta=0 (read NOT denied by scounteren=0)  %t ns", $time);
         else begin
            $display("ERROR: S-mode delta=%0d, expected 0 (S-mode wrongly denied?)  %t ns",
                     s_delta, $time);
            error = error + 1;
         end

         if (s_cyc !== 32'd0)
            $display("PASS:  S-mode cycle  = 0x%h (allowed: mcen=1, scen ignored for S)  %t ns",
                     s_cyc, $time);
         else begin
            $display("ERROR: S-mode cycle  = 0 (expected nonzero — S-mode read should succeed)  %t ns",
                     $time);
            error = error + 1;
         end

         $display("PASS:  S-mode cycleh = 0x%h (allowed: scounteren does NOT gate S-mode)  %t ns",
                  s_cyh, $time);
      end


      //=================================================================
      // PHASE 4: Write to shadow CSRs from M-mode → illegal instruction
      // Shadow CSRs (addr bits[11:10]=11) are read-only in all privilege
      // modes.  6 csrw attempts → p4_delta == 6, last_mcause == 2.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 4: SHADOW CSR WRITE FROM M-MODE → ILLEGAL INST        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      begin : check_phase4
         reg [31:0] p4_delta;
         reg [31:0] last_mcause;

         p4_delta    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'hA4)];
         last_mcause = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'hA8)];

         $display("phase 4 trap delta (expect 6): %0d", p4_delta);
         $display("last_mcause        (expect 2): 0x%h", last_mcause);

         if (p4_delta === 32'd6)
            $display("PASS:  phase4 delta = 6 (6 write-to-read-only traps)  %t ns", $time);
         else begin
            $display("ERROR: phase4 delta = %0d, expected 6  %t ns", p4_delta, $time);
            error = error + 1;
         end

         if (last_mcause === 32'd2)
            $display("PASS:  last_mcause = 2 (illegal instruction)  %t ns", $time);
         else begin
            $display("ERROR: last_mcause = 0x%h, expected 2  %t ns", last_mcause, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

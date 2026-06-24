//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_mcounteren
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM MCOUNTEREN GATING
//   mcounteren[10:3] WARL and HPM counter3 access gating via mcounteren[3]
//   and scounteren[3] (S-mode core):
//   U-mode read permitted iff mcounteren[3]=1 AND scounteren[3]=1.
//   S-mode read permitted iff mcounteren[3]=1 (scounteren ignored for S).
//   M-mode always permitted.
//
//   Each sub-phase is verified by its OWN trap-count DELTA (after-before),
//   never a global sticky mcause.  DENY: delta==1 (CANARY) & mcause==2
//   (supplementary).  ALLOW: delta==0 & U-mode value == M-mode value.
//   S-mode: delta==0 & hpmcounterh3==0xCAFEBABE.  The DENY-B (mcen=1,scen=0)
//   delta==1 check is the canary: it FAILS on a buggy mcounteren-only
//   implementation that wrongly allows the U-mode read (no trap → delta==0),
//   even though stale mcause still reads 2.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] mcounteren_rb;
reg [31:0] trap_count;
reg [31:0] hpm3_dA_d;
reg [31:0] hpm3_dA_m;
reg [31:0] hpm3_dB_d;
reg [31:0] hpm3_dB_m;
reg [31:0] hpm3_al_d;
reg [31:0] hpm3_al_u;
reg [31:0] hpm3_al_m;
reg [31:0] hpm3h_dA_d;
reg [31:0] hpm3h_dA_m;
reg [31:0] hpm3h_dB_d;
reg [31:0] hpm3h_dB_m;
reg [31:0] hpm3h_al_d;
reg [31:0] hpm3h_al_u;
reg [31:0] hpm3h_al_m;
reg [31:0] s_delta;
reg [31:0] s_hpm3;
reg [31:0] s_hpm3h;

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


      $display("");
      $display(" ====================================================================");
      $display("|     ZIHPM MCOUNTEREN+SCOUNTEREN: HPM COUNTER ACCESS GATING TEST    |");
      $display(" ====================================================================");
      $display("");


      //=================================================================
      // PHASE 0: mcounteren WARL — bits[31:11] must read as 0
      // (M-mode access, no gating involved.)
      //=================================================================
      $display("Waiting for Phase 0 sync (0x11111111)...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      mcounteren_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];

      $display("");
      $display(" ----------------------------------------------------");
      $display("  Phase 0: mcounteren WARL (write 0xFFFFFFFF)");
      $display(" ----------------------------------------------------");
      $display("  mcounteren readback: 0x%h  %t ns", mcounteren_rb, $time);

      // Check bits[31:11] = 0 (WARL upper bits always hardwired to 0)
      if (mcounteren_rb[31:11] === 21'h0)
         $display("  PASS  phase0: mcounteren WARL bits[31:11]=0 (readback=0x%h)  %t ns",
                  mcounteren_rb, $time);
      else begin
         $display("  ERROR phase0: mcounteren[31:11] should be 0, got 0x%h  %t ns",
                  mcounteren_rb[31:11], $time);
         error = error + 1;
      end

      // Check bits[10:3] = HPM_WARL_MASK: only bits for implemented counters
      // are writable; upper bits (beyond ZIHPM_NR) must read as 0.
      begin : warl_mask_check
         reg [7:0] hpm_warl_mask;
         hpm_warl_mask = (ZIHPM_NR == 0) ? 8'h00 :
                         (ZIHPM_NR == 1) ? 8'h01 :
                         (ZIHPM_NR == 2) ? 8'h03 :
                         (ZIHPM_NR == 3) ? 8'h07 :
                         (ZIHPM_NR == 4) ? 8'h0F :
                         (ZIHPM_NR == 5) ? 8'h1F :
                         (ZIHPM_NR == 6) ? 8'h3F :
                         (ZIHPM_NR == 7) ? 8'h7F : 8'hFF;
         if (mcounteren_rb[10:3] === hpm_warl_mask)
            $display("  PASS  phase0: mcounteren[10:3]=0x%h == HPM_WARL_MASK for ZIHPM_NR=%0d  %t ns",
                     hpm_warl_mask, ZIHPM_NR, $time);
         else begin
            $display("  ERROR phase0: mcounteren[10:3]=0x%h, expected HPM_WARL_MASK=0x%h for ZIHPM_NR=%0d  %t ns",
                     mcounteren_rb[10:3], hpm_warl_mask, ZIHPM_NR, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 1: hpmcounter3 — DENY-A / DENY-B / ALLOW from U-mode
      //   DENY-A : mcen=0, scen=1 → fresh trap (delta==1), mcause==2
      //   DENY-B : mcen=1, scen=0 → fresh trap (delta==1), mcause==2
      //            *** CANARY: delta==0 on buggy mcounteren-only RTL ***
      //   ALLOW  : mcen=1, scen=1 → no trap (delta==0), U==M frozen value
      //=================================================================
      $display("");
      $display("Waiting for Phase 1 sync (0x22222222)...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      trap_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      hpm3_dA_d  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];
      hpm3_dA_m  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
      hpm3_dB_d  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];
      hpm3_dB_m  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
      hpm3_al_d  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];
      hpm3_al_u  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];
      hpm3_al_m  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)];

      $display("");
      $display(" ----------------------------------------------------");
      $display("  Phase 1: hpmcounter3 gating");
      $display(" ----------------------------------------------------");
      $display("  trap_count (running, expect 2): %0d", trap_count);
      $display("  deny-A delta/mcause (1/2): %0d / 0x%h", hpm3_dA_d, hpm3_dA_m);
      $display("  deny-B delta/mcause (1/2): %0d / 0x%h", hpm3_dB_d, hpm3_dB_m);
      $display("  allow  delta/U/M (0/eq):  %0d / 0x%h / 0x%h", hpm3_al_d, hpm3_al_u, hpm3_al_m);

      // ---- hpmcounter3 DENY-A ----
      if (hpm3_dA_d === 32'd1)
         $display("  PASS  phase1a: hpmcounter3 deny-A delta=1 (fresh trap)  %t ns", $time);
      else begin
         $display("  ERROR phase1a: hpmcounter3 deny-A delta=%0d, expected 1  %t ns",
                  hpm3_dA_d, $time);
         error = error + 1;
      end
      if (hpm3_dA_m === 32'd2)
         $display("  PASS  phase1a: hpmcounter3 deny-A mcause=2  %t ns", $time);
      else begin
         $display("  ERROR phase1a: hpmcounter3 deny-A mcause=0x%h, expected 2  %t ns",
                  hpm3_dA_m, $time);
         error = error + 1;
      end

      // ---- hpmcounter3 DENY-B  (CANARY) ----
      if (hpm3_dB_d === 32'd1)
         $display("  PASS  phase1b: hpmcounter3 deny-B delta=1 (fresh trap; CANARY for scounteren gate)  %t ns",
                  $time);
      else begin
         $display("  ERROR phase1b: hpmcounter3 deny-B delta=%0d, expected 1 — U-mode read wrongly ALLOWED (mcounteren-only RTL?)  %t ns",
                  hpm3_dB_d, $time);
         error = error + 1;
      end
      if (hpm3_dB_m === 32'd2)
         $display("  PASS  phase1b: hpmcounter3 deny-B mcause=2 (supplementary)  %t ns", $time);
      else begin
         $display("  ERROR phase1b: hpmcounter3 deny-B mcause=0x%h, expected 2  %t ns",
                  hpm3_dB_m, $time);
         error = error + 1;
      end

      // ---- hpmcounter3 ALLOW ----
      if (hpm3_al_d === 32'd0)
         $display("  PASS  phase1c: hpmcounter3 allow delta=0 (no trap)  %t ns", $time);
      else begin
         $display("  ERROR phase1c: hpmcounter3 allow delta=%0d, expected 0 (read wrongly DENIED?)  %t ns",
                  hpm3_al_d, $time);
         error = error + 1;
      end
      if (hpm3_al_u === hpm3_al_m)
         $display("  PASS  phase1c: hpmcounter3 U-mode==M-mode (0x%h), mcen=1&scen=1 allowed  %t ns",
                  hpm3_al_u, $time);
      else begin
         $display("  ERROR phase1c: hpmcounter3 U-mode=0x%h != M-mode=0x%h (shadow mismatch)  %t ns",
                  hpm3_al_u, hpm3_al_m, $time);
         error = error + 1;
      end

      // Running trap_count sanity (secondary; per-phase deltas authoritative)
      if (trap_count === 32'd2)
         $display("  PASS  phase1: trap_count = 2 (running, hpmcounter3 deny-A + deny-B)  %t ns",
                  $time);
      else begin
         $display("  ERROR phase1: trap_count = %0d, expected 2 (running)  %t ns",
                  trap_count, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE 2: hpmcounterh3 — DENY-A / DENY-B / ALLOW from U-mode
      //=================================================================
      $display("");
      $display("Waiting for Phase 2 sync (0x33333333)...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      trap_count = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
      hpm3h_dA_d = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];
      hpm3h_dA_m = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)];
      hpm3h_dB_d = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)];
      hpm3h_dB_m = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h3C)];
      hpm3h_al_d = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)];
      hpm3h_al_u = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)];
      hpm3h_al_m = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)];

      $display("");
      $display(" ----------------------------------------------------");
      $display("  Phase 2: hpmcounterh3 gating");
      $display(" ----------------------------------------------------");
      $display("  trap_count (running, expect 4): %0d", trap_count);
      $display("  deny-A delta/mcause (1/2): %0d / 0x%h", hpm3h_dA_d, hpm3h_dA_m);
      $display("  deny-B delta/mcause (1/2): %0d / 0x%h", hpm3h_dB_d, hpm3h_dB_m);
      $display("  allow  delta/U/M (0/eq):  %0d / 0x%h / 0x%h", hpm3h_al_d, hpm3h_al_u, hpm3h_al_m);

      // ---- hpmcounterh3 DENY-A ----
      if (hpm3h_dA_d === 32'd1)
         $display("  PASS  phase2a: hpmcounterh3 deny-A delta=1 (fresh trap)  %t ns", $time);
      else begin
         $display("  ERROR phase2a: hpmcounterh3 deny-A delta=%0d, expected 1  %t ns",
                  hpm3h_dA_d, $time);
         error = error + 1;
      end
      if (hpm3h_dA_m === 32'd2)
         $display("  PASS  phase2a: hpmcounterh3 deny-A mcause=2  %t ns", $time);
      else begin
         $display("  ERROR phase2a: hpmcounterh3 deny-A mcause=0x%h, expected 2  %t ns",
                  hpm3h_dA_m, $time);
         error = error + 1;
      end

      // ---- hpmcounterh3 DENY-B  (CANARY) ----
      if (hpm3h_dB_d === 32'd1)
         $display("  PASS  phase2b: hpmcounterh3 deny-B delta=1 (fresh trap; CANARY for scounteren gate)  %t ns",
                  $time);
      else begin
         $display("  ERROR phase2b: hpmcounterh3 deny-B delta=%0d, expected 1 — U-mode read wrongly ALLOWED (mcounteren-only RTL?)  %t ns",
                  hpm3h_dB_d, $time);
         error = error + 1;
      end
      if (hpm3h_dB_m === 32'd2)
         $display("  PASS  phase2b: hpmcounterh3 deny-B mcause=2 (supplementary)  %t ns", $time);
      else begin
         $display("  ERROR phase2b: hpmcounterh3 deny-B mcause=0x%h, expected 2  %t ns",
                  hpm3h_dB_m, $time);
         error = error + 1;
      end

      // ---- hpmcounterh3 ALLOW ----
      if (hpm3h_al_d === 32'd0)
         $display("  PASS  phase2c: hpmcounterh3 allow delta=0 (no trap)  %t ns", $time);
      else begin
         $display("  ERROR phase2c: hpmcounterh3 allow delta=%0d, expected 0 (read wrongly DENIED?)  %t ns",
                  hpm3h_al_d, $time);
         error = error + 1;
      end
      if (hpm3h_al_u === hpm3h_al_m)
         $display("  PASS  phase2c: hpmcounterh3 U-mode==M-mode (0x%h), mcen=1&scen=1 allowed  %t ns",
                  hpm3h_al_u, $time);
      else begin
         $display("  ERROR phase2c: hpmcounterh3 U-mode=0x%h != M-mode=0x%h (hi shadow mismatch)  %t ns",
                  hpm3h_al_u, hpm3h_al_m, $time);
         error = error + 1;
      end
      // The frozen high word must be the 0xCAFEBABE preset visible from U-mode
      if (hpm3h_al_u === 32'hCAFEBABE)
         $display("  PASS  phase2c: hpmcounterh3 correct value 0xCAFEBABE visible from U-mode  %t ns",
                  $time);
      else begin
         $display("  ERROR phase2c: hpmcounterh3 U-mode=0x%h, expected 0xCAFEBABE  %t ns",
                  hpm3h_al_u, $time);
         error = error + 1;
      end

      if (trap_count === 32'd4)
         $display("  PASS  phase2: trap_count = 4 (running, cumulative)  %t ns", $time);
      else begin
         $display("  ERROR phase2: trap_count = %0d, expected 4 (running)  %t ns",
                  trap_count, $time);
         error = error + 1;
      end


      //=================================================================
      // PHASE S: S-mode read with mcounteren[3]=1, scounteren[3]=0.
      // scounteren must NOT gate S-mode → hpmcounter3 and hpmcounterh3
      // reads succeed: pS_delta==0 and hpmcounterh3==0xCAFEBABE.
      //=================================================================
      $display("");
      $display("Waiting for Phase S sync (0x44444444)...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      s_delta = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h4C)];
      s_hpm3  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];
      s_hpm3h = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)];

      $display("");
      $display(" ----------------------------------------------------");
      $display("  Phase S: S-mode ALLOW (mcen=1, scen=0)");
      $display(" ----------------------------------------------------");
      $display("  S-mode delta (expect 0): %0d", s_delta);
      $display("  S-mode hpmcounter3  value: 0x%h", s_hpm3);
      $display("  S-mode hpmcounterh3 value: 0x%h", s_hpm3h);

      // Per-phase delta must be 0: S-mode reads were allowed (scounteren=0
      // does NOT gate S-mode).
      if (s_delta === 32'd0)
         $display("  PASS  phaseS: S-mode delta=0 (NOT denied by scounteren=0)  %t ns", $time);
      else begin
         $display("  ERROR phaseS: S-mode delta=%0d, expected 0 (S-mode wrongly denied?)  %t ns",
                  s_delta, $time);
         error = error + 1;
      end

      // S-mode hpmcounterh3 must match the 0xCAFEBABE preset (counter frozen).
      if (s_hpm3h === 32'hCAFEBABE)
         $display("  PASS  phaseS: S-mode hpmcounterh3 = 0xCAFEBABE (allowed; scounteren ignored for S)  %t ns",
                  $time);
      else begin
         $display("  ERROR phaseS: S-mode hpmcounterh3 = 0x%h, expected 0xCAFEBABE  %t ns",
                  s_hpm3h, $time);
         error = error + 1;
      end

      $display("  PASS  phaseS: S-mode hpmcounter3 = 0x%h (allowed: mcen=1, scen ignored for S)  %t ns",
               s_hpm3, $time);


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

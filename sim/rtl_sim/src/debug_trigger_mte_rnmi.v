//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_mte_rnmi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdtrig tcontrol.MTE across an Smrnmi RNMI entry / MNRET
//   Companion testbench for debug_trigger_mte_rnmi.s. The firmware arms an
//   M-mode execute trigger (action=0, breakpoint) on an instruction INSIDE
//   its RNMI handler with tcontrol.MTE=1, then this testbench fires the NMI
//   (pin held until mnstatus.NMIE falls). Expected:
//     - tcontrol read inside the RNMI handler has MTE=0
//     - the armed marker executes: no breakpoint, no critical error
//     - lockup_o stays low throughout
//     - after MNRET tcontrol.MTE=1 again, MPTE unchanged
//     - the trigger re-pointed at a main marker fires (mcause=3)
//     - phase 4: with tcontrol = 0 a second NMI is fired; MTE reads 0 inside
//       the handler and still 0 after MNRET (MNRET restores the value saved
//       at that entry), MPTE stays 0, and an action=0 M trigger armed after
//       MNRET does not fire
//
//   Bug signatures: a breakpoint inside the RNMI handler is an UNEXPECTED
//   trap (NMIE=0) -> critical error, lockup_o high, no further progress;
//   or, if it were delivered to mtvec, slot 0x04 != 0. Every wait after the
//   NMI is bounded so a lockup produces ERROR lines instead of a hang.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

`define SPAD(byte_off)  ((byte_off)/4)

localparam integer WAIT_MAX = 20000;

reg [31:0] tc_pre, tc_post, tc_in, mval, addr;
reg [31:0] tc_pre2, tc_post2, tc_in1, tc_in2;

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

      // Breakpoints and the NMI entry look like traps to the monitor; the
      // firmware counters are the safety net. Deterministic NMI only.
      error_on_exception = 0;
      random_irq_enable  = 0;

      $display("");
      $display(" ====================================================================");
      $display("|  DEBUG TRIGGER MTE RNMI: tcontrol.MTE cleared on RNMI, restored    |");
      $display("|                          by MNRET (no breakpoint inside the RNMI)  |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 1: firmware armed the RNMI-marker trigger -> fire the NMI
      //=================================================================
      $display("Waiting for the firmware (armed sentinel)...");
      wait (probes_cpu.x31 == 32'h11111111);
      repeat(5) @(posedge free_clk);

      // Assert NMI and hold it until the core takes it (entry clears
      // mnstatus.NMIE), bounded so a dead core cannot hang the test.
      @(negedge free_clk);
      nmi = 1'b1;
      @(posedge free_clk);
      to = 0;
      while ((dut.arv_csr_top_inst.arv_csr_traps_inst.mnstatus_nmie_reg !== 1'b0) && (to < WAIT_MAX)) begin
         @(posedge free_clk);
         to = to + 1;
      end
      @(negedge free_clk);
      nmi = 1'b0;
      if (to >= WAIT_MAX) begin
         $display("ERROR: NMI not acknowledged (mnstatus.NMIE never fell) within %0d cycles %t ns", WAIT_MAX, $time);
         error = error + 1;
      end else begin
         $display("PASS:  NMI taken (mnstatus.NMIE fell after %0d cycles) %t ns", to, $time);
      end

      //=================================================================
      // PHASE 2: the RNMI handler must run through its marker and MNRET
      //=================================================================
      to = 0;
      while ((probes_cpu.x31 !== 32'h22222222) && (lockup !== 1'b1) && (to < WAIT_MAX)) begin
         @(posedge free_clk);
         to = to + 1;
      end
      if (lockup === 1'b1) begin
         $display("ERROR: lockup_o asserted -- breakpoint fired inside the RNMI handler with NMIE=0 (critical error) %t ns", $time);
         error = error + 1;
      end else if (to >= WAIT_MAX) begin
         $display("ERROR: no forward progress after the NMI (post-MNRET sentinel not seen in %0d cycles) %t ns", WAIT_MAX, $time);
         error = error + 1;
      end else begin
         $display("PASS:  firmware back from MNRET (%0d cycles) %t ns", to, $time);
      end

      //=================================================================
      // PHASE 4: MTE=0, second NMI
      //=================================================================
      to = 0;
      while ((probes_cpu.x31 !== 32'h33333333) && (lockup !== 1'b1) && (to < WAIT_MAX)) begin
         @(posedge free_clk);
         to = to + 1;
      end
      if (probes_cpu.x31 !== 32'h33333333) begin
         $display("ERROR: phase-4 sentinel not seen (x31=%h, lockup=%b) %t ns", probes_cpu.x31, lockup, $time);
         error = error + 1;
      end else begin
         repeat(5) @(posedge free_clk);
         @(negedge free_clk);
         nmi = 1'b1;
         @(posedge free_clk);
         to = 0;
         while ((dut.arv_csr_top_inst.arv_csr_traps_inst.mnstatus_nmie_reg !== 1'b0) && (to < WAIT_MAX)) begin
            @(posedge free_clk);
            to = to + 1;
         end
         @(negedge free_clk);
         nmi = 1'b0;
         if (to >= WAIT_MAX) begin
            $display("ERROR: second NMI not acknowledged (mnstatus.NMIE never fell) within %0d cycles %t ns", WAIT_MAX, $time);
            error = error + 1;
         end else begin
            $display("PASS:  second NMI taken (mnstatus.NMIE fell after %0d cycles) %t ns", to, $time);
         end
      end

      //=================================================================
      // PHASE 3/4: end sentinel
      //=================================================================
      to = 0;
      while ((probes_cpu.x31 !== 32'hdeadbeef) && (lockup !== 1'b1) && (to < WAIT_MAX)) begin
         @(posedge free_clk);
         to = to + 1;
      end
      if ((lockup !== 1'b1) && (to >= WAIT_MAX)) begin
         $display("ERROR: end sentinel not seen within %0d cycles %t ns", WAIT_MAX, $time);
         error = error + 1;
      end
      repeat(10) @(posedge free_clk);

      //=================================================================
      // CHECKS
      //=================================================================
      $display("");
      $display("--- lockup_o must be LOW ---");
      if (lockup !== 1'b0) begin
         $display("ERROR: lockup_o asserted (critical-error state) %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  lockup_o low %t ns", $time);
      end

      $display("");
      $display("--- Phase 0: trigger self-check in main (fires once) ---");
      check_mem_value(`SPAD(32'h2C), 32'h00000001);   // breakpoints at main_marker_0
      check_cpu_reg(25, 32'h00000011);                 // marker ran after disarm

      $display("");
      $display("--- Phase 1: tcontrol pre-NMI (MTE=1) ---");
      tc_pre = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];
      if (tc_pre[3] !== 1'b1) begin
         $display("ERROR: tcontrol pre-NMI MTE=0 (tcontrol=0x%h) %t ns", tc_pre, $time);
         error = error + 1;
      end else begin
         $display("PASS:  tcontrol pre-NMI MTE=1 (tcontrol=0x%h) %t ns", tc_pre, $time);
      end

      $display("");
      $display("--- Phase 1: RNMI entered exactly once ---");
      check_mem_value(`SPAD(32'h08), 32'h00000002);   // RNMI entries (phases 1 and 4)
      check_mem_value(`SPAD(32'h28), 32'h80000002);   // mncause = RNMI pin

      $display("");
      $display("--- Phase 1: tcontrol inside the RNMI handler (MTE=0) ---");
      tc_in = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
      if (tc_in[3] !== 1'b0) begin
         $display("ERROR: tcontrol.MTE=1 inside the RNMI handler (tcontrol=0x%h) -- MTE not cleared on RNMI entry %t ns", tc_in, $time);
         error = error + 1;
      end else begin
         $display("PASS:  tcontrol.MTE=0 inside the RNMI handler (tcontrol=0x%h) %t ns", tc_in, $time);
      end

      $display("");
      $display("--- Phase 1: no breakpoint inside the RNMI handler, marker executed ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // breakpoints at rnmi_marker
      check_cpu_reg(27, 32'h00000055);                 // rnmi_marker side effect taken

      $display("");
      $display("--- Phase 2: tcontrol after MNRET (MTE=1 restored, MPTE unchanged) ---");
      tc_post = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
      if (tc_post[3] !== 1'b1) begin
         $display("ERROR: tcontrol.MTE=0 after MNRET (tcontrol=0x%h) -- MTE not restored %t ns", tc_post, $time);
         error = error + 1;
      end else begin
         $display("PASS:  tcontrol.MTE=1 after MNRET (tcontrol=0x%h) %t ns", tc_post, $time);
      end
      if (tc_post[7] !== tc_pre[7]) begin
         $display("ERROR: tcontrol.MPTE changed across RNMI/MNRET (pre=0x%h post=0x%h) %t ns", tc_pre, tc_post, $time);
         error = error + 1;
      end else begin
         $display("PASS:  tcontrol.MPTE unchanged across RNMI/MNRET (pre=0x%h post=0x%h) %t ns", tc_pre, tc_post, $time);
      end

      $display("");
      $display("--- Phase 3: re-pointed trigger fires in main (MTE really armed) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000001);   // breakpoints at main_marker_3
      mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
      addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];
      if (mval !== addr) begin
         $display("ERROR: phase-3 mepc=0x%h != &main_marker_3=0x%h %t ns", mval, addr, $time);
         error = error + 1;
      end else begin
         $display("PASS:  phase-3 mepc=0x%h == &main_marker_3 %t ns", mval, $time);
      end
      check_cpu_reg(24, 32'h00000077);                 // marker ran after disarm

      $display("");
      $display("--- Phase 4: MTE=0 across the second RNMI / MNRET ---");
      tc_in1   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)];
      tc_pre2  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)];
      tc_in2   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)];
      tc_post2 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)];
      if (tc_in1 !== tc_in) begin
         $display("ERROR: per-entry tcontrol slot of the first RNMI 0x%h != 0x%h %t ns", tc_in1, tc_in, $time);
         error = error + 1;
      end
      if (tc_pre2[3] !== 1'b0 || tc_pre2[7] !== 1'b0) begin
         $display("ERROR: tcontrol before the second NMI = 0x%h (expected MTE=0, MPTE=0 after writing 0) %t ns", tc_pre2, $time);
         error = error + 1;
      end else begin
         $display("PASS:  tcontrol before the second NMI = 0x%h %t ns", tc_pre2, $time);
      end
      if (tc_in2[3] !== 1'b0) begin
         $display("ERROR: tcontrol.MTE=1 inside the second RNMI handler (tcontrol=0x%h) %t ns", tc_in2, $time);
         error = error + 1;
      end else begin
         $display("PASS:  tcontrol.MTE=0 inside the second RNMI handler (tcontrol=0x%h) %t ns", tc_in2, $time);
      end
      if (tc_post2[3] !== 1'b0) begin
         $display("ERROR: tcontrol.MTE=1 after the second MNRET (tcontrol=0x%h) -- MNRET must restore the saved 0 %t ns", tc_post2, $time);
         error = error + 1;
      end else begin
         $display("PASS:  tcontrol.MTE=0 after the second MNRET (tcontrol=0x%h) %t ns", tc_post2, $time);
      end
      if (tc_post2[7] !== tc_pre2[7]) begin
         $display("ERROR: tcontrol.MPTE changed across the second RNMI/MNRET (pre=0x%h post=0x%h) %t ns", tc_pre2, tc_post2, $time);
         error = error + 1;
      end
      check_cpu_reg(23, 32'h00000044);                 // main_marker_4 ran, no breakpoint

      $display("");
      $display("--- Totals ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // exactly two breakpoints (phase 0 + 3)
      check_mem_value(`SPAD(32'h0C), 32'h00000000);   // no unexpected trap

      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

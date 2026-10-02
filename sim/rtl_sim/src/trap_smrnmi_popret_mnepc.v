//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_smrnmi_popret_mnepc
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI ON CM.POPRET RETURN BRANCH -> STALE MNEPC REPRODUCER
//   The firmware calls a leaf function (cm.push ... cm.popret) 32 times,
//   writing a distinct sync value (0x51000000 + iter) to x31 right before
//   each call. This testbench pulses the NMI input at a DIFFERENT cycle
//   offset per iteration (offset = iteration index, 0..31 cycles after the
//   sync value is observed), sweeping the one-cycle-wide popret return
//   branch window across wait-state variants.
//
//   Fail signatures on buggy RTL (stale mnepc captured in the window):
//   - s11 (x27) == 0xDEADFA11: the poison sequence directly after the
//     cm.popret was executed after MNRET.
//   - An mnepc log entry equals the popret_poison address.
//   - Checksum (s4/x20) and/or iteration counter (s2/x18) corrupted.
//
//   Deterministic NMI injection only -- no random IRQs.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
`define SPAD(byte_off)  ((byte_off)/4)

reg [31:0] poison_addr;

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

      // NMI entries look like exceptions to the monitor
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init complete -> latch nmi_vector + poison-path address
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 1: INIT + CONFIGURE NMI VECTOR / READ POISON-PATH ADDR     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware (init sentinel)...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         poison_addr  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

         $display("NMI handler address    : 0x%h %t ns", handler_addr, $time);
         $display("Popret poison-path addr: 0x%h %t ns", poison_addr,  $time);

         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler addr in scratchpad is 0 %t ns", $time);
            error = error + 1;
         end
         if (poison_addr == 32'h0) begin
            $display("ERROR: popret_poison addr in scratchpad is 0 %t ns", $time);
            error = error + 1;
         end

      end


      //=================================================================
      // PHASE 2: SWEEP -- one NMI pulse per loop iteration, at a
      // different cycle offset (0..31) after each per-iteration sync
      // marker. The sync marker is written right before `jal func`, so
      // the swept offsets cover cm.push, the markers and the cm.popret
      // return branch cycle across wait-state variants.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: NMI OFFSET SWEEP OVER 32 CM.POPRET CALLS                |");
      $display(" ====================================================================");
      $display("");

      for (kk = 0; kk < 32; kk = kk + 1) begin
         // Wait for this iteration's distinct sync marker (level-
         // sensitive: the marker may already be there).
         wait (probes_cpu.x31 == (32'h51000000 + kk));

         // Swept offset: kk cycles after the sync marker
         repeat (kk) @(posedge free_clk);

         // Assert NMI and hold it until the core takes it (NMI entry clears
         // mnstatus.NMIE): a fixed short pulse can be swallowed if it lands in a
         // previous handler's NMIE=0 window or the post-MNRET suppression cycle.
         @(negedge free_clk);
         nmi = 1'b1;
         @(posedge free_clk);
         wait (dut.arv_csr_top_inst.arv_csr_traps_inst.mnstatus_nmie_reg === 1'b1);
         wait (dut.arv_csr_top_inst.arv_csr_traps_inst.mnstatus_nmie_reg === 1'b0);
         @(negedge free_clk);
         nmi = 1'b0;

         $display("Iteration %0d: NMI pulsed at offset %0d cycles %t ns", kk, kk, $time);
      end


      //=================================================================
      // PHASE 3: final checks
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 3: FINAL CHECKS (COUNTER / CHECKSUM / POISON / MNEPC LOG)  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware (end sentinel)...");

      wait (probes_cpu.x31 === 32'hdeadbeef);  // level-sensitive: sentinel may already be set when we get here
      random_irq_enable = 0;
      repeat(200) @(posedge free_clk);         // drain: the offset-31 NMI can land after the sentinel; let its handler retire before checking counts

      // --- Loop counter: all 32 iterations completed via correct path ---
      $display("");
      $display("--- Iteration counter s2/x18 (expect 32) ---");
      check_cpu_reg(18, 32'h00000020);

      // --- Checksum: updated only on the correct post-return path ---
      $display("");
      $display("--- Checksum s4/x20 (expect 0x00000A50) ---");
      check_cpu_reg(20, 32'h00000A50);

      // --- Poison register: the sequence after cm.popret never ran ---
      $display("");
      $display("--- Poison register s11/x27 (expect 0x00000000) ---");
      if (probes_cpu.x27 === 32'hDEADFA11) begin
         $display("ERROR: poison register s11 = 0xDEADFA11 -- STALE MNEPC: MNRET resumed at the sequential successor of cm.popret (return branch skipped after pops) %t ns", $time);
         error = error + 1;
      end else begin
         check_cpu_reg(27, 32'h00000000);
      end

      // --- NMI count: every injected pulse taken exactly once ---
      $display("");
      $display("--- NMI count t3/x28 (expect 32) ---");
      check_cpu_reg(28, 32'h00000020);

      // --- No unexpected synchronous exception ---
      $display("");
      $display("--- Exception count (expect 0) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      $display("");
      $display("--- Unexpected MCAUSE slot (expect 0) ---");
      check_mem_value(`SPAD(32'h14), 32'h00000000);

      // --- MNEPC log scan: no captured resume PC may equal the poison
      //     path (the direct bug signature, even if the poison sequence
      //     itself was preempted before executing) ---
      $display("");
      $display("--- MNEPC log scan (no entry may equal popret_poison 0x%h) ---", poison_addr);
      begin : scan_mnepc_log
         reg [31:0] log_entry;
         for (ii = 0; ii < 32; ii = ii + 1) begin
            log_entry = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100) + ii];
            if (log_entry === poison_addr) begin
               $display("ERROR: mnepc log[%0d] = 0x%h == popret_poison -- STALE resume PC captured on NMI entry %t ns",
                        ii, log_entry, $time);
               error = error + 1;
            end
         end
         $display("MNEPC log scan complete %t ns", $time);
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

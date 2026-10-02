//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_zcmt_jt_nmi_kill
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI DURING CM.JT JVT-LOAD PHASE -> ORPHAN DATA-PHASE /
//              PHANTOM FAULT / POST-MNRET RESTART CORRUPTION REPRODUCER
//   The firmware executes 32 iterations of cm.jt (through a 4-entry JVT),
//   writing a distinct sync value (0x52000000 + iter) to x31 right before
//   each cm.jt dispatch. This testbench pulses the NMI input at a DIFFERENT
//   cycle offset per iteration (offset = iteration index, 0..31 cycles
//   after the sync value is observed), sweeping the cm.jt JVT-load phase
//   across wait-state variants.
//
//   Fail signatures on buggy RTL:
//   - Phantom load-access-fault during NMI entry: exc_count > 0,
//     unexpected-mcause slot == 5, poison s11 (x27) == 0xDEADFA11.
//   - Corrupted post-mnret restart of the killed cm.jt: checksum (s4/x20)
//     != 0x50 and/or poison s11 == 0xDEADFA11 (cm.jt fall-through).
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
      // PHASE 1: init complete -> latch nmi_vector
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 1: INIT + CONFIGURE NMI VECTOR                             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware (init sentinel)...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];

         $display("NMI handler address : 0x%h %t ns", handler_addr, $time);

         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler addr in scratchpad is 0 %t ns", $time);
            error = error + 1;
         end

      end


      //=================================================================
      // PHASE 2: SWEEP -- one NMI pulse per loop iteration, at a
      // different cycle offset (0..31) after each per-iteration sync
      // marker. The sync marker is written right before the cm.jt
      // dispatch, so the swept offsets cover the JVT-load and branch
      // phases of the cm.jt across wait-state variants.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: NMI OFFSET SWEEP OVER 32 CM.JT EXECUTIONS               |");
      $display(" ====================================================================");
      $display("");

      for (kk = 0; kk < 32; kk = kk + 1) begin
         // Wait for this iteration's distinct sync marker (level-
         // sensitive: the marker may already be there).
         wait (probes_cpu.x31 == (32'h52000000 + kk));

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
      $display("|   PHASE 3: FINAL CHECKS (COUNTER / CHECKSUM / POISON / PHANTOM)    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware (end sentinel)...");

      wait (probes_cpu.x31 === 32'hdeadbeef);  // level-sensitive: sentinel may already be set when we get here
      random_irq_enable = 0;
      repeat(200) @(posedge free_clk);         // drain: the offset-31 NMI can land after the sentinel; let its handler retire before checking counts

      // --- Loop counter: all 32 iterations completed ---
      $display("");
      $display("--- Iteration counter s2/x18 (expect 32) ---");
      check_cpu_reg(18, 32'h00000020);

      // --- Checksum: every cm.jt landed on its correct pad exactly once ---
      $display("");
      $display("--- Checksum s4/x20 (expect 0x00000050) ---");
      check_cpu_reg(20, 32'h00000050);

      // --- Poison register: no unexpected sync trap, no cm.jt fall-through ---
      $display("");
      $display("--- Poison register s11/x27 (expect 0x00000000) ---");
      if (probes_cpu.x27 === 32'hDEADFA11) begin
         $display("ERROR: poison register s11 = 0xDEADFA11 -- unexpected synchronous trap or cm.jt fall-through (see mcause slot below) %t ns", $time);
         error = error + 1;
      end else begin
         check_cpu_reg(27, 32'h00000000);
      end

      // --- NMI count: every injected pulse taken exactly once ---
      $display("");
      $display("--- NMI count t3/x28 (expect 32) ---");
      check_cpu_reg(28, 32'h00000020);

      // --- No unexpected synchronous exception (phantom fault) ---
      $display("");
      $display("--- Exception count (expect 0: no phantom fault) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      $display("");
      $display("--- Unexpected MCAUSE slot (expect 0) ---");
      begin : check_phantom_mcause
         reg [31:0] mcause_val;
         reg [31:0] mepc_val;
         mcause_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];
         mepc_val   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         if (mcause_val === 32'h00000005) begin
            $display("ERROR: PHANTOM LOAD-ACCESS-FAULT (mcause=5) raised around NMI entry during cm.jt JVT-load -- mepc=0x%h %t ns",
                     mepc_val, $time);
            error = error + 1;
         end else if (mcause_val !== 32'h00000000) begin
            $display("ERROR: unexpected synchronous trap recorded -- mcause=0x%h, mepc=0x%h %t ns",
                     mcause_val, mepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  no unexpected synchronous trap recorded %t ns", $time);
         end
      end

      // --- MNCAUSE log scan (diagnostic): every taken NMI must have
      //     recorded an interrupt-flagged cause (bit 31 set). Zero
      //     entries are unwritten slots. ---
      $display("");
      $display("--- MNCAUSE log scan (nonzero entries must have bit31 set) ---");
      begin : scan_mncause_log
         reg [31:0] log_entry;
         for (ii = 0; ii < 32; ii = ii + 1) begin
            log_entry = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100) + ii];
            if (log_entry !== 32'h00000000 && log_entry[31] !== 1'b1) begin
               $display("ERROR: mncause log[%0d] = 0x%h -- interrupt bit (31) not set on NMI entry %t ns",
                        ii, log_entry, $time);
               error = error + 1;
            end
         end
         $display("MNCAUSE log scan complete %t ns", $time);
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

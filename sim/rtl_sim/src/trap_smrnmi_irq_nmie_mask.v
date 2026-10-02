//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_smrnmi_irq_nmie_mask
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SMRNMI x IRQ (NMIE=0 must mask ALL interrupts)
//   Ratified Smrnmi: "When NMIE=0, all interrupts are disabled." This bench
//   pulses NMI while the firmware runs a checksum loop, then -- on a sync
//   written FROM INSIDE the RNMI handler (NMIE=0) -- asserts irq_m_external
//   and HOLDS it. The IRQ must be taken only AFTER mnret restores NMIE=1.
//
//   Discriminators (per iteration, 2 iterations):
//   - s2-marker snapshot logged by the mtvec handler == 0 (spec) / == 1
//     means the machine external IRQ was taken inside the RNMI handler
//     with NMIE=0 (BUG REPRODUCED).
//   - checksum == 0x0000DCDC: mnret resumed at the exact interrupted PC.
//   - irq_count == 2, nmi_count == 2, mcause log == 0x8000000B,
//     mnstatus.NMIE == 0 and mncause[31] == 1 inside the RNMI handler.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

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

      // This test injects its own deterministic IRQs/NMIs.
      random_irq_enable  = 0;
      // NMI/IRQ entries look like traps to the exception monitor.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init complete -> latch nmi_vector from scratchpad
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 1: CONFIGURE NMI VECTOR                                     |");
      $display(" ====================================================================");
      $display("Waiting for the firmware (init sentinel)...");

      wait (probes_cpu.x31 == 32'h11111111);
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
      // PHASE 2: ITERATION 1
      //   ARM -> pulse NMI; in-RNMI sync -> assert + hold irq_m_external;
      //   DONE -> deassert.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: ITERATION 1 (NMI, then held IRQ during NMIE=0)           |");
      $display(" ====================================================================");
      $display("Waiting for the firmware (armed sentinel)...");

      wait (probes_cpu.x31 == 32'h21212121);
      repeat(5) @(posedge free_clk);
      @(negedge free_clk);
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI #1 pulsed (3 cycles) %t ns", $time);

      // Sync written from INSIDE the RNMI handler (NMIE=0 by construction)
      wait (probes_cpu.x31 == 32'hA0A00001);
      repeat(5) @(posedge free_clk);
      irq_m_external = 1'b1;      // held asserted through the NMIE=0 window
      $display("irq_m_external asserted inside RNMI handler #1 (held) %t ns", $time);

      wait (probes_cpu.x31 == 32'h22222222);
      repeat(3) @(posedge free_clk);
      irq_m_external = 1'b0;
      $display("irq_m_external deasserted after iteration 1 %t ns", $time);


      //=================================================================
      // PHASE 3: ITERATION 2 (identical choreography)
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: ITERATION 2 (NMI, then held IRQ during NMIE=0)           |");
      $display(" ====================================================================");
      $display("Waiting for the firmware (armed sentinel)...");

      wait (probes_cpu.x31 == 32'h31313131);
      repeat(5) @(posedge free_clk);
      @(negedge free_clk);
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI #2 pulsed (3 cycles) %t ns", $time);

      wait (probes_cpu.x31 == 32'hA0A00002);
      repeat(5) @(posedge free_clk);
      irq_m_external = 1'b1;
      $display("irq_m_external asserted inside RNMI handler #2 (held) %t ns", $time);

      wait (probes_cpu.x31 == 32'h33333333);
      repeat(3) @(posedge free_clk);
      irq_m_external = 1'b0;
      $display("irq_m_external deasserted after iteration 2 %t ns", $time);


      //=================================================================
      // PHASE 4: FINAL CHECKS
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: FINAL CHECKS                                             |");
      $display(" ====================================================================");
      $display("Waiting for the firmware (end sentinel)...");

      wait (probes_cpu.x31 == 32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      // --- Counts ---
      $display("");
      $display("--- irq_count (expect 2) / nmi_count (expect 2) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // irq_count
      check_mem_value(`SPAD(32'h28), 32'h00000002);   // nmi_count

      // --- mcause log: both IRQ traps must be machine external ---
      $display("");
      $display("--- mcause log (expect 0x8000000B for both IRQ traps) ---");
      check_mem_value(`SPAD(32'hA0), 32'h8000000B);
      check_mem_value(`SPAD(32'hA4), 32'h8000000B);

      // --- THE bug-sensitive check: marker snapshot per IRQ trap ---
      // s2 == 1 at IRQ-trap time means the standard machine IRQ was taken
      // INSIDE the RNMI handler while mnstatus.NMIE=0 -- Smrnmi mandates
      // "when NMIE=0, all interrupts are disabled".
      $display("");
      $display("--- NMIE=0 mask: s2-marker snapshot at each IRQ trap (expect 0) ---");
      begin : check_marker_snapshots
         reg [31:0] snap1, snap2;
         snap1 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'hC0)];
         snap2 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'hC4)];

         if (snap1 !== 32'h00000000) begin
            $display("ERROR: IRQ trap #1 taken INSIDE the RNMI handler (marker=0x%h, NMIE=0) -- Smrnmi 'NMIE=0 disables all interrupts' VIOLATED %t ns", snap1, $time);
            error = error + 1;
         end else begin
            $display("PASS:  IRQ trap #1 taken outside the RNMI handler (marker=0) %t ns", $time);
         end

         if (snap2 !== 32'h00000000) begin
            $display("ERROR: IRQ trap #2 taken INSIDE the RNMI handler (marker=0x%h, NMIE=0) -- Smrnmi 'NMIE=0 disables all interrupts' VIOLATED %t ns", snap2, $time);
            error = error + 1;
         end else begin
            $display("PASS:  IRQ trap #2 taken outside the RNMI handler (marker=0) %t ns", $time);
         end
      end

      // --- RNMI-handler diagnostics ---
      $display("");
      $display("--- In-RNMI-handler mnstatus.NMIE (bit 3) must be 0 ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)][3] !== 1'b0) begin
         $display("ERROR: mnstatus.NMIE=%b in RNMI handler (expected 0) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)][3], $time);
         error = error + 1;
      end else begin
         $display("PASS:  mnstatus.NMIE=0 in RNMI handler %t ns", $time);
      end

      $display("");
      $display("--- In-RNMI-handler mncause[31] must be 1 (interrupt) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)][31] !== 1'b1) begin
         $display("ERROR: mncause=0x%h in RNMI handler (bit31 expected 1) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  mncause[31]=1 in RNMI handler %t ns", $time);
      end

      // --- Resumability: checksums must match the golden value ---
      // Golden: s3=0; t0=1; repeat 200 { s3+=t0; s3^=(t0<<1); t0+=3; }
      //         => 0x0000DCDC. Any skipped/replayed instruction at the
      //         mnret (or IRQ mret) resume point diverges the result.
      $display("");
      $display("--- mnret resumability: checksums (expect 0x0000DCDC) ---");
      check_mem_value(`SPAD(32'h20), 32'h0000DCDC);   // iteration 1
      check_mem_value(`SPAD(32'h24), 32'h0000DCDC);   // iteration 2

      // s3 (x19) still holds the iteration-2 checksum
      check_cpu_reg(19, 32'h0000DCDC);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

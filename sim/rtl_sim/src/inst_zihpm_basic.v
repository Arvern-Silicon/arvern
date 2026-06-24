//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zihpm_basic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZIHPM BASIC
//   Zihpm HPM counter CSR verification across all ZIHPM_NR counters:
//   Phase 1 — mhpmeventN  write/read: selector 5 (branch-taken)
//   Phase 2 — mhpmcounterN increments on branch-taken events
//   Phase 3 — mcountinhibit bit[N] freezes mhpmcounterN
//   Phase 4 — hpmcounterN shadow == mhpmcounterN when inhibited
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;
integer zihpm_nr_found;

// Per-counter verification variables (declared at module level for for-loop use)
reg [31:0] ctr_event_rb;
reg [31:0] ctr_branch_count;
reg [31:0] ctr_rd1;
reg [31:0] ctr_rd2;
reg [31:0] ctr_machine_val;
reg [31:0] ctr_shadow_val;
integer    ctr_base_word;

// Scratchpad word address: mimpid at word 0, counter i data at words (1 + i*6)
`define SPAD(byte_off)      (byte_off/4)
`define CTR_SPAD_WORD(i)    (1 + (i)*6)

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


      //=================================================================
      // Wait for mimpid sync: firmware writes mimpid to scratchpad[0]
      // and signals with x31 = 0x11111111.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|                ZIHPM BASIC: HPM COUNTER TEST                       |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for mimpid sync (0x11111111)...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : read_mimpid
         reg [31:0] mimpid_rb;
         reg  [3:0] zihpm_nr;

         mimpid_rb    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         zihpm_nr     = mimpid_rb[23:20];
         zihpm_nr_found = zihpm_nr;

         $display("mimpid readback          : 0x%h  %t ns", mimpid_rb, $time);
         $display("ZIHPM_NR (mimpid[23:20]) : %0d   %t ns", zihpm_nr, $time);

         if (zihpm_nr == 0)
            $display("ZIHPM_NR=0: no HPM counters present, skipping counter tests");
         else
            $display("Testing %0d HPM counter(s): counter3..counter%0d", zihpm_nr, zihpm_nr+2);
      end


      if (zihpm_nr_found > 0) begin

         //=================================================================
         // Wait for all counter tests to complete.
         // Use wait() (level-sensitive) — firmware sets 0xAAAAAAAA then
         // 0xdeadbeef back-to-back, so the edge may already be past.
         //=================================================================
         $display("");
         $display("Waiting for all counter tests (0xAAAAAAAA)...");

         wait(probes_cpu.x31==32'hAAAAAAAA);
         random_irq_enable = 0;      // disable random IRQs before reading results
         repeat(3) @(posedge free_clk);


         //=================================================================
         // Verify results for each implemented counter
         //=================================================================
         for (ii = 0; ii < zihpm_nr_found; ii = ii + 1) begin

            ctr_base_word   = `CTR_SPAD_WORD(ii);
            ctr_event_rb    = ahb_bus_system_inst.sram_x_inst.mem[ctr_base_word + 0];
            ctr_branch_count= ahb_bus_system_inst.sram_x_inst.mem[ctr_base_word + 1];
            ctr_rd1         = ahb_bus_system_inst.sram_x_inst.mem[ctr_base_word + 2];
            ctr_rd2         = ahb_bus_system_inst.sram_x_inst.mem[ctr_base_word + 3];
            ctr_machine_val = ahb_bus_system_inst.sram_x_inst.mem[ctr_base_word + 4];
            ctr_shadow_val  = ahb_bus_system_inst.sram_x_inst.mem[ctr_base_word + 5];

            $display("");
            $display(" ----------------------------------------------------");
            $display("  Counter %0d  (mhpmcounter%0d / mhpmevent%0d / hpmcounter%0d)",
                     ii+3, ii+3, ii+3, ii+3);
            $display(" ----------------------------------------------------");

            // Phase 1: event selector readback
            if (ctr_event_rb[4:0] === 5'h05)
               $display("  PASS  phase1: mhpmevent%0d[4:0] = 0x05 (branch-taken)  %t ns",
                        ii+3, $time);
            else begin
               $display("  ERROR phase1: mhpmevent%0d[4:0] = 0x%h, expected 0x05  %t ns",
                        ii+3, ctr_event_rb[4:0], $time);
               error = error + 1;
            end

            // Phase 2: counter incremented
            if (ctr_branch_count > 32'd0)
               $display("  PASS  phase2: mhpmcounter%0d = %0d > 0 after branch loop  %t ns",
                        ii+3, ctr_branch_count, $time);
            else begin
               $display("  ERROR phase2: mhpmcounter%0d = 0 — counter did not increment  %t ns",
                        ii+3, $time);
               error = error + 1;
            end

            // Phase 3: inhibit froze counter (both reads must match)
            if (ctr_rd1 === ctr_rd2)
               $display("  PASS  phase3: mhpmcounter%0d frozen while inhibited (rd1==rd2==0x%h)  %t ns",
                        ii+3, ctr_rd1, $time);
            else begin
               $display("  ERROR phase3: mhpmcounter%0d changed while inhibited rd1=0x%h rd2=0x%h  %t ns",
                        ii+3, ctr_rd1, ctr_rd2, $time);
               error = error + 1;
            end

            // Phase 4: shadow register matches machine register
            if (ctr_machine_val === ctr_shadow_val)
               $display("  PASS  phase4: hpmcounter%0d shadow == mhpmcounter%0d (both 0x%h)  %t ns",
                        ii+3, ii+3, ctr_machine_val, $time);
            else begin
               $display("  ERROR phase4: hpmcounter%0d shadow mismatch machine=0x%h shadow=0x%h  %t ns",
                        ii+3, ctr_machine_val, ctr_shadow_val, $time);
               error = error + 1;
            end

         end // for each counter

      end // if zihpm_nr_found > 0


      //=================================================================
      // Wait for end of test
      // Use wait() — deadbeef follows 0xAAAAAAAA back-to-back in firmware.
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

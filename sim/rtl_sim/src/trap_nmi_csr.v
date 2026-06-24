//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_csr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI CSR
//   Smrnmi CSR read/write verification (no NMI triggered):
//   - mnscratch (0x740): full 32-bit R/W
//   - mnepc     (0x741): R/W, bit[0] hardwired 0
//   - mncause   (0x742): WARL, constant 0x80000000 (bit[31]=1, cause=0)
//   - mnstatus  (0x744): bit[3]=NMIE software-set-only (clear has no
//   effect), bits[12:11]=MNPP WARL R/W, rest=0
//   - nmi_vector(0xFFF): read-only, returns nmi_vector_i
//
//   Scratchpad layout (base 0x80000000):
//   0x000: mnscratch_rb
//   0x004: mnepc_rb
//   0x008: mncause_rb
//   0x00C: mnstatus_rb           (PHASE3 sub-1: NMIE write-0 @ NMIE=0)
//   0x010: nmi_handler_addr
//   0x014: nmi_vector_rb
//   0x018: mnstatus_nmie_set_rb  (PHASE3 sub-2: csrsi 8, expect NMIE=1)
//   0x01C: mnstatus_csrw0_rb     (PHASE3 sub-3: csrw 0 @ NMIE=1; NMIE=1)
//   0x020: mnstatus_csrrci_rb    (PHASE3 sub-4: csrrci 8 @ NMIE=1; NMIE=1)
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

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

      // No NMI is triggered in this test, but disable error-on-exception for safety
      error_on_exception = 0;

      // Pre-load nmi_vector with a known test value before firmware reads CSR 0xFFF in phase 4
      nmi_vector = 32'hDEAD1234;


      //=================================================================
      // PHASE 1: Initialization complete — verify scratchpad zeroed
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: INIT + MNSCRATCH R/W                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Verify scratchpad is zeroed before any writes
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // mnscratch_rb = 0
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // mnepc_rb = 0
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // mncause_rb = 0
      check_mem_value(`SPAD(32'h0C), 32'h00000000);   // mnstatus_rb = 0

      // Wait for phase 1 completion (mnscratch written and read back)
      @(probes_cpu.x31==32'h12121212);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MNSCRATCH readback (expect 0x5A5A5A5A) ---");
      check_mem_value(`SPAD(32'h00), 32'h5A5A5A5A);


      //=================================================================
      // PHASE 2: mnepc and mncause verification
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: MNEPC AND MNCAUSE R/W                     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MNEPC readback (expect 0x20000020, bit[0] hardwired 0) ---");
      check_mem_value(`SPAD(32'h04), 32'h20000020);

      $display("");
      $display("--- MNCAUSE readback (constant 0x80000000: bit[31]=1, cause=0) ---");
      check_mem_value(`SPAD(32'h08), 32'h80000000);


      //=================================================================
      // PHASE 3: mnstatus write/read verification
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: MNSTATUS R/W                              |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- MNSTATUS Smrnmi NMIE software-set-only verification ---");
      begin : check_mnstatus_rb
         reg [31:0] s1_val;   // sub-1: csrw 0 while NMIE=0 (reset state)
         reg [31:0] s2_val;   // sub-2: csrsi 8 (software SET of NMIE)
         reg [31:0] s3_val;   // sub-3: csrw 0 while NMIE=1 (FIX2 discriminator)
         reg [31:0] s4_val;   // sub-4: csrrci 8 while NMIE=1 (2nd discriminator)

         s1_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         s2_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         s3_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];
         s4_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];

         $display("MNSTATUS sub-1 (csrw 0 @ NMIE=0)  : 0x%h", s1_val);
         $display("MNSTATUS sub-2 (csrsi 8 -> set)   : 0x%h", s2_val);
         $display("MNSTATUS sub-3 (csrw 0 @ NMIE=1)  : 0x%h  <-- FIX2 discriminator", s3_val);
         $display("MNSTATUS sub-4 (csrrci 8 @ NMIE=1): 0x%h", s4_val);

         //----------------------------------------------------------------
         // Sub-step 1: write-0 while NMIE already 0 preserves NMIE=0,
         // and MNPP is normal WARL R/W so it reads back 00.
         // (This confirms write-0 does not spuriously SET NMIE, and the
         //  MNPP WARL path. It is NOT the set-only discriminator.)
         //----------------------------------------------------------------
         if (s1_val[3] !== 1'b0) begin
            $display("ERROR: MNSTATUS.NMIE should remain 0 after csrw 0 from reset state (write-0 must not spuriously set NMIE) -- 0x%h %t ns", s1_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  sub-1 NMIE=0 preserved after csrw 0 (reset state) %t ns", $time);
         end
         // MNPP after csrw 0: WARL accepts 0 under SU_MODE_EN=1; forced to 2'b11
         // under SU_MODE_EN=0 (U-mode absent → MPP hardwired to M).
         if (s1_val[12:11] !== (SU_MODE_EN ? 2'b00 : 2'b11)) begin
            $display("ERROR: MNSTATUS.MNPP should be %b after csrw 0 (WARL R/W under SU_MODE_EN=%0d) -- 0x%h %t ns",
                     (SU_MODE_EN ? 2'b00 : 2'b11), SU_MODE_EN, s1_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  sub-1 MNPP=%b (WARL R/W under SU_MODE_EN=%0d) %t ns",
                     s1_val[12:11], SU_MODE_EN, $time);
         end
         // The masked check at offset 0x1808 covers MNPP[12:11] + NMIE[3]; under
         // SU_MODE_EN=0 MNPP is 2'b11 so the masked region equals 0x00001800.
         if ((s1_val & 32'h00001808) !== (SU_MODE_EN ? 32'h00000000 : 32'h00001800)) begin
            $display("ERROR: sub-1 masked check failed -- expected 0x%h, got 0x%h %t ns",
                     (SU_MODE_EN ? 32'h00000000 : 32'h00001800), (s1_val & 32'h00001808), $time);
            error = error + 1;
         end else begin
            $display("PASS:  sub-1 masked (NMIE=0, MNPP=%b) = 0x%h %t ns",
                     s1_val[12:11], (s1_val & 32'h00001808), $time);
         end

         //----------------------------------------------------------------
         // Sub-step 2: software SET of NMIE via csrsi 8 must work.
         //----------------------------------------------------------------
         if (s2_val[3] !== 1'b1) begin
            $display("ERROR: MNSTATUS.NMIE must be 1 after csrsi 0x744,8 (Smrnmi: software CAN set NMIE) -- 0x%h %t ns", s2_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  sub-2 NMIE=1 after csrsi (software set works) %t ns", $time);
         end

         //----------------------------------------------------------------
         // Sub-step 3: clear-attempt via csrw 0 while NMIE=1.
         // *** FIX2 BUG DISCRIMINATOR ***
         // Spec-correct RTL: NMIE STAYS 1 (software-set-only).
         // Buggy RTL that honors bit[3]=0: NMIE becomes 0 -> this FAILS.
         // MNPP is cleared to 00 by this csrw 0 (normal WARL R/W) -- not a bug.
         //----------------------------------------------------------------
         if (s3_val[3] !== 1'b1) begin
            $display("ERROR: MNSTATUS.NMIE must remain 1 after csrw 0 (Smrnmi: NMIE is software-set-only, clear has no effect) -- 0x%h %t ns", s3_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  sub-3 NMIE remained 1 after csrw 0 (set-only honored) %t ns", $time);
         end
         // MNPP after sub-3 csrw 0: SU_MODE_EN=1 clears to 00 (WARL R/W);
         // SU_MODE_EN=0 stays at 2'b11 (hardwired to M).
         if (s3_val[12:11] !== (SU_MODE_EN ? 2'b00 : 2'b11)) begin
            $display("ERROR: sub-3 MNPP should be %b after csrw 0 (WARL under SU_MODE_EN=%0d) -- 0x%h %t ns",
                     (SU_MODE_EN ? 2'b00 : 2'b11), SU_MODE_EN, s3_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  sub-3 MNPP=%b (WARL under SU_MODE_EN=%0d) %t ns",
                     s3_val[12:11], SU_MODE_EN, $time);
         end

         //----------------------------------------------------------------
         // Sub-step 4: clear-attempt via csrrci 8 while NMIE=1.
         // Second independent discriminator (csrrci touches only bit[3]).
         //----------------------------------------------------------------
         if (s4_val[3] !== 1'b1) begin
            $display("ERROR: MNSTATUS.NMIE must remain 1 after csrrci 0x744,8 (Smrnmi: NMIE is software-set-only, clear has no effect) -- 0x%h %t ns", s4_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  sub-4 NMIE remained 1 after csrrci (set-only honored) %t ns", $time);
         end
      end

      // Verify earlier scratchpad values are still intact
      $display("");
      $display("--- Cross-check: earlier scratchpad values unchanged ---");
      check_mem_value(`SPAD(32'h00), 32'h5A5A5A5A);   // mnscratch_rb
      check_mem_value(`SPAD(32'h04), 32'h20000020);   // mnepc_rb
      check_mem_value(`SPAD(32'h08), 32'h80000000);   // mncause_rb


      //=================================================================
      // PHASE 4: nmi_vector read-only CSR at 0xFFF
      // Drive a known value on nmi_vector, then verify firmware read it back
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: NMI_VECTOR CSR 0xFFF READ                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- NMI_VECTOR readback via CSR 0xFFF (expect 0xDEAD1234) ---");
      check_mem_value(`SPAD(32'h14), 32'hDEAD1234);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

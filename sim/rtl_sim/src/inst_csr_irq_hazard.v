//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_irq_hazard
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CSR WRITE / IRQ DETECTION PIPELINE HAZARD
//   Tests that an IRQ cannot slip through on the same cycle that a CSR write
//   clears MIE (mstatus bit 3).
//
//   The hazard: irq_detect is combinational using the OLD (registered) value
//   of mstatus_mie, while CSRRCI writes the NEW value on the same clock edge.
//   If irq_detect is not suppressed during the CSR write, a spurious IRQ is
//   taken after MIE has been cleared.
//
//   Strategy:
//   1. Firmware sets up trap handler, enables MTIE + MIE
//   2. Testbench holds irq_m_timer=1 continuously
//   3. After initial IRQ is serviced (handler clears MTIE), firmware
//   executes: csrs mie, 0x80 (re-enable MTIE)
//   csrc mstatus, 0x8 (disable MIE)
//   Back-to-back: 1-cycle window where MTIE=1 and old MIE=1
//   4. With bug: spurious IRQ → trap count increments
//   Without bug: no IRQ → trap count unchanged
//
//   SRAM layout (firmware writes):
//   SRAM[0] = 0xDEAD0001  sync word
//   SRAM[1] = IRQ count before hazard test
//   SRAM[2] = IRQ count after 1st hazard (csrs mie + csrc mstatus)
//   SRAM[3] = IRQ count after 2nd hazard (csrs mie + csrc mstatus)
//   SRAM[4] = IRQ count after 3rd hazard (csrs mie + csrci mstatus)
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Disable error-on-exception (interrupts trigger exception monitors)
      error_on_exception = 0;

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|          CSR WRITE / IRQ DETECTION PIPELINE HAZARD TEST            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for firmware sync...");

      //=================================================================
      // Wait for firmware to initialize trap handler and signal ready
      //=================================================================
      @(probes_sram.sram_0 == 32'hDEAD0001);
      $display("Firmware sync received — asserting irq_m_timer");

      // Assert irq_m_timer and hold it high for the rest of the test
      irq_m_timer = 1'b1;

      // Wait for firmware to complete all hazard tests
      // Firmware ends with: csrc mstatus, 0x8 / end_of_test: nop / j end_of_test
      // Detect completion by waiting for SRAM[4] to be written (last store)
      @(probes_sram.sram_4 !== 32'h00000000);
      repeat(10) @(posedge free_clk);

      // Deassert irq_m_timer
      irq_m_timer = 1'b0;

      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                     CHECK HAZARD TEST RESULTS                      |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // Check IRQ count before hazard tests
      //=================================================================
      $display("--- IRQ count before hazard test ---");
      check_mem_value(1, 32'h00000001);

      //=================================================================
      // Check 1st hazard test: csrs mie, 0x80 + csrc mstatus, 0x8
      //=================================================================
      $display("");
      $display("--- 1st hazard test (csrs mie + csrc mstatus) ---");
      begin : check_hazard_1
         reg [31:0] count_before, count_after;
         count_before = ahb_bus_system_inst.sram_x_inst.mem[1];
         count_after  = ahb_bus_system_inst.sram_x_inst.mem[2];

         if (count_after !== count_before) begin
            $display("ERROR: Spurious IRQ detected — count before: %0d / after: %0d %t ns",
                     count_before, count_after, $time);
            error = error + 1;
         end else begin
            $display("PASS:  No spurious IRQ — count unchanged: %0d %t ns",
                     count_after, $time);
         end
      end

      //=================================================================
      // Check 2nd hazard test: csrs mie, 0x80 + csrc mstatus, 0x8
      //=================================================================
      $display("");
      $display("--- 2nd hazard test (csrs mie + csrc mstatus) ---");
      begin : check_hazard_2
         reg [31:0] count_before, count_after;
         count_before = ahb_bus_system_inst.sram_x_inst.mem[2];
         count_after  = ahb_bus_system_inst.sram_x_inst.mem[3];

         if (count_after !== count_before) begin
            $display("ERROR: Spurious IRQ detected — count before: %0d / after: %0d %t ns",
                     count_before, count_after, $time);
            error = error + 1;
         end else begin
            $display("PASS:  No spurious IRQ — count unchanged: %0d %t ns",
                     count_after, $time);
         end
      end

      //=================================================================
      // Check 3rd hazard test: csrs mie, 0x80 + csrci mstatus, 0x8
      //=================================================================
      $display("");
      $display("--- 3rd hazard test (csrs mie + csrci mstatus) ---");
      begin : check_hazard_3
         reg [31:0] count_before, count_after;
         count_before = ahb_bus_system_inst.sram_x_inst.mem[3];
         count_after  = ahb_bus_system_inst.sram_x_inst.mem[4];

         if (count_after !== count_before) begin
            $display("ERROR: Spurious IRQ detected — count before: %0d / after: %0d %t ns",
                     count_before, count_after, $time);
            error = error + 1;
         end else begin
            $display("PASS:  No spurious IRQ — count unchanged: %0d %t ns",
                     count_after, $time);
         end
      end

      //=================================================================
      // Summary
      //=================================================================
      $display("");
      $display("--- Summary ---");
      begin : summary
         reg [31:0] total_irqs;
         total_irqs = ahb_bus_system_inst.sram_x_inst.mem[4];
         $display("Total IRQ count at end of test: %0d (expected: 1)", total_irqs);
         if (total_irqs !== 32'h00000001) begin
            $display("ERROR: Expected exactly 1 IRQ (initial), got %0d — pipeline hazard bug! %t ns",
                     total_irqs, $time);
            error = error + 1;
         end else begin
            $display("PASS:  Exactly 1 IRQ — no spurious interrupts from CSR hazard %t ns", $time);
         end
      end

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

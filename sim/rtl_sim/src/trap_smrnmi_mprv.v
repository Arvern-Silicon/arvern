//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_smrnmi_mprv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SMRNMI × MPRV (NMIE=0 ⇒ MPRV clear)
//   Bug-sensitive reproducer for a missing mnstatus.NMIE gate on the MPRV
//   term at arv_csr_traps.v:2120. PROBE A (store inside the RNMI handler,
//   NMIE=0, MPRV=1/MPP=U) MUST be tagged M-mode on AHB per RISC-V Privileged
//   spec §8.3. RTL lacking the NMIE gate tags it U-mode ⇒ this test FAILS
//   without the gate and PASSES with it. PROBE B (post-mnret, NMIE=1)
//   confirms MPRV resumes normally (U-mode).
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

//=========================================================================
// AHB HPROT/HSMODE capture: data-bus store address phase to the two probes.
//=========================================================================
reg captured_hprot_a, captured_hsmode_a, captured_valid_a;
reg captured_hprot_b, captured_hsmode_b, captured_valid_b;

initial begin
   captured_valid_a = 0;
   captured_valid_b = 0;
end

always @(posedge free_clk) begin
   if (data_htrans == 2'b10 && data_hwrite == 1'b1) begin
      case (data_haddr)
         32'h80000100: begin captured_hprot_a <= data_hprot[1]; captured_hsmode_a <= data_hsmode; captured_valid_a <= 1; end
         32'h80000104: begin captured_hprot_b <= data_hprot[1]; captured_hsmode_b <= data_hsmode; captured_valid_b <= 1; end
      endcase
   end
end

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

      // NMI entry looks like a trap to the monitor — do not flag it.
      error_on_exception = 0;

      //=================================================================
      // PHASE 1: arm (MPRV=1, MPP=U, NMIE=1), then assert NMI
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 1: ARM (MPRV=1/MPP=U/NMIE=1) → ASSERT NMI                  |");
      $display(" ====================================================================");
      $display("Waiting for the firmware (armed sentinel)...");

      wait (probes_cpu.x31 == 32'h11111111);

      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         $display("NMI handler address : 0x%h %t ns", handler_addr, $time);
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler addr in scratchpad is 0 %t ns", $time);
            error = error + 1;
         end
         nmi_vector = handler_addr;
      end

      repeat(5) @(posedge free_clk);
      @(negedge free_clk);
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI asserted (3 cycles) and deasserted %t ns", $time);

      //=================================================================
      // PHASE 2: wait for completion, verify
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: VERIFY RNMI-HANDLER STORE IS M-TAGGED (§8.3)            |");
      $display(" ====================================================================");
      $display("Waiting for the firmware (end sentinel)...");

      wait ((probes_cpu.x31 == 32'hdeadbeef) || (probes_cpu.x31 == 32'h0badbadb));
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      if (probes_cpu.x31 == 32'h0badbadb) begin
         $display("ERROR: firmware hit the mtvec trap handler (unexpected trap) %t ns", $time);
         error = error + 1;
      end

      // --- NMI fired exactly once ---
      $display("");
      $display("--- NMI count (expect 1) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // --- Preconditions captured in the handler ---
      $display("");
      $display("--- In-handler mnstatus.NMIE (bit 3) must be 0 ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)][3] !== 1'b0) begin
         $display("ERROR: NMIE=%b in handler (expected 0) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)][3], $time);
         error = error + 1;
      end else begin
         $display("PASS:  NMIE=0 in RNMI handler %t ns", $time);
      end

      $display("");
      $display("--- In-handler mstatus: MPRV(17)=1, MPP(12:11)=00 ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)][17] !== 1'b1 ||
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)][12:11] !== 2'b00) begin
         $display("ERROR: MPRV=%b MPP=%b in handler (expected 1 / 00) %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)][17],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)][12:11], $time);
         error = error + 1;
      end else begin
         $display("PASS:  MPRV=1, MPP=00 in RNMI handler %t ns", $time);
      end

      // --- PROBE A: THE bug-sensitive check ---
      // §8.3: NMIE=0 ⇒ behave as MPRV clear ⇒ M-mode AHB (priv=1, hsmode=0).
      // Unfixed RTL emits U (priv=0) — this is what fails without the fix.
      $display("");
      $display("--- PROBE A: RNMI-handler store MUST be M-mode (expect HPROT[1]=1, HSMODE=0) ---");
      if (!captured_valid_a) begin
         $display("ERROR: no AHB capture for PROBE A (0x80000100) %t ns", $time);
         error = error + 1;
      end else if (captured_hprot_a !== 1'b1 || captured_hsmode_a !== 1'b0) begin
         $display("ERROR: PROBE A HPROT[1]=%b (exp 1) HSMODE=%b (exp 0) -- RNMI handler store signalled UNDER-privileged; RISC-V Priv spec section 8.3 violated (NMIE gate on MPRV term missing) %t ns",
                  captured_hprot_a, captured_hsmode_a, $time);
         error = error + 1;
      end else begin
         $display("PASS:  PROBE A HPROT[1]=1, HSMODE=0 -- RNMI handler store M-tagged (§8.3 honored) %t ns", $time);
      end

      // --- PROBE B: MPRV resumes normally after mnret (NMIE=1) ---
      $display("");
      $display("--- PROBE B: post-mnret store, MPRV honored (expect HPROT[1]=0, HSMODE=0) ---");
      if (!captured_valid_b) begin
         $display("ERROR: no AHB capture for PROBE B (0x80000104) %t ns", $time);
         error = error + 1;
      end else if (captured_hprot_b !== 1'b0 || captured_hsmode_b !== 1'b0) begin
         $display("ERROR: PROBE B HPROT[1]=%b (exp 0) HSMODE=%b (exp 0) -- MPRV did not resume post-mnret %t ns",
                  captured_hprot_b, captured_hsmode_b, $time);
         error = error + 1;
      end else begin
         $display("PASS:  PROBE B HPROT[1]=0, HSMODE=0 -- MPRV resumed (U-mode) after mnret %t ns", $time);
      end

      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_priority
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI PRIORITY
//   NMI priority verification (3 phases):
//   Phase 1: NMI fires when MSTATUS.MIE=0 (NMI is not gated by MIE)
//   Phase 2: NMI wins over simultaneous timer IRQ (NMI has higher priority)
//   Phase 3: NMI fires during countdown loop, before illegal instruction
//   exception (NMI taken, then exception fires after mnret)
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

      // Disable error-on-exception (NMI and trap entries look like exceptions)
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Init complete — configure nmi_vector, then assert NMI
      //          with MSTATUS.MIE=0 to verify NMI is not gated by MIE
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: NMI FIRES WHEN MSTATUS.MIE=0                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Read nmi_handler address from scratchpad[0x14] and drive nmi_vector
      begin : setup_nmi_vector_p1
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];
         $display("NMI handler address from scratchpad: 0x%h %t ns", handler_addr, $time);

         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler_addr in scratchpad is 0 -- firmware did not store it %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_handler_addr stored by firmware: 0x%h %t ns", handler_addr, $time);
         end

         nmi_vector = handler_addr;
      end

      // Verify scratchpad counters are zeroed before NMI fires
      $display("");
      $display("--- Initial counter values (all should be 0) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // nmi_count = 0
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // irq_count = 0
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // exc_count = 0

      // Assert NMI for 3 cycles while MIE=0; NMI must not be blocked
      repeat(3) @(posedge free_clk);
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI asserted (3 cycles) with MIE=0 %t ns", $time);

      // Wait for firmware to observe nmi_count >= 1 and reach phase 1 done sync
      @(probes_cpu.x31==32'h12121212);
      repeat(3) @(posedge free_clk);

      // Verify: nmi_count=1, irq_count=0 (MIE was 0, no IRQs could fire)
      $display("");
      $display("--- Phase 1 results ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // nmi_count = 1
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // irq_count = 0 (MIE was 0)

      // Check last_mnepc is in ROM range
      $display("");
      $display("--- MNEPC range check (phase 1) ---");
      begin : check_mnepc_p1
         reg [31:0] mnepc_val;
         mnepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

         if (mnepc_val[31:28] !== 4'h2) begin
            $display("ERROR: MNEPC should be in ROM range (0x2xxxxxxx) -- MNEPC: 0x%h %t ns", mnepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC in ROM range -- value: 0x%h %t ns", mnepc_val, $time);
         end

         if (mnepc_val[0] !== 1'b0) begin
            $display("ERROR: MNEPC bit[0] should be 0 (at least 2-byte aligned) -- MNEPC: 0x%h %t ns", mnepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC bit[0] = 0 %t ns", $time);
         end
      end


      //=================================================================
      // PHASE 2: NMI wins over simultaneous timer IRQ
      // Firmware enables MTIE + MIE then signals. Testbench asserts
      // both nmi and irq_m_timer at the same time. NMI must be taken
      // first (nmi_count => 2). After mnret, timer IRQ fires
      // (irq_count => 1).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 2: NMI WINS OVER SIMULTANEOUS TIMER IRQ          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Assert NMI and timer IRQ simultaneously
      nmi       = 1'b1;
      irq_m_timer = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI + irq_m_timer asserted simultaneously %t ns", $time);

      // Wait for firmware to observe both handlers ran and reach phase 2 done sync
      @(probes_cpu.x31==32'h23232323);
      irq_m_timer = 1'b0;
      repeat(3) @(posedge free_clk);

      // Verify: nmi_count=2, irq_count=1
      $display("");
      $display("--- Phase 2 results ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // nmi_count = 2
      check_mem_value(`SPAD(32'h04), 32'h00000001);   // irq_count = 1

      // last_mcause should be the timer IRQ (most recently completed trap)
      $display("");
      $display("--- MCAUSE check (timer IRQ = 0x80000007) ---");
      check_mem_value(`SPAD(32'h10), 32'h80000007);

      // Check last_mnepc is in ROM range
      $display("");
      $display("--- MNEPC range check (phase 2) ---");
      begin : check_mnepc_p2
         reg [31:0] mnepc_val;
         mnepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

         if (mnepc_val[31:28] !== 4'h2) begin
            $display("ERROR: MNEPC should be in ROM range (0x2xxxxxxx) -- MNEPC: 0x%h %t ns", mnepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC in ROM range -- value: 0x%h %t ns", mnepc_val, $time);
         end
      end


      //=================================================================
      // PHASE 3: NMI priority over exception
      // Testbench asserts NMI immediately after Phase 2 checks — the
      // firmware is already in its Phase 3 countdown loop (started
      // right after the Phase 2 done sync). NMI fires somewhere in
      // the loop (nmi_count => 3). After mnret the loop exits and
      // firmware executes an illegal instruction (.word 0xFFFFFFFF),
      // which the trap handler advances past (exc_count => 1,
      // last_mcause = 2). last_mnepc must point before the exception
      // instruction address stored in scratchpad[0x18].
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 3: NMI PRIORITY OVER EXCEPTION                   |");
      $display(" ====================================================================");
      $display("");

      // Assert NMI — firmware is already in Phase 3 countdown loop
      repeat(5) @(posedge free_clk);
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI asserted (3 cycles) in Phase 3 countdown loop %t ns", $time);

      // Wait for firmware to confirm NMI was taken (intermediate sync)
      @(probes_cpu.x31==32'h34343434);
      repeat(3) @(posedge free_clk);
      $display("NMI taken, about to execute exception instruction %t ns", $time);

      // Wait for final sync (exception instruction executed and handled)
      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      // Verify: nmi_count=3, exc_count=1
      $display("");
      $display("--- Phase 3 results ---");
      check_mem_value(`SPAD(32'h00), 32'h00000003);   // nmi_count = 3
      check_mem_value(`SPAD(32'h08), 32'h00000001);   // exc_count = 1

      // last_mcause should be illegal instruction (cause = 2)
      $display("");
      $display("--- MCAUSE check (illegal instruction = 0x00000002) ---");
      check_mem_value(`SPAD(32'h10), 32'h00000002);

      // Check last_mnepc: must be in ROM range AND before the exception instruction
      $display("");
      $display("--- MNEPC range and ordering check (phase 3) ---");
      begin : check_mnepc_p3
         reg [31:0] mnepc_val;
         reg [31:0] exc_addr;
         mnepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         exc_addr  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];

         $display("MNEPC (last NMI interrupted PC): 0x%h %t ns", mnepc_val, $time);
         $display("Exception instruction address:   0x%h %t ns", exc_addr,  $time);

         if (mnepc_val[31:28] !== 4'h2) begin
            $display("ERROR: MNEPC should be in ROM range (0x2xxxxxxx) -- MNEPC: 0x%h %t ns", mnepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC in ROM range: 0x%h %t ns", mnepc_val, $time);
         end

         if (mnepc_val >= exc_addr) begin
            $display("ERROR: MNEPC should be before exception instruction (0x%h >= 0x%h) %t ns",
                     mnepc_val, exc_addr, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC (0x%h) is before exception instruction (0x%h) %t ns",
                     mnepc_val, exc_addr, $time);
         end
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

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_basic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IRQ
//   Comprehensive asynchronous interrupt verification:
//   - Timer interrupt (MCAUSE = 0x80000007)
//   - Software interrupt (MCAUSE = 0x80000003)
//   - External interrupt (MCAUSE = 0x8000000B)
//   - Interrupt priority (simultaneous timer + external)
//   - MSTATUS.MIE=0 blocks all interrupts
//   - MSTATUS save/restore across interrupt entry/exit
//   - Register preservation across multiple interrupts
//
//   IRQ signals are driven directly by this testbench stimulus.
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

      // Disable error-on-exception (interrupts trigger exception monitors)
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Verify scratchpad is zeroed (trap_count should be 0)
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      // Check MTVEC readback
      $display("");
      $display("--- MTVEC readback ---");
      begin : check_mtvec
         reg [31:0] mtvec_val;
         mtvec_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];

         if (mtvec_val[1:0] !== 2'b00) begin
            $display("ERROR: MTVEC mode should be 00 (direct) -- MTVEC: 0x%h %t ns", mtvec_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MTVEC mode = 00 (direct) %t ns", $time);
         end

         if (mtvec_val[31:2] == 30'h0) begin
            $display("ERROR: MTVEC base should be non-zero -- MTVEC: 0x%h %t ns", mtvec_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MTVEC base = 0x%h %t ns", {mtvec_val[31:2], 2'b00}, $time);
         end
      end

      // Check callee-saved registers
      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: Timer interrupt
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: TIMER INTERRUPT                           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      repeat(5) @(posedge free_clk);

      // Assert timer interrupt
      irq_m_timer = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Deassert timer interrupt
      irq_m_timer = 1'b0;

      // Check trap_count = 1
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // Check MCAUSE = 0x80000007 (Machine Timer Interrupt)
      $display("");
      $display("--- MCAUSE verification (timer) ---");
      check_mem_value(`SPAD(32'h20), 32'h80000007);

      // Check MSTATUS inside trap handler
      $display("");
      $display("--- MSTATUS on trap entry ---");
      begin : check_mstatus_timer
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];

         // MIE = 0 (disabled on trap entry)
         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 in trap handler %t ns", $time);
         end

         // MPIE = 1 (saved from MIE which was 1)
         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 in trap handler %t ns", $time);
         end

         // MPP = 11 (trapped from M-mode)
         if (mstatus_val[12:11] !== 2'b11) begin
            $display("ERROR: MSTATUS.MPP should be 11 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = 11 in trap handler %t ns", $time);
         end
      end

      // Check MSTATUS after MRET
      $display("");
      $display("--- MSTATUS after MRET ---");
      begin : check_mstatus_mret_timer
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)];

         // MIE = 1 (restored from MPIE)
         if (mstatus_val[3] !== 1'b1) begin
            $display("ERROR: MSTATUS.MIE should be 1 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 1 after MRET %t ns", $time);
         end

         // MPIE = 1 (set to 1 by MRET)
         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 after MRET -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 after MRET %t ns", $time);
         end

         // MPP after MRET: 2'b00 (U-mode) under SU_MODE_EN=1 — the spec-recommended
         // "lowest implemented privilege" reset value. Under SU_MODE_EN=0 (M-only),
         // MPP is hardwired to 2'b11 (M) because U-mode is absent.
         if (mstatus_val[12:11] !== (SU_MODE_EN ? 2'b00 : 2'b11)) begin
            $display("ERROR: MSTATUS.MPP should be %b after MRET -- MSTATUS: 0x%h %t ns",
                     (SU_MODE_EN ? 2'b00 : 2'b11), mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = %b after MRET (SU_MODE_EN=%0d) %t ns",
                     mstatus_val[12:11], SU_MODE_EN, $time);
         end
      end

      // Check MEPC is in ROM range (async interrupt, exact PC is nondeterministic)
      $display("");
      $display("--- MEPC range check ---");
      begin : check_mepc_timer
         reg [31:0] mepc_val;
         mepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];
         if (mepc_val[31:28] !== 4'h2) begin
            $display("ERROR: MEPC should be in ROM range (0x2xxxxxxx) -- MEPC: 0x%h %t ns", mepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MEPC in ROM range -- value: 0x%h %t ns", mepc_val, $time);
         end
      end


      //=================================================================
      // PHASE 3: Software interrupt
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: SOFTWARE INTERRUPT                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(5) @(posedge free_clk);

      // Assert software interrupt
      irq_m_software = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_software = 1'b0;

      // Check trap_count = 2
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      // Check MCAUSE = 0x80000003 (Machine Software Interrupt)
      $display("");
      $display("--- MCAUSE verification (software) ---");
      check_mem_value(`SPAD(32'h30), 32'h80000003);

      // Check MSTATUS inside handler
      $display("");
      $display("--- MSTATUS on trap entry ---");
      begin : check_mstatus_software
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)];

         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 in trap handler %t ns", $time);
         end

         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 in trap handler %t ns", $time);
         end

         if (mstatus_val[12:11] !== 2'b11) begin
            $display("ERROR: MSTATUS.MPP should be 11 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = 11 in trap handler %t ns", $time);
         end
      end

      // Check MEPC range
      $display("");
      $display("--- MEPC range check ---");
      begin : check_mepc_software
         reg [31:0] mepc_val;
         mepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)];
         if (mepc_val[31:28] !== 4'h2) begin
            $display("ERROR: MEPC should be in ROM range -- MEPC: 0x%h %t ns", mepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MEPC in ROM range -- value: 0x%h %t ns", mepc_val, $time);
         end
      end


      //=================================================================
      // PHASE 4: External interrupt
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 4: EXTERNAL INTERRUPT                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h41414141);
      repeat(5) @(posedge free_clk);

      // Assert external interrupt
      irq_m_external = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_external = 1'b0;

      // Check trap_count = 3
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      // Check MCAUSE = 0x8000000B (Machine External Interrupt)
      $display("");
      $display("--- MCAUSE verification (external) ---");
      check_mem_value(`SPAD(32'h40), 32'h8000000B);

      // Check MSTATUS inside handler
      $display("");
      $display("--- MSTATUS on trap entry ---");
      begin : check_mstatus_external
         reg [31:0] mstatus_val;
         mstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)];

         if (mstatus_val[3] !== 1'b0) begin
            $display("ERROR: MSTATUS.MIE should be 0 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MIE = 0 in trap handler %t ns", $time);
         end

         if (mstatus_val[7] !== 1'b1) begin
            $display("ERROR: MSTATUS.MPIE should be 1 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPIE = 1 in trap handler %t ns", $time);
         end

         if (mstatus_val[12:11] !== 2'b11) begin
            $display("ERROR: MSTATUS.MPP should be 11 in trap handler -- MSTATUS: 0x%h %t ns", mstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MSTATUS.MPP = 11 in trap handler %t ns", $time);
         end
      end

      // Check MEPC range
      $display("");
      $display("--- MEPC range check ---");
      begin : check_mepc_external
         reg [31:0] mepc_val;
         mepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)];
         if (mepc_val[31:28] !== 4'h2) begin
            $display("ERROR: MEPC should be in ROM range -- MEPC: 0x%h %t ns", mepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MEPC in ROM range -- value: 0x%h %t ns", mepc_val, $time);
         end
      end


      //=================================================================
      // PHASE 5: Priority test (timer + external simultaneously)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 5: INTERRUPT PRIORITY                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h51515151);
      repeat(5) @(posedge free_clk);

      // Assert both timer and external simultaneously
      irq_m_timer    = 1'b1;
      irq_m_external = 1'b1;

      // Wait for firmware to complete phase
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);

      // Deassert both
      irq_m_timer    = 1'b0;
      irq_m_external = 1'b0;

      // Check trap_count = 5 (3 previous + 2 from priority test)
      check_mem_value(`SPAD(32'h00), 32'h00000005);

      // Check both MCAUSE values present (order is implementation-defined)
      $display("");
      $display("--- Priority: both interrupts handled ---");
      begin : check_priority
         reg [31:0] mc1, mc2;
         mc1 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)];
         mc2 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h58)];

         if ((mc1 == 32'h80000007 && mc2 == 32'h8000000B) ||
             (mc1 == 32'h8000000B && mc2 == 32'h80000007)) begin
            $display("PASS:  Both timer and external interrupts handled %t ns", $time);
            $display("       1st handled: 0x%h, 2nd handled: 0x%h", mc1, mc2);
         end else begin
            $display("ERROR: Expected timer(0x80000007) and external(0x8000000B) -- got: 0x%h and 0x%h %t ns", mc1, mc2, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 6: MIE=0 blocks interrupts
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 6: MIE=0 BLOCKS INTERRUPTS                  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h61616161);
      repeat(5) @(posedge free_clk);

      // Assert timer interrupt (should be blocked since MSTATUS.MIE=0)
      irq_m_timer = 1'b1;

      // Wait for firmware to complete phase (NOP loop + checks)
      @(probes_cpu.x31==32'h66666666);

      // Deassert before firmware re-enables MIE
      irq_m_timer = 1'b0;
      repeat(3) @(posedge free_clk);

      // Check trap_count unchanged
      $display("");
      $display("--- Trap count unchanged (MIE=0) ---");
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)] !==
          ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)]) begin
         $display("ERROR: Trap count changed with MIE=0 -- before: %0d / after: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)],
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h64)], $time);
         error = error + 1;
      end else begin
         $display("PASS:  Trap count unchanged (MIE=0 blocked interrupt) -- count: %0d %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h60)], $time);
      end


      // Check callee-saved registers preserved after 5 interrupts
      $display("");
      $display("--- Callee-saved registers after 5 interrupts ---");
      check_cpu_reg(18, 32'hAAAAAAAA);   // s2
      check_cpu_reg(19, 32'hBBBBBBBB);   // s3
      check_cpu_reg(20, 32'hCCCCCCCC);   // s4
      check_cpu_reg(21, 32'hDDDDDDDD);   // s5
      check_cpu_reg(22, 32'hEEEEEEEE);   // s6


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

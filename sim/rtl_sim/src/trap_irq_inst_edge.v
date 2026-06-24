//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_inst_edge
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP IRQ INST EDGE
//   IRQ edge cases with specific instruction types:
//   - IRQ during instruction stream (compressed/standard)
//   - IRQ during CSR read-modify-write sequence
//   - IRQ after branch instruction
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

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

      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization
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

      check_mem_value(`SPAD(32'h00), 32'h00000000);

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: IRQ during instruction stream
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|          PHASE 2: IRQ DURING INSTRUCTION STREAM                    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h21212121);
      repeat(10) @(posedge free_clk);

      // Assert timer interrupt (should hit somewhere in the NOP sled)
      irq_m_timer = 1'b1;

      // Wait for Phase 2 complete
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_timer = 1'b0;

      $display("");
      $display("--- MCAUSE verification (expect timer) ---");
      check_mem_value(`SPAD(32'h24), 32'h80000007);

      $display("");
      $display("--- MEPC alignment check ---");
      begin : check_mepc_align_p2
         reg [31:0] mepc_val;
         mepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         if (mepc_val[0] !== 1'b0) begin
            $display("ERROR: MEPC[0] is not 0 -- MEPC: 0x%h %t ns", mepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MEPC properly aligned -- MEPC: 0x%h %t ns", mepc_val, $time);
         end
      end

      $display("");
      $display("--- MEPC range check (within sled) ---");
      begin : check_mepc_range_p2
         reg [31:0] mepc_val, sled_start, sled_end;
         mepc_val   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         sled_start = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)];
         sled_end   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];
         if (mepc_val < sled_start || mepc_val > sled_end) begin
            $display("ERROR: MEPC outside sled range -- MEPC: 0x%h, range: [0x%h, 0x%h] %t ns",
                     mepc_val, sled_start, sled_end, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MEPC within sled range -- MEPC: 0x%h, range: [0x%h, 0x%h] %t ns",
                     mepc_val, sled_start, sled_end, $time);
         end
      end

      $display("");
      $display("--- Resume marker check ---");
      check_mem_value(`SPAD(32'h28), 32'hAAAA1111);


      //=================================================================
      // PHASE 3: IRQ during CSR sequence
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|          PHASE 3: IRQ DURING CSR READ-MODIFY-WRITE SEQUENCE        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h31313131);
      repeat(10) @(posedge free_clk);

      // Assert timer interrupt (should hit during CSR sequence)
      irq_m_timer = 1'b1;

      // Wait for Phase 3 complete
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_timer = 1'b0;

      $display("");
      $display("--- MCAUSE verification (expect timer) ---");
      check_mem_value(`SPAD(32'h44), 32'h80000007);

      $display("");
      $display("--- MEPC range check (within CSR sequence) ---");
      begin : check_mepc_range_p3
         reg [31:0] mepc_val, seq_start, seq_end;
         mepc_val  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)];
         seq_start = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h4C)];
         seq_end   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];
         if (mepc_val < seq_start || mepc_val > seq_end) begin
            $display("ERROR: MEPC outside CSR sequence range -- MEPC: 0x%h, range: [0x%h, 0x%h] %t ns",
                     mepc_val, seq_start, seq_end, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MEPC within CSR sequence range -- MEPC: 0x%h, range: [0x%h, 0x%h] %t ns",
                     mepc_val, seq_start, seq_end, $time);
         end
      end

      $display("");
      $display("--- MSCRATCH consistency check ---");
      begin : check_mscratch
         reg [31:0] mscratch_val;
         // Valid MSCRATCH values: 0x00000000, 0x11111111, ..., 0xFFFFFFFF
         // (any of the 16 values written in the CSR sequence, or 0 if no write completed)
         mscratch_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)];
         // Check that MSCRATCH is 0xNNNNNNNN pattern (all nibbles same) or 0x00000000
         if (mscratch_val == 32'h00000000 ||
             mscratch_val == 32'h11111111 ||
             mscratch_val == 32'h22222222 ||
             mscratch_val == 32'h33333333 ||
             mscratch_val == 32'h44444444 ||
             mscratch_val == 32'h55555555 ||
             mscratch_val == 32'h66666666 ||
             mscratch_val == 32'h77777777 ||
             mscratch_val == 32'h88888888 ||
             mscratch_val == 32'h99999999 ||
             mscratch_val == 32'hAAAAAAAA ||
             mscratch_val == 32'hBBBBBBBB ||
             mscratch_val == 32'hCCCCCCCC ||
             mscratch_val == 32'hDDDDDDDD ||
             mscratch_val == 32'hEEEEEEEE ||
             mscratch_val == 32'hFFFFFFFF) begin
            $display("PASS:  MSCRATCH has valid value (0x%h) -- CSR atomicity OK %t ns",
                     mscratch_val, $time);
         end else begin
            $display("ERROR: MSCRATCH has unexpected value (0x%h) -- possible CSR atomicity violation %t ns",
                     mscratch_val, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // PHASE 4: IRQ after branch instruction
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|          PHASE 4: IRQ AFTER BRANCH INSTRUCTION                     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h41414141);
      repeat(8) @(posedge free_clk);

      // Assert external interrupt (timed around the branch)
      irq_m_external = 1'b1;

      // Wait for Phase 4 complete
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      // Deassert
      irq_m_external = 1'b0;

      $display("");
      $display("--- MCAUSE verification (expect external) ---");
      check_mem_value(`SPAD(32'h64), 32'h8000000B);

      $display("");
      $display("--- Resume marker check ---");
      check_mem_value(`SPAD(32'h68), 32'hBBBB2222);


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after all phases ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

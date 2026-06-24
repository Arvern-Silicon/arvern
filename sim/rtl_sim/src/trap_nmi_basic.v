//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_basic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI BASIC
//   Basic Smrnmi (Resumable NMI) verification:
//   - NMI handler entered when nmi_i asserts
//   - mnepc saved (address of interrupted instruction)
//   - mnstatus at entry: NMIE=0 (bit3), MNPP=11 (bits12:11) = M-mode
//   - mncause = 0x80000000 at NMI entry (bit[31]=1, cause=0)
//   - mnret resumes execution at mnepc
//   - NMIE=1 after mnret (mnstatus_after_ret checked after handler returns)
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

      // Disable error-on-exception (NMI entry will look like a trap)
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete — configure nmi_vector
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: INIT + CONFIGURE NMI VECTOR               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      // Read nmi_handler address from scratchpad[0x14] and drive nmi_vector
      begin : setup_nmi_vector
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

      // Verify scratchpad is otherwise zeroed
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // nmi_count = 0


      //=================================================================
      // PHASE 2: Assert NMI and wait for handler entry
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 2: ASSERT NMI                                |");
      $display(" ====================================================================");
      $display("");

      // Assert NMI for a few cycles then deassert (level-sensitive, one shot)
      repeat(5) @(posedge free_clk);
      nmi = 1'b1;
      repeat(5) @(posedge free_clk);
      nmi = 1'b0;

      $display("NMI asserted and deasserted %t ns", $time);


      //=================================================================
      // PHASE 3: End of test — verify all NMI CSR values
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 3: VERIFY NMI CSR VALUES                     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      // Check nmi_count = 1
      $display("");
      $display("--- NMI count ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      // Check mnepc is in ROM range (interrupted instruction is in ROM)
      $display("");
      $display("--- MNEPC range check ---");
      begin : check_mnepc
         reg [31:0] mnepc_val;
         mnepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];

         if (mnepc_val[31:28] !== 4'h2) begin
            $display("ERROR: MNEPC should be in ROM range (0x2xxxxxxx) -- MNEPC: 0x%h %t ns", mnepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC in ROM range -- value: 0x%h %t ns", mnepc_val, $time);
         end

         // MNEPC bit[0] must be 0 (always word-aligned per spec, PC is at least 2-byte aligned)
         if (mnepc_val[0] !== 1'b0) begin
            $display("ERROR: MNEPC bit[0] should be 0 (hardwired) -- MNEPC: 0x%h %t ns", mnepc_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNEPC bit[0] = 0 %t ns", $time);
         end
      end

      // Check mnstatus at entry: NMIE=0 (bit3), MNPP=11 (bits12:11)
      $display("");
      $display("--- MNSTATUS at NMI entry ---");
      begin : check_mnstatus_entry
         reg [31:0] mnstatus_val;
         mnstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];

         $display("MNSTATUS at entry: 0x%h %t ns", mnstatus_val, $time);

         // NMIE should be 0 (bit[3], cleared by hardware on NMI entry)
         if (mnstatus_val[3] !== 1'b0) begin
            $display("ERROR: MNSTATUS.NMIE should be 0 at NMI entry -- MNSTATUS: 0x%h %t ns", mnstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNSTATUS.NMIE = 0 at NMI entry %t ns", $time);
         end

         // MNPP should be 11 (bits[12:11], trapped from M-mode)
         if (mnstatus_val[12:11] !== 2'b11) begin
            $display("ERROR: MNSTATUS.MNPP should be 11 (M-mode) at NMI entry -- MNSTATUS: 0x%h %t ns", mnstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNSTATUS.MNPP = 11 (M-mode) at NMI entry %t ns", $time);
         end
      end

      // Check mncause = 0x80000000: bit[31]=1 (interrupt), bits[30:0]=0 (NMI cause code 0)
      $display("");
      $display("--- MNCAUSE at NMI entry (expect 0x80000000: interrupt bit set, cause=0) ---");
      check_mem_value(`SPAD(32'h0C), 32'h80000000);

      // Check mnstatus after mnret: NMIE=1 (bit3 set by mnret)
      $display("");
      $display("--- MNSTATUS after MNRET ---");
      begin : check_mnstatus_after_ret
         reg [31:0] mnstatus_val;
         mnstatus_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];

         $display("MNSTATUS after MNRET: 0x%h %t ns", mnstatus_val, $time);

         // NMIE should be 1 (restored by mnret)
         if (mnstatus_val[3] !== 1'b1) begin
            $display("ERROR: MNSTATUS.NMIE should be 1 after MNRET -- MNSTATUS: 0x%h %t ns", mnstatus_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  MNSTATUS.NMIE = 1 after MNRET %t ns", $time);
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

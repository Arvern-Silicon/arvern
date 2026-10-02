//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_zcmp_popret_partial_atomic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Zcmp cm.popret PARTIAL-ATOMICITY (sp-update race)
//   DISCRIMINATOR: captured sp value after trap handler.
//
//   Pre-fix : captured sp = 0x2000000C (sp_old + 48)  → FAIL
//   Post-fix: captured sp = 0x1FFFFFDC (sp_old)        → PASS
//----------------------------------------------------------------------------

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

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Test deliberately triggers a load access fault during cm.popret
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: CHECK INITIALIZATION                          |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : program_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler address not published %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
         end
      end

      @(probes_cpu.x31==32'h21212121);
      $display(" mnstatus.NMIE armed -- the bus error must now be DELIVERED");
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // PHASE 2: cm.popret with ra load faulting; verify sp atomicity
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: cm.popret PARTIAL ATOMICITY (sp must not advance         |");
      $display("|           if the trailing load faults)                             |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      // Exactly one trap fired
      $display("");
      $display("--- trap_count (expect 1) ---");
      // Exactly one RNMI, cause = bus error. mtvec is a NEGATIVE CONTROL:
      // mcause 5/7 are RESERVED.
      check_mem_value(`SPAD(32'h24), 32'h00000001);
      check_mem_value(`SPAD(32'h28), 32'h80000003);
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      // mcause == 5 (LD access fault)
      $display("--- trap mcause (expect 5 = LD access fault) ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      // *** PRIMARY DISCRIMINATOR ***
      // Captured sp must equal sp_old = 0x1FFFFFDC, NOT sp_old+48 = 0x2000000C.
      // Pre-fix: 0x2000000C (BUG — sp updated despite trailing-load fault)
      // Post-fix: 0x1FFFFFDC (FIX — sp atomic with ret commit per §28.13.4.2)
      $display("");
      $display("--- captured sp (expect 0x1FFFFFDC = sp_old — NOT 0x2000000C) ---");
      check_mem_value(`SPAD(32'h10), 32'h1FFFFFDC);

      // Sanity: ra LOAD was correctly killed (its WB write suppressed by dph_error)
      $display("--- captured ra (expect 0xFEEDFACE — ra LOAD must be killed) ---");
      check_mem_value(`SPAD(32'h14), 32'hFEEDFACE);


      //=================================================================
      // END OF TEST
      //=================================================================
      wait (probes_cpu.x31==32'hdeadbeef);
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

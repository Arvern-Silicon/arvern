//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_csr_illegal_rd
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ILLEGAL CSR -> rd PRESERVE
//   Verify that an illegal CSR access does NOT write rd.
//   Spec: "When a CSR access raises an exception, the destination register
//   shall not be written."
//
//   Phase 2: csrrw  t0, mvendorid, x0   -> rd unchanged
//   Phase 3: csrrs  t1, mvendorid, t6   -> rd unchanged
//   Phase 4: csrrwi t2, mvendorid, 1    -> rd unchanged
//   Phase 5: csrrw  t3, 0x3A0, x0       -> rd unchanged
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

      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // PHASE 2: csrrw rd, mvendorid, x0   -> rd must keep 0xCAFEBABE
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 2: csrrw rd, mvendorid, x0   (rd preserve)             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count = 1 ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE = 2 (illegal instruction) ---");
      check_mem_value(`SPAD(32'h24), 32'h00000002);

      $display("");
      $display("--- t0 preserved across illegal csrrw to RO CSR ---");
      check_mem_value(`SPAD(32'h20), 32'hCAFEBABE);


      //=================================================================
      // PHASE 3: csrrs rd, mvendorid, t6   -> rd must keep 0xC0FFEEEE
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 3: csrrs rd, mvendorid, t6   (rd preserve)             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count = 2 ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- MCAUSE = 2 (illegal instruction) ---");
      check_mem_value(`SPAD(32'h34), 32'h00000002);

      $display("");
      $display("--- t1 preserved across illegal csrrs (rs1!=x0) to RO CSR ---");
      check_mem_value(`SPAD(32'h30), 32'hC0FFEEEE);


      //=================================================================
      // PHASE 4: csrrwi rd, mvendorid, 1   -> rd must keep 0xBADC0DE5
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 4: csrrwi rd, mvendorid, 1   (rd preserve)             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count = 3 ---");
      check_mem_value(`SPAD(32'h00), 32'h00000003);

      $display("");
      $display("--- MCAUSE = 2 (illegal instruction) ---");
      check_mem_value(`SPAD(32'h44), 32'h00000002);

      $display("");
      $display("--- t2 preserved across illegal csrrwi to RO CSR ---");
      check_mem_value(`SPAD(32'h40), 32'hBADC0DE5);


      //=================================================================
      // PHASE 5: csrrw rd, 0xBFF, x0       -> rd must keep 0xDEFACED0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 5: csrrw rd, 0x3A0, x0   (rd preserve)                 |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- trap_count = 4 ---");
      check_mem_value(`SPAD(32'h00), 32'h00000004);

      $display("");
      $display("--- MCAUSE = 2 (illegal instruction) ---");
      check_mem_value(`SPAD(32'h54), 32'h00000002);

      $display("");
      $display("--- t3 preserved across csrrw to unimplemented CSR ---");
      check_mem_value(`SPAD(32'h50), 32'hDEFACED0);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

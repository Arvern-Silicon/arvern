//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_stval
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP STVAL
//   Verify STVAL register content for exceptions delegated to S-mode:
//   - Load misaligned   (SCAUSE=4, STVAL=faulting address)
//   - Store misaligned  (SCAUSE=6, STVAL=faulting address)
//   - Illegal instruction (SCAUSE=2, STVAL=0)
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

      $display("");
      $display("--- Initial register values ---");
      check_cpu_reg(18, 32'hAAAAAAAA);
      check_cpu_reg(19, 32'hBBBBBBBB);
      check_cpu_reg(20, 32'hCCCCCCCC);
      check_cpu_reg(21, 32'hDDDDDDDD);
      check_cpu_reg(22, 32'hEEEEEEEE);


      //=================================================================
      // PHASE 2: Load misaligned delegated to S-mode
      //          SCAUSE = 4, STVAL = 0x80000001
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 2: LOAD MISALIGNED -> S-MODE (SCAUSE=4, STVAL=0x80000001) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (load misaligned) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000004);

      $display("");
      $display("--- STVAL verification (expect faulting address 0x80000001) ---");
      check_mem_value(`SPAD(32'h34), 32'h80000001);


      //=================================================================
      // PHASE 3: Store misaligned delegated to S-mode
      //          SCAUSE = 6, STVAL = 0x80000003
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 3: STORE MISALIGNED -> S-MODE (SCAUSE=6, STVAL=0x80000003)|");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (store misaligned) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000006);

      $display("");
      $display("--- STVAL verification (expect faulting address 0x80000003) ---");
      check_mem_value(`SPAD(32'h44), 32'h80000003);


      //=================================================================
      // PHASE 4: Illegal instruction delegated to S-mode
      //          SCAUSE = 2, STVAL = 0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|  PHASE 4: ILLEGAL INSTRUCTION -> S-MODE (SCAUSE=2, STVAL=0)      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- SCAUSE verification (illegal instruction) ---");
      check_mem_value(`SPAD(32'h50), 32'h00000002);

      $display("");
      $display("--- STVAL verification (expect 0) ---");
      check_mem_value(`SPAD(32'h54), 32'h00000000);


      //=================================================================
      // Register preservation check
      //=================================================================
      $display("");
      $display("--- Register preservation after all delegated exceptions ---");
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

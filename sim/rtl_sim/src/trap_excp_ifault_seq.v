//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ifault_seq
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IFAULT EXCEPTION (SEQUENTIAL)
//   Instruction access fault by SEQUENTIAL fall-off past the 64 KiB exec-
//   SRAM (SRAM_X) boundary. The test writes a 17-NOP run into SRAM_X at
//   runtime; the last valid instruction is at 0x8000FFFC and the faulting
//   sequential fetch is 0x80010000 (unmapped -> AHB error response).
//   Spec: for mcause=1 (instruction access fault) MEPC and MTVAL must BOTH
//   equal the exact PC of the faulting fetch -- here 0x80010000, with NO
//   off-by-parcel / off-by-word skew.
//
//   Phase A: fetch buffer empty at fault (decoder waiting on faulting fetch).
//   Phase B: fetch buffer non-empty at fault (a buffered pre-fault instr is
//   draining when the speculative prefetch of 0x80010000 errors) --
//   this is the scenario where a PC skew manifests.
//
//   Empirically the primary trigger is -rsalu (random ALU stalls): the ALU-
//   stall backpressure on decode/execute lets the fetch buffer fill ahead,
//   producing the buffer-non-empty state at the faulting cycle. -rwsram on
//   its own does NOT trigger the skew (it slows fetch instead); combined
//   -rsalu -rwsram variants also fail. To reproduce: run with -rsalu.
//
//   BUG DISCRIMINATOR (per phase): the MEPC and MTVAL check_mem_value calls
//   against 0x80010000.  A non-C off-by-word skew shows 0x8000FFFC; a C-mode
//   off-by-parcel skew shows 0x8000FFFE -- either makes those checks fail
//   with a visible PC mismatch.
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

      // The sequential fall-off into 0x80010000 is an INTENTIONAL fault;
      // do not let the harness flag it. The MCAUSE / MEPC / MTVAL
      // check_mem_value oracles below remain strict and individually
      // reported, so a wrong cause or a skewed PC still fails the test.
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
      // PHASE A: Sequential fall-off, fetch buffer EMPTY at fault.
      //          JALR lands 1 instr before the SRAM_X boundary; the
      //          decoder is directly waiting on the faulting fetch
      //          (0x80010000). Expect MCAUSE=1, MEPC=MTVAL=0x80010000.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("| PHASE A: SEQ FALL-OFF, BUFFER EMPTY  (fault @ 0x80010000, cause 1) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000001);

      $display("");
      $display("--- MEPC verification (expect exact faulting PC 0x80010000) ---");
      $display("    [BUG DISCRIMINATOR: off-by-word skew -> 0x8000FFFC]");
      check_mem_value(`SPAD(32'h24), 32'h80010000);

      $display("");
      $display("--- MTVAL verification (expect exact faulting PC 0x80010000) ---");
      $display("    [BUG DISCRIMINATOR: off-by-word skew -> 0x8000FFFC]");
      check_mem_value(`SPAD(32'h28), 32'h80010000);


      //=================================================================
      // PHASE B: Sequential fall-off, fetch buffer NON-EMPTY at fault.
      //          JALR lands >=16 instrs before the boundary; a buffered
      //          pre-fault instr is draining when the speculative
      //          prefetch of 0x80010000 errors. -rsalu (ALU-stall back-
      //          pressure) is the empirical primary trigger.
      //          Expect MCAUSE=1, MEPC=MTVAL=0x80010000 (SAME address;
      //          there is exactly one SRAM_X fall-off boundary -- the
      //          discriminator vs Phase A is the buffer state).
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("| PHASE B: SEQ FALL-OFF, BUFFER NON-EMPTY (fault @ 0x80010000, c=1)  |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);

      $display("");
      $display("--- MCAUSE verification (instruction access fault) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000001);

      $display("");
      $display("--- MEPC verification (expect exact faulting PC 0x80010000) ---");
      $display("    [BUG DISCRIMINATOR: off-by-word skew -> 0x8000FFFC]");
      check_mem_value(`SPAD(32'h34), 32'h80010000);

      $display("");
      $display("--- MTVAL verification (expect exact faulting PC 0x80010000) ---");
      $display("    [BUG DISCRIMINATOR: off-by-word skew -> 0x8000FFFC]");
      check_mem_value(`SPAD(32'h38), 32'h80010000);


      //=================================================================
      // Register preservation check (across 2 sequential ifaults)
      //=================================================================
      $display("");
      $display("--- Register preservation after 2 sequential ifaults ---");
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

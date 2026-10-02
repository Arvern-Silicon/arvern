//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_plic_size_violation
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PLIC AHB size-check ERROR response
//   Non-word accesses to any PLIC register must AHB-ERROR. The firmware:
//     1. SW priority[1] = 0x55      -- succeeds.
//     2. SB priority[1]             -- store access fault (cause 7).
//     3. LH threshold[ctx0]         -- load  access fault (cause 5).
//     4. LW priority[1]             -- still reads 0x55, confirming the
//        bad-size write of phase 2 was rejected, not committed.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

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

      // Two real exceptions are expected -- suppress the global exception
      // monitor's error counter.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: legit word write
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: word SW to priority[1] succeeds               |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h1E1E1E1E);
      repeat(3) @(posedge free_clk);

      begin : program_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler address not published %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
         end
      end

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000000);    // no trap yet


      //=================================================================
      // PHASE 2: byte write -> store access fault
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 2: SB priority[1] -> AHB ERROR -> SAF            |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);    // 1 trap fired
      check_mem_value(`SPAD(32'h04), 32'h80000003);    // mncause = data-bus error
      check_mem_value(`SPAD(32'h08), 32'h0C000004);    // marv_eaddr = PLIC_PRI1
      $display("PASS:  byte store to PLIC priority register AHB-ERRORed and trapped %t ns",
               $time);


      //=================================================================
      // PHASE 3: halfword read -> load access fault
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 3: LH threshold[ctx0] -> AHB ERROR -> LAF        |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);    // 2 traps total
      check_mem_value(`SPAD(32'h0C), 32'h80000003);    // mncause = data-bus error
      check_mem_value(`SPAD(32'h10), 32'h0C200000);    // marv_eaddr = PLIC_TH_M
      $display("PASS:  halfword load from PLIC threshold AHB-ERRORed and trapped %t ns",
               $time);


      //=================================================================
      // PHASE 4: register integrity check
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 4: priority[1] still = 0x55 (bad SB was rejected)      |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);    // still 2 traps
      // PRIO_BITS=3 -> priority register holds the low 3 bits of 0x55 (= 0x5).
      // The bad byte SB in phase 2 was rejected before reaching the
      // register file, so the read-back must still show 0x5.
      check_mem_value(`SPAD(32'h14), 32'h00000005);   // priority field truncates 0x55 -> 5

      // mcause 5/7 are RESERVED: no synchronous trap at all.
      $display("");
      $display("--- mtvec must NEVER be entered ---");
      check_mem_value(`SPAD(32'h1C), 32'h00000000);
      $display("PASS:  PLIC priority[1] kept 0x5 -- bad-size write was rejected %t ns",
               $time);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

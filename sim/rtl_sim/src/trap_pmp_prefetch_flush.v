//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_prefetch_flush
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: a pmpcfg write applies to the very next fetch, prefetch included
//   Companion testbench for trap_pmp_prefetch_flush.s. Each phase's block B
//   follows the csrw pmpcfg0 with no branch in between, so its first parcels
//   were prefetched under the old configuration.
//     Phase 1 (no fence.i):   cause 1 exactly at &B1, none of B1 ran
//     Phase 2 (fence.i):      cause 1 exactly at &B2 (control)
//     Phase 3 (X=1):          B3 runs to completion, no trap
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

`define SPAD(byte_off)  ((byte_off)/4)

// Every sentinel wait is bounded so a fault->resume->fault loop in a block
// produces ERROR lines instead of the global simulation timeout.
localparam integer WAIT_MAX = 10000;

reg [31:0] mval, addr;

task wait_sync;
   input [31:0] value;
   begin
      to = 0;
      while ((probes_cpu.x31 !== value) && (to < WAIT_MAX)) begin
         @(posedge free_clk);
         to = to + 1;
      end
      if (to >= WAIT_MAX) begin
         $display("ERROR: sentinel 0x%h not seen within %0d cycles (no forward progress) %t ns", value, WAIT_MAX, $time);
         error = error + 1;
      end
   end
endtask

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // The test takes PMP fetch faults on purpose.
      error_on_exception = 0;
      random_irq_enable  = 0;

      $display("");
      $display(" ====================================================================");
      $display("|         PMP PREFETCH FLUSH: pmpcfg write vs prefetched parcels     |");
      $display(" ====================================================================");
      $display("");

      //=================================================================
      // PHASE 1: csrw pmpcfg0 straight into B1 (no fence.i)
      //=================================================================
      wait_sync(32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 1: locked no-X rule written right before B1, no fence.i ---");
      check_cpu_reg(10, 32'h00000001);                 // a0: exactly one trap
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // mcause = instruction access fault
      addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];   // &B1
      mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];   // mepc
      if (mval !== addr) begin
         $display("ERROR: phase 1 mepc=0x%h != &B1=0x%h (prefetched parcels ran past the pmpcfg write) %t ns", mval, addr, $time);
         error = error + 1;
      end else begin
         $display("PASS:  phase 1 mepc=0x%h == &B1 %t ns", mval, $time);
      end
      mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];   // mtval
      if (mval !== addr) begin
         $display("ERROR: phase 1 mtval=0x%h != &B1=0x%h %t ns", mval, addr, $time);
         error = error + 1;
      end else begin
         $display("PASS:  phase 1 mtval=0x%h == &B1 %t ns", mval, $time);
      end
      $display("--- Phase 1: none of B1 executed (s3 == 0) ---");
      check_cpu_reg(19, 32'h00000000);                 // s3: B1 instructions that ran

      //=================================================================
      // PHASE 2: control -- fence.i between csrw and B2
      //=================================================================
      wait_sync(32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 2: same rule with fence.i (control) ---");
      check_cpu_reg(11, 32'h00000001);                 // a1: exactly one trap
      check_mem_value(`SPAD(32'h10), 32'h00000001);   // mcause = 1
      addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)];   // &B2
      mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];   // mepc
      if (mval !== addr) begin
         $display("ERROR: phase 2 mepc=0x%h != &B2=0x%h %t ns", mval, addr, $time);
         error = error + 1;
      end else begin
         $display("PASS:  phase 2 mepc=0x%h == &B2 %t ns", mval, $time);
      end
      mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];   // mtval
      if (mval !== addr) begin
         $display("ERROR: phase 2 mtval=0x%h != &B2=0x%h %t ns", mval, addr, $time);
         error = error + 1;
      end else begin
         $display("PASS:  phase 2 mtval=0x%h == &B2 %t ns", mval, $time);
      end
      check_cpu_reg(20, 32'h00000000);                 // s4: none of B2 ran

      //=================================================================
      // PHASE 3: negative -- X granted, B3 runs
      //=================================================================
      wait_sync(32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("--- Phase 3: locked X rule, B3 executes (negative) ---");
      check_cpu_reg(12, 32'h00000000);                 // a2: no trap
      check_cpu_reg(21, 32'h00000008);                 // s5: all eight ran

      //=================================================================
      // END OF TEST
      //=================================================================
      wait_sync(32'hdeadbeef);
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

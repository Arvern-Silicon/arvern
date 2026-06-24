//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_mstatus_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: mstatus SUM/MXR/TVM WARL CONFORMANCE
//   Verifies WARL behavior of mstatus.SUM (bit 18), mstatus.MXR (bit 19),
//   mstatus.TVM (bit 20), and the corresponding sstatus.SUM/MXR view.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

task check_bit;
   input  integer       address;
   input  integer       bit_pos;
   input                expect_set;     // 1 -> bit must be 1; 0 -> bit must be 0
   reg          [31:0]  val;
   begin
      #1;
      val = ahb_bus_system_inst.sram_x_inst.mem[address];
      if (val[bit_pos] !== expect_set) begin
         $display("ERROR: Bit check     -- address: 0x%h bit %0d -- read: %b / expected: %b (full word 0x%h) %t ns",
                  address, bit_pos, val[bit_pos], expect_set, val, $time);
         error = error + 1;
      end else begin
         $display("PASS:  Bit check     -- address: 0x%h bit %0d -- value: %b %t ns",
                  address, bit_pos, val[bit_pos], $time);
      end
   end
endtask

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
      // PHASE 1: init
      //=================================================================
      $display("");
      $display(" PHASE 1: init");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: SUM=1 via mstatus — verify mstatus and sstatus views.
      //=================================================================
      $display("");
      $display(" PHASE 2: SUM=1 via mstatus");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_bit(`SPAD(32'h20), 18, 1'b1);   // mstatus.SUM
      check_bit(`SPAD(32'h24), 18, 1'b1);   // sstatus.SUM


      //=================================================================
      // PHASE 3: MXR=1 via sstatus — verify sstatus and mstatus views.
      //=================================================================
      $display("");
      $display(" PHASE 3: MXR=1 via sstatus");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      check_bit(`SPAD(32'h30), 19, 1'b1);   // sstatus.MXR
      check_bit(`SPAD(32'h34), 19, 1'b1);   // mstatus.MXR


      //=================================================================
      // PHASE 4: TVM=1 via mstatus. TVM is M-only.
      //=================================================================
      $display("");
      $display(" PHASE 4: TVM=1 via mstatus (sstatus view must NOT show it)");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      check_bit(`SPAD(32'h40), 20, 1'b1);   // mstatus.TVM
      check_bit(`SPAD(32'h44), 20, 1'b0);   // sstatus does not expose TVM


      //=================================================================
      // PHASE 5: clear all — verify both views report 0.
      //=================================================================
      $display("");
      $display(" PHASE 5: clear SUM/MXR/TVM");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      check_bit(`SPAD(32'h50), 18, 1'b0);   // mstatus.SUM cleared
      check_bit(`SPAD(32'h50), 19, 1'b0);   // mstatus.MXR cleared
      check_bit(`SPAD(32'h50), 20, 1'b0);   // mstatus.TVM cleared
      check_bit(`SPAD(32'h54), 18, 1'b0);   // sstatus.SUM cleared
      check_bit(`SPAD(32'h54), 19, 1'b0);   // sstatus.MXR cleared


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

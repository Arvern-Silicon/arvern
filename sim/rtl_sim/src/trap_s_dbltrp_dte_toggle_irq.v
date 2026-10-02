//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_s_dbltrp_dte_toggle_irq
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: S DBLTRP DTE TOGGLE IRQ - doubled delegated interrupt
//   Requires SU_MODE_EN==1. S handler (DTE=0) sets SIE; M sets DTE=1, which
//   exposes the SDT left by the S trap entry (traps_and_interrupts.md §10);
//   mret to S with STIP pending/delegated/enabled -> double trap into M:
//   mcause=16, mtval2=5 (code only), mtval=0, mepc=&s_land, MPP=S, S bank
//   untouched, delivered through the mtvec base in vectored mode.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

task mem_eq;
   input [31:0]     off_a;
   input [31:0]     off_b;
   input [8*24-1:0] what;
   reg   [31:0]     va, vb;
   begin
      va = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off_a)];
      vb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off_b)];
      if ((va !== vb) || (vb === 32'h0)) begin
         $display("ERROR: %0s -- read 0x%h / expected 0x%h %t ns", what, va, vb, $time);
         error = error + 1;
      end else begin
         $display("PASS:  %0s -- 0x%h", what, va);
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
      random_irq_enable  = 0;

      wait ((probes_cpu.x31 === 32'hdeadbeef) ||
            (probes_cpu.x31 === 32'h0BADBADB) ||
            (probes_cpu.x31 === 32'h0BADBAD6) ||
            (probes_cpu.x31 === 32'h0BADBAD7) ||
            (probes_cpu.x31 === 32'h0BADBAD8));
      repeat(40) @(posedge free_clk);

      case (probes_cpu.x31)
         32'h0BADBADB: begin
            $display("ERROR: unexpected M trap or interrupt vector slot, mcause=0x%h %t ns",
                     ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)], $time);
            error = error + 1;
         end
         32'h0BADBAD6: begin
            $display("ERROR: after DTE 0->1, mstatus SDT|SIE = 0x%h, expected 0x01000002 %t ns",
                     ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)], $time);
            error = error + 1;
         end
         32'h0BADBAD7: begin
            $display("ERROR: delegated STI taken in S instead of doubled to M, scause=0x%h %t ns",
                     ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)], $time);
            error = error + 1;
         end
         32'h0BADBAD8: begin
            $display("ERROR: illegal1 did not trap to S %t ns", $time);
            error = error + 1;
         end
         default: ;
      endcase

      $display("");
      $display("--- Setup: DTE cleared, delegated illegal taken in S ---");
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // DTE after clear
      check_mem_value(`SPAD(32'h44), 32'h00000001);   // one S handler entry
      check_mem_value(`SPAD(32'h0C), 32'h00000002);   // scause
      check_mem_value(`SPAD(32'h10), 32'h00000000);   // SDT reads 0 at DTE=0
      check_mem_value(`SPAD(32'h14), 32'h00000002);   // SIE settable at DTE=0

      $display("--- DTE 0->1 exposes SDT; SIE still 1 ---");
      check_mem_value(`SPAD(32'h1C), 32'h08000000);   // DTE after set
      check_mem_value(`SPAD(32'h18), 32'h01000002);   // SDT|SIE

      $display("--- Doubled delegated STI delivered to M ---");
      check_mem_value(`SPAD(32'h20), 32'h00000010);   // mcause = 16, interrupt bit 0
      check_mem_value(`SPAD(32'h24), 32'h00000005);   // mtval2 = STI code
      check_mem_value(`SPAD(32'h28), 32'h00000000);   // mtval as an M interrupt would write
      mem_eq(32'h2C, 32'h30, "mepc == &s_land");
      check_mem_value(`SPAD(32'h34), 32'h00000001);   // MPP = S

      $display("--- S trap CSRs untouched by the double trap ---");
      check_mem_value(`SPAD(32'h38), 32'h00000002);   // scause still illegal1's
      mem_eq(32'h3C, 32'h40, "sepc == &illegal1");

      $display("--- Trap accounting ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);   // ecall + double trap
      check_mem_value(`SPAD(32'h04), 32'h00000000);
      check_mem_value(`SPAD(32'h48), 32'h00000000);
      check_cpu_reg(31, 32'hdeadbeef);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

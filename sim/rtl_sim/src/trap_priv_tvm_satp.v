//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_tvm_satp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TVM SATP - mstatus.TVM gates S-mode satp access
//   Requires SU_MODE_EN==1. Priv §3.1.6.6: "When TVM=1, attempts to read or
//   write the satp CSR ... while executing in S-mode will raise an
//   illegal-instruction exception. When TVM=0, these operations are
//   permitted in S-mode." M-mode access is unaffected; satp reads 0 (Bare
//   stub) and an unsupported-MODE write has no effect (Priv §12.1.11).
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)
`define SLOT(idx)       (`SPAD(32'h100) + (idx)*8)

reg [8*24-1:0] pr_name;

task pr_check;
   input integer    idx;
   input integer    trapped;      // 1: expect illegal-instruction
   input [31:0]     exp_mpp;
   input [31:0]     exp_rd;
   reg   [31:0]     r_cause, r_tval, r_pcoff, r_mpp, r_rd;
   begin
      r_cause = ahb_bus_system_inst.sram_x_inst.mem[`SLOT(idx)+0];
      r_tval  = ahb_bus_system_inst.sram_x_inst.mem[`SLOT(idx)+1];
      r_pcoff = ahb_bus_system_inst.sram_x_inst.mem[`SLOT(idx)+2];
      r_mpp   = ahb_bus_system_inst.sram_x_inst.mem[`SLOT(idx)+3];
      r_rd    = ahb_bus_system_inst.sram_x_inst.mem[`SLOT(idx)+4];
      if (trapped) begin
         if ((r_cause !== 32'd2) || (r_tval !== 32'd0) || (r_pcoff !== 32'd0) ||
             (r_mpp !== exp_mpp) || (r_rd !== 32'h5A5A5A5A)) begin
            $display("ERROR: probe %0d (%0s) -- expected illegal: mcause=2 mtval=0 mepc-probe=0 MPP=%0d rd=5a5a5a5a / got mcause=0x%h mtval=0x%h mepc-probe=0x%h MPP=0x%h rd=0x%h %t ns",
                     idx, pr_name, exp_mpp, r_cause, r_tval, r_pcoff, r_mpp, r_rd, $time);
            error = error + 1;
         end else begin
            $display("PASS:  probe %0d (%0s) -- illegal-instruction, MPP=%0d, rd unwritten", idx, pr_name, r_mpp);
         end
      end else begin
         if ((r_cause !== 32'hEEEEEEEE) || (r_rd !== exp_rd)) begin
            $display("ERROR: probe %0d (%0s) -- expected no trap, rd=0x%h / got mcause-slot=0x%h rd=0x%h %t ns",
                     idx, pr_name, exp_rd, r_cause, r_rd, $time);
            error = error + 1;
         end else begin
            $display("PASS:  probe %0d (%0s) -- no trap, rd=0x%h", idx, pr_name, r_rd);
         end
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

      wait ((probes_cpu.x31 === 32'hdeadbeef) || (probes_cpu.x31 === 32'h0BADBADB));
      repeat(40) @(posedge free_clk);

      if (probes_cpu.x31 === 32'h0BADBADB) begin
         $display("ERROR: unexpected trap, mcause=0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)], $time);
         error = error + 1;
      end

      $display("");
      $display("--- S-mode, TVM=0: satp accessible, reads 0, Sv32/PPN writes have no effect ---");
      pr_name = "S0 csrr satp";          pr_check( 0, 0, 0, 32'h00000000);
      pr_name = "S0 csrrw satp,Sv32";    pr_check( 1, 0, 0, 32'h00000000);
      pr_name = "S0 csrr satp";          pr_check( 2, 0, 0, 32'h00000000);
      pr_name = "S0 csrrw satp,Bare+PPN";pr_check( 3, 0, 0, 32'h00000000);
      pr_name = "S0 csrr satp";          pr_check( 4, 0, 0, 32'h00000000);

      $display("");
      $display("--- M-mode, TVM=1: satp unaffected ---");
      check_mem_value(`SPAD(32'h08), 32'h00100000);    // TVM reads back 1
      pr_name = "M1 csrr satp";          pr_check( 5, 0, 0, 32'h00000000);
      pr_name = "M1 csrrw satp";         pr_check( 6, 0, 0, 32'h00000000);
      pr_name = "M1 csrr satp";          pr_check( 7, 0, 0, 32'h00000000);

      $display("");
      $display("--- S-mode, TVM=1: every satp access traps (MPP=S) ---");
      pr_name = "S1 csrr satp";          pr_check( 8, 1, 1, 0);
      pr_name = "S1 csrrs satp,x0";      pr_check( 9, 1, 1, 0);
      pr_name = "S1 csrw satp";          pr_check(10, 1, 1, 0);
      pr_name = "S1 csrrw satp,x0";      pr_check(11, 1, 1, 0);
      pr_name = "S1 csrrci satp,0";      pr_check(12, 1, 1, 0);
      pr_name = "S1 csrr sscratch";      pr_check(13, 0, 0, 32'h0BADF00D);

      $display("");
      $display("--- S-mode, TVM cleared again: satp accessible ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000000);    // TVM reads back 0
      pr_name = "S2 csrr satp";          pr_check(14, 0, 0, 32'h00000000);

      $display("");
      check_mem_value(`SPAD(32'h00), 32'd5);           // trapped probes
      check_mem_value(`SPAD(32'h04), 32'h00000000);    // no unexpected trap

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

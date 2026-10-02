//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_csr_access_levels
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CSR PRIV LEVELS - address-encoded CSR privilege from U and S
//   Requires SU_MODE_EN==1. Priv §2.1: "Attempts to access a CSR without
//   appropriate privilege level raise illegal-instruction exceptions". Each
//   probe slot records mcause/mtval/mepc offset/MPP; a trapping probe must
//   leave its rd (sentinel 0x5A5A5A5A) unwritten.
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

      wait (probes_cpu.x31 === 32'h11111111);
      $display("--- M setup done, entering U ---");

      wait ((probes_cpu.x31 === 32'hdeadbeef) || (probes_cpu.x31 === 32'h0BADBADB));
      repeat(40) @(posedge free_clk);

      if (probes_cpu.x31 === 32'h0BADBADB) begin
         $display("ERROR: unexpected trap, mcause=0x%h %t ns",
                  ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)], $time);
         error = error + 1;
      end

      $display("");
      $display("--- U-mode: S-level and M-level CSRs must trap (MPP=U) ---");
      pr_name = "U csrr sstatus";      pr_check( 0, 1, 0, 0);
      pr_name = "U csrrw sscratch";    pr_check( 1, 1, 0, 0);
      pr_name = "U csrrs stvec,x0";    pr_check( 2, 1, 0, 0);
      pr_name = "U csrr scause";       pr_check( 3, 1, 0, 0);
      pr_name = "U csrw sepc";         pr_check( 4, 1, 0, 0);
      pr_name = "U csrr stval";        pr_check( 5, 1, 0, 0);
      pr_name = "U csrr sie";          pr_check( 6, 1, 0, 0);
      pr_name = "U csrrc sip";         pr_check( 7, 1, 0, 0);
      pr_name = "U csrr satp";         pr_check( 8, 1, 0, 0);
      pr_name = "U csrrw scounteren";  pr_check( 9, 1, 0, 0);
      pr_name = "U csrr mstatus";      pr_check(10, 1, 0, 0);
      pr_name = "U csrrw mscratch";    pr_check(11, 1, 0, 0);
      pr_name = "U csrr mepc";         pr_check(12, 1, 0, 0);
      pr_name = "U csrr mtvec";        pr_check(13, 1, 0, 0);
      pr_name = "U csrr mhartid";      pr_check(14, 1, 0, 0);
      pr_name = "U csrr mnstatus";     pr_check(15, 1, 0, 0);
      pr_name = "U csrw stvec";        pr_check(32, 1, 0, 0);

      $display("");
      $display("--- S-mode: M-level CSRs must trap (MPP=S) ---");
      pr_name = "S csrr mstatus";      pr_check(16, 1, 1, 0);
      pr_name = "S csrrw mscratch";    pr_check(17, 1, 1, 0);
      pr_name = "S csrr mtvec";        pr_check(18, 1, 1, 0);
      pr_name = "S csrw mepc";         pr_check(19, 1, 1, 0);
      pr_name = "S csrr mcause";       pr_check(20, 1, 1, 0);
      pr_name = "S csrr mie";          pr_check(21, 1, 1, 0);
      pr_name = "S csrr mip";          pr_check(22, 1, 1, 0);
      pr_name = "S csrr medeleg";      pr_check(23, 1, 1, 0);
      pr_name = "S csrr menvcfgh";     pr_check(24, 1, 1, 0);
      pr_name = "S csrr mnscratch";    pr_check(25, 1, 1, 0);
      pr_name = "S csrr mvendorid";    pr_check(26, 1, 1, 0);
      pr_name = "S csrr marv_ctl";     pr_check(27, 1, 1, 0);
      pr_name = "S csrr marv_epc";     pr_check(28, 1, 1, 0);
      pr_name = "S csrr mtval2";       pr_check(31, 1, 1, 0);

      $display("");
      $display("--- S-mode: sscratch is legal (controls) ---");
      pr_name = "S csrrw sscratch";    pr_check(29, 0, 0, 32'h13572468);
      pr_name = "S csrr sscratch";     pr_check(30, 0, 0, 32'hA5A5A5A5);

      $display("");
      $display("--- Trap count and CSRs the denied writes targeted ---");
      check_mem_value(`SPAD(32'h00), 32'd31);          // trapped probes
      check_mem_value(`SPAD(32'h04), 32'h00000000);    // no unexpected trap
      check_mem_value(`SPAD(32'h08), 32'h2468ACE0);    // mscratch unchanged
      check_mem_value(`SPAD(32'h0C), 32'h20001230);    // sepc unchanged
      check_mem_value(`SPAD(32'h10), 32'h20000100);    // stvec unchanged
      check_mem_value(`SPAD(32'h14), 32'hA5A5A5A5);    // sscratch = S control write only

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_csr_hpm_absent_razwi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: HPM ABSENT/RAZWI - Zihpm two-case existence rule (M-mode)
//   ZIHPM_NR==0: mhpmcounter*/mhpmevent*/hpmcounter3 raise illegal-instruction.
//   ZIHPM_NR>0: unprovided indices (11, 31) are read-only zero, no trap
//   (Priv §3.1.10 "a legal implementation is to make both the counter and
//   its corresponding event selector be read-only 0"). Both: a write to the
//   read-only hpmcounter3 traps.
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
            $display("PASS:  probe %0d (%0s) -- illegal-instruction, rd unwritten", idx, pr_name);
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

      if (ZIHPM_NR == 0) begin
         $display("--- ZIHPM_NR=0: Zihpm absent, every access traps ---");
         pr_name = "csrr mhpmcounter3";   pr_check(0, 1, 3, 0);
         pr_name = "csrw mhpmcounter3";   pr_check(1, 1, 3, 0);
         pr_name = "csrr mhpmevent3";     pr_check(2, 1, 3, 0);
         pr_name = "csrw mhpmevent3";     pr_check(3, 1, 3, 0);
         pr_name = "csrr mhpmcounterh3";  pr_check(4, 1, 3, 0);
         pr_name = "csrr hpmcounter3";    pr_check(5, 1, 3, 0);
         pr_name = "csrr mhpmcounter31";  pr_check(6, 1, 3, 0);
         pr_name = "csrr mhpmevent31";    pr_check(7, 1, 3, 0);
         pr_name = "csrw hpmcounter3 RO"; pr_check(8, 1, 3, 0);
         check_mem_value(`SPAD(32'h00), 32'd9);
      end else begin
         $display("--- ZIHPM_NR=%0d: unprovided indices read-only zero ---", ZIHPM_NR);
         pr_name = "csrw mhpmevent3=7";   pr_check( 0, 0, 0, 32'h5A5A5A5A);
         pr_name = "csrr mhpmevent3";     pr_check( 1, 0, 0, 32'h00000007);
         pr_name = "csrw mhpmcounter11";  pr_check( 2, 0, 0, 32'h5A5A5A5A);
         pr_name = "csrr mhpmcounter11";  pr_check( 3, 0, 0, 32'h00000000);
         pr_name = "csrw mhpmevent11";    pr_check( 4, 0, 0, 32'h5A5A5A5A);
         pr_name = "csrr mhpmevent11";    pr_check( 5, 0, 0, 32'h00000000);
         pr_name = "csrw mhpmcounterh31"; pr_check( 6, 0, 0, 32'h5A5A5A5A);
         pr_name = "csrr mhpmcounterh31"; pr_check( 7, 0, 0, 32'h00000000);
         pr_name = "csrw mhpmevent31";    pr_check( 8, 0, 0, 32'h5A5A5A5A);
         pr_name = "csrr mhpmevent31";    pr_check( 9, 0, 0, 32'h00000000);
         pr_name = "csrw mhpmcounter31";  pr_check(10, 0, 0, 32'h5A5A5A5A);
         pr_name = "csrr mhpmcounter31";  pr_check(11, 0, 0, 32'h00000000);
         pr_name = "csrr hpmcounter31";   pr_check(12, 0, 0, 32'h00000000);
         pr_name = "csrr hpmcounterh11";  pr_check(13, 0, 0, 32'h00000000);
         pr_name = "csrw hpmcounter3 RO"; pr_check(14, 1, 3, 0);
         check_mem_value(`SPAD(32'h00), 32'd1);
      end
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

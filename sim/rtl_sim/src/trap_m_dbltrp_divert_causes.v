//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_m_dbltrp_divert_causes
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Smdbltrp divert to the RNMI handler, one case per cause
//   Priv §8.3: a double trap in M "bit MXLEN-1 is set to 0 and the
//   least-significant bits are set to the cause code corresponding to the
//   exception that precipitated the double trap". Causes 11/2/3 (+5/7 with
//   PMP_NR>0), MDT set by a CSR write (path A) and by trap entry (path B):
//   mncause = cause, mnepc = faulting PC, mnstatus MNPP=M / NMIE=0 at entry,
//   M trap stack untouched, no lockup.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)
`define MEM(byte_off)   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(byte_off)]

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] base;
reg [31:0] exp_cause;
reg [31:0] cause_tab [0:4];
integer    ncause;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      cause_tab[0] = 32'd11;
      cause_tab[1] = 32'd2;
      cause_tab[2] = 32'd3;
      cause_tab[3] = 32'd5;
      cause_tab[4] = 32'd7;
      ncause       = (PMP_NR > 0) ? 5 : 3;

      wait(probes_cpu.x31 == 32'h11111111);
      $display("Smdbltrp divert causes: init done %t ns", $time);

      wait(probes_cpu.x31 == 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|   Smdbltrp: double trap in M diverts to RNMI, mncause = cause      |");
      $display(" ====================================================================");

      for (kk = 0; kk < 10; kk = kk + 1)
         if ((kk % 5) < ncause) begin
            base      = 32'h100 + kk*32;
            exp_cause = cause_tab[kk % 5];
            $display("");
            $display("--- case %0d: path %s, precipitating cause %0d ---", kk, (kk < 5) ? "A (csrs MDT)" : "B (trap-set MDT)", exp_cause);
            check_mem_value(`SPAD(base + 0),  exp_cause);                     // mncause, bit 31 = 0
            check_mem_value(`SPAD(base + 4),  `MEM(base + 28));                // mnepc = faulting PC
            if ((`MEM(base + 8) & 32'h1808) !== 32'h1800) begin
               $display("ERROR: mnstatus at entry 0x%h: expected MNPP=M, NMIE=0 %t ns", `MEM(base + 8), $time);
               error = error + 1;
            end else
               $display("PASS:  mnstatus at entry MNPP=M, NMIE=0 %t ns", $time);
            if (kk < 5) begin
               check_mem_value(`SPAD(base + 12), 32'h20000F00);             // mepc sentinel
               check_mem_value(`SPAD(base + 16), 32'h00000006);             // mcause sentinel
               check_mem_value(`SPAD(base + 20), 32'h5A5A5A5A);             // mtval sentinel
            end else begin
               check_mem_value(`SPAD(base + 12), `MEM(32'h40 + (kk-5)*4));   // mepc = first ECALL
               check_mem_value(`SPAD(base + 16), 32'h0000000B);
               check_mem_value(`SPAD(base + 20), 32'h00000000);
            end
            check_mem_value(`SPAD(base + 24), 32'h00000001);
         end

      $display("");
      $display("--- no trap reached mtvec on path A; handler_b once per path-B case ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);
      check_mem_value(`SPAD(32'h04), ncause);
      $display("");
      $display("--- ordinary ECALL afterwards goes through mtvec ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000001);
      check_mem_value(`SPAD(32'h10), 32'h0000000B);

      if (lockup !== 1'b0) begin
         $display("ERROR: lockup_o asserted %t ns", $time);
         error = error + 1;
      end else
         $display("PASS:  lockup_o low %t ns", $time);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

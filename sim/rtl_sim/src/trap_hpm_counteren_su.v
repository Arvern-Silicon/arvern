//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_hpm_counteren_su
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: hpmcounter3..10 / hpmcounterh3..10 from S and U under
//              mcounteren x scounteren combinations
//   Priv §3.1.11 / §12.1.4: S reads need mcounteren[N]; U reads need
//   mcounteren[N] and scounteren[N]; otherwise illegal instruction.
//   Implemented counters (N < 3+ZIHPM_NR) return their frozen preload,
//   unprovided ones read 0 (spec_compliance_notes.md). The enable bits of
//   implemented counters must read back as written; for unprovided counters
//   the docs do not say whether the enable bit is writable, so the expected
//   outcome is derived from the read-back enable.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)
`define MEM(byte_off)   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(byte_off)]

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] mcen_wr [0:4];
reg [31:0] scen_wr [0:4];
reg [31:0] mcen_rb, scen_rb, got, expv;
integer    p, m, n, hi, nerr, nchk, ntrap_exp;
reg        impl, allowed;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      mcen_wr[0] = 32'h000; scen_wr[0] = 32'h000;
      mcen_wr[1] = 32'h000; scen_wr[1] = 32'h7F8;
      mcen_wr[2] = 32'h7F8; scen_wr[2] = 32'h000;
      mcen_wr[3] = 32'h7F8; scen_wr[3] = 32'h7F8;
      mcen_wr[4] = 32'h2A8; scen_wr[4] = 32'h198;

      wait(probes_cpu.x31 == 32'h11111111);
      $display("HPM counteren matrix: init done (ZIHPM_NR=%0d) %t ns", ZIHPM_NR, $time);

      wait(probes_cpu.x31 == 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|   hpmcounter[h]3..10 from S/U under mcounteren x scounteren        |");
      $display(" ====================================================================");

      nerr      = 0;
      nchk      = 0;
      ntrap_exp = 0;
      for (p = 0; p < 5; p = p + 1)
         begin
            mcen_rb = `MEM(32'h100 + p*16);
            scen_rb = `MEM(32'h100 + p*16 + 4);
            for (n = 3; n <= 10; n = n + 1)
               if (n < 3 + ZIHPM_NR) begin
                  nchk = nchk + 2;
                  if (mcen_rb[n] !== mcen_wr[p][n]) begin
                     $display("ERROR: phase %0d mcounteren[%0d] read back %b, written %b", p, n, mcen_rb[n], mcen_wr[p][n]);
                     nerr = nerr + 1;
                  end
                  if (scen_rb[n] !== scen_wr[p][n]) begin
                     $display("ERROR: phase %0d scounteren[%0d] read back %b, written %b", p, n, scen_rb[n], scen_wr[p][n]);
                     nerr = nerr + 1;
                  end
               end
            for (m = 0; m < 2; m = m + 1)
               for (hi = 0; hi < 2; hi = hi + 1)
                  for (n = 3; n <= 10; n = n + 1)
                     begin
                        impl    = (n < 3 + ZIHPM_NR);
                        allowed = (m == 0) ? mcen_rb[n] : (mcen_rb[n] & scen_rb[n]);
                        if (!allowed)
                           expv = 32'hBADC0DE0;
                        else if (!impl)
                           expv = 32'h0;
                        else
                           expv = hi ? (32'hB1C00000 | n) : (32'hC0DE0000 | n);
                        if (!allowed) ntrap_exp = ntrap_exp + 1;
                        got  = `MEM(32'h200 + (2*p + m)*64 + hi*32 + (n-3)*4);
                        nchk = nchk + 1;
                        if (got !== expv) begin
                           $display("ERROR: phase %0d %s-mode hpmcounter%0d %s: read 0x%h, expected 0x%h (mcen=%b scen=%b)",
                                    p, m ? "U" : "S", n, hi ? "high" : "low ", got, expv, mcen_rb[n], scen_rb[n]);
                           nerr = nerr + 1;
                        end
                     end
         end

      if (`MEM(32'h00) !== ntrap_exp) begin
         $display("ERROR: %0d illegal-instruction traps, expected %0d", `MEM(32'h00), ntrap_exp);
         nerr = nerr + 1;
      end
      if (`MEM(32'h04) !== 32'h0) begin
         $display("ERROR: %0d unexpected (non cause-2) traps", `MEM(32'h04));
         nerr = nerr + 1;
      end

      if (nerr == 0)
         $display("PASS:  %0d HPM enable/shadow checks, %0d expected traps %t ns", nchk, ntrap_exp, $time);
      else begin
         $display("ERROR: %0d HPM enable/shadow mismatches %t ns", nerr, $time);
         error = error + nerr;
      end

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

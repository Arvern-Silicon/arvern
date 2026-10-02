//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_platform_deleg_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: every irq_platform_i line, delegated to S vs not delegated
//   traps_and_interrupts.md §4/§5 and Priv §3.1.8 ("Delegated interrupts
//   result in the interrupt being masked at the delegator privilege level").
//   16 lines x 5 scenarios (S/U delegated, S/U not delegated, delegated while
//   in M with MIE=1): handler, cause 0x80000010+N, previous privilege, one
//   trap per pulse, mideleg[16+N] writable.
//   The bench side is a generic responder: x31 = 0x6000_0s0N pulses line N.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] base;
reg [31:0] req;
reg [31:0] exp_id, exp_pp, exp_deleg;
integer    scen, line, idx;
reg        responder_done;

// Pulse responder: any x31 = 0x60xxxxxx pulses irq_platform_i[x31[3:0]]
initial
   begin
      responder_done = 1'b0;
      @(posedge hresetn);
      while (!responder_done)
         begin
            wait((probes_cpu.x31[31:24] == 8'h60) || (probes_cpu.x31 == 32'hdeadbeef));
            if (probes_cpu.x31 == 32'hdeadbeef)
               responder_done = 1'b1;
            else begin
               req = probes_cpu.x31;
               repeat(2) @(posedge free_clk);
               irq_platform[req[3:0]] = 1'b1;
               repeat(3) @(posedge free_clk);
               irq_platform[req[3:0]] = 1'b0;
               wait(probes_cpu.x31 != req);
            end
         end
   end

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      wait(probes_cpu.x31 == 32'h11111111);
      $display("platform IRQ delegation walk: init done %t ns", $time);

      wait(probes_cpu.x31 == 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|   irq_platform_i[N] x {S/U delegated, S/U not, masked in M}        |");
      $display(" ====================================================================");

      for (scen = 0; scen < 5; scen = scen + 1)
         for (line = 0; line < 16; line = line + 1)
            begin
               idx  = scen*16 + line;
               base = 32'h100 + idx*32;
               case (scen)
                  0: begin exp_id = 2; exp_pp = 1; end
                  1: begin exp_id = 2; exp_pp = 0; end
                  2: begin exp_id = 1; exp_pp = 1; end
                  3: begin exp_id = 1; exp_pp = 0; end
                  default: begin exp_id = 2; exp_pp = 1; end
               endcase
               exp_deleg = ((scen == 2) || (scen == 3)) ? 32'h0 : (32'h1 << (16 + line));
               $display("");
               $display("--- scenario %0d, line %0d ---", scen, line);
               check_mem_value(`SPAD(base + 0),  exp_id);
               check_mem_value(`SPAD(base + 4),  32'h80000010 + line);
               check_mem_value(`SPAD(base + 8),  exp_pp);
               if (scen == 4) begin
                  check_mem_value(`SPAD(base + 12), 32'h00000000);   // not taken while in M
                  check_mem_value(`SPAD(base + 16), 32'h00000001);   // still pending in M
               end
               check_mem_value(`SPAD(base + 20), 32'h00000001);
               check_mem_value(`SPAD(base + 24), exp_deleg);
            end

      $display("");
      $display("--- no unexpected trap ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

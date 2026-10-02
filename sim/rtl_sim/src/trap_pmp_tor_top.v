//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_tor_top
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP regions at the top of the 32-bit address space
//   pmpaddr read-back drops bits 33:32; a TOR entry cannot cover the word at
//   0xFFFFFFFC, a NAPOT entry can. "Allowed by PMP" is observed as the
//   data-bus-error RNMI (the region is unmapped), "denied" as a synchronous
//   mcause 5/7 with no bus access. Round layout in trap_pmp_tor_top.s.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;
integer rid, rbase, rop, rexp;
reg [31:0] raddr, rval, racc;

`define PMPTOP_MEM(byte_off) ahb_bus_system_inst.sram_x_inst.mem[(byte_off)/4]

// rexp: 0 = allowed by PMP -> RNMI, 5/7 = PMP fault, 1 = allowed and mapped (loads NX word)
// rop : 0 = lw, 1 = lbu, 2 = sw
task pmptop_round_cfg;
   input integer id;
   begin
      case (id)
         0: begin raddr = 32'hFFFFFF00; rop = 0; rexp = 0; end
         1: begin raddr = 32'hFFFFFFF8; rop = 0; rexp = 0; end
         2: begin raddr = 32'hFFFFFFFB; rop = 1; rexp = 0; end
         3: begin raddr = 32'hFFFFFFFC; rop = 0; rexp = 5; end
         4: begin raddr = 32'hFFFFFFFF; rop = 1; rexp = 5; end
         5: begin raddr = 32'hFFFFFFFC; rop = 2; rexp = 7; end
         6: begin raddr = 32'hFFFFFFF8; rop = 2; rexp = 0; end
         7: begin raddr = 32'hFFFFFEFC; rop = 0; rexp = 5; end
         8: begin raddr = 32'hFFFFFFFC; rop = 0; rexp = 0; end
         9: begin raddr = 32'hFFFFFFFF; rop = 1; rexp = 0; end
        10: begin raddr = 32'hFFFFFFFC; rop = 2; rexp = 0; end
        11: begin raddr = 32'hFFFFFEFC; rop = 0; rexp = 5; end
        12: begin raddr = 32'hFFFFFFFC; rop = 0; rexp = 0; end
        13: begin raddr = 32'h81000000; rop = 0; rexp = 1; end
        14: begin raddr = 32'hFFFFFFFC; rop = 2; rexp = 7; end
        15: begin raddr = 32'hFFFFFFFC; rop = 0; rexp = 0; end
        default: begin raddr = 32'h81000000; rop = 0; rexp = 1; end
      endcase
   end
endtask

task pmptop_chk;
   input [31:0]  actual;
   input [31:0]  expected;
   input [511:0] what;
   begin
      if (actual !== expected) begin
         $display("ERROR: round %0d %0s -- read: 0x%h / expected: 0x%h", rid, what, actual, expected);
         error = error + 1;
      end else begin
         $display("PASS:  round %0d %0s = 0x%h", rid, what, actual);
      end
   end
endtask

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|          PMP TOR / NAPOT AT THE TOP OF THE ADDRESS SPACE            |");
      $display(" ====================================================================");

      wait (probes_cpu.x31 === 32'h11111111);
      wait (probes_cpu.x31 === 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      rid = -1;
      $display("--- pmpaddr / pmpcfg read-back (pmpaddr[31:30] = address bits 33:32 read 0) ---");
      pmptop_chk(`PMPTOP_MEM(32'h80), 32'h3FFFFFFF, "pmpaddr2 after writing 0xFFFFFFFF (A)");
      pmptop_chk(`PMPTOP_MEM(32'h84), 32'h3FFFFFC0, "pmpaddr1");
      pmptop_chk(`PMPTOP_MEM(32'h88), 32'h3FFFFFDF, "pmpaddr2 (B)");
      pmptop_chk(`PMPTOP_MEM(32'h8C), 32'h3FFFFFFF, "pmpaddr2 after writing 0xFFFFFFFF (C)");
      pmptop_chk(`PMPTOP_MEM(32'h98), 32'h1FFFFFFF, "pmpaddr2 (D)");
      pmptop_chk(`PMPTOP_MEM(32'h90), 32'h000B001D, "pmpcfg0 (A)");
      pmptop_chk(`PMPTOP_MEM(32'h94), 32'h0019001D, "pmpcfg0 (C)");

      for (rid = 0; rid < 17; rid = rid + 1)
        begin
           pmptop_round_cfg(rid);
           rbase = 32'h100 + rid*64;
           racc  = `PMPTOP_MEM(rbase + 48);
           $display("--- round %0d: %0s 0x%h, expect %0s ---", rid,
                    (rop == 0) ? "lw" : (rop == 1) ? "lbu" : "sw", raddr,
                    (rexp == 0) ? "allowed by PMP -> bus error RNMI" :
                    (rexp == 1) ? "allowed, load completes" : "PMP access fault");
           if (racc == 32'h0) begin
              $display("ERROR: round %0d access PC slot is empty -- the round did not run", rid);
              error = error + 1;
           end
           pmptop_chk(`PMPTOP_MEM(rbase + 44), 32'h1, "ecall count (round completed in U)");

           if (rexp == 5 || rexp == 7) begin
              if (rid == 3)
                 $display("       (TOR top = 0x3FFFFFFF<<2 is exclusive: 0xFFFFFFFC must NOT match -> fault, no RNMI)");
              pmptop_chk(`PMPTOP_MEM(rbase +  0), 32'h1,   "trap count");
              pmptop_chk(`PMPTOP_MEM(rbase +  4), rexp,    "mcause");
              pmptop_chk(`PMPTOP_MEM(rbase +  8), raddr,   "mtval");
              pmptop_chk(`PMPTOP_MEM(rbase + 12), racc,    "mepc (= the access)");
              pmptop_chk(`PMPTOP_MEM(rbase + 16), 32'h0,   "RNMI count (denied access never reaches the bus)");
           end else begin
              pmptop_chk(`PMPTOP_MEM(rbase +  0), 32'h0,   "trap count (no PMP fault)");
           end

           if (rexp == 0) begin
              pmptop_chk(`PMPTOP_MEM(rbase + 16), 32'h1,        "RNMI count");
              pmptop_chk(`PMPTOP_MEM(rbase + 20), 32'h80000003, "mncause");
              pmptop_chk(`PMPTOP_MEM(rbase + 24), raddr,        "marv_eaddr");
              pmptop_chk(`PMPTOP_MEM(rbase + 28), racc,         "marv_epc (= the access)");
              rval = `PMPTOP_MEM(rbase + 32) & 32'h7;
              pmptop_chk(rval, (rop == 2) ? 32'h3 : 32'h1,      "marv_estat[2:0] {overrun,store,valid}");
              pmptop_chk(`PMPTOP_MEM(rbase + 36), 32'h0,        "mnstatus.MNPP at RNMI entry (U)");
           end

           if (rexp == 1) begin
              pmptop_chk(`PMPTOP_MEM(rbase + 16), 32'h0,        "RNMI count");
              pmptop_chk(`PMPTOP_MEM(rbase + 40), 32'h13579BDF, "loaded value");
           end else begin
              pmptop_chk(`PMPTOP_MEM(rbase + 40), 32'hBAD30000 + rid, "load rd unchanged (failed or no load)");
           end
        end

      rid = -1;
      $display("--- totals ---");
      pmptop_chk(`PMPTOP_MEM(32'h40), 32'd9, "total RNMIs");
      pmptop_chk(`PMPTOP_MEM(32'h44), 32'd6, "total PMP faults");

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_ccsr_bank_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: every custom-CSR bank and offset, from M, S and U
//   integration_guide.md §7: 11 banks; privilege from csr[9:8], read-only
//   when csr[11:10]=11; a failing access raises illegal instruction. The
//   model below replays the firmware's access sequence against the bench's
//   arv_custom_csr instance (U RW 0x800/0x801, S RW 0x5C0/0x5C1, M RW
//   0x7C0-0x7C7, RO 0xCC0/0xDC0/0xFC0/0xFC1, everything else reads 0) and
//   checks every old / read-back / re-read value and the trap count.
//----------------------------------------------------------------------------

`define VERY_LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)
`define MEM(byte_off)   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(byte_off)]

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

localparam [31:0] CCSR_MARK = 32'hDEADC0DE;
localparam [31:0] USR_RO    = 32'h0CC0A001;
localparam [31:0] SUP_RO    = 32'h0DC0A002;
localparam [31:0] MAC_RO0   = 32'h0FC0A003;
localparam [31:0] MAC_RO1   = 32'h0FC1A004;

reg [31:0] ccsr_model [0:4095];
reg [11:0] bank_base  [0:10];
integer    bank_cnt   [0:10];
reg [11:0] addr;
reg [31:0] pat, e_old, e_rb, e_rr, got_old, got_rb, got_rr, rec;
integer    npass, pass, prv, tag, b, o, idx, nerr, nchk, ntrap;
reg        allow_r, allow_w, impl_rw;

// Read-only CCSR sources: constants for the whole test
initial
   begin
      ccsr_usr_ro_0 = USR_RO;
      ccsr_sup_ro_0 = SUP_RO;
      ccsr_mac_ro_0 = MAC_RO0;
      ccsr_mac_ro_1 = MAC_RO1;
   end

function [31:0] ro_value;
   input [11:0] a;
   begin
      case (a)
         12'hCC0: ro_value = USR_RO;
         12'hDC0: ro_value = SUP_RO;
         12'hFC0: ro_value = MAC_RO0;
         12'hFC1: ro_value = MAC_RO1;
         default: ro_value = 32'h0;
      endcase
   end
endfunction

function is_impl_rw;
   input [11:0] a;
   begin
      is_impl_rw = (a == 12'h800) || (a == 12'h801) ||
                   (a == 12'h5C0) || (a == 12'h5C1) ||
                   ((a >= 12'h7C0) && (a <= 12'h7C7));
   end
endfunction

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      bank_base[0]  = 12'h800; bank_cnt[0]  = 64;
      bank_base[1]  = 12'h840; bank_cnt[1]  = 64;
      bank_base[2]  = 12'h880; bank_cnt[2]  = 64;
      bank_base[3]  = 12'h8C0; bank_cnt[3]  = 64;
      bank_base[4]  = 12'hCC0; bank_cnt[4]  = 64;
      bank_base[5]  = 12'h5C0; bank_cnt[5]  = 64;
      bank_base[6]  = 12'h9C0; bank_cnt[6]  = 64;
      bank_base[7]  = 12'hDC0; bank_cnt[7]  = 64;
      bank_base[8]  = 12'h7C0; bank_cnt[8]  = 61;
      bank_base[9]  = 12'hBC0; bank_cnt[9]  = 64;
      bank_base[10] = 12'hFC0; bank_cnt[10] = 60;
      for (ii = 0; ii < 4096; ii = ii + 1)
         ccsr_model[ii] = 32'h0;

      wait(probes_cpu.x31 == 32'h11111111);
      $display("CCSR bank walk: init done %t ns", $time);
      wait(probes_cpu.x31 == 32'h22222222);
      $display("CCSR bank walk: M pass done %t ns", $time);

      wait(probes_cpu.x31 == 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|   custom-CSR banks x offsets x {M, S, U}: access rules and data    |");
      $display(" ====================================================================");

      npass = (SU_MODE_EN != 0) ? 3 : 1;
      nerr  = 0;
      nchk  = 0;
      ntrap = 0;
      for (pass = 0; pass < npass; pass = pass + 1)
         begin
            prv = (pass == 0) ? 3 : (pass == 1) ? 1 : 0;
            tag = prv;
            // W pass (write + read-back), then R pass (re-read)
            idx = 0;
            for (b = 0; b < 11; b = b + 1)
               for (o = 0; o < bank_cnt[b]; o = o + 1)
                  begin
                     addr    = bank_base[b] + o;
                     allow_r = (prv >= addr[9:8]);
                     allow_w = allow_r && (addr[11:10] != 2'b11);
                     impl_rw = is_impl_rw(addr);
                     pat     = 32'hA5000000 | (tag << 16) | addr;
                     e_old   = !allow_w ? CCSR_MARK : impl_rw ? ccsr_model[addr] : ro_value(addr);
                     if (allow_w && impl_rw)
                        ccsr_model[addr] = pat;
                     e_rb    = !allow_r ? CCSR_MARK : impl_rw ? ccsr_model[addr] : ro_value(addr);
                     if (!allow_w) ntrap = ntrap + 1;
                     if (!allow_r) ntrap = ntrap + 2;
                     rec     = 32'h1000 + pass*32'h3000 + idx*16;
                     got_old = `MEM(rec + 0);
                     got_rb  = `MEM(rec + 4);
                     nchk    = nchk + 2;
                     if (got_old !== e_old) begin
                        $display("ERROR: prv %0d csr 0x%h csrrw old 0x%h, expected 0x%h", prv, addr, got_old, e_old);
                        nerr = nerr + 1;
                     end
                     if (got_rb !== e_rb) begin
                        $display("ERROR: prv %0d csr 0x%h read-back 0x%h, expected 0x%h", prv, addr, got_rb, e_rb);
                        nerr = nerr + 1;
                     end
                     idx = idx + 1;
                  end
            idx = 0;
            for (b = 0; b < 11; b = b + 1)
               for (o = 0; o < bank_cnt[b]; o = o + 1)
                  begin
                     addr    = bank_base[b] + o;
                     allow_r = (prv >= addr[9:8]);
                     impl_rw = is_impl_rw(addr);
                     e_rr    = !allow_r ? CCSR_MARK : impl_rw ? ccsr_model[addr] : ro_value(addr);
                     rec     = 32'h1000 + pass*32'h3000 + idx*16;
                     got_rr  = `MEM(rec + 8);
                     nchk    = nchk + 1;
                     if (got_rr !== e_rr) begin
                        $display("ERROR: prv %0d csr 0x%h re-read 0x%h, expected 0x%h", prv, addr, got_rr, e_rr);
                        nerr = nerr + 1;
                     end
                     idx = idx + 1;
                  end
         end

      if (`MEM(32'h00) !== ntrap) begin
         $display("ERROR: %0d illegal-instruction traps, expected %0d", `MEM(32'h00), ntrap);
         nerr = nerr + 1;
      end
      if (`MEM(32'h04) !== 32'h0) begin
         $display("ERROR: %0d unexpected (non cause-2) traps", `MEM(32'h04));
         nerr = nerr + 1;
      end

      if (nerr == 0)
         $display("PASS:  %0d CCSR accesses checked, %0d illegal-instruction traps %t ns", nchk, ntrap, $time);
      else begin
         $display("ERROR: %0d CCSR mismatches %t ns", nerr, $time);
         error = error + nerr;
      end

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

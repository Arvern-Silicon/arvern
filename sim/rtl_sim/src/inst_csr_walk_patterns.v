//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_walk_patterns
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: walking-ones / walking-zeros through every writable
//              address-holding CSR, read back against its WARL rule
//   mtvec/stvec: written & ~0x2 (MODE 2/3 store 0/1); mepc/sepc/mnepc:
//   IALIGN mask (~0x1 with C, ~0x3 without); mtval/stval/m/s/mnscratch: full
//   width; jvt: ~0x3F (BASE[31:6]). S CSRs only at SU_MODE_EN=1, jvt only at
//   C_EXTENSION>=4. No trap may occur.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)
`define MEM(byte_off)   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(byte_off)]

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] mask_of [0:10];
reg        en_of   [0:10];
reg [31:0] wval, expv, got;
integer    k, i, z, nerr, nchk;
reg [31:0] ialign_mask;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      ialign_mask = (C_EXTENSION > 0) ? 32'hFFFFFFFE : 32'hFFFFFFFC;
      mask_of[0]  = 32'hFFFFFFFD;  en_of[0]  = 1'b1;              // mtvec
      mask_of[1]  = 32'hFFFFFFFD;  en_of[1]  = (SU_MODE_EN != 0);  // stvec
      mask_of[2]  = ialign_mask;   en_of[2]  = 1'b1;              // mepc
      mask_of[3]  = ialign_mask;   en_of[3]  = (SU_MODE_EN != 0);  // sepc
      mask_of[4]  = ialign_mask;   en_of[4]  = 1'b1;              // mnepc
      mask_of[5]  = 32'hFFFFFFFF;  en_of[5]  = 1'b1;              // mtval
      mask_of[6]  = 32'hFFFFFFFF;  en_of[6]  = (SU_MODE_EN != 0);  // stval
      mask_of[7]  = 32'hFFFFFFFF;  en_of[7]  = 1'b1;              // mscratch
      mask_of[8]  = 32'hFFFFFFFF;  en_of[8]  = (SU_MODE_EN != 0);  // sscratch
      mask_of[9]  = 32'hFFFFFFFF;  en_of[9]  = 1'b1;              // mnscratch
      mask_of[10] = 32'hFFFFFFC0;  en_of[10] = (C_EXTENSION >= 4); // jvt

      wait(probes_cpu.x31 == 32'h11111111);
      $display("CSR walking patterns: init done %t ns", $time);

      wait(probes_cpu.x31 == 32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|   walking ones / zeros through address-holding CSRs (WARL masks)   |");
      $display(" ====================================================================");

      nerr = 0;
      nchk = 0;
      for (k = 0; k < 11; k = k + 1)
         if (en_of[k])
            for (z = 0; z < 2; z = z + 1)
               for (i = 0; i < 32; i = i + 1)
                  begin
                     wval = z ? ~(32'h1 << i) : (32'h1 << i);
                     expv = wval & mask_of[k];
                     got  = `MEM(32'h400 + k*256 + z*128 + i*4);
                     nchk = nchk + 1;
                     if (got !== expv) begin
                        $display("ERROR: CSR #%0d wrote 0x%h, read 0x%h, expected 0x%h", k, wval, got, expv);
                        nerr = nerr + 1;
                     end
                  end

      if (`MEM(32'h00) !== 32'h0) begin
         $display("ERROR: %0d unexpected traps", `MEM(32'h00));
         nerr = nerr + 1;
      end

      if (nerr == 0)
         $display("PASS:  %0d CSR walking-pattern read-backs %t ns", nchk, $time);
      else begin
         $display("ERROR: %0d CSR walking-pattern mismatches %t ns", nerr, $time);
         error = error + nerr;
      end

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

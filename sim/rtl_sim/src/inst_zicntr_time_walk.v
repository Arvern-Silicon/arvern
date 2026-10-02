//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_time_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MTIME walking-ones write, read back through time/timeh and MMIO
//
//   Priv 3.1.11: time/timeh are read-only shadows of the memory-mapped mtime.
//   For each k = 0..63 the firmware writes MTIME = 1<<k, fences, and reads it
//   back through the CSRs and over MMIO. MTIME keeps counting, so each value
//   must lie in [1<<k, (1<<k) + MTIME_DRIFT_MAX], and the MMIO read (issued
//   after the CSR read) must not be below the CSR value.
//
//   Step k = 64 writes MTIME back to 0 after the bit-63 step: timeh must read
//   0 again and the value lie in [0, MTIME_DRIFT_MAX].
//
//   MTIME_DRIFT_MAX is the bound inst_zicntr_aclint_mtime_write uses; the
//   documentation gives no write-to-read latency bound for the ACLINT.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

localparam [63:0] MTIME_DRIFT_MAX = 64'd10000;

reg [63:0] t_exp;
reg [63:0] t_csr;
reg [63:0] t_mmio;
integer    t_err;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      use_aclint = 1'b1;   // time CSR port served by the ACLINT

      $display("");
      $display(" ====================================================================");
      $display("|        MTIME WALKING ONES -- time/timeh AND MMIO READ-BACK         |");
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);

      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(40) @(posedge free_clk);

      for (kk = 0; kk < 65; kk = kk + 1) begin
         t_exp  = (kk == 64) ? 64'd0 : (64'd1 << kk);
         t_csr  = {ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + kk*16 + 4)],
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + kk*16 + 0)]};
         t_mmio = {ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + kk*16 + 12)],
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + kk*16 + 8)]};
         t_err  = 0;
         if (t_csr < t_exp || (t_csr - t_exp) > MTIME_DRIFT_MAX) begin
            $display("ERROR: k=%0d time/timeh = 0x%h, wrote 0x%h", kk, t_csr, t_exp);
            t_err = 1;
         end
         if (t_mmio < t_exp || (t_mmio - t_exp) > MTIME_DRIFT_MAX) begin
            $display("ERROR: k=%0d MMIO MTIME = 0x%h, wrote 0x%h", kk, t_mmio, t_exp);
            t_err = 1;
         end
         if (t_mmio < t_csr) begin
            $display("ERROR: k=%0d MMIO MTIME 0x%h read after time 0x%h is smaller", kk, t_mmio, t_csr);
            t_err = 1;
         end
         if (t_err)
            error = error + 1;
         else
            $display("PASS:  k=%0d wrote 0x%h  time 0x%h (+%0d)  MMIO 0x%h (+%0d)",
                     kk, t_exp, t_csr, t_csr - t_exp, t_mmio, t_mmio - t_exp);
      end

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

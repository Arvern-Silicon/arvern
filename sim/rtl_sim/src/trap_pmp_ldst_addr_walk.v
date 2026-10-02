//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_ldst_addr_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP load/store address walk over the whole 32-bit space
//
//   Locked entries allow only ROM read/execute and SRAM_X / SRAM_NX data; an
//   LW and an SW to each of 60 walking-ones / walking-zeros addresses must trap
//   with mcause 5 / 7 and mtval = the address, except 0x80000000 (SRAM_X, both
//   allowed) and the load of 0x20000000 (ROM, read-only).
//
//   doc/software_guide.md 12: "a load or store denied by PMP produces no bus
//   transfer at all" -- while the walk runs, a monitor flags any data-bus
//   transfer outside SRAM_X and the single allowed ROM read at 0x20000000.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define LONG_TIMEOUT
`define SPAD(byte_off)  ((byte_off)/4)

reg     walk_active;
integer bus_leaks;

initial begin
   walk_active = 1'b0;
   bus_leaks   = 0;
end

always @(posedge free_clk)
   if (walk_active && data_htrans[1] &&
       ((data_haddr < 32'h80000000) || (data_haddr >= 32'h80010000)) &&
       !((data_haddr == 32'h20000000) && !data_hwrite)) begin
      bus_leaks = bus_leaks + 1;
      $display("ERROR: data-bus transfer to 0x%h during the PMP walk (%s) %t ns",
               data_haddr, data_hwrite ? "write" : "read", $time);
   end

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;            // PMP faults are the stimulus

      $display("");
      $display(" ====================================================================");
      $display("|        PMP LOAD/STORE ADDRESS WALK (whole 32-bit space)            |");
      $display(" ====================================================================");

      wait(probes_cpu.x31==32'h11111111);
      walk_active = 1'b1;

      $display("--- PMP configuration read-back ---");
      check_cpu_reg(16, 32'h989B9B9D);   // a6: pmpcfg0
      check_cpu_reg(17, 32'h3FFFFFFF);   // a7: pmpaddr3 (bits [31:30] read 0)

      wait(probes_cpu.x31==32'h22222222);
      walk_active = 1'b0;
      repeat(40) @(posedge free_clk);

      $display("--- Walk results ---");
      check_cpu_reg(21, 32'd120);        // s5: checks performed
      check_cpu_reg(22, 32'd0);          // s6: failures
      check_cpu_reg(23, 32'd0);          // s7: first failure code
      check_cpu_reg(24, 32'd0);          // s8: RNMIs (an access reached an unmapped slave)
      check_cpu_reg(26, 32'd0);          // s10: unexpected trap causes
      check_cpu_reg(27, 32'd0);          // s11: mtval mismatches
      check_cpu_reg(13, 32'd58);         // a3: load access faults
      check_cpu_reg(14, 32'd59);         // a4: store access faults
      check_mem_value(`SPAD(32'h0), 32'h5EED001F);   // the one allowed store landed

      if (bus_leaks != 0) begin
         $display("ERROR: %0d denied accesses reached the data bus", bus_leaks);
         error = error + 1;
      end else
         $display("PASS:  no denied access reached the data bus during the walk");

      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

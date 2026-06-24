//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_aclint_time
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Zicntr time CSR routed through the ACLINT
//   With use_aclint=1, the core's time_req_o / time_gnt_i / time_val_i
//   side-band is wired to ahb_aclint instead of the legacy TB mtime
//   model. Two `csrr time` reads with a delay between must be non-zero
//   and strictly increasing.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

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
      use_aclint         = 1'b1;


      //=================================================================
      // PHASE 1: first time read taken
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|        PHASE 1: FIRST time CSR READ VIA ACLINT Zicntr PORT         |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : show_t0
         reg [31:0] lo;
         reg [31:0] hi;
         lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         hi = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
         $display("First  csrr time -> 0x%h_%h", hi, lo);
         if ({hi, lo} == 64'h0) begin
            $display("ERROR: time CSR returned 0 on first read %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  first time read is non-zero %t ns", $time);
         end
      end


      //=================================================================
      // PHASE 2: second time read -- must be strictly greater
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|         PHASE 2: SECOND time CSR READ, MUST BE STRICTLY >          |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      begin : show_t1
         reg [31:0] t0_lo, t0_hi;
         reg [31:0] t1_lo, t1_hi;
         reg [63:0] t0, t1;
         t0_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
         t0_hi = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
         t1_lo = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         t1_hi = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         t0    = {t0_hi, t0_lo};
         t1    = {t1_hi, t1_lo};
         $display("Second csrr time -> 0x%h_%h", t1_hi, t1_lo);
         if (t1 > t0) begin
            $display("PASS:  time advanced (0x%h_%h > 0x%h_%h) %t ns",
                     t1_hi, t1_lo, t0_hi, t0_lo, $time);
         end else begin
            $display("ERROR: time did NOT advance (0x%h_%h <= 0x%h_%h) %t ns",
                     t1_hi, t1_lo, t0_hi, t0_lo, $time);
            error = error + 1;
         end
      end

      stimulus_done = 1;
   end

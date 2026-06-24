//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_mpp_forced_m
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SU_MODE PRIV - mstatus.MPP hardwired to M under SU_MODE_EN=0
//   Verify mstatus.MPP[12:11] is hardwired to 2'b11. Reads after csrrc
//   (clear MPP), csrrw MPP=00, and csrrw MPP=01 must all still report 11.
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

      // No trap expected; trap_count is the authoritative no-trap check.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: MPP at reset = 11
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 2: MPP AT RESET = 11                                   |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- mstatus.MPP at reset (expect 11) ---");
      begin : check_mpp_reset
         reg [31:0] ms_val;
         ms_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         if (ms_val[12:11] !== 2'b11) begin
            $display("ERROR: MPP expected 11 -- mstatus=0x%h MPP=%b %t ns",
                     ms_val, ms_val[12:11], $time);
            error = error + 1;
         end else begin
            $display("PASS:  MPP = 11 (M) -- mstatus=0x%h %t ns", ms_val, $time);
         end
      end


      //=================================================================
      // PHASE 3: csrrc 0x1800 cannot clear MPP
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 3: csrrc 0x1800 -> MPP still 11                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- mstatus.MPP after csrrc 0x1800 (expect 11) ---");
      begin : check_mpp_csrrc
         reg [31:0] ms_val;
         ms_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)];
         if (ms_val[12:11] !== 2'b11) begin
            $display("ERROR: MPP expected 11 -- mstatus=0x%h MPP=%b %t ns",
                     ms_val, ms_val[12:11], $time);
            error = error + 1;
         end else begin
            $display("PASS:  MPP = 11 (M) -- mstatus=0x%h %t ns", ms_val, $time);
         end
      end


      //=================================================================
      // PHASE 4: csrrw MPP=00 -> still 11
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 4: csrrw MPP=00 -> MPP still 11                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h44444444);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- mstatus.MPP after csrrw MPP=00 (expect 11) ---");
      begin : check_mpp_w00
         reg [31:0] ms_val;
         ms_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];
         if (ms_val[12:11] !== 2'b11) begin
            $display("ERROR: MPP expected 11 -- mstatus=0x%h MPP=%b %t ns",
                     ms_val, ms_val[12:11], $time);
            error = error + 1;
         end else begin
            $display("PASS:  MPP = 11 (M) -- mstatus=0x%h %t ns", ms_val, $time);
         end
      end


      //=================================================================
      // PHASE 5: csrrw MPP=01 -> still 11
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 5: csrrw MPP=01 -> MPP still 11                        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- mstatus.MPP after csrrw MPP=01 (expect 11) ---");
      begin : check_mpp_w01
         reg [31:0] ms_val;
         ms_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)];
         if (ms_val[12:11] !== 2'b11) begin
            $display("ERROR: MPP expected 11 -- mstatus=0x%h MPP=%b %t ns",
                     ms_val, ms_val[12:11], $time);
            error = error + 1;
         end else begin
            $display("PASS:  MPP = 11 (M) -- mstatus=0x%h %t ns", ms_val, $time);
         end
      end


      //=================================================================
      // FINAL: trap_count must still be 0
      //=================================================================
      $display("");
      $display("--- trap_count = 0 (no MPP write trapped) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

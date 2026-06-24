//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_kill_muldiv
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI LOW-LATENCY KILL OF MULDIV/UOP
//   Asserts that an NMI fired while a long DIV is in flight aborts the DIV
//   (MNEPC points inside the DIV loop) even when irqkill_cfg.muldiv=0.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

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


      //=================================================================
      // PHASE 1: init complete -> latch NMI vector from scratchpad
      //=================================================================
      $display("");
      $display(" PHASE 1: configure nmi_vector");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler addr is 0 -- firmware did not publish it %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_handler addr published: 0x%h %t ns", handler_addr, $time);
         end
         nmi_vector = handler_addr;
      end

      check_mem_value(`SPAD(32'h00), 32'h00000000);   // nmi_count==0


      //=================================================================
      // PHASE 2: enter divide loop, fire NMI mid-divide
      //=================================================================
      $display("");
      $display(" PHASE 2: divide-loop, fire NMI mid-divide");
      $display("Waiting for the firmware marker (0xD0D0D0D0)...");

      @(probes_cpu.x31==32'hD0D0D0D0);

      // Wait until the DIV is actually in flight and killable, otherwise
      // slow timing variants (gahb/rsalu) may see NMI fire on a NOP before
      // the divide reaches EX. ex_alu_is_killable_o is the same signal
      // the RTL gates the kill on, so by definition this is the precise
      // window the fix must cover.
      @(posedge dut.ex_alu_is_killable);

      // Assert NMI for a few cycles. NMI is level-sensitive and one-shot
      // (mnstatus.NMIE clears on entry).
      nmi = 1'b1;
      repeat(4) @(posedge free_clk);
      nmi = 1'b0;

      $display("NMI asserted and deasserted %t ns", $time);


      //=================================================================
      // PHASE 3: verify MNEPC landed inside the DIV region
      //=================================================================
      $display("");
      $display(" PHASE 3: verify NMI killed the DIV (MNEPC in div_loop)");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);   // NMI taken exactly once

      begin : check_mnepc_is_div
         reg [31:0] mnepc_val;
         reg [31:0] kill_pc;
         reg [31:0] drain_pc;
         mnepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
         kill_pc   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
         drain_pc  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];

         $display("MNEPC=0x%h  kill_pc=0x%h  drain_pc=0x%h %t ns",
                  mnepc_val, kill_pc, drain_pc, $time);

         if (mnepc_val === kill_pc) begin
            $display("PASS:  MNEPC == div_pc -- NMI killed the multi-cycle DIV %t ns", $time);
         end else if (mnepc_val === drain_pc) begin
            $display("ERROR: MNEPC == post_div_pc -- NMI WAITED for the DIV to drain (kill did not fire) %t ns", $time);
            error = error + 1;
         end else begin
            $display("ERROR: MNEPC 0x%h matches neither kill_pc nor drain_pc -- test setup issue %t ns",
                     mnepc_val, $time);
            error = error + 1;
         end
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

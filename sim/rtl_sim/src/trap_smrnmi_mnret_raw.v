//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_smrnmi_mnret_raw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MNRET RAW HAZARD ON MNEPC
//   Pulses NMI once after the firmware enters the spin loop. The NMI handler
//   writes mnepc=mnret_new_target and immediately issues mnret (back-to-back)
//   -- the exact RAW window the fix closes.
//
//   Discriminator (probes_cpu.x31):
//   - 0xdeadbeef -> mnret read the NEW mnepc value (fix in place, PASS).
//   - 0xC0DEC0DE -> mnret read the OLD mnepc, resumed in spin loop (BUG).
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


      //=================================================================
      // PHASE 1: init complete -> latch nmi_vector from scratchpad
      //=================================================================
      $display("");
      $display(" PHASE 1: configure nmi_vector");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler addr is 0 %t ns", $time);
            error = error + 1;
         end
         nmi_vector = handler_addr;
      end


      //=================================================================
      // PHASE 2: firmware in spin loop -> pulse NMI
      //=================================================================
      $display("");
      $display(" PHASE 2: pulse NMI while firmware spins");
      // x31 was set to 0xC0DEC0DE right before the spin loop; level-sensitive
      // wait may already see the marker.
      wait(probes_cpu.x31==32'hC0DEC0DE);
      repeat(5) @(posedge free_clk);

      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;


      //=================================================================
      // PHASE 3: bounded wait for mnret resume; check x31 discriminator
      //
      // Post-fix: mnret reads NEW mnepc, jumps to mnret_new_target, sets
      // x31=0xdeadbeef within ~10 cycles.
      // Pre-fix: mnret reads STALE mnepc, resumes in spin loop. x31 stays
      // 0xC0DEC0DE forever.
      //
      // 500 cycles is generous for the post-fix path.
      //=================================================================
      $display("");
      $display(" PHASE 3: verify mnret resume point");
      repeat(500) @(posedge free_clk);

      if (probes_cpu.x31 === 32'hdeadbeef) begin
         $display("PASS:  mnret resumed at NEW mnepc -- MNRET RAW fix in place %t ns", $time);
      end else if (probes_cpu.x31 === 32'hC0DEC0DE) begin
         $display("ERROR: mnret resumed at STALE mnepc -- still in spin loop, x31=0xC0DEC0DE (MNRET RAW BUG REPRODUCED) %t ns", $time);
         error = error + 1;
      end else begin
         $display("ERROR: unexpected x31=0x%h -- mnret resumed at neither target %t ns", probes_cpu.x31, $time);
         error = error + 1;
      end


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

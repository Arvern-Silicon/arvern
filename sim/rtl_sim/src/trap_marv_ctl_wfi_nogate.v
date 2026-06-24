//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_marv_ctl_wfi_nogate
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: marv_ctl[4] (wfi_clkgate_dis) disables WFI clock-gating.
//
//   With marv_ctl[4]=1, the core must NOT gate its clock during WFI sleep
//   (dut_hclk_en stays 1), yet WFI must still stall and then wake on an
//   enabled interrupt. The firmware sets marv_ctl[4] + mie.MTIE (MIE=0) and
//   WFIs; this TB checks the clock stays on during the stall, then asserts
//   irq_m_timer to wake the core and confirms it resumes past WFI.
//----------------------------------------------------------------------------

`define VERY_LONG_TIMEOUT

`define SPAD(byte_off)  (byte_off/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

integer wait_cnt;
reg     woke;
reg     bad_trap;

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

      $display("");
      $display(" ====================================================================");
      $display("|     marv_ctl[4] = disable WFI clock-gating (stall, never gate)     |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware to set marv_ctl[4] and enter WFI...");

      @(probes_cpu.x31==32'h21212121);

      // Confirm marv_ctl[4] latched.
      repeat(5) @(posedge free_clk);
      $display("");
      $display("--- marv_ctl[4] armed check ---");
      begin : check_armed
         reg [31:0] mctl_val;
         mctl_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)];
         if (mctl_val[4] !== 1'b1) begin
            $display("ERROR: marv_ctl[4] not set after write -- marv_ctl=0x%h %t ns", mctl_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  marv_ctl[4] set -- marv_ctl=0x%h %t ns", mctl_val, $time);
         end
      end

      // Let the bus drain; with gating disabled the clock must remain ON.
      repeat(200) @(posedge free_clk);

      $display("");
      $display("--- WFI sleep with clock-gating disabled ---");
      if (dut_hclk_en !== 1'b1) begin
         $display("ERROR: dut_hclk_en=%b during WFI -- clock gated despite marv_ctl[4]=1 %t ns",
                  dut_hclk_en, $time);
         error = error + 1;
      end else begin
         $display("PASS:  dut_hclk_en=1 during WFI (clock-gating disabled by marv_ctl[4]) %t ns", $time);
      end

      // WFI must still wake: assert the machine-timer IRQ pin.
      irq_m_timer = 1'b1;

      woke     = 1'b0;
      bad_trap = 1'b0;
      begin : wfi_wait
         for (wait_cnt = 0; wait_cnt < 10000; wait_cnt = wait_cnt + 1) begin
            @(posedge free_clk);
            if ((probes_cpu.x31 == 32'h22222222) || (probes_cpu.x31 == 32'hdeadbeef)) begin
               woke = 1'b1;
               disable wfi_wait;
            end
            if (probes_cpu.x31 == 32'hbadbad00) begin
               bad_trap = 1'b1;
               disable wfi_wait;
            end
         end
      end

      $display("");
      $display("--- Result ---");
      if (woke) begin
         $display("PASS:  WFI still woke (stall-and-wake) with clock-gating disabled %t ns", $time);
         check_mem_value(`SPAD(32'h00), 32'hCAFEBABE);
      end else if (bad_trap) begin
         $display("ERROR: unexpected trap during MIE=0 WFI (x31=0xbadbad00) %t ns", $time);
         error = error + 1;
      end else begin
         $display("ERROR: WFI did not wake within 10000 cycles (x31 stuck) %t ns", $time);
         error = error + 1;
      end

      irq_m_timer = 1'b0;
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

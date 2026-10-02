//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_kill_zcmp_sweep
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IRQ KILL SWEEP -- an interrupt swept across every micro-op of a
//   13-register cm.push / cm.pop / cm.popret. Firmware checks the architectural
//   result of each of the 96 rounds; the testbench counts the UOP kills: some
//   in pass A (kill enabled), none in pass B (marv_ctl[1]=0).
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)
`define VERY_LONG_TIMEOUT      // 96 rounds of 13-register sequences under random wait states

integer kills_a, kills_b;
reg     pass_b;
reg     uop_en_q;
integer armed_id;
integer countdown;

initial begin
    kills_a   = 0;
    kills_b   = 0;
    pass_b    = 1'b0;
    uop_en_q  = 1'b0;
    armed_id  = -1;
    countdown = -1;
end

// Raise the M software IRQ N = id%16 cycles after the round's sequence starts
// (first start only -- a restarted sequence does not re-arm); drop it when taken.
always @(posedge `ARV_CPU_INST.hclk_i) begin
   uop_en_q <= `ARV_CPU_INST.ex_uop_control[9];
   if (`ARV_CPU_INST.ex_uop_control[9] & ~uop_en_q & (probes_cpu.x12 != armed_id) & (probes_cpu.x31 !== 32'hdeadbeef)) begin
      armed_id  <= probes_cpu.x12;
      countdown <= probes_cpu.x12 % 16;
   end else if (countdown == 0) begin
      irq_m_software <= 1'b1;
      countdown      <= -1;
   end else if (countdown > 0)
      countdown <= countdown - 1;
   if (`ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_taken &
       `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq)
      irq_m_software <= 1'b0;
end

always @(posedge `ARV_CPU_INST.hclk_i)
   if (`ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_kill_uop_o &
       `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_taken) begin
      if (pass_b) kills_b = kills_b + 1;
      else        kills_a = kills_a + 1;
      $display("       kill in round %0d %t ns", probes_cpu.x12, $time);
   end

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  IRQ KILL SWEEP: 13-register push/pop/popret  |");
    $display(" ===============================================");

    @(probes_cpu.x31 == 32'h22222222);
    pass_b = 1'b1;

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    $display("rounds=%0d failures=%0d first failing round=%0d  kills: pass A=%0d pass B=%0d",
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)],
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)],
             $signed(ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)]),
             kills_a, kills_b);
    check_mem_value(`SPAD(32'h18), 32'd96);
    check_mem_value(`SPAD(32'h14), 32'd0);
    if (kills_a == 0) begin
       $display("ERROR: no UOP sequence was killed with marv_ctl[1]=1 %t ns", $time);
       error = error + 1;
    end
    if (kills_b != 0) begin
       $display("ERROR: %0d UOP kills with marv_ctl[1]=0 %t ns", kills_b, $time);
       error = error + 1;
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

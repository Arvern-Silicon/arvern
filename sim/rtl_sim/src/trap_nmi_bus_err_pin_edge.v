//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_bus_err_pin_edge
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: RNMI PIN EDGE -- the nmi_i pin rises k = 0..11 cycles after the
//   data-bus error pulse (k = 0: the cycle right after it): exactly one bus-error RNMI and one pin RNMI per round.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer id;
integer countdown;

initial countdown = -1;

always @(posedge `ARV_CPU_INST.hclk_i) begin
   if (`ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.wb_bus_error_store_i & (probes_cpu.x12 < 32'd12)) begin
      if (probes_cpu.x12 == 32'd0) nmi <= 1'b1;             // same edge as the error pulse
      else                         countdown <= probes_cpu.x12 - 1;
   end else if (countdown == 0) begin
      nmi       <= 1'b1;
      countdown <= -1;
   end else if (countdown > 0)
      countdown <= countdown - 1;
   if (probes_cpu.x15 == 32'd1)
      nmi <= 1'b0;
end

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  RNMI PIN EDGE vs DATA-BUS ERROR              |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    for (id = 0; id < 12; id = id + 1) begin
       $display("round %0d (pin at +%0d): bus RNMIs=%0d pin RNMIs=%0d", id, id,
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*8)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h104 + id*8)]);
       check_mem_value(`SPAD(32'h100 + id*8), 32'd1);
       check_mem_value(`SPAD(32'h104 + id*8), 32'd1);
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

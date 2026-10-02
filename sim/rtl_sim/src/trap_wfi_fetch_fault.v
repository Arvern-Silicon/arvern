//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_wfi_fetch_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: WFI FETCH FAULT - WFI right before a fetch-denied word, woken by
//   an interrupt 200 cycles later: one interrupt, one instruction access fault
//   (mepc = &D), no hang.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

always @(posedge `ARV_CPU_INST.hclk_i)
   if (`ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_taken &
       `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq)
      irq_m_software <= 1'b0;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  WFI before an unfetchable word               |");
    $display(" ===============================================");
    repeat(200) @(posedge free_clk);
    irq_m_software = 1'b1;

    wait (probes_cpu.x31 === 32'hdeadbeef);
    repeat(40) @(posedge free_clk);

    $display("irq=%0d fault=%0d fault mepc=0x%h (&D=0x%h)",
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)],
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)],
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)],
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)]);
    check_mem_value(`SPAD(32'h00), 32'd1);
    check_mem_value(`SPAD(32'h04), 32'd1);
    check_mem_value(`SPAD(32'h08), ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)]);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_prefetch_open
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP PREFETCH OPEN - a pmpcfg write granting X to the next
//   instruction's region applies to the instruction already prefetched.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  PMP PREFETCH OPEN: csrw pmpcfg0 grants X     |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    $display("trap count=%0d mcause=%0d mepc=0x%h s3=%0d",
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)],
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)],
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)],
             probes_cpu.x19);
    check_mem_value(`SPAD(32'h0C), 32'h00000000);
    check_cpu_reg(19, 32'h00000008);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

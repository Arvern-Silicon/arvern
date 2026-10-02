//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_zcmp_popret_fault_target
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: POPRET BAD TARGET + IRQ -- an interrupt pending while cm.popret
//   returns to an unfetchable address: one IRQ, one cause-1 fault (mepc 0), no hang.
//
//   Results at 0x80000100 + id*16: w0 irq, w1 fault, w2 fault mepc, w3 other (0x100 = fell through).
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer id;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;
    use_aclint = 1'b1;        // route the ACLINT MSIP line to the core

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  POPRET BAD TARGET + IRQ                      |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    for (id = 0; id < 8; id = id + 1) begin
       $display("round %0d: irq=%0d fault=%0d fault_mepc=0x%h other=%0d", id,
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 0)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 4)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 8)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 12)]);
       check_mem_value(`SPAD(32'h100 + id*16 + 0),  32'd1);
       check_mem_value(`SPAD(32'h100 + id*16 + 4),  32'd1);
       check_mem_value(`SPAD(32'h100 + id*16 + 8),  32'h00000000);
       check_mem_value(`SPAD(32'h100 + id*16 + 12), 32'd0);
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

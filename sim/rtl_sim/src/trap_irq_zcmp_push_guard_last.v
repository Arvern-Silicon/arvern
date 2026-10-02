//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_zcmp_push_guard_last
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PUSH/POP GUARD ON THE LAST ACCESS + IRQ -- an interrupt swept across every
//              micro-op of cm.push/cm.pop {ra, s0-s1} whose last access faults: one IRQ, one
//              access fault (mepc=&macro-op, mtval=GUARD+12), sp unchanged.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

localparam [31:0] GUARD = 32'h80003000;

integer id;
reg [31:0] push_pc;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;
    use_aclint = 1'b1;        // route the ACLINT MSIP line to the core

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  PUSH/POP GUARD ON THE LAST ACCESS + IRQ     |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    for (id = 0; id < 24; id = id + 1) begin
       push_pc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 24)];
       $display("round %0d: irq=%0d fault=%0d mepc=0x%h (push 0x%h) mtval=0x%h other=%0d sp=0x%h", id,
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 0)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 4)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 8)],
                push_pc,
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 12)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 16)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 20)]);
       check_mem_value(`SPAD(32'h100 + id*32 + 0),  32'd1);
       check_mem_value(`SPAD(32'h100 + id*32 + 4),  32'd1);
       check_mem_value(`SPAD(32'h100 + id*32 + 8),  push_pc);
       check_mem_value(`SPAD(32'h100 + id*32 + 12), GUARD + 32'd12);
       check_mem_value(`SPAD(32'h100 + id*32 + 16), 32'd0);
       check_mem_value(`SPAD(32'h100 + id*32 + 20), (id < 12) ? GUARD + 32'd24 : GUARD + 32'd8);
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

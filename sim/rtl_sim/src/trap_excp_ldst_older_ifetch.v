//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ldst_older_ifetch
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: OLDER LDST vs IFETCH -- a late-resolving misaligned load/store
//   right before a fetch-denied region: the older exception is reported
//   (cause 4/6, mepc = the access), exactly once, never cause 1.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer id;
reg [31:0] acc_pc;
reg [31:0] cause_exp;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  OLDER LDST FAULT vs YOUNGER IFETCH FAULT     |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    for (id = 0; id < 3; id = id + 1) begin
       acc_pc    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h200 + id*4)];
       cause_exp = (id == 1) ? 32'd6 : 32'd4;
       $display("round %0d: mcause=%0d mepc=0x%h (access 0x%h) mtval=0x%h traps=%0d", id,
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 0)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 4)],
                acc_pc,
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 8)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 12)]);
       check_mem_value(`SPAD(32'h100 + id*16 + 0),  cause_exp);
       check_mem_value(`SPAD(32'h100 + id*16 + 4),  acc_pc);
       check_mem_value(`SPAD(32'h100 + id*16 + 8),  32'h80000101);
       check_mem_value(`SPAD(32'h100 + id*16 + 12), 32'd1);
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_kill_zcmp_bus_err
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: IRQ held for a Zcmp kill while the push's own store bus-errors: the push is
//              never lost -- every round it finally executes once at SP0 (see the .s).
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

localparam [31:0] SP0 = 32'h80002000;

integer id;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;
    use_aclint = 1'b1;        // route the ACLINT MSIP line to the core

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  ZCMP KILL + OWN BUS ERROR                     |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    for (id = 0; id < 12; id = id + 1) begin
       $display("round %0d: irq=%0d nmi=%0d other=%0d sp=0x%h stack=%h %h %h %h", id,
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 0)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 4)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 8)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 12)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 16)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 20)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 24)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*32 + 28)]);
       check_mem_value(`SPAD(32'h100 + id*32 + 0),  32'd1);                    // one IRQ
       check_mem_value(`SPAD(32'h100 + id*32 + 8),  32'd0);                    // no sync trap
       check_mem_value(`SPAD(32'h100 + id*32 + 12), SP0 - 32'd16);             // push executed
       check_mem_value(`SPAD(32'h100 + id*32 + 16), 32'h52000000 + id);        // s2
       check_mem_value(`SPAD(32'h100 + id*32 + 20), 32'h51000000 + id);        // s1
       check_mem_value(`SPAD(32'h100 + id*32 + 24), 32'h50000000 + id);        // s0
       check_mem_value(`SPAD(32'h100 + id*32 + 28), 32'h1A000000 + id);        // ra
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

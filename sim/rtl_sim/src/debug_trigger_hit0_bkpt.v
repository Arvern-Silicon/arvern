//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_hit0_bkpt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG TRIGGERS - mcontrol6.hit0 is set by action=0 (breakpoint
//   exception) fires too, for an execute and a load trigger.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

reg [31:0] v;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  TRIGGERS: hit0 on action=0 breakpoints      |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    repeat(40) @(posedge free_clk);

    v = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
    $display("tdata1 armed (before the fire) = 0x%h", v);
    if (v[22] !== 1'b0) begin
       $display("ERROR: hit0 already set before the fire %t ns", $time);
       error = error + 1;
    end
    v = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
    $display("execute breakpoint: tdata1 = 0x%h, mcause = %0d", v, ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)]);
    check_mem_value(`SPAD(32'h04), 32'd3);
    if (v[22] !== 1'b1) begin
       $display("ERROR: hit0 not set by an action=0 execute fire %t ns", $time);
       error = error + 1;
    end
    v = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
    $display("load breakpoint:    tdata1 = 0x%h, mcause = %0d", v, ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)]);
    check_mem_value(`SPAD(32'h0C), 32'd3);
    if (v[22] !== 1'b1) begin
       $display("ERROR: hit0 not set by an action=0 load fire %t ns", $time);
       error = error + 1;
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

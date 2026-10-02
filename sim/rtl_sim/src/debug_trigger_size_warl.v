//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_size_warl
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG TRIGGERS - mcontrol6.size reads 0 for execute-only triggers
//   (not honoured by the execute match), 1..3 once load or store is set.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  TRIGGERS: mcontrol6.size WARL               |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    repeat(40) @(posedge free_clk);

    check_mem_value(`SPAD(32'h00), 32'd0);
    check_mem_value(`SPAD(32'h04), 32'd0);
    check_mem_value(`SPAD(32'h08), 32'd2);
    check_mem_value(`SPAD(32'h0C), 32'd3);
    check_mem_value(`SPAD(32'h10), 32'd1);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

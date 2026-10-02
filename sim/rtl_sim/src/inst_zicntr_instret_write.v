//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_instret_write
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR - minstret counts every instruction after a CSR write to
//   it (the write takes effect once the writing instruction has completed).
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  ZICNTR: minstret after a CSR write           |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    check_mem_value(`SPAD(32'h00), 32'h00001000);
    check_mem_value(`SPAD(32'h04), 32'h00001001);
    check_mem_value(`SPAD(32'h08), 32'h00001002);
    check_mem_value(`SPAD(32'h0C), 32'h00001003);
    check_mem_value(`SPAD(32'h10), 32'h00000000);
    check_mem_value(`SPAD(32'h14), 32'h00000006);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

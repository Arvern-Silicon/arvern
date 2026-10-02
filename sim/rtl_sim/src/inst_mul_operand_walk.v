//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_mul_operand_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MUL/MULH/MULHSU/MULHU operand walk -- see
//              inst_mul_operand_walk.s. The firmware compares all four
//              results of 441 operand pairs with a precomputed table; the
//              bench checks the compare count and the verdict.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31==32'h11111111);

    @(probes_cpu.x31==32'hdeadbeef);
    random_irq_enable = 0;
    check_cpu_reg(20, 32'd1764);        // s4: compares executed (441 x 4)
    check_cpu_reg(18, 32'd0);           // s2: mismatches
    check_cpu_reg(19, 32'd0);           // s3: first failing code
    check_cpu_reg(21, 32'd0);           // s5: its value

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

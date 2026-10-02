//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_csr_ccsr_select
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ccsr_reg_sel_o is zero whenever ccsr_bank_o is zero
//
//   Sampled mid-cycle on every clock of the test (random IRQ handlers
//   included): a non-zero select without a bank is a phantom access for a
//   peripheral that qualifies transactions on |ccsr_reg_sel_o.
//----------------------------------------------------------------------------

integer sel_without_bank;
integer ccsr_accesses;

initial begin
    sel_without_bank = 0;
    ccsr_accesses    = 0;
end

always @(negedge free_clk)
    if (hresetn === 1'b1) begin
        if ((ccsr_bank == 11'h000) && (ccsr_reg_sel != 64'h0)) sel_without_bank = sel_without_bank + 1;
        if ((ccsr_bank != 11'h000) && (ccsr_reg_sel != 64'h0)) ccsr_accesses    = ccsr_accesses    + 1;
    end

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31==32'hdeadbeef);
    random_irq_enable = 0;

    check_cpu_reg(10, 32'h13572468);
    check_cpu_reg(11, 32'h0F0F0F0F);
    check_cpu_reg(12, 32'h00C0FFEE);
    check_cpu_reg(13, 32'h5F5F0F0F);

    if (sel_without_bank != 0) begin
        $display("ERROR: ccsr_reg_sel_o non-zero with ccsr_bank_o zero on %0d cycle(s)", sel_without_bank);
        error = error + 1;
    end
    if (ccsr_accesses < 7) begin
        $display("ERROR: only %0d custom-CSR access cycle(s) seen, expected at least 7", ccsr_accesses);
        error = error + 1;
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

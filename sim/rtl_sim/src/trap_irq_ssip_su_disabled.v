//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_ssip_su_disabled
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SU_MODE_EN=0 gating of irq_s_software_i. The TB asserts the
//              HW input and holds it; firmware spins and reports the trap
//              count + MIP[1]. Both must be 0 (the HW contribution is
//              masked by `& SU_MODE_EN` inside arv_csr_traps.v).
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31 == 32'hFFFFFFFF);

    /* ----- Phase 1: assert HW SSIP under SU_MODE_EN=0 ----- */
    @(probes_cpu.x31 == 32'h10101010);
    @(posedge free_clk);
    @(posedge free_clk);
    irq_s_software = 1'b1;

    @(probes_cpu.x31 == 32'h11111111);
    irq_s_software = 1'b0;
    check_cpu_reg(10, 32'h00000000);   // a0 = trap count = 0 (no trap fired)
    check_cpu_reg(11, 32'h00000000);   // a1 = MIP[1] = 0 (HW gated by SU_MODE_EN)

    /* ----- End ----- */
    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

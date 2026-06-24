//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_mideleg_routing
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: mideleg per-cause IRQ routing
//   Spec reference: RISC-V Privileged §3.1.6.1, §3.1.8, §12.1.3
//
//   mideleg[i]=1 -> cause i routes to S-mode
//   mideleg[i]=0 -> cause i routes to M-mode
//   mideleg has no bits for MSI=3 / MTI=7 / MEI=11 (M-class always to M)
//
//   Exercises each affected line of the IRQ priority vector in arv_csr_traps:
//   Phase 1: mideleg.SSI=0 + assert SSIP -> trap cause 1 (M-mode)
//   Phase 2: mideleg.STI=0 + assert STIP -> trap cause 5 (M-mode)
//   Phase 3: mideleg.SSI=1 + assert MSI (HW pin) -> trap cause 3 (M-mode)
//   (verifies MSI is NOT cross-masked by an unrelated mideleg bit)
//   Phase 4: mideleg.STI=1 + assert MTI (HW pin) -> trap cause 7 (M-mode)
//   (verifies MTI is NOT cross-masked by an unrelated mideleg bit)
//
//   Synchronisation invariants:
//   - MIE stays 1 throughout the test; mie.{XIE} bit is set/unset per phase
//   so only one IRQ source is enabled at a time.
//   - Each phase spins until the handler's count-store releases it (the
//   count store is sequenced AFTER the cause store, so when count changes
//   cause is guaranteed to already be visible -- release-acquire pair).
//   - The handler either clears the mip pending bit (SSI, STI) or masks
//   the source in mie (MSI, MTI -- HW-driven, not software-clearable);
//   so the IRQ doesn't immediately re-fire after MRET.
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

    /* ----- Phase 1: SSI to M-mode (mideleg.SSI=0) ----- */
    @(probes_cpu.x31 == 32'h11111111);
    check_cpu_reg(7,  32'h00000001);   // delta = 1
    check_cpu_reg(28, 32'h00000001);   // mcause = SSI (1)

    /* ----- Phase 2: STI to M-mode (mideleg.STI=0) ----- */
    @(probes_cpu.x31 == 32'h22222222);
    check_cpu_reg(7,  32'h00000001);
    check_cpu_reg(28, 32'h00000005);   // mcause = STI (5)

    /* ----- Phase 3: MSI delivers when mideleg.SSI=1 ----- */
    @(probes_cpu.x31 == 32'h30303030);
    /* Two clocks for the asm to enter its spin loop, then assert MSI pin */
    @(posedge free_clk);
    @(posedge free_clk);
    irq_m_software = 1'b1;

    @(probes_cpu.x31 == 32'h33333333);
    irq_m_software = 1'b0;
    check_cpu_reg(7,  32'h00000001);
    check_cpu_reg(28, 32'h00000003);   // mcause = MSI (3)

    /* ----- Phase 4: MTI delivers when mideleg.STI=1 ----- */
    @(probes_cpu.x31 == 32'h40404040);
    @(posedge free_clk);
    @(posedge free_clk);
    irq_m_timer = 1'b1;

    @(probes_cpu.x31 == 32'h44444444);
    irq_m_timer = 1'b0;
    check_cpu_reg(7,  32'h00000001);
    check_cpu_reg(28, 32'h00000007);   // mcause = MTI (7)

    /* ----- End ----- */
    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_load_rd_x0
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: LOAD with rd=x0 MUST still raise its exception.
//   Per RISC-V Unpriv ISA: using x0 as the destination of a load does NOT
//   suppress address-translation/access-check side-effects. An exception
//   that would normally fire MUST still fire.
//
//   If the LSU gated exception emission on rd!=0, then `lw x0, 0(rs1)` would
//   become a side-effect-free address-probe primitive. This test proves no
//   such gate exists by:
//   Phase A: lw x0, 0(x11) where x11 = unmapped addr -> cause 5 (LAF)
//   Phase B: lw x0, 0(x11) where x11 = misaligned    -> cause 4 (LAM)
//   The trap handler counts each entry. We then check the counters match the
//   number of faulting loads issued.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    /* This test deliberately triggers load-access-faults and load-address-misaligned.
       Tell the monitor not to flag them as test errors. */
    error_on_exception = 0;

    @(probes_cpu.x31 == 32'hFFFFFFFF);

    /* ----- Phase A: lw x0, 0(unmapped) must trap (cause 5) ----- */
    @(probes_cpu.x31 == 32'h11111111);
    check_cpu_reg(10, 32'h00000001);   // LAF counter must be 1

    /* ----- Phase B: lw x0, 0(misaligned) must trap (cause 4) ----- */
    @(probes_cpu.x31 == 32'h22222222);
    check_cpu_reg( 9, 32'h00000001);   // LAM counter must be 1

    /* ----- Phase C: control, lw x13, 0(unmapped) -> LAF counter must reach 2 ----- */
    @(probes_cpu.x31 == 32'h33333333);
    check_cpu_reg(10, 32'h00000002);   // LAF counter must now be 2

    /* ----- End ----- */
    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

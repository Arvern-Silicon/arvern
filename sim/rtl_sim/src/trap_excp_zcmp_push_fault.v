//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_zcmp_push_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: cm.push with first store hitting an unmapped address
//   Probes whether a Zcmp pushpop UOP sequence can leak a trailing AHB
//   transfer (next register's store) after the first store takes an
//   access fault. If the per-cycle aph_ongoing gates close cleanly, no
//   trailing transfer should reach the slave; the only observable AHB store
//   is the (faulting) first one.
//
//   Test method:
//   - Pre-init a counter at 0x80000020 = 0xC0FFEE00 sentinel.
//   - Point sp to an UNMAPPED address (0xA0000000) so the first store
//   attempt faults.
//   - Pre-init two SRAM addresses that the *trailing* push would target
//   (one offset higher than sp, but in mapped SRAM at 0x80000040/0x44)
//   with sentinels.
//   - Execute `cm.push {ra,s0-s2}, -16` (rlist=6: ra,s0,s1,s2; stack_adj=16)
//   with sp pointing into the unmapped region.
//   - Trap handler skips the cm.push.
//   - After return, check that none of the SRAM sentinel addresses were
//   touched (i.e., no trailing-store leak).
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    /* The cm.push deliberately faults; tell the exception monitor not to    */
    /* flag the access fault as a test error.                                */
    error_on_exception = 0;

    @(probes_cpu.x31 == 32'hFFFFFFFF);

    @(probes_cpu.x31 == 32'h11111111);
    check_cpu_reg(10, 32'hC0FFEE00);  // CANARY_A unchanged

    @(probes_cpu.x31 == 32'h22222222);
    check_cpu_reg(10, 32'hC0FFEE01);  // CANARY_B unchanged

    @(probes_cpu.x31 == 32'h33333333);
    check_cpu_reg(10, 32'hC0FFEE02);  // CANARY_C unchanged

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

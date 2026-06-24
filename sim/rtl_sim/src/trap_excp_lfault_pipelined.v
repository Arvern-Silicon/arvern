//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_lfault_pipelined
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: pipelined next-transfer leak past a load access fault.
//   When T1 = load to a fault-triggering address is followed immediately by
//   T2 = load or store with ≥1 AHB wait state, T2's address phase is issued
//   on the bus BEFORE the trap-kill signal stops it.
//
//   Two leak vectors:
//   Vector A (T2 = load): T2's loaded value writes to the destination
//   register post-trap (regfile clobbered).
//   Vector B (T2 = store): T2's store reaches the slave and writes memory
//   (slave-visible side-effect).
//
//   Test method per vector:
//   - Pre-initialise the destination (x10 / scratch memory) with SENTINEL.
//   - Sequence T1 then T2 with no instruction between.
//   - Trap handler skips BOTH T1 and T2 (advances mepc by 8) so that if no
//   leak occurs, T2 has no observable effect.
//   - Check the destination: SENTINEL = no leak; T2-value = LEAK (the bug).
//
//   The leak is timing-dependent: it requires at least one wait state on T1's
//   data phase so T2's address phase has time to be issued before kill takes
//   effect. The base variant may not expose it; -rwsram and friends will.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    /* This test deliberately triggers load-access-faults; tell the monitor
       not to flag them as test errors. */
    error_on_exception = 0;

    @(probes_cpu.x31 == 32'hFFFFFFFF);

    /* ----- Phase A: load-after-fault leak (regfile) ----- */
    @(probes_cpu.x31 == 32'h11111111);
    check_cpu_reg(10, 32'h12345678);   // SENTINEL_A (no leak); buggy -> 0xCAFEBABE

    /* ----- Phase B: store-after-fault leak (memory) ----- */
    @(probes_cpu.x31 == 32'h22222222);
    check_cpu_reg(10, 32'h55555555);   // SENTINEL_B (no leak); buggy -> 0xDEADBEEF

    /* ----- End ----- */
    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

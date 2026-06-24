//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_m_b2b_test
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: back-to-back muldiv patterns
//   Exercises four back-to-back patterns through the shared MUL/DIV unit:
//   Phase 1: MUL → DIV → REM   (DIV-after-MUL is the suspect pattern)
//   Phase 2: MUL → REM         (REM-after-MUL with no DIV between)
//   Phase 3: DIV → DIV         (control — should always work)
//   Phase 4: MUL → MUL         (control — should always work)
//
//   No non-muldiv instructions are scheduled between the back-to-back ops in
//   each phase, so the shared FSM's idle-cycle reset path is NOT exercised —
//   this isolates the inter-op handoff. Sync sentinels in x31 separate the
//   phases for the testbench's per-phase result checks.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31==32'hFFFFFFFF);

    /* ------------------ Phase 1: MUL → DIV → REM ------------------ */
    @(probes_cpu.x31==32'h11111111);
    check_cpu_reg(7,  32'h00000015);  // t2 = 21 (MUL)
    check_cpu_reg(28, 32'h00000002);  // t3 = 2  (DIV)  ← BUG: returns 0
    check_cpu_reg(29, 32'h00000001);  // t4 = 1  (REM)

    /* ------------------ Phase 2: MUL → REM ------------------------ */
    @(probes_cpu.x31==32'h22222222);
    check_cpu_reg(7,  32'h00000034);  // t2 = 52 (MUL)
    check_cpu_reg(28, 32'h00000001);  // t3 = 1  (REM)  ← suspect

    /* ------------------ Phase 3: DIV → DIV (control) -------------- */
    @(probes_cpu.x31==32'h33333333);
    check_cpu_reg(7,  32'h00000014);  // t2 = 20
    check_cpu_reg(28, 32'h0000000F);  // t3 = 15

    /* ------------------ Phase 4: MUL → MUL (control) -------------- */
    @(probes_cpu.x31==32'h44444444);
    check_cpu_reg(7,  32'h0000004D);  // t2 = 77
    check_cpu_reg(28, 32'h000000DD);  // t3 = 221

    /* ------------------ End ---------------------------------------- */
    wait(probes_cpu.x31==32'hdeadbeef);
    random_irq_enable = 0;

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

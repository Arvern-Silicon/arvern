//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_csr_value_walk
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: value walk through every software-writable value CSR -- see
//              trap_csr_value_walk.s. The firmware compares every read-back
//              with its documented mask; the bench checks the compare count
//              (66 per walked CSR, set by the build parameters), zero
//              mismatches, zero traps and the restored vectors.
//----------------------------------------------------------------------------

integer nr_csr;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    nr_csr = 9;                                             // mtvec mepc mtval mscratch mtval2 mnscratch mnepc marv_nmvec marv_ctl
    if (SU_MODE_EN != 0)                   nr_csr = nr_csr + 4;   // stvec sepc stval sscratch
    if (C_EXTENSION >= 4)                  nr_csr = nr_csr + 1;   // jvt
    if ((DEBUG_EN != 0) && (DM_TRIGGER_NR > 0)) nr_csr = nr_csr + 1;   // tdata2
    if (PMP_NR > 0)                        nr_csr = nr_csr + 1;   // pmpaddr0

    @(probes_cpu.x31==32'h11111111);
    check_cpu_reg(24, 32'd0);                               // s8: no trap during init

    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg( 8, 66*nr_csr);                           // s0: compares executed
    check_cpu_reg( 9, 32'd0);                               // s1: mismatches
    check_cpu_reg(18, 32'd0);                               // s2: first failing CSR id
    check_cpu_reg(19, 32'd0);                               // s3: its written value
    check_cpu_reg(20, 32'd0);                               // s4: its read value
    check_cpu_reg(24, 32'd0);                               // s8: traps
    check_cpu_reg( 5, probes_cpu.x22);                      // t0 (mtvec) == s6 (handler)
    check_cpu_reg( 6, probes_cpu.x23);                      // t1 == s7 (marv_nmvec at start)
    check_cpu_reg( 7, probes_cpu.x21);                      // t2 == s5 (marv_ctl at start)

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

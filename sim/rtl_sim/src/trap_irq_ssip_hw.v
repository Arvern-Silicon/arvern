//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_ssip_hw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Drives irq_s_software_i (the new HW SSIP input added alongside
//              the CSR-writable SSIP bit) and checks four properties:
//                Phase 1: mideleg.SSI=0 -> trap to M-mode, mcause=1
//                Phase 2: WFI wake on HW SSIP, trap+resume after wake
//                Phase 3: HW-OR semantics -- csrc mip[1] doesn't drop a still-
//                         asserted HW input; trap re-fires until HW drops
//                Phase 4: mideleg.SSI=1 -> trap to S-mode, scause=1
//              At each phase the TB asserts irq_s_software once the firmware
//              signals "ready" via x31; firmware checkpoints results into the
//              argument registers (a0..a7) for the TB to verify.
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    /* ----- Setup ----- */
    @(probes_cpu.x31 == 32'hFFFFFFFF);

    /* ===================================================================== */
    /* Phase 1: HW SSIP delivered to M-mode (mideleg.SSI=0)                  */
    /* ===================================================================== */
    @(probes_cpu.x31 == 32'h10101010);
    @(posedge free_clk);
    @(posedge free_clk);
    irq_s_software = 1'b1;

    @(probes_cpu.x31 == 32'h11111111);
    irq_s_software = 1'b0;
    check_cpu_reg(10, 32'h00000001);   // a0 = M-mode trap count delta = 1
    check_cpu_reg(11, 32'h00000001);   // a1 = mcause = SSI (1)

    /* ===================================================================== */
    /* Phase 2: WFI wake via irq_s_software_i                                */
    /* The firmware has executed WFI; the live wakeup path                   */
    /* (wfi_wakeup_live_o) must pull the core out and deliver the SSI trap.  */
    /* ===================================================================== */
    @(probes_cpu.x31 == 32'h20202020);
    /* Give the WFI a few cycles to actually go to sleep, then assert the
     * wake source. wfi_wakeup_live_o is the combinational wake path so the
     * core ungates within a couple of cycles of the assertion. */
    repeat(4) @(posedge free_clk);
    irq_s_software = 1'b1;

    @(probes_cpu.x31 == 32'h22222222);
    irq_s_software = 1'b0;
    check_cpu_reg(12, 32'h00000001);   // a2 = WFI-wake trap count delta = 1
    check_cpu_reg(13, 32'h00000001);   // a3 = mcause = SSI (1)

    /* ===================================================================== */
    /* Phase 3: HW-OR asymmetric clear semantics                             */
    /* Hold the HW pin throughout the back-to-back re-fire test; drop on the */
    /* 0x33333333 sync; verify the post-csrc MIP[1] stayed asserted, count   */
    /* incremented twice while HW was held, and zero additional traps fired  */
    /* once HW dropped.                                                     */
    /* ===================================================================== */
    @(probes_cpu.x31 == 32'h30303030);
    @(posedge free_clk);
    @(posedge free_clk);
    irq_s_software = 1'b1;             // hold for the whole phase

    @(probes_cpu.x31 == 32'h33333333);
    irq_s_software = 1'b0;             // drop -- no more traps should arrive
    check_cpu_reg(14, 32'h00000002);   // a4 = Phase-3 trap count (re-fire confirmed)
    check_cpu_reg(15, 32'h00000002);   // a5 = post-csrc MIP & (1<<1) = 2 (HW dominates)

    @(probes_cpu.x31 == 32'h44444444);
    check_cpu_reg(16, 32'h00000000);   // a6 = 0 (no spurious trap after HW drop)

    /* ===================================================================== */
    /* Phase 4: HW SSIP delivered to S-mode (mideleg.SSI=1) -- terminal      */
    /* ===================================================================== */
    @(probes_cpu.x31 == 32'h40404040);
    @(posedge free_clk);
    @(posedge free_clk);
    irq_s_software = 1'b1;

    @(probes_cpu.x31 == 32'h55555555);
    irq_s_software = 1'b0;
    check_cpu_reg(10, 32'h00000001);   // a0 (reused) = S-mode trap count delta = 1
    check_cpu_reg(11, 32'h00000001);   // a1 (reused) = scause = SSI (1)
    check_cpu_reg(17, 32'h00000001);   // a7 = S-mode trap count delta (stable copy)

    /* ----- End ----- */
    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

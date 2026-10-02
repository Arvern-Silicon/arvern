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
//   Phase 5: mideleg.SEI=0 + irq_s_external pin from M -> mcause 0x80000009
//   Phase 6: same from S-mode -> still M, MPP=S, mstatus.SIE untouched
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

`define SPAD(byte_off)  ((byte_off)/4)
`define MEM(byte_off)   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(byte_off)]

// mepc recorded at `val` must lie in [`lo`, `hi`) (both published by the firmware)
task check_range;
    input [31:0] val_off;
    input [31:0] lo_off;
    input [31:0] hi_off;
    begin
        if ((`MEM(val_off) < `MEM(lo_off)) || (`MEM(val_off) >= `MEM(hi_off)) || (`MEM(lo_off) == 32'h0)) begin
            $display("ERROR: mepc 0x%h outside the spin loop [0x%h, 0x%h) %t ns", `MEM(val_off), `MEM(lo_off), `MEM(hi_off), $time);
            error = error + 1;
        end else
            $display("PASS:  mepc 0x%h inside the spin loop [0x%h, 0x%h) %t ns", `MEM(val_off), `MEM(lo_off), `MEM(hi_off), $time);
    end
endtask

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

    /* ----- Phase 5: SEI to M-mode (mideleg.SEI=0), taken from M ----- */
    @(probes_cpu.x31 == 32'h50505050);
    @(posedge free_clk);
    @(posedge free_clk);
    irq_s_external = 1'b1;

    @(probes_cpu.x31 == 32'h55555555);
    irq_s_external = 1'b0;
    check_cpu_reg(7,  32'h00000001);
    check_cpu_reg(28, 32'h00000009);   // mcause = SEI (9)

    /* ----- Phase 6: SEI to M-mode (mideleg.SEI=0), taken from S ----- */
    @(probes_cpu.x31 == 32'h60606060);
    @(posedge free_clk);
    @(posedge free_clk);
    irq_s_external = 1'b1;

    @(probes_cpu.x31 == 32'h66666666);
    irq_s_external = 1'b0;
    check_cpu_reg(7,  32'h00000001);
    check_cpu_reg(28, 32'h00000009);

    /* ----- End ----- */
    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    $display("--- phase 5: mcause = 0x80000009, mepc inside the M-mode spin loop ---");
    check_mem_value(`SPAD(32'h40), 32'h80000009);
    check_range(32'h44, 32'h48, 32'h4C);
    $display("--- phase 6: mcause = 0x80000009, mepc inside the S-mode spin loop ---");
    check_mem_value(`SPAD(32'h50), 32'h80000009);
    check_range(32'h54, 32'h5C, 32'h60);
    if ((`MEM(32'h58) & 32'h00001802) !== 32'h00000802) begin
        $display("ERROR: mstatus in the M handler 0x%h: expected MPP=S (01) and SIE=1 %t ns", `MEM(32'h58), $time);
        error = error + 1;
    end else
        $display("PASS:  mstatus in the M handler: MPP=S, SIE=1 untouched %t ns", $time);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

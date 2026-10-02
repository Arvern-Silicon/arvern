//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_irq_masked
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG HALTREQ vs interrupts (Sdext)
//   Verifies the frozen-hart interrupt-masking contract:
//     (1) An external IRQ raised WHILE the hart is halted does NOT vector — the
//         hart stays in Debug Mode and the handler flag (x20) stays 0.
//     (2) The IRQ is not lost: after resume it is delivered (x20 -> 0xBEEF).
//   A test that checked only (1) would miss an IRQ-drop bug; checking only (2)
//   would miss a spurious-vector-while-halted bug. Both are asserted.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // Reset peripherals
    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG IRQ MASKING: IRQ pending while halted must not vector       |");
    $display(" ====================================================================");

    // Firmware has enabled MEIE+MIE and is spinning, IRQ flag (x20) still 0.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning, ready to halt (x31=0x11111111) %t ns", $time);

    // --- halt (no IRQ pending yet -> clean entry; DMI dmcontrol.haltreq) ---
    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: hart not in Debug Mode after dm_halt %t ns", $time);
        error = error + 1;
    end

    // --- raise an external IRQ WHILE halted ---
    repeat (3) @(posedge free_clk);
    irq_m_external = 1'b1;
    $display("Raised machine external IRQ while halted %t ns", $time);

    // The hart is frozen: it must NOT vector. Hold a window and confirm Debug
    // Mode stays asserted and the handler flag (x20) never changes from 0.
    repeat (150) @(posedge free_clk);
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: hart left Debug Mode (vectored?) while halted with IRQ pending %t ns", $time);
        error = error + 1;
    end
    if (probes_cpu.x20 !== 32'h00000000) begin
        $display("ERROR: IRQ handler ran while halted (x20=%h, expected 0) %t ns",
                 probes_cpu.x20, $time);
        error = error + 1;
    end else begin
        $display("PASS:  IRQ held pending, NOT taken while halted (x20=0) %t ns", $time);
    end

    // --- resume: the pending IRQ must now be delivered (DMI dmcontrol.resumereq) ---
    dm_resume;
    if (dbg_debug_mode !== 1'b0) begin
        $display("ERROR: hart still in Debug Mode after dm_resume %t ns", $time);
        error = error + 1;
    end

    // After resume the pending IRQ fires; handler sets x20 and masks MEIE.
    to = 0;
    while ((probes_cpu.x20 !== 32'h0000BEEF) && (to < 1000)) begin @(posedge free_clk); to = to + 1; end
    if (probes_cpu.x20 !== 32'h0000BEEF) begin
        $display("ERROR: IRQ was LOST across halt/resume (x20=%h, never delivered) %t ns",
                 probes_cpu.x20, $time);
        error = error + 1;
    end else begin
        $display("PASS:  pending IRQ delivered after resume (%0d cyc) %t ns", to, $time);
    end
    irq_m_external = 1'b0;       // drop the line (handler already masked MEIE)

    @(probes_cpu.x31==32'h22222222);
    $display("Firmware past IRQ (x31=0x22222222) %t ns", $time);

    @(probes_cpu.x31==32'hdeadbeef);
    check_cpu_reg(20, 32'h0000BEEF);   // IRQ taken exactly once, after resume
    check_cpu_reg(7,  32'hA5A5A5A5);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

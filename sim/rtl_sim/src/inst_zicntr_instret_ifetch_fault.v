//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_instret_ifetch_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR - minstret across an instruction access fault
//   An instruction that faults at FETCH never retired, so the trap must not
//   un-retire anything: the jump that led there stays counted. Same for an
//   instruction stopped by an Sdtrig execute breakpoint (action=0).
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  ZICNTR: minstret across an instruction fault |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    $display("--- probe 0: csrr + jalr -> fault at 0 (expect 2) ---");
    check_mem_value(`SPAD(32'h00), 32'h00000002);
    $display("--- probe 1: csrr + nop + jalr -> fault at 0 (expect 3) ---");
    check_mem_value(`SPAD(32'h04), 32'h00000003);
    $display("--- probe 2: csrr + jal + jalr -> fault at 0 (expect 3) ---");
    check_mem_value(`SPAD(32'h08), 32'h00000003);
    if ((DEBUG_EN != 0) && (DM_TRIGGER_NR > 0)) begin
       $display("--- probe 3: csrr + nop, execute breakpoint on the next (expect 2) ---");
       check_mem_value(`SPAD(32'h0C), 32'h00000002);
       $display("--- last mcause (expect 3, breakpoint) ---");
       check_mem_value(`SPAD(32'h40), 32'h00000003);
    end else begin
       $display("--- last mcause (expect 1, instruction access fault) ---");
       check_mem_value(`SPAD(32'h40), 32'h00000001);
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

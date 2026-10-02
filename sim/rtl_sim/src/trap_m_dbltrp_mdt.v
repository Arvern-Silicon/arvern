//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_m_dbltrp_mdt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MDT SETCLR - mstatush.MDT hardware set on M-trap, clear on xRET
//   Phase A  handler observes MDT=1 on trap entry
//   Phase B  MDT=0 after the handler's MRET
//   Phase C  SRET from M-mode clears MDT -- sampled white-box, because after
//            the SRET the hart is below M and cannot read mstatush, and
//            re-entering M would set MDT again
//   Phase D  a later trap re-arms MDT (set is not one-shot)
//
//   Scratchpad: 0x00 trap_count, 0x04 MDT in handler (A), 0x08 MDT after MRET,
//               0x10 MDT in handler (later traps)
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)
`define MDT  tb_arvern.dut.arv_csr_top_inst.arv_csr_traps_inst.mstatush_mdt

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;   // the ecalls are the mechanism

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  MDT SETCLR: set on M-trap, cleared by xRET   |");
    $display(" ===============================================");

    //--------------------------------------------------------------
    // Phases A / B
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h22222222);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- MDT must be SET on entry to the M handler ---");
    check_mem_value(`SPAD(32'h04), 32'h00000400);
    $display("--- and CLEARED by the handler's MRET ---");
    check_mem_value(`SPAD(32'h08), 32'h00000000);

    //--------------------------------------------------------------
    // Phase C -- white-box, straddling the SRET
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h33333333);
    repeat(2) @(posedge free_clk);
    $display("");
    $display("--- before SRET: MDT = %0d (must be 1) ---", `MDT);
    if (`MDT !== 1'b1) begin
       $display("ERROR: MDT should be 1 before the SRET %t ns", $time);
       error = error + 1;
    end

    @(probes_cpu.x31 == 32'h34343434);
    repeat(2) @(posedge free_clk);
    $display("--- after SRET from M-mode: MDT = %0d (must be 0) ---", `MDT);
    if (`MDT !== 1'b0) begin
       $display("ERROR: SRET executed in M-mode must clear MDT. This is NOT the");
       $display("       MPRV rule, which only clears when the return drops below M %t ns", $time);
       error = error + 1;
    end

    //--------------------------------------------------------------
    // Phase D
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h44444444);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- a later trap must re-arm MDT (set is not one-shot) ---");
    check_mem_value(`SPAD(32'h10), 32'h00000400);

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

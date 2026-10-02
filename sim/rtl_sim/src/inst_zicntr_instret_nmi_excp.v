//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_zicntr_instret_nmi_excp
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: ZICNTR - a data-bus RNMI latched together with a synchronous
//   fault: the faulting instruction re-executes after mnret and must not stay
//   counted. Each round's delta = csrr + sw + NOPs; one RNMI per round.
//   The testbench reports how many rounds actually co-latched the two.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer colatch;
initial colatch = 0;

always @(posedge `ARV_CPU_INST.hclk_i)
   if (`ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_taken &
       `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_is_nmi &
      (|`ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_stage))
      colatch = colatch + 1;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  ZICNTR: minstret, RNMI + synchronous fault   |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    $display("rounds where the RNMI co-latched with the fault: %0d", colatch);
    check_mem_value(`SPAD(32'h00), 32'd2);
    check_mem_value(`SPAD(32'h04), 32'd3);
    check_mem_value(`SPAD(32'h08), 32'd4);
    check_mem_value(`SPAD(32'h0C), 32'd5);
    check_mem_value(`SPAD(32'h20), 32'd4);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

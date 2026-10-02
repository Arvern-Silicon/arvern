//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_refetch_read
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PMP REFETCH READ - a PMP CSR op that does not write (csrr,
//   csrrs/csrrc with rs1=x0, csrrsi/csrrci with uimm=0) does not discard the
//   prefetch buffer; every writing op does. The testbench counts refetch
//   requests per phase: 0 for the 6 reads, 4 for the writes (csrw, csrrs with
//   a non-x0 rs1 holding 0, csrrwi, csrrc with a non-x0 rs1).
//----------------------------------------------------------------------------

integer refetch_rd, refetch_wr;
initial begin
    refetch_rd = 0;
    refetch_wr = 0;
end

always @(posedge `ARV_CPU_INST.hclk_i)
   if (`ARV_CPU_INST.arv_decode_inst.ex_pmp_refetch_o) begin
      if      (probes_cpu.x31 == 32'h11111111) refetch_rd = refetch_rd + 1;
      else if (probes_cpu.x31 == 32'h22222222) refetch_wr = refetch_wr + 1;
   end

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  PMP REFETCH: writes only                     |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    repeat(20) @(posedge free_clk);

    $display("refetches: reads=%0d (expected 0)  writes=%0d (expected 4)", refetch_rd, refetch_wr);
    if (refetch_rd != 0) begin
       $display("ERROR: a PMP CSR read triggered a refetch %t ns", $time);
       error = error + 1;
    end
    if (refetch_wr != 4) begin
       $display("ERROR: expected 4 refetches for the writing ops %t ns", $time);
       error = error + 1;
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

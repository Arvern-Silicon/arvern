//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_bus_err_lockup
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: BUSERR LOCK - a data-bus error must not escape lockup
//   marv_ctl[3] is SET, so the escape route is ENABLED and only the pin may
//   take it. The bus error is made pending (NMIE=0) BEFORE the lockup forms --
//   with NMIE set it would be delivered long before a lockup could exist, and
//   a locked core issues no accesses of its own, so this is the only ordering
//   in which the two genuinely coexist.
//
//   marv_estat is checked to prove a real error is sitting there: otherwise
//   "lockup stayed asserted" would pass with nothing pending at all.
//
//   Scratchpad: 0 nmi_count, 4 m_trap_count, 8 handler addr
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;   // illegal instructions and the store fault on purpose

    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" ===============================================");
    $display("|  BUSERR LOCK: bus error must not escape lockup |");
    $display(" ===============================================");

    begin : program_vector
       reg [31:0] handler_addr;
       handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
       if (handler_addr == 32'h0) begin
          $display("ERROR: nmi_handler address not published %t ns", $time);
          error = error + 1;
       end else begin
          $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
       end
    end

    @(probes_cpu.x31 == 32'h22222222);

    //--------------------------------------------------------------
    // PHASE 1: the bus error returns while locked -- must NOT escape
    //--------------------------------------------------------------
    wait(lockup === 1'b1);
    $display("");
    $display("--- lockup asserted; the posted store's error lands now ---");

    repeat(200) @(posedge free_clk);

    if (lockup !== 1'b1) begin
       $display("ERROR: lockup deasserted -- a data-bus error escaped lockup. The");
       $display("       escape is pin-only (marv_ctl[3] & nmi_r) precisely so a");
       $display("       locked-up core cannot rescue itself with its own faults %t ns", $time);
       error = error + 1;
    end else begin
       $display("PASS:  still locked after 200 cycles %t ns", $time);
    end
    check_mem_value(`SPAD(32'h00), 32'h00000000);   // NMI handler never ran

    // Prove there IS a pending bus error under the lockup, or the check above
    // is vacuous.
    if (tb_arvern.dut.arv_csr_top_inst.arv_csr_traps_inst.nmi_bus_pending !== 1'b1) begin
       $display("ERROR: no bus error was actually pending under the lockup -- the");
       $display("       check above proved nothing %t ns", $time);
       error = error + 1;
    end else begin
       $display("PASS:  a bus error IS pending under the lockup, and did not lift it %t ns",
                $time);
    end

    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_wfi_bus_error
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: WFI BUSERR - a data-bus error around WFI must not strand the hart
//   The test would TIME OUT if the core slept through the error, so reaching
//   the end-of-test sentinel is itself most of the assertion. The markers make
//   the failure legible rather than a bare timeout.
//
//   Scratchpad: 0 handler_addr, 4 nmi_count, 8 mncause,
//               0xC past-WFI marker
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

    error_on_exception = 0;   // the stores fault on purpose

    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" ===============================================");
    $display("|  WFI BUSERR: bus error must not strand a WFI  |");
    $display(" ===============================================");

    begin : program_vector
       reg [31:0] handler_addr;
       handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
       if (handler_addr == 32'h0) begin
          $display("ERROR: nmi_handler address not published %t ns", $time);
          error = error + 1;
       end else begin
          $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
       end
    end

    @(probes_cpu.x31 == 32'h22222222);
    $display("mnstatus.NMIE armed %t ns", $time);

    @(probes_cpu.x31 == 32'h33333333);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- store posted, WFI immediately after ---");
    check_mem_value(`SPAD(32'h0C), 32'h00000001);   // got past the WFI
    check_mem_value(`SPAD(32'h04), 32'h00000001);   // exactly one RNMI
    check_mem_value(`SPAD(32'h08), 32'h80000003);   // and it was the bus error

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

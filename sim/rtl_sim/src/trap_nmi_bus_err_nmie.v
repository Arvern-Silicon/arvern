//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_bus_err_nmie
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMIE HOLD - a data-bus error with mnstatus.NMIE=0 is held
//   NMIE resets to 0 and is software-set-only, so firmware that faults before
//   arming RNMIs must not lose the error. Captured while masked, delivered
//   once NMIE is set.
//
//   Scratchpad: 0 handler_addr, 4 nmi_count, 8 mncause,
//               0xC marv_estat while masked, 0x10 mtvec trap_count
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

    error_on_exception = 0;   // the store faults on purpose

    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" ===============================================");
    $display("|  NMIE HOLD: bus error masked by NMIE=0        |");
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
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- NMIE=0: nothing delivered, but the error IS captured ---");
    check_mem_value(`SPAD(32'h04), 32'h00000000);   // no RNMI yet
    begin : captured
       reg [31:0] estat;
       estat = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
       $display("marv_estat = 0x%h  valid=%0d store=%0d", estat, estat[0], estat[1]);
       if (estat[0] !== 1'b1) begin
          $display("ERROR: the error was masked AND lost -- marv_estat.valid must be");
          $display("       set even when NMIE=0 blocks delivery %t ns", $time);
          error = error + 1;
       end
       if (estat[1] !== 1'b1) begin
          $display("ERROR: marv_estat.store must be set for a faulting store %t ns", $time);
          error = error + 1;
       end
    end

    @(probes_cpu.x31 == 32'h33333333);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- arming NMIE releases the held error ---");
    check_mem_value(`SPAD(32'h04), 32'h00000001);
    check_mem_value(`SPAD(32'h08), 32'h80000003);

    $display("");
    $display("--- mtvec must NEVER be entered ---");
    check_mem_value(`SPAD(32'h10), 32'h00000000);

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_marv_ecapture_abut
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MARV ECAPABUT -- restartable across ABUTTING uop sequences
//   cm.push retires with its last store still posted; register-only cm.mva01s
//   sequences follow with no gap, so ex_uop_enable never falls. restartable
//   must still read 0 -- the sequence that ISSUED the faulting store is gone.
//
//   marv_epc is checked against the push PC first: without it, a 0 restartable
//   bit could just mean some OTHER fault populated the capture.
//
//   no_variants, but NOT single-alignment: this stimulus pins the SRAM wait states
//   itself (s_sram_x_number_ws) and repeats the check, so two deterministic bus
//   latencies are covered without random timing variants -- which would move the
//   fault mid-sequence and invalidate the premise. See the .s.
//
//   Scratchpad: 0 handler_addr, 0x40 estat, 0x44 marv_epc, 0x48 push PC,
//               0x4C nmi_count
//----------------------------------------------------------------------------

// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

localparam [31:0] ESTAT_UOP_RETIRED = 32'h00000013; // valid|store|uop, NOT restartable

reg [31:0] handler_addr, estat_rb, epc_rb, push_pc, nmi_cnt;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // The push faults on purpose.
    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" ===============================================");
    $display("|  MARV ECAPABUT: abutting uop sequences        |");
    $display(" ===============================================");

    begin : program_vector
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

    estat_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40)];
    epc_rb   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h44)];
    push_pc  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h48)];
    nmi_cnt  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h4C)];

    $display("");
    $display("--- the capture must belong to the push, not some later fault ---");
    $display("marv_epc = 0x%h, push PC = 0x%h %t ns", epc_rb, push_pc, $time);
    if (epc_rb !== push_pc) begin
       $display("ERROR: marv_epc does not identify the cm.push %t ns", $time);
       error = error + 1;
    end

    $display("");
    $display("--- ex_uop_enable stays HIGH across the boundary; restartable must be 0 ---");
    $display("estat = 0x%h   restartable=%0d  uop_sourced=%0d %t ns",
             estat_rb, estat_rb[3], estat_rb[4], $time);
    $display("restartable=1 here would invite a replay of a RETIRED cm.push,");
    $display("decrementing sp a second time.");
    check_mem_value(`SPAD(32'h40), ESTAT_UOP_RETIRED);

    //--------------------------------------------------------------
    // ROUND 2 -- same check at a pinned, longer bus latency
    //--------------------------------------------------------------
    s_sram_x_number_ws = 2;
    $display("");
    $display("SRAM wait states pinned to 2 -- repeating at a second alignment %t ns", $time);

    @(probes_cpu.x31 == 32'h44444444);
    repeat(3) @(posedge free_clk);

    estat_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];
    epc_rb   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h54)];
    push_pc  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h58)];
    nmi_cnt  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h4C)];

    $display("marv_epc = 0x%h, push PC = 0x%h %t ns", epc_rb, push_pc, $time);
    if (epc_rb !== push_pc) begin
       $display("ERROR: marv_epc does not identify the round-2 cm.push %t ns", $time);
       error = error + 1;
    end
    $display("estat = 0x%h   restartable=%0d  uop_sourced=%0d %t ns",
             estat_rb, estat_rb[3], estat_rb[4], $time);
    check_mem_value(`SPAD(32'h50), ESTAT_UOP_RETIRED);

    if (nmi_cnt !== 32'd2) begin
       $display("ERROR: expected exactly 2 RNMI deliveries, saw %0d %t ns", nmi_cnt, $time);
       error = error + 1;
    end

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

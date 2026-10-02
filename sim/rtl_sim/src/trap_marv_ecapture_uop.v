//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_marv_ecapture_uop
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MARV ECAP UOP -- bus error during a Zcmp sequence
//   case 1  sequence STILL IN FLIGHT -> uop=1 restart=1 (0x1B), RNMI delivered
//   case 2  sequence ALREADY RETIRED -> uop=1 restart=0 (0x13)
//   case 3  back-to-back        -> uop=1 restart=0 (0x13), the interleaving a
//                                 level check on ex_uop_enable gets WRONG
//
//   case 4  plain lw from 0     -> valid only (0x01), eaddr=0, epc=the lw,
//                                 mncause 0x80000003
//
//   Also proves DELIVERY: mnstatus.NMIE is armed, so these must actually be
//   TAKEN as RNMIs with mncause=3, not merely captured.
//
//   Scratchpad: 0 handler_addr, 0x40 estat c1, 0x44 estat c2, 0x48 sp after c2,
//               0x4C estat c3, 0x50 nmi_count, 0x54 mncause
//----------------------------------------------------------------------------

// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

localparam [31:0] ESTAT_UOP_INFLIGHT = 32'h0000001B; // valid|store|restartable|uop
localparam [31:0] ESTAT_UOP_RETIRED  = 32'h00000013; // valid|store|uop, NOT restartable
localparam [31:0] MNCAUSE_BUS_ERROR  = 32'h80000003;

reg [31:0] handler_addr, estat_c3, nmi_cnt;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // Every push below faults on purpose.
    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" ===============================================");
    $display("|  MARV ECAP UOP: bus error during a Zcmp seq   |");
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
    $display("mnstatus.NMIE armed -- UOP bus errors must now be DELIVERED %t ns", $time);

    //--------------------------------------------------------------
    // CASE 1 -- first store faults, sequence in flight
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h33333333);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- case 1: cm.push first store faults (sequence IN FLIGHT) ---");
    check_mem_value(`SPAD(32'h40), ESTAT_UOP_INFLIGHT);
    check_mem_value(`SPAD(32'h54), MNCAUSE_BUS_ERROR);   // it was really delivered

    //--------------------------------------------------------------
    // CASE 2 -- last posted store faults after the macro-op retired
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h44444444);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- case 2: cm.push LAST store faults (sequence RETIRED) ---");
    check_mem_value(`SPAD(32'h44), ESTAT_UOP_RETIRED);
    check_mem_value(`SPAD(32'h48), 32'h7FFFFFFC);        // sp WAS updated: retired
    $display("sp after the push = 0x7FFFFFFC -- decremented by 16, so the macro-op");
    $display("had retired before its last store's error arrived.");

    //--------------------------------------------------------------
    // CASE 3 -- back-to-back. The hard one: push #1's late error lands
    // while a DIFFERENT cm.push is in flight, so ex_uop_enable is high
    // for a sequence that is NOT the one that issued the faulting store.
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h55555555);
    repeat(3) @(posedge free_clk);
    estat_c3 = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h4C)];
    nmi_cnt  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50)];
    $display("");
    $display("--- case 3: back-to-back cm.push, error lands under a LATER sequence ---");
    $display("estat = 0x%h   restartable=%0d  uop_sourced=%0d   %t ns",
             estat_c3, estat_c3[3], estat_c3[4], $time);
    $display("restartable must be 0: the sequence that issued this store had retired,");
    $display("and replaying it would double-decrement sp.");
    begin : which_fault
       reg [31:0] epc_c3, push_pc;
       epc_c3  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h58)];
       push_pc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h5C)];
       $display("marv_epc = 0x%h, case-3 push PC = 0x%h", epc_c3, push_pc);
       if (epc_c3 !== push_pc) begin
          $display("ERROR: estat was populated by a DIFFERENT fault than case 3's push %t ns", $time);
          error = error + 1;
       end
    end
    check_mem_value(`SPAD(32'h4C), ESTAT_UOP_RETIRED);

    $display("total RNMIs delivered = %0d %t ns", nmi_cnt, $time);

    if (nmi_cnt < 32'd3) begin
       $display("ERROR: expected at least 3 RNMI deliveries, saw %0d %t ns", nmi_cnt, $time);
       error = error + 1;
    end

    //--------------------------------------------------------------
    // CASE 4 -- plain load bus error after the Zcmp cases
    //--------------------------------------------------------------
    wait(probes_cpu.x31 == 32'h66666666);
    repeat(40) @(posedge free_clk);
    $display("");
    $display("--- case 4: plain lw from address 0 (not UOP-sourced) ---");
    check_mem_value(`SPAD(32'h70), MNCAUSE_BUS_ERROR);    // delivered as the bus-error RNMI
    check_mem_value(`SPAD(32'h60), 32'h00000001);         // valid only: load, not uop, not restartable
    check_mem_value(`SPAD(32'h64), 32'h00000000);         // marv_eaddr = 0
    check_mem_value(`SPAD(32'h6C), ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h68)]); // marv_epc = the lw

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

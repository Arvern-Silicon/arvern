//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_bus_error
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI BUSERR -- a data-bus error is an RNMI, not mcause=5/7
//   The core S4 check. A load to an unmapped address must raise a resumable NMI
//   with mncause=0x80000003 and leave the evidence in marv_epc / marv_eaddr /
//   marv_estat. mtvec must never be entered: mcause 5/7 are RESERVED.
//
//   Scratchpad: 0 handler_addr, 1 nmi_count, 2 mncause, 3 mnepc,
//               4 marv_epc, 5 marv_eaddr, 6 marv_estat, 7 pc of the lw,
//               8 mcause seen by mtvec (must stay 0)
//----------------------------------------------------------------------------

// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

localparam [31:0] MNCAUSE_BUS_ERROR = 32'h80000003; // bit31 interrupt, cause 3 = bus error
localparam [31:0] ESTAT_LOAD_ORD    = 32'h00000001; // valid, load, not uop, not restartable
localparam [31:0] ESTAT_LOAD_OVR    = 32'h00000005; // valid, load, overrun
localparam [31:0] ESTAT_STORE_ORD   = 32'h00000003; // valid, store

reg [31:0] handler_addr, marv_epc_rb, mnepc_rb, pc_lw, epc_2nd;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // The probe faults on purpose.
    error_on_exception = 0;

    //--------------------------------------------------------------
    // Program nmi_vector from the address the firmware published
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" ===============================================");
    $display("|   NMI BUSERR: data-bus error -> RNMI cause 3  |");
    $display(" ===============================================");

    begin : program_vector
       handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
       if (handler_addr == 32'h0) begin
          $display("ERROR: nmi_handler address not published by firmware %t ns", $time);
          error = error + 1;
       end else begin
          $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
       end
    end

    @(probes_cpu.x31 == 32'h22222222);
    $display("mnstatus.NMIE armed %t ns", $time);

    //--------------------------------------------------------------
    // The faulting load must have produced exactly one RNMI
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h33333333);
    repeat(5) @(posedge free_clk);

    $display("");
    $display("--- the bus error must be an RNMI, not a synchronous exception ---");
    check_mem_value(`SPAD(32'h04), 32'h00000001);        // nmi_count == 1
    check_mem_value(`SPAD(32'h08), MNCAUSE_BUS_ERROR);   // mncause
    check_mem_value(`SPAD(32'h14), 32'h00000000);        // marv_eaddr = FAULT_ADDR
    check_mem_value(`SPAD(32'h18), ESTAT_LOAD_ORD);      // marv_estat

    $display("");
    $display("--- mtvec must NEVER be entered (mcause 5/7 RESERVED) ---");
    check_mem_value(`SPAD(32'h20), 32'h00000000);        // no synchronous trap at all

    //--------------------------------------------------------------
    // THE INVARIANT: marv_epc = WHAT faulted, mnepc = WHERE to resume.
    //--------------------------------------------------------------
    begin : invariant_check
       marv_epc_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
       mnepc_rb    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];
       pc_lw       = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)];
       $display("");
       $display("--- marv_epc = WHAT faulted, mnepc = WHERE to resume ---");
       $display("faulting lw PC = 0x%h", pc_lw);
       $display("marv_epc       = 0x%h   (must equal the faulting lw PC)", marv_epc_rb);
       $display("mnepc          = 0x%h   (must NOT equal it -- the load retired)  %t ns",
                mnepc_rb, $time);

       if (marv_epc_rb !== pc_lw) begin
          $display("ERROR: marv_epc does not identify the faulting access %t ns", $time);
          error = error + 1;
       end
       if (mnepc_rb === pc_lw) begin
          $display("ERROR: mnepc points AT the faulting load -- mnret would re-execute it");
          $display("       into a fault loop. mnepc must be the resume point. %t ns", $time);
          error = error + 1;
       end
    end

    //--------------------------------------------------------------
    // PHASE 2 -- second fault while unread: FIRST-FAULT-WINS
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h44444444);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- second bus error while valid set -> overrun, evidence preserved ---");
    check_mem_value(`SPAD(32'h24), ESTAT_LOAD_OVR);   // valid|load|overrun
    begin : preserved
       epc_2nd = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h28)];
       $display("marv_epc after 2nd fault = 0x%h (must still be 0x%h) %t ns",
                epc_2nd, marv_epc_rb, $time);
       if (epc_2nd !== marv_epc_rb) begin
          $display("ERROR: second bus error overwrote the captured PC %t ns", $time);
          error = error + 1;
       end
    end

    //--------------------------------------------------------------
    // PHASE 3 -- W1C clears valid and overrun
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h55555555);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- W1C of valid|overrun -> estat reads 0 ---");
    check_mem_value(`SPAD(32'h2C), 32'h00000000);

    //--------------------------------------------------------------
    // PHASE 4 -- a STORE bus error sets the store bit
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h66666666);
    repeat(3) @(posedge free_clk);
    $display("");
    $display("--- store bus error -> store bit set ---");
    check_mem_value(`SPAD(32'h30), ESTAT_STORE_ORD);

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

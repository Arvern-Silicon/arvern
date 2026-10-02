//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_bus_err_next_ldst
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI BUSERR NEXT-LDST -- the load/store right behind a data-bus
//   error must still execute. 12 firmware rounds put an unrelated lw or sw
//   0/1/2 NOPs behind a faulting lw or sw (unmapped address -> AHB ERROR ->
//   RNMI mncause=0x80000003). For every round this testbench demands:
//     - the younger access executed: RES[id] == K(id) (lw: rd; sw: readback),
//       and for a younger sw the SRAM word itself holds K(id)
//     - exactly one RNMI per round: CNT[id] == id+1
//     - record[id]: mncause == 0x80000003, marv_epc == FPC[id] (the faulting
//       access), FPC[id] < mnepc <= END[id] (resumes strictly past the fault,
//       inside the round), marv_eaddr == FAULT_ADDR, marv_estat == valid|load
//       or valid|store
//     - mtvec never entered (no synchronous cause 5/7)
//   Run under -wssram / -rwsram as well so the ERROR's second cycle lands on
//   the younger access in different pipeline positions.
//----------------------------------------------------------------------------

// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

localparam [31:0] MNCAUSE_BUS_ERROR = 32'h80000003; // bit31 interrupt, cause 3 = bus error
localparam [31:0] ESTAT_LOAD_ORD    = 32'h00000001; // valid, load
localparam [31:0] ESTAT_STORE_ORD   = 32'h00000003; // valid, store
localparam [31:0] FAULT_ADDR        = 32'h00000000;

localparam [31:0] OFF_NMI_CNT   = 32'h010;
localparam [31:0] OFF_MTVEC_CNT = 32'h014;
localparam [31:0] OFF_FPC       = 32'h020;
localparam [31:0] OFF_END       = 32'h060;
localparam [31:0] OFF_RES       = 32'h0A0;
localparam [31:0] OFF_CNT       = 32'h0E0;
localparam [31:0] OFF_DAT       = 32'h200;
localparam [31:0] OFF_REC       = 32'h400;

reg [31:0] fpc, endpc, mncause, mnepc, mepc, eaddr, estat, kval;
integer    fkind, skind, id;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // The rounds fault on purpose (data-bus errors).
    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    repeat(3) @(posedge free_clk);
    $display("");
    $display(" =====================================================");
    $display("|   NMI BUSERR NEXT-LDST: younger ld/st must execute  |");
    $display(" =====================================================");
    $display("nmi_handler published at 0x%h %t ns",
             ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)], $time);

    @(probes_cpu.x31 == 32'h22222222);
    $display("mnstatus.NMIE armed %t ns", $time);

    //--------------------------------------------------------------
    // All 12 rounds done: inspect the scratchpad
    //--------------------------------------------------------------
    @(probes_cpu.x31 == 32'h33333333);
    repeat(5) @(posedge free_clk);

    for (id = 0; id < 12; id = id + 1) begin
        fkind = (id >= 6) ? 1 : 0;              // 0..5 faulting lw, 6..11 faulting sw
        skind = ((id % 6) >= 3) ? 1 : 0;        // {0,1,2} younger lw, {3,4,5} younger sw
        kval  = 32'h5A5A0000 + id;
        fpc     = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(OFF_FPC + id*4)];
        endpc   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(OFF_END + id*4)];
        mncause = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(OFF_REC + id*32 + 0)];
        mnepc   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(OFF_REC + id*32 + 4)];
        mepc    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(OFF_REC + id*32 + 8)];
        eaddr   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(OFF_REC + id*32 + 12)];
        estat   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(OFF_REC + id*32 + 16)];

        $display("");
        $display("--- round %0d: faulting %0s, younger %0s %0d NOP(s) behind (fault PC 0x%h, mnepc 0x%h) ---",
                 id, fkind ? "sw" : "lw", skind ? "sw" : "lw", id % 3, fpc, mnepc);

        // the younger access really executed
        check_mem_value(`SPAD(OFF_RES + id*4), kval);          // rd / readback == K(id), not the sentinel
        if (skind)
            check_mem_value(`SPAD(OFF_DAT + id*4), kval);      // the store landed in SRAM

        // exactly one RNMI per round
        check_mem_value(`SPAD(OFF_CNT + id*4), id + 1);

        // RNMI evidence
        if (mncause !== MNCAUSE_BUS_ERROR) begin
            $display("ERROR: round %0d mncause=0x%h (expected 0x%h) %t ns", id, mncause, MNCAUSE_BUS_ERROR, $time);
            error = error + 1;
        end
        if (mepc !== fpc) begin
            $display("ERROR: round %0d marv_epc=0x%h does not name the faulting access 0x%h %t ns", id, mepc, fpc, $time);
            error = error + 1;
        end
        if (mnepc === fpc) begin
            $display("ERROR: round %0d mnepc=0x%h points AT the faulting access -- mnret would re-execute it %t ns", id, mnepc, $time);
            error = error + 1;
        end
        if (!((mnepc > fpc) && (mnepc <= endpc))) begin
            $display("ERROR: round %0d mnepc=0x%h outside (fault 0x%h, end 0x%h] %t ns", id, mnepc, fpc, endpc, $time);
            error = error + 1;
        end
        if (eaddr !== FAULT_ADDR) begin
            $display("ERROR: round %0d marv_eaddr=0x%h (expected 0x%h) %t ns", id, eaddr, FAULT_ADDR, $time);
            error = error + 1;
        end
        if (estat !== (fkind ? ESTAT_STORE_ORD : ESTAT_LOAD_ORD)) begin
            $display("ERROR: round %0d marv_estat=0x%h (expected 0x%h) %t ns", id, estat,
                     fkind ? ESTAT_STORE_ORD : ESTAT_LOAD_ORD, $time);
            error = error + 1;
        end
    end

    $display("");
    $display("--- totals: 12 RNMIs, mtvec never entered ---");
    check_mem_value(`SPAD(OFF_NMI_CNT),   32'd12);
    check_mem_value(`SPAD(OFF_MTVEC_CNT), 32'd0);

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

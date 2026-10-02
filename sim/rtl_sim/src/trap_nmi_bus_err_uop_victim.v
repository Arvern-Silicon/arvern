//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_nmi_bus_err_uop_victim
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: UOP VICTIM -- a data-bus error on a plain sw/lw must not cost the
//   younger cm.push / cm.mva01s / cm.jt its execution. One RNMI per round.
//
//   Results at 0x80000100 + id*16: w0..w2 per round kind (see the .s), w3 = RNMIs.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

localparam [31:0] SP0 = 32'h80002000;

integer id;
reg [31:0] e0, e1, e2;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  UOP VICTIM: plain-access bus error + Zcmp/Zcmt |");
    $display(" ===============================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(40) @(posedge free_clk);

    for (id = 0; id < 12; id = id + 1) begin
       if (id <= 4) begin                                  // cm.push {ra, s0}, -16
          e0 = SP0 - 16;
          e1 = 32'h50000000 + id;                     // s0 at sp0-4, ra at sp0-8 (Zcmp store order)
          e2 = 32'h1A000000 + id;
          $display("round %0d cm.push   : sp=0x%h [sp0-4]=0x%h [sp0-8]=0x%h rnmi=%0d", id,
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 0)],
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 4)],
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 8)],
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 12)]);
       end else if (id <= 7) begin                         // cm.mva01s s2, s3
          e0 = 32'h22000000 + id;
          e1 = 32'h33000000 + id;
          e2 = 32'h0;
          $display("round %0d cm.mva01s : a0=0x%h a1=0x%h rnmi=%0d", id,
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 0)],
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 4)],
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 12)]);
       end else begin                                      // cm.jt 0
          e0 = 32'h1;
          e1 = 32'h0;
          e2 = 32'h0;
          $display("round %0d cm.jt     : t5=0x%h (1=target FA11=fell-through E5C=escaped) rnmi=%0d", id,
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 0)],
                   ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + id*16 + 12)]);
       end
       check_mem_value(`SPAD(32'h100 + id*16 + 0),  e0);
       check_mem_value(`SPAD(32'h100 + id*16 + 4),  e1);
       check_mem_value(`SPAD(32'h100 + id*16 + 8),  e2);
       check_mem_value(`SPAD(32'h100 + id*16 + 12), 32'd1);
    end

    $display("unexpected synchronous traps: %0d", ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)]);
    check_mem_value(`SPAD(32'h18), 32'd0);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

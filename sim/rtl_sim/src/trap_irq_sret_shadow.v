//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_sret_shadow
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SRET SHADOW - MPP must agree with MEPC for an IRQ near SRET
//   MEPC == SRET PC  -> taken ON the sret   -> MPP = 01 (S)
//   MEPC == U target -> taken in U-mode     -> MPP = 00 (U)
//   Anything else is a privilege-escalation bug: mret would send U-mode code
//   back at S-mode privilege.
//
//   Scratchpad: 0 irq_count, 4 case index,
//               0x10+8i mepc, 0x14+8i mstatus, 0x40+4i sret PC, 0x50+4i U PC
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

integer c;
reg [31:0] mepc_v, mstat_v, sret_pc, u_pc;
reg [1:0]  mpp;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    use_aclint         = 0;   // irq_m_software is driven from here, precisely
    error_on_exception = 0;   // the U-mode ecalls are the case-advance mechanism

    @(probes_cpu.x31 == 32'h11111111);
    $display("");
    $display(" ===============================================");
    $display("|  SRET SHADOW: MPP must agree with MEPC        |");
    $display(" ===============================================");

    // Arm the IRQ a swept number of cycles after each case's marker, walking it
    // across the SRET boundary.
    for (c = 0; c < 4; c = c + 1) begin
       @(probes_cpu.x31 == (32'hA0000000 + c));
       repeat(c) @(posedge free_clk);
       irq_m_software = 1'b1;
       repeat(8) @(posedge free_clk);
       irq_m_software = 1'b0;
       repeat(20) @(posedge free_clk);
    end

    @(probes_cpu.x31 == 32'h22222222);
    repeat(5) @(posedge free_clk);

    $display("");
    $display("--- four alignments of the IRQ against the SRET ---");
    for (c = 0; c < 4; c = c + 1) begin
       mepc_v  = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10) + c*2];
       mstat_v = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14) + c*2];
       sret_pc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h40) + c];
       u_pc    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h50) + c];
       mpp     = mstat_v[12:11];

       $display("case %0d: mepc=0x%h  sret_pc=0x%h  u_pc=0x%h  MPP=%0d",
                c, mepc_v, sret_pc, u_pc, mpp);

       // The IRQ can land anywhere near the boundary, so compare POSITION, not
       // exact equality: at or before the sret the hart is still in S; from the
       // U target onward it is in U. MPP must agree with where MEPC points.
       if (mepc_v >= u_pc) begin
          if (mpp !== 2'b00) begin
             $display("ERROR: mepc is at/after the U target but MPP=%0d.", mpp);
             $display("       mret would resume U-mode code at S privilege %t ns", $time);
             error = error + 1;
          end
       end else if (mepc_v <= sret_pc) begin
          if (mpp !== 2'b01) begin
             $display("ERROR: mepc is at/before the sret but MPP=%0d, expected 1 (S) %t ns",
                      mpp, $time);
             error = error + 1;
          end
       end else begin
          $display("ERROR: mepc 0x%h lies between the sret and the U target %t ns",
                   mepc_v, $time);
          error = error + 1;
       end
    end

    // All four IRQs must actually have been delivered, or the loop above is vacuous.
    check_mem_value(`SPAD(32'h00), 32'h00000004);

    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_sba_pmp_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SBA PMP FAULT -- SBA traffic on a running hart while it takes
//   PMP access faults: one trap per denied access (4 * 64), no RNMI, no lockup.
//   The SBA block reads target SRAM the firmware does not use; the hart is
//   never halted.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;
integer n_sba;

localparam [6:0]  DMI_SBADDRESS0 = 7'h39;
localparam [6:0]  DMI_SBDATA0    = 7'h3c;
localparam [31:0] SBA_BASE       = 32'h80006000;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    $display("");
    $display(" ===============================================");
    $display("|  SBA PMP FAULT: SBA traffic vs denied lw/sw   |");
    $display(" ===============================================");

    @(probes_cpu.x31 == 32'h11111111);
    dmi_write(7'h10, 32'h00000001);                  // dmcontrol = dmactive (no halt)
    dmi_write(7'h10, 32'h10000001);                  // ackhavereset

    sba_cfg(1'b1, 1'b1, 1'b1, 3'd2);                 // readonaddr, readondata, autoincr, 32-bit
    dmi_write(DMI_SBADDRESS0, SBA_BASE);
    n_sba = 0;
    while (probes_cpu.x31 !== 32'h33333333 && probes_cpu.x31 !== 32'hdeadbeef && !lockup) begin
       dmi_read(DMI_SBDATA0);                        // each read arms the next bus read
       n_sba = n_sba + 1;
       if ((n_sba % 64) == 0) dmi_write(DMI_SBADDRESS0, SBA_BASE);
    end
    sba_cfg(1'b0, 1'b0, 1'b0, 3'd2);
    $display("SBA reads issued while the loop ran: %0d", n_sba);

    if (lockup) begin
       $display("ERROR: hart locked up (critical-error state) %t ns", $time);
       error = error + 1;
       repeat(20) @(posedge free_clk);
       stimulus_done = 1;
    end else begin
       wait (probes_cpu.x31 === 32'hdeadbeef);
       random_irq_enable = 0;
       repeat(40) @(posedge free_clk);
       $display("traps=%0d rnmi=%0d wrong-cause=%0d",
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)],
                ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)]);
       check_mem_value(`SPAD(32'h10), 32'd256);
       check_mem_value(`SPAD(32'h14), 32'd0);
       check_mem_value(`SPAD(32'h18), 32'd0);
       repeat(20) @(posedge free_clk);
       stimulus_done = 1;
    end
end

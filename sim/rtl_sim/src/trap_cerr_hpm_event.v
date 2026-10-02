//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_cerr_hpm_event
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CERR HPM - entering the Smdbltrp critical-error state updates no
//   architectural state: an mhpmcounter programmed with the exception event
//   stays 0. Read over the debugger after halting the locked-up hart.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

integer to;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE  = 32'h00000001;
localparam [31:0] DMC_HALTREQ   = 32'h80000000;
localparam [31:0] DMC_RESUMEREQ = 32'h40000000;

localparam [31:0] DMS_ALLHALTED  = 32'h00000200;
localparam [31:0] DMS_ALLRUNNING = 32'h00000800;

localparam [31:0] ACS_BUSY   = 32'h00001000;
localparam [31:0] ACS_CMDERR = 32'h00000700;

// Access Register read: aarsize=2 (32-bit) | transfer=1 | regno = CSR address
localparam [31:0] CMD_RD_BASE = 32'h00200000 | 32'h00020000;

reg [31:0] fault_pc;
reg [31:0] dpc_val, mepc_val, mcause_val, dcsr_val, dpc_val2;

// Abstract-read one CSR into data0; leaves the value in dmi_readval via a
// follow-up data0 read. Reports cmderr rather than hanging on it.
task acmd_read_csr;
   input [11:0] csr_addr;
   input [255:0] name;
   output [31:0] value;
   begin
      dmi_write(DMI_COMMAND, CMD_RD_BASE | {20'h0, csr_addr});
      to = 0;
      dmi_read(DMI_ABSTRACTCS);
      while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
         dmi_read(DMI_ABSTRACTCS);
         to = to + 1;
      end
      if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
         $display("ERROR: abstractcs.busy stuck reading %0s %t ns", name, $time);
         error = error + 1;
         value = 32'hDEADDEAD;
      end else if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d reading %0s %t ns", (dmi_readval & ACS_CMDERR) >> 8, name, $time);
         error = error + 1;
         value = 32'hDEADDEAD;
      end else begin
         dmi_read(DMI_DATA0);
         value = dmi_readval;
         $display("PASS:  abstract read %0s = 0x%h %t ns", name, value, $time);
      end
   end
endtask

reg [31:0] cnt;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;

      $display("");
      $display(" ===============================================");
      $display("|  CERR HPM: critical-error entry not counted   |");
      $display(" ===============================================");

      @(probes_cpu.x31 == 32'h11111111);
      wait(lockup === 1'b1);
      repeat(5) @(posedge free_clk);

      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: locked-up hart did not halt %t ns", $time);
         error = error + 1;
      end
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);

      acmd_read_csr(12'hB03, "mhpmcounter3", cnt);
      if (cnt !== 32'h0) begin
         $display("ERROR: mhpmcounter3 = %0d: the critical-error entry was counted as an exception %t ns", cnt, $time);
         error = error + 1;
      end else $display("PASS:  mhpmcounter3 still 0 %t ns", $time);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_critical_error
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: debugging a hart in the Smdbltrp critical-error state
//
//   Reached from the RESET state: NMIE is never armed, so the first M-mode trap
//   is unexpected and no handler runs.
//   Phase A  dcsr.cetrig is hardwired 0, so the hart asserts lockup_o and must
//            NOT enter Debug Mode by itself (Debug Spec 4.9.1).
//   Phase B  the debugger halts it anyway. haltreq must be honoured even though
//            the hart has ceased execution -- otherwise a critical error is
//            un-diagnosable in-band.
//   Phase C  the post-mortem is readable over abstract Access Register commands.
//            dpc names the instruction the hart died on; mepc/mcause are still
//            at their reset values, because the trap never wrote them.
//   Phase D  resume works, and lands the hart back in the critical-error state
//            with lockup_o still asserted and still executing nothing.
//
//   Phases B and D are the ones under test: the Debug spec does not say whether
//   a hart already in the critical-error state can be halted (see
//   doc/spec_compliance_notes.md), so this pins aRVern's answer.
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

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      $display("");
      $display(" ====================================================================");
      $display("|   DEBUGGING A HART IN THE Smdbltrp CRITICAL-ERROR STATE            |");
      $display(" ====================================================================");
      $display("");

      $display("--- lockup_o low out of reset ---");
      if (lockup !== 1'b0) begin
         $display("ERROR: lockup_o already asserted %t ns", $time);
         error = error + 1;
      end else $display("PASS:  lockup_o low %t ns", $time);

      //=================================================================
      // PHASE A -- cetrig=0: signal the platform, do NOT self-halt
      //=================================================================
      @(probes_cpu.x31 == 32'h11111111);
      $display("NMIE never armed; waiting for lockup_o on the first trap... %t ns", $time);

      // Level-sensitive: the ECALL follows the sync within two instructions, so
      // an edge-triggered wait can arrive after lockup has already risen.
      wait(lockup === 1'b1);
      repeat(5) @(posedge free_clk);

      $display("");
      $display("--- phase A: lockup_o asserted ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o not asserted %t ns", $time);
         error = error + 1;
      end else $display("PASS:  lockup_o asserted %t ns", $time);

      $display("");
      $display("--- cetrig=0, so the hart must NOT have entered Debug Mode itself ---");
      if (dbg_debug_mode !== 1'b0) begin
         $display("ERROR: hart self-entered Debug Mode -- that is cetrig=1 behaviour %t ns", $time);
         error = error + 1;
      end else $display("PASS:  hart did not enter Debug Mode %t ns", $time);

      fault_pc    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];

      $display("");
      $display("--- the M trap handler never ran ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      //=================================================================
      // PHASE B -- the debugger halts a hart that has ceased execution
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE B: haltreq against a hart that has ceased execution        |");
      $display(" ====================================================================");
      $display("");

      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);

      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: hart did not halt from the critical-error state (%0d polls) %t ns", to, $time);
         $display("       a critical error would then be un-diagnosable in-band.");
         error = error + 1;
      end else $display("PASS:  hart halted from the critical-error state (%0d polls) %t ns", to, $time);

      if (dbg_debug_mode !== 1'b1) begin
         $display("ERROR: dbg_debug_mode low although allhalted=1 %t ns", $time);
         error = error + 1;
      end else $display("PASS:  hart in Debug Mode %t ns", $time);

      //=================================================================
      // PHASE C -- read the post-mortem out
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE C: post-mortem over abstract Access Register commands      |");
      $display(" ====================================================================");
      $display("");

      acmd_read_csr(12'h7b1, "dpc",    dpc_val);
      acmd_read_csr(12'h341, "mepc",   mepc_val);
      acmd_read_csr(12'h342, "mcause", mcause_val);
      acmd_read_csr(12'h7b0, "dcsr",   dcsr_val);

      $display("");
      $display("--- dcsr.cause = 3 (haltreq). NOT 7: that is the cetrig=1 encoding ---");
      if (((dcsr_val >> 6) & 32'h7) !== 32'd3) begin
         $display("ERROR: dcsr.cause = %0d, expected 3 (haltreq) %t ns", (dcsr_val >> 6) & 32'h7, $time);
         error = error + 1;
      end else $display("PASS:  dcsr.cause = 3 (haltreq) %t ns", $time);

      $display("");
      $display("--- dcsr.cetrig reads 0 (hardwired) ---");
      if (((dcsr_val >> 19) & 32'h1) !== 32'h0) begin
         $display("ERROR: dcsr.cetrig = 1, expected hardwired 0 %t ns", $time);
         error = error + 1;
      end else $display("PASS:  dcsr.cetrig = 0 %t ns", $time);

      $display("");
      $display("--- mepc/mcause untouched: the trap wrote no architectural state ---");
      if (mcause_val !== 32'h00000000) begin
         $display("ERROR: mcause read back 0x%h, expected 0 %t ns", mcause_val, $time);
         error = error + 1;
      end else $display("PASS:  mcause still 0 %t ns", $time);

      if (mepc_val !== 32'h00000000) begin
         $display("ERROR: mepc read back 0x%h, expected 0 %t ns", mepc_val, $time);
         error = error + 1;
      end else $display("PASS:  mepc still 0 %t ns", $time);

      $display("");
      $display("--- dpc names the instruction the hart died on ---");
      if (dpc_val !== fault_pc) begin
         $display("ERROR: dpc = 0x%h, faulting instruction was at 0x%h %t ns", dpc_val, fault_pc, $time);
         error = error + 1;
      end else $display("PASS:  dpc = 0x%h = the faulting instruction %t ns", dpc_val, $time);

      //=================================================================
      // PHASE D -- resume returns the hart to the critical-error state
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE D: resume lands back in the critical-error state           |");
      $display(" ====================================================================");
      $display("");

      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);

      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
         $display("ERROR: hart did not resume (%0d polls) -- halted but unresumable %t ns", to, $time);
         error = error + 1;
      end else $display("PASS:  hart resumed (%0d polls) %t ns", to, $time);

      repeat(50) @(posedge free_clk);

      $display("");
      $display("--- lockup_o still asserted: the critical-error state is sticky ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o de-asserted across halt/resume %t ns", $time);
         error = error + 1;
      end else $display("PASS:  lockup_o still asserted %t ns", $time);

      $display("");
      $display("--- and the hart still executes nothing ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000000);
      check_mem_value(`SPAD(32'h00), 32'h00000000);

      //=================================================================
      // PHASE E -- halt a SECOND time. dpc_captured clears on resume, so
      // this re-runs the capture with the critical-error state already
      // established rather than arriving on its edge. A non-sticky PC
      // source would diverge here and nowhere else.
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE E: second halt reports the same dpc                        |");
      $display(" ====================================================================");
      $display("");

      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);

      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: hart did not halt a second time (%0d polls) %t ns", to, $time);
         error = error + 1;
      end else $display("PASS:  hart halted again (%0d polls) %t ns", to, $time);

      acmd_read_csr(12'h7b1, "dpc (2nd halt)", dpc_val2);

      if (dpc_val2 !== fault_pc) begin
         $display("ERROR: dpc = 0x%h on the second halt, expected 0x%h %t ns", dpc_val2, fault_pc, $time);
         error = error + 1;
      end else $display("PASS:  dpc = 0x%h on the second halt too %t ns", dpc_val2, $time);

      //=================================================================
      // END OF TEST -- the hart cannot reach 0xdeadbeef by design.
      //=================================================================
      random_irq_enable = 0;
      repeat(10) @(posedge free_clk);
      stimulus_done = 1;
   end

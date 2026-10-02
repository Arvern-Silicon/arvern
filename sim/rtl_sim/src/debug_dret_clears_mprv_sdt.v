//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dret_clears_mprv_sdt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG DRET clears MPRV / sstatus.SDT (Debug Spec 4.8 Resume)
//   Halts the hart from M-mode twice over the DMI bus (dmcontrol.haltreq),
//   rewrites dcsr.prv through the abstract Access Register command (read-
//   modify-write of dcsr 0x7b0, as debug_dmi_stopcount does) and resumes:
//     1. prv=U : after resume mstatus.MPRV==0 and sstatus.SDT==0
//                (firmware had armed both to 1 before the halt)
//     2. prv=S : after resume MPRV==0 (S < M) but SDT still 1
//   dcsr.prv is read back after each write so a WARL-restricted prv field
//   cannot silently void the premise. The firmware samples mstatus in its
//   M handler after an ecall from the resumed privilege (cause 8 / 9), which
//   also proves the privilege itself was restored from dcsr.prv.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

// dmcontrol field constants
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_HALTREQ    = 32'h80000000;  // [31] haltreq
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;  // [30] resumereq
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset

// dmstatus field masks
localparam [31:0] DMS_ALLHALTED    = 32'h00000200; // [9]
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800; // [11]
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000; // [17]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0, aarsize=2, transfer=1)
//   regno = the 12-bit CSR address directly
localparam [31:0] CMD_RD_DCSR     = 32'h00200000 | 32'h00020000 |              32'h000007b0; // = 0x002207b0
localparam [31:0] CMD_WR_DCSR     = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h000007b0; // = 0x002307b0

// dcsr fields
localparam [31:0] DCSR_PRV = 32'h00000003; // [1:0] prv

localparam [31:0] X18_SENTINEL = 32'hA5A5A5A5;

// Issue an abstract command and wait for abstractcs.busy to clear; the final
// abstractcs value (incl. cmderr) is left in dmi_readval.
task abs_run;
   input [31:0] cmd;
   begin
      dmi_write(DMI_COMMAND, cmd);
      to = 0;
      dmi_read(DMI_ABSTRACTCS);
      while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
         dmi_read(DMI_ABSTRACTCS);
         to = to + 1;
      end
   end
endtask

// Halt the hart via dmcontrol.haltreq, poll dmstatus.allhalted.
task halt_hart;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: hart did not halt on dmcontrol.haltreq (allhalted=0) %t ns", $time);
         error = error + 1;
      end else $display("PASS:  hart halted via DMI haltreq (allhalted=1, %0d polls) %t ns", to, $time);

      if (dbg_debug_mode !== 1'b1) begin
         $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
         error = error + 1;
      end
   end
endtask

// Read-modify-write dcsr.prv: expect the halted-from privilege `from`,
// write `to_prv`, read back and confirm it stuck.
task set_dcsr_prv;
   input [1:0] from;
   input [1:0] to_prv;
   begin
      abs_run(CMD_RD_DCSR);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after dcsr read %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
         error = error + 1;
      end
      dmi_read(DMI_DATA0);                                  // dmi_readval = current dcsr
      if ((dmi_readval & DCSR_PRV) !== {30'h0, from}) begin
         $display("ERROR: dcsr.prv=%0d at halt (expected %0d) %t ns", (dmi_readval & DCSR_PRV), from, $time);
         error = error + 1;
      end else $display("PASS:  halted from prv=%0d %t ns", from, $time);

      dmi_write(DMI_DATA0, (dmi_readval & ~DCSR_PRV) | {30'h0, to_prv});
      abs_run(CMD_WR_DCSR);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after dcsr write (prv=%0d) %t ns", (dmi_readval & ACS_CMDERR) >> 8, to_prv, $time);
         error = error + 1;
      end

      abs_run(CMD_RD_DCSR);
      dmi_read(DMI_DATA0);
      if ((dmi_readval & DCSR_PRV) !== {30'h0, to_prv}) begin
         $display("ERROR: dcsr.prv read back %0d after writing %0d %t ns", (dmi_readval & DCSR_PRV), to_prv, $time);
         error = error + 1;
      end else $display("PASS:  dcsr.prv=%0d written and read back %t ns", to_prv, $time);
   end
endtask

// Resume: drop haltreq, assert resumereq, poll allresumeack and allrunning.
task resume_hart;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                 // drop haltreq
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ); // request resume

      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) begin
         $display("ERROR: no allresumeack after resumereq %t ns", $time);
         error = error + 1;
      end

      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
      if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
         $display("ERROR: hart not running after resume (allrunning=0) %t ns", $time);
         error = error + 1;
      end else $display("PASS:  hart running after resume (allrunning=1) %t ns", $time);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // Reset peripherals
    @(negedge free_clk);
    force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
    force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
    @(negedge free_clk);
    release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
    release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

    error_on_exception = 0;
    random_irq_enable  = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG DRET: resume into U clears MPRV+SDT, into S clears MPRV only  |");
    $display(" ====================================================================");

    // --- bring the DM out of reset (dmactive=1) ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);  // clear sticky havereset

    //========================================================================
    // PHASE 1: halt from M with MPRV=1 / SDT=1 armed, resume into U
    //========================================================================
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware armed MPRV+SDT and spinning in M (x31=0x11111111) %t ns", $time);
    check_cpu_reg(20, 32'h01020000);   // both bits armed before the halt

    halt_hart;
    set_dcsr_prv(2'd3, 2'd0);          // halted from M, resume into U
    resume_hart;

    //========================================================================
    // PHASE 2: firmware re-armed in its M handler, resume into S
    //========================================================================
    @(probes_cpu.x31==32'h22222222);
    $display("Firmware re-armed MPRV+SDT and spinning in M (x31=0x22222222) %t ns", $time);

    $display("--- phase 1: ecall arrived from U (prv restored), MPRV and SDT cleared ---");
    check_cpu_reg(21, 32'h00000008);   // mcause = ecall from U
    check_cpu_reg(22, 32'h00000000);   // mstatus & (SDT|MPRV) == 0

    halt_hart;
    set_dcsr_prv(2'd3, 2'd1);          // halted from M, resume into S
    resume_hart;

    @(probes_cpu.x31==32'hdeadbeef);

    $display("--- phase 2: resumed into S, SDT kept, MPRV cleared ---");
    check_cpu_reg(23, 32'h01000000);   // sstatus.SDT read in S-mode == 1
    check_cpu_reg(24, 32'h00000009);   // mcause = ecall from S
    check_cpu_reg(25, 32'h00000000);   // mstatus.MPRV == 0
    check_cpu_reg(26, 32'h01000000);   // mstatus.SDT still 1
    check_cpu_reg(27, 32'h00000001);   // MPP = S
    check_cpu_reg(18, X18_SENTINEL);   // sentinel intact

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

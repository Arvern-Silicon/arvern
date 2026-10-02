//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_illegal
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdtrig execute trigger on the PC of an ILLEGAL instruction
//   (Debug 1.0). Companion testbench for debug_trigger_illegal.s. Per the
//   Debug Spec exception-priority table the instruction-address breakpoint
//   (mcontrol6 execute trigger) OUTRANKS the illegal-instruction exception:
//     A  action=0 armed on `.word 0xFFFFFFFF` -> mcause=3 (breakpoint),
//        mepc=&illegal_word, mtval=0, exactly 1 trap. mcause MUST NOT be 2.
//     B  negative control, trigger disabled, same address -> mcause=2
//        (illegal instruction), mepc=&illegal_word, mtval=0, exactly 1 trap.
//     C  action=1 (enter Debug), debugger-armed (dmode=1) on the same
//        address: hart AUTO-ENTERS Debug Mode with dcsr.cause=2 and
//        dpc=&illegal_word; the unexpected-M-trap counter stays 0 (the
//        illegal-instruction exception did not win). The .v then disarms,
//        writes dpc=&recover_C and resumes.
//   In every phase the illegal word itself never executes (fellthrough
//   marker stays 0).
//
//   The .v actively drives only PHASE C: it halts the spinning hart over
//   DMI, arms the trigger via the abstract Access Register command
//   (action=1 needs dmode=1 -> debugger-only), resumes, and after the
//   auto-entry reads dcsr / dpc, then disarms, redirects dpc past the
//   illegal word (x7 = &recover_C) and resumes.
//
//   error_on_exception is set 0: phases A/B deliberately raise breakpoint
//   (mcause=3) and illegal-instruction (mcause=2) exceptions. The firmware
//   trap COUNTERS (exact expected values) are the safety net against any
//   unexpected extra trap.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

// DMI halt/resume + abstract arming + deliberate traps under stacked
// wait-state variants is cycle-heavy: opt into the long timeout tier.
`define VERY_LONG_TIMEOUT

`define SPAD(byte_off)  ((byte_off)/4)

reg [31:0] dcsr_val, dpc_val;
reg [31:0] mval, addr_ill, addr_rec;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

// dmcontrol field constants
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset

// dmstatus field masks
localparam [31:0] DMS_ALLHALTED  = 32'h00000200;  // [9]

// abstractcs field masks
localparam [31:0] ACS_BUSY   = 32'h00001000;       // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700;       // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0, aarsize=2, transfer=1)
//   base = 0x00220000 ; +0x00010000 sets the write bit ; low 16 = regno
//   (CSR regno = 12-bit CSR address ; GPR regno = 0x1000 + n)
localparam [31:0] CMD_WR_TSELECT = 32'h00230000 | 32'h000007a0;
localparam [31:0] CMD_WR_TDATA1  = 32'h00230000 | 32'h000007a1;
localparam [31:0] CMD_WR_DPC     = 32'h00230000 | 32'h000007b1;
localparam [31:0] CMD_RD_DCSR    = 32'h00220000 | 32'h000007b0;
localparam [31:0] CMD_RD_DPC     = 32'h00220000 | 32'h000007b1;
localparam [31:0] CMD_RD_X6      = 32'h00220000 | 32'h00001006;
localparam [31:0] CMD_RD_X7      = 32'h00220000 | 32'h00001007;

// Phase-C trigger arming word (debugger-side):
//   type6 | dmode | action=1 | execute | m | match=0
localparam [31:0] ARM_C_TDATA1 = 32'h68001044;

// dcsr.cause field (bits[8:6]); cause==2 (trigger) -> field value 0x80
localparam [31:0] DCSR_CAUSE = 32'h000001C0;
localparam [31:0] DCSR_CAUSE_TRIGGER = 32'h00000080;

reg [31:0] acmd_rdata;

// Issue an abstract command, wait busy clear; abstractcs left in dmi_readval.
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

// Abstract CSR/GPR write of `val` (expect cmderr==0).
task abs_wr;
   input [31:0] cmd;
   input [31:0] val;
   begin
      dmi_write(DMI_DATA0, val);
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after abstract write (cmd=%h val=%h) %t ns",
                  (dmi_readval & ACS_CMDERR) >> 8, cmd, val, $time);
         error = error + 1;
      end
   end
endtask

// Abstract CSR/GPR read (expect cmderr==0); data -> acmd_rdata.
task abs_rd;
   input [31:0] cmd;
   begin
      abs_run(cmd);
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after abstract read (cmd=%h) %t ns",
                  (dmi_readval & ACS_CMDERR) >> 8, cmd, $time);
         error = error + 1;
      end
      dmi_read(DMI_DATA0);
      acmd_rdata = dmi_readval;
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

    // Phases A/B intentionally raise breakpoint (mcause=3) and illegal-
    // instruction (mcause=2) exceptions; the firmware trap counters are the
    // real safety net. Keep IRQs off so they cannot perturb the priority
    // race under test or the architectural checks.
    error_on_exception = 0;
    random_irq_enable  = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG TRIGGER ILLEGAL: execute trigger OUTRANKS illegal-instr     |");
    $display(" ====================================================================");

    //========================================================================
    // PHASE A : action=0 breakpoint armed on the illegal word (hart-side).
    //   Runs autonomously; sync only (mem checks deferred to end-of-test).
    //========================================================================
    @(probes_cpu.x31==32'h11111111);
    $display("Phase A complete (x31=0x11111111): trigger vs illegal priority %t ns", $time);
    check_cpu_reg(20, 32'h00000003);   // A mcause == 3: breakpoint WON over illegal

    //========================================================================
    // PHASE B : negative control (trigger disabled -> illegal wins).
    //========================================================================
    @(probes_cpu.x31==32'h22222222);
    $display("Phase B complete (x31=0x22222222): plain illegal-instruction trap %t ns", $time);
    check_cpu_reg(21, 32'h00000002);   // B mcause == 2: illegal instruction

    //========================================================================
    // PHASE C : action=1 (ENTER DEBUG), debugger-armed on the illegal word.
    //========================================================================
    @(probes_cpu.x31==32'h33333333);
    $display("Firmware pre-loaded C trigger, spinning (x31=0x33333333) %t ns", $time);

    // Bring the DM out of reset and halt the spinning hart.
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart halted in Debug Mode (abstract arming permitted) %t ns", $time);

    // Capture &illegal_word (x6) and &recover_C (x7) stashed by the firmware.
    abs_rd(CMD_RD_X6);
    addr_ill = acmd_rdata;
    abs_rd(CMD_RD_X7);
    addr_rec = acmd_rdata;
    $display("INFO:  &illegal_word (x6) = %h, &recover_C (x7) = %h %t ns", addr_ill, addr_rec, $time);

    // ARM the execute trigger: action=1 (enter Debug) + dmode=1 (debugger-only).
    // tdata2 (= &illegal_word) was already loaded by the firmware.
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, ARM_C_TDATA1);
    $display("PASS:  debugger armed C trigger (tdata1=%h, action=1 enter-Debug) %t ns", ARM_C_TDATA1, $time);

    // Resume; the hart finishes spinC and jumps to illegal_word -> the
    // trigger must AUTO-ENTER Debug Mode BEFORE any illegal-instruction
    // exception is raised (instruction-address breakpoint priority).
    dm_resume;

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200000)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: C execute trigger did NOT enter Debug Mode (allhalted=0 after %0d polls) %t ns", to, $time);
        error = error + 1;
    end else $display("PASS:  C execute trigger entered Debug Mode (allhalted=1, %0d polls) %t ns", to, $time);

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted after C trigger fire %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode after C trigger fire %t ns", $time);

    // dcsr.cause must be 2 (trigger) -- NOT an exception-related entry.
    abs_rd(CMD_RD_DCSR);
    dcsr_val = acmd_rdata;
    if ((dcsr_val & DCSR_CAUSE) !== DCSR_CAUSE_TRIGGER) begin
        $display("ERROR: C dcsr.cause=%0d (expected 2 trigger) dcsr=%h %t ns",
                 (dcsr_val & DCSR_CAUSE) >> 6, dcsr_val, $time);
        error = error + 1;
    end else $display("PASS:  C dcsr.cause=2 (trigger) dcsr=%h %t ns", dcsr_val, $time);

    // dpc must point AT the illegal (NOT executed, NOT trapped) instruction.
    abs_rd(CMD_RD_DPC);
    dpc_val = acmd_rdata;
    if (dpc_val !== addr_ill) begin
        $display("ERROR: C dpc=%h != &illegal_word=%h (matching instr address) %t ns", dpc_val, addr_ill, $time);
        error = error + 1;
    end else $display("PASS:  C dpc=%h points AT the illegal word (trigger won) %t ns", dpc_val, $time);

    // Disarm and redirect dpc PAST the illegal word (else resuming would
    // re-fetch it and raise the illegal-instruction exception), then resume.
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, 32'h0);
    abs_wr(CMD_WR_DPC, addr_rec);
    $display("PASS:  debugger disarmed C trigger + set dpc=&recover_C=%h %t ns", addr_rec, $time);
    dm_resume;

    //========================================================================
    // END OF TEST : inspect the scratchpad.
    //========================================================================
    @(probes_cpu.x31==32'hdeadbeef);
    repeat(10) @(posedge free_clk);

    //--- A: breakpoint (trigger) outranked the illegal-instruction excp ----
    mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)];
    if (mval === 32'h00000002) begin
        $display("ERROR: A mcause=2 -- illegal-instruction exception WON over the execute trigger %t ns", $time);
        error = error + 1;
    end
    check_mem_value(`SPAD(32'h00), 32'h00000003);   // mcause = 3 (breakpoint)
    mval     = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)]; // A mepc
    addr_ill = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)]; // &illegal_word
    if (mval !== addr_ill) begin
        $display("ERROR: A mepc=%h != &illegal_word=%h %t ns", mval, addr_ill, $time);
        error = error + 1;
    end else $display("PASS:  A mepc=%h == &illegal_word (matching instr) %t ns", mval, $time);
    check_mem_value(`SPAD(32'h08), 32'h00000000);   // mtval = 0 (breakpoint)
    check_mem_value(`SPAD(32'h0C), 32'h00000001);   // exactly 1 A trap

    //--- B: trigger disabled -> plain illegal-instruction exception --------
    check_mem_value(`SPAD(32'h10), 32'h00000002);   // mcause = 2 (illegal)
    mval = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)];     // B mepc
    if (mval !== addr_ill) begin
        $display("ERROR: B mepc=%h != &illegal_word=%h %t ns", mval, addr_ill, $time);
        error = error + 1;
    end else $display("PASS:  B mepc=%h == &illegal_word (same address, illegal now wins) %t ns", mval, $time);
    check_mem_value(`SPAD(32'h18), 32'h00000000);   // mtval = 0 (core convention)
    check_mem_value(`SPAD(32'h1C), 32'h00000001);   // exactly 1 B trap

    //--- C: Debug entry only -- no M-mode trap, firmware completed ---------
    check_mem_value(`SPAD(32'h28), 32'h00000000);   // unexpected-M-trap counter == 0
    check_mem_value(`SPAD(32'h2C), 32'hC0DE0001);   // recover_C reached after resume

    //--- All phases: the illegal word itself never executed / fell through -
    check_mem_value(`SPAD(32'h24), 32'h00000000);   // fellthrough marker == 0

    //--- Register-side copies (persistent across the whole test) -----------
    check_cpu_reg(20, 32'h00000003);   // A mcause (trigger breakpoint)
    check_cpu_reg(21, 32'h00000002);   // B mcause (illegal instruction)

    //========================================================================
    // END OF TEST
    //========================================================================
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

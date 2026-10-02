//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_exec
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdtrig EXECUTE (instruction-address) trigger FIRING (Debug 1.0)
//   Companion testbench for debug_trigger_exec.s. Proves type=6 (mcontrol6)
//   execute triggers FIRE just BEFORE the matching instruction executes (the
//   matching instruction does NOT retire). Crux of every phase: the side
//   effect of the matching instruction did NOT happen at fire-time.
//
//   The .v actively drives only PHASE A (action=1, enter Debug): it halts the
//   spinning hart over DMI, arms the trigger via the abstract Access Register
//   (action=1 needs dmode=1 -> debugger-only), resumes, and after the trigger
//   AUTO-ENTERS Debug Mode reads dcsr.cause / dpc / x5 / x6 to assert:
//     - dcsr.cause == 2 (trigger)
//     - dpc == x6 (== &trig_tgt_A): the matching instr did NOT execute
//     - x5 still PRE (0xBEEF0000): the side effect was NOT taken
//   It then disarms (clears dmode) + resumes; the hart runs phases B..F
//   autonomously (action=0 breakpoints + negative controls) and records every
//   result into an SRAM scratchpad that this .v inspects at end-of-test.
//
//   error_on_exception is set 0: phases B/C/E deliberately raise breakpoint
//   (mcause=3) exceptions. The firmware trap COUNTERS (exact expected values)
//   are the recovered safety net against any unexpected extra trap.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

// Dual-path firing test (DMI halt/resume + abstract arming + many breakpoint
// traps) under stacked wait-state variants is cycle-heavy: opt into long tier.
`define VERY_LONG_TIMEOUT

`define SPAD(byte_off)  ((byte_off)/4)

reg [31:0] dcsr_val, dpc_val, x5_val, x6_val;
reg [31:0] mval, addr_a, addr_b;

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
localparam [31:0] CMD_RD_DCSR    = 32'h00220000 | 32'h000007b0;
localparam [31:0] CMD_RD_DPC     = 32'h00220000 | 32'h000007b1;
localparam [31:0] CMD_RD_X5      = 32'h00220000 | 32'h00001005;
localparam [31:0] CMD_RD_X6      = 32'h00220000 | 32'h00001006;

// Phase-A trigger arming word (debugger-side):
//   type6 | dmode | action=1 | execute | m | match=0
localparam [31:0] ARM_A_TDATA1 = 32'h68001044;

// dcsr.cause field (bits[8:6]); cause==2 (trigger) -> field value 0x80
localparam [31:0] DCSR_CAUSE = 32'h000001C0;
localparam [31:0] DCSR_CAUSE_TRIGGER = 32'h00000080;

localparam [31:0] PREA = 32'hBEEF0000;   // x5 PRE value (A side effect not taken)

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

    // Phases B/C/E intentionally raise breakpoint (mcause=3) exceptions; the
    // firmware trap counters are the real safety net. Keep IRQs off so they
    // cannot perturb the breakpoint traps or the architectural checks.
    error_on_exception = 0;
    random_irq_enable  = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG TRIGGER EXEC: Sdtrig execute-trigger FIRING (action 0/1)    |");
    $display(" ====================================================================");

    //========================================================================
    // PHASE A : action=1 (ENTER DEBUG), equal match. Debugger-armed.
    //========================================================================
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware pre-loaded A trigger, spinning (x31=0x11111111) %t ns", $time);

    // Bring the DM out of reset and halt the spinning hart.
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart halted in Debug Mode (abstract arming permitted) %t ns", $time);

    // Capture &trig_tgt_A (firmware stashed it in x6) for the dpc compare later.
    abs_rd(CMD_RD_X6);
    addr_a = acmd_rdata;
    $display("INFO:  &trig_tgt_A (x6) = %h %t ns", addr_a, $time);

    // ARM the execute trigger: action=1 (enter Debug) + dmode=1 (debugger-only).
    // tdata2 (= &trig_tgt_A) was already loaded by the firmware.
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, ARM_A_TDATA1);
    $display("PASS:  debugger armed A trigger (tdata1=%h, action=1 enter-Debug) %t ns", ARM_A_TDATA1, $time);

    // Resume; the hart finishes spinA and reaches trig_tgt_A -> trigger fires
    // and AUTO-ENTERS Debug Mode (allhalted=1 again) BEFORE the addi executes.
    dm_resume;

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200000)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: A execute trigger did NOT enter Debug Mode (allhalted=0 after %0d polls) %t ns", to, $time);
        error = error + 1;
    end else $display("PASS:  A execute trigger entered Debug Mode (allhalted=1, %0d polls) %t ns", to, $time);

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted after A trigger fire %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode after A trigger fire %t ns", $time);

    // dcsr.cause must be 2 (trigger).
    abs_rd(CMD_RD_DCSR);
    dcsr_val = acmd_rdata;
    if ((dcsr_val & DCSR_CAUSE) !== DCSR_CAUSE_TRIGGER) begin
        $display("ERROR: A dcsr.cause=%0d (expected 2 trigger) dcsr=%h %t ns",
                 (dcsr_val & DCSR_CAUSE) >> 6, dcsr_val, $time);
        error = error + 1;
    end else $display("PASS:  A dcsr.cause=2 (trigger) dcsr=%h %t ns", dcsr_val, $time);

    // dpc must point AT the matching (NOT executed) instruction == &trig_tgt_A.
    abs_rd(CMD_RD_DPC);
    dpc_val = acmd_rdata;
    if (dpc_val !== addr_a) begin
        $display("ERROR: A dpc=%h != &trig_tgt_A=%h (matching instr address) %t ns", dpc_val, addr_a, $time);
        error = error + 1;
    end else $display("PASS:  A dpc=%h points AT the matching instruction (== &trig_tgt_A) %t ns", dpc_val, $time);

    // x5 must still hold its PRE value: the side effect (x5=0xAA) did NOT happen.
    abs_rd(CMD_RD_X5);
    x5_val = acmd_rdata;
    if (x5_val !== PREA) begin
        $display("ERROR: A side effect TAKEN: x5=%h (expected PRE %h -> matching addi must NOT have run) %t ns", x5_val, PREA, $time);
        error = error + 1;
    end else $display("PASS:  A side effect NOT taken: x5=%h still PRE (matching addi did not run) %t ns", x5_val, $time);

    // Disarm (write tdata1=0 clears dmode so the firmware can re-arm in M-mode),
    // then resume; trig_tgt_A now executes normally and phases B..F run.
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, 32'h0);
    $display("PASS:  debugger disarmed A trigger (dmode cleared) %t ns", $time);
    dm_resume;

    //========================================================================
    // PHASES B..F run autonomously; inspect the scratchpad once done.
    //========================================================================
    @(probes_cpu.x31==32'hdeadbeef);
    repeat(10) @(posedge free_clk);

    //--- A final: the matching instruction eventually executed after disarm ---
    check_mem_value(`SPAD(32'h40), 32'h000000AA);   // x5 = 0xAA

    //--- B: action=0 breakpoint, equal match -------------------------------
    check_mem_value(`SPAD(32'h00), 32'h00000003);   // mcause = 3 (breakpoint)
    mval   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)]; // B mepc
    addr_b = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)]; // &trig_tgt_B
    if (mval !== addr_b) begin
        $display("ERROR: B mepc=%h != &trig_tgt_B=%h %t ns", mval, addr_b, $time);
        error = error + 1;
    end else $display("PASS:  B mepc=%h == &trig_tgt_B (matching instr) %t ns", mval, $time);
    check_mem_value(`SPAD(32'h08), 32'h00000000);   // mtval = 0
    check_mem_value(`SPAD(32'h0C), 32'hB7B70000);   // x7 @ fire == PREB (side effect not taken)
    check_mem_value(`SPAD(32'h10), 32'h00000001);   // exactly 1 B trap

    //--- C: action=0 breakpoint, NAPOT match (fire addr != base) -----------
    check_mem_value(`SPAD(32'h18), 32'h00000003);   // mcause = 3
    mval   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)]; // C mepc
    addr_b = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)]; // &c_tgt (= base+4)
    if (mval !== addr_b) begin
        $display("ERROR: C mepc=%h != &c_tgt=%h (NAPOT in-range fire) %t ns", mval, addr_b, $time);
        error = error + 1;
    end else $display("PASS:  C mepc=%h == &c_tgt (NAPOT fired in-range, != base) %t ns", mval, $time);
    check_mem_value(`SPAD(32'h20), 32'hCCCC0000);   // x28 @ fire == PREC (side effect not taken)
    check_mem_value(`SPAD(32'h28), 32'h00000001);   // exactly 1 C trap

    //--- D: priv-gating negative (m=0 must NOT fire in M-mode) --------------
    check_mem_value(`SPAD(32'h2C), 32'h00000066);   // x29 = 0x66 (side effect DID happen)

    //--- E: mte non-re-fire (handler entered exactly once) -----------------
    check_mem_value(`SPAD(32'h34), 32'h00000001);   // E counter == 1

    //--- F: execute=0 (load-match) must NOT fire on a fetch ----------------
    check_mem_value(`SPAD(32'h38), 32'h00000077);   // x30 = 0x77 (side effect DID happen)

    //--- D & F shared: no unexpected trigger fire --------------------------
    check_mem_value(`SPAD(32'h30), 32'h00000000);   // unexpected-trap counter == 0

    //========================================================================
    // END OF TEST
    //========================================================================
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

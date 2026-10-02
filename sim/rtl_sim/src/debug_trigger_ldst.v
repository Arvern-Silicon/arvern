//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_ldst
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sdtrig LOAD/STORE DATA-ADDRESS watchpoint FIRING (Debug 1.0)
//   Companion testbench for debug_trigger_ldst.s. Proves type=6 (mcontrol6)
//   load/store data-address watchpoints (select=0 ADDRESS match) FIRE just
//   BEFORE the access completes: a STORE does NOT modify memory, a LOAD does
//   NOT update its destination register, at fire time. The "not modified"
//   assertions (watched word for stores, dest reg for the load) are the heart
//   of the test, made unambiguous with distinct PRE/POST sentinels.
//
//   The .v actively drives PHASE 1 (LOAD, action=1, enter Debug): it halts the
//   spinning hart over DMI, arms the load watchpoint via the abstract Access
//   Register (action=1 needs dmode=1 -> debugger-only), resumes, and after the
//   trigger AUTO-ENTERS Debug Mode reads dcsr.cause / dpc / x5 to assert:
//     - dcsr.cause == 2 (trigger)
//     - dpc == x6 (== &b_lw): dpc points at the LOAD INSTRUCTION (not the data
//       address in tdata2) and the load did NOT retire
//     - x5 still PRE (0xBEEF0000): the load side effect (dest update) NOT taken
//   It then disarms (clears dmode) + resumes; the hart runs phases A..F
//   autonomously (action=0 breakpoints + negative controls) and records every
//   result into an SRAM scratchpad / the watched words that this .v inspects.
//
//   error_on_exception is set 0: phases A/C deliberately raise breakpoint
//   (mcause=3) exceptions. The firmware trap COUNTERS (exact expected values)
//   are the recovered safety net against any unexpected extra trap.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

// Dual-path firing test (DMI halt/resume + abstract arming + breakpoint traps)
// under stacked wait-state variants is cycle-heavy: opt into the long tier.
`define VERY_LONG_TIMEOUT

`define SPAD(byte_off)  ((byte_off)/4)

reg [31:0] dcsr_val, dpc_val, x5_val;
reg [31:0] mval, addr_a, addr_c, lwaddr;

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

// Phase-1 load-watchpoint arming word (debugger-side):
//   type6 | dmode | action=1 | size=any | m | load | match=0
localparam [31:0] ARM_LD_TDATA1 = 32'h68001041;

// dcsr.cause field (bits[8:6]); cause==2 (trigger) -> field value 0x80
localparam [31:0] DCSR_CAUSE = 32'h000001C0;
localparam [31:0] DCSR_CAUSE_TRIGGER = 32'h00000080;

localparam [31:0] PRE_LD = 32'hBEEF0000;   // x5 PRE value (load side effect not taken)

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

    // Phases A/C intentionally raise breakpoint (mcause=3) exceptions; the
    // firmware trap counters are the real safety net. Keep IRQs off so they
    // cannot perturb the breakpoint traps or the architectural checks.
    error_on_exception = 0;
    random_irq_enable  = 0;

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG TRIGGER LDST: Sdtrig load/store watchpoint FIRING (act 0/1) |");
    $display(" ====================================================================");

    //========================================================================
    // PHASE 1 (task B) : LOAD watchpoint, action=1 (ENTER DEBUG), equal match.
    //========================================================================
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware pre-loaded phase-1 load watchpoint, spinning (x31=0x11111111) %t ns", $time);

    // Bring the DM out of reset and halt the spinning hart.
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dm_halt;
    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart halted in Debug Mode (abstract arming permitted) %t ns", $time);

    // Capture &b_lw (firmware stashed it in x6) for the dpc compare later.
    abs_rd(CMD_RD_X6);
    lwaddr = acmd_rdata;
    $display("INFO:  &b_lw (x6) = %h %t ns", lwaddr, $time);

    // ARM the load watchpoint: action=1 (enter Debug) + dmode=1 (debugger-only).
    // tdata2 (= &B_DATA, the DATA address) was already loaded by the firmware.
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, ARM_LD_TDATA1);
    $display("PASS:  debugger armed load watchpoint (tdata1=%h, action=1 enter-Debug) %t ns", ARM_LD_TDATA1, $time);

    // Resume; the hart finishes spin1 and reaches b_lw -> the load watchpoint
    // fires and AUTO-ENTERS Debug Mode (allhalted=1) BEFORE the lw updates x5.
    dm_resume;

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200000)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: load watchpoint did NOT enter Debug Mode (allhalted=0 after %0d polls) %t ns", to, $time);
        error = error + 1;
    end else $display("PASS:  load watchpoint entered Debug Mode (allhalted=1, %0d polls) %t ns", to, $time);

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted after load watchpoint fire %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode after load watchpoint fire %t ns", $time);

    // dcsr.cause must be 2 (trigger).
    abs_rd(CMD_RD_DCSR);
    dcsr_val = acmd_rdata;
    if ((dcsr_val & DCSR_CAUSE) !== DCSR_CAUSE_TRIGGER) begin
        $display("ERROR: dcsr.cause=%0d (expected 2 trigger) dcsr=%h %t ns",
                 (dcsr_val & DCSR_CAUSE) >> 6, dcsr_val, $time);
        error = error + 1;
    end else $display("PASS:  dcsr.cause=2 (trigger) dcsr=%h %t ns", dcsr_val, $time);

    // dpc must point AT the LOAD instruction (== &b_lw), NOT the data address.
    abs_rd(CMD_RD_DPC);
    dpc_val = acmd_rdata;
    if (dpc_val !== lwaddr) begin
        $display("ERROR: dpc=%h != &b_lw=%h (load instruction address) %t ns", dpc_val, lwaddr, $time);
        error = error + 1;
    end else $display("PASS:  dpc=%h points AT the load instruction (== &b_lw) %t ns", dpc_val, $time);

    // x5 must still hold its PRE value: the load destination was NOT updated.
    abs_rd(CMD_RD_X5);
    x5_val = acmd_rdata;
    if (x5_val !== PRE_LD) begin
        $display("ERROR: load side effect TAKEN: x5=%h (expected PRE %h -> lw must NOT have retired) %t ns", x5_val, PRE_LD, $time);
        error = error + 1;
    end else $display("PASS:  load side effect NOT taken: x5=%h still PRE (lw dest not updated) %t ns", x5_val, $time);

    // Disarm (write tdata1=0 clears dmode so the firmware can re-arm in M-mode),
    // then resume; b_lw now executes normally and phases A..F run.
    abs_wr(CMD_WR_TSELECT, 32'h0);
    abs_wr(CMD_WR_TDATA1, 32'h0);
    $display("PASS:  debugger disarmed load watchpoint (dmode cleared) %t ns", $time);
    dm_resume;

    //========================================================================
    // PHASES A..F run autonomously; inspect the scratchpad + watched words.
    //========================================================================
    @(probes_cpu.x31==32'hdeadbeef);
    repeat(10) @(posedge free_clk);

    //--- Phase 1 final: the load eventually executed after disarm -----------
    check_mem_value(`SPAD(32'h50), 32'h0B0B0B0B);   // x5 = loaded B_DATA

    //--- A: STORE watchpoint, action=0, equal match ------------------------
    check_mem_value(`SPAD(32'h00), 32'h00000003);   // mcause = 3 (breakpoint)
    mval   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)]; // A mepc
    addr_a = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h14)]; // &sw_A
    if (mval !== addr_a) begin
        $display("ERROR: A mepc=%h != &sw_A=%h (store instruction) %t ns", mval, addr_a, $time);
        error = error + 1;
    end else $display("PASS:  A mepc=%h == &sw_A (store instruction) %t ns", mval, $time);
    check_mem_value(`SPAD(32'h08), 32'h80001010);   // A mtval = &A_DATA (data address)
    check_mem_value(`SPAD(32'h0C), 32'h5A5A5A5A);   // A_DATA @ fire == sentinel (store NOT taken)
    check_mem_value(`SPAD(32'h10), 32'h00000001);   // exactly 1 A trap
    check_mem_value(`SPAD(32'h1010), 32'hA5A5A5A5); // A_DATA final (store eventually done)

    //--- C: STORE watchpoint, action=0, NAPOT match (fire addr != base) ----
    check_mem_value(`SPAD(32'h18), 32'h00000003);   // mcause = 3
    mval   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)]; // C mepc
    addr_c = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)]; // &sw_C
    if (mval !== addr_c) begin
        $display("ERROR: C mepc=%h != &sw_C=%h (store instruction) %t ns", mval, addr_c, $time);
        error = error + 1;
    end else $display("PASS:  C mepc=%h == &sw_C (store instruction) %t ns", mval, $time);
    check_mem_value(`SPAD(32'h20), 32'h80001024);   // C mtval = &c_word1 (= base+4, NAPOT in-range != base)
    check_mem_value(`SPAD(32'h24), 32'hC0C0C0C0);   // c_word1 @ fire == sentinel (store NOT taken)
    check_mem_value(`SPAD(32'h28), 32'h00000001);   // exactly 1 C trap
    check_mem_value(`SPAD(32'h1024), 32'hC5C5C5C5); // c_word1 final (store eventually done)

    //--- D: SIZE negative (size=word watchpoint must NOT fire on a byte sb) -
    check_mem_value(`SPAD(32'h1030), 32'hD0D0D011); // D_DATA: byte store DID modify (low byte 0x11)

    //--- E: PRIV-GATING negative (m=0 must NOT fire on an M-mode store) -----
    check_mem_value(`SPAD(32'h1040), 32'hEEEE1111); // E_DATA: store DID happen

    //--- F: DISABLED/wrong-type negative (execute-only must NOT fire on a store)
    check_mem_value(`SPAD(32'h1050), 32'hFFFF2222); // F_DATA: store DID happen

    //--- D/E/F shared: no unexpected watchpoint fire -----------------------
    check_mem_value(`SPAD(32'h30), 32'h00000000);   // unexpected-trap counter == 0

    //========================================================================
    // END OF TEST
    //========================================================================
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

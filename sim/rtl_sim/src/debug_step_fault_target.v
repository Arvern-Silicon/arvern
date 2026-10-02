//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_step_fault_target
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DEBUG single-step onto an UNFETCHABLE address (Sdext dcsr.step)
//   Halt the spinning hart, rewrite the jalr base x12 to 0x00000000 (unmapped:
//   instruction-bus ERROR, synchronous cause 1), set dcsr.step and walk:
//       step 1 (jalr)          : the jalr retires; the hart must re-halt with
//                                dpc == 0x00000000 (the next instruction, not yet
//                                fetched successfully), dcsr.cause == 4
//       step 2 (fetch at 0)    : the access fault is taken and the hart halts at
//                                the handler entry: dpc == mtvec, mcause == 1,
//                                mepc == 0
//   then dcsr.step is cleared and the handler returns to the end of the test.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;

reg [31:0] pc_parked;
reg [31:0] target_addr;
reg [31:0] mtvec_val;
reg [31:0] dpc_now;
reg [31:0] dpc_prev;
reg [31:0] dcsr_now;
reg [2:0]  cause_now;
reg [31:0] csr_val;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

localparam [31:0] DMC_DMACTIVE   = 32'h00000001;
localparam [31:0] DMC_HALTREQ    = 32'h80000000;
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;

localparam [31:0] DMS_ALLHALTED    = 32'h00000200;
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800;
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000;

localparam [31:0] ACS_BUSY   = 32'h00001000;
localparam [31:0] ACS_CMDERR = 32'h00000700;

// Access Register command words (cmdtype=0, aarsize=2, transfer=1)
localparam [31:0] CMD_RD_DCSR   = 32'h002207b0;
localparam [31:0] CMD_WR_DCSR   = 32'h002307b0;
localparam [31:0] CMD_RD_DPC    = 32'h002207b1;
localparam [31:0] CMD_RD_X13    = 32'h0022100d;
localparam [31:0] CMD_WR_X12    = 32'h0023100c;
localparam [31:0] CMD_RD_MTVEC  = 32'h00220305;
localparam [31:0] CMD_RD_MEPC   = 32'h00220341;
localparam [31:0] CMD_RD_MCAUSE = 32'h00220342;
localparam [31:0] CMD_RD_MTVAL  = 32'h00220343;

localparam [31:0] DCSR_STEP = 32'h00000004;

localparam [31:0] X18_SENTINEL    = 32'hA5A5A5A5;
localparam [31:0] RD_SENTINEL     = 32'hDEAD0000;
localparam [31:0] MISALIGNED_ADDR = 32'h80000101;
localparam [31:0] X5_VAL          = 32'h00000011;
localparam [31:0] X6_VAL          = 32'h00000022;

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

task chk_cmderr;
   input [8*32:1] where;
   begin
      if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
         $display("ERROR: cmderr=%0d after %0s %t ns", (dmi_readval & ACS_CMDERR) >> 8, where, $time);
         error = error + 1;
      end
   end
endtask

task read_dpc;
   begin
      abs_run(CMD_RD_DPC);
      chk_cmderr("dpc read");
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      dpc_now = dmi_readval;
   end
endtask

task read_dcsr;
   begin
      abs_run(CMD_RD_DCSR);
      chk_cmderr("dcsr read");
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      dcsr_now  = dmi_readval;
      cause_now = dcsr_now[8:6];
   end
endtask

task read_csr;
   input  [31:0] cmd;
   input  [8*32:1] where;
   output [31:0] val;
   begin
      abs_run(cmd);
      chk_cmderr(where);
      @(posedge dut_hclk);
      dmi_read(DMI_DATA0);
      val = dmi_readval;
   end
endtask

// Single-step: drop haltreq, assert resumereq, poll allhalted for the auto re-halt.
task do_step;
   begin
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
      dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ);
      to = 0;
      dmi_read(DMI_DMSTATUS);
      while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
         dmi_read(DMI_DMSTATUS);
         to = to + 1;
      end
   end
endtask

// Common post-step checks: auto re-halt, dcsr.cause==4, dpc == expected.
task chk_step;
   input [8*32:1] what;
   input [31:0]   dpc_exp;
   begin
      if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
         $display("ERROR: %0s did not auto re-halt (allhalted=0) %t ns", what, $time);
         error = error + 1;
      end else $display("PASS:  %0s auto re-halted (allhalted=1) %t ns", what, $time);
      read_dcsr;
      if (cause_now !== 3'd4) begin
         $display("ERROR: %0s dcsr.cause=%0d (expected 4=step) %t ns", what, cause_now, $time);
         error = error + 1;
      end else $display("PASS:  %0s dcsr.cause=4 (step) %t ns", what, $time);
      read_dpc;
      if (dpc_now !== dpc_exp) begin
         $display("ERROR: %0s dpc=%h (expected %h) %t ns", what, dpc_now, dpc_exp, $time);
         error = error + 1;
      end else $display("PASS:  %0s dpc=%h as expected %t ns", what, dpc_now, $time);
   end
endtask

localparam [31:0] BAD_TARGET = 32'h00000000;

initial begin
    @(posedge free_clk);
    @(posedge hresetn);
    error_on_exception = 0;   // the step onto address 0 is meant to fault

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG STEP FAULT TARGET: dcsr.step of a jalr into unmapped memory  |");
    $display(" ====================================================================");

    @(probes_cpu.x31==32'h11111111);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: hart did not halt on dmcontrol.haltreq %t ns", $time);
        error = error + 1;
    end
    read_csr(CMD_RD_MTVEC, "mtvec read", mtvec_val);
    $display("       mtvec = %h (trap handler entry)", mtvec_val);

    // --- redirect the spinning jalr to the unmapped address ---
    dmi_write(DMI_DATA0, BAD_TARGET);
    abs_run(CMD_WR_X12);
    chk_cmderr("x12 write");

    abs_run(CMD_RD_DCSR);
    chk_cmderr("dcsr read (pre-set step)");
    dmi_read(DMI_DATA0);
    dmi_write(DMI_DATA0, dmi_readval | DCSR_STEP);
    abs_run(CMD_WR_DCSR);
    chk_cmderr("dcsr write (set step)");

    //========================================================================
    // STEP 1 -- jalr x0, 0(x12): re-halt with dpc == 0
    //========================================================================
    do_step;
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: step 1 (jalr to 0x%h) never re-halted: the hart is wedged %t ns", BAD_TARGET, $time);
        error = error + 1;
        repeat(20) @(posedge free_clk);
        stimulus_done = 1;
    end else begin
        chk_step("step 1 (jalr)", BAD_TARGET);

        //====================================================================
        // STEP 2 -- the fetch at 0 faults: halt at the handler entry
        //====================================================================
        do_step;
        chk_step("step 2 (fetch fault)", mtvec_val);
        read_csr(CMD_RD_MCAUSE, "mcause read", csr_val);
        if (csr_val !== 32'd1) begin
            $display("ERROR: step 2 mcause=%h (expected 1) %t ns", csr_val, $time);
            error = error + 1;
        end else $display("PASS:  step 2 mcause=1 %t ns", $time);
        read_csr(CMD_RD_MEPC, "mepc read", csr_val);
        if (csr_val !== BAD_TARGET) begin
            $display("ERROR: step 2 mepc=%h (expected %h) %t ns", csr_val, BAD_TARGET, $time);
            error = error + 1;
        end else $display("PASS:  step 2 mepc=%h %t ns", csr_val, $time);

        abs_run(CMD_RD_DCSR);
        chk_cmderr("dcsr read (pre-clear step)");
        dmi_read(DMI_DATA0);
        dmi_write(DMI_DATA0, dmi_readval & ~DCSR_STEP);
        abs_run(CMD_WR_DCSR);
        chk_cmderr("dcsr write (clear step)");

        random_irq_enable = 0;
        dm_resume;

        to = 0;
        while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < 5000)) begin
            @(posedge free_clk);
            to = to + 1;
        end
        if (probes_cpu.x31 !== 32'hdeadbeef) begin
            $display("ERROR: firmware never reached the end marker after resume %t ns", $time);
            error = error + 1;
        end
        $display("--- handler entries x23 (expect 1), mcause x20 (expect 1), mepc x22 (expect 0) ---");
        check_cpu_reg(23, 32'h00000001);
        check_cpu_reg(20, 32'h00000001);
        check_cpu_reg(22, BAD_TARGET);

        repeat(20) @(posedge free_clk);
        stimulus_done = 1;
    end
end

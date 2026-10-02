//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      stimulus_act
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: The single stimulus for the RISC-V Architectural Certification
//              Test flow. Unlike sim/rtl_sim/src/*.v there is no per-test
//              oracle here: ACT ELFs are self-checking, so this file only has
//              to boot one, provide the two SoC hooks its RVMODEL macros need,
//              and translate its halt code into the harness verdict.
//
//              Copied to run/<persona>/work/stimulus.v by bin/run_act, which
//              also emits act_image.mem. See sim/arch_test/README.md.
//----------------------------------------------------------------------------

// Halt codes written to peripheral #0 register 0 by RVMODEL_HALT_PASS / _FAIL
// (see arvern/*/rvmodel_macros.h).
localparam [31:0] ACT_HALT_PASS = 32'd123456789;
localparam [31:0] ACT_HALT_FAIL = 32'd1;

integer act_timeout_cycles;

//
// Program load
//---------------------------------
// The ACT image is one contiguous rwx blob in the executable SRAM, not ROM, so
// the testbench's own $readmemh (ROM only) does not cover it.
//
// Deliberately at #1 rather than time 0: tb_arvern.v zero-fills sram_x in a
// time-0 initial block, and two initial blocks writing the same array have
// undefined relative order (the hazard rom.v:50 warns about). Every time-0
// block completes before any #1 event, and reset is still asserted then, so
// this is ordering-safe without touching the testbench.
initial begin
    #1;
    $readmemh("./act_image.mem", ahb_bus_system_inst.sram_x_inst.mem);
end

//
// External-interrupt generator (RVMODEL_SET/CLR_MEXT_INT, SET/CLR_SEXT_INT)
//---------------------------------
// Models the same protocol as sail_macros.h's simple_interrupt_generator, which
// is what raises the interrupts in the REFERENCE run: one address, bit 31 = set
// (1) / clear (0), remaining bits name the interrupt by cause number. The mask
// is accumulated so a source stays asserted until explicitly cleared. A pulse
// instead of a level makes arvern take fewer traps than the reference and shifts
// every subsequent signature record.
//
// MEI/SEI need this because the PLIC pending array is read-only on the bus, so
// firmware cannot raise them directly. MSI/SSI/MTI come from the ACLINT and are
// routed by use_aclint above.
localparam [31:0] ACT_IRQ_ADDR = 32'h10040008;

reg        act_irq_dph;
reg [31:0] act_irq_pending;

always @(posedge dut_hclk or negedge hresetn)
  if (!hresetn)          act_irq_dph <= 1'b0;
  else if (data_hready)  act_irq_dph <= data_htrans[1] & data_hwrite &
                                        (data_haddr == ACT_IRQ_ADDR);

wire        act_irq_wr  = data_hready & act_irq_dph;
wire [31:0] act_irq_bits = data_hwdata & 32'h7FFFFFFF;

// Effective mask includes the write landing THIS cycle. sail_macros.h's
// generator raises the interrupt as the store takes effect; registering first
// would deliver it a cycle later, and these tests write mideleg within a couple
// of instructions of arming a source -- late delivery routes to the wrong
// privilege and the trap sequences diverge.
wire [31:0] act_irq_eff = !act_irq_wr        ? act_irq_pending                :
                           data_hwdata[31]   ? (act_irq_pending |  act_irq_bits)
                                             : (act_irq_pending & ~act_irq_bits);

always @(posedge dut_hclk or negedge hresetn)
  if (!hresetn) act_irq_pending <= 32'h00000000;
  else          act_irq_pending <= act_irq_eff;

// Combinational, deliberately: sail_macros.h's generator raises the interrupt
// as the store completes, and these tests flip mideleg within a few
// instructions of arming a source. An extra register stage here delivers the
// interrupt on the far side of that write, so it routes to the wrong privilege
// and the whole trap sequence diverges from the reference.
//
// WFI wake is unaffected: act_irq_pending is already set by the time the core
// sleeps (the arming store must complete before the WFI retires), so the level
// is held even though its own clock has stopped.
always @* begin
    irq_m_external = act_irq_eff[11];   // cause 11 = MEI
    irq_s_external = act_irq_eff[9];    // cause  9 = SEI
end

//
// RVMODEL_IO_WRITE_STR sink
//---------------------------------
// ACT tests print a detailed failure report (failing instruction, expected vs
// actual) through RVMODEL_IO_WRITE_STR before halting. That is by far the most
// useful diagnostic the suite produces, so it must not be dropped.
//
// The macro stores one character at a time to peripheral #0 register 1, so the
// AHB write is snooped rather than the register output watched: two identical
// characters in a row produce no change on periph0_reg_01_out and would be lost.
// Address phase is registered and the data captured in the following data phase,
// per AHB pipelining.
localparam [31:0] ACT_IO_ADDR = 32'h10040004;

reg act_io_dph;

always @(posedge dut_hclk or negedge hresetn)
  if (!hresetn)          act_io_dph <= 1'b0;
  else if (data_hready)  act_io_dph <= data_htrans[1] & data_hwrite &
                                       (data_haddr == ACT_IO_ADDR);

always @(posedge dut_hclk)
  if (data_hready & act_io_dph)
    $write("%c", data_hwdata[7:0]);

//
// Verdict
//---------------------------------
initial begin
    // Past #1 for the same reason as the image load above: tb_arvern.v assigns
    // both of these in its own time-0 initial block (lines 571/580), and the
    // relative order of two initial blocks at time 0 is undefined -- setting
    // them at time 0 here gets silently overwritten about half the time.
    #1;
    random_irq_enable  = 0;  // ACT tests own their trap handlers end to end

    // Route the ACLINT's MSIP / SETSSIP / MTIP outputs to the core. Without
    // this the mux in tb_arvern.v leaves them on the unused stimulus regs, so
    // RVMODEL_SET_MSW_INT, RVMODEL_SET_SSW_INT and the MTIME/MTIMECMP timer all
    // write the ACLINT successfully but no interrupt ever reaches the hart.
    // use_plic stays 0: MEI/SEI are driven directly from the peripheral hooks
    // above, and that mux is independent of this one.
    use_aclint         = 1;

    // Single-hart platform, so mhartid must be 0: the spec requires at least one
    // hart to have ID zero, and the reference models hartid 0 (sail.json). The
    // testbench default is a deliberately non-zero 0x23. Sm_mcsr-00's
    // mhartid_csrrw1 coverpoint compares the two.
    hartid             = 8'h00;

    // ACT tests take exceptions deliberately -- ECALL, illegal instruction and
    // misaligned accesses are the subject matter, not faults. The ELF's own
    // self-check is the oracle, so the exception monitors must not also vote.
    error_on_exception = 0;

    // Peripheral #0 is the platform's halt/console/interrupt-generator device, which
    // the firmware writes from whatever privilege it runs in (RVMODEL_SET_*_INT from a
    // U-mode test body, for instance) -- like the reference's interrupt generator.
    // Its MDELEG gate resets to M-mode only and answers a denied access with an AHB
    // ERROR, which the core reports as a data-bus RNMI the test does not expect.
    // Open it to every privilege for the arch-test platform.
    force ahb_bus_system_inst.ahb_periph_example_inst0.mdeleg_wr_priv = 2'b00;
    force ahb_bus_system_inst.ahb_periph_example_inst0.mdeleg_rd_priv = 2'b00;

    @(posedge hresetn);

`ifdef ARV_ACT_FORCE_NMIE1
    // Personas with NMI_EN=1 only. Smrnmi says mnstatus.NMIE resets to 0 and that
    // "when NMIE=0, all interrupts are disabled" -- arv_csr_traps.v gates
    // irq_detect on it. Firmware is expected to enable NMIE (it is software-set-
    // only, or set by mnret), but the ACT tests know nothing about Smrnmi and
    // never do, so out of reset NOT ONE interrupt is ever delivered: every
    // Interrupts* test records zero traps. The reference has no Smrnmi at all
    // (absent from sail-riscv 0.13.1's config schema), so its interrupts are
    // always enabled. Forcing NMIE=1 presents the same machine.
    //
    // Remove when sail models Smrnmi; until then aRVern's RNMI behaviour is NOT
    // exercised by the suite. Covered instead by the trap_smrnmi_* tests in
    // sim/rtl_sim/src.
    @(negedge dut_hclk);
    force dut.arv_csr_top_inst.arv_csr_traps_inst.gen_nmi.mnstatus_nmie_reg = 1'b1;
    $display("ACT-INFO: mnstatus.NMIE forced to 1 (Smrnmi not modelled by the reference)");
`endif

`ifdef ARV_ACT_FORCE_DTE0
    // EXPERIMENT (opt-in, off by default): clear menvcfgh.DTE so Ssdbltrp is
    // disabled and the core does the spec-literal horizontal delegation.
    //
    // aRVern resets DTE to 1 (protection-by-default -- see doc/spec_compliance
    // _notes.md), but sail_riscv 0.13.1 cannot model Ssdbltrp at all, so the
    // reference behaves as a DTE=0 machine. Forcing it here makes the two agree
    // on double traps, which lets Sm_mcsr-00 run PAST that divergence and show
    // whatever else it would have caught.
     @(negedge dut_hclk);
    force dut.arv_csr_top_inst.arv_csr_traps_inst.g_ssdbltrp.menvcfgh_dte = 1'b0;
    $display("ACT-INFO: menvcfgh.DTE forced to 0 (Ssdbltrp disabled for this run)");
`endif

    // Smdbltrp: hold mstatush.MDT at 0 for the whole run.
    //
    // MDT resets to 1 and is the only implemented bit of mstatush, so Sm_mcsr-00
    // -- which writes all-ones and compares the raw read-back against the model --
    // sees 0x400 where the reference expects 0. sail-riscv does not model Smdbltrp
    // at any release: in 0.14 the MDT / SDT / DTE fields are commented out of the
    // Mstatus bitfield and there is no dbltrp source. Upgrading the pin does not
    // help.
    //
    // Holding MDT low presents the same machine the reference models: no double-trap
    // arming, mstatush reads 0. This DISABLES Smdbltrp for the run, exactly as the
    // DTE force disables Ssdbltrp -- the suite does not exercise it, and the pass
    // count must be read with that in mind.
    //
    // Remove when sail models Smdbltrp. Until then aRVern's double-trap behaviour is
    // covered only by trap_m_dbltrp_* in sim/rtl_sim/src.
    @(negedge dut_hclk);
    force dut.arv_csr_top_inst.arv_csr_traps_inst.mstatush_mdt = 1'b0;
    $display("ACT-INFO: mstatush.MDT forced to 0 (Smdbltrp not modelled by the reference)");

    // The test writes its halt code to peripheral #0 register 0 and then spins.
    // A run that never writes one is a hang, not a pass, so bound the wait.
    //
    // `lockup` is watched alongside it because it is a terminal state, not a
    // slow one: aRVern asserts it when a synchronous exception arrives while an
    // M-mode exception handler has yet to make progress, and only reset clears
    // it (doc/traps_and_interrupts.md section 10). Waiting out the cycle budget
    // after that just turns a precise diagnosis into a generic timeout -- and an
    // expensive one, since these tests are among the slowest to simulate.
    act_timeout_cycles = 0;
    while ((periph0_reg_00_out !== ACT_HALT_PASS) &&
           (periph0_reg_00_out !== ACT_HALT_FAIL) &&
           (lockup             !== 1'b1        ) &&
           (act_timeout_cycles  <  `ACT_TIMEOUT_CYCLES)) begin
        @(posedge free_clk);
        act_timeout_cycles = act_timeout_cycles + 1;
    end

    if (periph0_reg_00_out === ACT_HALT_PASS) begin
        $display("ACT: RVMODEL_HALT_PASS");
    end
    else if (periph0_reg_00_out === ACT_HALT_FAIL) begin
        $display("ACT: RVMODEL_HALT_FAIL -- self-check failed");
        error = error + 1;
    end
    else if (lockup === 1'b1) begin
        $display("ACT: LOCKUP after %0d cycles -- core halted on trap re-entry",
                 act_timeout_cycles);
        error = error + 1;
    end
    else begin
        $display("ACT: TIMEOUT after %0d cycles -- no halt code written",
                 act_timeout_cycles);
        error = error + 1;
    end

    // Signature dump for reference comparison. Only built when run_act passes
    // the symbol bounds (--sigdump), because it is a debugging aid: the normal
    // flow runs self-checking ELFs that need no signature at all. Format matches
    // sail_riscv_sim --test-signature (one 8-hex-digit word per line) so the two
    // can be diffed directly.
`ifdef ACT_SIG_BEGIN
    begin : act_sig_dump
        integer sig_fh;
        integer sig_addr;
        sig_fh = $fopen("act_signature.txt", "w");
        for (sig_addr = `ACT_SIG_BEGIN; sig_addr < `ACT_SIG_END; sig_addr = sig_addr + 4)
            $fwrite(sig_fh, "%08x\n",
                    ahb_bus_system_inst.sram_x_inst.mem[(sig_addr - 32'h80000000) >> 2]);
        $fclose(sig_fh);
        $display("ACT: signature dumped (%0d words)",
                 (`ACT_SIG_END - `ACT_SIG_BEGIN) / 4);
    end
`endif

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

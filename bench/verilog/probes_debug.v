//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    probes_debug
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : probes_debug.v
// Module Description : External-debug event tracer -> pitstop.log.
//
//   Companion to probes_instructions.v (asphalt.log). The instruction trace goes
//   dark while the hart is halted in Debug Mode -- exactly where the Debug Module
//   is busy. This probe fills that gap: it decodes the external-debug activity and
//   emits one cycle-stamped line per event, so a debug session reads as a single
//   time-ordered story once merged with asphalt.log (asphalt_summary/context do
//   the cycle-merge).
//
//   PORTABILITY / USAGE:
//     Instantiate once in the testbench, port-less, alongside probes_instructions:
//         probes_debug #(.DEBUG_EN(DEBUG_EN)) probes_debug ();
//     It reaches into the core by cross-module reference rooted at the `ARV_CPU_INST
//     macro (default `dut`) -- the SAME knob probes_instructions uses. A different
//     testbench hierarchy just overrides it: +define+ARV_CPU_INST=my_soc.u_cpu.
//     Pass the core's DEBUG_EN straight through so the two never drift: when
//     DEBUG_EN=0 the hart-side ground-truth taps sit in an un-taken generate branch
//     and are never elaborated (so the pruned g_debug hierarchy is not referenced),
//     while the boundary taps (DMI APB + SBA on the data bus) stay valid because
//     those are always-present top-level ports.
//
//   WHAT IT LOGS (three sources):
//     DMI  - every completed DMI/APB transaction (the debugger's whole conversation
//            with the DM): dmcontrol/dmstatus/abstractcs/command/data0/sbcs/...,
//            decoded (halt/resume, abstract Access-Register, cmderr, sberror, ...).
//     SBA  - System Bus Access transactions seen on the data AHB bus, tagged by
//            data_hmaster_o=1 (address, r/w, size, data, OKAY/ERROR incl. waits).
//     DBG  - hart-side ground truth (DEBUG_EN=1 only): Debug-Mode enter (with dcsr
//            cause + captured dpc) and exit/resume.
//
//   Disabled by defining NOTRACE (same as asphalt.log; regressions set it).
//----------------------------------------------------------------------------

`ifndef ARV_CPU_INST
  `define ARV_CPU_INST dut
`endif

module probes_debug #(
  parameter DEBUG_EN = 0,
  parameter LOGFILE  = "pitstop.log"
);

  integer dbg_fd;

  // Flush + close. Defined unconditionally so the testbench end-of-sim hook always
  // resolves, even under NOTRACE (where the body is a no-op).
  task trace_flush_and_close;
    begin
`ifndef NOTRACE
      $fflush(dbg_fd);
      $fclose(dbg_fd);
`endif
    end
  endtask

`ifndef NOTRACE

  //--------------------------------------------------------------------------
  // Cycle counter -- counted exactly like probes_instructions' trace_cycle
  // (same clock, same reset, free-running) so pitstop.log cycles line up
  // 1:1 with asphalt.log for the merge.
  //--------------------------------------------------------------------------
  wire        dbg_clk    = `ARV_CPU_INST.arv_decode_inst.hclk_i;
  wire        dbg_resetn = `ARV_CPU_INST.arv_decode_inst.hresetn_i;
  reg  [63:0] dbg_cycle;

  always @(posedge dbg_clk or negedge dbg_resetn)
    if (!dbg_resetn) dbg_cycle <= 64'd0;
    else             dbg_cycle <= dbg_cycle + 64'd1;

  //--------------------------------------------------------------------------
  // Boundary source 1: DMI / APB slave (always present -- top-level ports).
  // An APB transfer completes when PSEL & PENABLE & PREADY. Reg index = PADDR[8:2].
  //--------------------------------------------------------------------------
  wire        d_psel    = `ARV_CPU_INST.dmi_psel_i;
  wire        d_penable = `ARV_CPU_INST.dmi_penable_i;
  wire        d_pready  = `ARV_CPU_INST.dmi_pready_o;
  wire        d_pwrite  = `ARV_CPU_INST.dmi_pwrite_i;
  wire  [6:0] d_ridx    = `ARV_CPU_INST.dmi_paddr_i[8:2];
  wire [31:0] d_pwdata  = `ARV_CPU_INST.dmi_pwdata_i;
  wire [31:0] d_prdata  = `ARV_CPU_INST.dmi_prdata_o;

  reg [31:0] dval;

  always @(posedge dbg_clk) begin
    if (dbg_resetn && d_psel && d_penable && d_pready) begin
      dval = d_pwrite ? d_pwdata : d_prdata;

      $fwrite(dbg_fd, "%12d  DMI  ", dbg_cycle);
      if (d_pwrite) $fwrite(dbg_fd, "WR "); else $fwrite(dbg_fd, "RD ");

      case (d_ridx)                                   // register name (column-padded)
        7'h04: $fwrite(dbg_fd, "data0     ");
        7'h10: $fwrite(dbg_fd, "dmcontrol ");
        7'h11: $fwrite(dbg_fd, "dmstatus  ");
        7'h12: $fwrite(dbg_fd, "hartinfo  ");
        7'h16: $fwrite(dbg_fd, "abstractcs");
        7'h17: $fwrite(dbg_fd, "command   ");
        7'h18: $fwrite(dbg_fd, "abstauto  ");
        7'h38: $fwrite(dbg_fd, "sbcs      ");
        7'h39: $fwrite(dbg_fd, "sbaddress0");
        7'h3c: $fwrite(dbg_fd, "sbdata0   ");
        default: $fwrite(dbg_fd, "reg[0x%02x]", d_ridx);
      endcase

      $fwrite(dbg_fd, " = 0x%08x", dval);

      case (d_ridx)                                   // decoded note for key registers
        7'h10: if (d_pwrite)
                 $fwrite(dbg_fd, "   # halt=%0d resume=%0d ndmreset=%0d dmactive=%0d ackhavereset=%0d",
                         dval[31], dval[30], dval[1], dval[0], dval[28]);
        7'h11: $fwrite(dbg_fd, "   # allhalted=%0d allrunning=%0d allhavereset=%0d allresumeack=%0d",
                       dval[9], dval[11], dval[19], dval[17]);
        7'h16: $fwrite(dbg_fd, "   # busy=%0d cmderr=%0d", dval[12], dval[10:8]);
        7'h17: if (d_pwrite) begin                    // abstract command (Access Register = cmdtype 0)
                 if (dval[31:24] == 8'd0) begin
                   if ((dval[15:0] >= 16'h1000) && (dval[15:0] <= 16'h101f))
                     $fwrite(dbg_fd, "   # AccessReg wr=%0d x%0d aarsize=%0d",
                             dval[16], dval[15:0] - 16'h1000, dval[22:20]);
                   else
                     $fwrite(dbg_fd, "   # AccessReg wr=%0d csr=0x%03x aarsize=%0d",
                             dval[16], dval[11:0], dval[22:20]);
                 end else
                   $fwrite(dbg_fd, "   # cmdtype=%0d", dval[31:24]);
               end
        7'h38: $fwrite(dbg_fd, "   # sberror=%0d sbbusy=%0d", dval[14:12], dval[21]);
        default: ;
      endcase

      $fwrite(dbg_fd, "\n");
    end
  end

  //--------------------------------------------------------------------------
  // Boundary source 2: SBA transactions on the data AHB bus (always present).
  // Tagged by data_hmaster_o=1. Simple AHB monitor: latch the address phase,
  // report at data-phase completion (captures wait states and HRESP errors).
  //--------------------------------------------------------------------------
  wire  [1:0] s_htrans = `ARV_CPU_INST.data_htrans_o;
  wire        s_hwrite = `ARV_CPU_INST.data_hwrite_o;
  wire [31:0] s_haddr  = `ARV_CPU_INST.data_haddr_o;
  wire  [2:0] s_hsize  = `ARV_CPU_INST.data_hsize_o;
  wire [31:0] s_hwdata = `ARV_CPU_INST.data_hwdata_o;
  wire [31:0] s_hrdata = `ARV_CPU_INST.data_hrdata_i;
  wire        s_hready = `ARV_CPU_INST.data_hready_i;
  wire        s_hresp  = `ARV_CPU_INST.data_hresp_i;
  wire        s_hmaster= `ARV_CPU_INST.data_hmaster_o;

  reg        sba_pend;
  reg [31:0] sba_addr;
  reg        sba_wr;
  reg  [2:0] sba_sz;

  always @(posedge dbg_clk) begin
    if (!dbg_resetn) begin
      sba_pend <= 1'b0;
    end else begin
      if (sba_pend && s_hready) begin                 // data phase of the pending access
        $fwrite(dbg_fd, "%12d  SBA  ", dbg_cycle);
        if (sba_wr) $fwrite(dbg_fd, "WR "); else $fwrite(dbg_fd, "RD ");
        $fwrite(dbg_fd, "[0x%08x] = 0x%08x  sz=%0d  ",
                sba_addr, sba_wr ? s_hwdata : s_hrdata, (32'd1 << sba_sz));
        if (s_hresp) $fwrite(dbg_fd, "ERROR\n"); else $fwrite(dbg_fd, "OKAY\n");
        sba_pend <= 1'b0;
      end
      if (s_hmaster && (s_htrans == 2'b10) && s_hready) begin   // address phase accepted (NONSEQ)
        sba_addr <= s_haddr;
        sba_wr   <= s_hwrite;
        sba_sz   <= s_hsize;
        sba_pend <= 1'b1;
      end
    end
  end

  //--------------------------------------------------------------------------
  // Ground-truth source: hart-side Debug-Mode state (DEBUG_EN=1 only).
  // The reach-ins live in an un-taken generate branch when DEBUG_EN=0, so the
  // pruned g_debug hierarchy is never referenced there.
  //--------------------------------------------------------------------------
  generate
    if (DEBUG_EN) begin : g_internal
      wire        dm_mode  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.g_debug.u_arv_csr_debug.debug_mode_q;
      wire  [2:0] dm_cause = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.g_debug.u_arv_csr_debug.dcsr_cause;
      wire [31:0] dm_dpc   = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.g_debug.u_arv_csr_debug.dpc_q;
      wire        dm_dpcv  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.g_debug.u_arv_csr_debug.dpc_captured_q;

      reg dm_entered;   // ENTER already logged for this halt
      reg dm_mode_r;    // previous debug_mode_q (edge detect)

      always @(posedge dbg_clk) begin
        if (!dbg_resetn) begin
          dm_entered <= 1'b0;
          dm_mode_r  <= 1'b0;
        end else begin
          // ENTER: log once dpc is captured (cause + dpc valid).
          if (dm_mode && dm_dpcv && !dm_entered) begin
            $fwrite(dbg_fd, "%12d  DBG  ENTER Debug Mode  cause=", dbg_cycle);
            case (dm_cause)
              3'd1: $fwrite(dbg_fd, "ebreak");
              3'd2: $fwrite(dbg_fd, "trigger");
              3'd3: $fwrite(dbg_fd, "haltreq");
              3'd4: $fwrite(dbg_fd, "step");
              3'd5: $fwrite(dbg_fd, "resethaltreq");
              3'd6: $fwrite(dbg_fd, "group");
              default: $fwrite(dbg_fd, "%0d", dm_cause);
            endcase
            $fwrite(dbg_fd, "  dpc=0x%08x\n", dm_dpc);
            dm_entered <= 1'b1;
          end
          // EXIT: debug_mode falls.
          if (!dm_mode && dm_mode_r)
            $fwrite(dbg_fd, "%12d  DBG  EXIT  Debug Mode  (resume)\n", dbg_cycle);
          if (!dm_mode) dm_entered <= 1'b0;    // rearm for the next halt
          dm_mode_r <= dm_mode;
        end
      end
    end
  endgenerate

  //--------------------------------------------------------------------------
  // File + header.
  //--------------------------------------------------------------------------
  initial begin
    dbg_fd    = $fopen(LOGFILE, "w");
    dbg_cycle = 64'd0;
    sba_pend  = 1'b0;
    $fdisplay(dbg_fd, "# ============================================================================");
    $fdisplay(dbg_fd, "# arvern External-Debug Trace  (companion to asphalt.log; merge by cycle)");
    $fdisplay(dbg_fd, "# ============================================================================");
    $fdisplay(dbg_fd, "#   cycle : clock cycle (same basis as asphalt.log)");
    $fdisplay(dbg_fd, "#   DMI   : completed DMI/APB transaction  (WR/RD reg = value  # decode)");
    $fdisplay(dbg_fd, "#   SBA   : System Bus Access on the data AHB bus (data_hmaster=1)");
    $fdisplay(dbg_fd, "#   DBG   : hart-side Debug-Mode enter/exit (ground truth, DEBUG_EN=1)");
    $fdisplay(dbg_fd, "#   dcsr.cause: 1=ebreak 2=trigger 3=haltreq 4=step 5=resethaltreq 6=group");
    $fdisplay(dbg_fd, "# ----------------------------------------------------------------------------");
  end

`endif // NOTRACE

endmodule

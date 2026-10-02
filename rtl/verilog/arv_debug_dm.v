//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    arv_debug_dm
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : arv_debug_dm.v
// Module Description : RISC-V Debug Module (DM, Debug Spec 1.0). Single hart,
//                      frozen-hart model - no Program Buffer / debug ROM; the halted
//                      hart is accessed through side-ports.
//
//                      Contains the hclk-domain DMI register file, run control
//                      (halt / resume / reset-request + status), the abstract
//                      Access-Register engine (GPR, debug-CSR and general-CSR
//                      side-ports; one busy cycle while the hart is halted+drained)
//                      and the SBA child (arv_debug_sba). DMI register maps, cmderr
//                      codes and per-field detail live at each point of use below.
//
//                      DMI bus: an APB4 slave port in the hclk domain; the DTM owns
//                      the TCK->hclk CDC above it.
//
//                      Reset domain (key invariant): the DM runs on dbgresetn_i, NOT
//                      the hart's hresetn_i, so it SURVIVES an ndmreset (the SoC loops
//                      ndmreset onto hresetn while holding dbgresetn high) - the
//                      debugger stays attached and resethaltreq is remembered across
//                      the reset it triggers. dmactive is a second level: DM state
//                      resets on (~dbgresetn | ~dmactive), while dmactive and the DMI
//                      handshake flops reset on ~dbgresetn alone so the bus can raise
//                      dmactive.
//
//                      Built only when DEBUG_EN=1 (else not instantiated, DMI bus tied
//                      off -> bit-identical core).
//
//                      NOTE: DMI_ABITS sizes the dmi_paddr_i port, forcing an ANSI
//                      #(...) param header here, a deliberate local exception to the
//                      house in-body-parameter style (CUSTOM-012).
//----------------------------------------------------------------------------
`default_nettype none

module  arv_debug_dm #(
    parameter                    ARST_EN   = 1'b1,          // Reset style: 1=async, 0=sync (matches arv_dff)
    parameter                    DMI_ABITS = 7,             // DMI address width
    parameter                    RV32I_EN  = 1'b1           // 0: RV32E, x16-x31 do not exist
) (

// Clock / reset (hclk domain)
    input  wire                  hclk_i,
    input  wire                  dbgresetn_i,               // DEBUG reset (the DM survives ndmreset; see header)
    input  wire                  hart_resetn_i,             // the hart's hresetn_i (same hclk domain per the integration contract)

// DMI bus - APB4 slave, hclk domain (PCLK=hclk_i, PRESETn=dbgresetn_i).
    input  wire                  dmi_psel_i,                // APB select
    input  wire                  dmi_penable_i,             // APB enable (ACCESS phase)
    input  wire [DMI_ABITS+1:0]  dmi_paddr_i,               // APB byte address (reg index = [DMI_ABITS+1:2])
    input  wire                  dmi_pwrite_i,              // 1=write, 0=read
    input  wire           [31:0] dmi_pwdata_i,              // APB write data
    input  wire            [2:0] dmi_pprot_i,               // APB protection (standard APB4 signal; ignored)
    output wire                  dmi_pready_o,              // APB ready (1 wait state)
    output wire           [31:0] dmi_prdata_o,              // APB read data
    output wire                  dmi_pslverr_o,             // APB slave error (tied 0; future fault hook)

// Hart run-control interface (hart side = arv_csr_top / arv_csr_debug)
    output wire                  dm_haltreq_o,              // halt request (level) -> hart debug_req
    output wire                  dm_resumereq_o,            // resume request (level held until hart runs)
    input  wire                  hart_halted_i,             // hart is halted in Debug Mode (drain-qualified)
    input  wire                  hart_debug_mode_i,         // hart is in Debug Mode

// Platform reset request
    output wire                  dm_ndmreset_o,             // dmcontrol.ndmreset (system reset, not the DM)
    output wire                  dm_resethaltreq_o,         // resethaltreq state -> hart halts out of reset (cause=5)

// Abstract Access Register GPR side-port (to arv_int_registers). Driven only while
// the hart is halted+drained; the access completes in a single busy cycle.
    output wire                  dm_gpr_wen_o,              // GPR write strobe (busy cycle of a write command)
    output wire            [4:0] dm_gpr_waddr_o,            // GPR write index (regno[4:0])
    output wire           [31:0] dm_gpr_wdata_o,            // GPR write data (= data0)
    output wire            [4:0] dm_gpr_raddr_o,            // GPR read index (regno[4:0])
    output wire                  dm_gpr_ren_o,              // GPR read active (busy cycle of a read command) -> steals the ex_reg_src2 read port
    input  wire           [31:0] dm_gpr_rdata_i,            // GPR read data (combinational)

// Abstract Access Register debug-CSR side-port (to arv_csr_debug via arv_csr_top).
    output wire                  dm_csr_access_o,           // DM is accessing a debug CSR this busy cycle
    output wire            [1:0] dm_csr_sel_o,              // 0=dcsr 1=dpc; 2/3=dscratch0/1 (not implemented -> RAZ/WI)
    output wire                  dm_csr_wen_o,              // 1=write, 0=read
    output wire           [31:0] dm_csr_wdata_o,            // debug-CSR write data (= data0)
    input  wire           [31:0] dm_csr_rdata_i,            // debug-CSR read data (combinational)

// Abstract Access Register general-CSR side-port (to arv_csr_top EX datapath). A
// supported CSR (regno 0x000..0xfff, excluding the debug CSRs and time/timeh) is
// read/written through the real CSR datapath while the hart is frozen; the read
// value is combinational and a write commits in the busy cycle. dm_acsr_fault_i
// reports a structural fault (nonexistent / read-only / absent CSR) -> cmderr=3.
    output wire                  dm_acsr_active_o,          // drive the EX CSR datapath this busy cycle
    output wire           [11:0] dm_acsr_addr_o,            // CSR address (regno[11:0])
    output wire                  dm_acsr_wen_o,             // 1=write (csrrw), 0=read (csrrs)
    output wire           [31:0] dm_acsr_wdata_o,           // CSR write data (= data0)
    input  wire           [31:0] dm_acsr_rdata_i,           // CSR read data (combinational)
    input  wire                  dm_acsr_fault_i,           // structural fault for this access

// System Bus Access AHB-Lite master. Muxed onto the core data port at the arvern top
// level, which arbitrates it against the hart's load/store unit (req/gnt below), so the
// engine works with the hart halted or running. The mux select dm_sb_active_o is also
// exported as the data_hmaster_o sideband so the SoC fabric can apply memory protection
// to debugger accesses.
    output wire                  dm_sb_busy_o,              // 1 = an SBA access is accepted and not yet complete
    output wire                  dm_sb_req_o,               // 1 = engine wants the data bus
    input  wire                  dm_sb_gnt_i,               // 1 = arbiter hands the bus over from the next cycle
    output wire                  dm_sb_active_o,            // 1 = SBA owns the data bus this cycle (mux select)
    output wire           [31:0] dm_sb_haddr_o,
    output wire            [1:0] dm_sb_htrans_o,
    output wire                  dm_sb_hwrite_o,
    output wire            [2:0] dm_sb_hsize_o,
    output wire            [2:0] dm_sb_hburst_o,
    output wire           [31:0] dm_sb_hwdata_o,
    input  wire           [31:0] dm_sb_hrdata_i,
    input  wire                  dm_sb_hready_i,
    input  wire                  dm_sb_hresp_i

);

//////======================================================================================================================//////
//////    DMI register addresses (spec 1.0)                                                                                 //////
//////======================================================================================================================//////
localparam [6:0] DMI_DATA0       = 7'h04;
localparam [6:0] DMI_DMCONTROL   = 7'h10;
localparam [6:0] DMI_DMSTATUS    = 7'h11;
localparam [6:0] DMI_ABSTRACTCS  = 7'h16;
localparam [6:0] DMI_COMMAND     = 7'h17;
localparam [6:0] DMI_ABSTRACTAUTO= 7'h18;
localparam [6:0] DMI_SBCS        = 7'h38;
localparam [6:0] DMI_HALTSUM0    = 7'h40;
localparam [6:0] DMI_SBADDRESS0  = 7'h39;
localparam [6:0] DMI_SBDATA0     = 7'h3c;

//////======================================================================================================================//////
//////    APB4 slave front-end - accept in the ACCESS phase, 1 wait state (response registered next cycle)                  //////
//////======================================================================================================================//////
// APB: SETUP (PSEL & ~PENABLE) then ACCESS (PSEL & PENABLE); transfer completes on PENABLE & PREADY.
// accept pulses once on the first ACCESS cycle (before PREADY); the registered response drives PREADY
// the next cycle, so writes/reads take effect only in the ACCESS phase (no SETUP-phase side effects).
wire        rsp_valid_q;
wire        accept          = dmi_psel_i & dmi_penable_i & ~dmi_pready_o;
wire        is_write        = accept &  dmi_pwrite_i;
wire        is_read         = accept & ~dmi_pwrite_i;
wire [6:0]  addr7           = dmi_paddr_i[8:2];           // DMI_ABITS=7 (the only supported width): reg index in PADDR[8:2]
wire [1:0]  dmi_paddr_lsb_unused = dmi_paddr_i[1:0];      // APB byte offset within a word; word-addressed regs ignore it
wire [2:0]  dmi_pprot_unused = dmi_pprot_i;               // standard APB4 signal, ignored; tie off lint

// DMI_ABITS is supported at exactly 7
generate
if (DMI_ABITS > 7) begin : g_dmi_abits_wide
    wire [DMI_ABITS-8:0] dmi_paddr_hi_unused = dmi_paddr_i[DMI_ABITS+1:9];
end
endgenerate

// Per-register write strobes (only the addressed register, only on a write accept)
wire        wr_dmcontrol    = is_write & (addr7 == DMI_DMCONTROL);
wire        wr_abstractcs   = is_write & (addr7 == DMI_ABSTRACTCS);
wire        wr_command      = is_write & (addr7 == DMI_COMMAND);
wire        wr_data0        = is_write & (addr7 == DMI_DATA0);
wire        wr_abstractauto = is_write & (addr7 == DMI_ABSTRACTAUTO);
// dmstatus is read-only.

//////======================================================================================================================//////
//////    dmactive (DMI 0x10[0]) - the ONLY bit alive while the DM is in reset. Resets on ~dbgresetn only.                  //////
//////======================================================================================================================//////
wire        dmactive_q;
arv_dff #(.ARST_EN(ARST_EN)) u_dmactive (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .en_i(wr_dmcontrol),
                                                 .d_i (dmi_pwdata_i[0]), .q_o(dmactive_q));

// Synchronous soft-reset term for all other DM/SBA architectural state
wire        dm_sinit        = ~dmactive_q;

//////======================================================================================================================//////
////// dmcontrol architectural fields (soft-reset via sinit while dmactive=0). Single hart: hartsel/hasel/hartreset RAZ/WI. //////
//////======================================================================================================================//////
// Fields written in the same DMI transaction that sets dmactive 0->1 are cleared by the sinit
// flush (dm_sinit is still asserted on that write cycle): the debugger must set dmactive first,
// poll it back as 1, and only then program the other dmcontrol fields.
wire        haltreq_q;
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_haltreq (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(wr_dmcontrol),
                                                                     .d_i (dmi_pwdata_i[31]), .q_o(haltreq_q));
assign      dm_haltreq_o       = haltreq_q;

wire        ndmreset_q;
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_ndmreset (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(wr_dmcontrol),
                                                                     .d_i (dmi_pwdata_i[1]), .q_o(ndmreset_q));
assign      dm_ndmreset_o      = ndmreset_q;

// resethaltreq[3]=setresethaltreq / [2]=clrresethaltreq : write-1 set/clear PAIR controlling a single
// internal per-hart "halt-on-reset" state bit (spec: state is not readable). clrresethaltreq WINS if
// both are written. Soft-reset via sinit so a DM reset (dmactive=0 or ~dbgresetn) clears it -- but NOT the
// ndmreset it acts on (that arrives on the hart's hresetn, which does not reset the DM), so the
// request correctly SURVIVES the reset that halts the hart.
wire        resethaltreq_q;
wire        resethaltreq_set   = wr_dmcontrol & dmi_pwdata_i[3] & ~dmi_pwdata_i[2];
wire        resethaltreq_clr   = wr_dmcontrol & dmi_pwdata_i[2];
wire        resethaltreq_en    = resethaltreq_set | resethaltreq_clr;
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_resethaltreq (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(resethaltreq_en),
                                                                     .d_i (resethaltreq_set), .q_o(resethaltreq_q));
assign      dm_resethaltreq_o  = resethaltreq_q;

//////======================================================================================================================//////
//////    Resume handshake. resumereq is W1 + self-clearing via the resumeack handshake. The hart sees a LEVEL held until   //////
//////    it leaves Debug Mode, then deasserted. allresumeack latches when the resume completes.                            //////
//////======================================================================================================================//////
wire        req_resume         = wr_dmcontrol & dmi_pwdata_i[30];   // debugger asserts resumereq
wire        resume_pending_q;
wire        resumeack_q;
wire        sb_busy;                                       // SBA transfer in flight (from arv_debug_sba); gates resume so the hart cannot leave Debug Mode mid-transfer
wire        busy_q;
wire        start_run;

// resume completes when a pending resume sees the hart leave Debug Mode.
wire        resume_done        = resume_pending_q & ~hart_debug_mode_i;

// "resumereq is ignored if haltreq is set" (Debug Spec 1.0, dmcontrol.resumereq): a write
// carrying both haltreq=1 and resumereq=1 latches only haltreq (no pending resume, no
// resumeack update). A write with haltreq=0 clears the request and its resumereq is honoured.
wire        resume_pending_set = req_resume & hart_halted_i         // only meaningful while halted
                                            & ~dmi_pwdata_i[31];    // "resumereq is ignored if haltreq is set": the WRITTEN haltreq of this access
wire        resume_pending_en  = resume_pending_set | resume_done;
wire        resume_pending_nxt = resume_pending_set;            // 1 on request, 0 on completion
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_resume_pending (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(resume_pending_en),
                                                                     .d_i (resume_pending_nxt), .q_o(resume_pending_q));
// Hold resume off while an SBA transfer is outstanding, so a resume never races an in-flight
// debugger access (the shared data port is arbitrated at arvern, so this is not needed for bus
// safety). Likewise held off across an abstract command's start (start_run) and busy (busy_q)
// cycles: those cycles own the GPR/CSR side-ports, which are valid only while the hart is
// halted+drained - redirecting the hart out of Debug Mode there would corrupt the access.
// resume_pending_q stays latched, so the hart resumes as soon as the engine drains.
assign      dm_resumereq_o     = resume_pending_q & ~sb_busy & ~busy_q & ~start_run;

wire        resumeack_en       = resume_pending_set | resume_done;
wire        resumeack_nxt      = resume_done;                        // set when done, cleared on new request
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_resumeack (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(resumeack_en),
                                                                     .d_i (resumeack_nxt), .q_o(resumeack_q));

//////=======================================================================================================================//////
//////    havereset sticky tracker - initialises SET (the hart "has reset and not acknowledged"); cleared by ackhavereset.   //////
//////    RE-SET while the hart is in reset from EITHER source: ndmreset (the SoC hresetn loopback) or a SoC-initiated       //////
//////    hart-only reset observed on hart_resetn_i - the DM survives both (dbgresetn domain), so it must record that a      //////
//////    reset occurred -> a reset-halt then reads allhavereset=1. An in-flight reset outranks ack (it can't be             //////
//////    acknowledged away).                                                                                                //////
//////=======================================================================================================================//////

wire        hart_alive_q;
arv_dff #(.RST_VAL(1'b0), .ARST_EN(ARST_EN)) u_hart_alive (
          .clk_i(hclk_i), .rst_n_i(hart_resetn_i), .en_i(1'b1),
                                                   .d_i (1'b1), .q_o(hart_alive_q));

wire        hart_in_reset = ndmreset_q | ~hart_alive_q;             // hart reset in flight (either source)

wire        havereset_q;
wire        ack_havereset = wr_dmcontrol & dmi_pwdata_i[28];
wire        havereset_en  = ack_havereset | hart_in_reset;
wire        havereset_nxt = hart_in_reset;                           // set while the hart is in reset, else clear on ack
arv_dff_sinit #(.RST_VAL(1'b1), .ARST_EN(ARST_EN)) u_havereset (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(havereset_en),
                                                                     .d_i (havereset_nxt), .q_o(havereset_q));

//////=======================================================================================================================//////
//////    abstractauto (DMI 0x18) - abstractautoexec. There is exactly one data register (data0), so only bit 0 =            //////
//////    autoexecdata[0] is meaningful: it is a readable/writable WARL flop. All other bits (progbuf autoexec - there is    //////
//////    no Program Buffer) are hardwired 0. When autoexecdata[0]=1, ANY DMI access (read OR write) to data0 re-executes    //////
//////    the last command written to 0x17, routed through the SAME start arbitration a real command write uses - so the     //////
//////    idle/cmderr==0/hart-halted checks and every cmderr/busy outcome (4=halt, 2=unsupported, 1=busy) apply identically. //////
//////======================================================================================================================//////
wire        autoexec_q;
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_autoexec (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(wr_abstractauto),
                                                                     .d_i (dmi_pwdata_i[0]), .q_o(autoexec_q));
wire [31:0] abstractauto_read = {31'd0, autoexec_q};                 // bit 0 = autoexecdata[0]; [31:1] WARL-0

// Auto-exec trigger: a data0 access (read OR write of DMI 0x04) while autoexec is set. Keyed on the DMI
// ACCESS (accept-gated wr_data0 / is_read), never on data0 CHANGING - so the engine's own busy-cycle
// writeback into data0 (abs_read_done) does NOT re-trigger, and there is no auto-exec loop.
wire        data0_access     = wr_data0 | (is_read & (addr7 == DMI_DATA0));
wire        autoexec_trig    = data0_access & autoexec_q;

// Last command word written to 0x17. command is WARZ (reads 0), so it is not otherwise stored; this flop
// keeps a verbatim copy for the autoexec replay. Latches on ANY write to 0x17 (en_i = wr_command), even a
// write that errors - autoexec replays the CONTENTS of command, matching the spec. Soft-reset with the DM.
//
// aarpostincrement (bit 19): after a SUCCESSFUL Access-Register transfer whose stored command has
// aarpostincrement set, the regno field is incremented by 1 in place so the NEXT execution (a fresh
// autoexec replay, or - for a fresh command write - the first replay) targets regno+1. The increment
// fires in the busy cycle (last_cmd_inc), where last_cmd_q still holds the executing command for BOTH
// paths: a fresh write loaded it at start (T), and an autoexec left it unchanged. aarpostincrement is
// read from last_cmd_q[19] (NOT the c_* decode): autoexec_trig is accept-gated and already deasserted
// in the busy cycle, so cmd_word/c_aarpostinc no longer reflect the command there. A collision between a
// fresh write (load) and an increment cannot occur in practice (2-cycle DMI spacing, see the busy note
// below) but is arbitrated fresh-write-wins by the mux priority regardless.
wire [31:0] last_cmd_q;
wire        busy_fault;                                              // genCSR structural fault this busy cycle (declared below)
wire        last_cmd_inc     = busy_q & ~busy_fault & last_cmd_q[19]; // successful areg xfer w/ aarpostincrement
wire        last_cmd_en      = wr_command | last_cmd_inc;
wire [31:0] last_cmd_nxt     = wr_command ? dmi_pwdata_i                                 // fresh write wins
                                          : {last_cmd_q[31:16], last_cmd_q[15:0] + 16'd1}; // regno += 1, upper bits held
arv_dff_sinit #(.WIDTH(32), .ARST_EN(ARST_EN)) u_last_cmd (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(last_cmd_en),
                                                                     .d_i (last_cmd_nxt), .q_o(last_cmd_q));

// Command word feeding the decode below: the live write data on a real command write, or the stored last
// command on an autoexec replay. The two triggers are mutually exclusive (distinct addr7: 0x17 vs 0x04).
wire [31:0] cmd_word         = autoexec_trig ? last_cmd_q : dmi_pwdata_i;

//////======================================================================================================================//////
//////    command (DMI 0x17) is WARZ per Debug Spec 1.0 -- reads MUST return 0, regardless of the last write. So there is    //////
//////    no readback register: the command word is decoded live on the write (c_* fields) and the acting fields are latched //////
//////    into op_* at start; nothing else needs the raw word. 0x17 reads 0 (see the DMI read mux).                          //////
//////=======================================================================================================================//////
//////    Access Register: cmdtype=0, aarsize=2, transfer=1, ~postexec. Target-class decode (GPR/dbgCSR/genCSR) and cmderr   //////
//////    assignment are commented at their own logic below.                                                                 //////
//////=======================================================================================================================//////
wire  [2:0] cmderr_q;
wire [31:0] data0_q;

// Decode the command word (combinational). cmd_word is the live write data on a real command write,
// or the stored last command (last_cmd_q) on an autoexec-of-data0 replay.
wire  [7:0] c_cmdtype       = cmd_word[31:24];
wire  [2:0] c_aarsize       = cmd_word[22:20];
wire        c_postexec      = cmd_word[18];
wire        c_transfer      = cmd_word[17];
wire        c_write         = cmd_word[16];
wire [15:0] c_regno         = cmd_word[15:0];
// Bit 23 is an Access-Register reserved bit. Bit 19 (aarpostincrement) is NOT decoded from cmd_word:
// autoexec_trig is accept-gated and gone by the busy cycle, so the increment reads it from last_cmd_q[19]
// (which holds the executing command through busy) instead. Tie both off for lint.
wire  [1:0] cmd_word_unused = {cmd_word[23], cmd_word[19]};

// Common Access-Register qualifier: 32-bit transfer, no postexec. aarpostincrement (bit 19)
// IS supported (see last_cmd_q) and so is NOT rejected here. postexec is an unimplemented
// optional variant; per Debug Spec 1.0 an unsupported option set in a command must be rejected
// with cmderr=2 (not supported). aarsize is qualified even when transfer=0: the spec ties the
// size-check to the field value ("If aarsize specifies a size larger than the register's actual
// size, the access must fail"), independent of whether the transfer is performed.
wire        c_is_areg       = (c_cmdtype == 8'd0);
wire        c_areg_base     = c_is_areg & ~cmd_word[23] & (c_aarsize == 3'd2) & ~c_postexec;   // bit 23 reserved: must be 0
wire        c_areg_ok       = c_areg_base &  c_transfer;
// transfer=0 is a LEGAL NO-OP: "regno and write are ignored unless transfer is set"
// (Debug Spec 1.0, Access Register command). It completes successfully - cmderr stays 0,
// no busy cycle, no GPR/CSR side-port strobe (see start arbitration below).
wire        c_areg_noop     = c_areg_base & ~c_transfer;

// Target-class decode (mutually exclusive).
wire        c_is_gpr        = (c_regno[15:5]  == 11'd128);                          // 0x1000..0x101f
wire        c_is_csraddr    = (c_regno[15:12] ==  4'd0);                            // 0x000..0xfff
wire        c_is_dbgcsr     = c_is_csraddr & (c_regno[11:2] == 10'h1ec);            // 0x7b0..0x7b3
wire        c_is_time       = c_is_csraddr & ((c_regno[11:0] == 12'hc01) |          // time   (req/gnt handshake -> not single-cycle)
                                              (c_regno[11:0] == 12'hc81));          // timeh
wire        c_is_gencsr     = c_is_csraddr & ~c_is_dbgcsr & ~c_is_time;

// Registers the hart does not have: dscratch0/1 (0x7b2/0x7b3, not implemented), on RV32E
// x16-x31, and every regno outside the CSR and GPR ranges (FPRs, vector, custom). Accessing
// one is an exception, cmderr=3 (Debug 1.0 Access Register).
wire        c_is_dscratch   = c_is_dbgcsr  & c_regno[1];
wire        c_gpr_absent    = c_is_gpr     & c_regno[4] & ~RV32I_EN;
wire        c_no_class      = ~c_is_gpr    & ~c_is_csraddr;
wire        c_absent        = c_areg_ok    & (c_is_dscratch | c_gpr_absent | c_no_class);

wire        c_supp_gpr      = c_areg_ok & c_is_gpr    & ~c_gpr_absent;
wire        c_supp_dbgcsr   = c_areg_ok & c_is_dbgcsr & ~c_is_dscratch;
wire        c_supp_gencsr   = c_areg_ok & c_is_gencsr;
wire        c_supported     = c_supp_gpr | c_supp_dbgcsr | c_supp_gencsr;

// Start arbitration. A command is only acted on when the engine is idle and cmderr is clear.
// The transfer=0 no-op (c_areg_noop) completes right here: it is excluded from start_unsupp
// so cmderr stays 0, and it never reaches start_run, so busy is not set and no side-port
// strobe fires - the debugger observes an immediately-successful command.
// A start is attempted by a real command write OR an autoexec-of-data0 replay; both take the same path.
wire        cmd_trigger     = wr_command | autoexec_trig;
wire        start_attempt   = cmd_trigger & ~busy_q;
wire        start_ok        = start_attempt & (cmderr_q == 3'd0);
wire        start_halterr   = start_ok & ~hart_halted_i;                 // hart not halted   -> cmderr=4
wire        start_absent    = start_ok &  hart_halted_i &  c_absent;    // absent register   -> cmderr=3
wire        start_unsupp    = start_ok &  hart_halted_i & ~c_supported
                                                        & ~c_areg_noop & ~c_absent;  // unsupported cmd -> cmderr=2
assign      start_run       = start_ok &  hart_halted_i &  c_supported;  // begin an access
wire        cmd_while_busy  = cmd_trigger & busy_q & (cmderr_q == 3'd0); // command/autoexec during busy -> cmderr=1
// Invariant: with this 1-wait-state DMI, the single-cycle busy window is unobservable via the
// DMI itself -- the earliest a subsequent APB access can be accepted is 2 cycles after busy
// clears, so cmd_while_busy (and a data0-while-busy) cannot fire from DMI traffic alone.
// If any abstract op ever becomes multi-cycle, the data0-write/read-while-busy -> cmderr=1
// rule (Debug Spec 1.0, abstractcs.busy) must be implemented alongside this one.

// Latched operation (valid during the busy cycle). Full 12-bit regno so the genCSR
// address muxed into the EX datapath at arvern is stable across the busy cycle.
wire         op_write_q;
wire [11:0]  op_regno_q;
wire         op_is_dbgcsr_q;
wire         op_is_gencsr_q;
wire         op_is_gpr_q     = ~op_is_dbgcsr_q & ~op_is_gencsr_q;
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_op_write (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(start_run),
                                                                     .d_i (c_write), .q_o(op_write_q));
arv_dff_sinit #(.WIDTH(12), .ARST_EN(ARST_EN)) u_op_regno (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(start_run),
                                                                     .d_i (c_regno[11:0]), .q_o(op_regno_q));
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_op_dbgcsr (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(start_run),
                                                                     .d_i (c_supp_dbgcsr), .q_o(op_is_dbgcsr_q));
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_op_gencsr (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(start_run),
                                                                     .d_i (c_supp_gencsr), .q_o(op_is_gencsr_q));

// busy: high for exactly the one cycle in which the access is performed.
wire        busy_set        = start_run;
wire        busy_clr        = busy_q;
wire        busy_en         = busy_set | busy_clr;
wire        busy_nxt        = busy_set;
arv_dff_sinit #(.ARST_EN(ARST_EN)) u_busy (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(busy_en),
                                                                     .d_i (busy_nxt), .q_o(busy_q));

// GPR side-port drive (busy cycle, GPR class only).
assign      dm_gpr_raddr_o  = op_regno_q[4:0];
assign      dm_gpr_ren_o    = busy_q & ~op_write_q & op_is_gpr_q;
assign      dm_gpr_wen_o    = busy_q &  op_write_q & op_is_gpr_q;
assign      dm_gpr_waddr_o  = op_regno_q[4:0];
assign      dm_gpr_wdata_o  = data0_q;

// Debug-CSR side-port drive (busy cycle, dbgCSR class only). sel = regno[1:0].
assign      dm_csr_access_o = busy_q & op_is_dbgcsr_q;
assign      dm_csr_sel_o    = op_regno_q[1:0];
assign      dm_csr_wen_o    = busy_q & op_write_q & op_is_dbgcsr_q;
assign      dm_csr_wdata_o  = data0_q;

// General-CSR side-port drive (busy cycle, genCSR class only). dm_acsr_active gates
// the EX-datapath input mux at arvern; dm_acsr_wen selects csrrw(write)/csrrs(read).
assign      dm_acsr_active_o = busy_q & op_is_gencsr_q;
assign      dm_acsr_addr_o   = op_regno_q;
assign      dm_acsr_wen_o    = op_write_q;
assign      dm_acsr_wdata_o  = data0_q;

// A genCSR access faults this cycle if the (privilege-bypassed) CSR datapath reports
// a structural illegal -> cmderr=3. (Declared above, near last_cmd_q, which also consumes it.)
assign      busy_fault      = busy_q & op_is_gencsr_q & dm_acsr_fault_i;

// Read-result capture into data0: only on a non-faulting read in the busy cycle.
wire        abs_read_done   = busy_q & ~op_write_q & ~busy_fault;
wire [31:0] abs_read_data   = op_is_gpr_q    ? dm_gpr_rdata_i :
                              op_is_dbgcsr_q ? dm_csr_rdata_i :
                                               dm_acsr_rdata_i ;

//////======================================================================================================================//////
//////    abstractcs.cmderr (DMI 0x16[10:8]) - sticky, write-1-to-clear; set by the engine (4=halt/resume, 3=exception,      //////
//////    2=unsupported, 1=busy). Errors latch only from cmderr==0 (start_ok / cmd_while_busy / busy already gate on that).   //////
//////======================================================================================================================//////

wire        cmderr_w1c      = wr_abstractcs & (|dmi_pwdata_i[10:8]);  // any 1 in the field clears it (W1C)
wire        cmderr_set      = start_halterr | start_unsupp | start_absent | cmd_while_busy | busy_fault;
// Priority: cmd_while_busy(1) and busy_fault(3) can both occur in a busy cycle; a
// protocol-violating command during busy is surfaced as cmderr=1 (canonical), so it
// wins. start_* are mutually exclusive with both (they require ~busy_q).
wire  [2:0] cmderr_setval   = cmd_while_busy ? 3'd1 :
                              start_halterr  ? 3'd4 :
                             (busy_fault | start_absent) ? 3'd3 : 3'd2;
wire        cmderr_en       = cmderr_w1c | cmderr_set;
wire  [2:0] cmderr_nxt      = cmderr_w1c ? 3'd0 : cmderr_setval;        // a clear and a new error never co-occur (distinct addrs)
arv_dff_sinit #(.WIDTH(3), .ARST_EN(ARST_EN)) u_cmderr (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(cmderr_en),
                                                                     .d_i (cmderr_nxt), .q_o(cmderr_q));

//////======================================================================================================================//////
//////    data0 (DMI 0x04): debugger-written (write command arg) OR engine-written (read result capture).                   //////
//////======================================================================================================================//////

wire        data0_en        = wr_data0 | abs_read_done;
wire [31:0] data0_nxt       = wr_data0 ? dmi_pwdata_i : abs_read_data;
arv_dff_sinit #(.WIDTH(32), .ARST_EN(ARST_EN)) u_data0 (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .sinit_i(dm_sinit), .en_i(data0_en),
                                                                     .d_i (data0_nxt), .q_o(data0_q));

//////======================================================================================================================//////
//////    Status assembly. Debug Spec 1.0 requires every hart to be in EXACTLY ONE of halted / running / unavailable /       //////
//////    nonexistent. Single existent hart -> the three live states partition as: unavailable while ndmreset holds the     //////
//////    hart in reset; halted once drain-qualified; running otherwise -- including the halt-entry drain window, where the  //////
//////    hart is still finishing work and has not become unreachable. all* == any* (one hart).                              //////
//////                                                                                                                       //////
//////    SETTLE GUARD: the dmstatus / haltsum0 READ view is built from a free-running 1-cycle snapshot of the status        //////
//////    inputs, NOT the live signals. hart_halted_i rises at the same edge the final in-flight writeback of a             //////
//////    just-halted hart lands (drain is edge-aligned), so with the combinational PRDATA a live view could report          //////
//////    allhalted=1 in the very cycle hart state is still settling. The snapshot read at the response cycle equals the     //////
//////    value at the ACCEPT cycle and keeps the                                                                          //////
//////    dmstatus word internally coherent (one snapshot for halted/running/unavail/resumeack/havereset). Run-control       //////
//////    logic (resume handshake, abstract-command halt check, SBA gating) keeps the LIVE signals.                          //////
//////======================================================================================================================//////
wire        hart_halted_smp_q;
wire        ndmreset_smp_q;
wire        resumeack_smp_q;
wire        havereset_smp_q;
arv_dff #(.ARST_EN(ARST_EN)) u_hart_halted_smp (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .en_i(1'b1), .d_i(hart_halted_i),     .q_o(hart_halted_smp_q));
arv_dff #(.ARST_EN(ARST_EN)) u_ndmreset_smp (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .en_i(1'b1), .d_i(ndmreset_q),        .q_o(ndmreset_smp_q));
arv_dff #(.ARST_EN(ARST_EN)) u_resumeack_smp (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .en_i(1'b1), .d_i(resumeack_q),       .q_o(resumeack_smp_q));
arv_dff #(.RST_VAL(1'b1), .ARST_EN(ARST_EN)) u_havereset_smp (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .en_i(1'b1), .d_i(havereset_q),       .q_o(havereset_smp_q));

wire        unavail         =  ndmreset_smp_q;
wire        halted          =  hart_halted_smp_q    & ~ndmreset_smp_q;
wire        running         = ~hart_halted_smp_q    & ~ndmreset_smp_q;

// dmstatus (0x11), read-only
wire [31:0] dmstatus_read   =   32'd0                        |
                              ( 32'd3               <<  0)   |  // version = 3 (Debug Spec 1.0)
                              ( 32'd1               <<  5)   |  // hasresethaltreq (halt-on-reset supported)
                              ( 32'd1               <<  7)   |  // authenticated
                              ({31'd0, halted}      <<  8)   |  // anyhalted
                              ({31'd0, halted}      <<  9)   |  // allhalted
                              ({31'd0, running}     << 10)   |  // anyrunning
                              ({31'd0, running}     << 11)   |  // allrunning
                              ({31'd0, unavail}     << 12)   |  // anyunavail
                              ({31'd0, unavail}     << 13)   |  // allunavail
                              ({31'd0, resumeack_smp_q} << 16)   |  // anyresumeack
                              ({31'd0, resumeack_smp_q} << 17)   |  // allresumeack
                              ({31'd0, havereset_smp_q} << 18)   |  // anyhavereset
                              ({31'd0, havereset_smp_q} << 19)   ;  // allhavereset

// dmcontrol (0x10) readback: W1/WARZ fields read 0; only ndmreset + dmactive are stateful.
wire [31:0] dmcontrol_read  =   32'd0                        |
                              ({31'd0, ndmreset_q}  <<  1)   |
                              ({31'd0, dmactive_q}  <<  0)   ;

// haltsum0 (0x40), read-only (Debug Spec 1.0 "Halt Summary 0"): bit 0 = this hart's halted
// status (same drain-qualified `halted` term dmstatus.allhalted uses), bits [31:1] = 0
// (single hart). Writes are ignored (no W1C, no side effects).
wire [31:0] haltsum0_read   = {31'd0, halted};

// abstractcs (0x16): progbufsize=0, datacount=1, busy, cmderr.
wire [31:0] abstractcs_read =   32'd0                        |
                              ({31'd0, busy_q}      << 12)   |
                              ({29'd0, cmderr_q}    <<  8)   |
                              ( 32'd1               <<  0)   ;  // datacount = 1 (one data register)

//////======================================================================================================================//////
//////    System Bus Access engine - sbcs/sbaddress0/sbdata0 + AHB-Lite master (always present under DEBUG_EN).             //////
//////    Usable with the hart halted or running: the master is muxed onto - and arbitrates for - the data port at arvern.   //////
//////======================================================================================================================//////
wire [31:0] sbcs_read;
wire [31:0] sbaddress0_read;
wire [31:0] sbdata0_read;

arv_debug_sba #(.ARST_EN(ARST_EN)) u_arv_debug_sba (
    .hclk_i             ( hclk_i          ),
    .dbgresetn_i        ( dbgresetn_i     ),
    .dm_sinit_i         ( dm_sinit        ),
    .addr7_i            ( addr7           ),
    .is_read_i          ( is_read         ),
    .is_write_i         ( is_write        ),
    .wdata_i            ( dmi_pwdata_i    ),
    .sbcs_rdata_o       ( sbcs_read       ),
    .sbaddress0_rdata_o ( sbaddress0_read ),
    .sbdata0_rdata_o    ( sbdata0_read    ),
    .sb_busy_o          ( sb_busy         ),
    .sb_bus_req_o       ( dm_sb_req_o     ),
    .sb_bus_gnt_i       ( dm_sb_gnt_i     ),
    .sb_bus_active_o    ( dm_sb_active_o  ),
    .sb_haddr_o         ( dm_sb_haddr_o   ),
    .sb_htrans_o        ( dm_sb_htrans_o  ),
    .sb_hwrite_o        ( dm_sb_hwrite_o  ),
    .sb_hsize_o         ( dm_sb_hsize_o   ),
    .sb_hburst_o        ( dm_sb_hburst_o  ),
    .sb_hwdata_o        ( dm_sb_hwdata_o  ),
    .sb_hrdata_i        ( dm_sb_hrdata_i  ),
    .sb_hready_i        ( dm_sb_hready_i  ),
    .sb_hresp_i         ( dm_sb_hresp_i   )
);

assign      dm_sb_busy_o = sb_busy;

//////======================================================================================================================//////
//////    DMI read mux + response register (1-cycle latency, held until rsp_ready)                                          //////
//////======================================================================================================================//////
wire [31:0] dmi_read        = (addr7 == DMI_DATA0)         ? data0_q         :
                              (addr7 == DMI_DMCONTROL)     ? dmcontrol_read  :
                              (addr7 == DMI_DMSTATUS)      ? dmstatus_read   :
                              (addr7 == DMI_ABSTRACTCS)    ? abstractcs_read :
                              (addr7 == DMI_COMMAND)       ? 32'd0           :
                              (addr7 == DMI_ABSTRACTAUTO)  ? abstractauto_read :
                              (addr7 == DMI_SBCS)          ? sbcs_read       :
                              (addr7 == DMI_SBADDRESS0)    ? sbaddress0_read :
                              (addr7 == DMI_SBDATA0)       ? sbdata0_read    :
                              (addr7 == DMI_HALTSUM0)      ? haltsum0_read   :
                                                             32'd0           ;

// PREADY: 1-cycle pulse one cycle after accept. PRDATA is driven COMBINATIONALLY from
// the read mux (AREA: no 32-bit response register). This is APB-safe: every mux source
// is a flop and PADDR is stable through the ACCESS phase, so PRDATA is stable while
// PREADY is high. The only register that can change between accept and the response
// cycle from the transaction's own side effects is sbdata0 on a read-on-data trigger,
// and its earliest update is one cycle AFTER the response cycle (SBA issues NONSEQ at
// accept+1, data phase completes >= accept+2) even on a zero-wait-state bus. (data0 on
// an autoexec-of-data0 read has the same property: the engine's read-result writeback
// lands at accept+2, one cycle after the accept+1 response, so the read still returns
// the pre-trigger data0.) The
// live-hart-state view (dmstatus / haltsum0) is NOT read live - see the SETTLE GUARD
// snapshot at the status assembly. PRDATA during a WRITE response is the addressed
// register's read value (don't-care per APB).
wire        rsp_valid_set   = accept;
wire        rsp_valid_clr   = rsp_valid_q;       // self-clear: PREADY is a single-cycle pulse
wire        rsp_valid_en    = rsp_valid_set | rsp_valid_clr;
wire        rsp_valid_nxt   = rsp_valid_set;

arv_dff #(.ARST_EN(ARST_EN)) u_rsp_valid (
          .clk_i(hclk_i), .rst_n_i(dbgresetn_i), .en_i(rsp_valid_en),
                                                 .d_i (rsp_valid_nxt), .q_o(rsp_valid_q));

assign      dmi_pready_o    = rsp_valid_q;       // 1 wait state
assign      dmi_prdata_o    = dmi_read;
assign      dmi_pslverr_o   = 1'b0;              // no error reporting on the transport (in-band cmderr/sberror)

endmodule // arv_debug_dm

`default_nettype wire

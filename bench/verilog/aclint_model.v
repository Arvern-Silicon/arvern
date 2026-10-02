//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    aclint_model
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : aclint_model.v
// Module Description : BEHAVIOURAL ACLINT for the riscv-arch-test flow. Pin-
//                      compatible with ahb_aclint so ahb_bus_system.v can swap
//                      one for the other, but deliberately NOT a model of that
//                      IP -- it models the REFERENCE PLATFORM instead.
//
// WHY THIS EXISTS
//   riscv-arch-test is an ISA conformance suite: what it must exercise is the
//   core's trap and interrupt architecture, not the timing of the platform's
//   timer device. The real ahb_aclint keeps MTIME in an always-on low-frequency
//   domain so the timer survives WFI clock gating, which necessarily puts clock
//   -domain crossings between an MTIMECMP write and MTIP. The Sail reference has
//   no such device: its timer is instantaneous and advances once per RETIRED
//   INSTRUCTION (sail.json "instructions_per_tick": 1).
//
//   That mismatch produced failures that say nothing about the core -- interrupt
//   delivery ordered differently from the reference because MTIP arrived a cycle
//   late, and a timer armed with a margin the CDC latency had already consumed.
//   Modelling the reference platform removes the whole class.
//
//   The real ahb_aclint is verified by its own block-level regression and by the
//   trap_irq_aclint_* tests in sim/rtl_sim. A green arch-test run says NOTHING
//   about it -- that is the deliberate trade, and it is why this model is opt-in
//   (ARV_TB_ACLINT_MODEL) and used only by sim/arch_test.
//
// HOW IT MATCHES THE REFERENCE
//   + MTIP is combinational on mtime >= mtimecmp: zero delivery latency, and it
//     clears the same way -- the reference recomputes it every tick.
//   + A store to MTIMECMP takes effect during its own data phase, not a cycle
//     later, mirroring the reference applying it within the instruction.
//   + The Zicntr time port answers in the same cycle it is asked.
//   + No clock-domain crossing anywhere: everything is in hclk_i.
//
// ADDRESS MAP (identical to ahb_aclint)
//      0x0000 + 4*hart : MSIP[hart]        (bit 0)
//      0x4000 + 8*hart : MTIMECMP_LO[hart]
//      0x4004 + 8*hart : MTIMECMP_HI[hart]
//      0xBFF8          : MTIME_LO          (read-write, ACLINT 1.0-rc4 S2.2)
//      0xBFFC          : MTIME_HI
//                        MTIME sits at the top of the 32-KB MTIMER window per
//                        ACLINT Table 2, i.e. the CLINT-compatible 0x0200_BFF8,
//                        and is independent of NUM_HARTS.
//      0xC000 + 4*hart : SETSSIP[hart]     (write-only edge)
//----------------------------------------------------------------------------
`default_nettype none

module  aclint_model #(
    parameter                   NUM_HARTS  = 1,         // Number of harts (this model supports 1)
    parameter                   SU_MODE_EN = 1          // 1 => SSWI window present
) (

// CLOCK & RESET
    input  wire                 hclk_i,
    input  wire                 hclk_aon_i,
    input  wire                 hresetn_i,
    output wire                 hclk_en_o,
    output wire                 mtimer_wake_lf_o,   // single bit: OR across harts, matching ahb_aclint

// LOW-FREQUENCY CLOCK & RESET (accepted for pin compatibility, UNUSED: the
// always-on role is played by hclk_aon_i here)
    input  wire                 clk_lf_i,
    input  wire                 resetn_lf_i,
    input  wire                 hclk_aon_en_i,      // accepted for pin compatibility, UNUSED
    input  wire                 scan_mode_i,        // accepted for pin compatibility, UNUSED

// AHB-LITE SLAVE INTERFACE
    input  wire                 hsel_i,
    input  wire          [15:0] haddr_i,
    input  wire                 hwrite_i,
    input  wire           [2:0] hsize_i,
    input  wire           [1:0] htrans_i,
    input  wire           [3:0] hprot_i,
    input  wire                 hsmode_i,
    input  wire                 hready_i,
    input  wire          [31:0] hwdata_i,
    output wire          [31:0] hrdata_o,
    output wire                 hreadyout_o,
    output wire                 hresp_o,

// PER-HART INTERRUPTS
    output wire [NUM_HARTS-1:0] irq_m_software_o,
    output wire [NUM_HARTS-1:0] irq_m_timer_o,
    output wire [NUM_HARTS-1:0] irq_s_software_o,

// ZICNTR TIME INTERFACE
    input  wire                 time_req_i,
    output wire                 time_gnt_o,
    output wire          [63:0] time_val_o
);

localparam [15:0] MSWI_BASE   = 16'h0000;
localparam [15:0] MTIMER_BASE = 16'h4000;
localparam [15:0] SSWI_BASE   = 16'hC000;

localparam [15:0] MTIMECMP_LO = MTIMER_BASE + 16'h0000;
localparam [15:0] MTIMECMP_HI = MTIMER_BASE + 16'h0004;
localparam [15:0] MTIME_LO    = MTIMER_BASE + 16'h7FF8;   // 0xBFF8, top of the 32-KB MTIMER window
localparam [15:0] MTIME_HI    = MTIMER_BASE + 16'h7FFC;   // 0xBFFC


//=============================================================================
// 1)  AHB ADDRESS / DATA PHASE
//=============================================================================
// Single-cycle slave: hreadyout_o is always high. There is nothing to wait for
// -- no CDC, no synchronizer warmup -- which is exactly the point.

wire        aph_valid = hsel_i & hready_i & htrans_i[1];

reg         dph_valid;
reg         dph_write;
reg  [15:0] dph_addr;

always @(posedge hclk_i or negedge hresetn_i)
  if (!hresetn_i) begin
     dph_valid <= 1'b0;
     dph_write <= 1'b0;
     dph_addr  <= 16'h0000;
  end else if (hready_i) begin
     dph_valid <= aph_valid;
     dph_write <= aph_valid & hwrite_i;
     dph_addr  <= haddr_i;
  end

wire wr = dph_valid & dph_write;

assign hreadyout_o = 1'b1;
assign hresp_o     = 1'b0;
// Nothing here can stall or run without the bus, so the clock is only needed
// while a transfer is in flight.
assign hclk_en_o   = aph_valid | dph_valid;


//=============================================================================
// 2)  MTIME -- PACED BY RETIRED INSTRUCTIONS
//=============================================================================
// One count per retired instruction, matching the reference model's
// instructions_per_tick=1. A write replaces the count for that cycle.
//
reg [63:0] mtime;

// MTIME advances once per hclk_aon_i cycle.
//
// WALL-CLOCK, not instruction-paced. The reference (sail-riscv) ticks once per
// step-loop iteration, and an earlier version of this model reproduced that
// exactly -- but it cannot match the reference's VALUE, because the reference's
// MTIME is a function of ITS binary's instruction count and our RVMODEL glue
// differs from sail_macros.h. What matters to the suite is not matching MTIME
// but landing interrupts in the windows the tests expect, and a wall-clock rate
// does that.
//
// One tick per cycle is the fastest this model can run, and the constraint is
// ONE-SIDED: measured by sweep, InterruptsS-00 passes up to 1.32 cycles/tick and
// fails from 1.35, because a timer armed just before an MRET must fire BEFORE the
// target mode is entered, as it does in the reference. So the fastest rate is
// also the safest, and there is nothing to tune. (For contrast, the real
// ahb_aclint at LF_HALF_PERIOD=660 is exactly 1.32 -- sitting on the boundary,
// which is why that configuration was so brittle.)

// MTIME is read-write (ACLINT 1.0-rc4 Section 2.2); a write replaces the count.
wire mtime_wr_lo = wr & (dph_addr == MTIME_LO);
wire mtime_wr_hi = wr & (dph_addr == MTIME_HI);

always @(posedge hclk_aon_i or negedge hresetn_i)
  if (!hresetn_i)
     mtime <= 64'h0;
  else if (mtime_wr_lo)
     mtime <= {mtime[63:32], hwdata_i};
  else if (mtime_wr_hi)
     mtime <= {hwdata_i, mtime[31:0]};
  else
     mtime <= mtime + 64'h1;


//=============================================================================
// 3)  MTIMECMP + MTIP (ZERO LATENCY)
//=============================================================================
// Reset all-ones so the comparator cannot fire before firmware programs it.

reg [63:0] mtimecmp;

always @(posedge hclk_aon_i or negedge hresetn_i)
  if (!hresetn_i)
     mtimecmp <= 64'hFFFFFFFF_FFFFFFFF;
  else if (wr & (dph_addr == MTIMECMP_LO))
     mtimecmp <= {mtimecmp[63:32], hwdata_i};
  else if (wr & (dph_addr == MTIMECMP_HI))
     mtimecmp <= {hwdata_i, mtimecmp[31:0]};

// Combinational, like the reference: MTIP is pending the instant the comparison
// holds, with no synchronizer or handshake in the way.
//
// The comparison uses the write data DURING its data phase, not the registered
// value that appears a cycle later. The reference applies a store to MTIMECMP
// within the executing instruction, so MTIP is pending immediately; a registered
// model is one cycle behind, and that cycle is observable. Measured on
// InterruptsSSm-00: firmware re-arms the timer expecting MTIP inside an mstatus
// .MIE window, our MTIP landed 1 cycle after MIE dropped (52124 vs 52123), so the
// interrupt was deferred to the following MRET and taken from S instead of M.
wire [63:0] mtimecmp_eff = (wr & (dph_addr == MTIMECMP_LO)) ? {mtimecmp[63:32], hwdata_i} :
                           (wr & (dph_addr == MTIMECMP_HI)) ? {hwdata_i, mtimecmp[31:0]} :
                                                               mtimecmp;

assign irq_m_timer_o    = (mtime >= mtimecmp_eff);
assign mtimer_wake_lf_o = |irq_m_timer_o;


//=============================================================================
// 4)  MSWI (MSIP) AND SSWI (SETSSIP)
//=============================================================================
// MSIP is a read-write bit. SETSSIP is a different animal and the two must not
// be modelled alike: ACLINT 1.0 S4.2 makes it WRITE-ONLY, with writing 1 setting
// the target hart's sip.SSIP, writing 0 having NO effect, and reads returning 0.
// The hardware therefore emits an EDGE and never holds a level -- clearing SSIP
// is the receiving hart's job, through sip.SSIP, not through this register.
//
// Modelling it as a sticky, readable, writable-to-zero level would be the more
// forgiving shape, and would hide a real hazard: a level needs only one enabled
// clock edge at the consumer, so it never exercises the case where the ACLINT's
// clock and the hart's clock are independently gated and a one-cycle pulse has
// to survive the gap. The platform gates each IP separately, so that gap is
// exactly what arch-test needs to see.

reg msip;
reg ssip_pulse;

always @(posedge hclk_aon_i or negedge hresetn_i)
  if (!hresetn_i)
     msip <= 1'b0;
  else if (wr & (dph_addr == MSWI_BASE))
     msip <= hwdata_i[0];

always @(posedge hclk_aon_i or negedge hresetn_i)
  if (!hresetn_i)
     ssip_pulse <= 1'b0;
  else
     ssip_pulse <= wr & (dph_addr == SSWI_BASE) & hwdata_i[0];

assign irq_m_software_o = msip;
assign irq_s_software_o = (SU_MODE_EN != 0) ? ssip_pulse : 1'b0;


//=============================================================================
// 5)  READ MUX
//=============================================================================
// Unmapped offsets inside the window read 0, matching the real IP's RAZ.

reg [31:0] rdata;

always @(*) begin
   rdata = 32'h00000000;
   if (dph_valid & ~dph_write) begin
      case (dph_addr)
        MSWI_BASE   : rdata = {31'h0, msip};
        MTIMECMP_LO : rdata = mtimecmp[31:0];
        MTIMECMP_HI : rdata = mtimecmp[63:32];
        MTIME_LO    : rdata = mtime[31:0];
        MTIME_HI    : rdata = mtime[63:32];
        SSWI_BASE   : rdata = 32'h00000000;   // SETSSIP is write-only: reads return 0 (ACLINT S4.2)
        default     : rdata = 32'h00000000;
      endcase
   end
end

assign hrdata_o = rdata;


//=============================================================================
// 6)  ZICNTR TIME PORT -- SAME-CYCLE GRANT
//=============================================================================

assign time_gnt_o = time_req_i;
assign time_val_o = mtime;

endmodule // aclint_model

`default_nettype wire

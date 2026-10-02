//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    debug_dtm_jtag_tasks
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : debug_dtm_jtag_tasks.v
// Module Description : JTAG host BFM for the END-TO-END debug test. Instead of the
//                      testbench driving the DMI APB bus directly, the arv_dtm JTAG
//                      DTM (shipping arv_dtm wrapper, DTM_TYPE=0 (JTAG)) is the DMI
//                      master, and this TAP driver shifts dtmcs/dmi DRs to reach it.
//                      Black-box: drives only TCK/TMS/TDI, samples only TDO.
//
//   IEEE 1149.1 edge discipline (matches a real debugger / OpenOCD): the host
//   changes TMS/TDI on the FALLING TCK edge and samples TDO on the RISING edge;
//   the DUT samples TMS/TDI on RISING and updates TDO on FALLING.
//
//   It exposes dmi_write / dmi_read (setting dmi_readval) with the SAME signature
//   as the direct-APB helpers, so the high-level run-control / SBA helpers in
//   debug_dmi_tasks.v (dm_halt, dm_resume, sba_read32, ...) drive the real DTM
//   unchanged. Those adapters ASSUME the IR already holds DMI -- dtm_jtag_open
//   (tap_reset + shift_ir(IR_DMI)) MUST run once before the first transaction, so
//   the test calls it where the UART test calls uart_autobaud_sync. Each DMI op
//   launches on Update-DR then settles DTM_IDLE_N Run-Test/Idle cycles for the
//   TCK<->hclk CDC before the result is collected (this is an integration SANITY
//   test; the standalone arv_dtm bench stresses tight non-integer TCK:hclk CDC).
//----------------------------------------------------------------------------

// Requires (declared in tb_arvern.v, DTM_E2E block): tck (running clock), tms /
// tdi (reg, host -> DTM), tdo (wire, DTM -> host), tdo_sampled (reg); and
// dmi_readval / error in module scope.

localparam integer DBG_ABITS    = 7;
localparam integer DBG_DMI_DR_W = DBG_ABITS + 34;   // 41 bits at ABITS=7 (JTAG DMI DR)
localparam integer DBG_IDLE_N   = 16;               // Run-Test/Idle settle cycles per op

localparam [4:0] DBG_IR_IDCODE = 5'h01,
                 DBG_IR_DTMCS  = 5'h10,
                 DBG_IR_DMI    = 5'h11;

localparam [1:0] DBG_OP_NOP   = 2'd0,
                 DBG_OP_READ  = 2'd1,
                 DBG_OP_WRITE = 2'd2;

// One TCK cycle: set TMS/TDI on negedge, sample TDO on the next posedge.
task tck_cycle;
    input tms_val;
    input tdi_val;
    begin
        @(negedge tck);
        tms = tms_val;
        tdi = tdi_val;
        @(posedge tck);
        tdo_sampled = tdo;          // host samples TDO on the rising edge
    end
endtask

// Move the TAP to Test-Logic-Reset, then to Run-Test/Idle.
task tap_reset;
    integer k;
    begin
        for (k = 0; k < 6; k = k + 1) tck_cycle(1'b1, 1'b0);  // >=5 TMS=1 -> TLR
        tck_cycle(1'b0, 1'b0);                                // -> Run-Test/Idle
    end
endtask

// Insert n Run-Test/Idle cycles (TMS=0) -- the dtmcs.idle CDC settling hint.
task idle_cycles;
    input integer n;
    integer k;
    begin
        for (k = 0; k < n; k = k + 1) tck_cycle(1'b0, 1'b0);
    end
endtask

// Shift the IR (5 bits, LSB first). Assumes Run-Test/Idle, returns to it.
task shift_ir;
    input  [4:0] ir_val;
    integer i;
    begin
        tck_cycle(1'b1, 1'b0);      // RTI   -> Select-DR
        tck_cycle(1'b1, 1'b0);      //       -> Select-IR
        tck_cycle(1'b0, 1'b0);      //       -> Capture-IR
        tck_cycle(1'b0, 1'b0);      //       -> Shift-IR
        for (i = 0; i < 5; i = i + 1)
            tck_cycle((i == 4) ? 1'b1 : 1'b0, ir_val[i]);   // last bit -> Exit1-IR
        tck_cycle(1'b1, 1'b0);      // Exit1 -> Update-IR
        tck_cycle(1'b0, 1'b0);      //       -> Run-Test/Idle
    end
endtask

// Shift a DR of arbitrary width (LSB first). Assumes Run-Test/Idle, returns to
// it. Captures the shifted-out value into tdo_dr. DR-update side effects (e.g. a
// DMI launch) fire as the TAP passes through Update-DR.
task shift_dr;
    input  [63:0] tdi_dr;
    input  integer nbits;
    output [63:0] tdo_dr;
    integer i;
    begin
        tdo_dr = 64'b0;
        tck_cycle(1'b1, 1'b0);      // RTI   -> Select-DR
        tck_cycle(1'b0, 1'b0);      //       -> Capture-DR
        tck_cycle(1'b0, 1'b0);      //       -> Shift-DR (DR now holds capture value)
        for (i = 0; i < nbits; i = i + 1) begin
            tck_cycle((i == nbits-1) ? 1'b1 : 1'b0, tdi_dr[i]);  // last bit -> Exit1-DR
            tdo_dr[i] = tdo_sampled;
        end
        tck_cycle(1'b1, 1'b0);      // Exit1 -> Update-DR
        tck_cycle(1'b0, 1'b0);      //       -> Run-Test/Idle (launch fires here)
    end
endtask

// Raw DMI DR scan (IR must already be DMI). Assembles {address, data, op} and
// returns the captured {address, data, op}.
//   dmi DR layout: [ABITS+33:34]=address, [33:2]=data, [1:0]=op
task dmi_scan;
    input  [6:0]  addr;
    input  [31:0] data;
    input  [1:0]  op;
    output [31:0] cap_data;
    output [1:0]  cap_op;
    reg [63:0] tdi_dr;
    reg [63:0] cap;
    begin
        tdi_dr                    = 64'b0;
        tdi_dr[1:0]               = op;
        tdi_dr[33:2]              = data;
        tdi_dr[DBG_ABITS+33:34]   = addr;
        shift_dr(tdi_dr, DBG_DMI_DR_W, cap);
        cap_op   = cap[1:0];
        cap_data = cap[33:2];
    end
endtask

// Open the JTAG link before the first DMI transaction: reset the TAP and select
// IR=DMI (the dmi_write/dmi_read adapters assume DMI is already selected). The
// test calls this where the UART test calls uart_autobaud_sync.
task dtm_jtag_open;
    reg [63:0] cap;
    begin
        repeat (4) @(posedge tck);
        tap_reset;
        shift_ir(DBG_IR_IDCODE);
        shift_dr(64'b0, 32, cap);
        if (cap[31:0] !== 32'h0000_01F7) begin   // arv_dtm_tap IDCODE default (neutral IP default)
            $display("ERROR: DTM JTAG IDCODE=0x%08h (expected 0x000001F7) %t ns", cap[31:0], $time);
            error = error + 1;
        end else $display("PASS:  DTM JTAG IDCODE=0x%08h %t ns", cap[31:0], $time);
        shift_ir(DBG_IR_DMI);
    end
endtask

// DMI-register primitives with the SAME interface as the direct-APB helpers, so
// dm_halt / dm_resume / sba_* in debug_dmi_tasks.v work unchanged over the DTM.
// IR is assumed to already hold DMI (see dtm_jtag_open).
task dmi_write;
    input [6:0]  addr;
    input [31:0] data;
    reg [31:0] d0;
    reg [1:0]  s0;
    begin
        dmi_scan(addr, data, DBG_OP_WRITE, d0, s0);   // launch write on Update-DR
        idle_cycles(DBG_IDLE_N);                       // settle the CDC
    end
endtask

task dmi_read;
    input [6:0] addr;
    reg [31:0] d0;
    reg [1:0]  s0;
    begin
        dmi_scan(addr, 32'b0, DBG_OP_READ, d0, s0);   // launch read
        idle_cycles(DBG_IDLE_N);                       // settle the CDC
        dmi_scan(7'b0, 32'b0, DBG_OP_NOP, d0, s0);     // collect the result
        dmi_readval = d0;
    end
endtask

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    debug_dmi_tasks
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : debug_dmi_tasks.v
// Module Description : Debug Module Interface (DMI) bus helper tasks for the
//                      testbench. Drive the hclk-domain APB4 slave
//                      exposed at the arvern boundary (this TB is the APB master).
//                      Synchronous to the ALWAYS-ON free_clk (NOT the gated
//                      dut_hclk): a real DTM drives the DMI requester from an
//                      always-on domain so a pending request (PSEL) can ungate the
//                      core clock and reach the DM even while the hart is WFI
//                      clock-gated (dmi_keepalive term in arvern.v). While the hart
//                      runs, dut_hclk == free_clk edge-for-edge. These reference the
//                      dmi_p* APB signals declared next to the DUT instantiation in
//                      tb_arvern.v; this file is `included into the testbench module
//                      scope, exactly like check_tasks.v / tb_irq_checkers.v.
//----------------------------------------------------------------------------

// The low-level DMI-register primitives (dmi_xfer/dmi_write/dmi_read + dmi_readval)
// come in two flavours; the high-level helpers below (dm_halt/dm_resume/sba_*) are
// transport-agnostic and use whichever pair is compiled in:
//   - default            : this TB is the APB master and drives the DMI bus directly.
//   - DTM_UART_E2E define : the arv_dtm UART DTM is the DMI master and these
//                           primitives talk to it over the serial link (the
//                           end-to-end integration path). See debug_dtm_uart_tasks.v.
//   - DTM_I2C_E2E  define : same, over the arv_dtm I2C  DTM. See debug_dtm_i2c_tasks.v.
//   - DTM_JTAG_E2E define : same, over the arv_dtm JTAG DTM. See debug_dtm_jtag_tasks.v.
`ifdef DTM_UART_E2E
`include "debug_dtm_uart_tasks.v"
`elsif DTM_I2C_E2E
`include "debug_dtm_i2c_tasks.v"
`elsif DTM_JTAG_E2E
`include "debug_dtm_jtag_tasks.v"
`else
// One DMI transaction over APB (op: 1=read, 2=write). SETUP (PSEL, ~PENABLE) then
// ACCESS (PSEL, PENABLE); wait for PREADY (latency-agnostic), then sample PRDATA.
// The register index is placed in PADDR[8:2] (byte address). Captures read data
// into dmi_readval. `op` kept for caller compatibility: 2->PWRITE=1, else read.
task dmi_xfer;
   input [6:0]  addr;
   input [1:0]  op;
   input [31:0] data;
   integer      dmto;
   begin
      @(posedge free_clk);
      dmi_paddr   = {addr, 2'b00};                    // reg index in PADDR[8:2]
      dmi_pwdata  = data;
      dmi_pwrite  = (op == 2'd2);
      dmi_psel    = 1'b1;
      dmi_penable = 1'b0;                              // SETUP phase
      @(posedge free_clk);
      dmi_penable = 1'b1;                              // ACCESS phase
      @(posedge free_clk);
      dmto = 0;
      while ((dmi_pready !== 1'b1) && (dmto < 1000)) begin
         @(posedge free_clk); dmto = dmto + 1;
      end
      dmi_readval = dmi_prdata;                        // valid with PREADY
      dmi_psel    = 1'b0;
      dmi_penable = 1'b0;
      dmi_pwrite  = 1'b0;
   end
endtask

// Write `data` to DMI register `addr`.
task dmi_write;
   input [6:0]  addr;
   input [31:0] data;
   begin
      dmi_xfer(addr, 2'd2, data);
   end
endtask

// Read DMI register `addr` into dmi_readval.
task dmi_read;
   input [6:0]  addr;
   begin
      dmi_xfer(addr, 2'd1, 32'h0);
   end
endtask
`endif // DTM_*_E2E (direct-APB vs UART/I2C/JTAG-DTM primitives)

// ---------------------------------------------------------------------------
// High-level run-control helpers: halt / resume the hart over the
// DMI bus. These replace the dbg_haltreq_i/dbg_resumereq_i backdoor for
// the timing-robust tests (debug_haltreq / _zcmp / irq_masked / priv_restore).
//
// Self-contained - numeric DMI literals, no per-test localparam dependency.
// Synchronous to the always-on free_clk via dmi_xfer, so a pending request ungates
// the core clock (arvern.v dmi_keepalive) and these CAN halt/resume a clock-gated
// WFI-sleeping hart over the bus - no backdoor needed. On handshake timeout they
// bump the shared `error` counter so a hang fails the test loudly.
//
// DMI map: dmcontrol=0x10, dmstatus=0x11. dmcontrol bits: dmactive[0],
// resumereq[30], haltreq[31]. dmstatus bits: allhalted[9], allrunning[11].
// ---------------------------------------------------------------------------

// Halt the hart: ensure dmactive, assert haltreq, poll dmstatus.allhalted.
task dm_halt;
   integer dmto;
   begin
      dmi_write(7'h10, 32'h00000001);                       // dmcontrol = dmactive
      dmi_write(7'h10, 32'h80000001);                       // dmcontrol = dmactive | haltreq
      dmto = 0;
      dmi_read(7'h11);                                      // dmstatus
      while (((dmi_readval & 32'h00000200) === 32'h0) && (dmto < 200)) begin
         dmi_read(7'h11); dmto = dmto + 1;
      end
      if ((dmi_readval & 32'h00000200) === 32'h0) begin
         $display("ERROR: dm_halt: hart did not halt (allhalted=0, %0d polls) %t ns", dmto, $time);
         error = error + 1;
      end else
         $display("PASS:  dm_halt: hart halted (allhalted=1, %0d polls) %t ns", dmto, $time);
   end
endtask

// Resume the hart: drop haltreq, assert resumereq, poll dmstatus.allrunning.
task dm_resume;
   integer dmto;
   begin
      dmi_write(7'h10, 32'h00000001);                       // dmcontrol = dmactive (drop haltreq)
      dmi_write(7'h10, 32'h40000001);                       // dmcontrol = dmactive | resumereq
      dmto = 0;
      dmi_read(7'h11);                                      // dmstatus
      while (((dmi_readval & 32'h00000800) === 32'h0) && (dmto < 200)) begin
         dmi_read(7'h11); dmto = dmto + 1;
      end
      if ((dmi_readval & 32'h00000800) === 32'h0) begin
         $display("ERROR: dm_resume: hart did not resume (allrunning=0, %0d polls) %t ns", dmto, $time);
         error = error + 1;
      end else
         $display("PASS:  dm_resume: hart running (allrunning=1, %0d polls) %t ns", dmto, $time);
   end
endtask

// ---------------------------------------------------------------------------
// Halt-on-reset (resethaltreq) helpers. The DM's resethaltreq state
// survives an ndmreset: the TB models the SoC reset contract (dbg_ndmreset resets
// the hart via dut_hresetn while dbgresetn keeps the DM alive). Reset-halt = set
// resethaltreq, pulse ndmreset, poll dmstatus.allhalted -> hart halts out of reset
// with dcsr.cause=5. dmcontrol bits: dmactive[0], ndmreset[1], clrresethaltreq[2],
// setresethaltreq[3]. dmstatus: allhalted[9], allhavereset[19].
// ---------------------------------------------------------------------------

// Set the halt-on-reset request (setresethaltreq, keep dmactive).
task dm_set_resethaltreq;
   begin
      dmi_write(7'h10, 32'h00000009);                       // dmactive | setresethaltreq
   end
endtask

// Clear the halt-on-reset request (clrresethaltreq, keep dmactive).
task dm_clr_resethaltreq;
   begin
      dmi_write(7'h10, 32'h00000005);                       // dmactive | clrresethaltreq
   end
endtask

// Pulse ndmreset (dmactive|ndmreset held, then dropped). The TB resets the hart while
// ndmreset is asserted; on deassertion the hart comes out of reset (and reset-halts if
// resethaltreq is set).
task dm_ndmreset_pulse;
   integer k;
   begin
      dmi_write(7'h10, 32'h00000003);                       // dmactive | ndmreset -> hart held in reset
      for (k = 0; k < 8; k = k + 1) @(posedge free_clk);
      dmi_write(7'h10, 32'h00000001);                       // dmactive (drop ndmreset) -> hart released
   end
endtask

// Full reset-halt: set resethaltreq, pulse ndmreset, poll dmstatus.allhalted.
task dm_reset_halt;
   integer dmto;
   begin
      dm_set_resethaltreq;
      dm_ndmreset_pulse;
      dmto = 0;
      dmi_read(7'h11);                                      // dmstatus
      while (((dmi_readval & 32'h00000200) === 32'h0) && (dmto < 400)) begin
         dmi_read(7'h11); dmto = dmto + 1;
      end
      if ((dmi_readval & 32'h00000200) === 32'h0) begin
         $display("ERROR: dm_reset_halt: hart did not halt out of reset (allhalted=0, %0d polls) %t ns", dmto, $time);
         error = error + 1;
      end else
         $display("PASS:  dm_reset_halt: hart halted out of reset (allhalted=1, %0d polls) %t ns", dmto, $time);
   end
endtask

// ---------------------------------------------------------------------------
// System Bus Access (SBA) helpers. Drive memory through the Debug
// Module's own AHB master via sbcs (0x38) / sbaddress0 (0x39) / sbdata0 (0x3C)
// while the hart is halted. Self-contained numeric literals. Results land in
// the shared regs sba_rdata / sba_sberr (declared in tb_arvern.v).
//
// sbcs fields: sbreadonaddr[20], sbaccess[19:17] (0/1/2 = 8/16/32-bit),
// sbautoincrement[16], sbreadondata[15], sberror[14:12] (W1C), sbbusyerror[22]
// (W1C), sbbusy[21]. Convention: a READ is triggered by writing sbaddress0 with
// sbreadonaddr=1; a WRITE is triggered by writing sbdata0 (sbreadonaddr=0).
// ---------------------------------------------------------------------------

// Write an sbcs configuration word from the individual fields.
task sba_cfg;
   input        readonaddr;
   input        readondata;
   input        autoincr;
   input  [2:0] access;       // 0/1/2 = 8/16/32-bit
   begin
      dmi_write(7'h38, ({31'd0, readonaddr} << 20)
                     | ({29'd0, access}     << 17)
                     | ({31'd0, autoincr}   << 16)
                     | ({31'd0, readondata} << 15));
   end
endtask

// Poll sbcs.sbbusy (bit 21) until clear; bump `error` on timeout.
task sba_wait_idle;
   integer sbto;
   begin
      sbto = 0;
      dmi_read(7'h38);
      while (((dmi_readval & 32'h00200000) !== 32'h0) && (sbto < 200)) begin
         dmi_read(7'h38); sbto = sbto + 1;
      end
      if ((dmi_readval & 32'h00200000) !== 32'h0) begin
         $display("ERROR: sba_wait_idle: sbbusy stuck (%0d polls) %t ns", sbto, $time);
         error = error + 1;
      end
   end
endtask

// 32-bit SBA write: data -> [addr].
task sba_write32;
   input [31:0] addr;
   input [31:0] data;
   begin
      sba_cfg(1'b0, 1'b0, 1'b0, 3'd2);     // 32-bit, no readonaddr/readondata/autoincr
      dmi_write(7'h39, addr);              // sbaddress0 (readonaddr=0 -> no read triggered)
      dmi_write(7'h3c, data);              // sbdata0 -> triggers the bus WRITE
      sba_wait_idle;
   end
endtask

// 32-bit SBA read: returns [addr] in sba_rdata (and dmi_readval).
task sba_read32;
   input [31:0] addr;
   begin
      sba_cfg(1'b1, 1'b0, 1'b0, 3'd2);     // 32-bit, readonaddr=1
      dmi_write(7'h39, addr);              // sbaddress0 -> triggers the bus READ
      sba_wait_idle;
      dmi_read(7'h3c);                     // sbdata0 = read result
      sba_rdata = dmi_readval;
   end
endtask

// Read sbcs and capture the sberror[14:12] field (0..7) into sba_sberr.
task sba_get_sberr;
   begin
      dmi_read(7'h38);
      sba_sberr = dmi_readval[14:12];
   end
endtask

// Clear sbcs.sberror and sbcs.sbbusyerror (W1C).
task sba_clr_err;
   begin
      dmi_write(7'h38, 32'h00407000);      // W1C sbbusyerror[22] + sberror[14:12]
   end
endtask

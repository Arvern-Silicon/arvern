//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    debug_dtm_uart_tasks
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : debug_dtm_uart_tasks.v
// Module Description : UART host BFM for the END-TO-END debug test. Instead of the
//                      testbench driving the DMI APB bus directly, the arv_dtm UART
//                      DTM (shipping arv_dtm wrapper, DTM_TYPE=1 (UART)) is the DMI
//                      master, and this host talks to it over the serial link using
//                      the "DMI over serial" wire format:
//                        Request  : [0x55][addr][d31:24][d23:16][d15:8][d7:0][op]
//                        Response : [status][d31:24][d23:16][d15:8][d7:0]
//                      op: 1=read, 2=write, 3=dmihardreset.
//
//   It exposes dmi_write / dmi_read (setting dmi_readval) with the SAME signature
//   as the direct-APB helpers, so the high-level run-control / SBA helpers in
//   debug_dmi_tasks.v (dm_halt, dm_resume, sba_read32, ...) drive the real DTM
//   unchanged. 8-N-1, LSB-first. The DTM has no configured baud -- it auto-measures
//   the host from a leading 0x80 -- so the session opens with uart_autobaud_sync
//   (send 0x80, consume the DTM's echo). Bit timing is counted in free_clk edges so
//   it is timescale-independent (this is an integration SANITY test; the standalone
//   arv_dtm bench stresses async baud drift, glitches, and the auto-baud re-arm).
//----------------------------------------------------------------------------

// Requires (declared in tb_arvern.v, DTM_UART_E2E block): uart_rx (reg), uart_tx
// (wire), free_clk, dbgresetn; and dmi_readval / error in module scope.

localparam integer DTM_CLKS_PER_BIT = 8;   // host bit period (the DTM auto-measures it)

// One UART bit = DTM_CLKS_PER_BIT free_clk periods.
task uart_bit;
    integer c;
    begin
        for (c = 0; c < DTM_CLKS_PER_BIT; c = c + 1) @(posedge free_clk);
    end
endtask

// Send one byte host -> DTM, 8-N-1, LSB first.
task uart_send_byte;
    input [7:0] b;
    integer i;
    begin
        uart_rx = 1'b0; uart_bit;                 // start bit
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx = b[i]; uart_bit;
        end
        uart_rx = 1'b1; uart_bit;                 // stop bit
    end
endtask

// Receive one byte DTM -> host: wait for the start edge, sample each bit mid-period.
task uart_recv_byte;
    output [7:0] b;
    integer i, c;
    begin
        @(negedge uart_tx);                       // start bit
        for (c = 0; c < DTM_CLKS_PER_BIT + DTM_CLKS_PER_BIT/2; c = c + 1) @(posedge free_clk);
        for (i = 0; i < 8; i = i + 1) begin       // now at the middle of bit 0
            b[i] = uart_tx;
            uart_bit;
        end
    end
endtask

// Background full-duplex receiver: capture every byte the DTM transmits into a
// FIFO so a fast reply that begins before the request's stop bit is never missed.
reg [7:0] dtm_rx_fifo [0:255];
integer   dtm_rx_wr;
integer   dtm_rx_rd;

initial begin
    dtm_rx_wr = 0;
    dtm_rx_rd = 0;
end

initial begin : dtm_rx_monitor
    reg [7:0] b;
    @(posedge dbgresetn);                         // don't sample the reset transient
    forever begin
        uart_recv_byte(b);
        dtm_rx_fifo[dtm_rx_wr] = b;
        dtm_rx_wr = (dtm_rx_wr + 1) & 255;
    end
end

task dtm_fifo_pop;
    output [7:0] b;
    begin
        wait (dtm_rx_wr !== dtm_rx_rd);
        b     = dtm_rx_fifo[dtm_rx_rd];
        dtm_rx_rd = (dtm_rx_rd + 1) & 255;
    end
endtask

// Auto-baud sync handshake: open the link by sending the single 0x80 the DTM
// measures for the host baud, then consume the 0x80 it echoes back at that measured
// baud as its ACK. The DTM is self-calibrating, so every session opens here.
task uart_autobaud_sync;
    reg [7:0] echo;
    begin
        uart_send_byte(8'h80);
        dtm_fifo_pop(echo);
        if (echo !== 8'h80) begin
            $display("ERROR: DTM sync echo=%h (expected 0x80) %t ns", echo, $time);
            error = error + 1;
        end else $display("PASS:  DTM auto-baud sync echo OK %t ns", $time);
    end
endtask

// One full DMI transaction over UART. op: 1=read, 2=write, 3=dmihardreset.
task dtm_dmi_uart;
    input  [6:0]  addr;
    input  [1:0]  op;
    input  [31:0] data;
    output [1:0]  status;
    output [31:0] rdata;
    reg [7:0] s, b3, b2, b1, b0;
    begin
        uart_send_byte(8'h55);                    // SYNC delimiter
        uart_send_byte({1'b0, addr});
        uart_send_byte(data[31:24]);
        uart_send_byte(data[23:16]);
        uart_send_byte(data[15:8]);
        uart_send_byte(data[7:0]);
        uart_send_byte({6'b0, op});
        dtm_fifo_pop(s);                          // [status]
        dtm_fifo_pop(b3);                         // [d31:24]
        dtm_fifo_pop(b2);                         // [d23:16]
        dtm_fifo_pop(b1);                         // [d15:8]
        dtm_fifo_pop(b0);                         // [d7:0]
        status = s[1:0];
        rdata  = {b3, b2, b1, b0};
    end
endtask

// DMI-register primitives with the SAME interface as the direct-APB helpers, so
// dm_halt / dm_resume / sba_* in debug_dmi_tasks.v work unchanged over the DTM.
task dmi_write;
    input [6:0]  addr;
    input [31:0] data;
    reg [1:0]  st;
    reg [31:0] rd;
    begin
        dtm_dmi_uart(addr, 2'd2, data, st, rd);
    end
endtask

task dmi_read;
    input [6:0] addr;
    reg [1:0]  st;
    reg [31:0] rd;
    begin
        dtm_dmi_uart(addr, 2'd1, 32'h0, st, rd);
        dmi_readval = rd;
    end
endtask

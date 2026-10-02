//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    debug_dtm_i2c_tasks
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : debug_dtm_i2c_tasks.v
// Module Description : I2C host BFM for the END-TO-END debug test. Instead of the
//                      testbench driving the DMI APB bus directly, the arv_dtm I2C
//                      DTM (shipping arv_dtm wrapper, DTM_TYPE=2 (I2C)) is the DMI
//                      master, and this bit-banged open-drain I2C master talks to it
//                      using the "DMI over serial" wire format:
//                        Request  : addr+W [0x55][addr][d31:24..d7:0][op]
//                        Response : addr+R [status][d31:24..d7:0]  (repeated-START)
//                      op: 1=read, 2=write, 3=dmihardreset.
//
//   It exposes dmi_write / dmi_read (setting dmi_readval) with the SAME signature
//   as the direct-APB helpers, so the high-level run-control / SBA helpers in
//   debug_dmi_tasks.v (dm_halt, dm_resume, sba_read32, ...) drive the real DTM
//   unchanged. The master HONOURS CLOCK-STRETCHING (after releasing SCL it waits
//   for the line to actually rise, which the target holds low while a DMI op is in
//   flight) so busy is hidden exactly as on silicon. Bit phases are counted in
//   free_clk edges so timing is timescale-independent and gives the DTM's
//   sync + majority + mid-high-sample pipeline ample settle (this is an integration
//   SANITY test; the standalone arv_dtm bench stresses tight async I2C timing).
//----------------------------------------------------------------------------

// Requires (declared in tb_arvern.v, DTM_E2E block): m_scl_pd / m_sda_pd (reg,
// host pull-downs), scl / sda (wired-AND line levels), free_clk, dbgresetn; and
// dmi_readval / error in module scope.

localparam [6:0]   DBG_I2C_ADDR = 7'h30;   // must match arv_dtm I2C_ADDR default

// SCL-high / SCL-low / setup phase lengths, in free_clk edges. Generous so the
// DTM's 2-FF sync + 3-tap majority + mid-high sample pipeline resolves each phase.
localparam integer I2C_T_HIGH = 18;
localparam integer I2C_T_LOW  = 18;
localparam integer I2C_T_SU   = 5;

task i2c_edges;
    input integer n;
    integer c;
    begin
        for (c = 0; c < n; c = c + 1) @(posedge free_clk);
    end
endtask

// SCL helpers (clock-stretch aware).
task scl_release_high;                 // release SCL, wait for it to actually rise
    begin
        m_scl_pd = 1'b0;
        wait (scl === 1'b1);           // target may hold it low (clock stretch)
        i2c_edges(I2C_T_HIGH);
    end
endtask

task scl_drive_low;
    begin
        m_scl_pd = 1'b1;
        i2c_edges(I2C_T_LOW);
    end
endtask

// START / STOP (bus idle = both lines high).
task i2c_start;
    begin
        m_sda_pd = 1'b0;  m_scl_pd = 1'b0;  i2c_edges(I2C_T_SU);   // ensure both high
        m_sda_pd = 1'b1;  i2c_edges(I2C_T_HIGH);                   // SDA low while SCL high = START
        m_scl_pd = 1'b1;  i2c_edges(I2C_T_LOW);                    // SCL low
    end
endtask

task i2c_stop;
    begin
        m_sda_pd = 1'b1;  i2c_edges(I2C_T_SU);                     // SDA low while SCL low
        scl_release_high;                                          // SCL high
        m_sda_pd = 1'b0;  i2c_edges(I2C_T_HIGH);                   // SDA high while SCL high = STOP
    end
endtask

// Write one byte, return the target's ACK (1 = ACK).
task i2c_write_byte;
    input  [7:0] b;
    output       ack;
    integer i;
    begin
        for (i = 7; i >= 0; i = i - 1) begin
            m_sda_pd = ~b[i];          // drive bit while SCL low (0 -> pull low)
            i2c_edges(I2C_T_SU);
            scl_release_high;
            scl_drive_low;
        end
        m_sda_pd = 1'b0;               // release SDA for ACK
        i2c_edges(I2C_T_SU);
        scl_release_high;
        ack = ~sda;                    // ACK = SDA pulled low by target
        scl_drive_low;
    end
endtask

// Read one byte; send ACK (more to come) or NACK (last byte).
task i2c_read_byte;
    output [7:0] b;
    input        ack;                  // 1 = ACK, 0 = NACK
    integer i;
    begin
        m_sda_pd = 1'b0;               // release SDA (target drives)
        for (i = 7; i >= 0; i = i - 1) begin
            scl_release_high;
            b[i] = sda;
            scl_drive_low;
        end
        m_sda_pd = ack ? 1'b1 : 1'b0;  // ACK = pull low / NACK = release
        i2c_edges(I2C_T_SU);
        scl_release_high;
        scl_drive_low;
        m_sda_pd = 1'b0;
    end
endtask

// One full DMI transaction over I2C. op: 1=read, 2=write, 3=dmihardreset.
task dtm_dmi_i2c;
    input  [6:0]  addr;
    input  [1:0]  op;
    input  [31:0] data;
    output [1:0]  status;
    output [31:0] rdata;
    reg ack;
    reg [7:0] s, b3, b2, b1, b0;
    begin
        // ---- request (write) ----
        i2c_start;
        i2c_write_byte({DBG_I2C_ADDR, 1'b0}, ack);      // address + W
        i2c_write_byte(8'h55, ack);                     // SYNC
        i2c_write_byte({1'b0, addr}, ack);
        i2c_write_byte(data[31:24], ack);
        i2c_write_byte(data[23:16], ack);
        i2c_write_byte(data[15:8],  ack);
        i2c_write_byte(data[7:0],   ack);
        i2c_write_byte({6'b0, op},  ack);
        // ---- response (repeated-START, read) ----
        i2c_start;
        i2c_write_byte({DBG_I2C_ADDR, 1'b1}, ack);      // address + R
        i2c_read_byte(s,  1'b1);                        // [status]   ACK
        i2c_read_byte(b3, 1'b1);                        // [d31:24]   ACK
        i2c_read_byte(b2, 1'b1);                        // [d23:16]   ACK
        i2c_read_byte(b1, 1'b1);                        // [d15:8]    ACK
        i2c_read_byte(b0, 1'b0);                        // [d7:0]     NACK (last)
        i2c_stop;
        status = s[1:0];
        rdata  = {b3, b2, b1, b0};
    end
endtask

// Open the I2C link before the first DMI transaction. The bus is level-idle
// (both lines high) out of reset, so there is no calibration handshake -- just
// release both pull-downs and let the DTM's startup-settle pipeline prime.
task dtm_i2c_open;
    begin
        m_scl_pd = 1'b0;
        m_sda_pd = 1'b0;
        i2c_edges(I2C_T_HIGH);
        $display("PASS:  DTM I2C link idle-primed (addr 0x%0h) %t ns", DBG_I2C_ADDR, $time);
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
        dtm_dmi_i2c(addr, 2'd2, data, st, rd);
    end
endtask

task dmi_read;
    input [6:0] addr;
    reg [1:0]  st;
    reg [31:0] rd;
    begin
        dtm_dmi_i2c(addr, 2'd1, 32'h0, st, rd);
        dmi_readval = rd;
    end
endtask

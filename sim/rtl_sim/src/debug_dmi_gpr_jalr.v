//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_dmi_gpr_jalr
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: DM-written GPR visible to a post-resume jalr base (Debug Module)
//   Drives the hclk-domain DMI bus (no DTM) via dmi_write/dmi_read. The firmware
//   spins on `jalr x0, 0(x12)` with x12 pointing at the jalr itself (self-loop),
//   so the jalr base is "primed" on x12 at the instant of halt. This testbench:
//     - halts the spinning hart over the DMI bus (frozen-hart);
//     - reads the intended jump target (good_target) from x13 via probes -- no
//       hard-coded addresses, robust to linking;
//     - abstract-WRITES that address into x12 (the jalr base register);
//     - read-backs x12 to confirm the DM write reached the register file;
//     - resumes and proves the post-resume jalr uses the NEW (DM-written) x12 as
//       its target by reaching good_target.
//
//   DISCRIMINATION: if the post-resume jalr used a STALE base for x12 (a DM write
//   to a jalr base register not made visible to the jalr), the hart would keep
//   self-looping and never set x20/x31. The success-wait is therefore a BOUNDED
//   watchdog (counted poll on free_clk), never a blocking event -- a stale base
//   manifests as a watchdog timeout, not a simulation hang.
//
//   No fixed cycle counts gate correctness: allhalted/busy are POLLED, and the
//   watchdog bound is generous enough to tolerate -rwsram/-rwsrom slowdowns.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

integer to;
reg [31:0] good_addr;

// DMI register addresses (Debug Spec 1.0)
localparam [6:0] DMI_DATA0      = 7'h04;
localparam [6:0] DMI_DMCONTROL  = 7'h10;
localparam [6:0] DMI_DMSTATUS   = 7'h11;
localparam [6:0] DMI_ABSTRACTCS = 7'h16;
localparam [6:0] DMI_COMMAND    = 7'h17;

// dmcontrol field constants
localparam [31:0] DMC_DMACTIVE   = 32'h00000001;  // [0]  dmactive
localparam [31:0] DMC_HALTREQ    = 32'h80000000;  // [31] haltreq
localparam [31:0] DMC_RESUMEREQ  = 32'h40000000;  // [30] resumereq
localparam [31:0] DMC_ACKHAVERST = 32'h10000000;  // [28] ackhavereset

// dmstatus field masks
localparam [31:0] DMS_ALLHALTED    = 32'h00000200; // [9]
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800; // [11]
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000; // [17]

// abstractcs field masks (Debug Spec 1.0)
localparam [31:0] ACS_BUSY   = 32'h00001000; // [12] busy
localparam [31:0] ACS_CMDERR = 32'h00000700; // [10:8] cmderr (W1C)

// Access Register command words (command[0x17], cmdtype=0)
//   [22:20] aarsize=2 (32-bit) -> 0x00200000 ; [17] transfer=1 -> 0x00020000
//   [16] write ; [15:0] regno = 0x1000 + 12 = 0x100C for x12
localparam [31:0] CMD_WRITE_X12 = 32'h00200000 | 32'h00020000 | 32'h00010000 | 32'h0000100C; // = 0x0023100C
localparam [31:0] CMD_READ_X12  = 32'h00200000 | 32'h00020000 | 32'h0000100C;                // = 0x0022100C

localparam [31:0] X20_SUCCESS = 32'h0000600D;   // success marker set at good_target
localparam integer RESUME_WATCHDOG = 40000;     // free_clk cycles; generous for -rwsram/-rwsrom

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

    $display("");
    $display(" ====================================================================");
    $display("|  DEBUG DMI GPR JALR: DM-written jalr base must be seen by resumed jalr|");
    $display(" ====================================================================");

    // Wait for the firmware to be spinning on the jalr.
    @(probes_cpu.x31==32'h11111111);
    $display("Firmware spinning on jalr through x12 (x31=0x11111111) %t ns", $time);

    // --- bring the DM out of reset (dmactive=1), clear sticky havereset ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_ACKHAVERST);

    // --- halt the hart via dmcontrol.haltreq, poll dmstatus.allhalted ---
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_HALTREQ);
    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLHALTED) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLHALTED) === 32'h0) begin
        $display("ERROR: hart did not halt on dmcontrol.haltreq (allhalted=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart halted via DMI haltreq (allhalted=1, %0d polls) %t ns", to, $time);

    if (dbg_debug_mode !== 1'b1) begin
        $display("ERROR: dbg_debug_mode not asserted while allhalted=1 %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart in Debug Mode (abstract GPR access permitted) %t ns", $time);

    // --- learn the intended jump target from x13 (la result, valid while halted) ---
    good_addr = probes_cpu.x13;
    $display("INFO:  good_target address read from x13 = %h %t ns", good_addr, $time);
    if (good_addr === 32'h0) begin
        $display("ERROR: good_target address (x13) read back as 0 -- la did not resolve %t ns", $time);
        error = error + 1;
    end

    //========================================================================
    // Abstract WRITE of x12 (the jalr base register) with good_target address.
    //========================================================================
    dmi_write(DMI_DATA0, good_addr);            // arg0 = new jalr base value
    dmi_write(DMI_COMMAND, CMD_WRITE_X12);       // transfer+write x12 from data0

    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_BUSY) !== 32'h0) begin
        $display("ERROR: abstractcs.busy stuck after x12 write command %t ns", $time);
        error = error + 1;
    end else $display("PASS:  abstract write command completed (busy clear, %0d polls) %t ns", to, $time);

    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after x12 write (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end else $display("PASS:  abstractcs.cmderr=0 after x12 write %t ns", $time);

    // cross-check: the DM write reached the register file while halted
    if (probes_cpu.x12 !== good_addr) begin
        $display("ERROR: regfile x12=%h after DM write (expected %h) %t ns", probes_cpu.x12, good_addr, $time);
        error = error + 1;
    end else $display("PASS:  DM write reached regfile x12=%h while halted %t ns", good_addr, $time);

    // recommended: abstract read-back of x12 confirms the value through the DM path
    dmi_write(DMI_COMMAND, CMD_READ_X12);
    to = 0;
    dmi_read(DMI_ABSTRACTCS);
    while (((dmi_readval & ACS_BUSY) !== 32'h0) && (to < 200)) begin
        dmi_read(DMI_ABSTRACTCS);
        to = to + 1;
    end
    if ((dmi_readval & ACS_CMDERR) !== 32'h0) begin
        $display("ERROR: abstractcs.cmderr=%0d after x12 read-back (expected 0) %t ns", (dmi_readval & ACS_CMDERR) >> 8, $time);
        error = error + 1;
    end
    dmi_read(DMI_DATA0);
    if (dmi_readval !== good_addr) begin
        $display("ERROR: abstract read-back of x12 returned %h (expected %h) %t ns", dmi_readval, good_addr, $time);
        error = error + 1;
    end else $display("PASS:  abstract read-back of x12 = good_target %h %t ns", good_addr, $time);

    //========================================================================
    // RESUME and prove the post-resume jalr uses the NEW x12 as its target.
    //========================================================================
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE);                 // drop haltreq
    dmi_write(DMI_DMCONTROL, DMC_DMACTIVE | DMC_RESUMEREQ); // request resume

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0) begin
        $display("ERROR: no allresumeack after resumereq %t ns", $time);
        error = error + 1;
    end else $display("PASS:  allresumeack set after resume (%0d polls) %t ns", to, $time);

    to = 0;
    dmi_read(DMI_DMSTATUS);
    while (((dmi_readval & DMS_ALLRUNNING) === 32'h0) && (to < 200)) begin
        dmi_read(DMI_DMSTATUS);
        to = to + 1;
    end
    if ((dmi_readval & DMS_ALLRUNNING) === 32'h0) begin
        $display("ERROR: hart not running after resume (allrunning=0) %t ns", $time);
        error = error + 1;
    end else $display("PASS:  hart running after resume (allrunning=1) %t ns", $time);

    // --- DISCRIMINATION: bounded watchdog on reaching the end.
    //     On a stale-base failure the hart re-enters the self-loop and hangs, so
    //     we MUST NOT block forever -- poll x31 with a generous cycle bound.
    to = 0;
    while ((probes_cpu.x31 !== 32'hdeadbeef) && (to < RESUME_WATCHDOG)) begin
        @(posedge free_clk);
        to = to + 1;
    end
    if (probes_cpu.x31 !== 32'hdeadbeef) begin
        $display("ERROR: hart did not reach end after resume -> jalr used a STALE base for x12 (DM write to a jalr base register not visible to the jalr) %t ns", $time);
        error = error + 1;
    end else begin
        $display("PASS:  hart reached end after resume (jalr used the DM-written x12, %0d cycles) %t ns", to, $time);
        check_cpu_reg(20, X20_SUCCESS);          // good_target ran => jalr jumped to the DM-written target
        check_cpu_reg(12, good_addr[31:0]);      // jalr base still holds the DM-written address
    end

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_resumeack_clear
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: a resumereq write clears dmstatus.allresumeack even when the
// hart is not halted (see the .s).
//----------------------------------------------------------------------------
`define SPAD(byte_off)  ((byte_off)/4)

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;
localparam [31:0] DMS_ALLRESUMEACK = 32'h00020000;   // [17]
localparam [31:0] DMS_ALLRUNNING   = 32'h00000800;   // [11]

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);
      error_on_exception = 0;
      ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0)] = 32'h0;

      $display("");
      $display(" ====================================================================");
      $display("|   resumereq CLEARS THE RESUME ACK EVEN WHEN THE HART RUNS          |");
      $display(" ====================================================================");

      @(probes_cpu.x31==32'h11111111);
      dm_halt;
      dm_resume;
      dmi_read(7'h11);
      if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0)
         begin $display("ERROR: allresumeack=0 after a completed resume"); error = error + 1; end

      // resumereq while running: ignored by the hart, but the ack clears
      dmi_write(7'h10, 32'h40000001);
      dmi_read(7'h11);
      $display("INFO:  dmstatus after resumereq while running = 0x%h", dmi_readval);
      if ((dmi_readval & DMS_ALLRUNNING) === 32'h0)
         begin $display("ERROR: the hart is not running"); error = error + 1; end
      if ((dmi_readval & DMS_ALLRESUMEACK) !== 32'h0)
         begin $display("ERROR: allresumeack=1 after a resumereq write (spec: the write clears it)"); error = error + 1; end
      else
         $display("PASS:  allresumeack cleared by the resumereq write");

      // haltreq + resumereq in one write: resumereq is ignored, ack untouched
      dm_halt;
      dm_resume;
      dmi_write(7'h10, 32'hC0000001);
      dmi_read(7'h11);
      if ((dmi_readval & DMS_ALLRESUMEACK) === 32'h0)
         begin $display("ERROR: allresumeack cleared by a write that also sets haltreq (resumereq is ignored)"); error = error + 1; end
      dmi_write(7'h10, 32'h00000001);
      dm_resume;

      ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0)] = 32'h1;
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

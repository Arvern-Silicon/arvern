//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_seip_csrrs_rmw
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: MIP[9] / SEIP CSRRS/CSRRC RMW spec-conformance test bench
//   (Priv §3.1.9 P207-208). The TB drives irq_s_external around firmware
//   sync points and verifies the firmware's captured MIP[9] reads.
//
//   The headline assertion is check_cpu_reg(s6, 0) -- after a csrrs RMW
//   whose mask did NOT include bit 9 (while E was asserted), MIP[9] must
//   read 0 once E deasserts. A non-spec-conformant implementation would
//   have latched B=1 during the RMW and SEIP would have stuck at 1.
//
//   Stable result register map (firmware writes each exactly once):
//     s2 (x18) = MIP[9] at sync 0xFFFFFFFF  (E=0 init,        expect 0)
//     s3 (x19) = MIP[9] at sync 0x11111111  (E=1,             expect 1)
//     s4 (x20) = MIP[9] at sync 0x22222222  (csrrs rs1=x0,    expect 1)
//     s5 (x21) = MIP[9] at sync 0x33333333  (csrrs RMW mask=MSIP, expect 1)
//     s6 (x22) = MIP[9] at sync 0x44444444  (after E deassert,    expect 0)  <-- HEADLINE
//     s7 (x23) = MIP[9] at sync 0x55555556  (after csrrc + E deassert, expect 0)
//     s8 (x24) = MIP[9] after csrrw set, E=0,    expect 1
//     s9 (x25) = MIP[9] after csrrw clear, E=0,  expect 0
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // No random IRQs throughout this test -- we are probing MIP read
      // semantics, not trap delivery.
      random_irq_enable = 0;

      // Ensure E starts at 0 (it should already be reset; explicit for clarity).
      irq_s_external = 1'b0;


      //=================================================================
      // SYNC 0xFFFFFFFF: init done, E=0 (TB keeps pin low)
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  SYNC 0xFFFFFFFF: INIT, E=0, EXPECT MIP[9] = 0                    |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'hFFFFFFFF);
      // E remains 0. Firmware will capture MIP[9] into s2 (x18).


      //=================================================================
      // SYNC 0x11111111: assert E=1, expect MIP[9] OR'd read = 1
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  SYNC 0x11111111: ASSERT E=1, EXPECT MIP[9] = 1 (OR'd READ)       |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h11111111);
      // Drive irq_s_external high immediately after sync; firmware spins
      // ~64 iterations before reading, giving the 2-FF synchroniser plenty
      // of time to clock the assertion into the core.
      @(posedge free_clk);
      @(posedge free_clk);
      irq_s_external = 1'b1;


      //=================================================================
      // SYNC 0x22222222: csrrs rs1=x0 (true no-write), E held high
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  SYNC 0x22222222: CSRRS rs1=x0 NO-WRITE, E=1, EXPECT rd[9] = 1    |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h22222222);
      // No TB-side action; E stays asserted. Firmware will capture rd[9] into s4.


      //=================================================================
      // SYNC 0x33333333: csrrs RMW with mask=(1<<3), E held high
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  SYNC 0x33333333: CSRRS RMW MASK=MSIP, E=1, EXPECT rd[9] = 1      |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h33333333);
      // No TB-side action; E stays asserted. Firmware runs the RMW and
      // captures rd[9] into s5. The discriminating MIP[9] read happens at
      // the NEXT sync after E is deasserted.


      //=================================================================
      // SYNC 0x44444444: deassert E; expect MIP[9] = 0   <-- HEADLINE
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  SYNC 0x44444444: DEASSERT E, EXPECT MIP[9] = 0 (HEADLINE)        |");
      $display("|  This is the spec-conformance assertion -- a non-conformant       |");
      $display("|  RTL would have latched B=1 in the prior csrrs RMW and SEIP       |");
      $display("|  would stick at 1 here.                                           |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h44444444);
      @(posedge free_clk);
      @(posedge free_clk);
      irq_s_external = 1'b0;


      //=================================================================
      // SYNC 0x55555555: re-assert E for the csrrc clear-all RMW
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  SYNC 0x55555555: RE-ASSERT E=1 FOR CSRRC RMW                     |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h55555555);
      @(posedge free_clk);
      @(posedge free_clk);
      irq_s_external = 1'b1;


      //=================================================================
      // SYNC 0x55555556: firmware done with the csrrc; deassert E
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  SYNC 0x55555556: DEASSERT E AFTER CSRRC, EXPECT MIP[9] = 0       |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h55555556);
      @(posedge free_clk);
      @(posedge free_clk);
      irq_s_external = 1'b0;


      //=================================================================
      // SYNC 0x66666666: csrrw set / csrrw clear with E held low
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|  SYNC 0x66666666: CSRRW SET/CLEAR PATH, E=0 THROUGHOUT            |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h66666666);
      // E already low. Firmware: csrrw set -> read (s8 expect 1)
      //                          csrrw clr -> read (s9 expect 0).


      //=================================================================
      // SYNC 0xdeadbeef: end of test -- verify all captured results
      //=================================================================
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(5) @(posedge free_clk);

      // Just to be tidy.
      irq_s_external = 1'b0;

      $display("");
      $display("--- MIP[9] / SEIP CSRRS/CSRRC RMW spec-conformance checks ---");
      check_cpu_reg(18, 32'h00000000);   // s2: init,        E=0 -> MIP[9]=0
      check_cpu_reg(19, 32'h00000001);   // s3: E=1,             MIP[9]=1
      check_cpu_reg(20, 32'h00000001);   // s4: csrrs rs1=x0,    rd[9]=1
      check_cpu_reg(21, 32'h00000001);   // s5: csrrs RMW mask=MSIP, rd[9]=1
      check_cpu_reg(22, 32'h00000000);   // s6: HEADLINE -- after E deassert, MIP[9]=0
      check_cpu_reg(23, 32'h00000000);   // s7: after csrrc + E deassert, MIP[9]=0
      check_cpu_reg(24, 32'h00000001);   // s8: csrrw set,  E=0 -> MIP[9]=1
      check_cpu_reg(25, 32'h00000000);   // s9: csrrw clear, E=0 -> MIP[9]=0

      $display("");
      $display("--- Confirm headline (s6): spec-conformant B did NOT latch from E ---");

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

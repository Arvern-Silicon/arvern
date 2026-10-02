//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_irq_plic_priv_violation
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: PLIC PRIV_CHECK_EN deny -> AHB ERROR -> access-fault trap
//   The S-mode firmware deliberately reads ctx-0 threshold and writes
//   ctx-0 enable (both denied to S-mode under PRIV_CHECK_EN=1). Each
//   denied access must AHB-ERROR; the core reports a load-access-fault
//   (cause 5) for the first and a store-access-fault (cause 7) for the
//   second. The S-mode read of ctx-1 threshold (allowed) must succeed
//   and return 0 (default value).
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

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

      // Two real exceptions (the denied accesses) are expected -- suppress
      // the global exception monitor's error counter for this test.
      error_on_exception = 0;
      use_plic           = 1'b1;


      //=================================================================
      // PHASE 1: PLIC configured, dropping to S-mode
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|             PHASE 1: PLIC configured, dropping to S                |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h1E1E1E1E);
      repeat(3) @(posedge free_clk);

      begin : program_vector
         reg [31:0] handler_addr;
         handler_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)];
         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler address not published %t ns", $time);
            error = error + 1;
         end else begin
            $display("PASS:  nmi_vector programmed to 0x%h %t ns", handler_addr, $time);
         end
      end

      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: S-mode tries to READ ctx-0 threshold -> load access fault
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: S-mode lw  ctx0 threshold -> AHB ERROR -> LAF           |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000001);                 // 1 trap fired
      check_mem_value(`SPAD(32'h04), 32'h80000003);                 // mncause = data-bus error
      check_mem_value(`SPAD(32'h08), 32'h0C200000);                 // marv_eaddr = PLIC_TH_M

      // THE PLATFORM CONTRACT (plan section 5): an S-mode containment breach
      // escalates to M-mode as a NON-DELEGABLE RNMI, not a delegable S-mode
      // fault. mnstatus.MNPP[12:11] must record the S-mode it came from, so
      // mnret returns there.
      begin : escalation
         reg [31:0] mnst;
         mnst = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h18)];
         $display("mnstatus at RNMI entry = 0x%h  MNPP = %0d (1 = S-mode)",
                  mnst, mnst[12:11]);
         if (mnst[12:11] !== 2'b01) begin
            $display("ERROR: MNPP = %0d, expected 1 (S) -- the RNMI must record the", mnst[12:11]);
            $display("       privilege it escalated FROM %t ns", $time);
            error = error + 1;
         end
      end
      $display("PASS:  S-mode load to ctx-0 threshold AHB-ERRORed and trapped %t ns",
               $time);


      //=================================================================
      // PHASE 3: S-mode tries to WRITE ctx-0 enable -> store access fault
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 3: S-mode sw  ctx0 enable    -> AHB ERROR -> SAF           |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);                 // 2 traps total
      check_mem_value(`SPAD(32'h0C), 32'h80000003);                 // mncause = data-bus error
      check_mem_value(`SPAD(32'h10), 32'h0C002000);                 // marv_eaddr = PLIC_EN_M
      $display("PASS:  S-mode store to ctx-0 enable AHB-ERRORed and trapped %t ns",
               $time);


      //=================================================================
      // PHASE 4: S-mode reads ctx-1 threshold (allowed) -> no extra trap
      //=================================================================
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 4: S-mode lw  ctx1 threshold -> ALLOWED                    |");
      $display(" ====================================================================");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h00), 32'h00000002);                 // still 2 traps
      check_mem_value(`SPAD(32'h14), 32'h00000000);                 // ctx1 threshold = 0

      $display("");
      $display("--- mtvec must NEVER be entered (5/7 RESERVED) ---");
      check_mem_value(`SPAD(32'h1C), 32'h00000000);
      $display("PASS:  S-mode load to ctx-1 threshold succeeded %t ns", $time);


      //=================================================================
      // END OF TEST
      //=================================================================
      repeat(20) @(posedge free_clk);
      $display("");
      stimulus_done = 1;
   end

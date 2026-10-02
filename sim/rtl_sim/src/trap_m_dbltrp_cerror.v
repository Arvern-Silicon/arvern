//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_m_dbltrp_cerror
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Smdbltrp critical-error state reached with MDT CLEAR
//   A fault inside an RNMI handler is an unexpected trap purely because
//   mnstatus.NMIE is 0 there -- MDT plays no part, and the test proves it by
//   reading mstatush back as 0 from inside the handler.
//   No architectural state changes, lockup_o asserts and is sticky.
//----------------------------------------------------------------------------

`define SPAD(byte_off)  ((byte_off)/4)

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

reg [31:0] rnmi_addr;

wire [31:0] lat_mcause = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mcause;
wire [31:0] lat_mepc   = {`ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mepc_mepc, 1'b0};

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      @(probes_cpu.x31 == 32'h11111111);
      repeat(3) @(posedge free_clk);

      $display("");
      $display(" ====================================================================");
      $display("|   Smdbltrp: critical error from NMIE=0, with MDT CLEAR             |");
      $display(" ====================================================================");
      $display("");

      rnmi_addr = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];
      if (rnmi_addr == 32'h0) begin
         $display("ERROR: rnmi_handler address not published %t ns", $time);
         error = error + 1;
      end else begin
         $display("PASS:  nmi_vector programmed to 0x%h %t ns", rnmi_addr, $time);
      end

      $display("");
      $display("--- lockup_o low before the RNMI ---");
      if (lockup !== 1'b0) begin
         $display("ERROR: lockup_o already asserted %t ns", $time);
         error = error + 1;
      end else $display("PASS:  lockup_o low %t ns", $time);

      // Fire the external RNMI. The handler runs with NMIE=0.
      repeat(10) @(posedge free_clk);
      @(negedge free_clk);
      nmi = 1'b1;
      repeat(2) @(negedge free_clk);
      nmi = 1'b0;

      @(probes_cpu.x31 == 32'h22222222);
      $display("");
      $display("In the RNMI handler (NMIE=0); waiting for lockup_o... %t ns", $time);

      @(posedge lockup);
      repeat(5) @(posedge free_clk);

      $display("");
      $display("--- lockup_o asserted ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o not asserted after a fault inside the RNMI handler %t ns", $time);
         error = error + 1;
      end else $display("PASS:  lockup_o asserted %t ns", $time);

      $display("");
      $display("--- the RNMI handler ran exactly once ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      //=================================================================
      // The load-bearing check: MDT was 0, so this cannot be the MDT arm
      //=================================================================
      $display("");
      $display("--- mstatush read 0 inside the handler: MDT did NOT cause this ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      $display("");
      $display("--- it really was an RNMI that got us there (mncause bit31 set) ---");
      begin : mncause_chk
         reg [31:0] mnc;
         mnc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         if (mnc[31] !== 1'b1) begin
            $display("ERROR: mncause=0x%h, expected an RNMI (bit31=1) %t ns", mnc, $time);
            error = error + 1;
         end else $display("PASS:  mncause=0x%h %t ns", mnc, $time);
      end

      //=================================================================
      // "without updating any architectural state, including the pc"
      //=================================================================
      $display("");
      $display("--- the M trap stack was never written (handler never entered) ---");
      if (lat_mcause !== 32'h00000000) begin
         $display("ERROR: mcause=0x%h -- the M handler ran, or the M stack was written %t ns", lat_mcause, $time);
         error = error + 1;
      end else $display("PASS:  mcause still 0 %t ns", $time);

      if (lat_mepc !== 32'h00000000) begin
         $display("ERROR: mepc=0x%h -- the M stack was written %t ns", lat_mepc, $time);
         error = error + 1;
      end else $display("PASS:  mepc still 0 %t ns", $time);

      $display("");
      $display("--- execution ceased: nothing ran past the faulting instruction ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000000);

      //=================================================================
      // Sticky
      //=================================================================
      repeat(100) @(posedge free_clk);
      $display("");
      $display("--- lockup_o still asserted 100 cycles later ---");
      if (lockup !== 1'b1) begin
         $display("ERROR: lockup_o de-asserted -- the critical-error state must be sticky %t ns", $time);
         error = error + 1;
      end else $display("PASS:  lockup_o sticky %t ns", $time);

      check_mem_value(`SPAD(32'h0C), 32'h00000000);
      check_mem_value(`SPAD(32'h00), 32'h00000001);

      //=================================================================
      // END OF TEST -- the hart cannot reach 0xdeadbeef by design.
      //=================================================================
      random_irq_enable = 0;
      repeat(10) @(posedge free_clk);
      stimulus_done = 1;
   end

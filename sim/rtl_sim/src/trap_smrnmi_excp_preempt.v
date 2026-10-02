//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_smrnmi_excp_preempt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: NMI PREEMPTS AN IN-FLIGHT POSTED STORE -> FAULT STILL REPORTED
//   A pin NMI preempting the store does not lose its fault: the error
//   sets a sticky nmi_bus_pending, so it is delivered as a second RNMI after
//   the pin one. Two deliveries, in source order: mncause 2 then 3.
//   The store is still not replayed -- mnepc stays strictly past its PC.
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  ((byte_off)/4)

reg [31:0] store_fault_pc;

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      // Both the NMI entry AND the synchronous store-access-fault look
      // like exceptions to the monitor -- do not treat them as errors.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init complete -> latch nmi_vector + faulting-store PC
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 1: INIT + CONFIGURE NMI VECTOR / READ FAULTING-STORE PC    |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware (pre-store sentinel)...");

      // `wait`, not `@`: the firmware reaches this sentinel during the peripheral-reset
      // sequence above, so by the time this line runs x31 may ALREADY hold the value.
      // `@(expr)` waits for an event on expr and would then block forever, which is
      // exactly what happened when the testbench arrived after the firmware.
      wait (probes_cpu.x31==32'h11111111);

      begin : setup_nmi_vector
         reg [31:0] handler_addr;
         handler_addr   = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)];
         store_fault_pc = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h0C)];

         $display("NMI handler address  : 0x%h %t ns", handler_addr,   $time);
         $display("Faulting store PC    : 0x%h %t ns", store_fault_pc, $time);

         if (handler_addr == 32'h0) begin
            $display("ERROR: nmi_handler addr in scratchpad is 0 %t ns", $time);
            error = error + 1;
         end
         if (store_fault_pc == 32'h0) begin
            $display("ERROR: store_fault PC in scratchpad is 0 %t ns", $time);
            error = error + 1;
         end

      end

      // Armed: release the firmware, which is spinning on this slot. Until this
      // write it cannot reach the faulting store, so the PC window below cannot be
      // missed however the simulator schedules us. Before the handshake the store
      // was the very next instruction after the sentinel and a single cycle of
      // testbench latency lost the window -- which is what made this test pass on
      // Icarus and hang on Verilator.
      ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h1C)] = 32'h1;


      //=================================================================
      // PHASE 2: assert NMI on the precise cycle the faulting store
      //          reaches decode -> NMI preempts the store before it
      //          completes / before its synchronous exception is taken.
      //
      // The pre-store sentinel is the LAST instruction before the store,
      // so the very next decode-stage PC is store_fault. Waiting on
      // probes_cpu.pc == store_fault (level-sensitive) and asserting NMI
      // on the next edge guarantees the store has not completed its AHB
      // data phase when the NMI is taken.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 2: PREEMPT FAULTING STORE WITH NMI (PC-TIMED)              |");
      $display(" ====================================================================");
      $display("");

      wait (probes_cpu.pc == store_fault_pc);
      $display("Decode PC reached faulting store 0x%h -- asserting NMI %t ns",
               store_fault_pc, $time);
      @(negedge free_clk);
      nmi = 1'b1;
      repeat(3) @(posedge free_clk);
      nmi = 1'b0;
      $display("NMI asserted (3 cycles) and deasserted %t ns", $time);


      //=================================================================
      // PHASE 3: verify the ACCEPTED DEVIATION -- the in-flight store-
      //          access-fault is DROPPED, the NMI is serviced, and the
      //          program resumes strictly past the (not-replayed) store.
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|   PHASE 3: VERIFY ACCEPTED DEVIATION (FAULT DROPPED, NMI SERVICED) |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware (end sentinel)...");

      wait (probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      // --- NMI actually fired exactly once (async trap serviced) ---
      $display("");
      $display("--- mncause of each RNMI delivered (2 = pin, 3 = data-bus error) ---");
      $display("     #1 = 0x%h   #2 = 0x%h",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h20)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h24)]);

      $display("--- two RNMIs: the pin, then the preempted store's bus error ---");
      check_mem_value(`SPAD(32'h00), 32'h00000002);
      check_mem_value(`SPAD(32'h20), 32'h80000002);   // #1 pin
      check_mem_value(`SPAD(32'h24), 32'h80000003);   // #2 data-bus error

      // mncause is latched at nmi_detect, not sampled at trap_taken: the pin
      // can deassert in the cycle between, which reported a pin NMI as cause 3.

      // --- DEVIATION-LOCK MNEPC CHECK (contract-derived, bug-sensitive) ---
      // The store is posted/committed and NOT replayed by MNRET, so the
      // resume PC must be STRICTLY PAST the store. A spec-strict
      // implementation would instead resume ON the store (mnepc ==
      // store_fault PC) so it could replay+fault -- that would FAIL here,
      // which is exactly the desired tripwire. The exact offset (+4/+8...)
      // is a pipeline-depth artefact and is deliberately NOT asserted.
      $display("");
      $display("--- MNEPC deviation check (contract: STRICTLY PAST store PC) ---");
      begin : check_mnepc
         reg [31:0] mnepc_val;
         mnepc_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h10)];

         $display("MNEPC captured in NMI handler : 0x%h %t ns", mnepc_val,      $time);
         $display("Faulting store PC             : 0x%h %t ns", store_fault_pc, $time);

         if (mnepc_val === store_fault_pc) begin
            $display("ERROR: MNEPC (0x%h) == store PC -- store was REPLAYED (spec-strict resumability); the accepted posted-store deviation requires it NOT be replayed %t ns",
                     mnepc_val, $time);
            error = error + 1;
         end else if (mnepc_val > store_fault_pc) begin
            $display("PASS:  MNEPC (0x%h) > store PC (0x%h) -- store posted/committed, NOT replayed (accepted deviation) %t ns",
                     mnepc_val, store_fault_pc, $time);
         end else begin
            $display("ERROR: MNEPC (0x%h) < store PC (0x%h) or X -- nonsensical resume point %t ns",
                     mnepc_val, store_fault_pc, $time);
            error = error + 1;
         end
      end

      // The fault is reported through the RNMI, never through mtvec:
      // mcause 5/7 are RESERVED.
      $display("");
      $display("--- no synchronous exception: mtvec is never entered ---");
      check_mem_value(`SPAD(32'h04), 32'h00000000);

      $display("");
      $display("--- MCAUSE slot (expect 0: mtvec handler never ran) ---");
      check_mem_value(`SPAD(32'h14), 32'h00000000);

      $display("");
      $display("--- MEPC slot (expect 0: mtvec handler never ran) ---");
      check_mem_value(`SPAD(32'h18), 32'h00000000);

      // --- Sentinel register survived NMI + resume (no corruption) ---
      $display("");
      $display("--- Register preservation (s2 = 0xA5A5A5A5) ---");
      check_cpu_reg(18, 32'hA5A5A5A5);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

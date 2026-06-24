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
// Description: ACCEPTED-DEVIATION LOCK
//   NMI PREEMPTS AN IN-FLIGHT POSTED STORE -> FAULT DROPPED
//----------------------------------------------------------------------------

`define LONG_TIMEOUT

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Scratchpad word address offset (byte address / 4)
// SRAM base is 0x80000000, word-addressed starting at 0
`define SPAD(byte_off)  (byte_off/4)

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

      @(probes_cpu.x31==32'h11111111);

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

         nmi_vector = handler_addr;
      end

      // NOTE: do NOT issue any clock-consuming task (check_mem_value,
      // @(posedge), repeat) between here and the wait() below -- the
      // faulting store is the very next instruction after the sentinel,
      // so any consumed cycle misses the PC window and the level-
      // sensitive wait() would block forever.


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

      @(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      // --- NMI actually fired exactly once (async trap serviced) ---
      $display("");
      $display("--- NMI count (expect 1) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000001);

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

      // --- THE DEVIATION: the store-access-fault was NEVER reported ---
      // (spec-strict would be exc_count==1, mcause==7, mepc==store PC)
      $display("");
      $display("--- Exception count (expect 0: fault DROPPED) ---");
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

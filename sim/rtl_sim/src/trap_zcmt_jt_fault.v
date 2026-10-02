//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_zcmt_jt_fault
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// !! OPEN RTL BUG -- this test FAILS on purpose. !!
//
// The RNMI half is correct: 2 RNMIs, mncause=0x80000003 each. What fails is
// "mtvec must never be entered": it IS, with mcause=1 (instruction access
// fault) and mepc=0.
//
// ROOT CAUSE (traced, cycles 76-79): mnepc is captured as 0.
//
//   cycle 78  dph_error=1, jt_fault_exit=1 -> ex_uop_jt_active CLEARED
//   cycle 79  nmi_detect=1, ex_uop_jt_active=0, id_pc=0x00000000
//                                               ex_pc =0x200000D4  (the cm.jt)
//
// trap_pc_to_save (arv_csr_traps.v:2230) guards its cm.jt arm on
// ex_uop_jt_active_i, but jt_fault_exit has already cleared that a cycle
// earlier, so the cascade falls through to `nmi_detect ? id_pc_i` -- and id_pc
// is 0 while the JT abort is draining. mnret then returns to 0.
//
// NOT a poisoned branch target: an errored load leaves dph_valid low
// (arv_load_store.v:168), so wb_ldst_wr never strobes, jt_branch_active is
// never set, and the JVT read data is never captured.
//
// This breaks the invariant the comment at :2239 states -- "mnepc is the
// RESUME POINT, so mnret always makes forward progress". Left asserting the
// strict expectation until the resume PC for an aborted cm.jt is decided.
//
// Description: CM.JT/JALT LOAD ACCESS-FAULT TRAP
//   Verifies that an unmapped JVT[i] load takes a load access-fault trap and
//   the JT FSM does not livelock. Requires C_EXTENSION>=4 (Zcmt).
//----------------------------------------------------------------------------

`define LONG_TIMEOUT


integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

task check_jt_report(input [63:0] what);
   reg [31:0] mnepc_rb, estat_rb, pc_rb;
   begin
      mnepc_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)];
      estat_rb = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)];
      pc_rb    = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h38)];
      $display("%0s: mnepc=0x%h (published PC 0x%h)  estat=0x%h restartable=%0d",
               what, mnepc_rb, pc_rb, estat_rb, estat_rb[3]);
      // mnepc must name the aborted table jump, NOT 0 and NOT the resume point.
      if (mnepc_rb !== pc_rb) begin
         $display("ERROR: mnepc does not identify the aborted table jump %t ns", $time);
         error = error + 1;
      end
      // A JT table read can never be replayed: re-executing re-reads the same
      // entry and takes the same hard error.
      if (estat_rb[3] !== 1'b0) begin
         $display("ERROR: restartable=1 for a Zcmt table read -- replay would loop %t ns", $time);
         error = error + 1;
      end
   end
endtask

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

      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init
      //=================================================================
      $display("");
      $display(" PHASE 1: init");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h11111111);
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
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // PHASE 2: cm.jt 0 with JVT=0 -> load access fault must deliver
      //=================================================================
      $display("");
      $display(" PHASE 2: cm.jt with unmapped JVT load");
      $display("Waiting for cm.jt entry marker...");
      @(probes_cpu.x31==32'h12121212);

      $display("Waiting for the firmware (post-trap recovery)...");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);

      check_mem_value(`SPAD(32'h24), 32'h00000001);                  // 1 RNMI delivered
      check_mem_value(`SPAD(32'h28), 32'h80000003);                  // mncause = bus error
      check_mem_value(`SPAD(32'h00), 32'h00000000);                  // mtvec NEVER entered
      check_jt_report("cm.jt");


      //=================================================================
      // PHASE 3: cm.jalt 32 -> same fault path on the JALT variant
      //=================================================================
      $display("");
      $display(" PHASE 3: cm.jalt with unmapped JVT load");
      $display("Waiting for cm.jalt entry marker...");
      @(probes_cpu.x31==32'h32323232);

      $display("Waiting for the firmware (post-trap recovery)...");
      @(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);

      $display("DIAG: mcause=0x%h mepc=0x%h trap_count=%0d mnepc=0x%h estat=0x%h marv_epc=0x%h",
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h04)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h08)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h00)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h2C)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h30)],
               ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h34)]);
      check_mem_value(`SPAD(32'h24), 32'h00000002);                  // 2 RNMIs total
      check_mem_value(`SPAD(32'h28), 32'h80000003);                  // mncause = bus error
      check_mem_value(`SPAD(32'h00), 32'h00000000);                  // mtvec NEVER entered
      check_jt_report("cm.jalt");


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

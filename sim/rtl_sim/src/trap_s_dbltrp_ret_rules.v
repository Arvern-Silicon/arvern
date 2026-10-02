//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_s_dbltrp_ret_rules
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: TRAP S DBLTRP RET RULES (Ssdbltrp xRET / SIE-SDT interlock)
//   Requires SU_MODE_EN==1. Directed checks of the sstatus.SDT rules:
//   MRET/MNRET clear SDT only when the new privilege mode is U (a return to
//   S or M keeps it); SRET clears it unconditionally; an explicit CSR write
//   that sets SDT=1 forces SIE=0, and SIE can only be set to 1 when SDT is
//   0 or is being cleared by the same write.
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

      error_on_exception = 0;
      random_irq_enable  = 0;

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 1: (a)/(b) MRET to S keeps SDT, MRET to U clears it |");
      $display(" ============================================================");

      wait(probes_cpu.x31 == 32'h11111111);
      repeat(40) @(posedge free_clk);   // drain posted, wait-stated stores before reading the scratchpad

      $display("--- SDT set through the mstatus alias reads 1 ---");
      check_mem_value(`SPAD(32'h00), 32'h01000000);

      wait((probes_cpu.x31 == 32'h22222222) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(40) @(posedge free_clk);   // drain posted, wait-stated stores before reading the scratchpad

      $display("--- (a) MRET with MPP=S keeps SDT=1 ---");
      check_mem_value(`SPAD(32'h04), 32'h01000000);

      $display("--- (a) MRET with MPP=M keeps SDT=1 ---");
      check_mem_value(`SPAD(32'h08), 32'h01000000);

      $display("--- (b) MRET with MPP=U clears SDT ---");
      check_mem_value(`SPAD(32'h0C), 32'h00000000);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 2: (c) SRET clears SDT unconditionally              |");
      $display(" ============================================================");

      wait((probes_cpu.x31 == 32'h33333333) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(40) @(posedge free_clk);   // drain posted, wait-stated stores before reading the scratchpad

      $display("--- (c) S handler entered exactly once, SDT set by HW ---");
      check_mem_value(`SPAD(32'h18), 32'h00000001);
      check_mem_value(`SPAD(32'h10), 32'h01000000);

      $display("--- (c) SRET back to S cleared SDT ---");
      check_mem_value(`SPAD(32'h14), 32'h00000000);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 3: (d)-(g) SDT / SIE write interlock                |");
      $display(" ============================================================");

      wait((probes_cpu.x31 == 32'h44444444) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(40) @(posedge free_clk);   // drain posted, wait-stated stores before reading the scratchpad

      $display("--- (d) csrs sstatus SDT|SIE -> SDT=1, SIE=0 ---");
      check_mem_value(`SPAD(32'h1C), 32'h01000000);

      $display("--- (e) csrs SIE while SDT=1 -> SIE stays 0 ---");
      check_mem_value(`SPAD(32'h20), 32'h01000000);

      $display("--- (e) csrw with SDT=1, SIE=1 -> SIE stays 0 ---");
      check_mem_value(`SPAD(32'h24), 32'h01000000);

      $display("--- (f) csrw clearing SDT and setting SIE -> SIE=1 ---");
      check_mem_value(`SPAD(32'h28), 32'h00000002);

      $display("--- (g) SDT=0, csrs SIE -> SIE=1 ---");
      check_mem_value(`SPAD(32'h2C), 32'h00000002);

      $display("--- (d') csrs mstatus SDT|SIE -> SDT=1, SIE=0 ---");
      check_mem_value(`SPAD(32'h30), 32'h01000000);

      $display("");
      $display(" ============================================================");
      $display("|  PHASE 4: (h) MNRET to S keeps SDT, MNRET to U clears it   |");
      $display(" ============================================================");

      $display("Waiting for end of test...");

      wait((probes_cpu.x31 == 32'hdeadbeef) || (probes_cpu.x31 == 32'h0BADBADB));
      repeat(5) @(posedge free_clk);

      $display("--- (h) MNRET with MNPP=S keeps SDT=1 ---");
      check_mem_value(`SPAD(32'h34), 32'h01000000);

      $display("--- (h) MNRET with MNPP=U clears SDT ---");
      check_mem_value(`SPAD(32'h38), 32'h00000000);

      $display("--- M trampoline entered 5 times, no double trap, last cause 8 ---");
      check_mem_value(`SPAD(32'h3C), 32'h00000005);
      check_mem_value(`SPAD(32'h40), 32'h00000008);

      $display("--- final flag ---");
      check_mem_value(`SPAD(32'h44), 32'h000000AA);

      $display("--- x31 PASS sentinel ---");
      check_cpu_reg(31, 32'hdeadbeef);

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

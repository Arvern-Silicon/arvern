//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_std_system_reserved
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: RESERVED SYSTEM ENCODINGS -> ILLEGAL
//   Verifies 5 reserved SYSTEM words each raise illegal-instruction
//   (mcause=2), the real ECALL raises mcause=11, and the legal CSR access
//   does not trap (illegal_count stays at 5, ecall_count == 1).
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

`define SPAD(byte_off)  (byte_off/4)

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

      // Reserved SYSTEM encodings and one ECALL are expected to trap.
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: init
      //=================================================================
      $display("");
      $display(" PHASE 1: init");
      $display("Waiting for the firmware...");
      @(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000000);   // illegal_count
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // ecall_count
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // other_count


      //=================================================================
      // PHASE 2: funct3=100 reserved (all-zero fields) -> mcause=2
      //=================================================================
      $display("");
      $display(" PHASE 2: SYSTEM funct3=100 (0x00004073)");
      @(probes_cpu.x31==32'h22222222);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000001);   // illegal_count = 1
      check_mem_value(`SPAD(32'h0C), 32'h00000002);   // MCAUSE = 2
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // no ECALL yet
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // no other


      //=================================================================
      // PHASE 3: funct3=100 reserved (rs1 set) -> mcause=2
      //=================================================================
      $display("");
      $display(" PHASE 3: SYSTEM funct3=100 (0x001F4073)");
      @(probes_cpu.x31==32'h33333333);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000002);
      check_mem_value(`SPAD(32'h0C), 32'h00000002);
      check_mem_value(`SPAD(32'h08), 32'h00000000);


      //=================================================================
      // PHASE 4: ECALL-shaped, rd!=0 -> reserved -> mcause=2
      //=================================================================
      $display("");
      $display(" PHASE 4: ECALL-shaped rd=x30 (0x00000F73)");
      @(probes_cpu.x31==32'h44444444);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000003);
      check_mem_value(`SPAD(32'h0C), 32'h00000002);
      check_mem_value(`SPAD(32'h04), 32'h00000000);   // still NOT an ECALL
      check_mem_value(`SPAD(32'h08), 32'h00000000);


      //=================================================================
      // PHASE 5: ECALL-shaped, rs1!=0 -> reserved -> mcause=2
      //=================================================================
      $display("");
      $display(" PHASE 5: ECALL-shaped rs1=x30 (0x000F0073)");
      @(probes_cpu.x31==32'h55555555);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000004);
      check_mem_value(`SPAD(32'h0C), 32'h00000002);
      check_mem_value(`SPAD(32'h04), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000000);


      //=================================================================
      // PHASE 6: funct3=000 imm12=0x002 reserved -> mcause=2
      //=================================================================
      $display("");
      $display(" PHASE 6: SYSTEM imm12=0x002 (0x00200073)");
      @(probes_cpu.x31==32'h66666666);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000005);   // 5 illegal traps total
      check_mem_value(`SPAD(32'h0C), 32'h00000002);
      check_mem_value(`SPAD(32'h04), 32'h00000000);
      check_mem_value(`SPAD(32'h08), 32'h00000000);


      //=================================================================
      // PHASE 7: POSITIVE CONTROL -- a real ECALL -> mcause=11
      //          illegal_count must NOT advance.
      //=================================================================
      $display("");
      $display(" PHASE 7: real ECALL (positive control)");
      @(probes_cpu.x31==32'h77777777);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000005);   // still 5 (ECALL not illegal)
      check_mem_value(`SPAD(32'h04), 32'h00000001);   // ecall_count = 1
      check_mem_value(`SPAD(32'h0C), 32'h0000000B);   // MCAUSE = 11
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // no other


      //=================================================================
      // PHASE 8: POSITIVE CONTROL -- legal CSR access (no trap)
      //          illegal_count unchanged; CSR readback correct.
      //=================================================================
      $display("");
      $display(" PHASE 8: legal CSR access (positive control)");
      // Level wait (not edge) for the final sentinel: with the firmware
      // load-back fence in the .s the store at 0x10 is already globally
      // visible before x31 is set, so the existing slack is sufficient.
      wait(probes_cpu.x31==32'hdeadbeef);
      repeat(3) @(posedge free_clk);
      check_mem_value(`SPAD(32'h00), 32'h00000005);   // still 5
      check_mem_value(`SPAD(32'h04), 32'h00000001);   // still 1
      check_mem_value(`SPAD(32'h08), 32'h00000000);   // still 0
      check_mem_value(`SPAD(32'h10), 32'h0BADF00D);   // csrr mscratch readback


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      inst_rv32e_basic
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: RV32E BASIC (TEMPLATE)
//   RV32E SANITY TEST + REUSABLE TEMPLATE for all future RV32E tests.
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

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;


      $display("");
      $display(" ====================================================================");
      $display("|             RV32E BASIC: CHECK INIT REGISTER VALUES                |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'hFFFFFFFF);   // SYNC 0: init done

      check_cpu_reg(1,  32'hffffffff);
      check_cpu_reg(2,  32'hffffffff);
      check_cpu_reg(3,  32'hffffffff);
      check_cpu_reg(4,  32'hffffffff);
      check_cpu_reg(5,  32'hffffffff);
      check_cpu_reg(6,  32'hffffffff);
      check_cpu_reg(7,  32'hffffffff);
      check_cpu_reg(8,  32'hffffffff);
      check_cpu_reg(9,  32'hffffffff);
      check_cpu_reg(10, 32'hffffffff);
      check_cpu_reg(11, 32'hffffffff);
      check_cpu_reg(12, 32'hffffffff);
      check_cpu_reg(13, 32'hffffffff);
      check_cpu_reg(14, 32'hffffffff);
      check_cpu_reg(15, 32'hffffffff);


      $display("");
      $display(" ====================================================================");
      $display("|        RV32E BASIC: CHECKPOINT 1 (ALU reg-imm / reg-reg)           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h11111111);   // SYNC 1

      check_cpu_reg(1,  32'h00000064);   // 100
      check_cpu_reg(2,  32'h0000007B);   // addi 100+23
      check_cpu_reg(3,  32'h000000F0);
      check_cpu_reg(4,  32'h0000000F);
      check_cpu_reg(5,  32'h000000FF);   // add
      check_cpu_reg(6,  32'h000000E1);   // sub
      check_cpu_reg(7,  32'h00000000);   // and
      check_cpu_reg(8,  32'h000000FF);   // or
      check_cpu_reg(9,  32'h000000FF);   // xor
      check_cpu_reg(12, 32'h00000010);   // sll 1<<4
      check_cpu_reg(14, 32'h08000000);   // srl 0x80000000>>4


      $display("");
      $display(" ====================================================================");
      $display("|     RV32E BASIC: CHECKPOINT 2 (sra/slt/sltu, lui, auipc)           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h22222222);   // SYNC 2

      check_cpu_reg(3,  32'hFFFFFFFC);   // sra -16>>2 = -4
      check_cpu_reg(6,  32'h00000001);   // slt  -5 < 3  signed
      check_cpu_reg(7,  32'h00000000);   // sltu -5 < 3  unsigned (false)
      check_cpu_reg(8,  32'h00000001);   // slti -5 < 0
      check_cpu_reg(9,  32'h00000001);   // sltiu 3 < 10
      check_cpu_reg(10, 32'hABCDE000);   // lui
      check_cpu_reg(13, 32'h00000000);   // auipc base == la(label) -> 0


      $display("");
      $display(" ====================================================================");
      $display("|   RV32E BASIC: CHECKPOINT 3 (byte/half/word load-store)            |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h33333333);   // SYNC 3

      check_cpu_reg(1,  32'hDEADBEEF);   // word round-trip
      check_cpu_reg(2,  32'hFFFFFFF5);   // lb  sign-extended 0xF5
      check_cpu_reg(3,  32'h000000F5);   // lbu zero-extended 0xF5
      check_cpu_reg(4,  32'hFFFF8123);   // lh  sign-extended 0x8123
      check_cpu_reg(5,  32'h00008123);   // lhu zero-extended 0x8123
      check_cpu_reg(6,  32'h01020304);   // word round-trip 2


      $display("");
      $display(" ====================================================================");
      $display("|        RV32E BASIC: CHECKPOINT 4 (misa RV32E identity bits)        |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h44444444);   // SYNC 4: misa

      // x11 = misa & 0xC0000110, isolating ONLY the RV32E_EN-deterministic
      // bits {31,30,8,4}.  Expected 0x40000010 = MXL=01 (bit31=0,bit30=1)
      // | E set (bit4=1), with I clear (bit8=0) and all config-dependent
      // extension bits (M/C/B/F/...) masked out.  This asserts the RV32E
      // base-ISA identity advertised by misa @0x301 in M-mode.
      check_cpu_reg(11, 32'h40000010);


      $display("");
      $display(" ====================================================================");
      $display("|   RV32E BASIC: FINAL (branches taken/not-taken, jal/jalr)          |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      wait(probes_cpu.x15==32'hdeadbeef);   // FINAL SYNC (level wait)

      // Disable random IRQ injection before final register checks
      random_irq_enable = 0;

      check_cpu_reg(10, 32'h00000FFF);   // a0: all 12 branch sub-checks set
      check_cpu_reg(2,  32'h0000600D);   // jalr landed at jalr_land
      check_cpu_reg(3,  32'h600D600D);   // jal_target executed (good marker)
      // x1(ra) is intentionally clobbered by the jal/jalr link path
      // and is NOT checked here.

      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

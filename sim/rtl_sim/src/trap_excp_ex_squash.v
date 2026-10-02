//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_excp_ex_squash
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: EX-STAGE EXCEPTION vs THE YOUNGER INSTRUCTION IN ID
//   For every case the firmware ran (flag at +4C): exactly one trap, with the
//   expected mcause/mepc/mtval, every piece of state the younger instruction
//   could modify unchanged when the handler ran, and (with Zicntr) a minstret
//   difference proving the younger instruction did not retire. A probe also
//   counts the cycles where the squash met a consumed ID instruction, so a
//   pipeline change that stops reaching that corner fails the test.
//----------------------------------------------------------------------------

integer ii;
integer kk;
integer base;
integer ncases;
integer nexpected;
integer squash_hits;
reg [8*6-1:0] state_name;

`define SPAD_W(byte_addr)  (((byte_addr) - 32'h80000000) / 4)

task check_word;
   input [31:0] byte_addr;
   input [31:0] expected;
   input [8*32-1:0] what;
   reg   [31:0] got;
   begin
      got = ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(byte_addr)];
      if (got !== expected) begin
         $display("ERROR: case %0d %0s = 0x%h, expected 0x%h  %t ns", kk, what, got, expected, $time);
         error = error + 1;
      end
   end
endtask

// EX-stage exception squash while decode hands a valid ID instruction to fetch
initial squash_hits = 0;
always @(posedge dut.hclk_i)
   if (dut.arv_decode_inst.ex_excp_squash_i & dut.arv_decode_inst.id_instruction_request_o &
       dut.arv_decode_inst.id_instruction_valid_i)
      squash_hits = squash_hits + 1;

// CM.PUSH (case 19) is a 16-bit parcel the STD-mode golden trace does not hold
initial
   begin
      @(probes_cpu.x31==32'h33333333);
      checker_enable = 0;
      @(probes_cpu.x31==32'h44444444);
      checker_enable = 1;
   end

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      // The cases trap on purpose (and case 3 speculatively fetches address 0)
      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|  EX-STAGE EXCEPTION vs YOUNGER INSTRUCTION                         |");
      $display(" ====================================================================");
      $display("");

      @(probes_cpu.x31==32'h11111111);
      $display("Init done, waiting for the cases...");

      @(probes_cpu.x31==32'h22222222);
      repeat(40) @(posedge free_clk);

      ncases = 0;
      for (kk = 0; kk < 21; kk = kk + 1) begin
         base = 32'h80000100 + kk*32'h60;
         if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(base + 32'h4C)] == 32'h1) begin
            ncases = ncases + 1;
            check_word(base + 32'h0C, 32'h1,                                                        "trap count");
            check_word(base + 32'h00, ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(base + 32'h44)], "mcause");
            check_word(base + 32'h04, ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(base + 32'h40)], "mepc");
            check_word(base + 32'h08, ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(base + 32'h48)], "mtval");
            for (ii = 0; ii < 6; ii = ii + 1) begin
               case (ii)
                  0: state_name = "s2";
                  1: state_name = "ra";
                  2: state_name = "sp";
                  3: state_name = "mscr";
                  4: state_name = "[s4]";
                  default: state_name = "pmpa1";
               endcase
               check_word(base + 32'h28 + ii*4, ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(base + 32'h10 + ii*4)], {"state ", state_name});
            end
            if (ZICNTR_EN)
               check_word(base + 32'h58,
                          ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(base + 32'h54)] +
                          ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(base + 32'h5C)], "minstret in the handler");
         end
      end
      // CM.PUSH executed once the handler returned to it
      kk = 19;
      if (ahb_bus_system_inst.sram_x_inst.mem[`SPAD_W(32'h80000100 + 19*32'h60 + 32'h4C)] == 32'h1)
         check_word(32'h80000100 + 19*32'h60 + 32'h50, 32'hA0000013, "pushed ra");

      nexpected = 15 + ((PMP_NR > 0) ? 5 : 0) + ((C_EXTENSION >= 3) ? 1 : 0);
      $display("Checked %0d cases, squash corner hit %0d times", ncases, squash_hits);
      if (ncases != nexpected) begin
         $display("ERROR: %0d cases ran, %0d expected", ncases, nexpected);
         error = error + 1;
      end
`ifndef ROM_RANDOM_WS
      // Random instruction-fetch wait states can leave ID empty in the fault cycle,
      // so the corner is only required with a deterministic fetch.
      if (squash_hits == 0) begin
         $display("ERROR: the squash never met a consumed ID instruction");
         error = error + 1;
      end
`endif

      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

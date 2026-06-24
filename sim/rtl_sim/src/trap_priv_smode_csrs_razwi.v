//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_priv_smode_csrs_razwi
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: SU_MODE PRIV - S-mode shadow CSRs RAZ/WI + misa S/U bits = 0
//   Verify the full S-mode shadow set is RAZ/WI under SU_MODE_EN=0:
//   sstatus, sie, stvec, scounteren, sscratch, sepc, scause, stval, sip, satp.
//   No access must trap. misa[18] (S) and misa[20] (U) must read 0.
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

      // No traps expected -- but keep error_on_exception=0 so the trap_count
      // check below is the authoritative "no-trap" assertion (matches the
      // inst_csr_smode_warl convention).
      error_on_exception = 0;


      //=================================================================
      // PHASE 1: Initialization complete
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                 PHASE 1: CHECK INITIALIZATION                      |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h11111111);
      repeat(3) @(posedge free_clk);


      //=================================================================
      // PHASE 2: Read all 10 S-mode CSRs at reset (expect 0, no trap)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 2: S-MODE SHADOW CSR READS = 0 (no trap)               |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h22222222);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- sstatus(0x100) sie(0x104) stvec(0x105) scounteren(0x106) ---");
      check_mem_value(`SPAD(32'h20), 32'h00000000);  // sstatus
      check_mem_value(`SPAD(32'h24), 32'h00000000);  // sie
      check_mem_value(`SPAD(32'h28), 32'h00000000);  // stvec
      check_mem_value(`SPAD(32'h2C), 32'h00000000);  // scounteren
      $display("--- sscratch(0x140) sepc(0x141) scause(0x142) stval(0x143) ---");
      check_mem_value(`SPAD(32'h30), 32'h00000000);  // sscratch
      check_mem_value(`SPAD(32'h34), 32'h00000000);  // sepc
      check_mem_value(`SPAD(32'h38), 32'h00000000);  // scause
      check_mem_value(`SPAD(32'h3C), 32'h00000000);  // stval
      $display("--- sip(0x144) satp(0x180) ---");
      check_mem_value(`SPAD(32'h40), 32'h00000000);  // sip
      check_mem_value(`SPAD(32'h44), 32'h00000000);  // satp


      //=================================================================
      // PHASE 3: Write 0xDEADBEEF to each, re-read (expect still 0)
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 3: S-MODE SHADOW CSR WRITES IGNORED (RAZ/WI)           |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'h33333333);
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- sstatus/sie/stvec/scounteren after 0xDEADBEEF write ---");
      check_mem_value(`SPAD(32'h50), 32'h00000000);
      check_mem_value(`SPAD(32'h54), 32'h00000000);
      check_mem_value(`SPAD(32'h58), 32'h00000000);
      check_mem_value(`SPAD(32'h5C), 32'h00000000);
      $display("--- sscratch/sepc/scause/stval after 0xDEADBEEF write ---");
      check_mem_value(`SPAD(32'h60), 32'h00000000);
      check_mem_value(`SPAD(32'h64), 32'h00000000);
      check_mem_value(`SPAD(32'h68), 32'h00000000);
      check_mem_value(`SPAD(32'h6C), 32'h00000000);
      $display("--- sip/satp after 0xDEADBEEF write ---");
      check_mem_value(`SPAD(32'h70), 32'h00000000);
      check_mem_value(`SPAD(32'h74), 32'h00000000);


      //=================================================================
      // PHASE 4: misa S/U bits = 0
      //=================================================================
      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|       PHASE 4: misa[S]=0 AND misa[U]=0                             |");
      $display(" ====================================================================");
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x15==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(3) @(posedge free_clk);

      $display("");
      $display("--- misa[18] (S-bit) must be 0 ---");
      begin : check_misa_s
         reg [31:0] misa_val;
         misa_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h80)];
         if (misa_val[18] !== 1'b0) begin
            $display("ERROR: misa[18] (S) expected 0 -- misa=0x%h %t ns", misa_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  misa[18] (S) = 0 -- misa=0x%h %t ns", misa_val, $time);
         end
      end

      $display("");
      $display("--- misa[20] (U-bit) must be 0 ---");
      begin : check_misa_u
         reg [31:0] misa_val;
         misa_val = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h80)];
         if (misa_val[20] !== 1'b0) begin
            $display("ERROR: misa[20] (U) expected 0 -- misa=0x%h %t ns", misa_val, $time);
            error = error + 1;
         end else begin
            $display("PASS:  misa[20] (U) = 0 -- misa=0x%h %t ns", misa_val, $time);
         end
      end


      //=================================================================
      // FINAL: trap_count must still be 0 (no S-mode CSR access trapped)
      //=================================================================
      $display("");
      $display("--- trap_count = 0 (no S-CSR access raised a trap) ---");
      check_mem_value(`SPAD(32'h00), 32'h00000000);


      //=================================================================
      // END OF TEST
      //=================================================================
      $display("");
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

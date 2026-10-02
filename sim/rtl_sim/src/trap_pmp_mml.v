//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      trap_pmp_mml
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Smepmp Machine Mode Lockdown -- the full mseccfg.MML truth table
//
//   The firmware probes every LRWX encoding six ways and records the trap
//   cause per probe (0 = no trap). The expected causes are derived here from
//   the table in Priv 6.2.1, not from the RTL, so a disagreement is a real
//   one. Per row: {M read, M write, M exec, S/U read, S/U write, S/U exec}.
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

// Priv 6.2.1, "Truth table when mseccfg.MML is set". Index = LRWX.
reg [5:0] mml_perm [0:15];
initial begin
    //               Mr Mw Mx Sr Sw Sx
    mml_perm[ 0] = 6'b000_000;   // 0000  inaccessible
    mml_perm[ 1] = 6'b000_001;   // 0001  S/U execute-only
    mml_perm[ 2] = 6'b110_100;   // 0010  shared data: M rw, S/U r
    mml_perm[ 3] = 6'b110_110;   // 0011  shared data: M rw, S/U rw
    mml_perm[ 4] = 6'b000_100;   // 0100  S/U read-only
    mml_perm[ 5] = 6'b000_101;   // 0101  S/U read/execute
    mml_perm[ 6] = 6'b000_110;   // 0110  S/U read/write
    mml_perm[ 7] = 6'b000_111;   // 0111  S/U rwx
    mml_perm[ 8] = 6'b000_000;   // 1000  locked, inaccessible
    mml_perm[ 9] = 6'b001_000;   // 1001  M execute-only
    mml_perm[10] = 6'b001_001;   // 1010  shared code: x for both
    mml_perm[11] = 6'b101_001;   // 1011  shared code: M rx, S/U x
    mml_perm[12] = 6'b100_000;   // 1100  M read-only
    mml_perm[13] = 6'b101_000;   // 1101  M read/execute  (the ROM)
    mml_perm[14] = 6'b110_000;   // 1110  M read/write
    mml_perm[15] = 6'b100_100;   // 1111  shared read-only
end

initial
   begin
      @(posedge free_clk);
      @(posedge hresetn);

      error_on_exception = 0;

      $display("");
      $display(" ====================================================================");
      $display("|             Smepmp MML -- 16 ROWS x {M,U} x {LOAD,STORE,EXEC}      |");
      $display(" ====================================================================");
      $display("");

      wait(probes_cpu.x31==32'h11111111);
      repeat(3) @(posedge free_clk);

      begin : check_table
         reg [31:0] got;
         reg [31:0] expct;
         reg [5:0]  p;
         integer    row, probe, bad;
         bad = 0;
         for (row = 0; row < 16; row = row + 1) begin
            p = mml_perm[row];
            for (probe = 0; probe < 6; probe = probe + 1) begin
               case (probe)
                  0: expct = p[5] ? 32'd0  : 32'd5;   // M load
                  1: expct = p[4] ? 32'd0  : 32'd7;   // M store
                  2: expct = p[3] ? 32'd11 : 32'd1;   // M exec  -> ECALL from M, or refused
                  3: expct = p[2] ? 32'd0  : 32'd5;   // U load
                  4: expct = p[1] ? 32'd0  : 32'd7;   // U store
                  5: expct = p[0] ? 32'd8  : 32'd1;   // U exec  -> ECALL from U, or refused
               endcase
               got = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(32'h100 + (row*6 + probe)*4)];
               if (got !== expct) begin
                  $display("ERROR: LRWX=%b probe %0d (%s): cause %0d, expected %0d   %t ns",
                           row[3:0], probe,
                           probe==0 ? "M load " : probe==1 ? "M store" : probe==2 ? "M exec " :
                           probe==3 ? "U load " : probe==4 ? "U store" : "U exec ",
                           got, expct, $time);
                  error = error + 1;
                  bad = bad + 1;
               end
            end
         end
         if (bad == 0)
            $display("PASS:  all 96 probes match the Priv 6.2.1 table   %t ns", $time);
      end

      $display("--- mseccfg.MML sticky, locked M-execute rule refused after MML ---");
      check_cpu_reg(10, 32'h00000001);   // a0: MML read back set
      check_cpu_reg(11, 32'h00000001);   // a1: still set after a clear attempt
      check_cpu_reg(12, 32'h1E1A1C18);   // a2: pmpcfg0 unchanged by the LRWX=1001 write

      //=================================================================
      // M-executable pmpcfg encodings refused per entry (Smepmp 4b)
      //=================================================================
      wait(probes_cpu.x31==32'h22222222);
      repeat(40) @(posedge free_clk);
      $display("");
      $display("--- pmpcfg0/1: 0x9C9A9E9D refused, L=0 bytes of mixed writes land ---");
      check_mem_value(`SPAD(32'h600), 32'h1E1A1C18);   // pmpcfg0 unchanged
      check_mem_value(`SPAD(32'h604), 32'h19191919);
      check_mem_value(`SPAD(32'h608), 32'h18181818);
      check_mem_value(`SPAD(32'h60C), 32'h18191819);   // only the 0x19 bytes
      check_mem_value(`SPAD(32'h610), 32'h19181918);
      check_mem_value(`SPAD(32'h620), 32'h1F1B1D19);   // pmpcfg1 unchanged
      check_mem_value(`SPAD(32'h624), 32'h19191919);
      check_mem_value(`SPAD(32'h628), 32'h18181818);
      check_mem_value(`SPAD(32'h62C), 32'h18191819);
      check_mem_value(`SPAD(32'h630), 32'h19181918);
      $display("--- pmpcfg2/3: locked rows (RLB=0) ignore every write ---");
      for (kk = 0; kk < 5; kk = kk + 1) begin
         check_mem_value(`SPAD(32'h640 + kk*4), 32'h9E9A9C98);
         check_mem_value(`SPAD(32'h660 + kk*4), 32'h9F9B9D99);
      end

      //=================================================================
      // END OF TEST
      //=================================================================
      wait(probes_cpu.x31==32'hdeadbeef);
      random_irq_enable = 0;
      repeat(20) @(posedge free_clk);
      stimulus_done = 1;
   end

//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      csr_ids
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: CSRRW
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;
integer ahb_master;
integer allow_peripheral_accesses;

// Compute expected CSR values based on parameters
reg [31:0] expected_mimpid;
reg [31:0] expected_misa;

// Derive individual enables from parameters (matching arvern.v)
reg        C_EXT_EN, ZCA_EN, ZCB_EN, ZCMP_EN, ZCMT_EN;
reg        B_EXT_EN, ZBB_EN, ZBA_EN, ZBS_EN;
reg        M_EXT_EN, MUL_EN, DIV_EN;
reg        MUL_1C_EN, MUL_4C_EN, MUL_16C_EN;
reg        DIV_12C_EN, DIV_17C_EN, DIV_33C_EN;
reg        RV32I_EN;

initial begin
    // Derive extension enables from parameters (matching arvern.v lines 193-217)
    C_EXT_EN   = (C_EXTENSION >= 1) ? 1'b1 : 1'b0;
    ZCA_EN     = (C_EXTENSION >= 1) ? 1'b1 : 1'b0;
    ZCB_EN     = (C_EXTENSION >= 2) ? 1'b1 : 1'b0;
    ZCMP_EN    = (C_EXTENSION >= 3) ? 1'b1 : 1'b0;
    ZCMT_EN    = (C_EXTENSION >= 4) ? 1'b1 : 1'b0;

    // SPEC RULE (RISC-V ISA manual, misa): bit 1 ('B') = 1 iff the COMPLETE
    // ratified B extension is implemented, i.e. Zba AND Zbb AND Zbs together.
    // A partial subset (e.g. only Zbb, or Zbb+Zba) must read misa.B = 0.
    // Zbc (carry-less multiply) is NOT part of the ratified B umbrella and is
    // irrelevant to misa.B. Per arvern B_EXTENSION tiering
    // (0=none, 1=Zbb, 2=Zbb+Zba, 3=Zbb+Zba+Zbs, 4=+Zbc) that is B_EXTENSION>=3.
    // NOTE: this is the SPEC rule, deliberately NOT "matching arvern.v".
    B_EXT_EN   = (B_EXTENSION >= 3) ? 1'b1 : 1'b0;
    ZBB_EN     = (B_EXTENSION >= 1) ? 1'b1 : 1'b0;
    ZBA_EN     = (B_EXTENSION >= 2) ? 1'b1 : 1'b0;
    ZBS_EN     = (B_EXTENSION >= 3) ? 1'b1 : 1'b0;

    M_EXT_EN   = (M_EXTENSION >= 2) ? 1'b1 : 1'b0;
    MUL_EN     = (M_EXTENSION >= 1) ? 1'b1 : 1'b0;
    DIV_EN     = (M_EXTENSION >= 2) ? 1'b1 : 1'b0;

    MUL_1C_EN  = (MUL_TYPE == 1) ? MUL_EN : 1'b0;
    MUL_4C_EN  = (MUL_TYPE == 2) ? MUL_EN : 1'b0;
    MUL_16C_EN = (MUL_TYPE == 3) ? MUL_EN : 1'b0;

    DIV_12C_EN = (DIV_TYPE == 1) ? DIV_EN : 1'b0;
    DIV_17C_EN = (DIV_TYPE == 2) ? DIV_EN : 1'b0;
    DIV_33C_EN = (DIV_TYPE == 3) ? DIV_EN : 1'b0;

    RV32I_EN      = (RV32E_EN    == 0) ? 1'b1 : 1'b0;

    // Compute MIMPID based on arv_csr_ids.v formula
    // NOTE: keep [31:20] in sync with the RTL_VERSION localparam in arvern.v -- bump together on each RTL release.
    expected_mimpid = {12'h000,                // [31:20] :  RTL release version (RTL_VERSION, 12 bits)
                       ZIHPM_NR[3:0],          // [19:16] :  Zihpm HPM counter count (0-8)
                       ZICNTR_EN[0],           // [15]    :  Zicntr extension enable (cycle, time, instret)
                       SINGLE_CYCLE_BRANCH[0], // [14]    :  1=zero-bubble taken branch (max IPC); 0=one-bubble (max Fmax)
                       NMI_EN[0],              // [13]    :  Smrnmi extension enable (resumable NMI)
                       CCSR_EN[0],             // [12]    :  Custom-CSR available

                       // [11:10] : Divider type    (0=none, 1=12cyc, 2=17cyc, 3=33cyc)
                       (({2{DIV_12C_EN}} & 2'd1) | ({2{DIV_17C_EN}} & 2'd2) | ({2{DIV_33C_EN}} & 2'd3)),
                       // [ 9: 8] : Multiplier type (0=none, 1=1cyc,  2=4cyc,  3=16cyc)
                       (({2{MUL_1C_EN }} & 2'd1) | ({2{MUL_4C_EN }} & 2'd2) | ({2{MUL_16C_EN}} & 2'd3)),

                       ZCMT_EN,             // [ 7]    :  Zcmt extension enable
                       ZCMP_EN,             // [ 6]    :  Zcmp extension enable
                       ZCB_EN,              // [ 5]    :  Zcb extension enable
                       ZCA_EN,              // [ 4]    :  Zca extension enable

                       ASYNC_RST_EN[0],     // [ 3]    :  Reset architecture (1=asynchronous, 0=synchronous)
                       ZBS_EN,              // [ 2]    :  Zbs extension enable
                       ZBA_EN,              // [ 1]    :  Zba extension enable
                       ZBB_EN               // [ 0]    :  Zbb extension enable
                      };

    // Compute MISA based on arv_csr_ids.v formula (lines 162-188)
    expected_misa = {2'b01,              // [31:30] MXL: 32-bit
                     4'b0000,            // [29:26] Reserved
                     1'b0,               // [25] Z
                     1'b0,               // [24] Y
                     1'b0,               // [23] X
                     1'b0,               // [22] W
                     1'b0,               // [21] V
                     (SU_MODE_EN ? 1'b1 : 1'b0), // [20] U: User mode (gated by SU_MODE_EN; explicit 1-bit cast)
                     1'b0,               // [19] T
                     (SU_MODE_EN ? 1'b1 : 1'b0), // [18] S: Supervisor mode (gated by SU_MODE_EN; explicit 1-bit cast)
                     1'b0,               // [17] R
                     1'b0,               // [16] Q
                     1'b0,               // [15] P
                     1'b0,               // [14] O
                     1'b0,               // [13] N
                     M_EXT_EN,           // [12] M: Full M extension (DIV_EN)
                     1'b0,               // [11] L
                     1'b0,               // [10] K
                     1'b0,               // [9]  J
                     RV32I_EN,           // [8]  I: RV32I base (not RV32E)
                     1'b0,               // [7]  H
                     1'b0,               // [6]  G
                     1'b0,               // [5]  F
                     ~RV32I_EN,          // [4]  E: RV32E base (not RV32I)
                     1'b0,               // [3]  D
                     C_EXT_EN,           // [2]  C: Compressed
                     B_EXT_EN,           // [1]  B: Bit manipulation
                     1'b0                // [0]  A
                    };

    $display("");
    $display("===================================================================");
    $display("CSR_IDS Test Configuration (from arv_parameterization.v):");
    $display("===================================================================");
    $display("  RV32E_EN       = %0d (0=RV32I, 1=RV32E)", RV32E_EN);
    $display("  C_EXTENSION    = %0d (0=none, 1=Zca, 2=Zca+Zcb, 3=Zca+Zcb+Zcmp)", C_EXTENSION);
    $display("  M_EXTENSION    = %0d (0=none, 1=Zmmul, 2=M)", M_EXTENSION);
    $display("  B_EXTENSION    = %0d (0=none, 1=Zbb, 2=Zbb+Zba, 3=Zbb+Zba+Zbs)", B_EXTENSION);
    $display("  MUL_TYPE       = %0d (1=1cyc, 2=4cyc, 3=16cyc)", MUL_TYPE);
    $display("  DIV_TYPE       = %0d (1=12cyc, 2=17cyc, 3=33cyc)", DIV_TYPE);
    $display("  CCSR_EN        = %0d", CCSR_EN);
    $display("  NMI_EN         = %0d", NMI_EN);
    $display("  SINGLE_CYCLE_BRANCH = %0d (1=zero-bubble taken branch / max IPC, 0=one-bubble / max Fmax)", SINGLE_CYCLE_BRANCH);
    $display("  MVENDORID      = 0x%08h (mvendorid 0xF11; integration-set parameter; firmware csrr must read this back)", MVENDORID);
    $display("");
    $display("Derived enables:");
    $display("  RV32I_EN       = %0d", RV32I_EN);
    $display("  C_EXT_EN       = %0d  (ZCA=%0d, ZCB=%0d, ZCMP=%0d, ZCMT=%0d)", C_EXT_EN, ZCA_EN, ZCB_EN, ZCMP_EN, ZCMT_EN);
    $display("  M_EXT_EN       = %0d  (MUL_EN=%0d, DIV_EN=%0d)", M_EXT_EN, MUL_EN, DIV_EN);
    $display("  B_EXT_EN       = %0d  (ZBB=%0d, ZBA=%0d, ZBS=%0d)", B_EXT_EN, ZBB_EN, ZBA_EN, ZBS_EN);
    $display("  MUL enables    = 1C:%0d, 4C:%0d, 16C:%0d", MUL_1C_EN, MUL_4C_EN, MUL_16C_EN);
    $display("  DIV enables    = 12C:%0d, 17C:%0d, 33C:%0d", DIV_12C_EN, DIV_17C_EN, DIV_33C_EN);
    $display("");
    $display("Expected CSR values:");
    $display("  MIMPID         = 0x%08h", expected_mimpid);
    $display("  MISA           = 0x%08h", expected_misa);
    $display("===================================================================");
    $display("");
end

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
      $display("");
      $display(" ====================================================================");
      $display("|                 CHECK REGISTER VALUES BEFORE THE CSRRW             |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");
      $display("Waiting for the firmware...");

      @(probes_cpu.x31==32'hFFFFFFFF);

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
	   check_cpu_reg(16, 32'hffffffff);
	   check_cpu_reg(17, 32'hffffffff);
	   check_cpu_reg(18, 32'hffffffff);
	   check_cpu_reg(19, 32'hffffffff);
	   check_cpu_reg(20, 32'hffffffff);
	   check_cpu_reg(21, 32'hffffffff);
	   check_cpu_reg(22, 32'hffffffff);
	   check_cpu_reg(23, 32'hffffffff);
	   check_cpu_reg(24, 32'hffffffff);
	   check_cpu_reg(25, 32'hffffffff);
	   check_cpu_reg(26, 32'hffffffff);
	   check_cpu_reg(27, 32'hffffffff);
	   check_cpu_reg(28, 32'hffffffff);
	   check_cpu_reg(29, 32'hffffffff);
	   check_cpu_reg(30, 32'hffffffff);
	   check_cpu_reg(31, 32'hffffffff);


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|         CHECK REGISTER VALUES AFTER READING DEFAULT VALUES         |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x29==32'hdeadbeef);

	   check_cpu_reg(1,  MVENDORID);       // MVENDORID   -->  Vendor ID: must equal the MVENDORID
                                               //                  parameter the testbench instantiated the
                                               //                  DUT with (verifies the integration
                                               //                  parameter propagates arvern -> csr_top
                                               //                  -> csr_ids -> CSR read -> firmware csrr).
 	   check_cpu_reg(2,  32'h00000000);    // MARCHID     -->  Architecture ID: core-owned (arvern.v
                                               //                  MARCHID localparam, NOT an integration
                                               //                  parameter). 0 until RISC-V International
                                               //                  allocates an ID; keep this literal in
                                               //                  sync with that localparam if it changes.
 	   check_cpu_reg(3,  expected_mimpid); // MIMPID      -->  Implementation ID (computed from parameters)
 	   check_cpu_reg(4,  32'h00000023);    // MHARTID     -->  Hardware thread ID.
	   check_cpu_reg(5,  32'h00000000);    // MCONFIGPTR  -->  Pointer to configuration data structure.
	   check_cpu_reg(6,  expected_misa);   // MISA        -->  ISA and extensions (computed from parameters)

      // Force different values to test CSR read paths
      force tb_arvern.dut.arv_csr_top_inst.arv_csr_ids_inst.mvendorid  = 32'h12345678;
      force tb_arvern.dut.arv_csr_top_inst.arv_csr_ids_inst.marchid    = 32'h9ABCDEF0;
      force tb_arvern.dut.arv_csr_top_inst.arv_csr_ids_inst.mimpid     = 32'h13243546;
      force tb_arvern.dut.arv_csr_top_inst.arv_csr_ids_inst.mhartid    = 32'h14253647;
      force tb_arvern.dut.arv_csr_top_inst.arv_csr_ids_inst.mconfigptr = 32'hFCEA6352;
      force tb_arvern.dut.arv_csr_top_inst.arv_csr_ids_inst.misa       = 32'h9A2B7D1E;


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|         CHECK REGISTER VALUES AFTER READING FORCED VALUES          |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      @(probes_cpu.x30==32'hdeadbeef);

	   check_cpu_reg(11, 32'h12345678);   // MVENDORID   -->  Vendor ID.
 	   check_cpu_reg(12, 32'h9ABCDEF0);   // MARCHID     -->  Architecture ID.
 	   check_cpu_reg(13, 32'h13243546);   // MIMPID      -->  Implementation ID.
 	   check_cpu_reg(14, 32'h14253647);   // MHARTID     -->  Hardware thread ID.
	   check_cpu_reg(15, 32'hFCEA6352);   // MCONFIGPTR  -->  Pointer to configuration data structure.
	   check_cpu_reg(16, 32'h9A2B7D1E);   // MISA        -->  ISA and extensions.


      $display("");
      $display("");
      $display(" ====================================================================");
      $display("|                  CHECK REGISTER AFTER WRITING VALUES               |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);

      $display("");
      $display("Waiting for the firmware...");
      while(probes_cpu.x31!==32'hdeadbeef) @(posedge free_clk);

      // MISA write test: writes are ignored, value should remain as forced value (0x9A2B7D1E)
	   check_cpu_reg(21, 32'h9A2B7D1E);  // MISA old value from csrrw (forced value)
	   check_cpu_reg(22, 32'h9A2B7D1E);  // MISA current value (unchanged, forced value)

      // MVENDORID write test: should trap (illegal write to read-only CSR).
      // Per spec, a CSR access that raises an exception shall not write rd,
      // so x23 must retain its pre-instruction value (initialized to 0xFFFFFFFF).
      // x24 reads MVENDORID after handler returns (forced value).
	   check_cpu_reg(23, 32'hFFFFFFFF);  // rd preserved across illegal CSR access
	   check_cpu_reg(24, 32'h12345678);  // MVENDORID current value (unchanged, forced value)


      $display("");

      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(20) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

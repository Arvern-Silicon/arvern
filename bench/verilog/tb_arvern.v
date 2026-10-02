//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    tb_arvern
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : tb_arvern.v
// Module Description : Top-level testbench for the arvern CPU core.
//----------------------------------------------------------------------------

`include "timescale.v"

module  tb_arvern;

//
// Wire & Register definition
//------------------------------

parameter            ROM_SIZE     = 64*1024;                // Size of the ROM memory instance (in Bytes)
parameter            SRAM_X_SIZE  = 64*1024;                // Size of the Executable SRAM memory instance (in Bytes)
parameter            SRAM_NX_SIZE = 64*1024;                // Size of the Non-executable SRAM memory instance (in Bytes)
parameter            RESET_VECTOR = 32'h20000000;           // Reset PC. Overridable at elaboration (-P/-G) so the arch-test flow can boot from SRAM_X

// Clock / Reset
wire                 free_clk;
wire                 dut_hclk;
wire                 dut_hclk_en;
wire                 system_hclk;
wire                 system_hclk_en;
wire                 ccsr_hclk;
wire                 ccsr_hclk_en;
reg                  porn_async;
wire                 resetn_lf;
wire                 porn;
wire                 hresetn;
wire                 dbgresetn;

// AHB Manager interfaces
wire          [31:0] inst_haddr;
wire           [2:0] inst_hburst;
wire                 inst_hmastlock;
wire           [3:0] inst_hprot;
wire           [2:0] inst_hsize;
wire                 inst_hsmode;
wire           [1:0] inst_htrans;
wire          [31:0] inst_hwdata;
wire                 inst_hwrite;
wire          [31:0] inst_hrdata;
wire                 inst_hready;
wire                 inst_hresp;

wire          [31:0] data_haddr;
wire           [2:0] data_hburst;
wire                 data_hmastlock;
wire           [3:0] data_hprot;
wire           [2:0] data_hsize;
wire                 data_hsmode;
wire                 data_hmaster;       // debug-master sideband (1 = SBA access)
wire           [1:0] data_htrans;
wire          [31:0] data_hwdata;
wire                 data_hwrite;
wire          [31:0] data_hrdata;
wire                 data_hready;
wire                 data_hresp;

// AHB Subordinate Interfaces with inserted wait states
integer              s_rom_number_ws;
reg                  s_rom_random_ws_en;
integer              s_sram_x_number_ws;
reg                  s_sram_x_random_ws_en;
integer              s_sram_nx_number_ws;
reg                  s_sram_nx_random_ws_en;
integer              s_periph0_number_ws;
reg                  s_periph0_random_ws_en;
integer              s_periph1_number_ws;
reg                  s_periph1_random_ws_en;
integer              s_periph2_number_ws;
reg                  s_periph2_random_ws_en;

// AHB Peripheral #0
wire          [31:0] periph0_reg_00_out;
wire          [31:0] periph0_reg_01_out;
wire          [31:0] periph0_reg_02_out;
wire          [31:0] periph0_reg_03_out;
wire          [31:0] periph0_reg_04_out;
wire          [31:0] periph0_reg_05_out;
wire          [31:0] periph0_reg_06_out;
wire          [31:0] periph0_reg_07_out;
reg           [31:0] periph0_reg_08_in;
reg           [31:0] periph0_reg_09_in;
reg           [31:0] periph0_reg_10_in;
reg           [31:0] periph0_reg_11_in;
reg           [31:0] periph0_reg_12_in;
reg           [31:0] periph0_reg_13_in;
reg           [31:0] periph0_reg_14_in;
reg           [31:0] periph0_reg_15_in;

// AHB Peripheral #1
wire          [31:0] periph1_reg_00_out;
wire          [31:0] periph1_reg_01_out;
wire          [31:0] periph1_reg_02_out;
wire          [31:0] periph1_reg_03_out;
wire          [31:0] periph1_reg_04_out;
wire          [31:0] periph1_reg_05_out;
wire          [31:0] periph1_reg_06_out;
wire          [31:0] periph1_reg_07_out;
reg           [31:0] periph1_reg_08_in;
reg           [31:0] periph1_reg_09_in;
reg           [31:0] periph1_reg_10_in;
reg           [31:0] periph1_reg_11_in;
reg           [31:0] periph1_reg_12_in;
reg           [31:0] periph1_reg_13_in;
reg           [31:0] periph1_reg_14_in;
reg           [31:0] periph1_reg_15_in;

// AHB Peripheral #2
wire          [31:0] periph2_reg_00_out;
wire          [31:0] periph2_reg_01_out;
wire          [31:0] periph2_reg_02_out;
wire          [31:0] periph2_reg_03_out;
wire          [31:0] periph2_reg_04_out;
wire          [31:0] periph2_reg_05_out;
wire          [31:0] periph2_reg_06_out;
wire          [31:0] periph2_reg_07_out;
reg           [31:0] periph2_reg_08_in;
reg           [31:0] periph2_reg_09_in;
reg           [31:0] periph2_reg_10_in;
reg           [31:0] periph2_reg_11_in;
reg           [31:0] periph2_reg_12_in;
reg           [31:0] periph2_reg_13_in;
reg           [31:0] periph2_reg_14_in;
reg           [31:0] periph2_reg_15_in;

// Read-only CCSR registers
reg           [31:0] ccsr_usr_ro_0;
reg           [31:0] ccsr_sup_ro_0;
reg           [31:0] ccsr_mac_ro_0;
reg           [31:0] ccsr_mac_ro_1;

// Read-write CCSR values
wire          [31:0] ccsr_usr_rw_0;
wire          [31:0] ccsr_usr_rw_1;
wire          [31:0] ccsr_sup_rw_0;
wire          [31:0] ccsr_sup_rw_1;
wire          [31:0] ccsr_mac_rw_0;
wire          [31:0] ccsr_mac_rw_1;
wire          [31:0] ccsr_mac_rw_2;
wire          [31:0] ccsr_mac_rw_3;
wire          [31:0] ccsr_mac_rw_4;
wire          [31:0] ccsr_mac_rw_5;
wire          [31:0] ccsr_mac_rw_6;
wire          [31:0] ccsr_mac_rw_7;

// Interface between the aRVern core and CCSR unit
wire          [10:0] ccsr_bank;
wire          [63:0] ccsr_reg_sel;
wire          [31:0] ccsr_wdata;
wire                 ccsr_wen;
wire          [31:0] ccsr_rdata;


// Testbench variables
integer              tb_idx;
integer              tmp_seed;
integer              error;
reg                  stimulus_done;
reg                  error_on_exception;
reg                  checker_report_en;
reg                  checker_enable;

// Interrupt inputs (directly driven by stimulus)
reg                  irq_m_software;
reg                  irq_s_software;
reg                  irq_m_timer;
reg                  irq_m_external;
reg                  irq_s_external;
reg           [15:0] irq_platform;
reg                  random_irq_enable;
wire                 lockup;

// PLIC integration (disabled when use_plic=0, default)
parameter            PLIC_NUM_SRC = 31;
reg                  use_plic;
reg [PLIC_NUM_SRC:0] plic_irq_src;
wire                 plic_irq_m_external;
wire                 plic_irq_s_external;

// ACLINT integration (disabled when use_aclint=0, default)
reg                  use_aclint;
wire                 aclint_irq_m_software;
wire                 aclint_irq_s_software;
wire                 aclint_irq_m_timer;
wire                 aclint_mtimer_wake_lf;
wire                 aclint_time_gnt;
wire          [63:0] aclint_time_val;

// mhartid driver
reg            [7:0] hartid;

// Main oscillator deep-sleep allow signal.
// When 0 (default), the main osc is forced on regardless of hclk_en.
// When 1, the main osc enable follows the OR of all dut/system/ccsr hclk_en advisories
//         so if all three drop (deep WFI with all AHB activity quiesced) the master osc
//         also stops, and only the ACLINT LF wake (aclint_mtimer_wake_lf) can restart it.
reg                  allow_deep_sleep;

// IRQ-to-DUT signal mux. ALL six IRQ inputs are driven from a single
// always @* block so the simulator's continuous-assign scheduling gives
// every IRQ the same delta-cycle delay relative to the stimulus blocking
// assignments.
reg                  irq_m_software_to_dut;
reg                  irq_s_software_to_dut;
reg                  irq_m_timer_to_dut;
reg                  irq_m_external_to_dut;
reg                  irq_s_external_to_dut;
reg           [15:0] irq_platform_to_dut;

always @* begin
   irq_m_software_to_dut = use_aclint ? aclint_irq_m_software : irq_m_software;
   irq_s_software_to_dut = use_aclint ? aclint_irq_s_software : irq_s_software;
   irq_m_timer_to_dut    = use_aclint ? aclint_irq_m_timer    : irq_m_timer;
   irq_m_external_to_dut = use_plic   ? plic_irq_m_external   : irq_m_external;
   irq_s_external_to_dut = use_plic   ? plic_irq_s_external   : irq_s_external;
   irq_platform_to_dut   = irq_platform;
end

reg                  nmi;
reg            [7:0] hpm_platform_events;   // Zihpm platform event inputs (0x0B-0x12)

// EXTERNAL DEBUG STATUS
wire                 dbg_debug_mode;
wire                 dbg_halted;
wire                 dbg_stoptime;

// DEBUG MODULE INTERFACE (DMI) - APB4, testbench is the master
reg                  dmi_psel;
reg                  dmi_penable;
reg  [8:0]           dmi_paddr;
reg                  dmi_pwrite;
reg  [31:0]          dmi_pwdata;
reg  [2:0]           dmi_pprot;
wire                 dmi_pready;
wire [31:0]          dmi_prdata;
wire                 dmi_pslverr;
wire                 dbg_ndmreset;
reg  [31:0]          dmi_readval;      // scratch for dmi_read() task result
reg  [31:0]          sba_rdata;        // scratch for sba_read32() task result
reg  [2:0]           sba_sberr;        // scratch for sba_get_sberr() task result

//=============================================================================
// DMI master source select. The arvern DMI slave inputs are driven from one of:
//   - default            : the testbench APB regs above (dmi_write/dmi_read tasks);
//   - DTM_*_E2E defines   : the shipping arv_dtm wrapper (transport chosen at
//                           elaboration by its DTM_TYPE parameter) is the
//                           DMI master, and a host BFM drives it over a REAL
//                           transport -- the end-to-end integration path. The
//                           specific transport is picked by DTM_UART_E2E /
//                           DTM_I2C_E2E / DTM_JTAG_E2E (each implies the umbrella
//                           DTM_E2E, set by runsim); the matching host BFM
//                           (debug_dtm_{uart,i2c,jtag}_tasks.v) is `included by
//                           debug_dmi_tasks.v.
//=============================================================================
wire                 dmi_psel_src;
wire                 dmi_penable_src;
wire [8:0]           dmi_paddr_src;
wire                 dmi_pwrite_src;
wire [31:0]          dmi_pwdata_src;
wire [2:0]           dmi_pprot_src;

`ifdef DTM_E2E
// The SHIPPING arv_dtm wrapper, with the transport picked at elaboration by
// DTM_TYPE. Runs on the always-on free_clk so a pending request can ungate the
// core clock; reset by dbgresetn (POR-only DM-domain reset). One build sets exactly
// one of DTM_{UART,I2C,JTAG}_E2E; the unselected transports' PHY pins idle so their
// DTMs stay quiescent. Bit/edge timing here is deliberately relaxed (this is an
// integration SANITY pass); the standalone arv_dtm bench (100 MHz, non-integer
// TCK/baud ratios) covers tight async sampling, glitches, and CDC corners.
`ifdef DTM_UART_E2E
localparam integer DTM_TYPE_E2E = 1;
`elsif DTM_I2C_E2E
localparam integer DTM_TYPE_E2E = 2;
`else // DTM_JTAG_E2E
localparam integer DTM_TYPE_E2E = 0;      // 0=JTAG, 1=UART, 2=I2C, 3=cJTAG
`endif

// UART PHY: host -> DTM idles high.
reg                  uart_rx;
wire                 uart_tx;
initial uart_rx = 1'b1;

// I2C PHY: open-drain wired-AND. m_*_pd = host pull-downs, *_pd_dtm = DTM
// pull-downs; a line is low iff either side pulls it (idle released = high).
reg                  m_scl_pd, m_sda_pd;
wire                 scl_pd_dtm, sda_pd_dtm;
wire                 scl = (m_scl_pd | scl_pd_dtm) ? 1'b0 : 1'b1;
wire                 sda = (m_sda_pd | sda_pd_dtm) ? 1'b0 : 1'b1;
initial begin m_scl_pd = 1'b0; m_sda_pd = 1'b0; end

// JTAG PHY: host drives TMS/TDI, samples TDO. TCK is a free-running clock
// asynchronous to free_clk (~3.1:1) so the TCK<->hclk CDC is genuinely crossed;
// it idles at 0 (unused) for the non-JTAG transports. trst_n must be asserted at
// start so the DMI master's TCK-side handshake flops reset (its reset is trst_n &
// synced(dbgresetn)); without it the req/ack CDC wedges and every DMI op stalls
// while pure-TCK IDCODE still works. Only the JTAG build pulses trst_n (it waits on
// TCK edges, which the non-JTAG builds do not run).
reg                  tms, tdi;
reg                  tdo_sampled;
wire                 tdo;
initial begin tms = 1'b1; tdi = 1'b0; end
`ifdef DTM_JTAG_E2E
reg                  tck;
initial tck = 1'b0;
always #1550 tck = ~tck;               // ~3.1x the free_clk period (free half = 500)
reg                  trst_n;
initial begin
    trst_n = 1'b0;                     // hold TAP + DMI-master TCK side in reset...
    wait (dbgresetn);                  // ...through POR (dbgresetn deasserted)...
    repeat (2) @(posedge tck);         // ...and a couple TCK edges, then release.
    trst_n = 1'b1;
end
`else
wire                 tck    = 1'b0;
wire                 trst_n = 1'b1;
`endif

wire                 w_dmi_psel;
wire                 w_dmi_penable;
wire [8:0]           w_dmi_paddr;
wire                 w_dmi_pwrite;
wire [31:0]          w_dmi_pwdata;
wire [2:0]           w_dmi_pprot;

arv_dtm #(
    .DTM_TYPE           ( DTM_TYPE_E2E  ),
    .ARST_EN            ( 1'b1          ),
    .AB_BREAK_CLKS      ( 32'd700       ), // Small break threshold to speed up simulations
    .UART_RX_FIFO_DEPTH ( 32            )
) u_dtm_wrapper (
    .idcode_version_i   ( 4'h0          ), // IDCODE version strap (ECO-tieable port)
    .clk_i              ( free_clk      ),
    .dbgresetn_i        ( dbgresetn     ),
    .scan_mode_i        ( 1'b0          ), // no scan infrastructure in this bench
    .dbg_wakeup_o       (               ), // cold-attach wake: unused on this board
    .tck_i              ( tck           ),
    .trst_n_i           ( trst_n        ),
    .tms_i              ( tms           ),
    .tdi_i              ( tdi           ),
    .tdo_o              ( tdo           ),
    .tdo_oe_o           (               ),
    .uart_rx_i          ( uart_rx       ),
    .uart_tx_o          ( uart_tx       ),
    .scl_i              ( scl           ),
    .sda_i              ( sda           ),
    .scl_pd_o           ( scl_pd_dtm    ),
    .sda_pd_o           ( sda_pd_dtm    ),

    // cJTAG (DTM_TYPE=3) is not exercised end-to-end on the core bench yet.
    .tckc_i             ( 1'b0          ),
    .tmsc_i             ( 1'b0          ),
    .tmsc_o             (               ),
    .tmsc_oe_o          (               ),

    .dmi_psel_o         ( w_dmi_psel    ),
    .dmi_penable_o      ( w_dmi_penable ),
    .dmi_paddr_o        ( w_dmi_paddr   ),
    .dmi_pwrite_o       ( w_dmi_pwrite  ),
    .dmi_pwdata_o       ( w_dmi_pwdata  ),
    .dmi_pprot_o        ( w_dmi_pprot   ),
    .dmi_pready_i       ( dmi_pready    ),
    .dmi_prdata_i       ( dmi_prdata    ),
    .dmi_pslverr_i      ( dmi_pslverr   )
);

assign dmi_psel_src    = w_dmi_psel;
assign dmi_penable_src = w_dmi_penable;
assign dmi_paddr_src   = w_dmi_paddr;
assign dmi_pwrite_src  = w_dmi_pwrite;
assign dmi_pwdata_src  = w_dmi_pwdata;
assign dmi_pprot_src   = w_dmi_pprot;
`else
assign dmi_psel_src    = dmi_psel;
assign dmi_penable_src = dmi_penable;
assign dmi_paddr_src   = dmi_paddr;
assign dmi_pwrite_src  = dmi_pwrite;
assign dmi_pwdata_src  = dmi_pwdata;
assign dmi_pprot_src   = dmi_pprot;
`endif

wire                 time_req;
reg                  time_gnt;
reg           [63:0] time_val;
reg           [63:0] mtime;
reg           [63:0] mtime_init;       // initial mtime value at reset (set from stimulus; default 0)
reg            [2:0] mtime_grant_ctr;  // countdown to grant; 0=idle
reg            [2:0] mtime_rnd;      // scratch register for random delay computation
integer              mtime_rnd_i;    // 32-bit scratch: keeps the modulo width-clean

// Zicntr time-port mux (selects between the legacy randomised model above
// and the ACLINT's Zicntr port when use_aclint=1).
reg                  time_gnt_to_dut;
reg           [63:0] time_val_to_dut;
always @* begin
   time_gnt_to_dut = use_aclint ? aclint_time_gnt : time_gnt;
   time_val_to_dut = use_aclint ? aclint_time_val : time_val;
end


//
// Include files
//------------------------------

// Verilog stimulus
`include "arv_parameterization.v"
`include "check_tasks.v"
`include "stimulus.v"
`include "random_irq_injector.v"


//
// Initialize Memory & Peripherals
//---------------------------------
initial
  begin
     // Initialize ROM (zero-fill then load, in this order, in one initial block)
     for (tb_idx=0; tb_idx < ROM_SIZE/4; tb_idx=tb_idx+1)
       ahb_bus_system_inst.rom_inst0.mem[tb_idx] = 32'h00000000;
     $readmemh("./pmem.mem", ahb_bus_system_inst.rom_inst0.mem);

     // Initialize Executable SRAM
     for (tb_idx=0; tb_idx < SRAM_X_SIZE/4; tb_idx=tb_idx+1)
       ahb_bus_system_inst.sram_x_inst.mem[tb_idx] = 32'h00000000;

     // Initialize Non-executable SRAM
     for (tb_idx=0; tb_idx < SRAM_NX_SIZE/4; tb_idx=tb_idx+1)
       ahb_bus_system_inst.sram_nx_inst.mem[tb_idx] = 32'h00000000;

     // Initialize peripheral #0
     periph0_reg_08_in = 32'h00000000 ;
     periph0_reg_09_in = 32'h00000000 ;
     periph0_reg_10_in = 32'h00000000 ;
     periph0_reg_11_in = 32'h00000000 ;
     periph0_reg_12_in = 32'h00000000 ;
     periph0_reg_13_in = 32'h00000000 ;
     periph0_reg_14_in = 32'h00000000 ;
     periph0_reg_15_in = 32'h00000000 ;

     // Initialize peripheral #1
     periph1_reg_08_in = 32'h00000000 ;
     periph1_reg_09_in = 32'h00000000 ;
     periph1_reg_10_in = 32'h00000000 ;
     periph1_reg_11_in = 32'h00000000 ;
     periph1_reg_12_in = 32'h00000000 ;
     periph1_reg_13_in = 32'h00000000 ;
     periph1_reg_14_in = 32'h00000000 ;
     periph1_reg_15_in = 32'h00000000 ;

     // Initialize peripheral #2
     periph2_reg_08_in = 32'h00000000 ;
     periph2_reg_09_in = 32'h00000000 ;
     periph2_reg_10_in = 32'h00000000 ;
     periph2_reg_11_in = 32'h00000000 ;
     periph2_reg_12_in = 32'h00000000 ;
     periph2_reg_13_in = 32'h00000000 ;
     periph2_reg_14_in = 32'h00000000 ;
     periph2_reg_15_in = 32'h00000000 ;

  end


//
// Generate Clock & Reset
//------------------------------

// Main AHB-frequency oscillator
wire    free_osc_enable =  dut_hclk_en      |
                           system_hclk_en   |
                           ccsr_hclk_en     |
                          ~allow_deep_sleep ;

// Clock SOURCE: reset by the RAW async porn_async, NOT the synchronized porn.
// porn is synchronized to free_clk (which this oscillator generates), so using it
// here would be circular; a clock source is not a free_clk flop and takes the raw
// async reset. porn_async is POR-only, so the clock still survives an ndmreset.
wire    hclk_aon_en;   // the oscillator's own enable view -> ACLINT hclk_aon_en_i

// The model only toggles; arv_osc_ctrl owns the stop sequence, so hclk_aon_en
// falls one edge before the clock does -- the same block a real SoC uses.
wire    free_osc_run;

osc #(.HALF_PERIOD(500)) u_free_osc (.en_i     (free_osc_run         ),
                                     .clk_o    (free_clk             ));

arv_osc_ctrl u_free_osc_ctrl        (.osc_clk_i(free_clk             ),
                                     .osc_en_o (free_osc_run         ),
                                     .resetn_i (porn_async           ),
                                     .scan_mode_i(1'b0               ),
                                     .wake_i   (aclint_mtimer_wake_lf),
                                     .enable_i (free_osc_enable      ),
                                     .clk_en_o (hclk_aon_en          ));

// Gated Clock for the arvern. The LF MTIP wake from the ACLINT is OR'd in
// so that a programmed mtimecmp expiry can un-gate hclk while the CPU is
// in WFI sleep -- models the SoC's LF-domain wake aggregator.
wire    dut_hclk_en_with_wake = dut_hclk_en | aclint_mtimer_wake_lf;
reg     dut_hclk_en_latch;
always @(free_clk or dut_hclk_en_with_wake)
  if (~free_clk) dut_hclk_en_latch <= dut_hclk_en_with_wake;
assign  dut_hclk     =  (free_clk & dut_hclk_en_latch);

// Gated Clock for the system (fabric + peripherals)
reg     system_hclk_en_latch;
always @(free_clk or system_hclk_en)
  if (~free_clk) system_hclk_en_latch <= system_hclk_en;
assign  system_hclk  =  (free_clk & system_hclk_en_latch);

// Gated Clock for the custom CSR registers
reg     ccsr_hclk_en_latch;
always @(free_clk or ccsr_hclk_en)
  if (~free_clk) ccsr_hclk_en_latch <= ccsr_hclk_en;
assign  ccsr_hclk    =  (free_clk & ccsr_hclk_en_latch);

// ACLINT always-on AHB-frequency clock: the free-running copy of the AHB clock source, never gated.
wire    hclk_aon     =   free_clk;

// ACLINT low-frequency clock (MTIME tick).
//
// With the real ahb_aclint: 100 kHz against the 1 MHz free_clk -- a ratio of 10,
// rather than the typical 32 kHz, to keep simulations short. PHASE_OFFSET=7 keeps
// it demonstrably asynchronous to free_clk so the IP's CDC paths are genuinely
// exercised.
//
// THE RATIO IS A HARD CONSTRAINT, NOT A CONVENIENCE. ahb_aclint observes clk_lf
// by sampling it AS DATA in the hclk_aon domain, so each of its phases must
// survive two hclk_aon edges: R = f(hclk_aon)/f(clk_lf) >= 10. This oscillator
// used to run at HALF_PERIOD(100), i.e. 5 MHz -- five times FASTER than hclk.
// That was harmless while MTIME crossed on a Gray-coded bus (correct at any
// ratio, in either direction) and is invalid now. Do not lower it below 5000
// without also revisiting doc/ahb_aclint.md.
//
// With the behavioural aclint_model (sim/arch_test): tied to free_clk. That model
// has no low-frequency domain at all -- it paces MTIME off retired instructions
// and keeps its state on hclk_aon -- so a separate slow, skewed clock would only
// add a clock domain that nothing in the model uses.
wire    clk_lf;

`ifdef ARV_TB_ACLINT_MODEL
assign  clk_lf = free_clk;
`else
// Clock SOURCE: like u_free_osc, reset by the raw async porn_async (resetn_lf is
// synchronized to clk_lf, which this oscillator generates -- circular).
// Free-running: this one is never stopped, so it needs no controller.
osc #(.HALF_PERIOD(5000), .PHASE_OFFSET(7)) u_lf_osc (.en_i  (1'b1  ),
                                                      .clk_o (clk_lf));
`endif

// Reset generation. A single async power-on pulse (porn_async) drives reset_gen,
// which produces four synchronized resets modelling the SoC halt-on-reset contract:
//   porn_async: the RAW async POR (this reg) -> the clock SOURCES (u_free_osc,
//               u_lf_osc) directly, since they generate the clocks the synchronized
//               resets are built on. POR-only, so the clocks survive an ndmreset.
//   porn      : POR-only, synchronized to free_clk -> always-on FLOPS in that domain
//               (the mtime real-time counter). Survives an ndmreset.
//   hresetn   : hart/system reset = POR | ndmreset -> the DUT's hresetn_i and the rest
//               of the system (AHB interconnect/memory/peripherals, checkers,
//               custom-CSR). The debugger's dmcontrol.ndmreset (dbg_ndmreset) resets
//               the hart and the system while the clock and DM keep running; SRAM/ROM
//               array contents survive on their own.
//   dbgresetn : POR-only DM reset -> the DUT's dbgresetn_i, so the DM (and
//               resethaltreq) survive an ndmreset and the debugger stays connected.
// For every non-reset-halt test dbg_ndmreset=0, so hresetn == porn (transparent).

initial
  begin
     porn_async = 1'b1;
     #90;
     porn_async = 1'b0;           // assert power-on reset
     #650;
     porn_async = 1'b1;           // release
  end

reset_gen u_reset_gen (
    .porn_async_i ( porn_async    ),
    .clk_lf       ( clk_lf        ),
    .free_clk     ( free_clk      ),
    .dbg_ndmreset ( dbg_ndmreset  ),
    .resetn_lf    ( resetn_lf     ),
    .porn         ( porn          ),
    .hresetn      ( hresetn       ),
    .dbgresetn    ( dbgresetn     )
);

`ifdef ARV_COV_RESET_ZERO
// Coverage counts start once reset is applied: the Verilator coverage flow starts every
// flop at 1 so the asynchronous resets see an edge, and the reset driving them to 0 would
// otherwise count as a toggle of every bit.
initial begin
    @(posedge hresetn);
    $c("Verilated::threadContextp()->coveragep()->zero();");
end
`endif

// Variables initialization
initial
  begin
    tmp_seed               =  `SEED;
    tmp_seed               =  $urandom(tmp_seed);
    error                  =  0;
    stimulus_done          =  0;
    error_on_exception     =  1;
    checker_report_en      =  0;
    checker_enable         =  1;
    irq_m_software         =  0;
    irq_s_software         =  0;
    irq_m_timer            =  0;
    irq_m_external         =  0;
    irq_s_external         =  0;
    irq_platform           =  16'h0000;
    random_irq_enable      =  0;
    use_plic               =  0;
    hartid                 =  8'h23;
    use_aclint             =  0;
    allow_deep_sleep       =  0;
    plic_irq_src           = {(PLIC_NUM_SRC+1){1'b0}};
    nmi                    =  0;
    hpm_platform_events    =  8'h00;
    dmi_psel               =  0;
    dmi_penable            =  0;
    dmi_paddr              =  0;
    dmi_pwrite             =  0;
    dmi_pwdata             =  0;
    dmi_pprot              =  0;
    time_gnt               =  1'b0;
    time_val               =  64'h0;
    mtime                  =  64'h0;
    mtime_init             =  64'h0;
    mtime_grant_ctr        =  3'd0;
    mtime_rnd              =  3'd0;

    // No wait-state by default
    s_rom_number_ws        =  0;
    s_rom_random_ws_en     =  0;
    s_sram_x_number_ws     =  0;
    s_sram_x_random_ws_en  =  0;
    s_sram_nx_number_ws    =  0;
    s_sram_nx_random_ws_en =  0;
    s_periph0_number_ws    =  0;
    s_periph1_number_ws    =  0;
    s_periph2_number_ws    =  0;
    s_periph0_random_ws_en =  0;
    s_periph1_random_ws_en =  0;
    s_periph2_random_ws_en =  0;

    // Fixed wait-states
`ifdef ROM_WS
    s_rom_number_ws        =  5;
    s_rom_random_ws_en     =  0;
`endif
`ifdef SRAM_WS
    s_sram_x_number_ws     =  5;
    s_sram_x_random_ws_en  =  0;
    s_sram_nx_number_ws    =  5;
    s_sram_nx_random_ws_en =  0;
`endif
`ifdef PERIPH_WS
    s_periph0_number_ws    =  5;
    s_periph1_number_ws    =  5;
    s_periph2_number_ws    =  5;
    s_periph0_random_ws_en =  0;
    s_periph1_random_ws_en =  0;
    s_periph2_random_ws_en =  0;
`endif

    // Randomized wait-states
`ifdef ROM_RANDOM_WS
    s_rom_number_ws        =  5;
    s_rom_random_ws_en     =  1;
`endif
`ifdef SRAM_RANDOM_WS
    s_sram_x_number_ws     =  5;
    s_sram_x_random_ws_en  =  1;
    s_sram_nx_number_ws    =  5;
    s_sram_nx_random_ws_en =  1;
`endif
`ifdef PERIPH_RANDOM_WS
    s_periph0_number_ws    =  5;
    s_periph1_number_ws    =  5;
    s_periph2_number_ws    =  5;
    s_periph0_random_ws_en =  1;
    s_periph1_random_ws_en =  1;
    s_periph2_random_ws_en =  1;
`endif

  end


//--------------------------------------------------------------------
// ZICNTR: mtime free-running counter
//--------------------------------------------------------------------
always @(posedge free_clk or negedge porn)
  if (!porn) mtime <= mtime_init;
  else       mtime <= mtime + 1'b1;

//--------------------------------------------------------------------
// ZICNTR: randomized mtime grant model (delay 0-5 clock cycles)
// Delay=0: grant in the same clock cycle as the request is first seen.
// Delay=1-5: grant after N additional clock cycles.
// A new random delay is chosen for each new request.
//--------------------------------------------------------------------
always @(posedge free_clk or negedge porn)
  if (!porn) begin
    time_gnt        <= 1'b0;
    time_val        <= 64'h0;
    mtime_grant_ctr <= 3'd0;
  end else begin
    time_gnt <= 1'b0;   // default: deassert

    if (mtime_grant_ctr == 3'd0) begin
      if (time_req) begin
        mtime_rnd_i = ($random >> 1) % 6;   // integer scratch: keeps the modulo 32-bit
        mtime_rnd = mtime_rnd_i[2:0];   // blocking: 0-5
        if (mtime_rnd == 3'd0) begin
          // Delay 0: grant in the same cycle as the request
          time_gnt <= 1'b1;
          time_val <= mtime;
        end else begin
          // Delay 1-5: start countdown
          mtime_grant_ctr <= mtime_rnd;
        end
      end
    end else if (mtime_grant_ctr == 3'd1) begin
      // Last countdown cycle: assert grant
      time_gnt        <= 1'b1;
      time_val        <= mtime;
      mtime_grant_ctr <= 3'd0;
    end else begin
      // Counting down
      mtime_grant_ctr <= mtime_grant_ctr - 3'd1;
    end
  end


//--------------------------------------------------------------------
// DUT: ARVERN
//--------------------------------------------------------------------
arvern #(.RV32E_EN             ( RV32E_EN                  ),
         .B_EXTENSION          ( B_EXTENSION               ),
         .C_EXTENSION          ( C_EXTENSION               ),
         .M_EXTENSION          ( M_EXTENSION               ),
         .MUL_TYPE             ( MUL_TYPE                  ),
         .DIV_TYPE             ( DIV_TYPE                  ),
         .CCSR_EN              ( CCSR_EN                   ),
         .SU_MODE_EN           ( SU_MODE_EN                ),
         .DEBUG_EN             ( DEBUG_EN                  ),
         .DM_TRIGGER_NR        ( DM_TRIGGER_NR             ),
         .ZICNTR_EN            ( ZICNTR_EN                 ),
         .ZIHPM_NR             ( ZIHPM_NR                  ),
         .PMP_NR               ( PMP_NR                    ),
         .ASYNC_RST_EN         ( ASYNC_RST_EN              ),
         .SINGLE_CYCLE_BRANCH  ( SINGLE_CYCLE_BRANCH       )) dut (

// AHB CLOCK & RESET
    .hclk_i                    ( dut_hclk                  ),
    .hresetn_i                 ( hresetn                   ),   // hart reset (POR OR debugger ndmreset), from reset_gen
    .dbgresetn_i               ( dbgresetn                 ),   // debug-module reset (POR only; survives ndmreset)
    .hclk_en_o                 ( dut_hclk_en               ),

// INSTRUCTION AHB BUS
    .inst_hrdata_i             ( inst_hrdata               ),
    .inst_hready_i             ( inst_hready               ),
    .inst_hresp_i              ( inst_hresp                ),

    .inst_haddr_o              ( inst_haddr                ),
    .inst_hburst_o             ( inst_hburst               ),
    .inst_hmastlock_o          ( inst_hmastlock            ),
    .inst_hprot_o              ( inst_hprot                ),
    .inst_hsize_o              ( inst_hsize                ),
    .inst_hsmode_o             ( inst_hsmode               ),
    .inst_htrans_o             ( inst_htrans               ),
    .inst_hwdata_o             ( inst_hwdata               ),
    .inst_hwrite_o             ( inst_hwrite               ),

// DATA AHB BUS
    .data_hrdata_i             ( data_hrdata               ),
    .data_hready_i             ( data_hready               ),
    .data_hresp_i              ( data_hresp                ),

    .data_haddr_o              ( data_haddr                ),
    .data_hburst_o             ( data_hburst               ),
    .data_hmastlock_o          ( data_hmastlock            ),
    .data_hprot_o              ( data_hprot                ),
    .data_hsize_o              ( data_hsize                ),
    .data_hsmode_o             ( data_hsmode               ),
    .data_hmaster_o            ( data_hmaster              ),
    .data_htrans_o             ( data_htrans               ),
    .data_hwdata_o             ( data_hwdata               ),
    .data_hwrite_o             ( data_hwrite               ),

// INTERFACE TO CUSTOM CSR REGISTERS
    .ccsr_rdata_i              ( ccsr_rdata                ),
    .ccsr_bank_o               ( ccsr_bank                 ),
    .ccsr_reg_sel_o            ( ccsr_reg_sel              ),
    .ccsr_wdata_o              ( ccsr_wdata                ),
    .ccsr_wen_o                ( ccsr_wen                  ),

// INTERRUPT INPUTS
    .irq_m_software_i          ( irq_m_software_to_dut     ),
    .irq_s_software_i          ( irq_s_software_to_dut     ),
    .irq_m_timer_i             ( irq_m_timer_to_dut        ),
    .irq_m_external_i          ( irq_m_external_to_dut     ),
    .irq_s_external_i          ( irq_s_external_to_dut     ),
    .irq_platform_i            ( irq_platform_to_dut       ),

// OTHERS
    .hartid_i                  ( hartid                    ),
    .reset_vector_i            ( RESET_VECTOR              ),

// LOCKUP STATUS
    .lockup_o                  ( lockup                    ),

// NMI (SMRNMI)
    .nmi_i                     ( nmi                       ),
// ZIHPM PLATFORM EVENTS
    .hpm_platform_events_i     ( hpm_platform_events       ),

// ZICNTR TIME INTERFACE
    .time_req_o                ( time_req                  ),
    .time_gnt_i                ( time_gnt_to_dut           ),
    .time_val_i                ( time_val_to_dut           ),

// EXTERNAL DEBUG (Sdext)
    .dbg_debug_mode_o          ( dbg_debug_mode            ),
    .dbg_halted_o              ( dbg_halted                ),
    .dbg_stoptime_o            ( dbg_stoptime              ),
    .dbg_ndmreset_o            ( dbg_ndmreset              ),
    .dmi_psel_i                ( dmi_psel_src              ),
    .dmi_penable_i             ( dmi_penable_src           ),
    .dmi_paddr_i               ( dmi_paddr_src             ),
    .dmi_pwrite_i              ( dmi_pwrite_src            ),
    .dmi_pwdata_i              ( dmi_pwdata_src            ),
    .dmi_pprot_i               ( dmi_pprot_src             ),
    .dmi_pready_o              ( dmi_pready                ),
    .dmi_prdata_o              ( dmi_prdata                ),
    .dmi_pslverr_o             ( dmi_pslverr               )

);

//--------------------------------------------------------------------
// CUSTOM CSR REGISTERS
//--------------------------------------------------------------------

arv_custom_csr #(.NR_USR_RW(2), .NR_USR_RO(1),
                 .NR_SUP_RW(2), .NR_SUP_RO(1),
                 .NR_MAC_RW(8), .NR_MAC_RO(2)) arv_custom_csr_inst (

// AHB CLOCK & RESET
    .hclk_i                    ( ccsr_hclk                                                   ),
    .hresetn_i                 ( hresetn                                                     ),
    .hclk_en_o                 ( ccsr_hclk_en                                                ),

// READ-ONLY VALUES FROM OUTSIDE WORLD
    .ccsr_usr_ro_i             ( {ccsr_usr_ro_0}                                             ),
    .ccsr_sup_ro_i             ( {ccsr_sup_ro_0}                                             ),
    .ccsr_mac_ro_i             ( {ccsr_mac_ro_1, ccsr_mac_ro_0}                              ),

// READ-WRITE VALUES TO OUTSIDE WORLD
    .ccsr_usr_rw_o             ( {ccsr_usr_rw_1, ccsr_usr_rw_0}                              ),
    .ccsr_sup_rw_o             ( {ccsr_sup_rw_1, ccsr_sup_rw_0}                              ),
    .ccsr_mac_rw_o             ( {ccsr_mac_rw_7, ccsr_mac_rw_6, ccsr_mac_rw_5, ccsr_mac_rw_4,
                                  ccsr_mac_rw_3, ccsr_mac_rw_2, ccsr_mac_rw_1, ccsr_mac_rw_0}),

// INTERFACE TO CUSTOM CSR REGISTERS
    .ccsr_bank_i               ( ccsr_bank                                                   ),
    .ccsr_reg_sel_i            ( ccsr_reg_sel                                                ),
    .ccsr_wdata_i              ( ccsr_wdata                                                  ),
    .ccsr_wen_i                ( ccsr_wen                                                    ),
    .ccsr_rdata_o              ( ccsr_rdata                                                  )
);

//--------------------------------------------------------------------
// BUS SYSTEM
//--------------------------------------------------------------------

ahb_bus_system #(.ROM_SIZE        (ROM_SIZE                ),
                 .SRAM_X_SIZE     (SRAM_X_SIZE             ),
                 .SRAM_NX_SIZE    (SRAM_NX_SIZE            ),
                 .PLIC_NUM_SRC    (PLIC_NUM_SRC            ),
                 .PLIC_SU_MODE_EN (SU_MODE_EN              )) ahb_bus_system_inst (

// AHB CLOCK & RESET
    .hclk_i                    ( system_hclk               ),
    .hresetn_i                 ( hresetn                   ),
    .hclk_en_o                 ( system_hclk_en            ),


// RANDOM WAIT STATES CONFIGURATION
    .s_rom_number_ws_i         ( s_rom_number_ws           ),
    .s_rom_random_ws_en_i      ( s_rom_random_ws_en        ),
    .s_sram_x_number_ws_i      ( s_sram_x_number_ws        ),
    .s_sram_x_random_ws_en_i   ( s_sram_x_random_ws_en     ),
    .s_sram_nx_number_ws_i     ( s_sram_nx_number_ws       ),
    .s_sram_nx_random_ws_en_i  ( s_sram_nx_random_ws_en    ),
    .s_periph0_number_ws_i     ( s_periph0_number_ws       ),
    .s_periph0_random_ws_en_i  ( s_periph0_random_ws_en    ),
    .s_periph1_number_ws_i     ( s_periph1_number_ws       ),
    .s_periph1_random_ws_en_i  ( s_periph1_random_ws_en    ),
    .s_periph2_number_ws_i     ( s_periph2_number_ws       ),
    .s_periph2_random_ws_en_i  ( s_periph2_random_ws_en    ),

// EXECUTABLE AHB BUS MANAGER INTERFACE
    .m_x_haddr_i               ( inst_haddr                ),
    .m_x_hburst_i              ( inst_hburst               ),
    .m_x_hmastlock_i           ( inst_hmastlock            ),
    .m_x_hprot_i               ( inst_hprot                ),
    .m_x_hsize_i               ( inst_hsize                ),
    .m_x_hsmode_i              ( inst_hsmode               ),
    .m_x_htrans_i              ( inst_htrans               ),
    .m_x_hwdata_i              ( inst_hwdata               ),
    .m_x_hwrite_i              ( inst_hwrite               ),

    .m_x_hrdata_o              ( inst_hrdata               ),
    .m_x_hready_o              ( inst_hready               ),
    .m_x_hresp_o               ( inst_hresp                ),

// NON-EXECUTABLE AHB MANAGER INTERFACE
    .m_nx_haddr_i              ( data_haddr                ),
    .m_nx_hburst_i             ( data_hburst               ),
    .m_nx_hmaster_i            ( data_hmaster              ),
    .m_nx_hmastlock_i          ( data_hmastlock            ),
    .m_nx_hprot_i              ( data_hprot                ),
    .m_nx_hsize_i              ( data_hsize                ),
    .m_nx_hsmode_i             ( data_hsmode               ),
    .m_nx_htrans_i             ( data_htrans               ),
    .m_nx_hwdata_i             ( data_hwdata               ),
    .m_nx_hwrite_i             ( data_hwrite               ),

    .m_nx_hrdata_o             ( data_hrdata               ),
    .m_nx_hready_o             ( data_hready               ),
    .m_nx_hresp_o              ( data_hresp                ),

// AHB PERIPHERAL #0
    .periph0_reg_08_i          ( periph0_reg_08_in         ),
    .periph0_reg_09_i          ( periph0_reg_09_in         ),
    .periph0_reg_10_i          ( periph0_reg_10_in         ),
    .periph0_reg_11_i          ( periph0_reg_11_in         ),
    .periph0_reg_12_i          ( periph0_reg_12_in         ),
    .periph0_reg_13_i          ( periph0_reg_13_in         ),
    .periph0_reg_14_i          ( periph0_reg_14_in         ),
    .periph0_reg_15_i          ( periph0_reg_15_in         ),

    .periph0_reg_00_o          ( periph0_reg_00_out        ),
    .periph0_reg_01_o          ( periph0_reg_01_out        ),
    .periph0_reg_02_o          ( periph0_reg_02_out        ),
    .periph0_reg_03_o          ( periph0_reg_03_out        ),
    .periph0_reg_04_o          ( periph0_reg_04_out        ),
    .periph0_reg_05_o          ( periph0_reg_05_out        ),
    .periph0_reg_06_o          ( periph0_reg_06_out        ),
    .periph0_reg_07_o          ( periph0_reg_07_out        ),

// AHB PERIPHERAL #1
    .periph1_reg_08_i          ( periph1_reg_08_in         ),
    .periph1_reg_09_i          ( periph1_reg_09_in         ),
    .periph1_reg_10_i          ( periph1_reg_10_in         ),
    .periph1_reg_11_i          ( periph1_reg_11_in         ),
    .periph1_reg_12_i          ( periph1_reg_12_in         ),
    .periph1_reg_13_i          ( periph1_reg_13_in         ),
    .periph1_reg_14_i          ( periph1_reg_14_in         ),
    .periph1_reg_15_i          ( periph1_reg_15_in         ),

    .periph1_reg_00_o          ( periph1_reg_00_out        ),
    .periph1_reg_01_o          ( periph1_reg_01_out        ),
    .periph1_reg_02_o          ( periph1_reg_02_out        ),
    .periph1_reg_03_o          ( periph1_reg_03_out        ),
    .periph1_reg_04_o          ( periph1_reg_04_out        ),
    .periph1_reg_05_o          ( periph1_reg_05_out        ),
    .periph1_reg_06_o          ( periph1_reg_06_out        ),
    .periph1_reg_07_o          ( periph1_reg_07_out        ),

// AHB PERIPHERAL #2
    .periph2_reg_08_i          ( periph2_reg_08_in         ),
    .periph2_reg_09_i          ( periph2_reg_09_in         ),
    .periph2_reg_10_i          ( periph2_reg_10_in         ),
    .periph2_reg_11_i          ( periph2_reg_11_in         ),
    .periph2_reg_12_i          ( periph2_reg_12_in         ),
    .periph2_reg_13_i          ( periph2_reg_13_in         ),
    .periph2_reg_14_i          ( periph2_reg_14_in         ),
    .periph2_reg_15_i          ( periph2_reg_15_in         ),

    .periph2_reg_00_o          ( periph2_reg_00_out        ),
    .periph2_reg_01_o          ( periph2_reg_01_out        ),
    .periph2_reg_02_o          ( periph2_reg_02_out        ),
    .periph2_reg_03_o          ( periph2_reg_03_out        ),
    .periph2_reg_04_o          ( periph2_reg_04_out        ),
    .periph2_reg_05_o          ( periph2_reg_05_out        ),
    .periph2_reg_06_o          ( periph2_reg_06_out        ),
    .periph2_reg_07_o          ( periph2_reg_07_out        ),

// AHB PLIC
    .plic_irq_src_i            ( plic_irq_src              ),
    .plic_irq_m_external_o     ( plic_irq_m_external       ),
    .plic_irq_s_external_o     ( plic_irq_s_external       ),

// AHB ACLINT
    .hclk_aon_i                ( hclk_aon                  ),
    .hclk_aon_en_i             ( hclk_aon_en               ),
    .clk_lf_i                  ( clk_lf                    ),
    .resetn_lf_i               ( resetn_lf                 ),
    .aclint_irq_m_software_o   ( aclint_irq_m_software     ),
    .aclint_irq_s_software_o   ( aclint_irq_s_software     ),
    .aclint_irq_m_timer_o      ( aclint_irq_m_timer        ),
    .aclint_mtimer_wake_lf_o   ( aclint_mtimer_wake_lf     ),
    .aclint_time_req_i         ( time_req                  ),
    .aclint_time_gnt_o         ( aclint_time_gnt           ),
    .aclint_time_val_o         ( aclint_time_val           )
);

//--------------------------------------------------------------------
// INSTRUCTION DECODER AND PROBES FOR DEBUG
//--------------------------------------------------------------------

probes_instructions probes_instructions ();
probes_debug #(.DEBUG_EN(DEBUG_EN)) probes_debug ();
probes_cpu          probes_cpu();
probes_cpu_alt      probes_cpu_alt();
probes_rom          probes_rom();
probes_sram         probes_sram();
probes_var          probes_var();
probes_stack        probes_stack();
probes_stack_alt    probes_stack_alt();


//--------------------------------------------------------------------
// OTHER STUFF
//--------------------------------------------------------------------

//
// Exception Monitors
//----------------------------------------
// Control whether exceptions are treated as errors (increment error counter)
// Set to 0 for tests that intentionally verify exception handling

monitor_exception   monitor_excp_inst_address_misaligned  ({"Instruction Missaligned Address", 264'b0}, dut.arv_csr_top_inst.if_excp_inst_address_misaligned_i,  free_clk, error_on_exception);
monitor_exception   monitor_excp_inst_access_fault        ({"Instruction Access Fault",        320'b0}, dut.arv_csr_top_inst.id_excp_inst_access_fault_i,        free_clk, error_on_exception);
monitor_exception   monitor_excp_id_illegal_instruction   ({"Illegal Instruction",             360'b0}, dut.arv_csr_top_inst.id_excp_illegal_inst_i,             free_clk, error_on_exception);
monitor_exception   monitor_excp_ebreak                   ({"EBREAK",                          464'b0}, dut.arv_csr_top_inst.id_excp_ebreak_i,                   free_clk, error_on_exception);
monitor_exception   monitor_excp_ecall                    ({"ECALL",                           472'b0}, dut.arv_csr_top_inst.id_excp_ecall_i,                    free_clk, error_on_exception);
monitor_exception   monitor_excp_load_address_misaligned  ({"Data Load  Missaligned Address",  272'b0}, dut.arv_csr_top_inst.ex_excp_load_address_misaligned_i,  free_clk, error_on_exception);
monitor_exception   monitor_excp_store_address_misaligned ({"Data Store Missaligned Address",  272'b0}, dut.arv_csr_top_inst.ex_excp_store_address_misaligned_i, free_clk, error_on_exception);
monitor_exception   monitor_excp_load_access_fault        ({"Data Load  Bus Error   ",         328'b0}, dut.arv_csr_top_inst.wb_bus_error_load_i,                free_clk, error_on_exception);
monitor_exception   monitor_excp_store_access_fault       ({"Data Store Bus Error   ",         328'b0}, dut.arv_csr_top_inst.wb_bus_error_store_i,               free_clk, error_on_exception);

//
// Instruction/PC Consistency Checker
//----------------------------------------

instruction_pc_checker #(
    .ROM_SIZE_BYTES           (ROM_SIZE)
) instruction_pc_checker_inst (
    .hclk_i                   (free_clk),
    .hresetn_i                (hresetn),
    .id_instruction_i         (dut.arv_decode_inst.id_instruction_i),
    .id_instruction_valid_i   (dut.arv_decode_inst.id_instruction_valid_i),
    .id_instruction_request_i (dut.arv_decode_inst.id_instruction_request_o),
    .id_pc_i                  (dut.arv_decode_inst.id_pc_i),
    .report_trigger_i         (checker_report_en),
    .checker_enable_i         (checker_enable)
);

//
// AHB-Lite address-phase stability checkers (instruction + data masters)
//----------------------------------------
`ifdef AHB_PROTOCOL_CHECK
wire ahb_chk_en = checker_enable;
`else
wire ahb_chk_en = 1'b0;
`endif

// Instruction bus: fully checked, no exemptions. inst_htrans_o is gated with
// inst_hready_i, so the master only presents NONSEQ on cycles the transfer is accepted
// and no mid-wait address-phase change can be observed.
ahb_protocol_checker ahb_protocol_checker_inst (
    .bus_name_i             ({"AHB Instruction Bus", 360'b0}),
    .hclk_i                 (dut_hclk),
    .hresetn_i              (hresetn),
    .haddr_i                (inst_haddr),
    .htrans_i               (inst_htrans),
    .hsize_i                (inst_hsize),
    .hwrite_i               (inst_hwrite),
    .hburst_i               (inst_hburst),
    .hready_i               (inst_hready),
    .hresp_i                (inst_hresp),
    .checker_enable_i       (ahb_chk_en)
);

ahb_protocol_checker ahb_protocol_checker_data (
    .bus_name_i             ({"AHB Data Bus", 416'b0}),
    .hclk_i                 (dut_hclk),
    .hresetn_i              (hresetn),
    .haddr_i                (data_haddr),
    .htrans_i               (data_htrans),
    .hsize_i                (data_hsize),
    .hwrite_i               (data_hwrite),
    .hburst_i               (data_hburst),
    .hready_i               (data_hready),
    .hresp_i                (data_hresp),
    .checker_enable_i       (ahb_chk_en)
);

//
// Generate Waveform
//----------------------------------------
initial
  begin
   `ifdef NODUMP
   `else
     `ifdef VPD_FILE
        $vcdplusfile("tb_arvern.vpd");
        $vcdpluson();
     `else
       `ifdef TRN_FILE
          $recordfile ("tb_arvern.trn");
          $recordvars;
       `else
          $dumpfile("tb_arvern.vcd");
          $dumpvars(0, tb_arvern);
       `endif
     `endif
   `endif
  end


//
// End of simulation
//----------------------------------------

initial // Timeout
  begin
   `ifdef NO_TIMEOUT
   `else
     `ifdef VERY_LONG_TIMEOUT
         #5000000000;
     `else
     `ifdef LONG_TIMEOUT
         #500000000;
     `else
       #50000000;
     `endif
     `endif
       $display(" ===============================================");
       $display("|               SIMULATION FAILED               |");
       $display("|              (simulation Timeout)             |");
       $display(" ===============================================");
       $display("");
       tb_extra_report;
       tb_result_file("FAILED");
       $finish;
   `endif
  end

`include "tb_irq_checkers.v"

// Subordinate-side HREADY protocol violations, counted inside the wait-state
// models (see ahb_waitstate_inserter.v: a stalling subordinate must be handed
// hready=0). Folded into `error` at the end of the test.
integer hready_viol_total;
task collect_hready_violations;
  begin
     hready_viol_total = 0;
`ifndef FUSED_AHB
     hready_viol_total = hready_viol_total + ahb_bus_system_inst.ahb_waitstate_inserter_rom_inst.hready_viol_cnt
                                          + ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.hready_viol_cnt
                                          + ahb_bus_system_inst.ahb_waitstate_inserter_sram_lo_x_inst.hready_viol_cnt;
`endif
     hready_viol_total = hready_viol_total + ahb_bus_system_inst.ahb_waitstate_inserter_sram_nx_inst.hready_viol_cnt
                                          + ahb_bus_system_inst.ahb_waitstate_inserter_periph0_inst.hready_viol_cnt
                                          + ahb_bus_system_inst.ahb_waitstate_inserter_periph1_inst.hready_viol_cnt
                                          + ahb_bus_system_inst.ahb_waitstate_inserter_periph2_inst.hready_viol_cnt;
     if (hready_viol_total != 0)
       begin
          $display("ERROR: %0d cycle(s) where a stalling subordinate was handed hready=1", hready_viol_total);
          error = error + hready_viol_total;
       end
  end
endtask

// Subordinate-side HMASTER: the fabric numbers the instruction port 4'h0 and
// the data port 4'h1, and ORs data_hmaster_o into HMASTER[3], so an SBA
// transfer arrives as 4'h9. Any other value is an error; SBA arrivals are
// counted for the debug tests (not visible behind the fused ROM/SRAM).
integer sba_hmaster_cnt;
initial sba_hmaster_cnt = 0;

task check_sub_hmaster;
  input       commit;
  input [3:0] hmaster;
  begin
     if (commit) begin
        if ((hmaster != 4'h0) && (hmaster != 4'h1) && (hmaster != 4'h9)) begin
           $display("ERROR: subordinate HMASTER=%h (expected 0, 1 or 9) %t ns", hmaster, $time);
           error = error + 1;
        end
        if (hmaster == 4'h9) sba_hmaster_cnt = sba_hmaster_cnt + 1;
     end
  end
endtask

always @(posedge free_clk) begin
`ifndef FUSED_AHB
   check_sub_hmaster(ahb_bus_system_inst.s_rom_hsel       & ahb_bus_system_inst.s_rom_hready       & ahb_bus_system_inst.s_rom_htrans[1],       ahb_bus_system_inst.s_rom_hmaster);
   check_sub_hmaster(ahb_bus_system_inst.s_sram_x_hsel    & ahb_bus_system_inst.s_sram_x_hready    & ahb_bus_system_inst.s_sram_x_htrans[1],    ahb_bus_system_inst.s_sram_x_hmaster);
   check_sub_hmaster(ahb_bus_system_inst.s_sram_lo_x_hsel & ahb_bus_system_inst.s_sram_lo_x_hready & ahb_bus_system_inst.s_sram_lo_x_htrans[1], ahb_bus_system_inst.s_sram_lo_x_hmaster);
`endif
   check_sub_hmaster(ahb_bus_system_inst.s_sram_nx_hsel   & ahb_bus_system_inst.s_sram_nx_hready   & ahb_bus_system_inst.s_sram_nx_htrans[1],   ahb_bus_system_inst.s_sram_nx_hmaster);
   check_sub_hmaster(ahb_bus_system_inst.s_periph0_hsel   & ahb_bus_system_inst.s_periph0_hready   & ahb_bus_system_inst.s_periph0_htrans[1],   ahb_bus_system_inst.s_periph0_hmaster);
   check_sub_hmaster(ahb_bus_system_inst.s_periph1_hsel   & ahb_bus_system_inst.s_periph1_hready   & ahb_bus_system_inst.s_periph1_htrans[1],   ahb_bus_system_inst.s_periph1_hmaster);
   check_sub_hmaster(ahb_bus_system_inst.s_periph2_hsel   & ahb_bus_system_inst.s_periph2_hready   & ahb_bus_system_inst.s_periph2_htrans[1],   ahb_bus_system_inst.s_periph2_hmaster);
end

initial // Normal end of test
  begin
     #10;
     @(posedge stimulus_done);
     collect_hready_violations;

     $display(" ===============================================");
     if (error!=0)
       begin
          $display("|               SIMULATION FAILED               |");
          $display("|     (some verilog stimulus checks failed)     |");
          $display("|     (      %d errors           )     |", error);
       end
     else
       begin
          $display("|               SIMULATION PASSED               |");
       end
     $display(" ===============================================");
     $display("");
     tb_extra_report;
     tb_result_file((error!=0) ? "FAILED" : "PASSED");
     $finish;
  end


//
// Tasks Definition
//------------------------------

   task tb_error;
      input [65*8:0] error_string;
      begin
         $display("ERROR: %s %t", error_string, $time);
         error = error+1;
      end
   endtask

   task tb_extra_report;
      begin
         // Trigger instruction/PC checker report
         checker_report_en = 1;
         #1;
         checker_report_en = 0;

`ifndef NOTRACE
         // Flush pending trace entries and close trace file
         probes_instructions.trace_flush_and_close;
         probes_debug.trace_flush_and_close;
`endif

         $display("");
         $display("SIMULATION SEED: %d", `SEED);
         $display("");
      end
   endtask

   task tb_skip_finish;
      input [65*8-1:0] skip_string;
      begin
         $display(" ===============================================");
         $display("|               SIMULATION SKIPPED              |");
         $display("%s", skip_string);
         $display(" ===============================================");
         $display("");
         tb_extra_report;
         tb_result_file("SKIPPED");
         $finish;
      end
   endtask

   // Verdict for rtlsim.sh, which turns it into the simulation's exit status
   // ($finish exits 0 whatever the outcome).
   task tb_result_file;
      input [8*8-1:0] verdict;
      integer fd;
      begin
         fd = $fopen("sim_result.txt", "w");
         $fdisplay(fd, "%0s", verdict);
         $fclose(fd);
      end
   endtask

   //------------------------------------------------------------------------
   // DMI bus helper tasks - dmi_xfer / dmi_write / dmi_read. Factored
   // into a dedicated file like check_tasks.v / tb_irq_checkers.v; the DMI signals
   // they drive are declared next to the DUT instantiation above.
   //------------------------------------------------------------------------
`include "debug_dmi_tasks.v"

endmodule

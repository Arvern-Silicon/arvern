//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    ahb_bus_system
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : ahb_bus_system.v
// Module Description : Full AHB bus system used by the arvern testbench
//                      (ROM, SRAM, peripheral models + decoder + arbiter + interconnect wiring).
//----------------------------------------------------------------------------

module  ahb_bus_system #(

// PARAMETERs
//======================================
    parameter                ROM_SIZE        = 8*1024,                // Size of the ROM memory instance (in Bytes)
    parameter                SRAM_X_SIZE     = 8*1024,                // Size of the Executable SRAM memory instance (in Bytes)
    parameter                SRAM_NX_SIZE    = 8*1024,                // Size of the Non-executable SRAM memory instance (in Bytes)
    parameter                PLIC_NUM_SRC    = 31,                    // PLIC: number of external interrupt sources
    parameter                PLIC_SU_MODE_EN = 1                      // PLIC: per-hart S-context (must match core SU_MODE_EN)

) (

// AHB CLOCK & RESET
    input  wire                  hclk_i,
    input  wire                  hresetn_i,
    output wire                  hclk_en_o,

// RANDOM WAIT STATES CONFIGURATION
    input  wire           [31:0] s_rom_number_ws_i,
    input  wire                  s_rom_random_ws_en_i,
    input  wire           [31:0] s_sram_x_number_ws_i,
    input  wire                  s_sram_x_random_ws_en_i,
    input  wire           [31:0] s_sram_nx_number_ws_i,
    input  wire                  s_sram_nx_random_ws_en_i,
    input  wire           [31:0] s_periph0_number_ws_i,
    input  wire                  s_periph0_random_ws_en_i,
    input  wire           [31:0] s_periph1_number_ws_i,
    input  wire                  s_periph1_random_ws_en_i,
    input  wire           [31:0] s_periph2_number_ws_i,
    input  wire                  s_periph2_random_ws_en_i,

// EXECUTABLE AHB BUS MANAGER INTERFACE
    input  wire           [31:0] m_x_haddr_i,
    input  wire            [2:0] m_x_hburst_i,
    input  wire                  m_x_hmastlock_i,
    input  wire            [3:0] m_x_hprot_i,
    input  wire            [2:0] m_x_hsize_i,
    input  wire                  m_x_hsmode_i,
    input  wire            [1:0] m_x_htrans_i,
    input  wire           [31:0] m_x_hwdata_i,
    input  wire                  m_x_hwrite_i,

    output wire           [31:0] m_x_hrdata_o,
    output wire                  m_x_hready_o,
    output wire                  m_x_hresp_o,

// NON-EXECUTABLE AHB MANAGER INTERFACES
    input  wire           [31:0] m_nx_haddr_i,
    input  wire            [2:0] m_nx_hburst_i,
    input  wire                  m_nx_hmastlock_i,
    input  wire            [3:0] m_nx_hprot_i,
    input  wire            [2:0] m_nx_hsize_i,
    input  wire                  m_nx_hsmode_i,
    input  wire            [1:0] m_nx_htrans_i,
    input  wire           [31:0] m_nx_hwdata_i,
    input  wire                  m_nx_hwrite_i,

    output wire           [31:0] m_nx_hrdata_o,
    output wire                  m_nx_hready_o,
    output wire                  m_nx_hresp_o,

// AHB PERIPHERAL #0
    input  wire           [31:0] periph0_reg_08_i,
    input  wire           [31:0] periph0_reg_09_i,
    input  wire           [31:0] periph0_reg_10_i,
    input  wire           [31:0] periph0_reg_11_i,
    input  wire           [31:0] periph0_reg_12_i,
    input  wire           [31:0] periph0_reg_13_i,
    input  wire           [31:0] periph0_reg_14_i,
    input  wire           [31:0] periph0_reg_15_i,

    output wire           [31:0] periph0_reg_00_o,
    output wire           [31:0] periph0_reg_01_o,
    output wire           [31:0] periph0_reg_02_o,
    output wire           [31:0] periph0_reg_03_o,
    output wire           [31:0] periph0_reg_04_o,
    output wire           [31:0] periph0_reg_05_o,
    output wire           [31:0] periph0_reg_06_o,
    output wire           [31:0] periph0_reg_07_o,

// AHB PERIPHERAL #1
    input  wire           [31:0] periph1_reg_08_i,
    input  wire           [31:0] periph1_reg_09_i,
    input  wire           [31:0] periph1_reg_10_i,
    input  wire           [31:0] periph1_reg_11_i,
    input  wire           [31:0] periph1_reg_12_i,
    input  wire           [31:0] periph1_reg_13_i,
    input  wire           [31:0] periph1_reg_14_i,
    input  wire           [31:0] periph1_reg_15_i,

    output wire           [31:0] periph1_reg_00_o,
    output wire           [31:0] periph1_reg_01_o,
    output wire           [31:0] periph1_reg_02_o,
    output wire           [31:0] periph1_reg_03_o,
    output wire           [31:0] periph1_reg_04_o,
    output wire           [31:0] periph1_reg_05_o,
    output wire           [31:0] periph1_reg_06_o,
    output wire           [31:0] periph1_reg_07_o,

// AHB PERIPHERAL #2
    input  wire           [31:0] periph2_reg_08_i,
    input  wire           [31:0] periph2_reg_09_i,
    input  wire           [31:0] periph2_reg_10_i,
    input  wire           [31:0] periph2_reg_11_i,
    input  wire           [31:0] periph2_reg_12_i,
    input  wire           [31:0] periph2_reg_13_i,
    input  wire           [31:0] periph2_reg_14_i,
    input  wire           [31:0] periph2_reg_15_i,

    output wire           [31:0] periph2_reg_00_o,
    output wire           [31:0] periph2_reg_01_o,
    output wire           [31:0] periph2_reg_02_o,
    output wire           [31:0] periph2_reg_03_o,
    output wire           [31:0] periph2_reg_04_o,
    output wire           [31:0] periph2_reg_05_o,
    output wire           [31:0] periph2_reg_06_o,
    output wire           [31:0] periph2_reg_07_o,

// AHB PLIC
    input  wire [PLIC_NUM_SRC:0] plic_irq_src_i,        // External level lines into the PLIC; bit 0 ignored
    output wire                  plic_irq_m_external_o, // M-mode external IRQ to the core
    output wire                  plic_irq_s_external_o, // S-mode external IRQ to the core (0 when PLIC_SU_MODE_EN=0)

// AHB ACLINT
    input  wire                  hclk_aon_i,              // Always-on AHB-frequency clock (free-running copy of hclk_i; drives the LF -> hclk MTIP synchronizer inside the ACLINT)
    input  wire                  clk_lf_i,                // Low-frequency clock for MTIME (always-on)
    input  wire                  resetn_lf_i,             // Active-low async reset for the LF domain (sync-deassert)
    output wire                  aclint_irq_m_software_o, // MSIP to the core (hclk_i domain)
    output wire                  aclint_irq_s_software_o, // SSIP to the core (hclk_i domain) -- 1-hclk pulse per SETSSIP write
    output wire                  aclint_irq_m_timer_o,    // MTIP to the core (hclk_i domain)
    output wire                  aclint_mtimer_wake_lf_o, // LF-domain MTIP wake to the SoC's power controller; valid even while hclk_i is gated
    input  wire                  aclint_time_req_i,       // Zicntr time-request from the core
    output wire                  aclint_time_gnt_o,       // Zicntr grant pulse from the ACLINT
    output wire           [63:0] aclint_time_val_o        // 64-bit MTIME snapshot held alongside the grant

);


//=============================================================================
// 1)  WIRE & REGISTER DEFINITION
//=============================================================================

// Local parameters
localparam               ROM_ADDRW      = $clog2(ROM_SIZE)-2;     // Address width of the ROM memory instance (32b words)
localparam               ROM_HADDRW     = $clog2(ROM_SIZE);       // Address width of the ROM AHB interface (8b words)

localparam               SRAM_X_ADDRW   = $clog2(SRAM_X_SIZE)-2;  // Address width of the Executable SRAM memory instance (32b words)
localparam               SRAM_X_HADDRW  = $clog2(SRAM_X_SIZE);    // Address width of the Executable SRAM AHB interface (8b words)

localparam               SRAM_NX_ADDRW  = $clog2(SRAM_NX_SIZE)-2; // Address width of the Non-executable SRAM memory instance (32b words)
localparam               SRAM_NX_HADDRW = $clog2(SRAM_NX_SIZE);   // Address width of the Non-executable SRAM AHB interface (8b words)

localparam               HAUSER_W       = 1;                      // Width of the HAUSER bus (min value is 1)

// Arbiter Interface
wire                     m_nx_grant;
wire                     m_nx_request;

wire               [1:0] m_grant;
wire               [1:0] m_request;

// Address Decoder Interface
wire               [7:0] s_x_decoder_1hot;
wire              [31:0] s_x_decoder_addr;
wire               [7:0] s_decoder_1hot;
wire              [31:0] s_decoder_addr;

// AHB Subordinate Interfaces
wire              [31:0] s_rom_hrdata;
wire                     s_rom_hreadyout;
wire                     s_rom_hresp;
wire                     s_rom_hsel;
wire              [31:0] s_rom_haddr;
wire      [HAUSER_W-1:0] s_rom_hauser;
wire               [2:0] s_rom_hburst;
wire               [3:0] s_rom_hmaster;
wire                     s_rom_hmastlock;
wire               [3:0] s_rom_hprot;
wire                     s_rom_hready;
wire               [2:0] s_rom_hsize;
wire               [1:0] s_rom_htrans;
wire              [31:0] s_rom_hwdata;
wire                     s_rom_hwrite;

wire              [31:0] s_sram_x_hrdata;
wire                     s_sram_x_hreadyout;
wire                     s_sram_x_hresp;
wire                     s_sram_x_hsel;
wire              [31:0] s_sram_x_haddr;
wire      [HAUSER_W-1:0] s_sram_x_hauser;
wire               [2:0] s_sram_x_hburst;
wire               [3:0] s_sram_x_hmaster;
wire                     s_sram_x_hmastlock;
wire               [3:0] s_sram_x_hprot;
wire                     s_sram_x_hready;
wire               [2:0] s_sram_x_hsize;
wire               [1:0] s_sram_x_htrans;
wire              [31:0] s_sram_x_hwdata;
wire                     s_sram_x_hwrite;

wire              [31:0] s_sram_nx_hrdata;
wire                     s_sram_nx_hreadyout;
wire                     s_sram_nx_hresp;
wire                     s_sram_nx_hsel;
wire              [31:0] s_sram_nx_haddr;
wire      [HAUSER_W-1:0] s_sram_nx_hauser;
wire               [2:0] s_sram_nx_hburst;
wire               [3:0] s_sram_nx_hmaster;
wire                     s_sram_nx_hmastlock;
wire               [3:0] s_sram_nx_hprot;
wire                     s_sram_nx_hready;
wire               [2:0] s_sram_nx_hsize;
wire               [1:0] s_sram_nx_htrans;
wire              [31:0] s_sram_nx_hwdata;
wire                     s_sram_nx_hwrite;

wire              [31:0] s_periph0_hrdata;
wire                     s_periph0_hreadyout;
wire                     s_periph0_hresp;
wire                     s_periph0_hsel;
wire              [31:0] s_periph0_haddr;
wire      [HAUSER_W-1:0] s_periph0_hauser;
wire               [2:0] s_periph0_hburst;
wire               [3:0] s_periph0_hmaster;
wire                     s_periph0_hmastlock;
wire               [3:0] s_periph0_hprot;
wire                     s_periph0_hready;
wire               [2:0] s_periph0_hsize;
wire               [1:0] s_periph0_htrans;
wire              [31:0] s_periph0_hwdata;
wire                     s_periph0_hwrite;

wire              [31:0] s_periph1_hrdata;
wire                     s_periph1_hreadyout;
wire                     s_periph1_hresp;
wire                     s_periph1_hsel;
wire              [31:0] s_periph1_haddr;
wire      [HAUSER_W-1:0] s_periph1_hauser;
wire               [2:0] s_periph1_hburst;
wire               [3:0] s_periph1_hmaster;
wire                     s_periph1_hmastlock;
wire               [3:0] s_periph1_hprot;
wire                     s_periph1_hready;
wire               [2:0] s_periph1_hsize;
wire               [1:0] s_periph1_htrans;
wire              [31:0] s_periph1_hwdata;
wire                     s_periph1_hwrite;

wire              [31:0] s_periph2_hrdata;
wire                     s_periph2_hreadyout;
wire                     s_periph2_hresp;
wire                     s_periph2_hsel;
wire              [31:0] s_periph2_haddr;
wire      [HAUSER_W-1:0] s_periph2_hauser;
wire               [2:0] s_periph2_hburst;
wire               [3:0] s_periph2_hmaster;
wire                     s_periph2_hmastlock;
wire               [3:0] s_periph2_hprot;
wire                     s_periph2_hready;
wire               [2:0] s_periph2_hsize;
wire               [1:0] s_periph2_htrans;
wire              [31:0] s_periph2_hwdata;
wire                     s_periph2_hwrite;

wire              [31:0] s_plic_hrdata;
wire                     s_plic_hreadyout;
wire                     s_plic_hresp;
wire                     s_plic_hsel;
wire              [31:0] s_plic_haddr;
wire      [HAUSER_W-1:0] s_plic_hauser;
wire               [2:0] s_plic_hburst;
wire               [3:0] s_plic_hmaster;
wire                     s_plic_hmastlock;
wire               [3:0] s_plic_hprot;
wire                     s_plic_hready;
wire               [2:0] s_plic_hsize;
wire               [1:0] s_plic_htrans;
wire              [31:0] s_plic_hwdata;
wire                     s_plic_hwrite;

wire              [31:0] s_aclint_hrdata;
wire                     s_aclint_hreadyout;
wire                     s_aclint_hresp;
wire                     s_aclint_hsel;
wire              [31:0] s_aclint_haddr;
wire      [HAUSER_W-1:0] s_aclint_hauser;
wire               [2:0] s_aclint_hburst;
wire               [3:0] s_aclint_hmaster;
wire                     s_aclint_hmastlock;
wire               [3:0] s_aclint_hprot;
wire                     s_aclint_hready;
wire               [2:0] s_aclint_hsize;
wire               [1:0] s_aclint_htrans;
wire              [31:0] s_aclint_hwdata;
wire                     s_aclint_hwrite;

// AHB Subordinate Interfaces (wait-state inserter)
wire              [31:0] ws_s_rom_hrdata;
wire                     ws_s_rom_hreadyout;
wire                     ws_s_rom_hresp;
wire                     ws_s_rom_hsel;
wire              [31:0] ws_s_rom_haddr;
wire      [HAUSER_W-1:0] ws_s_rom_hauser;
wire               [3:0] ws_s_rom_hprot;
wire                     ws_s_rom_hready;
wire               [2:0] ws_s_rom_hsize;
wire               [1:0] ws_s_rom_htrans;
wire              [31:0] ws_s_rom_hwdata;
wire                     ws_s_rom_hwrite;

wire              [31:0] ws_s_sram_x_hrdata;
wire                     ws_s_sram_x_hreadyout;
wire                     ws_s_sram_x_hresp;
wire                     ws_s_sram_x_hsel;
wire              [31:0] ws_s_sram_x_haddr;
wire      [HAUSER_W-1:0] ws_s_sram_x_hauser;
wire               [3:0] ws_s_sram_x_hprot;
wire                     ws_s_sram_x_hready;
wire               [2:0] ws_s_sram_x_hsize;
wire               [1:0] ws_s_sram_x_htrans;
wire              [31:0] ws_s_sram_x_hwdata;
wire                     ws_s_sram_x_hwrite;

wire              [31:0] ws_s_sram_nx_hrdata;
wire                     ws_s_sram_nx_hreadyout;
wire                     ws_s_sram_nx_hresp;
wire                     ws_s_sram_nx_hsel;
wire              [31:0] ws_s_sram_nx_haddr;
wire      [HAUSER_W-1:0] ws_s_sram_nx_hauser;
wire               [3:0] ws_s_sram_nx_hprot;
wire                     ws_s_sram_nx_hready;
wire               [2:0] ws_s_sram_nx_hsize;
wire               [1:0] ws_s_sram_nx_htrans;
wire              [31:0] ws_s_sram_nx_hwdata;
wire                     ws_s_sram_nx_hwrite;

wire              [31:0] ws_s_periph0_hrdata;
wire                     ws_s_periph0_hreadyout;
wire                     ws_s_periph0_hresp;
wire                     ws_s_periph0_hsel;
wire              [31:0] ws_s_periph0_haddr;
wire      [HAUSER_W-1:0] ws_s_periph0_hauser;
wire               [3:0] ws_s_periph0_hprot;
wire                     ws_s_periph0_hready;
wire               [2:0] ws_s_periph0_hsize;
wire               [1:0] ws_s_periph0_htrans;
wire              [31:0] ws_s_periph0_hwdata;
wire                     ws_s_periph0_hwrite;

wire              [31:0] ws_s_periph1_hrdata;
wire                     ws_s_periph1_hreadyout;
wire                     ws_s_periph1_hresp;
wire                     ws_s_periph1_hsel;
wire              [31:0] ws_s_periph1_haddr;
wire      [HAUSER_W-1:0] ws_s_periph1_hauser;
wire               [3:0] ws_s_periph1_hprot;
wire                     ws_s_periph1_hready;
wire               [2:0] ws_s_periph1_hsize;
wire               [1:0] ws_s_periph1_htrans;
wire              [31:0] ws_s_periph1_hwdata;
wire                     ws_s_periph1_hwrite;

wire              [31:0] ws_s_periph2_hrdata;
wire                     ws_s_periph2_hreadyout;
wire                     ws_s_periph2_hresp;
wire                     ws_s_periph2_hsel;
wire              [31:0] ws_s_periph2_haddr;
wire      [HAUSER_W-1:0] ws_s_periph2_hauser;
wire               [3:0] ws_s_periph2_hprot;
wire                     ws_s_periph2_hready;
wire               [2:0] ws_s_periph2_hsize;
wire               [1:0] ws_s_periph2_htrans;
wire              [31:0] ws_s_periph2_hwdata;
wire                     ws_s_periph2_hwrite;

// PLIC has no wait-state inserter: it is single-cycle by design. The fabric-side
// signals connect directly to the PLIC slave.

// ROM Interface
//   In FUSED_AHB mode, the fused interconnect drives a 30-bit word address
//   (rom0_addr_full); rom0_addr is the sliced version that feeds the macro.
//   In HIPERF/GENERIC modes, ahb_rom_controller drives rom0_addr directly and
//   rom0_addr_full is unused.
wire              [31:0] rom0_dout;
wire     [ROM_ADDRW-1:0] rom0_addr;
wire              [29:0] rom0_addr_full;
wire                     rom0_cen;
wire                     rom0_clk;

// Executable SRAM Interface  (same _full / sliced split as ROM)
wire              [31:0] sram_x_dout;
wire  [SRAM_X_ADDRW-1:0] sram_x_addr;
wire              [29:0] sram_x_addr_full;
wire                     sram_x_cen;
wire                     sram_x_clk;
wire              [31:0] sram_x_din;
wire               [3:0] sram_x_wen;

// Non-executable SRAM Interface
wire              [31:0] sram_nx_dout;
wire [SRAM_NX_ADDRW-1:0] sram_nx_addr;
wire                     sram_nx_cen;
wire                     sram_nx_clk;
wire              [31:0] sram_nx_din;
wire               [3:0] sram_nx_wen;

// Architectural clock-gating
wire                     interconnect_hclk;
wire                     interconnect_hclk_en;
reg                      interconnect_hclk_en_latch;

wire                     s_rom_hclk;
wire                     s_rom_hclk_en;
wire                     ws_s_rom_hclk_en;
reg                      s_rom_hclk_en_latch;

wire                     s_sram_x_hclk;
wire                     s_sram_x_hclk_en;
wire                     ws_s_sram_x_hclk_en;
reg                      s_sram_x_hclk_en_latch;

wire                     s_sram_nx_hclk;
wire                     s_sram_nx_hclk_en;
wire                     ws_s_sram_nx_hclk_en;
reg                      s_sram_nx_hclk_en_latch;

wire                     s_periph0_hclk;
wire                     s_periph0_hclk_en;
wire                     ws_s_periph0_hclk_en;
reg                      s_periph0_hclk_en_latch;

wire                     s_periph1_hclk;
wire                     s_periph1_hclk_en;
wire                     ws_s_periph1_hclk_en;
reg                      s_periph1_hclk_en_latch;

wire                     s_periph2_hclk;
wire                     s_periph2_hclk_en;
wire                     ws_s_periph2_hclk_en;
reg                      s_periph2_hclk_en_latch;

wire                     s_plic_hclk;
wire                     s_plic_hclk_en;
reg                      s_plic_hclk_en_latch;

wire                     s_aclint_hclk;
wire                     s_aclint_hclk_en;
reg                      s_aclint_hclk_en_latch;


//=============================================================================
// 2)  HIGH-PERF AHB INTERCONNECT
//=============================================================================
`ifdef HIPERF_AHB

ahb_interconnect_hiperf #(.NR_M    (1),       // Number of non-executable AHB Managers
                          .NR_S_X  (2),       // Number of AHB Subordinates in executable space
                          .NR_S_NX (6),       // Number of AHB Subordinates in non-executable space
                          .HAUSER_W(HAUSER_W) // Width of the HAUSER bus (min value is 1)
                         )               ahb_interconnect_inst (

// AHB CLOCK & RESET
    .hclk_i                ( interconnect_hclk                         ),
    .hresetn_i             ( hresetn_i                                 ),

    .hclk_en_o             ( interconnect_hclk_en                      ),

// EXECUTABLE AHB BUS MANAGER INTERFACE
    .m_x_haddr_i           ( m_x_haddr_i                               ),
    .m_x_hauser_i          ( m_x_hsmode_i                              ),
    .m_x_hburst_i          ( m_x_hburst_i                              ),
    .m_x_hmastlock_i       ( m_x_hmastlock_i                           ),
    .m_x_hprot_i           ( m_x_hprot_i                               ),
    .m_x_hsize_i           ( m_x_hsize_i                               ),
    .m_x_htrans_i          ( m_x_htrans_i                              ),
    .m_x_hwdata_i          ( m_x_hwdata_i                              ),
    .m_x_hwrite_i          ( m_x_hwrite_i                              ),
    .m_x_hrdata_o          ( m_x_hrdata_o                              ),
    .m_x_hready_o          ( m_x_hready_o                              ),
    .m_x_hresp_o           ( m_x_hresp_o                               ),

// NON-EXECUTABLE AHB MANAGER INTERFACES
    .m_nx_haddr_i          ( m_nx_haddr_i                              ),
    .m_nx_hauser_i         ( m_nx_hsmode_i                             ),
    .m_nx_hburst_i         ( m_nx_hburst_i                             ),
    .m_nx_hmastlock_i      ( m_nx_hmastlock_i                          ),
    .m_nx_hprot_i          ( m_nx_hprot_i                              ),
    .m_nx_hsize_i          ( m_nx_hsize_i                              ),
    .m_nx_htrans_i         ( m_nx_htrans_i                             ),
    .m_nx_hwdata_i         ( m_nx_hwdata_i                             ),
    .m_nx_hwrite_i         ( m_nx_hwrite_i                             ),
    .m_nx_hrdata_o         ( m_nx_hrdata_o                             ),
    .m_nx_hready_o         ( m_nx_hready_o                             ),
    .m_nx_hresp_o          ( m_nx_hresp_o                              ),

// ARBITER INTERFACE for NON-EXECUTABLE MANAGERS
    .m_nx_grant_i          ( m_nx_grant                                ),
    .m_nx_request_o        ( m_nx_request                              ),

// ADDRESS DECODER INTERFACES (FOR ALL SUBORDINATES)
    .s_decoder_1hot_i      ( s_decoder_1hot                            ),
    .s_decoder_addr_o      ( s_decoder_addr                            ),

// ADDRESS DECODER INTERFACES (FOR EXECUTABLE SUBORDINATES ONLY)
    .s_x_decoder_1hot_i    ( s_x_decoder_1hot[1:0]                     ),
    .s_x_decoder_addr_o    ( s_x_decoder_addr                          ),

// EXECUTABLE AHB SUBORDINATE INTERFACES
    .s_x_hrdata_i          ({s_sram_x_hrdata,     s_rom_hrdata        }),
    .s_x_hreadyout_i       ({s_sram_x_hreadyout,  s_rom_hreadyout     }),
    .s_x_hresp_i           ({s_sram_x_hresp,      s_rom_hresp         }),
    .s_x_haddr_o           ({s_sram_x_haddr,      s_rom_haddr         }),
    .s_x_hauser_o          ({s_sram_x_hauser,     s_rom_hauser        }),
    .s_x_hburst_o          ({s_sram_x_hburst,     s_rom_hburst        }),
    .s_x_hmaster_o         ({s_sram_x_hmaster,    s_rom_hmaster       }),
    .s_x_hmastlock_o       ({s_sram_x_hmastlock,  s_rom_hmastlock     }),
    .s_x_hprot_o           ({s_sram_x_hprot,      s_rom_hprot         }),
    .s_x_hready_o          ({s_sram_x_hready,     s_rom_hready        }),
    .s_x_hsel_o            ({s_sram_x_hsel,       s_rom_hsel          }),
    .s_x_hsize_o           ({s_sram_x_hsize,      s_rom_hsize         }),
    .s_x_htrans_o          ({s_sram_x_htrans,     s_rom_htrans        }),
    .s_x_hwdata_o          ({s_sram_x_hwdata,     s_rom_hwdata        }),
    .s_x_hwrite_o          ({s_sram_x_hwrite,     s_rom_hwrite        }),

// NON-EXECUTABLE AHB SUBORDINATE INTERFACES
    .s_nx_hrdata_i         ({s_aclint_hrdata,     s_plic_hrdata,       s_periph2_hrdata,    s_periph1_hrdata,    s_periph0_hrdata,    s_sram_nx_hrdata    }),
    .s_nx_hreadyout_i      ({s_aclint_hreadyout,  s_plic_hreadyout,    s_periph2_hreadyout, s_periph1_hreadyout, s_periph0_hreadyout, s_sram_nx_hreadyout }),
    .s_nx_hresp_i          ({s_aclint_hresp,      s_plic_hresp,        s_periph2_hresp,     s_periph1_hresp,     s_periph0_hresp,     s_sram_nx_hresp     }),

    .s_nx_haddr_o          ({s_aclint_haddr,      s_plic_haddr,        s_periph2_haddr,     s_periph1_haddr,     s_periph0_haddr,     s_sram_nx_haddr     }),
    .s_nx_hauser_o         ({s_aclint_hauser,     s_plic_hauser,       s_periph2_hauser,    s_periph1_hauser,    s_periph0_hauser,    s_sram_nx_hauser    }),
    .s_nx_hburst_o         ({s_aclint_hburst,     s_plic_hburst,       s_periph2_hburst,    s_periph1_hburst,    s_periph0_hburst,    s_sram_nx_hburst    }),
    .s_nx_hmaster_o        ({s_aclint_hmaster,    s_plic_hmaster,      s_periph2_hmaster,   s_periph1_hmaster,   s_periph0_hmaster,   s_sram_nx_hmaster   }),
    .s_nx_hmastlock_o      ({s_aclint_hmastlock,  s_plic_hmastlock,    s_periph2_hmastlock, s_periph1_hmastlock, s_periph0_hmastlock, s_sram_nx_hmastlock }),
    .s_nx_hprot_o          ({s_aclint_hprot,      s_plic_hprot,        s_periph2_hprot,     s_periph1_hprot,     s_periph0_hprot,     s_sram_nx_hprot     }),
    .s_nx_hready_o         ({s_aclint_hready,     s_plic_hready,       s_periph2_hready,    s_periph1_hready,    s_periph0_hready,    s_sram_nx_hready    }),
    .s_nx_hsel_o           ({s_aclint_hsel,       s_plic_hsel,         s_periph2_hsel,      s_periph1_hsel,      s_periph0_hsel,      s_sram_nx_hsel      }),
    .s_nx_hsize_o          ({s_aclint_hsize,      s_plic_hsize,        s_periph2_hsize,     s_periph1_hsize,     s_periph0_hsize,     s_sram_nx_hsize     }),
    .s_nx_htrans_o         ({s_aclint_htrans,     s_plic_htrans,       s_periph2_htrans,    s_periph1_htrans,    s_periph0_htrans,    s_sram_nx_htrans    }),
    .s_nx_hwdata_o         ({s_aclint_hwdata,     s_plic_hwdata,       s_periph2_hwdata,    s_periph1_hwdata,    s_periph0_hwdata,    s_sram_nx_hwdata    }),
    .s_nx_hwrite_o         ({s_aclint_hwrite,     s_plic_hwrite,       s_periph2_hwrite,    s_periph1_hwrite,    s_periph0_hwrite,    s_sram_nx_hwrite    })
);


//=============================================================================
// 3)  FUSED AHB INTERCONNECT
//=============================================================================
`elsif FUSED_AHB

ahb_interconnect_fused #(.NR_M         (1),        // Number of non-executable AHB Managers
                         .NR_S_X_ROM   (1),        // Number of fused ROM controllers
                         .NR_S_X_SRAM  (1),        // Number of fused SRAM controllers
                         .NR_S_NX      (6),        // Number of AHB Subordinates in non-executable space
                         .HAUSER_W     (HAUSER_W), // Width of the HAUSER bus (min value is 1)
                         .FIXED_B_PRIO (1'b1)      // 1'b1 = Fixed priority arbitration, 1'b0 = Round-robin arbitration
                        )                ahb_interconnect_inst (

// AHB CLOCK & RESET
    .hclk_i                ( interconnect_hclk                         ),
    .hresetn_i             ( hresetn_i                                 ),

    .hclk_en_o             ( interconnect_hclk_en                      ),

// EXECUTABLE AHB BUS MANAGER INTERFACE
    .m_x_haddr_i           ( m_x_haddr_i                               ),
    .m_x_hauser_i          ( m_x_hsmode_i                              ),
    .m_x_hburst_i          ( m_x_hburst_i                              ),
    .m_x_hmastlock_i       ( m_x_hmastlock_i                           ),
    .m_x_hprot_i           ( m_x_hprot_i                               ),
    .m_x_hsize_i           ( m_x_hsize_i                               ),
    .m_x_htrans_i          ( m_x_htrans_i                              ),
    .m_x_hwdata_i          ( m_x_hwdata_i                              ),
    .m_x_hwrite_i          ( m_x_hwrite_i                              ),
    .m_x_hrdata_o          ( m_x_hrdata_o                              ),
    .m_x_hready_o          ( m_x_hready_o                              ),
    .m_x_hresp_o           ( m_x_hresp_o                               ),

// NON-EXECUTABLE AHB MANAGER INTERFACES
    .m_nx_haddr_i          ( m_nx_haddr_i                              ),
    .m_nx_hauser_i         ( m_nx_hsmode_i                             ),
    .m_nx_hburst_i         ( m_nx_hburst_i                             ),
    .m_nx_hmastlock_i      ( m_nx_hmastlock_i                          ),
    .m_nx_hprot_i          ( m_nx_hprot_i                              ),
    .m_nx_hsize_i          ( m_nx_hsize_i                              ),
    .m_nx_htrans_i         ( m_nx_htrans_i                             ),
    .m_nx_hwdata_i         ( m_nx_hwdata_i                             ),
    .m_nx_hwrite_i         ( m_nx_hwrite_i                             ),
    .m_nx_hrdata_o         ( m_nx_hrdata_o                             ),
    .m_nx_hready_o         ( m_nx_hready_o                             ),
    .m_nx_hresp_o          ( m_nx_hresp_o                              ),

// ARBITER INTERFACE for NON-EXECUTABLE MANAGERS
    .m_nx_grant_i          ( m_nx_grant                                ),
    .m_nx_request_o        ( m_nx_request                              ),

// ADDRESS DECODER INTERFACES (FOR ALL SUBORDINATES)
    .s_decoder_1hot_i      ( s_decoder_1hot                            ),
    .s_decoder_addr_o      ( s_decoder_addr                            ),

// ADDRESS DECODER INTERFACES (FOR EXECUTABLE SUBORDINATES ONLY)
    .s_x_decoder_1hot_i    ( s_x_decoder_1hot[1:0]                     ),
    .s_x_decoder_addr_o    ( s_x_decoder_addr                          ),

// FUSED ROM CONTROLLER MEMORY INTERFACE  (slot 0 = low decoder bit)
    .rom_dout_i            ( rom0_dout                                 ),
    .rom_addr_o            ( rom0_addr_full                            ),
    .rom_cen_o             ( rom0_cen                                  ),
    .rom_clk_o             ( rom0_clk                                  ),

// FUSED SRAM CONTROLLER MEMORY INTERFACE (slot 1 = high decoder bit)
    .sram_dout_i           ( sram_x_dout                               ),
    .sram_addr_o           ( sram_x_addr_full                          ),
    .sram_cen_o            ( sram_x_cen                                ),
    .sram_clk_o            ( sram_x_clk                                ),
    .sram_din_o            ( sram_x_din                                ),
    .sram_wen_o            ( sram_x_wen                                ),

// NON-EXECUTABLE AHB SUBORDINATE INTERFACES
    .s_nx_hrdata_i         ({s_aclint_hrdata,    s_plic_hrdata,    s_periph2_hrdata,    s_periph1_hrdata,    s_periph0_hrdata,    s_sram_nx_hrdata    }),
    .s_nx_hreadyout_i      ({s_aclint_hreadyout, s_plic_hreadyout, s_periph2_hreadyout, s_periph1_hreadyout, s_periph0_hreadyout, s_sram_nx_hreadyout }),
    .s_nx_hresp_i          ({s_aclint_hresp,     s_plic_hresp,     s_periph2_hresp,     s_periph1_hresp,     s_periph0_hresp,     s_sram_nx_hresp     }),
    .s_nx_haddr_o          ({s_aclint_haddr,     s_plic_haddr,     s_periph2_haddr,     s_periph1_haddr,     s_periph0_haddr,     s_sram_nx_haddr     }),
    .s_nx_hauser_o         ({s_aclint_hauser,    s_plic_hauser,    s_periph2_hauser,    s_periph1_hauser,    s_periph0_hauser,    s_sram_nx_hauser    }),
    .s_nx_hburst_o         ({s_aclint_hburst,    s_plic_hburst,    s_periph2_hburst,    s_periph1_hburst,    s_periph0_hburst,    s_sram_nx_hburst    }),
    .s_nx_hmaster_o        ({s_aclint_hmaster,   s_plic_hmaster,   s_periph2_hmaster,   s_periph1_hmaster,   s_periph0_hmaster,   s_sram_nx_hmaster   }),
    .s_nx_hmastlock_o      ({s_aclint_hmastlock, s_plic_hmastlock, s_periph2_hmastlock, s_periph1_hmastlock, s_periph0_hmastlock, s_sram_nx_hmastlock }),
    .s_nx_hprot_o          ({s_aclint_hprot,     s_plic_hprot,     s_periph2_hprot,     s_periph1_hprot,     s_periph0_hprot,     s_sram_nx_hprot     }),
    .s_nx_hready_o         ({s_aclint_hready,    s_plic_hready,    s_periph2_hready,    s_periph1_hready,    s_periph0_hready,    s_sram_nx_hready    }),
    .s_nx_hsel_o           ({s_aclint_hsel,      s_plic_hsel,      s_periph2_hsel,      s_periph1_hsel,      s_periph0_hsel,      s_sram_nx_hsel      }),
    .s_nx_hsize_o          ({s_aclint_hsize,     s_plic_hsize,     s_periph2_hsize,     s_periph1_hsize,     s_periph0_hsize,     s_sram_nx_hsize     }),
    .s_nx_htrans_o         ({s_aclint_htrans,    s_plic_htrans,    s_periph2_htrans,    s_periph1_htrans,    s_periph0_htrans,    s_sram_nx_htrans    }),
    .s_nx_hwdata_o         ({s_aclint_hwdata,    s_plic_hwdata,    s_periph2_hwdata,    s_periph1_hwdata,    s_periph0_hwdata,    s_sram_nx_hwdata    }),
    .s_nx_hwrite_o         ({s_aclint_hwrite,    s_plic_hwrite,    s_periph2_hwrite,    s_periph1_hwrite,    s_periph0_hwrite,    s_sram_nx_hwrite    })
);

// Slice the fused fabric's 30-bit word address down to each macro's
// physical address width (the legacy ahb_rom_controller / ahb_sram_controller
// performed the slicing themselves; here it is explicit).
assign rom0_addr   = rom0_addr_full  [ROM_ADDRW-1:0];
assign sram_x_addr = sram_x_addr_full[SRAM_X_ADDRW-1:0];


//=============================================================================
// 3)  GENERIC AHB INTERCONNECT
//=============================================================================
`else

ahb_interconnect_generic #(.NR_M    (2),       // Number of AHB Managers
                           .NR_S    (8),       // Number of AHB Subordinates
                           .HAUSER_W(HAUSER_W) // Width of the HAUSER bus (min value is 1)
)                                        ahb_interconnect_generic_inst (

// AHB CLOCK & RESET
    .hclk_i                ( hclk_i                                    ),
    .hresetn_i             ( hresetn_i                                 ),

    .hclk_en_o             ( interconnect_hclk_en                      ),

// AHB MANAGER INTERFACES
    .m_haddr_i             ({m_nx_haddr_i,       m_x_haddr_i          }),
    .m_hauser_i            ({m_nx_hsmode_i,      m_x_hsmode_i         }),
    .m_hburst_i            ({m_nx_hburst_i,      m_x_hburst_i         }),
    .m_hmastlock_i         ({m_nx_hmastlock_i,   m_x_hmastlock_i      }),
    .m_hprot_i             ({m_nx_hprot_i,       m_x_hprot_i          }),
    .m_hsize_i             ({m_nx_hsize_i,       m_x_hsize_i          }),
    .m_htrans_i            ({m_nx_htrans_i,      m_x_htrans_i         }),
    .m_hwdata_i            ({m_nx_hwdata_i,      m_x_hwdata_i         }),
    .m_hwrite_i            ({m_nx_hwrite_i,      m_x_hwrite_i         }),

    .m_hrdata_o            ({m_nx_hrdata_o,      m_x_hrdata_o         }),
    .m_hready_o            ({m_nx_hready_o,      m_x_hready_o         }),
    .m_hresp_o             ({m_nx_hresp_o,       m_x_hresp_o          }),

// ARBITER INTERFACES
    .m_grant_i             ( m_grant                                   ),
    .m_request_o           ( m_request                                 ),

// ADDRESS DECODER INTERFACES
    .s_decoder_1hot_i      ( s_decoder_1hot                            ),
    .s_decoder_addr_o      ( s_decoder_addr                            ),

// AHB SUBORDINATE INTERFACES
    .s_hrdata_i            ({s_aclint_hrdata,    s_plic_hrdata,    s_periph2_hrdata,    s_periph1_hrdata,    s_periph0_hrdata,    s_sram_nx_hrdata,    s_sram_x_hrdata,     s_rom_hrdata    }),
    .s_hreadyout_i         ({s_aclint_hreadyout, s_plic_hreadyout, s_periph2_hreadyout, s_periph1_hreadyout, s_periph0_hreadyout, s_sram_nx_hreadyout, s_sram_x_hreadyout,  s_rom_hreadyout }),
    .s_hresp_i             ({s_aclint_hresp,     s_plic_hresp,     s_periph2_hresp,     s_periph1_hresp,     s_periph0_hresp,     s_sram_nx_hresp,     s_sram_x_hresp,      s_rom_hresp     }),
    .s_haddr_o             ({s_aclint_haddr,     s_plic_haddr,     s_periph2_haddr,     s_periph1_haddr,     s_periph0_haddr,     s_sram_nx_haddr,     s_sram_x_haddr,      s_rom_haddr     }),
    .s_hauser_o            ({s_aclint_hauser,    s_plic_hauser,    s_periph2_hauser,    s_periph1_hauser,    s_periph0_hauser,    s_sram_nx_hauser,    s_sram_x_hauser,     s_rom_hauser    }),
    .s_hburst_o            ({s_aclint_hburst,    s_plic_hburst,    s_periph2_hburst,    s_periph1_hburst,    s_periph0_hburst,    s_sram_nx_hburst,    s_sram_x_hburst,     s_rom_hburst    }),
    .s_hmaster_o           ({s_aclint_hmaster,   s_plic_hmaster,   s_periph2_hmaster,   s_periph1_hmaster,   s_periph0_hmaster,   s_sram_nx_hmaster,   s_sram_x_hmaster,    s_rom_hmaster   }),
    .s_hmastlock_o         ({s_aclint_hmastlock, s_plic_hmastlock, s_periph2_hmastlock, s_periph1_hmastlock, s_periph0_hmastlock, s_sram_nx_hmastlock, s_sram_x_hmastlock,  s_rom_hmastlock }),
    .s_hprot_o             ({s_aclint_hprot,     s_plic_hprot,     s_periph2_hprot,     s_periph1_hprot,     s_periph0_hprot,     s_sram_nx_hprot,     s_sram_x_hprot,      s_rom_hprot     }),
    .s_hready_o            ({s_aclint_hready,    s_plic_hready,    s_periph2_hready,    s_periph1_hready,    s_periph0_hready,    s_sram_nx_hready,    s_sram_x_hready,     s_rom_hready    }),
    .s_hsel_o              ({s_aclint_hsel,      s_plic_hsel,      s_periph2_hsel,      s_periph1_hsel,      s_periph0_hsel,      s_sram_nx_hsel,      s_sram_x_hsel,       s_rom_hsel      }),
    .s_hsize_o             ({s_aclint_hsize,     s_plic_hsize,     s_periph2_hsize,     s_periph1_hsize,     s_periph0_hsize,     s_sram_nx_hsize,     s_sram_x_hsize,      s_rom_hsize     }),
    .s_htrans_o            ({s_aclint_htrans,    s_plic_htrans,    s_periph2_htrans,    s_periph1_htrans,    s_periph0_htrans,    s_sram_nx_htrans,    s_sram_x_htrans,     s_rom_htrans    }),
    .s_hwdata_o            ({s_aclint_hwdata,    s_plic_hwdata,    s_periph2_hwdata,    s_periph1_hwdata,    s_periph0_hwdata,    s_sram_nx_hwdata,    s_sram_x_hwdata,     s_rom_hwdata    }),
    .s_hwrite_o            ({s_aclint_hwrite,    s_plic_hwrite,    s_periph2_hwrite,    s_periph1_hwrite,    s_periph0_hwrite,    s_sram_nx_hwrite,    s_sram_x_hwrite,     s_rom_hwrite    })
 );

`endif


// Architectural clock-gate
always @(hclk_i or interconnect_hclk_en)
  if (~hclk_i) interconnect_hclk_en_latch <= interconnect_hclk_en;
assign  interconnect_hclk  =  (hclk_i & interconnect_hclk_en_latch);


//=============================================================================
// 4)  ADDRESS DECODER + ARBITER
//=============================================================================

`ifdef HIPERF_AHB

// No arbitration, only one NX master
assign m_nx_grant = m_nx_request;

ahb_decoder #(.ROM_SIZE(ROM_SIZE), .SRAM_X_SIZE(SRAM_X_SIZE), .SRAM_NX_SIZE(SRAM_NX_SIZE)) ahb_decoder_x_inst (
    .decoder_addr_i        ( s_x_decoder_addr                          ),
    .decoder_1hot_o        ( s_x_decoder_1hot                          )
);
`elsif FUSED_AHB

// No arbitration, only one NX master  (same as HIPERF)
assign m_nx_grant = m_nx_request;

ahb_decoder #(.ROM_SIZE(ROM_SIZE), .SRAM_X_SIZE(SRAM_X_SIZE), .SRAM_NX_SIZE(SRAM_NX_SIZE)) ahb_decoder_x_inst (
    .decoder_addr_i        ( s_x_decoder_addr                          ),
    .decoder_1hot_o        ( s_x_decoder_1hot                          )
);
`else

ahb_arbiter ahb_arbiter_inst (

    .hclk_i                ( interconnect_hclk                         ),
    .hresetn_i             ( hresetn_i                                 ),
    .request_i             ( m_request                                 ),
    .grant_o               ( m_grant                                   )
);

`endif


ahb_decoder #(.ROM_SIZE(ROM_SIZE), .SRAM_X_SIZE(SRAM_X_SIZE), .SRAM_NX_SIZE(SRAM_NX_SIZE)) ahb_decoder_inst   (

    .decoder_addr_i        ( s_decoder_addr                            ),
    .decoder_1hot_o        ( s_decoder_1hot                            )
);


//=============================================================================
// 5)  ROM MEMORY
//=============================================================================
//   In FUSED_AHB mode, the AHB-side ROM controller is absorbed into
//   ahb_interconnect_fused -- only the physical macro lives here, and the WS
//   inserter/clock-gate are skipped (the fused fabric is single-cycle by design).
//
`ifndef FUSED_AHB

ahb_waitstate_inserter #(HAUSER_W) ahb_waitstate_inserter_rom_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_rom_hclk                                ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( s_rom_hclk_en                             ),

    .number_ws_i           ( s_rom_number_ws_i                         ),
    .random_ws_en_i        ( s_rom_random_ws_en_i                      ),

// AHB INTERFACE (TO FABRIC OR DRIVER)
    .haddr_i               ( s_rom_haddr                               ),
    .hauser_i              ( s_rom_hauser                              ),
    .hprot_i               ( s_rom_hprot                               ),
    .hready_i              ( s_rom_hready                              ),
    .hsize_i               ( s_rom_hsize                               ),
    .htrans_i              ( s_rom_htrans                              ),
    .hwdata_i              ( s_rom_hwdata                              ),
    .hwrite_i              ( s_rom_hwrite                              ),
    .hsel_i                ( s_rom_hsel                                ),
    .hrdata_o              ( s_rom_hrdata                              ),
    .hreadyout_o           ( s_rom_hreadyout                           ),
    .hresp_o               ( s_rom_hresp                               ),

// AHB INTERFACE (TO AHB SUBORDINATE)
    .s_haddr_o             ( ws_s_rom_haddr                            ),
    .s_hauser_o            ( ws_s_rom_hauser                           ),
    .s_hprot_o             ( ws_s_rom_hprot                            ),
    .s_hready_o            ( ws_s_rom_hready                           ),
    .s_hsize_o             ( ws_s_rom_hsize                            ),
    .s_htrans_o            ( ws_s_rom_htrans                           ),
    .s_hwdata_o            ( ws_s_rom_hwdata                           ),
    .s_hwrite_o            ( ws_s_rom_hwrite                           ),
    .s_hsel_o              ( ws_s_rom_hsel                             ),
    .s_hrdata_i            ( ws_s_rom_hrdata                           ),
    .s_hreadyout_i         ( ws_s_rom_hreadyout                        ),
    .s_hresp_i             ( ws_s_rom_hresp                            )
 );

ahb_rom_controller #(ROM_SIZE) ahb_rom_ctrl_inst0 (

// AHB CLOCK & RESET
    .hclk_i                ( s_rom_hclk                                ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( ws_s_rom_hclk_en                          ),

// AHB INTERFACE
    .haddr_i               ( ws_s_rom_haddr[ROM_HADDRW-1:0]            ),
    .hready_i              ( ws_s_rom_hready                           ),
    .hsize_i               ( ws_s_rom_hsize                            ),
    .htrans_i              ( ws_s_rom_htrans                           ),
    .hwdata_i              ( ws_s_rom_hwdata                           ),
    .hwrite_i              ( ws_s_rom_hwrite                           ),
    .hsel_i                ( ws_s_rom_hsel                             ),
    .hrdata_o              ( ws_s_rom_hrdata                           ),
    .hreadyout_o           ( ws_s_rom_hreadyout                        ),
    .hresp_o               ( ws_s_rom_hresp                            ),

// ROM INTERFACE
    .rom_dout_i            ( rom0_dout                                 ),
    .rom_addr_o            ( rom0_addr                                 ),
    .rom_cen_o             ( rom0_cen                                  ),
    .rom_clk_o             ( rom0_clk                                  )
 );

// Architectural clock-gate
always @(hclk_i or s_rom_hclk_en or ws_s_rom_hclk_en)
  if (~hclk_i) s_rom_hclk_en_latch <= (s_rom_hclk_en | ws_s_rom_hclk_en);
assign  s_rom_hclk  =  (hclk_i & s_rom_hclk_en_latch);

`endif // FUSED_AHB

rom #(ROM_ADDRW, ROM_SIZE) rom_inst0 (

// OUTPUTs
    .rom_dout_o            ( rom0_dout                                 ),

// INPUTs
    .rom_addr_i            ( rom0_addr                                 ),
    .rom_cen_i             ( rom0_cen                                  ),
    .rom_clk_i             ( rom0_clk                                  )
);


//=============================================================================
// 6)  EXECUTABLE SRAM MEMORY
//=============================================================================
//   FUSED_AHB: same fusing pattern as ROM section above.
//
`ifndef FUSED_AHB

ahb_waitstate_inserter #(HAUSER_W) ahb_waitstate_inserter_sram_x_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_sram_x_hclk                             ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( s_sram_x_hclk_en                          ),

    .number_ws_i           ( s_sram_x_number_ws_i                      ),
    .random_ws_en_i        ( s_sram_x_random_ws_en_i                   ),

// AHB INTERFACE (TO FABRIC OR DRIVER)
    .haddr_i               ( s_sram_x_haddr                            ),
    .hauser_i              ( s_sram_x_hauser                           ),
    .hprot_i               ( s_sram_x_hprot                            ),
    .hready_i              ( s_sram_x_hready                           ),
    .hsize_i               ( s_sram_x_hsize                            ),
    .htrans_i              ( s_sram_x_htrans                           ),
    .hwdata_i              ( s_sram_x_hwdata                           ),
    .hwrite_i              ( s_sram_x_hwrite                           ),
    .hsel_i                ( s_sram_x_hsel                             ),
    .hrdata_o              ( s_sram_x_hrdata                           ),
    .hreadyout_o           ( s_sram_x_hreadyout                        ),
    .hresp_o               ( s_sram_x_hresp                            ),

// AHB INTERFACE (TO AHB SUBORDINATE)
    .s_haddr_o             ( ws_s_sram_x_haddr                         ),
    .s_hauser_o            ( ws_s_sram_x_hauser                        ),
    .s_hprot_o             ( ws_s_sram_x_hprot                         ),
    .s_hready_o            ( ws_s_sram_x_hready                        ),
    .s_hsize_o             ( ws_s_sram_x_hsize                         ),
    .s_htrans_o            ( ws_s_sram_x_htrans                        ),
    .s_hwdata_o            ( ws_s_sram_x_hwdata                        ),
    .s_hwrite_o            ( ws_s_sram_x_hwrite                        ),
    .s_hsel_o              ( ws_s_sram_x_hsel                          ),
    .s_hrdata_i            ( ws_s_sram_x_hrdata                        ),
    .s_hreadyout_i         ( ws_s_sram_x_hreadyout                     ),
    .s_hresp_i             ( ws_s_sram_x_hresp                         )
 );

ahb_sram_controller #(SRAM_X_SIZE) ahb_sram_x_ctrl_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_sram_x_hclk                             ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( ws_s_sram_x_hclk_en                       ),

// AHB INTERFACE
    .haddr_i               ( ws_s_sram_x_haddr[SRAM_X_HADDRW-1:0]      ),
    .hready_i              ( ws_s_sram_x_hready                        ),
    .hsize_i               ( ws_s_sram_x_hsize                         ),
    .htrans_i              ( ws_s_sram_x_htrans                        ),
    .hwdata_i              ( ws_s_sram_x_hwdata                        ),
    .hwrite_i              ( ws_s_sram_x_hwrite                        ),
    .hsel_i                ( ws_s_sram_x_hsel                          ),
    .hrdata_o              ( ws_s_sram_x_hrdata                        ),
    .hreadyout_o           ( ws_s_sram_x_hreadyout                     ),
    .hresp_o               ( ws_s_sram_x_hresp                         ),

// SRAM INTERFACE
    .sram_dout_i           ( sram_x_dout                               ),
    .sram_addr_o           ( sram_x_addr                               ),
    .sram_cen_o            ( sram_x_cen                                ),
    .sram_clk_o            ( sram_x_clk                                ),
    .sram_din_o            ( sram_x_din                                ),
    .sram_wen_o            ( sram_x_wen                                )
 );

// Architectural clock-gate
always @(hclk_i or s_sram_x_hclk_en or ws_s_sram_x_hclk_en)
  if (~hclk_i) s_sram_x_hclk_en_latch <= (s_sram_x_hclk_en | ws_s_sram_x_hclk_en);
assign  s_sram_x_hclk  =  (hclk_i & s_sram_x_hclk_en_latch);

`endif // FUSED_AHB

sram #(SRAM_X_ADDRW, SRAM_X_SIZE) sram_x_inst (

// OUTPUTs
    .sram_dout_o           ( sram_x_dout                               ),

// INPUTs
    .sram_addr_i           ( sram_x_addr                               ),
    .sram_cen_i            ( sram_x_cen                                ),
    .sram_clk_i            ( sram_x_clk                                ),
    .sram_din_i            ( sram_x_din                                ),
    .sram_wen_i            ( sram_x_wen                                )
);


//=============================================================================
// 7)  NON-EXECUTABLE SRAM MEMORY
//=============================================================================

ahb_waitstate_inserter #(HAUSER_W) ahb_waitstate_inserter_sram_nx_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_sram_nx_hclk                            ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( s_sram_nx_hclk_en                         ),

    .number_ws_i           ( s_sram_nx_number_ws_i                     ),
    .random_ws_en_i        ( s_sram_nx_random_ws_en_i                  ),

// AHB INTERFACE (TO FABRIC OR DRIVER)
    .haddr_i               ( s_sram_nx_haddr                           ),
    .hauser_i              ( s_sram_nx_hauser                          ),
    .hprot_i               ( s_sram_nx_hprot                           ),
    .hready_i              ( s_sram_nx_hready                          ),
    .hsize_i               ( s_sram_nx_hsize                           ),
    .htrans_i              ( s_sram_nx_htrans                          ),
    .hwdata_i              ( s_sram_nx_hwdata                          ),
    .hwrite_i              ( s_sram_nx_hwrite                          ),
    .hsel_i                ( s_sram_nx_hsel                            ),
    .hrdata_o              ( s_sram_nx_hrdata                          ),
    .hreadyout_o           ( s_sram_nx_hreadyout                       ),
    .hresp_o               ( s_sram_nx_hresp                           ),

// AHB INTERFACE (TO AHB SUBORDINATE)
    .s_haddr_o             ( ws_s_sram_nx_haddr                        ),
    .s_hauser_o            ( ws_s_sram_nx_hauser                       ),
    .s_hprot_o             ( ws_s_sram_nx_hprot                        ),
    .s_hready_o            ( ws_s_sram_nx_hready                       ),
    .s_hsize_o             ( ws_s_sram_nx_hsize                        ),
    .s_htrans_o            ( ws_s_sram_nx_htrans                       ),
    .s_hwdata_o            ( ws_s_sram_nx_hwdata                       ),
    .s_hwrite_o            ( ws_s_sram_nx_hwrite                       ),
    .s_hsel_o              ( ws_s_sram_nx_hsel                         ),
    .s_hrdata_i            ( ws_s_sram_nx_hrdata                       ),
    .s_hreadyout_i         ( ws_s_sram_nx_hreadyout                    ),
    .s_hresp_i             ( ws_s_sram_nx_hresp                        )
 );

ahb_sram_controller #(SRAM_NX_SIZE) ahb_sram_nx_ctrl_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_sram_nx_hclk                            ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( ws_s_sram_nx_hclk_en                      ),

// AHB INTERFACE
    .haddr_i               ( ws_s_sram_nx_haddr[SRAM_NX_HADDRW-1:0]    ),
    .hready_i              ( ws_s_sram_nx_hready                       ),
    .hsize_i               ( ws_s_sram_nx_hsize                        ),
    .htrans_i              ( ws_s_sram_nx_htrans                       ),
    .hwdata_i              ( ws_s_sram_nx_hwdata                       ),
    .hwrite_i              ( ws_s_sram_nx_hwrite                       ),
    .hsel_i                ( ws_s_sram_nx_hsel                         ),
    .hrdata_o              ( ws_s_sram_nx_hrdata                       ),
    .hreadyout_o           ( ws_s_sram_nx_hreadyout                    ),
    .hresp_o               ( ws_s_sram_nx_hresp                        ),

// SRAM INTERFACE
    .sram_dout_i           ( sram_nx_dout                              ),
    .sram_addr_o           ( sram_nx_addr                              ),
    .sram_cen_o            ( sram_nx_cen                               ),
    .sram_clk_o            ( sram_nx_clk                               ),
    .sram_din_o            ( sram_nx_din                               ),
    .sram_wen_o            ( sram_nx_wen                               )
 );

sram #(SRAM_NX_ADDRW, SRAM_NX_SIZE) sram_nx_inst (

// OUTPUTs
    .sram_dout_o           ( sram_nx_dout                              ),

// INPUTs
    .sram_addr_i           ( sram_nx_addr                              ),
    .sram_cen_i            ( sram_nx_cen                               ),
    .sram_clk_i            ( sram_nx_clk                               ),
    .sram_din_i            ( sram_nx_din                               ),
    .sram_wen_i            ( sram_nx_wen                               )
);

// Architectural clock-gate
always @(hclk_i or s_sram_nx_hclk_en or ws_s_sram_nx_hclk_en)
  if (~hclk_i) s_sram_nx_hclk_en_latch <= (s_sram_nx_hclk_en | ws_s_sram_nx_hclk_en);
assign  s_sram_nx_hclk  =  (hclk_i & s_sram_nx_hclk_en_latch);


//=============================================================================
// 8)  AHB PERIPHERAL #0
//=============================================================================

ahb_waitstate_inserter #(HAUSER_W) ahb_waitstate_inserter_periph0_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_periph0_hclk                            ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( s_periph0_hclk_en                         ),

    .number_ws_i           ( s_periph0_number_ws_i                     ),
    .random_ws_en_i        ( s_periph0_random_ws_en_i                  ),

// AHB INTERFACE (TO FABRIC OR DRIVER)
    .haddr_i               ( s_periph0_haddr                           ),
    .hauser_i              ( s_periph0_hauser                          ),
    .hprot_i               ( s_periph0_hprot                           ),
    .hready_i              ( s_periph0_hready                          ),
    .hsize_i               ( s_periph0_hsize                           ),
    .htrans_i              ( s_periph0_htrans                          ),
    .hwdata_i              ( s_periph0_hwdata                          ),
    .hwrite_i              ( s_periph0_hwrite                          ),
    .hsel_i                ( s_periph0_hsel                            ),
    .hrdata_o              ( s_periph0_hrdata                          ),
    .hreadyout_o           ( s_periph0_hreadyout                       ),
    .hresp_o               ( s_periph0_hresp                           ),

// AHB INTERFACE (TO AHB SUBORDINATE)
    .s_haddr_o             ( ws_s_periph0_haddr                        ),
    .s_hauser_o            ( ws_s_periph0_hauser                       ),
    .s_hprot_o             ( ws_s_periph0_hprot                        ),
    .s_hready_o            ( ws_s_periph0_hready                       ),
    .s_hsize_o             ( ws_s_periph0_hsize                        ),
    .s_htrans_o            ( ws_s_periph0_htrans                       ),
    .s_hwdata_o            ( ws_s_periph0_hwdata                       ),
    .s_hwrite_o            ( ws_s_periph0_hwrite                       ),
    .s_hsel_o              ( ws_s_periph0_hsel                         ),
    .s_hrdata_i            ( ws_s_periph0_hrdata                       ),
    .s_hreadyout_i         ( ws_s_periph0_hreadyout                    ),
    .s_hresp_i             ( ws_s_periph0_hresp                        )
 );

ahb_periph_example  ahb_periph_example_inst0 (

// AHB CLOCK & RESET
    .hclk_i                ( s_periph0_hclk                            ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( ws_s_periph0_hclk_en                      ),

// AHB INTERFACE
    .haddr_i               ( ws_s_periph0_haddr[6:0]                   ),
    .hprot_i               ( ws_s_periph0_hprot                        ),
    .hready_i              ( ws_s_periph0_hready                       ),
    .hsize_i               ( ws_s_periph0_hsize                        ),
    .hsmode_i              ( ws_s_periph0_hauser[0]                    ),
    .htrans_i              ( ws_s_periph0_htrans                       ),
    .hwdata_i              ( ws_s_periph0_hwdata                       ),
    .hwrite_i              ( ws_s_periph0_hwrite                       ),
    .hsel_i                ( ws_s_periph0_hsel                         ),
    .hrdata_o              ( ws_s_periph0_hrdata                       ),
    .hreadyout_o           ( ws_s_periph0_hreadyout                    ),
    .hresp_o               ( ws_s_periph0_hresp                        ),

// REGISTERS (FOR PROBING)
    .register_00_o         ( periph0_reg_00_o                          ),
    .register_01_o         ( periph0_reg_01_o                          ),
    .register_02_o         ( periph0_reg_02_o                          ),
    .register_03_o         ( periph0_reg_03_o                          ),
    .register_04_o         ( periph0_reg_04_o                          ),
    .register_05_o         ( periph0_reg_05_o                          ),
    .register_06_o         ( periph0_reg_06_o                          ),
    .register_07_o         ( periph0_reg_07_o                          ),

    .register_08_i         ( periph0_reg_08_i                          ),
    .register_09_i         ( periph0_reg_09_i                          ),
    .register_10_i         ( periph0_reg_10_i                          ),
    .register_11_i         ( periph0_reg_11_i                          ),
    .register_12_i         ( periph0_reg_12_i                          ),
    .register_13_i         ( periph0_reg_13_i                          ),
    .register_14_i         ( periph0_reg_14_i                          ),
    .register_15_i         ( periph0_reg_15_i                          )
 );

// Architectural clock-gate
always @(hclk_i or s_periph0_hclk_en or ws_s_periph0_hclk_en)
  if (~hclk_i) s_periph0_hclk_en_latch <= (s_periph0_hclk_en | ws_s_periph0_hclk_en);
assign  s_periph0_hclk  =  (hclk_i & s_periph0_hclk_en_latch);


//=============================================================================
// 9)  AHB PERIPHERAL #1
//=============================================================================

ahb_waitstate_inserter #(HAUSER_W) ahb_waitstate_inserter_periph1_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_periph1_hclk                            ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( s_periph1_hclk_en                         ),

    .number_ws_i           ( s_periph1_number_ws_i                     ),
    .random_ws_en_i        ( s_periph1_random_ws_en_i                  ),

// AHB INTERFACE (TO FABRIC OR DRIVER)
    .haddr_i               ( s_periph1_haddr                           ),
    .hauser_i              ( s_periph1_hauser                          ),
    .hprot_i               ( s_periph1_hprot                           ),
    .hready_i              ( s_periph1_hready                          ),
    .hsize_i               ( s_periph1_hsize                           ),
    .htrans_i              ( s_periph1_htrans                          ),
    .hwdata_i              ( s_periph1_hwdata                          ),
    .hwrite_i              ( s_periph1_hwrite                          ),
    .hsel_i                ( s_periph1_hsel                            ),
    .hrdata_o              ( s_periph1_hrdata                          ),
    .hreadyout_o           ( s_periph1_hreadyout                       ),
    .hresp_o               ( s_periph1_hresp                           ),

// AHB INTERFACE (TO AHB SUBORDINATE)
    .s_haddr_o             ( ws_s_periph1_haddr                        ),
    .s_hauser_o            ( ws_s_periph1_hauser                       ),
    .s_hprot_o             ( ws_s_periph1_hprot                        ),
    .s_hready_o            ( ws_s_periph1_hready                       ),
    .s_hsize_o             ( ws_s_periph1_hsize                        ),
    .s_htrans_o            ( ws_s_periph1_htrans                       ),
    .s_hwdata_o            ( ws_s_periph1_hwdata                       ),
    .s_hwrite_o            ( ws_s_periph1_hwrite                       ),
    .s_hsel_o              ( ws_s_periph1_hsel                         ),
    .s_hrdata_i            ( ws_s_periph1_hrdata                       ),
    .s_hreadyout_i         ( ws_s_periph1_hreadyout                    ),
    .s_hresp_i             ( ws_s_periph1_hresp                        )
 );

ahb_periph_example  ahb_periph_example_inst1 (

// AHB CLOCK & RESET
    .hclk_i                ( s_periph1_hclk                            ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( ws_s_periph1_hclk_en                      ),

// AHB INTERFACE
    .haddr_i               ( ws_s_periph1_haddr[6:0]                   ),
    .hprot_i               ( ws_s_periph1_hprot                        ),
    .hready_i              ( ws_s_periph1_hready                       ),
    .hsize_i               ( ws_s_periph1_hsize                        ),
    .hsmode_i              ( ws_s_periph1_hauser[0]                    ),
    .htrans_i              ( ws_s_periph1_htrans                       ),
    .hwdata_i              ( ws_s_periph1_hwdata                       ),
    .hwrite_i              ( ws_s_periph1_hwrite                       ),
    .hsel_i                ( ws_s_periph1_hsel                         ),
    .hrdata_o              ( ws_s_periph1_hrdata                       ),
    .hreadyout_o           ( ws_s_periph1_hreadyout                    ),
    .hresp_o               ( ws_s_periph1_hresp                        ),

// REGISTERS (FOR PROBING)
    .register_00_o         ( periph1_reg_00_o                          ),
    .register_01_o         ( periph1_reg_01_o                          ),
    .register_02_o         ( periph1_reg_02_o                          ),
    .register_03_o         ( periph1_reg_03_o                          ),
    .register_04_o         ( periph1_reg_04_o                          ),
    .register_05_o         ( periph1_reg_05_o                          ),
    .register_06_o         ( periph1_reg_06_o                          ),
    .register_07_o         ( periph1_reg_07_o                          ),

    .register_08_i         ( periph1_reg_08_i                          ),
    .register_09_i         ( periph1_reg_09_i                          ),
    .register_10_i         ( periph1_reg_10_i                          ),
    .register_11_i         ( periph1_reg_11_i                          ),
    .register_12_i         ( periph1_reg_12_i                          ),
    .register_13_i         ( periph1_reg_13_i                          ),
    .register_14_i         ( periph1_reg_14_i                          ),
    .register_15_i         ( periph1_reg_15_i                          )
 );

// Architectural clock-gate
always @(hclk_i or s_periph1_hclk_en or ws_s_periph1_hclk_en)
  if (~hclk_i) s_periph1_hclk_en_latch <= (s_periph1_hclk_en | ws_s_periph1_hclk_en);
assign  s_periph1_hclk  =  (hclk_i & s_periph1_hclk_en_latch);


//=============================================================================
// 10)  AHB PERIPHERAL #2
//=============================================================================

ahb_waitstate_inserter #(HAUSER_W) ahb_waitstate_inserter_periph2_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_periph2_hclk                            ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( s_periph2_hclk_en                         ),

    .number_ws_i           ( s_periph2_number_ws_i                     ),
    .random_ws_en_i        ( s_periph2_random_ws_en_i                  ),

// AHB INTERFACE (TO FABRIC OR DRIVER)
    .haddr_i               ( s_periph2_haddr                           ),
    .hauser_i              ( s_periph2_hauser                          ),
    .hprot_i               ( s_periph2_hprot                           ),
    .hready_i              ( s_periph2_hready                          ),
    .hsize_i               ( s_periph2_hsize                           ),
    .htrans_i              ( s_periph2_htrans                          ),
    .hwdata_i              ( s_periph2_hwdata                          ),
    .hwrite_i              ( s_periph2_hwrite                          ),
    .hsel_i                ( s_periph2_hsel                            ),
    .hrdata_o              ( s_periph2_hrdata                          ),
    .hreadyout_o           ( s_periph2_hreadyout                       ),
    .hresp_o               ( s_periph2_hresp                           ),

// AHB INTERFACE (TO AHB SUBORDINATE)
    .s_haddr_o             ( ws_s_periph2_haddr                        ),
    .s_hauser_o            ( ws_s_periph2_hauser                       ),
    .s_hprot_o             ( ws_s_periph2_hprot                        ),
    .s_hready_o            ( ws_s_periph2_hready                       ),
    .s_hsize_o             ( ws_s_periph2_hsize                        ),
    .s_htrans_o            ( ws_s_periph2_htrans                       ),
    .s_hwdata_o            ( ws_s_periph2_hwdata                       ),
    .s_hwrite_o            ( ws_s_periph2_hwrite                       ),
    .s_hsel_o              ( ws_s_periph2_hsel                         ),
    .s_hrdata_i            ( ws_s_periph2_hrdata                       ),
    .s_hreadyout_i         ( ws_s_periph2_hreadyout                    ),
    .s_hresp_i             ( ws_s_periph2_hresp                        )
 );

ahb_periph_example  ahb_periph_example_inst2 (

// AHB CLOCK & RESET
    .hclk_i                ( s_periph2_hclk                            ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( ws_s_periph2_hclk_en                      ),

// AHB INTERFACE
    .haddr_i               ( ws_s_periph2_haddr[6:0]                   ),
    .hprot_i               ( ws_s_periph2_hprot                        ),
    .hready_i              ( ws_s_periph2_hready                       ),
    .hsize_i               ( ws_s_periph2_hsize                        ),
    .hsmode_i              ( ws_s_periph2_hauser[0]                    ),
    .htrans_i              ( ws_s_periph2_htrans                       ),
    .hwdata_i              ( ws_s_periph2_hwdata                       ),
    .hwrite_i              ( ws_s_periph2_hwrite                       ),
    .hsel_i                ( ws_s_periph2_hsel                         ),
    .hrdata_o              ( ws_s_periph2_hrdata                       ),
    .hreadyout_o           ( ws_s_periph2_hreadyout                    ),
    .hresp_o               ( ws_s_periph2_hresp                        ),

// REGISTERS (FOR PROBING)
    .register_00_o         ( periph2_reg_00_o                          ),
    .register_01_o         ( periph2_reg_01_o                          ),
    .register_02_o         ( periph2_reg_02_o                          ),
    .register_03_o         ( periph2_reg_03_o                          ),
    .register_04_o         ( periph2_reg_04_o                          ),
    .register_05_o         ( periph2_reg_05_o                          ),
    .register_06_o         ( periph2_reg_06_o                          ),
    .register_07_o         ( periph2_reg_07_o                          ),

    .register_08_i         ( periph2_reg_08_i                          ),
    .register_09_i         ( periph2_reg_09_i                          ),
    .register_10_i         ( periph2_reg_10_i                          ),
    .register_11_i         ( periph2_reg_11_i                          ),
    .register_12_i         ( periph2_reg_12_i                          ),
    .register_13_i         ( periph2_reg_13_i                          ),
    .register_14_i         ( periph2_reg_14_i                          ),
    .register_15_i         ( periph2_reg_15_i                          )
 );

// Architectural clock-gate
always @(hclk_i or s_periph2_hclk_en or ws_s_periph2_hclk_en)
  if (~hclk_i) s_periph2_hclk_en_latch <= (s_periph2_hclk_en | ws_s_periph2_hclk_en);
assign  s_periph2_hclk  =  (hclk_i & s_periph2_hclk_en_latch);


//=============================================================================
// 11)  AHB PLIC
//=============================================================================
// Mapped at 0xC0000000 (4 MB window) by ahb_decoder.
// NUM_HARTS=1 matches the single-hart TB.
// SU_MODE_EN follows the core's SU_MODE_EN via parameter.
// No wait-state inserter; the fabric-side signals feed the PLIC AHB port directly.

ahb_plic #(.NUM_SOURCES    ( PLIC_NUM_SRC     ),
           .NUM_HARTS      ( 1                ),
           .SU_MODE_EN     ( PLIC_SU_MODE_EN  ),
           .PRIO_BITS      ( 3                ),
           .PRIV_CHECK_EN  ( 1                )) ahb_plic_inst (

// AHB CLOCK & RESET
    .hclk_i                ( s_plic_hclk                               ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( s_plic_hclk_en                            ),

// AHB-LITE SLAVE INTERFACE
    .hsel_i                ( s_plic_hsel                               ),
    .haddr_i               ( s_plic_haddr[21:0]                        ),
    .hwrite_i              ( s_plic_hwrite                             ),
    .hsize_i               ( s_plic_hsize                              ),
    .htrans_i              ( s_plic_htrans                             ),
    .hprot_i               ( s_plic_hprot                              ),
    .hsmode_i              ( s_plic_hauser[0]                          ),
    .hready_i              ( s_plic_hready                             ),
    .hwdata_i              ( s_plic_hwdata                             ),
    .hrdata_o              ( s_plic_hrdata                             ),
    .hreadyout_o           ( s_plic_hreadyout                          ),
    .hresp_o               ( s_plic_hresp                              ),

// PER-SOURCE LEVEL-TRIGGERED INTERRUPT INPUTS
    .irq_src_i             ( plic_irq_src_i                            ),

// PER-HART INTERRUPT OUTPUTS
    .irq_m_external_o      ( plic_irq_m_external_o                     ),
    .irq_s_external_o      ( plic_irq_s_external_o                     )
);

// Architectural clock-gate
always @(hclk_i or s_plic_hclk_en)
  if (~hclk_i) s_plic_hclk_en_latch <= s_plic_hclk_en;
assign  s_plic_hclk  =  (hclk_i & s_plic_hclk_en_latch);


//=============================================================================
// 12)  AHB ACLINT
//=============================================================================
// Mapped at 0x02000000 (64 KB window) by ahb_decoder (SiFive CLINT-compatible
// base for OpenSBI / Linux). NUM_HARTS=1 matches the single-hart TB.
// SU_MODE_EN follows the core's SU_MODE_EN via the existing parameter.
// hclk_aon_i + clk_lf_i + resetn_lf_i come from the testbench top.

ahb_aclint #(.NUM_HARTS     ( 1               ),
             .SU_MODE_EN    ( PLIC_SU_MODE_EN ),
             .PRIV_CHECK_EN ( 1               )) ahb_aclint_inst (

// AHB CLOCK, RESET & WAKEUP
    .hclk_i                ( s_aclint_hclk                             ),
    .hclk_aon_i            ( hclk_aon_i                                ),
    .hresetn_i             ( hresetn_i                                 ),
    .hclk_en_o             ( s_aclint_hclk_en                          ),
    .mtimer_wake_lf_o      ( aclint_mtimer_wake_lf_o                   ),

// LOW-FREQUENCY CLOCK & RESET
    .clk_lf_i              ( clk_lf_i                                  ),
    .resetn_lf_i           ( resetn_lf_i                               ),

// AHB-LITE SLAVE INTERFACE
    .hsel_i                ( s_aclint_hsel                             ),
    .haddr_i               ( s_aclint_haddr[15:0]                      ),
    .hwrite_i              ( s_aclint_hwrite                           ),
    .hsize_i               ( s_aclint_hsize                            ),
    .htrans_i              ( s_aclint_htrans                           ),
    .hprot_i               ( s_aclint_hprot                            ),
    .hsmode_i              ( s_aclint_hauser[0]                        ),
    .hready_i              ( s_aclint_hready                           ),
    .hwdata_i              ( s_aclint_hwdata                           ),
    .hrdata_o              ( s_aclint_hrdata                           ),
    .hreadyout_o           ( s_aclint_hreadyout                        ),
    .hresp_o               ( s_aclint_hresp                            ),

// PER-HART INTERRUPTS
    .irq_m_software_o      ( aclint_irq_m_software_o                   ),
    .irq_m_timer_o         ( aclint_irq_m_timer_o                      ),
    .irq_s_software_o      ( aclint_irq_s_software_o                   ),

// ZICNTR TIME INTERFACE
    .time_req_i            ( aclint_time_req_i                         ),
    .time_gnt_o            ( aclint_time_gnt_o                         ),
    .time_val_o            ( aclint_time_val_o                         )
);

// Architectural clock-gate
always @(hclk_i or s_aclint_hclk_en)
  if (~hclk_i) s_aclint_hclk_en_latch <= s_aclint_hclk_en;
assign  s_aclint_hclk  =  (hclk_i & s_aclint_hclk_en_latch);


//=============================================================================
// 13)  GLOBAL CLOCK ENABLE
//=============================================================================
//   In FUSED_AHB mode the fused interconnect's interconnect_hclk_en already
//   covers ROM + executable SRAM activity (the controllers were absorbed),
//   so the per-controller s_rom_hclk_en / s_sram_x_hclk_en signals do not
//   exist and must be excluded from the OR.
//

`ifdef FUSED_AHB
assign  hclk_en_o       =   interconnect_hclk_en  |
                            s_sram_nx_hclk_en     |
                            ws_s_sram_nx_hclk_en  |
                            s_periph0_hclk_en     |
                            ws_s_periph0_hclk_en  |
                            s_periph1_hclk_en     |
                            ws_s_periph1_hclk_en  |
                            s_periph2_hclk_en     |
                            ws_s_periph2_hclk_en  |
                            s_plic_hclk_en        |
                            s_aclint_hclk_en      ;
`else
assign  hclk_en_o       =   interconnect_hclk_en  |
                            s_rom_hclk_en         |
                            ws_s_rom_hclk_en      |
                            s_sram_x_hclk_en      |
                            ws_s_sram_x_hclk_en   |
                            s_sram_nx_hclk_en     |
                            ws_s_sram_nx_hclk_en  |
                            s_periph0_hclk_en     |
                            ws_s_periph0_hclk_en  |
                            s_periph1_hclk_en     |
                            ws_s_periph1_hclk_en  |
                            s_periph2_hclk_en     |
                            ws_s_periph2_hclk_en  |
                            s_plic_hclk_en        |
                            s_aclint_hclk_en      ;
`endif


//=============================================================================
// 12)  LINT CLEANUP
//=============================================================================

// ROM and Executable SRAM
//   In FUSED_AHB mode the AHB-side ROM/SRAM controllers and WS inserters are
//   absorbed into ahb_interconnect_fused, so the s_rom_*, ws_s_rom_*,
//   s_sram_x_*, ws_s_sram_x_* signals have no driver and the unused-sinks
//   below would propagate X.
//
`ifndef FUSED_AHB
// ROM
wire               [2:0] s_rom_hburst_unused;
assign                   s_rom_hburst_unused          = s_rom_hburst;

wire               [3:0] s_rom_hmaster_unused;
assign                   s_rom_hmaster_unused         = s_rom_hmaster;

wire                     s_rom_hmastlock_unused;
assign                   s_rom_hmastlock_unused       = s_rom_hmastlock;

wire      [HAUSER_W-1:0] ws_s_rom_hauser_unused;
assign                   ws_s_rom_hauser_unused       = ws_s_rom_hauser;

wire               [3:0] ws_s_rom_hprot_unused;
assign                   ws_s_rom_hprot_unused        = ws_s_rom_hprot;

wire     [31:ROM_HADDRW] ws_s_rom_haddr_unused;
assign                   ws_s_rom_haddr_unused        = ws_s_rom_haddr[31:ROM_HADDRW];

// Executable SRAM
wire               [2:0] s_sram_x_hburst_unused;
assign                   s_sram_x_hburst_unused       = s_sram_x_hburst;

wire               [3:0] s_sram_x_hmaster_unused;
assign                   s_sram_x_hmaster_unused      = s_sram_x_hmaster;

wire                     s_sram_x_hmastlock_unused;
assign                   s_sram_x_hmastlock_unused    = s_sram_x_hmastlock;

wire      [HAUSER_W-1:0] ws_s_sram_x_hauser_unused;
assign                   ws_s_sram_x_hauser_unused    = ws_s_sram_x_hauser;

wire               [3:0] ws_s_sram_x_hprot_unused;
assign                   ws_s_sram_x_hprot_unused     = ws_s_sram_x_hprot;

wire  [31:SRAM_X_HADDRW] ws_s_sram_x_haddr_unused;
assign                   ws_s_sram_x_haddr_unused     = ws_s_sram_x_haddr[31:SRAM_X_HADDRW];
`else
// FUSED_AHB: absorb the now-unused WS configuration inputs.
wire              [31:0] s_rom_number_ws_unused;
assign                   s_rom_number_ws_unused       = s_rom_number_ws_i;
wire                     s_rom_random_ws_en_unused;
assign                   s_rom_random_ws_en_unused    = s_rom_random_ws_en_i;
wire              [31:0] s_sram_x_number_ws_unused;
assign                   s_sram_x_number_ws_unused    = s_sram_x_number_ws_i;
wire                     s_sram_x_random_ws_en_unused;
assign                   s_sram_x_random_ws_en_unused = s_sram_x_random_ws_en_i;
`endif

// Non-executable SRAM
wire               [2:0] s_sram_nx_hburst_unused;
assign                   s_sram_nx_hburst_unused      = s_sram_nx_hburst;

wire               [3:0] s_sram_nx_hmaster_unused;
assign                   s_sram_nx_hmaster_unused     = s_sram_nx_hmaster;

wire                     s_sram_nx_hmastlock_unused;
assign                   s_sram_nx_hmastlock_unused   = s_sram_nx_hmastlock;

wire      [HAUSER_W-1:0] ws_s_sram_nx_hauser_unused;
assign                   ws_s_sram_nx_hauser_unused   = ws_s_sram_nx_hauser;

wire               [3:0] ws_s_sram_nx_hprot_unused;
assign                   ws_s_sram_nx_hprot_unused    = ws_s_sram_nx_hprot;

wire [31:SRAM_NX_HADDRW] ws_s_sram_nx_haddr_unused;
assign                   ws_s_sram_nx_haddr_unused    = ws_s_sram_nx_haddr[31:SRAM_NX_HADDRW];

// Periph0
wire               [2:0] s_periph0_hburst_unused;
assign                   s_periph0_hburst_unused      = s_periph0_hburst;

wire               [3:0] s_periph0_hmaster_unused;
assign                   s_periph0_hmaster_unused     = s_periph0_hmaster;

wire                     s_periph0_hmastlock_unused;
assign                   s_periph0_hmastlock_unused   = s_periph0_hmastlock;

wire              [31:6] ws_s_periph0_haddr_unused;
assign                   ws_s_periph0_haddr_unused    = ws_s_periph0_haddr[31:6];

// Periph1
wire               [2:0] s_periph1_hburst_unused;
assign                   s_periph1_hburst_unused      = s_periph1_hburst;

wire               [3:0] s_periph1_hmaster_unused;
assign                   s_periph1_hmaster_unused     = s_periph1_hmaster;

wire                     s_periph1_hmastlock_unused;
assign                   s_periph1_hmastlock_unused   = s_periph1_hmastlock;

wire              [31:6] ws_s_periph1_haddr_unused;
assign                   ws_s_periph1_haddr_unused    = ws_s_periph1_haddr[31:6];

// Periph2
wire               [2:0] s_periph2_hburst_unused;
assign                   s_periph2_hburst_unused      = s_periph2_hburst;

wire               [3:0] s_periph2_hmaster_unused;
assign                   s_periph2_hmaster_unused     = s_periph2_hmaster;

wire                     s_periph2_hmastlock_unused;
assign                   s_periph2_hmastlock_unused   = s_periph2_hmastlock;

wire              [31:6] ws_s_periph2_haddr_unused;
assign                   ws_s_periph2_haddr_unused    = ws_s_periph2_haddr[31:6];

// X Decoder
wire               [6:2] s_x_decoder_1hot6_2_unused;
assign                   s_x_decoder_1hot6_2_unused   = s_x_decoder_1hot[6:2];

// PLIC
//   The PLIC ignores AHB hburst/hmaster/hmastlock (it is an AHB-Lite slave
//   that handles only NONSEQ/SEQ word accesses). Sink them. The PLIC also
//   only consumes haddr[21:0]; bits [31:22] are address-decoded upstream by
//   ahb_decoder and are unused inside the slave.
wire               [2:0] s_plic_hburst_unused;
assign                   s_plic_hburst_unused         = s_plic_hburst;

wire               [3:0] s_plic_hmaster_unused;
assign                   s_plic_hmaster_unused        = s_plic_hmaster;

wire                     s_plic_hmastlock_unused;
assign                   s_plic_hmastlock_unused      = s_plic_hmastlock;

wire              [31:22] s_plic_haddr_unused;
assign                    s_plic_haddr_unused         = s_plic_haddr[31:22];


endmodule

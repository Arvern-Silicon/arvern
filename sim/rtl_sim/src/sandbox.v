//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      sandbox
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: Sandbox playground for ad-hoc experimentation (no automated check; intended for interactive use).
//----------------------------------------------------------------------------

integer ii;
integer jj;
integer kk;

initial
   begin
      @(posedge free_clk);
      s_rom_number_ws        =  0;
      s_rom_random_ws_en     =  0;

      s_periph0_number_ws    =  0;
      s_periph0_random_ws_en =  0;

      s_periph1_number_ws    =  0;
      s_periph1_random_ws_en =  0;

      @(posedge hresetn);

      // Reset the peripherals
      @(negedge free_clk);
      force   ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i = 1'b0;
      force   ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i = 1'b0;
      @(negedge free_clk);
      release ahb_bus_system_inst.ahb_periph_example_inst0.hresetn_i;
      release ahb_bus_system_inst.ahb_periph_example_inst1.hresetn_i;

      $display(" ====================================================================");
      $display("|                           SANDBOX TRIALS                           |");
      $display(" ====================================================================");
      repeat(3) @(posedge free_clk);
      $display("");

      //  | Hex            | Nickname / Meaning                          |
      //  |----------------+---------------------------------------------|
      //  |  32'hDEADBEEF  | Dead beef    — classic debug filler         |
      //  |  32'hBAADF00D  | Bad food     — uninitialized heap (Windows) |
      //  |  32'hDEADC0DE  | Dead code    — unreachable section          |
      //  |  32'hFEEDFACE  | Feed face    — Mach-O magic (macOS)         |
      //  |  32'hCAFEBABE  | Cafe babe    — Java class file header       |
      //  |  32'hFEE1DEAD  | Feel dead    — poetic crash message         |
      //  |  32'h0BADC0DE  | Oh bad code  — punny fail marker            |
      //  |  32'h8BADF00D  | Ate bad food — iOS crash signal             |
      //  |  32'hBADC0FFE  | Bad coffee   — emergency required           |
      //  |  32'hDEAD10CC  | Dead lock    — for threading issues         |
      //  |  32'hABADBABE  | A bad babe   — fun stack pattern            |
      //  |  32'hFACEFEED  | Face feed    — weird but catchy             |
      //  |  32'hB105F00D  | BIOS food    — nerd pun                     |

      // Initialize peripheral #1
      periph1_reg_08_in = 32'h8BADF00D ;
      periph1_reg_09_in = 32'hFEE1DEAD ;
      periph1_reg_10_in = 32'h0BADC0DE ;
      periph1_reg_11_in = 32'hBADC0FFE ;
      periph1_reg_12_in = 32'hDEAD10CC ;
      periph1_reg_13_in = 32'hABADBABE ;
      periph1_reg_14_in = 32'hB105F00D ;
      periph1_reg_15_in = 32'hDEADC0DE ;


      //---------------------------------------------------------------
      //------------------ END OF TEST --------------------------------
      //---------------------------------------------------------------
      repeat(50) @(posedge free_clk);
      $display("");
      $display("");
      stimulus_done = 1;
   end

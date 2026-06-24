//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    check_tasks
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : check_tasks.v
// Module Description : Generic verification tasks used by the testbench (register / memory / counter checks).
//----------------------------------------------------------------------------

task check_mem_value;

   input integer address;
   input integer expected_value;
     
   reg [511:0] formatted_string;
   integer i;
   begin
     #1;
     if (ahb_bus_system_inst.sram_x_inst.mem[address] !== expected_value) begin
       $display("ERROR: Memory check   -- address: 0x%h -- read: 0x%h / expected: 0x%h %t ns", address, ahb_bus_system_inst.sram_x_inst.mem[address], expected_value, $time); 
       error = error+1;
     end else begin
       $display("PASS:  Memory check   -- address: 0x%h -- value: 0x%h %t ns", address, ahb_bus_system_inst.sram_x_inst.mem[address], $time);
     end
   end
endtask

task check_rom_value;
     input integer address;
     input integer expected_value;
       
     reg [511:0] formatted_string;
     integer i;
     begin
       #1;
       if (ahb_bus_system_inst.rom_inst0.mem[address] !== expected_value) begin
         $display("ERROR: ROM check   -- address: 0x%h -- read: 0x%h / expected: 0x%h %t ns", address, ahb_bus_system_inst.rom_inst0.mem[address], expected_value, $time); 
         error = error+1;
       end else begin
         $display("PASS:  ROM check   -- address: 0x%h -- value: 0x%h %t ns", address, ahb_bus_system_inst.rom_inst0.mem[address], $time);
       end
     end
endtask

task check_periph_reg_value;
   input integer periph_number;
   input integer reg_number;
   input integer expected_value;
     
   reg [511:0] formatted_string;
   reg  [31:0] selected_reg;
   begin
     #1;
     if (periph_number == 0) begin
         case (reg_number)
            0: selected_reg = periph0_reg_00_out;
            1: selected_reg = periph0_reg_01_out;
            2: selected_reg = periph0_reg_02_out;
            3: selected_reg = periph0_reg_03_out;
            4: selected_reg = periph0_reg_04_out;
            5: selected_reg = periph0_reg_05_out;
            6: selected_reg = periph0_reg_06_out;
            7: selected_reg = periph0_reg_07_out;
            8: selected_reg = periph0_reg_08_in ;
            9: selected_reg = periph0_reg_09_in ;
           10: selected_reg = periph0_reg_10_in ;
           11: selected_reg = periph0_reg_11_in ;
           12: selected_reg = periph0_reg_12_in ;
           13: selected_reg = periph0_reg_13_in ;
           14: selected_reg = periph0_reg_14_in ;
           15: selected_reg = periph0_reg_15_in ; 
           default: begin
               selected_reg = 32'h00000000;
           end
         endcase
     end else if (periph_number == 1) begin
         case (reg_number)
            0: selected_reg = periph1_reg_00_out;
            1: selected_reg = periph1_reg_01_out;
            2: selected_reg = periph1_reg_02_out;
            3: selected_reg = periph1_reg_03_out;
            4: selected_reg = periph1_reg_04_out;
            5: selected_reg = periph1_reg_05_out;
            6: selected_reg = periph1_reg_06_out;
            7: selected_reg = periph1_reg_07_out;
            8: selected_reg = periph1_reg_08_in ;
            9: selected_reg = periph1_reg_09_in ;
           10: selected_reg = periph1_reg_10_in ;
           11: selected_reg = periph1_reg_11_in ;
           12: selected_reg = periph1_reg_12_in ;
           13: selected_reg = periph1_reg_13_in ;
           14: selected_reg = periph1_reg_14_in ;
           15: selected_reg = periph1_reg_15_in ; 
           default: begin
               selected_reg = 32'h00000000;
           end
         endcase
     end else if (periph_number == 2) begin
         case (reg_number)
            0: selected_reg = periph2_reg_00_out;
            1: selected_reg = periph2_reg_01_out;
            2: selected_reg = periph2_reg_02_out;
            3: selected_reg = periph2_reg_03_out;
            4: selected_reg = periph2_reg_04_out;
            5: selected_reg = periph2_reg_05_out;
            6: selected_reg = periph2_reg_06_out;
            7: selected_reg = periph2_reg_07_out;
            8: selected_reg = periph2_reg_08_in ;
            9: selected_reg = periph2_reg_09_in ;
           10: selected_reg = periph2_reg_10_in ;
           11: selected_reg = periph2_reg_11_in ;
           12: selected_reg = periph2_reg_12_in ;
           13: selected_reg = periph2_reg_13_in ;
           14: selected_reg = periph2_reg_14_in ;
           15: selected_reg = periph2_reg_15_in ; 
           default: begin
               selected_reg = 32'h00000000;
           end
         endcase
     end

     if (selected_reg !== expected_value) begin
       $display("ERROR: Periph check   -- periph: %d -- reg_number: %d -- read: 0x%h / expected: 0x%h %t ns", periph_number, reg_number, selected_reg, expected_value, $time); 
       error = error+1;
     end else begin
       $display("PASS:  Periph check   -- periph: %d -- reg_number: %d -- value: 0x%h %t ns", periph_number, reg_number, selected_reg, $time);
     end
   end
endtask

task set_periph_regin_value;
   input integer periph_number;
   input integer regin_number;
   input integer value;

   begin
     #1;
     if (periph_number == 0) begin
         case (regin_number)
            8: periph0_reg_08_in = value;
            9: periph0_reg_09_in = value;
           10: periph0_reg_10_in = value;
           11: periph0_reg_11_in = value;
           12: periph0_reg_12_in = value;
           13: periph0_reg_13_in = value;
           14: periph0_reg_14_in = value;
           15: periph0_reg_15_in = value; 
           default: begin
           end
         endcase
     end else if (periph_number == 1) begin
         case (regin_number)
            8: periph1_reg_08_in = value;
            9: periph1_reg_09_in = value;
           10: periph1_reg_10_in = value;
           11: periph1_reg_11_in = value;
           12: periph1_reg_12_in = value;
           13: periph1_reg_13_in = value;
           14: periph1_reg_14_in = value;
           15: periph1_reg_15_in = value; 
           default: begin
           end
         endcase
     end else if (periph_number == 2) begin
         case (regin_number)
            8: periph2_reg_08_in = value;
            9: periph2_reg_09_in = value;
           10: periph2_reg_10_in = value;
           11: periph2_reg_11_in = value;
           12: periph2_reg_12_in = value;
           13: periph2_reg_13_in = value;
           14: periph2_reg_14_in = value;
           15: periph2_reg_15_in = value; 
           default: begin
           end
         endcase
     end
   end
endtask


task check_cpu_reg;
   input integer reg_number;
   input integer expected_value;

   reg    [31:0] selected_reg;
   reg [7:0] c1, c2;
   integer digit1, digit2;

   begin
     `ifdef RANDOM_IRQ
     // Wait until not inside a trap handler before reading registers.
     // MIE=1 means we are back in normal code (handler has MRETed).
     // After MIE=1, also wait for any pending load writeback to drain.
     // (MRET can complete before a pending handler load due to no data
     //  dependency, especially with random SRAM wait states.)
     while (!`ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mstatus_mie ||
             `ARV_CPU_INST.arv_load_store_inst.wb_load_busy_o)
       @(negedge `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.hclk_i);
     `endif
     #1;
     case (reg_number)
        0: selected_reg = probes_cpu.x00;
        1: selected_reg = probes_cpu.x01;
        2: selected_reg = probes_cpu.x02;
        3: selected_reg = probes_cpu.x03;
        4: selected_reg = probes_cpu.x04;
        5: selected_reg = probes_cpu.x05;
        6: selected_reg = probes_cpu.x06;
        7: selected_reg = probes_cpu.x07;
        8: selected_reg = probes_cpu.x08;
        9: selected_reg = probes_cpu.x09;
       10: selected_reg = probes_cpu.x10;
       11: selected_reg = probes_cpu.x11;
       12: selected_reg = probes_cpu.x12;
       13: selected_reg = probes_cpu.x13;
       14: selected_reg = probes_cpu.x14;
       15: selected_reg = probes_cpu.x15; 
       16: selected_reg = probes_cpu.x16; 
       17: selected_reg = probes_cpu.x17; 
       18: selected_reg = probes_cpu.x18; 
       19: selected_reg = probes_cpu.x19; 
       20: selected_reg = probes_cpu.x20;
       21: selected_reg = probes_cpu.x21;
       22: selected_reg = probes_cpu.x22;
       23: selected_reg = probes_cpu.x23;
       24: selected_reg = probes_cpu.x24;
       25: selected_reg = probes_cpu.x25; 
       26: selected_reg = probes_cpu.x26; 
       27: selected_reg = probes_cpu.x27; 
       28: selected_reg = probes_cpu.x28; 
       29: selected_reg = probes_cpu.x29; 
       30: selected_reg = probes_cpu.x30;
       31: selected_reg = probes_cpu.x31;
       default: begin
           selected_reg = 32'h00000000;
       end
     endcase

     if (reg_number < 10) begin
       // One digit → left-align by adding a space after
       digit1 = "0" + reg_number;
       c1 = digit1[7:0];
       c2 = " ";
     end else begin
       // Two digits → split into characters
       digit1 = "0" + (reg_number / 10);
       digit2 = "0" + (reg_number % 10);
       c1 = digit1[7:0];
       c2 = digit2[7:0];
     end

     if (selected_reg !== expected_value) begin
       $display("ERROR: CPU Register check -- x%s%s -- read: 0x%h / expected: 0x%h %t ns", c1, c2, selected_reg, expected_value, $time); 
       error = error+1;
     end else begin
       $display("PASS:  CPU Register check -- x%s%s -- value: 0x%h %t ns", c1, c2, selected_reg, $time);
     end
   end
endtask

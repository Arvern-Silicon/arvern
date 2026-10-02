//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Test:      debug_trigger_multi_bkpt
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// Description: several mcontrol6 triggers firing together, and trigger index
//   >= 1 firing alone, with action=0 (breakpoint exception)
//   Debug 1.0 5.3: "When multiple triggers in the same priority fire at once,
//   hit (if implemented) is set for all of them." mcontrol6.hit0 "0 (false):
//   The trigger did not fire."
//   Per phase: exactly one breakpoint exception (mcause 3, mepc = matched
//   instruction), and the tdata1.hit0 pattern recorded by the handler:
//     P1 execute, trigger 1 alone     -> hit0 = {1 on trigger 1}
//     P2 load,    trigger 1 alone     -> hit0 = {1 on trigger 1}, mtval = DATA
//     P3 execute, all triggers        -> hit0 = all ones
//     P4 load,    all triggers        -> hit0 = all ones, mtval = DATA
//     P5 execute t0 + load t1, one lw -> hit0 = {1 on trigger 0} (Table 13:
//        the execute-address breakpoint is taken before the load executes)
//----------------------------------------------------------------------------

integer ii, jj, kk, ahb_master, allow_peripheral_accesses;

`define SPAD(byte_off)  ((byte_off)/4)

localparam [31:0] DATA = 32'h80000800;

reg [31:0] w;
reg [7:0]  hit_mask, all_mask;
integer    t;

task chk_phase;
   input [8*4:1] tag;
   input [31:0]  off;
   input [7:0]   exp_hit;
   input         is_load;
   begin
      w = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'h0C)];
      if (w !== 32'd1) begin
         $display("ERROR: %0s: %0d breakpoint exception(s) taken (expected exactly 1) %t ns", tag, w, $time);
         error = error + 1;
      end
      w = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off)];
      if (w !== 32'd3) begin
         $display("ERROR: %0s: mcause = %h (expected 3) %t ns", tag, w, $time);
         error = error + 1;
      end
      w = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'h04)];
      if (w !== ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'h30)]) begin
         $display("ERROR: %0s: mepc = %h (expected %h) %t ns", tag, w, ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'h30)], $time);
         error = error + 1;
      end
      if (is_load) begin
         w = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'h08)];
         if (w !== DATA) begin
            $display("ERROR: %0s: mtval = %h (expected data address %h) %t ns", tag, w, DATA, $time);
            error = error + 1;
         end
      end
      hit_mask = 8'h00;
      for (t = 0; t < DM_TRIGGER_NR; t = t + 1) begin
         w = ahb_bus_system_inst.sram_x_inst.mem[`SPAD(off + 32'h10 + 4*t)];
         hit_mask[t] = w[22];
         $display("       %0s: trigger %0d tdata1 = %h (hit0 = %b)", tag, t, w, w[22]);
      end
      if (hit_mask !== exp_hit) begin
         $display("ERROR: %0s: hit0 per trigger = %b (expected %b) %t ns", tag, hit_mask, exp_hit, $time);
         error = error + 1;
      end else
         $display("PASS:  %0s: one breakpoint, hit0 per trigger = %b %t ns", tag, hit_mask, $time);
   end
endtask

initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    error_on_exception = 0;

    wait (probes_cpu.x31 === 32'h11111111);
    $display("");
    $display(" ======================================================");
    $display("|  TRIGGERS: multiple firing / index>=1, action=0      |");
    $display(" ======================================================");

    wait (probes_cpu.x31 === 32'hdeadbeef);
    repeat(40) @(posedge free_clk);

    all_mask = 8'h00;
    for (t = 0; t < DM_TRIGGER_NR; t = t + 1) all_mask[t] = 1'b1;

    chk_phase("P1", 32'h000, 8'b0000_0010, 1'b0);
    chk_phase("P2", 32'h040, 8'b0000_0010, 1'b1);
    chk_phase("P3", 32'h080, all_mask,     1'b0);
    chk_phase("P4", 32'h0C0, all_mask,     1'b1);
    chk_phase("P5", 32'h100, 8'b0000_0001, 1'b0);
    check_mem_value(`SPAD(32'h200), 32'd5);             // total breakpoint exceptions

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end

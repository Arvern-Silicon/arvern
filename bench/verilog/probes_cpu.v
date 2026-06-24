//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    probes_cpu
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : probes_cpu.v
// Module Description : Hierarchical probes into the arvern core internal state (register file, PC, CSRs).
//----------------------------------------------------------------------------

`ifndef ARV_CPU_INST
  `define ARV_CPU_INST dut
`endif

module  probes_cpu;

    // openRV31I PC
    wire [31:0] pc       = `ARV_CPU_INST.arv_decode_inst.id_pc_i;
    wire [31:0] inst_bin = `ARV_CPU_INST.arv_decode_inst.id_instruction_i;

    // openRV31I register probes
    wire [31:0] x00      = `ARV_CPU_INST.arv_int_registers_inst.reg_x00_zero_read;
    wire [31:0] x01      = `ARV_CPU_INST.arv_int_registers_inst.reg_x01_ra_read;
    wire [31:0] x02      = `ARV_CPU_INST.arv_int_registers_inst.reg_x02_sp_read;
    wire [31:0] x03      = `ARV_CPU_INST.arv_int_registers_inst.reg_x03_gp_read;
    wire [31:0] x04      = `ARV_CPU_INST.arv_int_registers_inst.reg_x04_tp_read;
    wire [31:0] x05      = `ARV_CPU_INST.arv_int_registers_inst.reg_x05_t0_read;
    wire [31:0] x06      = `ARV_CPU_INST.arv_int_registers_inst.reg_x06_t1_read;
    wire [31:0] x07      = `ARV_CPU_INST.arv_int_registers_inst.reg_x07_t2_read;
    wire [31:0] x08      = `ARV_CPU_INST.arv_int_registers_inst.reg_x08_s0_read;
    wire [31:0] x09      = `ARV_CPU_INST.arv_int_registers_inst.reg_x09_s1_read;
    wire [31:0] x10      = `ARV_CPU_INST.arv_int_registers_inst.reg_x10_a0_read;
    wire [31:0] x11      = `ARV_CPU_INST.arv_int_registers_inst.reg_x11_a1_read;
    wire [31:0] x12      = `ARV_CPU_INST.arv_int_registers_inst.reg_x12_a2_read;
    wire [31:0] x13      = `ARV_CPU_INST.arv_int_registers_inst.reg_x13_a3_read;
    wire [31:0] x14      = `ARV_CPU_INST.arv_int_registers_inst.reg_x14_a4_read;
    wire [31:0] x15      = `ARV_CPU_INST.arv_int_registers_inst.reg_x15_a5_read;
    wire [31:0] x16      = `ARV_CPU_INST.arv_int_registers_inst.reg_x16_a6_read;
    wire [31:0] x17      = `ARV_CPU_INST.arv_int_registers_inst.reg_x17_a7_read;
    wire [31:0] x18      = `ARV_CPU_INST.arv_int_registers_inst.reg_x18_s2_read;
    wire [31:0] x19      = `ARV_CPU_INST.arv_int_registers_inst.reg_x19_s3_read;
    wire [31:0] x20      = `ARV_CPU_INST.arv_int_registers_inst.reg_x20_s4_read;
    wire [31:0] x21      = `ARV_CPU_INST.arv_int_registers_inst.reg_x21_s5_read;
    wire [31:0] x22      = `ARV_CPU_INST.arv_int_registers_inst.reg_x22_s6_read;
    wire [31:0] x23      = `ARV_CPU_INST.arv_int_registers_inst.reg_x23_s7_read;
    wire [31:0] x24      = `ARV_CPU_INST.arv_int_registers_inst.reg_x24_s8_read;
    wire [31:0] x25      = `ARV_CPU_INST.arv_int_registers_inst.reg_x25_s9_read;
    wire [31:0] x26      = `ARV_CPU_INST.arv_int_registers_inst.reg_x26_s10_read;
    wire [31:0] x27      = `ARV_CPU_INST.arv_int_registers_inst.reg_x27_s11_read;
    wire [31:0] x28      = `ARV_CPU_INST.arv_int_registers_inst.reg_x28_t3_read;
    wire [31:0] x29      = `ARV_CPU_INST.arv_int_registers_inst.reg_x29_t4_read;
    wire [31:0] x30      = `ARV_CPU_INST.arv_int_registers_inst.reg_x30_t5_read;
    wire [31:0] x31      = `ARV_CPU_INST.arv_int_registers_inst.reg_x31_t6_read;
endmodule

module  probes_cpu_alt;

    // openRV31I register probes (with alternate names)
    wire [31:0] x00_zero = `ARV_CPU_INST.arv_int_registers_inst.reg_x00_zero_read;
    wire [31:0] x01_ra   = `ARV_CPU_INST.arv_int_registers_inst.reg_x01_ra_read;
    wire [31:0] x02_sp   = `ARV_CPU_INST.arv_int_registers_inst.reg_x02_sp_read;
    wire [31:0] x03_gp   = `ARV_CPU_INST.arv_int_registers_inst.reg_x03_gp_read;
    wire [31:0] x04_tp   = `ARV_CPU_INST.arv_int_registers_inst.reg_x04_tp_read;
    wire [31:0] x05_t0   = `ARV_CPU_INST.arv_int_registers_inst.reg_x05_t0_read;
    wire [31:0] x06_t1   = `ARV_CPU_INST.arv_int_registers_inst.reg_x06_t1_read;
    wire [31:0] x07_t2   = `ARV_CPU_INST.arv_int_registers_inst.reg_x07_t2_read;
    wire [31:0] x08_s0   = `ARV_CPU_INST.arv_int_registers_inst.reg_x08_s0_read;
    wire [31:0] x09_s1   = `ARV_CPU_INST.arv_int_registers_inst.reg_x09_s1_read;
    wire [31:0] x10_a0   = `ARV_CPU_INST.arv_int_registers_inst.reg_x10_a0_read;
    wire [31:0] x11_a1   = `ARV_CPU_INST.arv_int_registers_inst.reg_x11_a1_read;
    wire [31:0] x12_a2   = `ARV_CPU_INST.arv_int_registers_inst.reg_x12_a2_read;
    wire [31:0] x13_a3   = `ARV_CPU_INST.arv_int_registers_inst.reg_x13_a3_read;
    wire [31:0] x14_a4   = `ARV_CPU_INST.arv_int_registers_inst.reg_x14_a4_read;
    wire [31:0] x15_a5   = `ARV_CPU_INST.arv_int_registers_inst.reg_x15_a5_read;
    wire [31:0] x16_a6   = `ARV_CPU_INST.arv_int_registers_inst.reg_x16_a6_read;
    wire [31:0] x17_a7   = `ARV_CPU_INST.arv_int_registers_inst.reg_x17_a7_read;
    wire [31:0] x18_s2   = `ARV_CPU_INST.arv_int_registers_inst.reg_x18_s2_read;
    wire [31:0] x19_s3   = `ARV_CPU_INST.arv_int_registers_inst.reg_x19_s3_read;
    wire [31:0] x20_s4   = `ARV_CPU_INST.arv_int_registers_inst.reg_x20_s4_read;
    wire [31:0] x21_s5   = `ARV_CPU_INST.arv_int_registers_inst.reg_x21_s5_read;
    wire [31:0] x22_s6   = `ARV_CPU_INST.arv_int_registers_inst.reg_x22_s6_read;
    wire [31:0] x23_s7   = `ARV_CPU_INST.arv_int_registers_inst.reg_x23_s7_read;
    wire [31:0] x24_s8   = `ARV_CPU_INST.arv_int_registers_inst.reg_x24_s8_read;
    wire [31:0] x25_s9   = `ARV_CPU_INST.arv_int_registers_inst.reg_x25_s9_read;
    wire [31:0] x26_s10  = `ARV_CPU_INST.arv_int_registers_inst.reg_x26_s10_read;
    wire [31:0] x27_s11  = `ARV_CPU_INST.arv_int_registers_inst.reg_x27_s11_read;
    wire [31:0] x28_t3   = `ARV_CPU_INST.arv_int_registers_inst.reg_x28_t3_read;
    wire [31:0] x29_t4   = `ARV_CPU_INST.arv_int_registers_inst.reg_x29_t4_read;
    wire [31:0] x30_t5   = `ARV_CPU_INST.arv_int_registers_inst.reg_x30_t5_read;
    wire [31:0] x31_t6   = `ARV_CPU_INST.arv_int_registers_inst.reg_x31_t6_read;

endmodule

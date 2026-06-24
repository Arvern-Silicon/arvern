//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          File:      submit.f  (arvern CPU testbench)
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
//----------------------------------------------------------------------------
// Paths are relative to THIS submit file's directory (Option-2 portable
// form).  Cross-IP `-f` references reach the portable filelists of each
// arvern-ips IP, which in turn use file-relative paths internally; the
// sim launcher's flatten step (sim/rtl_sim/bin/flatten_filelist.py) walks
// the whole tree and emits absolute paths before invoking the simulator.
//----------------------------------------------------------------------------

//=============================================================================
// Testbench files
//=============================================================================

+incdir+.
ahb_bus_system.v
ahb_arbiter.v
ahb_decoder.v
ahb_waitstate_inserter.v
osc.v
rom.v
sram.v
probes_cpu.v
probes_mem.v
probes_instructions.v
monitor_exception.v
instruction_pc_checker.v
ahb_protocol_checker.v
tb_arvern.v


//=============================================================================
// Run-dir-local generated files
//=============================================================================
// `./`-prefixed lines are preserved verbatim by the flatten preprocessor
// (= simulator-cwd-relative).  `probes_variables.v` is generated into the
// per-run WORK directory at sim-launch time by runsim.py.

+incdir+./
./probes_variables.v


//=============================================================================
// arvern-ips dependencies (each uses portable file-relative paths)
//=============================================================================

-f ../../../arvern-ips/ahb_rom_controller/rtl/verilog/filelist.f
-f ../../../arvern-ips/ahb_sram_controller/rtl/verilog/filelist.f
-f ../../../arvern-ips/ahb_periph_example/rtl/verilog/filelist.f
-f ../../../arvern-ips/ahb_interconnect/rtl/verilog/filelist.f
-f ../../../arvern-ips/arv_custom_csr/rtl/verilog/filelist.f
-f ../../../arvern-ips/ahb_plic/rtl/verilog/filelist.f
-f ../../../arvern-ips/ahb_aclint/rtl/verilog/filelist.f


//=============================================================================
// arvern CPU
//=============================================================================

-f ../../rtl/verilog/filelist.f

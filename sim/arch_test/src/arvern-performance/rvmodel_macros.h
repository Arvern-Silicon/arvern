# rvmodel_macros.h
# RVMODEL macro definitions for the aRVern core (tb_arvern SoC)
# SPDX-License-Identifier: BSD-3-Clause

#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

// Sm_mcsr writes all-1s / all-0s to every M-mode CSR and records one trap
// signature entry per trap taken. The framework default of 15000 entries
// (tests/env/check_defines.h) overflows on this config. rvmodel_macros.h is
// included before check_defines.h (riscv_arch_test.h:11 vs :15), so this is the
// supported place to raise it.
#define TRAP_SIGUPD_COUNT 40000

#define RVMODEL_DATA_SECTION

#define STANDARD_SM_SUPPORTED

##### STARTUP #####

// The image is preloaded straight into SRAM_X by the testbench stimulus and the
// reset vector points at TEST_BASE, so there is no image to bring up.
//
// But Smrnmi IS unconditional since v0.1, and mnstatus.NMIE resets to 0. Per the
// Smrnmi spec "when NMIE=0, all interrupts are disabled" -- that includes MTI/MSI/MEI,
// not just RNMI. Upstream arch-test firmware targets cores without Smrnmi and never
// sets NMIE, so without this every Interrupts* test would see its interrupt masked
// forever. Boot code on any Smrnmi part must do this.
#define RVMODEL_BOOT \
  csrsi 0x744, 8   ;

// Default RVTEST_BOOT_TO_MMODE is correct -- arvern resets into M-mode.
//#define RVMODEL_BOOT_TO_MMODE

// RVMODEL_ACCESS_FAULT_ADDRESS is deliberately NOT defined.
//
// This configuration builds PMP, so causes 5 and 7 DO have an in-core source -- but that
// does not make this macro definable. PMP resets with every pmpcfg at zero (A=OFF), so
// nothing matches and an M-mode access to any address is permitted. The tests that use
// this macro do not program PMP, so no address they can name produces a PMP fault.
//
// What they would hit instead is a data-bus error, which aRVern reports asynchronously as a
// resumable NMI (mncause=0x80000003), not as a synchronous mcause=5/7. Such a test takes an
// RNMI to mnepc rather than an exception to mtvec, and its signature would not match the
// reference model.
//
// Leaving it undefined makes ACT skip those tests rather than mis-signature them. Defining
// it would require a target that faults on a bus access, which is a platform property, not
// something PMP changed.
// NOTE: this also skips cp_instr_access_fault (a `jalr` to the same address),
// which aRVern still handles correctly as a synchronous mcause=1 -- one #ifdef
// guards both the instruction and data cases, and the test bodies are
// certification vectors that must not be patched. Accepted coverage loss; see doc/spec_compliance_notes.md.

##### TERMINATION #####

// AHB PERIPH #0 at 0x10040000. Register 0 is driven out of the peripheral as
// periph0_reg_00_out, which the ACT stimulus watches to end the simulation.
#define RVMODEL_HALT_PASS  \
  li x1, 123456789        ;\
  li t0, 0x10040000       ;\
  write_halt_pass:        ;\
    sw x1, 0(t0)          ;\
    sw x0, 4(t0)          ;\
  self_loop_pass:         ;\
    j self_loop_pass      ;\

#define RVMODEL_HALT_FAIL \
  li x1, 1                ;\
  li t0, 0x10040000       ;\
  write_halt_fail:        ;\
    sw x1, 0(t0)          ;\
    sw x0, 4(t0)          ;\
  self_loop_fail:         ;\
    j self_loop_fail      ;\

##### IO #####

//#define RVMODEL_IO_INIT(_R1, _R2, _R3)

// Byte-at-a-time to peripheral #0 register 1; the stimulus renders it.
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
1:                           ;                        \
  lbu  _R1, 0(_STR_PTR)      ;                        \
  beqz _R1, 3f               ;                        \
2:                           ;                        \
  li   _R2, 0x10040004       ;                        \
  sw   _R1, 0(_R2)           ;                        \
  addi _STR_PTR, _STR_PTR, 1 ;                        \
  j 1b                       ;                        \
3:

##### MTVEC Alignment #####

##### Interrupt Latency #####

#define RVMODEL_INTERRUPT_LATENCY 10

##### Machine Timer #####

#define RVMODEL_MAX_CYCLES_PER_TIMER_TICK 2

// Raised from 100 (2026-09-09). This scales BOTH the arming delay
// (SOON_DELAY*2 ticks) and the U-mode idle spin (SOON_DELAY*MAX_CYCLES*2 cycles),
// keeping them in proportion. 100 left the spin too short once undefining
// RVMODEL_ACCESS_FAULT_ADDRESS shortened the instruction stream, so InterruptsS-00's
// armed timer landed after U-mode had been left. MAX_CYCLES_PER_TIMER_TICK cannot
// fix that: aclint_model already ticks once per cycle, its fastest rate.
#define RVMODEL_TIMER_INT_SOON_DELAY 200

// ACLINT MTIMER at the SiFive CLINT-compatible base 0x02000000. MTIME is at the
// legacy CLINT offset 0xBFF8 (ACLINT 1.0 Table 2), so this map is drop-in for a
// stock CLINT driver and MTIME's address does not move with the hart count.
#define RVMODEL_MTIME_ADDRESS     0x0200BFF8
#define RVMODEL_MTIMECMP_ADDRESS  0x02004000

##### Machine Interrupts #####

// ACLINT MSWI: MSIP[hart] at base + 4*hart.
#define RVMODEL_SET_MSW_INT(_R1, _R2)                                   \
    li _R1, 1                    ;                                      \
    li _R2, 0x02000000           ;                                      \
    sw _R1, 0(_R2)

#define RVMODEL_CLR_MSW_INT(_R1, _R2)                                   \
    li _R2, 0x02000000           ;                                      \
    sw x0, 0(_R2)

// Neither MEI nor SEI can be raised through the PLIC from software, and that is
// by design rather than a gap in aRVern's PLIC. The ratified RISC-V PLIC spec
// Ch.5 gives the pending array a read path only -- "The current status of the
// interrupt source pending bits in the PLIC core can be read from the pending
// array [...] A pending bit in the PLIC core can be cleared by setting the
// associated enable bit then performing a claim" -- so a pending bit is set only
// by its gateway (the source line) and cleared only by a claim. arvern-ips/ahb_plic
// implements exactly that and silently drops bus writes to 0x001000.
//
// The bench-specific part is one level below: the PLIC's source lines are the
// testbench reg `plic_irq_src`, so nothing the firmware executes can wiggle them.
// (In a real SoC firmware often can, indirectly, by poking the peripheral that
// owns the line.)
//
// mip is not an alternative either, at least not a uniform one. mip.MEIP is
// read-only per the Priv spec and aRVern wires it straight from the pin
// (`mip_meip = irq_m_external_r`), so MEI is unreachable from software full stop.
// mip.SEIP *is* M-writable (`sip_seip = sip_seip_sw | irq_s_external_r`), so SEI
// alone could be raised with `csrs mip, 1<<9` -- but that would need a second,
// different mechanism for MEI, and would not be the one the REFERENCE run uses.
//
// So firmware pokes a peripheral register and the ACT stimulus turns it into an
// interrupt, for both causes.
//
// The protocol deliberately mirrors sail_macros.h's simple_interrupt_generator,
// because that is what generates the REFERENCE run's interrupts: a single
// address, bit 31 selects set (1) or clear (0), and the remaining bits name the
// interrupt by cause number. The stimulus accumulates a pending mask, so an
// interrupt stays asserted until explicitly cleared -- level, not pulse. Getting
// this wrong makes arvern take a different NUMBER of traps than the reference
// and every downstream signature record shifts.
#define RVMODEL_SET_MEXT_INT(_R1, _R2)                                  \
    li _R1, 0x80000800           ; /* set   | MEI (cause 11) */         \
    li _R2, 0x10040008           ;                                      \
    sw _R1, 0(_R2)

#define RVMODEL_CLR_MEXT_INT(_R1, _R2)                                  \
    li _R1, 0x00000800           ; /* clear | MEI (cause 11) */         \
    li _R2, 0x10040008           ;                                      \
    sw _R1, 0(_R2)

##### Supervisor Interrupts #####

// SSI has a real path: the ACLINT SSWI window exposes a write-only SETSSIP
// edge register (sim/rtl_sim/src/trap_irq_aclint_setssip.s), which drives
// aclint_irq_s_software_o straight to the core.
#define RVMODEL_SET_SSW_INT(_R1, _R2)                                   \
    li _R1, 1                    ;                                      \
    li _R2, 0x0200C000           ; /* ACLINT SETSSIP[hart 0] */         \
    sw _R1, 0(_R2)

// SETSSIP is edge/write-only -- the handler clears SIP.SSIP via the CSR, so
// there is nothing to undo at the ACLINT.
#define RVMODEL_CLR_SSW_INT(_R1, _R2)

// SEI uses the same generator and protocol as MEI above.
#define RVMODEL_SET_SEXT_INT(_R1, _R2)                                  \
    li _R1, 0x80000200           ; /* set   | SEI (cause 9) */          \
    li _R2, 0x10040008           ;                                      \
    sw _R1, 0(_R2)

#define RVMODEL_CLR_SEXT_INT(_R1, _R2)                                  \
    li _R1, 0x00000200           ; /* clear | SEI (cause 9) */          \
    li _R2, 0x10040008           ;                                      \
    sw _R1, 0(_R2)

#endif // _RVMODEL_MACROS_H

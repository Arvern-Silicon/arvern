#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_pmp_addr_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: PMP address-register walk and NAPOT size sweep on every entry
#
#   doc/arvern_instructions.md (PMP CSRs): pmpaddr holds "addr[33:2], [31:30]
#   read 0: 32-bit physical space"; "Granularity G = 0"; "Sixteen entries
#   always exist architecturally; entries at or above PMP_NR are read-only
#   zero."
#   Priv 3.7.1 Table 19: pmpaddr "yyyy...yyy0 NAPOT 8-byte", "yyyy...yy01 NAPOT
#   16-byte", ... (k trailing ones = 2^(k+3) bytes, naturally aligned).
#   Priv 3.7.1: "If no PMP entry matches an M-mode access, the access
#   succeeds. If no PMP entry matches an S-mode or U-mode access, but at least
#   one PMP entry is implemented, the access fails." "When the L bit is clear,
#   any M-mode access matching the PMP entry will succeed".
#   Smepmp: "When mseccfg.RLB is 1 locked PMP rules may be removed/modified".
#   doc/traps_and_interrupts.md: mtval for causes 5/7 is the faulting address.
#
#   Entries walked: NE = 16 / 8 / 4 for PMP_NR >= 16 / >= 8 / otherwise.
#
#   PART A, per entry i (all cfg OFF, unlocked): pmpaddr_i <- 0xFFFFFFFF
#     (reads 0x3FFFFFFF), <- 0, then walking one and walking zero over bits
#     0..31 (read-back = written & 0x3FFFFFFF). Entries NE..15: a write of
#     0xFFFFFFFF reads 0.
#
#   PART B, per entry i, per k = 0..30 (pmpaddr_i = (B >> 2) | (2^k - 1));
#     every entry is programmed and read back at every size, the probes below
#     run on entries 0 and NE-1 (the matcher logic is per entry, the probe
#     behaviour is not):
#     k 0..21  B = 0x81000000, size 2^(k+3)
#     k 22..28 B = 0x80000000, size 2^(k+3)   (k = 28: 2 GB, nothing above)
#     k 29     pmpaddr 0x1FFFFFFF: 4 GB at 0 -- no outside address
#     k 30     pmpaddr 0x3FFFFFFF: 8 GB at 0 -- no outside address
#     Probes: LB+SB at the first byte (B; 0x80000000 for k >= 29), the last
#     byte (B+size-1; 0xFFFFFFFF for k >= 29), B-1 (k <= 28), B+size (k <= 27).
#     U phase (SU_MODE_EN): entry i = NAPOT RWX unlocked, one helper entry
#       (1 for i = 0, else 0) = NAPOT X over the ROM so U code runs; U-mode
#       probes: inside allowed, outside faults (no match).
#     M phase (RLB = 1): entry i = L|NAPOT|X; M-mode probes: inside loads and
#       stores fault (L binds M, no R/W), outside allowed (no match); then the
#       entry is cleared and must read back 0.
#   Every fault is checked for cause 5/7, mtval = address, mepc = the LB/SB;
#   a faulting LB leaves rd unchanged. Allowed accesses outside the bench
#   memories reach the executable SRAM through the bench alias (armed by the
#   .v); a data-bus RNMI is counted as an error. The handlers touch no memory
#   (a locked X-only region may cover the SRAMs).
#
#   Every check writes x31 = 0x5 << 28 | phase << 24 | entry << 16 | k << 8 |
#   idx (never a sync value).
#   Result registers:
#     s5 (x21) checks performed      s6 (x22) failures (0)
#     s7 (x23) first failing x31 code (0)
#     s10 (x26) handler mismatches: mtval/mepc +1, unexpected cause +0x10000
#     a3 (x13) load faults           a4 (x14) store faults
#     a7 (x17) RNMIs (0)
#   Handler-only registers: t5, gp, tp. Probe byte area: SRAM_X 0x80000000.
#
# Requires PMP_NR > 0.
#----------------------------------------------------------------------------

.include "firmware_config.inc"

.section .text
.global main

.option norvc

.equ MARV_NMVEC,   0x7FD
.equ MARV_ESTAT,   0x7FE
.equ MSECCFG,      0x747
.equ ROM_NAPOT,    (0x20000000 >> 2) | 0x1FFF      # 64 KB
.equ WMASK,        0x3FFFFFFF
.equ LD_POISON,    0x0BAD0BAD
.equ CTX_BASE,     0x50000000

.if CFG_PMP_NR >= 16
.equ NE, 16
.elseif CFG_PMP_NR >= 8
.equ NE, 8
.else
.equ NE, 4
.endif

main:
    j _start

    #=================================================================
    # M trap handler (no memory access)
    #=================================================================
    .align 2
m_handler:
    csrr t5, mcause
    li   gp, 5
    beq  t5, gp, h_load
    li   gp, 7
    beq  t5, gp, h_store
    li   gp, 8
    beq  t5, gp, h_ecall
    li   gp, 11
    beq  t5, gp, h_ecall
    li   gp, 0x10000                # unexpected: abandon the probe
    add  s10, s10, gp
    j    h_ecall
h_load:
    ori  s9, s9, 1
    addi a3, a3, 1
    la   gp, probe_ld
    j    h_epc
h_store:
    ori  s9, s9, 2
    addi a4, a4, 1
    la   gp, probe_st
h_epc:
    csrr t5, mepc
    beq  t5, gp, 1f
    addi s10, s10, 1
1:  csrr t5, mtval
    beq  t5, a0, 2f
    addi s10, s10, 1
2:  csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret
h_ecall:
    csrw mepc, s8
    li   t5, 0x1800
    csrs mstatus, t5                # MPP = M
    mret

    #=================================================================
    # RNMI handler: an allowed access got a bus error. Count it.
    #=================================================================
    .align 2
nmi_handler:
    csrw 0x740, t5                  # mnscratch
    li   t5, 5
    csrw MARV_ESTAT, t5             # W1C valid|overrun
    addi a7, a7, 1
    csrr t5, 0x740
    .word 0x70200073                # mnret

    #=================================================================
    # Probe (M or U): LB then SB at a0, back to M through ECALL.
    #=================================================================
    .align 2
probe:
    li   s9, 0
    li   t3, LD_POISON
    li   t4, 0x5A
probe_ld:
    lb   t3, 0(a0)
probe_st:
    sb   t4, 0(a0)
    ecall

#=========================================================================
# Macros
#=========================================================================
.macro CHK reg, code
    li   t2, \code
    or   t2, t2, s4
    mv   x31, t2
    addi s5, s5, 1
    beqz \reg, .Lchk_ok\@
    addi s6, s6, 1
    bnez s7, .Lchk_ok\@
    mv   s7, t2
.Lchk_ok\@:
.endm

.macro CTX
    slli s4, s0, 16
    slli t0, s1, 8
    or   s4, s4, t0
    li   t0, CTX_BASE
    or   s4, s4, t0
.endm

# pmpaddr[\idx] <- a0, a1 <- read-back
.macro CALL_ADDR idx
    la   t0, addr_stubs
    slli t1, \idx, 4
    add  t0, t0, t1
    jalr ra, 0(t0)
.endm

# cfg byte of entry [\idx] <- a5, a1 <- read-back byte
.macro CALL_CFG idx
    la   t0, cfg_stubs
    slli t1, \idx, 6
    add  t0, t0, t1
    jalr ra, 0(t0)
.endm

# t3 <- helper entry index (1 for entry 0, else 0)
.macro HELPER_IDX
    li   t3, 0
    bnez s0, .Lhi\@
    li   t3, 1
.Lhi\@:
.endm

.macro PROBE_M
    la   s8, .Lpm\@
    j    probe
.Lpm\@:
.endm

.macro PROBE_U
    la   s8, .Lpu\@
    la   t0, probe
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0                # MPP = U
    mret
.Lpu\@:
.endm

# Probes run on entries 0 and NE-1 only (branch to \skip otherwise).
.macro PROBE_GATE skip
    beqz s0, .Lpg\@
    li   t0, NE-1
    bne  s0, t0, \skip
.Lpg\@:
.endm

# a2 = expected fault mask (0 or 3): mask check, then rd check.
.macro CHECK_PROBE code
    xor  t0, s9, a2
    CHK  t0, \code
    li   t0, 0
    beqz a2, .Lcp\@
    li   t1, LD_POISON
    xor  t0, t3, t1
.Lcp\@:
    CHK  t0, (\code)+1
.endm

# Probes of one size: s2 = B, s3 = size; a2 = inside mask, a6 = outside mask
.macro PROBES mode, code
    mv   a0, s2
    PROBE_\mode
    CHECK_PROBE (\code)|0x10
    add  a0, s2, s3
    addi a0, a0, -1
    PROBE_\mode
    CHECK_PROBE (\code)|0x12
    li   t0, 28
    bgt  s1, t0, .Lpo\@
    mv   a2, a6
    addi a0, s2, -1
    PROBE_\mode
    CHECK_PROBE (\code)|0x14
    li   t0, 27
    bgt  s1, t0, .Lpo\@
    add  a0, s2, s3
    PROBE_\mode
    CHECK_PROBE (\code)|0x16
.Lpo\@:
.endm

#=========================================================================
_start:
    li   sp, 0x80010000
    la   t0, m_handler
    csrw mtvec, t0
    la   t0, nmi_handler
    csrw MARV_NMVEC, t0
    csrsi 0x744, 8                  # mnstatus.NMIE = 1
    csrw mstatush, x0               # mstatus.MDT = 0
    csrci mstatus, 8                # MIE = 0
    li   t0, 0x20000                # MPRV = 0
    csrc mstatus, t0

    li   s0, 0
    li   s1, 0
    li   s4, CTX_BASE
    li   s5, 0
    li   s6, 0
    li   s7, 0
    li   s9, 0
    li   s10, 0
    li   a3, 0
    li   a4, 0
    li   a7, 0

    csrw pmpcfg0, zero
    csrw pmpcfg1, zero
    csrw pmpcfg2, zero
    csrw pmpcfg3, zero
    csrsi MSECCFG, 4                # RLB = 1 (nothing locked yet)

    li   x31, 0x11111111            # Sync: PART A

    #=================================================================
    # PART A: pmpaddr bit walk
    #=================================================================
    li   s0, 0
a_entry:
    li   s1, 0
    CTX
    li   a0, -1
    CALL_ADDR s0
    li   t0, WMASK
    xor  t0, a1, t0
    CHK  t0, 0x01000000
    li   a0, 0
    CALL_ADDR s0
    CHK  a1, 0x01000001
a_ones:
    CTX
    li   t0, 1
    sll  a0, t0, s1
    CALL_ADDR s0
    li   t0, WMASK
    and  t0, a0, t0
    xor  t0, t0, a1
    CHK  t0, 0x01000002
    addi s1, s1, 1
    li   t0, 32
    blt  s1, t0, a_ones
    li   s1, 0
a_zeros:
    CTX
    li   t0, 1
    sll  a0, t0, s1
    not  a0, a0
    CALL_ADDR s0
    li   t0, WMASK
    and  t0, a0, t0
    xor  t0, t0, a1
    CHK  t0, 0x01000003
    addi s1, s1, 1
    li   t0, 32
    blt  s1, t0, a_zeros
    li   a0, 0
    CALL_ADDR s0
    addi s0, s0, 1
    li   t0, NE
    blt  s0, t0, a_entry

.if NE < 16
    li   s1, 0
a_surplus:
    CTX
    li   a0, -1
    CALL_ADDR s0
    CHK  a1, 0x01800000
    addi s0, s0, 1
    li   t0, 16
    blt  s0, t0, a_surplus
.endif

    li   x31, 0x22222222            # Sync: PART B

    #=================================================================
    # PART B: NAPOT size sweep
    #=================================================================
    li   s0, 0
b_entry:
    li   s1, 0
b_size:
    CTX
    li   t0, 29
    blt  s1, t0, 1f
    li   s2, 0x80000000             # k = 29, 30: whole space
    li   s3, 0x80000000
    li   a0, 0x1FFFFFFF
    beq  s1, t0, 3f
    li   a0, 0x3FFFFFFF
    j    3f
1:  li   t0, 8
    sll  s3, t0, s1                 # size = 8 << k
    li   s2, 0x81000000
    li   t0, 21
    ble  s1, t0, 2f
    li   s2, 0x80000000
2:  li   t0, 1
    sll  t0, t0, s1
    addi t0, t0, -1
    srli a0, s2, 2
    or   a0, a0, t0
3:  mv   s11, a0
    CALL_ADDR s0
    xor  t0, a1, s11
    CHK  t0, 0x02000000

.if CFG_SU_MODE_EN
    HELPER_IDX
    li   a0, ROM_NAPOT
    CALL_ADDR t3
    HELPER_IDX
    li   a5, 0x1C                   # NAPOT | X
    CALL_CFG t3
    li   a5, 0x1F                   # NAPOT | RWX, unlocked
    CALL_CFG s0
    xori t0, a1, 0x1F
    CHK  t0, 0x03000000
    li   a2, 0
    li   a6, 3
    PROBE_GATE .Lskip_u
    PROBES U, 0x03000000
.Lskip_u:
    li   a5, 0
    CALL_CFG s0
    HELPER_IDX
    li   a5, 0
    CALL_CFG t3
.endif

    li   a5, 0x9C                   # L | NAPOT | X
    CALL_CFG s0
    xori t0, a1, 0x9C
    CHK  t0, 0x04000000
    li   a2, 3
    li   a6, 0
    PROBE_GATE .Lskip_m
    PROBES M, 0x04000000
.Lskip_m:
    li   a5, 0                      # RLB = 1: the locked entry is editable
    CALL_CFG s0
    CHK  a1, 0x04000001

    addi s1, s1, 1
    li   t0, 31
    blt  s1, t0, b_size
    li   a0, 0
    CALL_ADDR s0
    addi s0, s0, 1
    li   t0, NE
    blt  s0, t0, b_entry

    csrci MSECCFG, 4                # RLB = 0, nothing locked

    li   x31, 0xdeadbeef
end_of_test:
    nop
    j    end_of_test

#=========================================================================
# Per-entry CSR stubs (CSR numbers are immediates)
#=========================================================================
    .balign 16
addr_stubs:
.irp e, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    csrw 0x3B0 + \e, a0
    csrr a1, 0x3B0 + \e
    jalr x0, 0(ra)
    nop
.endr

    .balign 64
cfg_stubs:
.irp e, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    .balign 64
    csrr t0, 0x3A0 + ((\e) >> 2)
    li   t1, (~(0xFF << (((\e) & 3) * 8))) & 0xFFFFFFFF
    and  t0, t0, t1
    slli t1, a5, ((\e) & 3) * 8
    or   t0, t0, t1
    csrw 0x3A0 + ((\e) >> 2), t0
    csrr a1, 0x3A0 + ((\e) >> 2)
    srli a1, a1, ((\e) & 3) * 8
    andi a1, a1, 0xFF
    jalr x0, 0(ra)
.endr

#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_marv_addr_walk
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: MARV ADDRESS WALK -- data-bus-error evidence registers
#   software_guide.md §9: a data-bus error is a resumable NMI with
#   mncause = 0x8000_0003; marv_epc (0xFFC) = "PC of the access that faulted",
#   marv_eaddr (0xFFD) = "the address that faulted", marv_estat (0x7FE) =
#   {uop_sourced[4], restartable[3], overrun[2], store[1], valid[0]}, valid and
#   overrun W1C (write 0x5). mnepc points past the access, so MNRET resumes.
#
#   PHASE A (bench alias ON): a stub `lw a5, 0(x0); jalr x0, 0(ra)` copied to
#     executable-SRAM offsets 0x0800 and (1<<k)|0x0800 for k = 12..15 (the alias
#     decodes the low 16 bits) is called at (1<<k)|0x0800, k = 12..31
#     (bit 25 -> 0x0201_0800, bit 29 -> 0x2100_0800 so no real slave is hit;
#     k = 31 is the real 0x8000_0800). Each load from 0 faults:
#     marv_epc = the stub address (PC bits 12..31 walk), marv_eaddr = 0,
#     marv_estat = 0x01.
#   PHASE B (bench alias OFF): lw/sw at unmapped addresses from table_b --
#     walking ones bits 3..31 (bit 25 -> 0x0280_0000, 29 -> 0x2100_0000,
#     31 -> 0xC000_0000), sw to 0x4000_0000|(1<<k) k = 3..20, walking zeros
#     bits 2..31 (word aligned). marv_eaddr = address, marv_epc = the lw/sw,
#     marv_estat = 0x01 (load) / 0x03 (store).
#
#   The RNMI handler compares against a0 (expected epc), a1 (expected eaddr),
#   a3 (expected estat), W1C estat and counts deliveries in s3. Main waits for
#   the count before the next round (the RNMI is asynchronous to the access).
#   Results: s0 = rounds (20 + 77), s1 = errors (0), t2 = first failing
#   address (0), s2 = rounds that timed out waiting for the RNMI (0).
#----------------------------------------------------------------------------

.equ MNCAUSE,     0x742
.equ MNSTATUS,    0x744
.equ MARV_NMVEC,  0x7FD
.equ MARV_ESTAT,  0x7FE
.equ MARV_EPC,    0xFFC
.equ MARV_EADDR,  0xFFD
.equ STUB_OFF,    0x0800
.equ STUB_WORDS,  2

.section .text
.global main
main:
    j   _start

#=========================================================================
# RNMI handler: check the evidence against a0/a1/a3, clear, count
#=========================================================================
    .align 2
rnmi_handler:
    csrr  t3, MNCAUSE
    li    t4, 0x80000003
    bne   t3, t4, h_err
    csrr  t3, MARV_EPC
    bne   t3, a0, h_err
    csrr  t3, MARV_EADDR
    bne   t3, a1, h_err
    csrr  t3, MARV_ESTAT
    bne   t3, a3, h_err
    j     h_ok
h_err:
    addi  s1, s1, 1
    bnez  t2, h_ok
    mv    t2, a2
h_ok:
    li    t3, 0x5
    csrw  MARV_ESTAT, t3
    addi  s3, s3, 1
    .word 0x70200073            # mnret

#=========================================================================
# mtvec: nothing synchronous is expected (bus errors are never mcause 5/7)
#=========================================================================
    .align 2
m_bad_handler:
    li    x31, 0xBADBAD05
    j     m_bad_handler

#=========================================================================
# Wait for the RNMI of the access just issued (s7 = count before it)
#=========================================================================
wait_rnmi:
    li    s6, 20000
1:  bne   s3, s7, 2f
    addi  s6, s6, -1
    bnez  s6, 1b
    addi  s2, s2, 1             # timed out: no RNMI
    addi  s1, s1, 1
    bnez  t2, 2f
    mv    t2, a2
2:  ret

_start:
    csrsi MNSTATUS, 8           # mnstatus.NMIE = 1
    csrw  mstatush, x0          # mstatus.MDT   = 0
    la    t0, m_bad_handler
    csrw  mtvec, t0
    la    t0, rnmi_handler
    csrw  MARV_NMVEC, t0
    li    t0, 0x5
    csrw  MARV_ESTAT, t0

    li    s0, 0                 # rounds
    li    s1, 0                 # errors
    li    s2, 0                 # timeouts
    li    s3, 0                 # RNMI count
    li    t2, 0                 # first failing address

    # copy the stub to executable-SRAM offset STUB_OFF, and to (1<<k)|STUB_OFF for
    # k = 12..15: the alias decodes the low 16 bits, so those PCs land there
    la    s6, stub_offsets
    la    s8, stub_offsets_end
0:  la    t0, stub
    lw    t1, 0(s6)
    li    t3, 0x80000000
    or    t1, t1, t3
    li    t3, STUB_WORDS
1:  lw    t4, 0(t0)
    sw    t4, 0(t1)
    addi  t0, t0, 4
    addi  t1, t1, 4
    addi  t3, t3, -1
    bnez  t3, 1b
    addi  s6, s6, 4
    bne   s6, s8, 0b
    fence.i

    li    x31, 0x11111111       # sync: bench arms the alias

    #--- PHASE A: stub executed at walking PC addresses
    la    s4, table_a
    la    s5, table_a_end
round_a:
    lw    a0, 0(s4)             # stub address = expected marv_epc
    li    a1, 0                 # expected marv_eaddr
    li    a3, 0x1               # expected marv_estat: valid, load
    mv    a2, a0                # failure tag
    mv    s7, s3
    jalr  ra, 0(a0)
    call  wait_rnmi
    addi  s0, s0, 1
    addi  s4, s4, 4
    bltu  s4, s5, round_a

    li    x31, 0x22222222       # sync: bench disarms the alias

    #--- PHASE B: lw / sw at unmapped addresses
    la    s4, table_b
    la    s5, table_b_end
round_b:
    lw    a1, 0(s4)             # address = expected marv_eaddr
    lw    t0, 4(s4)             # 1 = store
    mv    a2, a1
    mv    s7, s3
    bnez  t0, do_store
    la    a0, ld_pc
    li    a3, 0x1               # valid, load
ld_pc:
    lw    a5, 0(a1)
    j     b_wait
do_store:
    la    a0, st_pc
    li    a3, 0x3               # valid, store
st_pc:
    sw    a1, 0(a1)
b_wait:
    call  wait_rnmi
    addi  s0, s0, 1
    addi  s4, s4, 8
    bltu  s4, s5, round_b

    li    x31, 0xdeadbeef

end_of_test:
    nop
    j end_of_test

    .align 2
.option push
.option norvc
stub:
    lw    a5, 0(x0)             # address 0: unmapped -> bus error
    jalr  x0, 0(ra)
.option pop

    .align 2
table_a:
    .word 0x00001800    # bit 12
    .word 0x00002800    # bit 13
    .word 0x00004800    # bit 14
    .word 0x00008800    # bit 15
    .word 0x00010800    # bit 16
    .word 0x00020800    # bit 17
    .word 0x00040800    # bit 18
    .word 0x00080800    # bit 19
    .word 0x00100800    # bit 20
    .word 0x00200800    # bit 21
    .word 0x00400800    # bit 22
    .word 0x00800800    # bit 23
    .word 0x01000800    # bit 24
    .word 0x02010800    # bit 25 (bit 25: ACLINT -> +bit 16)
    .word 0x04000800    # bit 26
    .word 0x08000800    # bit 27
    .word 0x10000800    # bit 28
    .word 0x21000800    # bit 29 (bit 29: ROM -> +bit 24)
    .word 0x40000800    # bit 30
    .word 0x80000800    # bit 31
table_a_end:

    .align 2
stub_offsets:
    .word 0x0800, 0x1800, 0x2800, 0x4800, 0x8800
stub_offsets_end:

    .align 2
table_b:
    .word 0x00000008, 0    # walking one, bit 3
    .word 0x00000010, 0    # walking one, bit 4
    .word 0x00000020, 0    # walking one, bit 5
    .word 0x00000040, 0    # walking one, bit 6
    .word 0x00000080, 0    # walking one, bit 7
    .word 0x00000100, 0    # walking one, bit 8
    .word 0x00000200, 0    # walking one, bit 9
    .word 0x00000400, 0    # walking one, bit 10
    .word 0x00000800, 0    # walking one, bit 11
    .word 0x00001000, 0    # walking one, bit 12
    .word 0x00002000, 0    # walking one, bit 13
    .word 0x00004000, 0    # walking one, bit 14
    .word 0x00008000, 0    # walking one, bit 15
    .word 0x00010000, 0    # walking one, bit 16
    .word 0x00020000, 0    # walking one, bit 17
    .word 0x00040000, 0    # walking one, bit 18
    .word 0x00080000, 0    # walking one, bit 19
    .word 0x00100000, 0    # walking one, bit 20
    .word 0x00200000, 0    # walking one, bit 21
    .word 0x00400000, 0    # walking one, bit 22
    .word 0x00800000, 0    # walking one, bit 23
    .word 0x01000000, 0    # walking one, bit 24
    .word 0x02800000, 0    # walking one, bit 25 (ACLINT -> +bit 23)
    .word 0x04000000, 0    # walking one, bit 26
    .word 0x08000000, 0    # walking one, bit 27
    .word 0x10000000, 0    # walking one, bit 28
    .word 0x21000000, 0    # walking one, bit 29 (ROM -> +bit 24)
    .word 0x40000000, 0    # walking one, bit 30
    .word 0xC0000000, 0    # walking one, bit 31 (SRAM_X -> +bit 30)
    .word 0x40000008, 1    # 0x4000_0000 | bit 3, store
    .word 0x40000010, 1    # 0x4000_0000 | bit 4, store
    .word 0x40000020, 1    # 0x4000_0000 | bit 5, store
    .word 0x40000040, 1    # 0x4000_0000 | bit 6, store
    .word 0x40000080, 1    # 0x4000_0000 | bit 7, store
    .word 0x40000100, 1    # 0x4000_0000 | bit 8, store
    .word 0x40000200, 1    # 0x4000_0000 | bit 9, store
    .word 0x40000400, 1    # 0x4000_0000 | bit 10, store
    .word 0x40000800, 1    # 0x4000_0000 | bit 11, store
    .word 0x40001000, 1    # 0x4000_0000 | bit 12, store
    .word 0x40002000, 1    # 0x4000_0000 | bit 13, store
    .word 0x40004000, 1    # 0x4000_0000 | bit 14, store
    .word 0x40008000, 1    # 0x4000_0000 | bit 15, store
    .word 0x40010000, 1    # 0x4000_0000 | bit 16, store
    .word 0x40020000, 1    # 0x4000_0000 | bit 17, store
    .word 0x40040000, 1    # 0x4000_0000 | bit 18, store
    .word 0x40080000, 1    # 0x4000_0000 | bit 19, store
    .word 0x40100000, 1    # 0x4000_0000 | bit 20, store
    .word 0xFFFFFFF8, 0    # walking zero, bit 2
    .word 0xFFFFFFF4, 0    # walking zero, bit 3
    .word 0xFFFFFFEC, 0    # walking zero, bit 4
    .word 0xFFFFFFDC, 0    # walking zero, bit 5
    .word 0xFFFFFFBC, 0    # walking zero, bit 6
    .word 0xFFFFFF7C, 0    # walking zero, bit 7
    .word 0xFFFFFEFC, 0    # walking zero, bit 8
    .word 0xFFFFFDFC, 0    # walking zero, bit 9
    .word 0xFFFFFBFC, 0    # walking zero, bit 10
    .word 0xFFFFF7FC, 0    # walking zero, bit 11
    .word 0xFFFFEFFC, 0    # walking zero, bit 12
    .word 0xFFFFDFFC, 0    # walking zero, bit 13
    .word 0xFFFFBFFC, 0    # walking zero, bit 14
    .word 0xFFFF7FFC, 0    # walking zero, bit 15
    .word 0xFFFEFFFC, 0    # walking zero, bit 16
    .word 0xFFFDFFFC, 0    # walking zero, bit 17
    .word 0xFFFBFFFC, 0    # walking zero, bit 18
    .word 0xFFF7FFFC, 0    # walking zero, bit 19
    .word 0xFFEFFFFC, 0    # walking zero, bit 20
    .word 0xFFDFFFFC, 0    # walking zero, bit 21
    .word 0xFFBFFFFC, 0    # walking zero, bit 22
    .word 0xFF7FFFFC, 0    # walking zero, bit 23
    .word 0xFEFFFFFC, 0    # walking zero, bit 24
    .word 0xFDFFFFFC, 0    # walking zero, bit 25
    .word 0xFBFFFFFC, 0    # walking zero, bit 26
    .word 0xF7FFFFFC, 0    # walking zero, bit 27
    .word 0xEFFFFFFC, 0    # walking zero, bit 28
    .word 0xDFFFFFFC, 0    # walking zero, bit 29
    .word 0xBFFFFFFC, 0    # walking zero, bit 30
    .word 0x7FFFFFFC, 0    # walking zero, bit 31
table_b_end:

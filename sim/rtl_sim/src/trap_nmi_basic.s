#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_basic
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI BASIC
#   Basic Smrnmi (Resumable NMI) verification:
#   - NMI handler entered when nmi_i asserts
#   - mnepc saved to scratchpad (address of interrupted instruction)
#   - mnstatus at entry: NMIE=0 (bit3), MNPP=11 (bits12:11) = M-mode
#   - mncause = 0x80000000 at NMI entry (bit[31]=1, cause=0)
#   - mnret resumes execution at mnepc
#   - NMIE=1 after mnret (mnstatus_after_ret checked after handler returns)
#
#   Scratchpad layout (base 0x80000000):
#   0x000: nmi_count           (incremented each NMI entry)
#   0x004: last_mnepc          (mnepc value saved at NMI entry)
#   0x008: mnstatus_at_entry   (mnstatus value at NMI entry)
#   0x00C: mncause_at_entry    (mncause value at NMI entry, expect 0)
#   0x010: mnstatus_after_ret  (mnstatus value read after mnret)
#   0x014: nmi_handler_addr    (address of nmi_handler, for testbench)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # NMI HANDLER (Smrnmi)
    # Entered on NMI assertion (mnstatus.NMIE=1 and nmi_i=1).
    # On entry: NMIE is cleared by hardware, MNPP holds previous priv.
    # Saves mnepc, mnstatus, mncause to scratchpad, increments count.
    # Issues mnret to resume at interrupted PC.
    #=================================================================
    .align 2

nmi_handler:
    addi sp, sp, -16
    sw   t0, 12(sp)
    sw   t1,  8(sp)
    sw   t2,  4(sp)

    # Increment NMI count
    lw   t0, 0x00(s1)
    addi t0, t0, 1
    sw   t0, 0x00(s1)

    # Save MNEPC (address of interrupted instruction)
    csrr t1, 0x741          # mnepc = 0x741
    sw   t1, 0x04(s1)

    # Save MNSTATUS at entry (expect NMIE=0 bit[3], MNPP=11 bits[12:11])
    csrr t2, 0x744          # mnstatus = 0x744
    sw   t2, 0x08(s1)

    # Save MNCAUSE (expect 0 - implementation-defined, always 0)
    csrr t0, 0x742          # mncause = 0x742
    sw   t0, 0x0C(s1)

    lw   t2,  4(sp)
    lw   t1,  8(sp)
    lw   t0, 12(sp)
    addi sp, sp, 16

    .word 0x70200073         # mnret: restore MNPP to priv, set NMIE=1, jump to mnepc

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)          # nmi_count
    sw   t0, 0x04(s1)          # last_mnepc
    sw   t0, 0x08(s1)          # mnstatus_at_entry
    sw   t0, 0x0C(s1)          # mncause_at_entry
    sw   t0, 0x10(s1)          # mnstatus_after_ret

    # Store nmi_handler address in scratchpad for testbench to read
    la   t0, nmi_handler
    sw   t0, 0x14(s1)          # nmi_handler_addr

    # Install a safe mtvec (regular exceptions go here)
    la   t0, safe_mtvec
    csrw mtvec, t0

    # Enable NMI (NMIE resets to 0 per Smrnmi spec; must be set before NMI can be taken)
    csrsi 0x744, 8             # mnstatus.NMIE = 1

    li   x31, 0x11111111       # Sync: init done, handler address stored

    # Wait loop: testbench asserts nmi_i while we loop here.
    # NMI fires, handler runs, mnret returns to the interrupted
    # instruction in this loop. Loop continues until nmi_count > 0.
wait_for_nmi:
    li   t0, 10000
poll_loop:
    addi t0, t0, -1
    bnez t0, poll_loop
    # Check if NMI was already taken
    lw   t0, 0x00(s1)
    beqz t0, wait_for_nmi

    # NMI was taken. Read mnstatus now (NMIE should be 1 after mnret).
    csrr t0, 0x744             # mnstatus
    sw   t0, 0x10(s1)          # mnstatus_after_ret
    lw   t3, 0x10(s1)          # AHB fence: ensure store completes before sync

    li   x31, 0xdeadbeef       # Sync: all done

end_of_test:
    j    end_of_test

    #=================================================================
    # SAFE MTVEC (regular exception fallback - should not fire here)
    #=================================================================
    .align 2
safe_mtvec:
    mret

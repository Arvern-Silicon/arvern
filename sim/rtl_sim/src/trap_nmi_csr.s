#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Test:      trap_nmi_csr
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Description: NMI CSR
#   Smrnmi CSR read/write verification (no NMI triggered):
#   - mnscratch (0x740): full 32-bit R/W
#   - mnepc     (0x741): R/W, bit[0] hardwired 0
#   - mncause   (0x742): WARL, constant 0x80000000 (bit[31]=1, cause=0)
#   - mnstatus  (0x744): bit[3]=NMIE R/W, bits[12:11]=MNPP R/W, rest=0
#
#   Scratchpad layout (base 0x80000000):
#   0x000: mnscratch_rb      (readback after write)
#   0x004: mnepc_rb          (readback after write)
#   0x008: mncause_rb        (readback, expect 0)
#   0x00C: mnstatus_rb       (PHASE3 sub-1: NMIE write-0 @ NMIE=0)
#   0x010: nmi_handler_addr  (safe handler address, for testbench)
#   0x014: nmi_vector_rb     (readback of 0xFFF CSR)
#   0x018: mnstatus_nmie_set_rb (PHASE3 sub-2: after csrsi 8, expect NMIE=1)
#   0x01C: mnstatus_csrw0_rb (PHASE3 sub-3: csrw 0 @ NMIE=1; NMIE stays 1)
#   0x020: mnstatus_csrrci_rb(PHASE3 sub-4: csrrci 8 @ NMIE=1; NMIE stays 1)
#----------------------------------------------------------------------------

.section .text
.global main

main:
    j _start

    #=================================================================
    # SAFE HANDLER (fallback — should not fire during this test)
    #=================================================================
    .align 2

safe_handler:
    mret

    #=================================================================
    # MAIN TEST CODE
    #=================================================================
_start:
    li   sp, 0x80010000
    li   s1, 0x80000000        # Scratchpad base

    # Zero scratchpad
    li   t0, 0
    sw   t0, 0x00(s1)          # mnscratch_rb
    sw   t0, 0x04(s1)          # mnepc_rb
    sw   t0, 0x08(s1)          # mncause_rb
    sw   t0, 0x0C(s1)          # mnstatus_rb
    sw   t0, 0x10(s1)          # nmi_handler_addr
    sw   t0, 0x14(s1)          # nmi_vector_rb
    sw   t0, 0x18(s1)          # mnstatus_nmie_set_rb
    sw   t0, 0x1C(s1)          # mnstatus_csrw0_rb
    sw   t0, 0x20(s1)          # mnstatus_csrrci_rb

    # Install safe fallback mtvec
    la   t0, safe_handler
    csrw mtvec, t0

    # Store safe_handler address in scratchpad for testbench (nmi_handler_addr slot)
    la   t0, safe_handler
    sw   t0, 0x10(s1)

    li   x31, 0x11111111       # Sync: init done


    #=================================================================
    # PHASE 1: mnscratch R/W
    # Write 0x5A5A5A5A to mnscratch (CSR 0x740), read back.
    #=================================================================

    li   t0, 0x5A5A5A5A
    csrw 0x740, t0             # write mnscratch
    csrr t1, 0x740             # read back
    sw   t1, 0x00(s1)          # mnscratch_rb
    lw   t3, 0x00(s1)          # fence: wait for SW AHB data phase before sync

    li   x31, 0x12121212       # Sync: phase 1 done


    #=================================================================
    # PHASE 2: mnepc and mncause
    # Write a valid ROM address to mnepc (CSR 0x741), read back.
    # Read mncause (CSR 0x742) — must return 0 (read-only).
    #=================================================================

    li   t0, 0x20000020        # valid ROM address, 2-byte aligned
    csrw 0x741, t0             # write mnepc
    csrr t1, 0x741             # read back
    sw   t1, 0x04(s1)          # mnepc_rb

    csrr t1, 0x742             # read mncause (expect 0)
    sw   t1, 0x08(s1)          # mncause_rb
    lw   t3, 0x08(s1)          # fence: wait for SW AHB data phase before sync

    li   x31, 0x22222222       # Sync: phase 2 done


    #=================================================================
    # PHASE 3: mnstatus write/read + Smrnmi NMIE software-set-only check
    #
    # mnstatus bit[3]=NMIE, bits[12:11]=MNPP.
    # NMIE semantics (Smrnmi): resets to 0; software CAN set it (write
    # bit[3]=1) but software CANNOT clear it (a write with bit[3]=0 leaves
    # NMIE unchanged). NMIE is cleared only by HW on NMI trap entry and
    # set back by MNRET. MNPP is normal WARL R/W.
    #
    # Sub-step ordering:
    #   1. NMIE=0 (reset): csrw 0  -> NMIE stays 0, MNPP=00      [0x0C]
    #   2. csrsi 8 (set bit[3])    -> NMIE becomes 1             [0x18]
    #   3. csrw 0 while NMIE=1     -> NMIE STAYS 1 (FIX2 disc.)  [0x1C]
    #   4. csrrci 8 while NMIE=1   -> NMIE STAYS 1 (2nd disc.)   [0x20]
    #   5. restore safe state NMIE=1, MNPP=11 -> 0x00001808
    #=================================================================

    # ---- Sub-step 1: NMIE write-0 while NMIE already 0 (reset state) ----
    # Phases 1-2 never set NMIE, so NMIE=0 here.
    # Write 0 to whole reg: NMIE=0 (no spurious set), MNPP=00 (WARL R/W).
    li   t0, 0x00000000        # NMIE=0, MNPP=00
    csrw 0x744, t0             # write mnstatus
    csrr t1, 0x744             # read back
    sw   t1, 0x0C(s1)          # mnstatus_rb  (expect NMIE=0, MNPP=00)

    # ---- Sub-step 2: software SET of NMIE via csrsi (bit[3]) ----
    csrsi 0x744, 8             # set mnstatus.NMIE (uimm[3]=1)
    csrr t1, 0x744             # read back
    sw   t1, 0x18(s1)          # mnstatus_nmie_set_rb  (expect NMIE=1)

    # ---- Sub-step 3: clear-attempt via csrw 0 while NMIE=1 (FIX2 DISC.) ----
    # Spec: NMIE is software-set-only. csrw 0 must NOT clear NMIE.
    # Buggy RTL that honors the bit[3]=0 write would clear NMIE -> FAIL.
    # MNPP IS cleared to 00 by this write (normal WARL R/W) -- not a bug.
    li   t0, 0x00000000        # whole reg = 0 (bit[3]=0 -> clear attempt)
    csrw 0x744, t0             # attempt to clear NMIE
    csrr t1, 0x744             # read back
    sw   t1, 0x1C(s1)          # mnstatus_csrw0_rb  (expect NMIE STILL 1)

    # ---- Sub-step 4: clear-attempt via csrrci (bit[3]) while NMIE=1 ----
    # Second independent discriminator: csrrci clears only bit[3].
    csrrci x0, 0x744, 8        # clear-bit attempt on mnstatus.NMIE
    csrr t1, 0x744             # read back
    sw   t1, 0x20(s1)          # mnstatus_csrrci_rb (expect NMIE STILL 1)
    lw   t3, 0x20(s1)          # fence: wait for SW AHB data phase before sync

    # ---- Sub-step 5: restore safe state ----
    # NMIE=1 (bit3=1), MNPP=11 (bits[12:11]=11 -> 0x1800) => 0x00001808
    li   t0, 0x00001808        # NMIE=1, MNPP=11 (M-mode)
    csrw 0x744, t0

    li   x31, 0x33333333       # Sync: phase 3 done


    #=================================================================
    # PHASE 4: nmi_vector read-only CSR at 0xFFF
    # Read back nmi_vector_i via CSR 0xFFF, store in scratchpad.
    # The testbench drives nmi_vector to a known value and verifies
    # the readback matches exactly.
    #=================================================================

    csrr t1, 0xFFF             # read nmi_vector (CSR 0xFFF)
    sw   t1, 0x14(s1)          # nmi_vector_rb
    lw   t3, 0x14(s1)          # fence: wait for SW AHB data phase before sync

    li   x31, 0xdeadbeef       # Sync: all done

end_of_test:
    j    end_of_test

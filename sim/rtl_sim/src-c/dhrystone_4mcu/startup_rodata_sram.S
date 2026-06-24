#
# startup_rodata_sram.S -- .rodata-in-SRAM variant of startup.S for CoreMark.
#
# Identical to startup.S except for the extra copy loop (step 1c) that mirrors
# .rodata from ROM into SRAM at boot. See the matching linker script
# (link_rodata_sram.ld) for the memory layout.
#
# Selected by BUILD_RODATA_LOCATION=SRAM in run_config.json toolchain.build_config.
#

.section .text.init, "ax"
.global _start
.global __start
.extern main

_start:
__start:
    /*
     * 1. Set up the stack pointer.
     */
    la sp, _stack_end

    /*
     * 1c. Copy the .rodata section from ROM into SRAM.
     */
    la a0, _rodata_load_start    /* Source address (in ROM) */
    la a1, _rodata_start         /* Destination address (in SRAM) */
    la a2, _rodata_load_end      /* End of source */
    sub a2, a2, a0               /* a2 = size = end - start */
    beqz a2, 2f                  /* If empty, skip the copy loop */

1:
    lw t0, 0(a0)
    sw t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    addi a2, a2, -4
    bgt a2, x0, 1b

2:
    /*
     * 2. Copy the initialized data section (.data) from ROM to RAM.
     */
    la a0, __romdatastart
    la a1, __datastart
    la a2, __romdatacopysize
    beqz a2, 4f

3:
    lw t0, 0(a0)
    sw t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    addi a2, a2, -4
    bgt a2, x0, 3b

4:
    /*
     * 3. Zero out the uninitialized data section (.bss).
     */
    la a0, __bssstart
    la a1, __bssend
    sub a2, a1, a0
    beqz a2, 6f

    li t0, 0

5:
    sw t0, 0(a0)
    addi a0, a0, 4
    addi a2, a2, -4
    bnez a2, 5b

6:
    /*
     * 4. Call main().
     */
    call main

    /*
     * 5. Trap forever.
     */
    j .

    .short 0x0001    /* c.nop -- 2-byte padding */

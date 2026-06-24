#
# crt0_rodata_sram.S -- .rodata-in-SRAM variant of crt0.S for the arvern_iverilog
# Embench startup.
#
# Identical to crt0.S except for one extra copy loop (step 1c) that mirrors
# .rodata from ROM into SRAM at boot. The matching linker script
# (link_rodata_sram.ld) places .rodata's VMA in RAM but loads its image from
# ROM via ">RAM AT>ROM"; this code copies the bytes across before main() runs.
#
# Selected by BUILD_RODATA_LOCATION=SRAM in run_config.json toolchain.build_config.
#

.section .text.init, "ax"
.global _start
.global __start
.global _text_start
.extern main

_start:
__start:
    /*
     * 1. Set up the stack pointer.
     */
    la sp, _stack_end

    /*
     * 1b. Set up the global pointer (GP) for small data sections.
     */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /*
     * 1c. Copy the .rodata section from ROM into SRAM.
     *
     * The linker placed .rodata's runtime address (VMA) in RAM but loaded
     * the image into ROM. We mirror the image now so all subsequent .rodata
     * accesses go to SRAM -- eliminating instruction-bus / data-bus contention
     * at the ROM port for .rodata-heavy workloads (S-boxes, lookup tables,
     * soft-FP coefficients, etc.).
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
     * 2. Copy the initialized data section (.data + .sdata) from ROM to RAM.
     * The linker packs .data + .sdata images contiguously after .rodata's LMA
     * in ROM, and contiguously after .rodata's VMA in RAM, so a single copy
     * loop covers both.
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
     * 3. Zero out the uninitialized data section (.bss + .sbss).
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
     * 5. Capture main's return value and report verification result.
     * Identical to crt0.S -- writes pass/fail flag to P1_OUT1 and "done"
     * flag to P1_OUT2, then halts.
     */

    # Invert the return value: a0 = (a0 == 0) ? 1 : 0
    seqz a0, a0

    # Write result to P1_OUT1 peripheral register at 0x10041004
    li t0, 0x10041004
    sw a0, 0(t0)

    # Write to P1_OUT2 peripheral register at 0x10041008 that the testbench is now done
    li t0, 0x10041008
    li a0, 1
    sw a0, 0(t0)

    /*
     * 6. Trap forever.
     */
    j .

    .short 0x0001    /* c.nop -- 2-byte padding */

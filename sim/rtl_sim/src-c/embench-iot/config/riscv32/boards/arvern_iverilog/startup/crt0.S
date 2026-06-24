#
# startup.S - C runtime startup code for bare-metal RISC-V (arvern)
#
# This file must be compiled with a RISC-V cross-compiler.
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
     * The stack is defined in the linker script in the RAM region.
     * We point the stack pointer (sp) to the end of the stack region.
     */
    la sp, _stack_end

    /*
     * 1b. Set up the global pointer (GP) for small data sections.
     * The global pointer is used for efficient access to .sdata and .sbss sections.
     * It must be set before accessing any global variables that might be in these sections.
     */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /*
     * 2. Copy the initialized data section (.data) from ROM to RAM.
     * The linker script places the load image of .data immediately
     * after the .text section in ROM. The runtime image is in RAM.
     */
    la a0, __romdatastart        /* Source address (in ROM) */
    la a1, __datastart           /* Destination address (in RAM) */
    la a2, __romdatacopysize     /* Size of the data to copy */
    beqz a2, 2f                  /* If size is zero, skip the copy loop */

1:
    lw t0, 0(a0)                 /* Load a word from ROM */
    sw t0, 0(a1)                 /* Store it in RAM */
    addi a0, a0, 4               /* Increment source address by 4 bytes */
    addi a1, a1, 4               /* Increment destination address by 4 bytes */
    addi a2, a2, -4              /* Decrement the size counter by 4 */
    bgt a2, x0, 1b               /* Loop if there's still data to copy */

2:
    /*
     * 3. Zero out the uninitialized data section (.bss).
     * This section is not included in the binary image, so we must
     * manually clear the allocated memory.
     */
    la a0, __bssstart            /* Start address of the BSS section */
    la a1, __bssend              /* End address of the BSS section */
    sub a2, a1, a0               /* Calculate the size of the BSS section */
    beqz a2, 3f                  /* If size is zero, skip the zeroing loop */

    li t0, 0                     /* Value to write (zero) */

4:
    sw t0, 0(a0)                 /* Write a zero word */
    addi a0, a0, 4               /* Increment destination address by 4 bytes */
    addi a2, a2, -4              /* Decrement the size counter by 4 */
    bnez a2, 4b                  /* Loop if there's still data to zero */

3:
    /*
     * 4. Call the main function.
     * At this point, the stack is set up, and global variables are
     * initialized. We can now jump to the C code.
     */
    call main

    /*
     * 5. Capture main's return value and report verification result.
     * main() returns 0 if verification passed, 1 if failed (Unix convention).
     * We need to invert this: write 1 to P1_OUT1 if passed, 0 if failed.
     * Return value is in a0 register per RISC-V calling convention.
     */

    # Invert the return value: a0 = (a0 == 0) ? 1 : 0
    seqz a0, a0                  # Set a0 to 1 if a0 was 0, else 0

    # Write result to P1_OUT1 peripheral register at 0x10041004
    li t0, 0x10041004            # Load P1_OUT1 address
    sw a0, 0(t0)                 # Store verification result (1=pass, 0=fail)

    # Write to P1_OUT2 peripheral register at 0x10041008 that the testbench is now done
    li t0, 0x10041008            # Load P1_OUT2 address
    li a0, 1                     # Set done value
    sw a0, 0(t0)                 # Store testbench done value

    /*
     * 6. Infinite loop after reporting result.
     * In a bare-metal system, `main` should not return. If it does,
     * we trap the execution here to prevent the processor from
     * executing garbage instructions.
     */
    j .

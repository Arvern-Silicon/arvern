.section .init
.globl _start
_start:
    la sp, stack_top      # Set up stack pointer
    call main             # Call main
    j .                   # Hang if main returns

.section .bss
.space 4096               # Reserve 4 KB stack
.globl stack_top
stack_top:

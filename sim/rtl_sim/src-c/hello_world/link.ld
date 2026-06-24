ENTRY(_start)

MEMORY
{
    ROM  (rx)  : ORIGIN = 0x20000000, LENGTH = 32K
    SRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 32K
}

SECTIONS
{
    /* Code and read-only data go to ROM */
    .text : {
        *(.init)
        *(.text*)
        *(.rodata*)
        *(.srodata*)
    } > ROM

    /* Initialized data: runtime in SRAM, init values in ROM */
    .data : {
        *(.data*)
    } > SRAM AT > ROM

    /* Uninitialized data (no init values) in SRAM */
    .bss (NOLOAD) : {
        *(.bss*)
        *(COMMON)
    } > SRAM

    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }

    /* Startup symbols */
    __romdatastart    = LOADADDR(.data);   /* init values in ROM */
    __datastart       = ADDR(.data);       /* runtime location */
    __romdatacopysize = SIZEOF(.data);
}

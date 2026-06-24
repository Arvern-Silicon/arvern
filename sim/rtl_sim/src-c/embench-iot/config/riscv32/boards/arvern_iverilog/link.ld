ENTRY(_start)

MEMORY
{
  ROM (rx)  : ORIGIN = 0x20000000, LENGTH = 64K
  RAM (rwx) : ORIGIN = 0x81000000, LENGTH = 64K
}

SECTIONS
{
  /* --- Code (ROM) --- */
  .text :
  {
    . = ALIGN(4);
    _text_start = .;
    KEEP(*(.init))
    *(.text .text.*)
    *(.eh_frame)              /* sometimes emitted by GCC */
    . = ALIGN(4);
    _text_end = .;
  } > ROM

  /* --- Read-Only Data (ROM) --- */
  .rodata :
  {
    . = ALIGN(4);
    _rodata_start = .;
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)    /* small read-only data constants */
    . = ALIGN(4);
    _rodata_end = .;
  } > ROM

  /* --- Initialized Data (RAM, load from ROM) --- */
  .data : AT (ADDR(.rodata) + SIZEOF(.rodata))
  {
    . = ALIGN(4);
    _data_start = .;
    *(.data .data.*)
    . = ALIGN(4);
    _data_end = .;
  } > RAM

  /* --- Small Initialized Data (RAM, load from ROM) --- */
  .sdata : AT (ADDR(.rodata) + SIZEOF(.rodata) + SIZEOF(.data))
  {
    . = ALIGN(4);
    _sdata_start = .;
    __global_pointer$ = . + 0x800;  /* GP is set to middle of sdata for ±2KB access */
    *(.sdata .sdata.*)
    . = ALIGN(4);
    _sdata_end = .;
  } > RAM

  /* --- BSS (RAM, zero-initialized) --- */
  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    _bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  /* --- Small BSS (RAM, zero-initialized) --- */
  .sbss (NOLOAD) :
  {
    . = ALIGN(4);
    _sbss_start = .;
    *(.sbss .sbss.*)
    . = ALIGN(4);
    _sbss_end = .;
  } > RAM

  /* --- Stack (RAM) --- */
  .stack (NOLOAD) :
  {
    . = ALIGN(4);      /* Ensure start of section is aligned */
    _stack_start = .;
    . += 8K;           /* Allocate 8KB of space */
    . = ALIGN(4);      /* Ensure end address (Initial SP) is aligned */
    _stack_end = .;
  } > RAM


  __datastart       = _data_start;
  __dataend         = _sdata_end;
  __romdatastart    = LOADADDR(.data);
  __romdatacopysize = _sdata_end - _data_start;

  __bssstart        = _bss_start;
  __bssend          = _sbss_end;

  PROVIDE(end = _sbss_end);
}

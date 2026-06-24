/*
 * link_rodata_sram.ld -- .rodata-in-SRAM variant of the arvern CoreMark linker
 * script. See link.ld for the baseline layout. Differences:
 *
 *   .rodata now lives in RAM (VMA) but is loaded from ROM (LMA).
 *   _rodata_load_start / _rodata_load_end expose the ROM range to startup_rodata_sram.S.
 *   .data's LMA is reanchored to LOADADDR(.rodata) + SIZEOF(.rodata) so the
 *   ROM image stays packed and __romdatastart/__romdatacopysize keep working.
 *
 * Selected by BUILD_RODATA_LOCATION=SRAM in run_config.json toolchain.build_config.
 */

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

  /* --- Read-Only Data (RAM at runtime, image loaded into ROM) --- */
  .rodata :
  {
    . = ALIGN(4);
    _rodata_start = .;
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)    /* small read-only data constants */
    . = ALIGN(4);
    _rodata_end = .;
  } > RAM AT> ROM

  _rodata_load_start = LOADADDR(.rodata);
  _rodata_load_end   = LOADADDR(.rodata) + SIZEOF(.rodata);

  /* --- Initialized Data (RAM, load from ROM, packed after .rodata LMA) --- */
  .data : AT (LOADADDR(.rodata) + SIZEOF(.rodata))
  {
    . = ALIGN(4);
    _data_start = .;
    *(.data .data.*)
    . = ALIGN(4);
    _data_end = .;
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

  /* --- Stack (RAM) --- */
  .stack (NOLOAD) :
  {
    . = ALIGN(4);
    _stack_start = .;
    . += 8K;
    . = ALIGN(4);
    _stack_end = .;
  } > RAM


  __datastart       = _data_start;
  __dataend         = _data_end;
  __romdatastart    = LOADADDR(.data);
  __romdatacopysize = _data_end - _data_start;

  __bssstart        = _bss_start;
  __bssend          = _bss_end;

  PROVIDE(end = _bss_end);
}

/*
 * link_rodata_sram.ld -- .rodata-in-SRAM variant of the arvern_iverilog
 * Embench linker script.
 *
 * Layout:
 *   .text       -> ROM  (placement)
 *   .rodata     -> RAM  (placement, copied from ROM at boot by crt0_rodata_sram.S)
 *   .data       -> RAM  (placement, copied from ROM at boot -- unchanged)
 *   .sdata      -> RAM  (placement, copied from ROM at boot -- unchanged)
 *   .bss/.sbss  -> RAM  (NOLOAD, zeroed at boot -- unchanged)
 *   .stack      -> RAM  (NOLOAD, unchanged)
 *
 * The ">RAM AT>ROM" syntax tells the linker: place .rodata at a RAM VMA, but
 * load the image from ROM at the next free ROM byte after .text. The
 * _rodata_load_start / _rodata_load_end symbols expose the ROM range so the
 * crt0 can copy at boot.
 *
 * The .data and .sdata LMAs are reanchored to LOADADDR(.rodata) +
 * SIZEOF(.rodata) so the ROM image stays packed and the existing
 * __romdatastart / __romdatacopysize symbols keep working for the single
 * .data + .sdata copy loop (the two sections remain contiguous in both LMA
 * and VMA, so one copy still covers both).
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
  /* crt0_rodata_sram.S copies _rodata_load_start.._rodata_load_end (ROM) */
  /* into _rodata_start (RAM) before main() runs. */
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

  /* --- Small Initialized Data (RAM, load from ROM, packed after .data LMA) --- */
  .sdata : AT (LOADADDR(.data) + SIZEOF(.data))
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

/* Set these to match the DUT memory map and hart count.
 *
 * The whole ACT image (code + data + bss + stack) must sit in one contiguous
 * rwx region. arvern's ROM is not writable and its .data alone is ~96 KB, so the
 * image lives entirely in the executable SRAM at 0x80000000, enlarged for this
 * flow via -Ptb_arvern.SRAM_X_SIZE=1048576. TEST_BASE is also the reset vector
 * (-Ptb_arvern.RESET_VECTOR=0x80000000).
 *
 * 1 MB rather than 512 KB: every instruction suite fits in 220 KB, but Sm_mcsr
 * needs ~706 KB. Keep this in step with the memory.regions size in sail.json.
 */
RAM_ORIGIN = 0x80000000;
RAM_LENGTH = 0x00100000;
TEST_BASE = 0x80000000;
NUM_HARTS = 1;

/* Most users should not need to modify anything below this line. */
/* 16 KB rather than the stock 128 KB: the stock size alone would be most
   of the budget, and no ACT test comes close to needing it. */
STACK_SIZE = 0x4000;

OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

MEMORY
{
  ram (rwx) : ORIGIN = RAM_ORIGIN, LENGTH = RAM_LENGTH
}

PROVIDE(__stack_size = STACK_SIZE);
PROVIDE(__num_harts = NUM_HARTS);

SECTIONS
{
  ASSERT(TEST_BASE >= ORIGIN(ram) && TEST_BASE < ORIGIN(ram) + LENGTH(ram), "TEST_BASE is outside RAM; update TEST_BASE and RAM_ORIGIN/RAM_LENGTH in link.ld, and the matching memory.regions entry in sail.json")

  .text.init   TEST_BASE : { *(.text.init) } > ram
  .text.rvtest . : { *(.text.rvtest) *(.text.rvtest.*) } > ram

  . = ALIGN(0x4000);
  .rodata . : { *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) } > ram
  .data   . : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) } > ram

  . = ALIGN(16);
  .bss . : {
    __bss_start = .;
    *(.sbss) *(.sbss.*) *(.bss) *(.bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
  } > ram

  . = ALIGN(16);
  __stack_bottom = .;
  . += __stack_size * __num_harts;
  __stack_top = .;

  . = ALIGN(0x1000);
  .text.rvmodel . : { *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*) } > ram

  . = ALIGN(0x1000);
  _end = .;

  ASSERT(_end <= ORIGIN(ram) + LENGTH(ram), "ACT ELF exceeds RAM; increase RAM_LENGTH in link.ld and the matching memory.regions size in sail.json")
}

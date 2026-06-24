#!/bin/bash
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    asm2ihex.sh
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Assemble a .s file with riscv-none-elf-gcc and convert to Intel HEX.
#----------------------------------------------------------------------------

if [ $# -lt 4 ] || [ $# -gt 5 ]; then
  echo "ERROR    : wrong number of arguments"
  echo "USAGE    : asm2ihex.sh <test name> <test assembler file> <linker script> <inst_mode> [extra_src]"
  echo "Example  : asm2ihex.sh c-jump_jge  ../src/c-jump_jge.s43 ../bin/link.ld STD_MODE"
  echo "Example  : asm2ihex.sh c-jump_jge  ../src/c-jump_jge.s43 ../bin/link.ld COMP_MODE"
  echo "Example  : asm2ihex.sh pmem        pmem.s                ../bin/link.ld STD_MODE  ../src/random_irq_trap_handler.s"
  exit 1
fi

# Optional extra source file (e.g., random IRQ trap handler)
EXTRA_SRC=""
if [ $# -eq 5 ]; then
    EXTRA_SRC="$5"
    if [ ! -e "$EXTRA_SRC" ]; then
        echo "Extra source file doesn't exist: $EXTRA_SRC"
        exit 1
    fi
fi

# Load MARCH and toolchain configuration (auto-generated from RTL config)
if [ -f march_config.sh ]; then
    source march_config.sh
else
    echo "Warning: march_config.sh not found, using default values"
    MARCH_STD="rv32im_zicsr"
    MARCH_COMP="rv32imc_zicsr"
    CROSS="riscv64-unknown-elf"
    TC_CC="${CROSS}-gcc"
    TC_OBJCOPY="${CROSS}-objcopy"
    TC_OBJDUMP="${CROSS}-objdump"
    TC_SIZE="${CROSS}-size"
fi

# Use toolchain variables (TC_*) from march_config.sh, with fallback to CROSS prefix
CC="${TC_CC:-${CROSS}-gcc}"
OBJCOPY="${TC_OBJCOPY:-${CROSS}-objcopy}"
OBJDUMP="${TC_OBJDUMP:-${CROSS}-objdump}"
OBJSIZE="${TC_SIZE:-${CROSS}-size}"

# Set architecture based on instruction mode
INST_MODE=$4
if [ "$INST_MODE" == "COMP_MODE" ]; then
    # Compressed instruction mode
    MARCH="$MARCH_COMP"
else
    # Standard instruction mode (default)
    MARCH="$MARCH_STD"
fi

CFLAGS="-march=${MARCH} -mabi=${MABI:-ilp32} -nostartfiles -Wall -Wextra -O0"

echo "Instruction mode: $INST_MODE (using -march=${MARCH})"


###############################################################################
#               Check if definition & assembler files exist                   #
###############################################################################

if [ ! -e $2 ]; then
    echo "Assembler file doesn't exist: $2"
    exit 1
fi
if [ ! -e $3 ]; then
    echo "Linker definition file template doesn't exist: $3"
    exit 1
fi


###############################################################################
#                  Compile, link & generate IHEX file                         #
###############################################################################
echo "      \$ ${CC} ${CFLAGS} -T $3 $1.s ${EXTRA_SRC} -o $1.elf"
${CC}      ${CFLAGS} -T $3 $1.s ${EXTRA_SRC} -o $1.elf
echo "      \$ ${OBJCOPY} -O ihex $1.elf  $1.ihex"
${OBJCOPY} -O ihex $1.elf  $1.ihex
echo "      \$ ${OBJDUMP} -dSt    $1.elf >$1.lst"
${OBJDUMP} -dSt    $1.elf >$1.lst
echo "      \$ ${OBJSIZE}         $1.elf >$1.size"
${OBJSIZE}         $1.elf >$1.size
LST2CHECKER="${BIN_DIR:-../bin}/lst2checker.py"
echo "      \$ ${LST2CHECKER} $1.lst checker_data.mem"
${LST2CHECKER} $1.lst checker_data.mem
echo ""

#!/bin/bash
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    c2ihex.sh
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Compile a .c source tree with riscv-none-elf-gcc and convert to Intel HEX.
#----------------------------------------------------------------------------

EXPECTED_ARGS=2
if [ $# -ne $EXPECTED_ARGS ]; then
  echo "ERROR    : wrong number of arguments"
  echo "USAGE    : c2ihex.sh <test directory> <inst_mode>"
  echo "Example  : c2ihex.sh ../src-c/hello_world STD_MODE"
  echo "Example  : c2ihex.sh ../src-c/coremark COMP_MODE"
  exit 1
fi

TEST_DIR=$1
INST_MODE=$2

# Set architecture info based on instruction mode
if [ "$INST_MODE" == "COMP_MODE" ]; then
    # Compressed instruction mode: add 'c' extension
    MARCH_INFO="rv32ic"
else
    # Standard instruction mode (default)
    MARCH_INFO="rv32i"
fi

echo "Instruction mode: $INST_MODE (using -march=${MARCH_INFO})"


###############################################################################
#               Check if test directory exists                                #
###############################################################################

if [ ! -d "$TEST_DIR" ]; then
    echo "Test directory doesn't exist: $TEST_DIR"
    exit 1
fi

if [ ! -f "$TEST_DIR/Makefile" ]; then
    echo "Makefile doesn't exist in: $TEST_DIR"
    exit 1
fi


###############################################################################
#                  Compile C code and generate IHEX file                      #
###############################################################################

# Export instruction mode for Makefile to use
export INST_MODE

# Run make in test directory
echo "      Running: make clean && make in $TEST_DIR"
cd "$TEST_DIR"
make clean
make

exit_code=$?
if [ $exit_code -ne 0 ]; then
    echo "ERROR: Make failed with exit code $exit_code"
    exit $exit_code
fi

# Get the test name from the directory
TEST_NAME=$(basename "$TEST_DIR")

# Generate checker data from .lst file if it exists
if [ -f "${TEST_NAME}.lst" ]; then
    echo "      Generating checker data from ${TEST_NAME}.lst"
    LST2CHECKER="${BIN_DIR:-../../bin}/lst2checker.py"
    CHECKER_OUT="${CHECKER_DATA_DIR:-../../run}/checker_data.mem"
    ${LST2CHECKER} "${TEST_NAME}.lst" "${CHECKER_OUT}"
else
    echo "WARNING: ${TEST_NAME}.lst not found, checker will be disabled"
fi

echo ""

#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    lst2checker.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Parse riscv-objdump .lst output and generate the checker_data.mem file consumed by the PC/instruction checker.
#----------------------------------------------------------------------------

import sys
import re
from typing import Dict, Tuple

def parse_lst_file(lst_filename: str) -> Dict[int, Tuple[int, bool]]:
    """
    Parse the .lst disassembly file and extract PC -> (instruction, is_compressed) mappings

    Args:
        lst_filename: Path to the .lst file

    Returns:
        Dictionary mapping PC address to (instruction code, is_compressed flag)
    """
    pc_to_inst = {}

    # Pattern to match disassembly lines:
    # 20000000:	fff00093          	li	ra,-1
    # Address (hex):  instruction_hex (tab) mnemonic
    pattern = re.compile(r'^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]+)\s+')

    try:
        with open(lst_filename, 'r') as f:
            for line in f:
                match = pattern.match(line)
                if match:
                    pc_addr = int(match.group(1), 16)
                    inst_hex = match.group(2)

                    # Determine if compressed (16-bit) or standard (32-bit)
                    if len(inst_hex) <= 4:
                        # Compressed instruction (16-bit)
                        inst_code = int(inst_hex, 16)
                        is_compressed = True
                    else:
                        # Standard instruction (32-bit)
                        inst_code = int(inst_hex, 16)
                        is_compressed = False

                    pc_to_inst[pc_addr] = (inst_code, is_compressed)

    except FileNotFoundError:
        print(f"ERROR: Could not open file '{lst_filename}'", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Failed to parse file '{lst_filename}': {e}", file=sys.stderr)
        sys.exit(1)

    return pc_to_inst

def generate_checker_mem(pc_to_inst: Dict[int, Tuple[int, bool]], output_filename: str):
    """
    Generate Verilog memory initialization file for the checker

    Format: Each line contains:
    @address instruction_hex compressed_flag

    Args:
        pc_to_inst: Dictionary mapping PC to (instruction, is_compressed)
        output_filename: Path to output .mem file
    """
    try:
        with open(output_filename, 'w') as f:
            # Write header comment
            f.write("// Instruction/PC checker data\n")
            f.write("// Format: @PC_address instruction_hex compressed_flag\n")
            f.write("//         compressed_flag: 0=standard (32-bit), 1=compressed (16-bit)\n")
            f.write("\n")

            # Sort by PC address for cleaner output
            for pc_addr in sorted(pc_to_inst.keys()):
                inst_code, is_compressed = pc_to_inst[pc_addr]

                # Format: @address inst_hex is_compressed
                if is_compressed:
                    # 16-bit compressed instruction
                    f.write(f"@{pc_addr:08x} {inst_code:04x} 1\n")
                else:
                    # 32-bit standard instruction
                    f.write(f"@{pc_addr:08x} {inst_code:08x} 0\n")

        print(f"INFO: Generated checker memory file: {output_filename}")
        print(f"INFO: Total instructions: {len(pc_to_inst)}")

    except Exception as e:
        print(f"ERROR: Failed to write file '{output_filename}': {e}", file=sys.stderr)
        sys.exit(1)

def main():
    """Main entry point"""

    if len(sys.argv) != 3:
        print("Usage: lst2checker.py <input.lst> <output.mem>")
        print("  <input.lst>  - Input disassembly listing file from objdump")
        print("  <output.mem> - Output Verilog memory initialization file")
        sys.exit(1)

    lst_filename = sys.argv[1]
    mem_filename = sys.argv[2]

    # Parse the .lst file
    print(f"INFO: Parsing listing file: {lst_filename}")
    pc_to_inst = parse_lst_file(lst_filename)

    if not pc_to_inst:
        print("WARNING: No instructions found in listing file", file=sys.stderr)
        sys.exit(0)

    # Generate checker memory file
    generate_checker_mem(pc_to_inst, mem_filename)

    print("INFO: Checker data generation complete")

if __name__ == "__main__":
    main()

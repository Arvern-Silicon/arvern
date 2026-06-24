#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    gen_symbol_probes.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Generate Verilog hierarchical probes from ELF symbol addresses for benchmark instrumentation.
#----------------------------------------------------------------------------

import re
import sys
import argparse

# Section name mapping
SECTION_NAMES = {
    ".data": "Initialized Data (RAM)",
    ".sdata": "Initialized Data (RAM)",
    ".bss": "Uninitialized Data (RAM, zeroed)",
    ".sbss": "Uninitialized Data (RAM, zeroed)",
    ".stack": "Stack"
}


def friendly_section(section):
    return SECTION_NAMES.get(section, "Other")

def parse_symbols(filename):
    stack_info = []
    variables = []
    regex = re.compile(
        r'^(?P<addr>[0-9a-fA-F]+)\s+\S+\s+(?P<type>\S*)\s+(?P<section>\S+)\s+(?P<size>[0-9a-fA-F]+)\s+(?P<name>\S+)$'
    )
    with open(filename, 'r') as f:
        for line in f:
            match = regex.match(line)
            if match:
                addr = int(match.group('addr'), 16)
                size = int(match.group('size'), 16)
                name = match.group('name')
                section = match.group('section')
                stype = match.group('type')

                # detect stack
                if section == ".stack" or name.startswith("_stack") or name.startswith("stack_top"):
                    stack_info.append((name, size, addr, friendly_section(section)))
                # user variables
                elif stype == "O" and not name.startswith("_"):
                    variables.append((name, size, addr, friendly_section(section)))
    return stack_info, variables

def generate_verilog_probes(header, variables, stack_info, base_addr, filename_out="probes_variables.v"):

    lines = header
    lines.append("\n// Verilog Probes for SRAM variables")
    lines.append("module  probes_var;\n")

    for name, size, addr, _ in variables:
        if addr >= base_addr:
            full_offset = (addr - base_addr)
            offset      = full_offset // 4
            byte_nr     = full_offset % 4
            nibble_nr   = full_offset % 2
            wire_name   = name.lower()
            wire_name   = wire_name.replace(".", "_")
            if wire_name=='reg':
                wire_name = '_reg_'
            if wire_name=='output':
                wire_name = '_output_'
            if wire_name=='input':
                wire_name = '_input_'
            if wire_name=='time':
                wire_name = '_time_'

            if size == 1:
                lines.append(
                    f"    wire [7:0]  {wire_name:<20} = ahb_bus_system_inst.sram_nx_inst.mem[{offset}][{8*(byte_nr+1)-1}:{8*byte_nr}];"
                    f"  // 0x{addr:08X} (1 byte)"
                )
            elif size == 2:
                lines.append(
                    f"    wire [15:0] {wire_name:<20} = ahb_bus_system_inst.sram_nx_inst.mem[{offset}][{16*(nibble_nr+1)-1}:{16*nibble_nr}];"
                    f"  // 0x{addr:08X} (2 bytes)"
                )
            elif size == 4:
                lines.append(
                    f"    wire [31:0] {wire_name:<20} = ahb_bus_system_inst.sram_nx_inst.mem[{offset}];"
                    f"  // 0x{addr:08X} (4 bytes)"
                )
            elif size == 8:
                lines.append(
                    f"    wire [63:0] {wire_name:<20} = {{ahb_bus_system_inst.sram_nx_inst.mem[{offset+1}], "
                    f"ahb_bus_system_inst.sram_nx_inst.mem[{offset}]}};"
                    f"  // 0x{addr:08X} (8 bytes)"
                )
            else:
                lines.append(
                    f"    wire [31:0] {wire_name:<20} = ahb_bus_system_inst.sram_nx_inst.mem[{offset}];"
                    f"  // 0x{addr:08X} ({size} bytes)  // Array, first word only"
                )
    lines.append("\nendmodule;")

    lines.append("\n// Stack probes (first 50 words)")
    lines.append("module  probes_stack;\n")

    # If stack is found, probe first 50 words
    if stack_info:
        stack_addr = None
        for current in stack_info:
            if "end" in current[0]:
                stack_addr = current[2]
        for current in stack_info:
            if "top" in current[0]:
                stack_addr = current[2]

            #print(current)
        #stack_addr = stack_info[0][2]
        # Guard: only emit probes if an end/top stack symbol was found;
        # otherwise stack_addr stays None -> skip (avoids a NameError on a
        # symbol table that has stack entries but no end/top symbol).
        if stack_addr is not None:
            stack_offset = (stack_addr - base_addr) // 4
            for i in range(50):
                lines.append(
                    f"     wire [31:0] stack_{i:<3} = ahb_bus_system_inst.sram_nx_inst.mem[{stack_offset - i:#d}];"
                    f"  // 0x{(stack_addr - i*4):08X}"
                )

    lines.append("\nendmodule;\n\n")

    lines.append("module  probes_stack_alt;\n")

    # If stack is found, probe first 50 words
    if stack_info:
        stack_addr = None
        for current in stack_info:
            if "end" in current[0]:
                stack_addr = current[2]
        for current in stack_info:
            if "top" in current[0]:
                stack_addr = current[2]

            #print(current)
        #stack_addr = stack_info[0][2]
        # Guard: only emit probes if an end/top stack symbol was found;
        # otherwise stack_addr stays None -> skip (avoids a NameError on a
        # symbol table that has stack entries but no end/top symbol).
        if stack_addr is not None:
            stack_offset = (stack_addr - base_addr) // 4
            for i in range(50):
                lines.append(
                    f"     wire [31:0] stack_{(stack_addr - i*4):08X} = ahb_bus_system_inst.sram_nx_inst.mem[{stack_offset - i:#d}];"
                    f"  // 0x{(stack_addr - i*4):08X}"
                )

    lines.append("\nendmodule;\n\n")

    with open(filename_out, "w") as f:
        f.write("\n".join(lines))
    return lines

if __name__ == "__main__":

    # Parse arguments
    parser = argparse.ArgumentParser()
    parser.add_argument('-l','--lst',              required=True)
    parser.add_argument('-o','--out',              required=True)
    parser.add_argument('-b','--sram_base_offset', required=True)
    args = vars(parser.parse_args())

    symbol_file = args['lst']
    stack_info, variables = parse_symbols(symbol_file)

    # Print stack info
    header = []
    header.append("//   === Stack Information ===")
    if stack_info:
        for name, size, addr, section in stack_info:
            header.append(f"//   {name:<30} {size:6} 0x{addr:08X} {section}")
    else:
        header.append("//   No stack symbols found.")

    # Print variables
    header.append("//\n//   === Variables ===")
    if variables:
        header.append(f"//   {'Variable':<30} {'Size':>6} {'Address':>10} {'Type'}")
        header.append("//   "+"-" * 70)
        for name, size, addr, section in sorted(variables, key=lambda x: x[2]):
            header.append(f"//   {name:<30} {size:6} 0x{addr:08X} {section}")
    else:
        header.append("//   No user variables found.")

    # Generate Verilog file
    verilog_lines = generate_verilog_probes(header, variables, stack_info, int(args['sram_base_offset'], 16), args['out'])


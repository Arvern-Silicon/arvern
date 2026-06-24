#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    ihex2mem.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Convert an Intel HEX file into a Verilog $readmemh memory-init file.
#----------------------------------------------------------------------------

import argparse

###############################################################################
#                            Intel-HEX Parser                                 #
###############################################################################
def parse_intel_hex(filename):

    memory = {}              # Address -> Data byte
    upper_addr = 0           # Extended Linear Address (for 32-bit addresses)

    with open(filename, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line.startswith(':'):
                raise ValueError(f"Line {line_num}: Missing ':' start code.")

            # Convert hex string to bytes
            byte_count   = int(line[1:3], 16)
            address      = int(line[3:7], 16)
            record_type  = int(line[7:9], 16)
            data         = bytes.fromhex(line[9:9+2*byte_count])
            checksum     = int(line[9+2*byte_count:9+2*byte_count+2], 16)

            # Verify checksum
            computed_sum = byte_count + (address >> 8) + (address & 0xFF) + record_type + sum(data)
            computed_sum = (computed_sum & 0xFF)
            computed_sum = (~computed_sum + 1) & 0xFF  # Two's complement
            if computed_sum != checksum:
                raise ValueError(f"Line {line_num}: Checksum error.")

            if record_type == 0x00:    # Data record
                full_addr = (upper_addr << 16) + address
                for i, byte in enumerate(data):
                    memory[full_addr + i] = byte

            elif record_type == 0x01:  # End Of File
                break

            elif record_type == 0x04:  # Extended Linear Address
                if byte_count != 2:
                    raise ValueError(f"Line {line_num}: Invalid extended address record.")
                upper_addr = (data[0] << 8) + data[1]

            elif record_type == 0x05:  # Start Linear Address Record
                reset_vector = ""
                for i, byte in enumerate(data):
                    reset_vector = f"{reset_vector}{byte:02X}"
                #print(f"Detected Reset Vector at address 0x{reset_vector}")

            else:
                print(line)
                print(f"Line {line_num}: Unsupported record type {record_type:02X}, skipping.")

    return memory


###############################################################################
#                            Intel-HEX Parser                                 #
###############################################################################
def generate_mem(filename, mem, mem_size, mem_base_offset):

    # First build the memory content with 8B words, removing the base offset
    mem_8B  = {}
    for addr in range(mem_size):
        mem_8B[addr] = 0
        if (addr+mem_base_offset) in mem.keys():
            mem_8B[addr] = mem[addr+mem_base_offset]

    # Now build the memory content with 32B words
    mem_32B   = {}
    addr_list = list(sorted(mem_8B.keys()))
    for addr in range(0, mem_size, 4):
        chunk = addr_list[addr : addr + 4]
        mem_32B[int(addr/4)] = f"{mem_8B[chunk[3]]:02x}{mem_8B[chunk[2]]:02x}{mem_8B[chunk[1]]:02x}{mem_8B[chunk[0]]:02x}"


    # Compute how many characters are needed to represent the address
    nb = len(f"{int((mem_size-1)/4):X}")

    # Format mem lines
    all_lines = []
    new_line  = ""
    line_idx  = 15
    for addr in sorted(mem_32B.keys()):
        if line_idx==15:
            all_lines.append(new_line)
            new_line  = f"@{addr:0{nb}X}  {mem_32B[addr]}"
            line_idx  = 0
        else:
            new_line  = f"{new_line} {mem_32B[addr]}"
            line_idx += 1

    all_lines.append(new_line)

    with open(filename, 'w') as file:
        for line in all_lines:
            file.write(line + '\n')


###############################################################################
#                                   MAIN                                      #
###############################################################################

if __name__ == "__main__":

    # Parse arguments
    parser = argparse.ArgumentParser(description='Description of your program')
    parser.add_argument('-i','--ihex',            help='Description for foo argument', required=True)
    parser.add_argument('-o','--out',             help='Description for bar argument', required=True)
    parser.add_argument('-s','--mem_size',        help='Description for bar argument', required=True)
    parser.add_argument('-b','--mem_base_offset', help='Description for bar argument', required=True)
    args = vars(parser.parse_args())

    # Parse the IHEX file
    mem = parse_intel_hex(filename=args['ihex'])

    print(f"Binary size: {len(mem)}B")

    # Validate memory size
    mem_size = int(args['mem_size'])
    mem_base_offset = int(eval(args['mem_base_offset']))

    if mem:
        min_addr = min(mem.keys())
        max_addr = max(mem.keys())

        # Check if addresses fit within the specified memory region
        if min_addr < mem_base_offset:
            print(f"\nERROR: IHEX file contains address 0x{min_addr:08X} which is below the memory base offset 0x{mem_base_offset:08X}")
            exit(1)

        required_size = max_addr - mem_base_offset + 1
        if required_size > mem_size:
            print(f"\nERROR: IHEX file requires {required_size} bytes (0x{required_size:X})")
            print(f"       Address range: 0x{min_addr:08X} - 0x{max_addr:08X}")
            print(f"       Memory base:   0x{mem_base_offset:08X}")
            print(f"       Specified memory size: {mem_size} bytes (0x{mem_size:X})")
            print(f"       Need to increase --mem_size by at least {required_size - mem_size} bytes")
            exit(1)

    # Generate MEM file
    generate_mem(filename=args['out'], mem=mem, mem_size=mem_size, mem_base_offset=mem_base_offset)

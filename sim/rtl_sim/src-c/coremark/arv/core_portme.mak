# Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Original Author: Shay Gal-on

#File : core_portme.mak

ITERATIONS  = 3

# Flag : OUTFLAG
#	Use this flag to define how to to get an executable (e.g -o)
OUTFLAG= -o
# Load MARCH and toolchain configuration from auto-generated file (based on RTL config)
MARCH_CONFIG_FILE = ../../run/march_config.sh
ifneq ($(wildcard $(MARCH_CONFIG_FILE)),)
    MARCH_STD  := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$MARCH_STD')
    MARCH_COMP := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$MARCH_COMP')
    MABI       := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $${MABI:-ilp32}')
    CC         := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_CC')
    AS         := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_AS')
    LD         := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_LD')
    OBJCOPY    := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_OBJCOPY')
    OBJDUMP    := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_OBJDUMP')
    OBJSIZE    := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_SIZE')
    TC_OPT     := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_OPT')
    BUILD_LIBC            := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $${BUILD_LIBC:-newlib}')
    BUILD_RODATA_LOCATION := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $${BUILD_RODATA_LOCATION:-ROM}')
else
    $(warning march_config.sh not found, using default values)
    MARCH_STD  = rv32im_zicsr
    MARCH_COMP = rv32imc_zicsr
    MABI       = ilp32
    CC         = riscv64-unknown-elf-gcc
    AS         = riscv64-unknown-elf-as
    LD         = riscv64-unknown-elf-ld
    OBJCOPY    = riscv64-unknown-elf-objcopy
    OBJDUMP    = riscv64-unknown-elf-objdump
    OBJSIZE    = riscv64-unknown-elf-size
    TC_OPT     = -O3
endif

# Set architecture based on instruction mode (from environment variable)
ifeq ($(INST_MODE),COMP_MODE)
    MARCH = $(MARCH_COMP)
else
    MARCH = $(MARCH_STD)
endif

# Libc selection (BUILD_LIBC from march_config.sh): 'newlib-nano' picks
# --specs=nano.specs (smaller printf/malloc/softfloat); 'newlib' (default)
# uses the full newlib.
ifeq ($(BUILD_LIBC),newlib-nano)
    LIBC_FLAGS = --specs=nano.specs
else
    LIBC_FLAGS =
endif

# .rodata placement (BUILD_RODATA_LOCATION from march_config.sh): 'SRAM' picks
# the alternate linker script + startup that copies .rodata into SRAM at boot.
# 'ROM' (default) keeps .rodata next to .text. (SRAM variant files land in
# phase d; until then BUILD_RODATA_LOCATION=SRAM will fail to link.)
ifeq ($(BUILD_RODATA_LOCATION),SRAM)
    LINK_SCRIPT_PATH = arv/link_rodata_sram.ld
    STARTUP_FILE     = $(PORT_DIR)/startup_rodata_sram.S
else
    LINK_SCRIPT_PATH = arv/link.ld
    STARTUP_FILE     = $(PORT_DIR)/startup.S
endif

PORT_CFLAGS = -march=$(MARCH) -mabi=$(MABI) $(TC_OPT) -g -nostartfiles -T $(LINK_SCRIPT_PATH) $(STARTUP_FILE) $(LIBC_FLAGS)

FLAGS_STR = "$(PORT_CFLAGS) $(XCFLAGS) $(XLFLAGS) $(LFLAGS_END)"
CFLAGS = $(PORT_CFLAGS) -I$(PORT_DIR) -I. -DFLAGS_STR=\"$(FLAGS_STR)\"
#Flag : LFLAGS_END
#	Define any libraries needed for linking or other flags that should come at the end of the link line (e.g. linker scripts).
#	Note : On certain platforms, the default clock_gettime implementation is supported but requires linking of librt.
#SEPARATE_COMPILE=1
# Flag : SEPARATE_COMPILE
# You must also define below how to create an object file, and how to link.
OBJOUT 	= -o
LFLAGS 	=
ASFLAGS =
OFLAG 	= -o
COUT 	= -c

LFLAGS_END =
# Flag : PORT_SRCS
# 	Port specific source files can be added here
#	You may also need cvt.c if the fcvt functions are not provided as intrinsics by your compiler!
PORT_SRCS = $(PORT_DIR)/core_portme.c $(PORT_DIR)/ee_printf.c
vpath %.c $(PORT_DIR)
vpath %.s $(PORT_DIR)

# Flag : LOAD
#	For a simple port, we assume self hosted compile and run, no load needed.

# Flag : RUN
#	For a simple port, we assume self hosted compile and run, simple invocation of the executable

LOAD = echo "Please set LOAD to the process of loading the executable to the flash"
RUN = echo "Please set LOAD to the process of running the executable (e.g. via jtag, or board reset)"

OEXT = .o
EXE = .elf

$(OPATH)$(PORT_DIR)/%$(OEXT) : %.c
	$(CC) $(CFLAGS) $(XCFLAGS) $(COUT) $< $(OBJOUT) $@

$(OPATH)%$(OEXT) : %.c
	$(CC) $(CFLAGS) $(XCFLAGS) $(COUT) $< $(OBJOUT) $@

$(OPATH)$(PORT_DIR)/%$(OEXT) : %.s
	$(AS) $(ASFLAGS) $< $(OBJOUT) $@

# Target : port_pre% and port_post%
# For the purpose of this simple port, no pre or post steps needed.

.PHONY : port_prebuild port_postbuild port_prerun port_postrun port_preload port_postload

port_postbuild:
	$(OBJCOPY) -O ihex coremark.elf    coremark.ihex
	$(OBJDUMP) -dSt    coremark.elf  > coremark.lst
	$(OBJSIZE) -A      coremark.elf  > coremark.size
	cat coremark.size

port_pre% port_post% :

# FLAG : OPATH
# Path to the output folder. Default - current folder.
OPATH = ./
MKDIR = mkdir -p


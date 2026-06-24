# Makefile for Embench IOT benchmark
# This is a simple wrapper that uses pre-built binaries from embench-iot

BENCHMARK_NAME = embench_aha-mont64
EMBENCH_ELF = ../embench-iot/bd/src/aha-mont64/aha-mont64

# Load MARCH and toolchain configuration from auto-generated file (based on RTL config)
MARCH_CONFIG_FILE = ../../run/march_config.sh
ifneq ($(wildcard $(MARCH_CONFIG_FILE)),)
    MARCH_STD  := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$MARCH_STD')
    MARCH_COMP := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$MARCH_COMP')
    MABI       := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $${MABI:-ilp32}')
    TC_CC      := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_CC')
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
    TC_CC      = riscv64-unknown-elf-gcc
    OBJCOPY    = riscv64-unknown-elf-objcopy
    OBJDUMP    = riscv64-unknown-elf-objdump
    OBJSIZE    = riscv64-unknown-elf-size
    TC_OPT     = -O3
    BUILD_LIBC            = newlib
    BUILD_RODATA_LOCATION = ROM
endif

# Set architecture based on instruction mode (from environment variable)
ifeq ($(INST_MODE),COMP_MODE)
    MARCH = $(MARCH_COMP)
else
    MARCH = $(MARCH_STD)
endif

.PHONY: all clean rebuild_embench $(BENCHMARK_NAME).elf $(BENCHMARK_NAME).ihex $(BENCHMARK_NAME).lst $(BENCHMARK_NAME).size

all: $(BENCHMARK_NAME).elf $(BENCHMARK_NAME).ihex $(BENCHMARK_NAME).lst $(BENCHMARK_NAME).size

# Force recompilation of all Embench benchmarks from source every time
rebuild_embench:
	@echo "Rebuilding all Embench benchmarks from source..."
	@cd ../embench-iot && MARCH_STD='$(MARCH_STD)' MARCH_COMP='$(MARCH_COMP)' INST_MODE='$(INST_MODE)' TC_CC='$(TC_CC)' TC_OPT='$(TC_OPT)' MABI='$(MABI)' BUILD_LIBC='$(BUILD_LIBC)' BUILD_RODATA_LOCATION='$(BUILD_RODATA_LOCATION)' python3 build_all.py --arch riscv32 --board arvern_iverilog --clean
	@echo "Embench rebuild complete."


$(BENCHMARK_NAME).elf: rebuild_embench
	@echo "Using pre-built Embench binary: $(EMBENCH_ELF)"
	@if [ ! -f "$(EMBENCH_ELF)" ]; then \
		echo "ERROR: Embench binary not found."; \
		exit 1; \
	fi
	@ln -sf $(EMBENCH_ELF) $(BENCHMARK_NAME).elf
	@echo "Created symlink: $(BENCHMARK_NAME).elf -> $(EMBENCH_ELF)"

$(BENCHMARK_NAME).ihex: $(BENCHMARK_NAME).elf
	@$(OBJCOPY) -O ihex $(BENCHMARK_NAME).elf $(BENCHMARK_NAME).ihex
	@echo "Generated $(BENCHMARK_NAME).ihex"

$(BENCHMARK_NAME).lst: $(BENCHMARK_NAME).elf
	@$(OBJDUMP) -dSt $(BENCHMARK_NAME).elf > $(BENCHMARK_NAME).lst
	@echo "Generated $(BENCHMARK_NAME).lst"

$(BENCHMARK_NAME).size: $(BENCHMARK_NAME).elf
	@$(OBJSIZE) -A   $(BENCHMARK_NAME).elf > $(BENCHMARK_NAME).size
	@echo "Generated $(BENCHMARK_NAME).size"

clean:
	@rm -f $(BENCHMARK_NAME).elf $(BENCHMARK_NAME).ihex $(BENCHMARK_NAME).lst $(BENCHMARK_NAME).size

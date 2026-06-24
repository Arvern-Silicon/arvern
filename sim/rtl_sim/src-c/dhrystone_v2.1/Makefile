# makfile configuration
NAME            = dhrystone_v2.1
OBJECTS         = dhry_1.o dhry_2.o arv_func.o mylib/cprintf.o

# Compiler performance option:
#                              -O0 (No optimization)
#                              -O1 (Optimize)
#                              -O2 (Optimize more)
#                              -O3 (Optimize even more)
#                              -Os (Optimize for size)
#                              -Oz (Optimize for size even more)
# disable some warnings specific to the Dhrystone code
#WARNINGS        =  -Wall -Wextra
WARNINGS        =  -Wall

# Load MARCH and toolchain configuration from auto-generated file (based on RTL config)
MARCH_CONFIG_FILE = ../../run/march_config.sh
ifneq ($(wildcard $(MARCH_CONFIG_FILE)),)
    MARCH_STD  := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$MARCH_STD')
    MARCH_COMP := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$MARCH_COMP')
    MABI       := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $${MABI:-ilp32}')
    CC         := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_CC')
    OBJCOPY    := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_OBJCOPY')
    OBJDUMP    := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_OBJDUMP')
    OBJSIZE    := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_SIZE')
    TC_OPT     := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $$TC_OPT')
    BUILD_LIBC            := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $${BUILD_LIBC:-newlib}')
    BUILD_RODATA_LOCATION := $(shell bash -c 'source $(MARCH_CONFIG_FILE) && echo $${BUILD_RODATA_LOCATION:-ROM}')
else
    $(warning march_config.sh not found, using default values)
    MARCH_STD  = rv32i_zicsr
    MARCH_COMP = rv32ic_zicsr
    MABI       = ilp32
    CC         = riscv64-unknown-elf-gcc
    OBJCOPY    = riscv64-unknown-elf-objcopy
    OBJDUMP    = riscv64-unknown-elf-objdump
    OBJSIZE    = riscv64-unknown-elf-size
    TC_OPT     = -O3
endif

PORT_CFLAGS    = $(TC_OPT)

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
    LINK_SCRIPT  = link_rodata_sram.ld
    STARTUP_FILE = startup_rodata_sram.S
else
    LINK_SCRIPT  = link.ld
    STARTUP_FILE = startup.S
endif

# Select flags
CFLAGS  = -march=$(MARCH) -mabi=$(MABI) -g -nostartfiles ${WARNINGS} $(PORT_CFLAGS) -std=gnu89 $(LIBC_FLAGS)


.PHONY: all FORCE clean download dist

#all should be the first target. it's built when make is runwithout args
all: clean ${NAME}.elf ${NAME}.ihex ${NAME}.lst ${NAME}.size

#configure the next line if you want to use the serial download
download: download-uart

#additional rules for files
${NAME}.elf: ${OBJECTS}
	${CC} ${CFLAGS} -T $(LINK_SCRIPT) $(STARTUP_FILE) -o $@ ${OBJECTS}

${NAME}.ihex: ${NAME}.elf
	${OBJCOPY} -O ihex $^ $@

${NAME}.lst: ${NAME}.elf
	${OBJDUMP} -dSt $^ >$@

${NAME}.size: ${NAME}.elf
	${OBJSIZE} -A   $^ >$@

download-uart: all
	arverni-loader.tcl -device /dev/ttyUSB0 -baudrate 115200 ${NAME}.elf

clean:
	rm -f ${NAME} ${NAME}.ihex ${NAME}.lst ${NAME}.elf ${NAME}.size *.o mylib/*.o

#backup archive
dist:
	tar czf dist.tgz *.c *.h *.txt makefile

#dummy target as dependecy if something has to be build everytime
FORCE:

#project dependencies
dhry_1.o: dhry_1.c
dhry_2.o: dhry_2.c
arv_func.o: arv_func.c
mylib/cprintf.o: mylib/cprintf.c

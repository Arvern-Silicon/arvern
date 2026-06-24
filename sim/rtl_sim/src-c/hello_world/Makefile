
NAME    = hello_world

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
else
    $(warning march_config.sh not found, using default values)
    MARCH_STD  = rv32i
    MARCH_COMP = rv32ic
    MABI       = ilp32
    CC         = riscv64-unknown-elf-gcc
    OBJCOPY    = riscv64-unknown-elf-objcopy
    OBJDUMP    = riscv64-unknown-elf-objdump
    OBJSIZE    = riscv64-unknown-elf-size
    TC_OPT     = -O2
endif

# Set architecture based on instruction mode (from environment variable)
ifeq ($(INST_MODE),COMP_MODE)
    MARCH = $(MARCH_COMP)
else
    MARCH = $(MARCH_STD)
endif

CFLAGS  = -march=$(MARCH) -mabi=$(MABI) -nostartfiles -Wall -Wextra $(TC_OPT)

all: ${NAME}.elf ${NAME}.ihex ${NAME}.lst ${NAME}.size

${NAME}.elf: mylib/my_func.c mylib/cprintf.c main.c startup.S link.ld
	${CC} ${CFLAGS} -T link.ld startup.S mylib/my_func.c mylib/cprintf.c main.c -o ${NAME}.elf

${NAME}.ihex: ${NAME}.elf
	${OBJCOPY} -O ihex $^ $@

${NAME}.lst: ${NAME}.elf
	${OBJDUMP} -dSt $^ >$@

${NAME}.size: ${NAME}.elf
	${OBJSIZE}  $^ >$@

clean:
	rm -f ${NAME}.elf ${NAME}.ihex ${NAME}.lst ${NAME}.size

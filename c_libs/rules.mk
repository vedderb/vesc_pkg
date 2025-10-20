# ======================================================================
# Unified Makefile for STM32F4 (default) and ESP32-C3 (minimal)
# ======================================================================

# ------------------------- Arch selection ------------------------------
ARCH ?= stm32
ifeq ($(ESP_PLATFORM),true)
  ARCH := esp32
endif

# CROSS prefix per arch (override if you like)
ifeq ($(ARCH),stm32)

CC = arm-none-eabi-gcc
LD = arm-none-eabi-gcc
OBJDUMP = arm-none-eabi-objdump
OBJCOPY = arm-none-eabi-objcopy
PYTHON = python3

STLIB_PATH = $(VESC_C_LIB_PATH)/stdperiph_stm32f4/

ifeq ($(USE_STLIB),yes)
	SOURCES += \
		$(STLIB_PATH)/src/misc.c \
		$(STLIB_PATH)/src/stm32f4xx_adc.c \
		$(STLIB_PATH)/src/stm32f4xx_dma.c \
		$(STLIB_PATH)/src/stm32f4xx_exti.c \
		$(STLIB_PATH)/src/stm32f4xx_flash.c \
		$(STLIB_PATH)/src/stm32f4xx_rcc.c \
		$(STLIB_PATH)/src/stm32f4xx_syscfg.c \
		$(STLIB_PATH)/src/stm32f4xx_tim.c \
		$(STLIB_PATH)/src/stm32f4xx_iwdg.c \
		$(STLIB_PATH)/src/stm32f4xx_wwdg.c
endif

UTILS_PATH = $(VESC_C_LIB_PATH)/utils/

SOURCES += $(UTILS_PATH)/rb.c
SOURCES += $(UTILS_PATH)/utils.c

OBJECTS = $(SOURCES:.c=.so)

ifeq ($(USE_OPT),)
	USE_OPT =
endif

CFLAGS = -fpic -Os -Wall -Wextra -Wundef -std=gnu99 -I$(VESC_C_LIB_PATH)
CFLAGS += -I$(STLIB_PATH)/CMSIS/include -I$(STLIB_PATH)/CMSIS/ST -I$(UTILS_PATH)/
CFLAGS += -fomit-frame-pointer -falign-functions=16 -mthumb
CFLAGS += -fsingle-precision-constant -Wdouble-promotion
CFLAGS += -mfloat-abi=hard -mfpu=fpv4-sp-d16 -mcpu=cortex-m4
CFLAGS += -fdata-sections -ffunction-sections
CFLAGS += -DIS_VESC_LIB
CFLAGS += $(USE_OPT)

ifeq ($(USE_STLIB),yes)
	CFLAGS += -DUSE_STLIB -I$(STLIB_PATH)/inc
endif

LDFLAGS = -nostartfiles -static -mfloat-abi=hard -mfpu=fpv4-sp-d16 -mcpu=cortex-m4
LDFLAGS += -lm -Wl,--gc-sections,--undefined=init
LDFLAGS += -T $(VESC_C_LIB_PATH)/link.ld

.PHONY: default all clean

default: $(TARGET)
all: default

%.so: %.c
	$(CC) $(CFLAGS) -c $< -o $@

.PRECIOUS: $(TARGET) $(OBJECTS)

$(TARGET): $(OBJECTS)
	$(LD) $(OBJECTS) $(LDFLAGS) -o $@.elf
	$(OBJDUMP) -D $@.elf > $@.list
	$(OBJCOPY) -O binary $@.elf $@.bin --gap-fill 0x00
	$(PYTHON) $(VESC_C_LIB_PATH)/conv.py -f $@.bin -n $@ > $@.lisp

clean:
	rm -f $(OBJECTS) $(TARGET).elf $(TARGET).list $(TARGET).lisp $(TARGET).bin
else ifeq ($(ARCH),esp32)
# ======================================================================
#  ESP32-C3   Native-lib rules (PIC blob for LispBM)
#  - RISC-V (rv32imc / ilp32, software float)
#  - Section GC + (optional) LTO
#  - Generates: .elf, .bin (with header), .lisp, .list, .map
# ======================================================================

# ---- toolchain (override CROSS if needed) -----------------------------
CROSS     ?= riscv32-esp-elf-
CC        := $(CROSS)gcc
AR        := $(CROSS)ar
OBJDUMP   := $(CROSS)objdump
OBJCOPY   := $(CROSS)objcopy
NM        := $(CROSS)nm
READELF   := $(CROSS)readelf
PYTHON    ?= python3

# ---- project defaults (override if you like) --------------------------
TARGET   ?= package_lib
SOURCES  ?=

# ---- paths ------------------------------------------------------------
VESC_C_LIB_PATH ?= ../..
LINKER_SCRIPT   ?= $(VESC_C_LIB_PATH)/link_esp32.ld

# ---- RVfplib (required) -----------------------------------------------
# Expect RVfplib sources at $(VESC_C_LIB_PATH)RVfplib/
# Always produce and link $(VESC_C_LIB_PATH)librvfp.a
RVFP_SRC_DIR   := $(VESC_C_LIB_PATH)/RVfplib
RVFP_VARIANT   ?= rvfp_nd_s
RVFP_LIB := $(RVFP_SRC_DIR)/build/lib/lib$(RVFP_VARIANT).a

# ---- toggles ----------------------------------------------------------
USE_LTO      ?= no        # Use LTO if your riscv32-esp-elf toolchain supports it
VERBOSE_LINK ?= yes       # Emit a link map and (optionally) GC diagnostics

# Exported entry symbols (kept even with GC/LTO)
ENTRY_SYMS ?= init

# ---- common flags -----------------------------------------------------
CFLAGS_COMMON = \
  -Os -Wall -Wextra -Wundef -std=gnu99 \
  -ffunction-sections -fdata-sections \
  -fPIC -fvisibility=hidden \
  -I$(VESC_C_LIB_PATH) -DIS_VESC_LIB \
  -DESP_PLATFORM=true \
  -march=rv32imc_zicsr_zifencei -mabi=ilp32 \
  -mno-save-restore \
  -mcmodel=medany \
  -msmall-data-limit=0 \
  -Wdouble-promotion -Wfloat-conversion \
  -Werror=implicit-function-declaration \
  -Werror=incompatible-pointer-types \
  -Werror=int-conversion \
  -Werror=return-type

ifeq ($(USE_LTO),yes)
  CFLAGS_COMMON += -flto
  LDFLAGS_LTO   = -flto
else
  LDFLAGS_LTO   =
endif

# Dependency generation
CFLAGS_DEPS = -MMD

CFLAGS += $(CFLAGS_COMMON) $(CFLAGS_DEPS)

# ---- link flags -------------------------------------------------------
LDFLAGS = \
  -static \
  -Wl,--gc-sections \
  -Wl,--no-relax \
  -Wl,--no-warn-rwx-segments \
  -T $(LINKER_SCRIPT) \
  -Wl,-Map=$(TARGET).map \
  $(LDFLAGS_LTO)

# Keep required entry points
LDFLAGS += $(foreach s,$(ENTRY_SYMS),-Wl,--undefined=$(s))

# Helpful traces (you can comment these out if too chatty)
LDFLAGS += -Wl,--trace-symbol=__mulsf3 -Wl,--trace-symbol=__divsf3
LDFLAGS += -Wl,--trace-symbol=__addsf3 -Wl,--trace-symbol=__subsf3
LDFLAGS += -Wl,--trace-symbol=__eqsf2  -Wl,--trace-symbol=__nesf2

# Diagnostics
ifeq ($(VERBOSE_LINK),yes)
  # Uncomment to see stripped sections:
  # LDFLAGS += -Wl,--print-gc-sections
endif

# ---- required soft-float libs (group avoids cyclic deps) --------------
# Always link the locally-built librvfp.a first
LDGROUP := -Wl,--start-group $(RVFP_LIB) -Wl,--end-group

# ---- derived names ----------------------------------------------------
OBJECTS := $(SOURCES:.c=.o)
DEPS    := $(SOURCES:.c=.d)
ELF     := $(TARGET).elf
BIN     := $(TARGET).bin
LISP    := $(TARGET).lisp
LIST    := $(TARGET).list
MAP     := $(TARGET).map

# ---- phony ------------------------------------------------------------
.PHONY: default all clean nmcheck disasm rvfp

default: $(TARGET)
all:     default

# ---- auto-build librvfp.a (no checks; assumes RVfplib exists) --------
$(RVFP_LIB):
	@echo ">> Building RVfplib ($(RVFP_VARIANT)) with $(CROSS)"
	$(MAKE) -C "$(RVFP_SRC_DIR)" \
		RISCV_PREFIX=$(CROSS) ARCH=rv32imc ABI=ilp32 \
		CC=$(CC) AR=$(AR) NM=$(NM) OBJDUMP=$(OBJDUMP)

rvfp: $(RVFP_LIB)

# ---- build rules ------------------------------------------------------
$(TARGET): $(ELF)
	$(OBJCOPY) -O binary $< $@.temp
	echo 'cafebabe' | xxd -r -p > $@.bin
	cat $@.temp >> $@.bin
	rm $@.temp
	$(PYTHON) $(VESC_C_LIB_PATH)/conv.py -f $@.bin -n $(TARGET) > $(LISP)

$(ELF): $(OBJECTS) $(RVFP_LIB)
	$(CC) $(OBJECTS) $(CFLAGS) $(LDFLAGS) $(LDGROUP) -o $@
	$(OBJDUMP) -D $@ > $(LIST)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(DEPS) $(ELF) $(BIN) $(LISP) $(LIST) $(MAP) $(ADD_TO_CLEAN)

# ---- helpers ----------------------------------------------------------
nmcheck: $(ELF)
	@echo "# soft-float helpers present (T=defined, U=undefined):"
	$(NM) $(ELF) | egrep '__subsf3|__addsf3|__mulsf3|__divsf3|__eqsf2|__nesf2' || true
	@echo
	@echo "# relocations against helpers (should usually be none):"
	$(READELF) -r $(ELF) | egrep '__subsf3|__addsf3|__mulsf3|__divsf3|__eqsf2|__nesf2' || true

disasm: $(ELF)
	$(OBJDUMP) -drwC --disassemble=buffer_get_float16 $(ELF) | sed -n '1,200p'

# Include auto-generated dependencies
-include $(DEPS)

else
  $(error Unknown ARCH=$(ARCH); use stm32 or esp32)
endif
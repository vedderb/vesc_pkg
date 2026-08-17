# ARCH is stm32 (VESC motor controllers) or esp32 (VESC Express). ESP builds
# are per-chip - a native lib only runs on the chip it was built for - so the
# binary carries the target in its name.
ARCH ?= stm32

ifeq ($(ARCH),esp32)
ESP_TARGET ?= esp32c3
TARGET = boosted_$(ESP_TARGET)
else
TARGET = boosted_stm32
endif

SOURCES = code.c

VESC_C_LIB_PATH=../../c_libs/
include $(VESC_C_LIB_PATH)rules.mk

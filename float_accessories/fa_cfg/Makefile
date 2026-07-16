ESP_TARGET ?= esp32c3

ARCH = esp32
TARGET = fa_cfg_$(ESP_TARGET)

SOURCES = code.c buffer.c ../conf/confparser.c ../conf/confxml.c

CFLAGS += -I. -I../conf

VESC_C_LIB_PATH=../../c_libs/
include $(VESC_C_LIB_PATH)rules.mk

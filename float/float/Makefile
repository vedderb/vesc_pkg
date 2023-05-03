VESC_TOOL ?= vesc_tool

TARGET = float

SOURCES = float.c conf/buffer.c conf/confparser.c conf/confxml.c

ADD_TO_CLEAN = conf/confxml.h conf/confxml.c

VESC_C_LIB_PATH = ../../c_libs/
include $(VESC_C_LIB_PATH)rules.mk

float.c: conf/confparser.h conf/confxml.h

conf/confparser.h conf/confxml.h conf/confxml.c &: conf/settings.xml
	$(VESC_TOOL) --xmlConfToCode conf/settings.xml

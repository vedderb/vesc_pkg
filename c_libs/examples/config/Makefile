VESC_TOOL ?= vesc_tool

TARGET = config

SOURCES = code.c conf/buffer.c conf/confparser.c conf/confxml.c

ADD_TO_CLEAN = conf/conf_default.h conf/confparser.h conf/confparser.c conf/confxml.h conf/confxml.c

VESC_C_LIB_PATH = ../../
include $(VESC_C_LIB_PATH)rules.mk

code.c: conf/confparser.h conf/confxml.h

conf/conf_default.h conf/confparser.c conf/confparser.h conf/confxml.h conf/confxml.c &: conf/settings.xml
	$(VESC_TOOL) --xmlConfToCode conf/settings.xml

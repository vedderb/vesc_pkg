VESC_TOOL ?= vesc_tool

TARGET = balance

SOURCES = balance.c conf/buffer.c conf/confparser.c conf/confxml.c

ADD_TO_CLEAN = conf/confparser.h conf/confxml.h conf/confxml.c

balance.c: conf/confparser.h conf/confxml.h

VESC_C_LIB_PATH=../../c_libs/
include $(VESC_C_LIB_PATH)rules.mk

conf/confparser.h conf/confxml.h conf/confxml.c &: conf/settings.xml
	$(VESC_TOOL) --xmlConfToCode conf/settings.xml

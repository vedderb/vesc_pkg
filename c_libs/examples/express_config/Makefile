# Custom config example for the VESC Express. Native libs only run on the
# chip they were built for, so the library is built once per target.
#
#   make        - generate the conf sources and build the lib for all chips
#   make pkg    - also build express_config.vescpkg
#   make clean
#
# Both the conf generation and the package build need vesc_tool in the path
# (or VESC_TOOL=/path/to/vesc_tool).

VESC_TOOL ?= vesc_tool
ESP_TARGETS = esp32c3 esp32c6 esp32s3 esp32p4

# Emitted by 'vesc_tool --xmlConfToCode conf/settings.xml' - not in git.
GENERATED = conf/confparser.c conf/confparser.h conf/confxml.c \
	conf/confxml.h conf/conf_default.h

ifdef ESP_TARGET
# Recursive invocation: build one target's lib via the common rules.
ARCH = esp32
TARGET = express_config_$(ESP_TARGET)
SOURCES = code.c conf/buffer.c conf/confparser.c conf/confxml.c

CFLAGS += -Iconf

VESC_C_LIB_PATH=../../
include $(VESC_C_LIB_PATH)rules.mk
else
all: libs

# confparser/confxml/conf_default are generated from the parameter
# description. Regenerate them whenever the XML changes.
$(GENERATED) &: conf/settings.xml
	cd conf && $(VESC_TOOL) --xmlConfToCode settings.xml

# Objects are not target-suffixed, so they are removed between targets.
libs: $(GENERATED)
	for t in $(ESP_TARGETS); do \
		rm -f *.o *.d conf/*.o conf/*.d; \
		$(MAKE) ESP_TARGET=$$t || exit 1; \
	done
	rm -f *.o *.d conf/*.o conf/*.d

pkg: libs
	$(VESC_TOOL) --buildPkg "express_config.vescpkg:express_config.lisp::0:README.md:Express Custom Config Example"

clean:
	for t in $(ESP_TARGETS); do \
		$(MAKE) ESP_TARGET=$$t clean; \
	done
	rm -f *.o *.d conf/*.o conf/*.d
	rm -f $(GENERATED) express_config.vescpkg

.PHONY: all libs pkg clean
endif

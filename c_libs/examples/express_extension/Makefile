# Native lib example for the VESC Express. Native libs only run on the
# chip they were built for, so the library is built once per target.
#
#   make        - build the lib for all supported chips
#   make pkg    - also build express_extension.vescpkg (needs vesc_tool)
#   make clean

VESC_TOOL ?= vesc_tool
ESP_TARGETS = esp32c3 esp32c6 esp32s3 esp32p4

ifdef ESP_TARGET
# Recursive invocation: build one target's lib via the common rules.
ARCH = esp32
TARGET = express_extension_$(ESP_TARGET)
SOURCES = code.c

VESC_C_LIB_PATH=../../
include $(VESC_C_LIB_PATH)rules.mk
else
all: libs

# Objects are not target-suffixed, so they are removed between targets.
libs:
	for t in $(ESP_TARGETS); do \
		rm -f *.o *.d; \
		$(MAKE) ESP_TARGET=$$t || exit 1; \
	done
	rm -f *.o *.d

pkg: libs
	$(VESC_TOOL) --buildPkg "express_extension.vescpkg:express_extension.lisp::0:README.md:Express Native Lib Example"

clean:
	for t in $(ESP_TARGETS); do \
		$(MAKE) ESP_TARGET=$$t clean; \
	done
	rm -f express_extension.vescpkg

.PHONY: all libs pkg clean
endif

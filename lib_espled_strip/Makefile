VESC_TOOL ?= vesc_tool
PYTHON ?= python3

# One binary per chip - native libs only run on the chip they were built for.
ESP_TARGETS = esp32c3 esp32c6 esp32s3 esp32p4

all: espled_strip.vescpkg

espled_strip.vescpkg: libs
	$(VESC_TOOL) --buildPkg "espled_strip.vescpkg:espled_strip.lisp:ui.qml:0:README.md:ESPLED Strip"

# Shared lisp constants, generated from the C enums so consumers cannot drift.
defs: espled_defs.lisp
espled_defs.lisp: gen_defs.py espled_strip/code.c
	$(PYTHON) gen_defs.py

# Objects are not target-suffixed, so they are removed between targets.
libs: espled_defs.lisp
	for t in $(ESP_TARGETS); do \
		rm -f espled_strip/*.o espled_strip/*.d; \
		$(MAKE) -C espled_strip ESP_TARGET=$$t || exit 1; \
	done
	rm -f espled_strip/*.o espled_strip/*.d

clean:
	rm -f espled_strip.vescpkg
	for t in $(ESP_TARGETS); do \
		$(MAKE) -C espled_strip ESP_TARGET=$$t clean; \
	done

.PHONY: all clean libs defs

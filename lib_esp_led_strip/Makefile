VESC_TOOL ?= vesc_tool
PYTHON ?= python3

# One binary per chip - native libs only run on the chip they were built for.
ESP_TARGETS = esp32c3 esp32c6 esp32s3 esp32p4

all: esp_led_strip.vescpkg

esp_led_strip.vescpkg: libs
	$(VESC_TOOL) --buildPkg "esp_led_strip.vescpkg:esp_led_strip.lisp:ui.qml:0:README.md:ESP LED Strip"

# Shared lisp constants, generated from the C enums so consumers cannot drift.
defs: esp_led_defs.lisp
esp_led_defs.lisp: gen_defs.py esp_led_strip/code.c
	$(PYTHON) gen_defs.py

# Objects are not target-suffixed, so they are removed between targets.
libs: esp_led_defs.lisp
	for t in $(ESP_TARGETS); do \
		rm -f esp_led_strip/*.o esp_led_strip/*.d; \
		$(MAKE) -C esp_led_strip ESP_TARGET=$$t || exit 1; \
	done
	rm -f esp_led_strip/*.o esp_led_strip/*.d

clean:
	rm -f esp_led_strip.vescpkg
	for t in $(ESP_TARGETS); do \
		$(MAKE) -C esp_led_strip ESP_TARGET=$$t clean; \
	done

.PHONY: all clean libs defs

VESC_TOOL ?= vesc_tool

# One binary per chip - a native lib only runs on the chip it was built for.
ESP_TARGETS = esp32c3 esp32c6 esp32s3 esp32p4

all: boosted_doctor.vescpkg

boosted_doctor.vescpkg: libs pkgdesc.qml README.md ui.qml code.lbm
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

# Objects are not target-suffixed, so they are removed between targets.
libs:
	for t in $(ESP_TARGETS); do \
		rm -f boosted/*.o boosted/*.d; \
		$(MAKE) -C boosted ARCH=esp32 ESP_TARGET=$$t || exit 1; \
	done
	rm -f boosted/*.o boosted/*.d
	$(MAKE) -C boosted ARCH=stm32

clean:
	rm -f boosted_doctor.vescpkg
	for t in $(ESP_TARGETS); do \
		$(MAKE) -C boosted ARCH=esp32 ESP_TARGET=$$t clean; \
	done
	$(MAKE) -C boosted ARCH=stm32 clean
	rm -f boosted/*.o boosted/*.d

.PHONY: all clean libs

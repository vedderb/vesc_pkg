VESC_TOOL ?= vesc_tool

# One binary per chip - a native lib only runs on the chip it was built for.
ESP_TARGETS = esp32c3 esp32c6 esp32s3 esp32p4

# Emitted by 'vesc_tool --xmlConfToCode conf/settings.xml' - not in git.
GENERATED = boosted/conf/confparser.c boosted/conf/confparser.h \
	boosted/conf/confxml.c boosted/conf/confxml.h \
	boosted/conf/conf_default.h

OBJ = boosted/*.o boosted/*.d boosted/*.so \
	boosted/conf/*.o boosted/conf/*.d boosted/conf/*.so

all: boosted_doctor.vescpkg

boosted_doctor.vescpkg: libs pkgdesc.qml README.md ui.qml code.lbm
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

# The custom config parser and the compiled settings XML. Regenerated
# whenever the parameter description changes.
conf: $(GENERATED)

$(GENERATED) &: boosted/conf/settings.xml
	cd boosted/conf && $(VESC_TOOL) --xmlConfToCode settings.xml

# Objects are not target-suffixed, so they are removed between targets.
libs: $(GENERATED)
	for t in $(ESP_TARGETS); do \
		rm -f $(OBJ); \
		$(MAKE) -C boosted ARCH=esp32 ESP_TARGET=$$t || exit 1; \
	done
	rm -f $(OBJ)
	$(MAKE) -C boosted ARCH=stm32

clean:
	rm -f boosted_doctor.vescpkg
	for t in $(ESP_TARGETS); do \
		$(MAKE) -C boosted ARCH=esp32 ESP_TARGET=$$t clean; \
	done
	$(MAKE) -C boosted ARCH=stm32 clean
	rm -f $(OBJ) $(GENERATED)

.PHONY: all clean conf libs

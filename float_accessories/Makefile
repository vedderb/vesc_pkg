VESC_TOOL ?= vesc_tool
PYTHON ?= python3

# One binary per chip - native libs only run on the chip they were built for.
ESP_TARGETS = esp32c3 esp32c6 esp32s3 esp32p4

# Single source of truth for the package version. It is stamped into the
# generated README (build info) and into the About box in the UI.
VERSION=`cat version`

all: float_accessories.vescpkg

# Regenerate the config sources from conf/gen_conf.py when it changed.
conf/settings.xml fa_cfg/datatypes.h fa_cfg/conf_lookup.h &: conf/gen_conf.py
	$(PYTHON) conf/gen_conf.py

conf/confparser.c conf/confparser.h conf/confxml.c conf/confxml.h conf/conf_default.h &: conf/settings.xml
	cd conf && $(VESC_TOOL) --xmlConfToCode settings.xml

# The esp_led_strip lib binaries are imported from ../lib_esp_led_strip -
# build them there first.
esp_led_libs:
	$(MAKE) -C ../lib_esp_led_strip libs

fa_cfg_libs: conf/confparser.c fa_cfg/datatypes.h
	for t in $(ESP_TARGETS); do \
		rm -f fa_cfg/*.o fa_cfg/*.d conf/*.o conf/*.d; \
		$(MAKE) -C fa_cfg ESP_TARGET=$$t || exit 1; \
	done
	rm -f fa_cfg/*.o fa_cfg/*.d conf/*.o conf/*.d

# Built from pkgdesc.qml rather than a --buildPkg string, so the package can
# declare isCompatible and refuse non-Express hardware. --testPkgDesc runs that
# function at build time against a fake device, so a broken check is caught here
# instead of on a user's bench.
README-gen.md: README.md version
	cp $< $@
	echo "" >> $@
	echo "### Build Info" >> $@
	echo "" >> $@
	echo "- Version: ${VERSION}" >> $@
	echo "- Build Date: `date --rfc-3339=seconds`" >> $@
	echo "- Git Commit: #`git rev-parse --short HEAD`" >> $@

# The About box is generated from README-gen.md, so it cannot drift from the
# package store description. gen_ui.py does the substitution (not sed, which
# would need escaping for arbitrary markdown).
ui.qml: ui.qml.in version README-gen.md gen_ui.py
	$(PYTHON) gen_ui.py

float_accessories.vescpkg: esp_led_libs fa_cfg_libs pkgdesc.qml README-gen.md ui.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml \
		--testPkgDesc 'custom:Devkit C3' \
		--testPkgDesc 'custom:Avaspark RGB V3' \
		--testPkgDesc 'vesc bms:VESC BMS' \
		--testPkgDesc 'vesc:test'

clean:
	rm -f float_accessories.vescpkg
	rm -f README-gen.md ui.qml
	for t in $(ESP_TARGETS); do \
		$(MAKE) -C fa_cfg ESP_TARGET=$$t clean; \
	done
	$(MAKE) -C ../lib_esp_led_strip clean

.PHONY: all clean esp_led_libs fa_cfg_libs

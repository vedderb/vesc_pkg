VESC_TOOL ?= vesc_tool
PYTHON ?= python3

# One binary per chip - native libs only run on the chip they were built for.
ESP_TARGETS = esp32c3 esp32c6 esp32s3 esp32p4

all: float_accessories.vescpkg

# Regenerate the config sources from conf/gen_conf.py when it changed.
conf/settings.xml fa_cfg/datatypes.h fa_cfg/conf_lookup.h &: conf/gen_conf.py
	$(PYTHON) conf/gen_conf.py

conf/confparser.c conf/confparser.h conf/confxml.c conf/confxml.h conf/conf_default.h &: conf/settings.xml
	cd conf && $(VESC_TOOL) --xmlConfToCode settings.xml

# The espled_strip lib binaries are imported from ../lib_espled_strip -
# build them there first.
espled_libs:
	$(MAKE) -C ../lib_espled_strip libs

fa_cfg_libs: conf/confparser.c fa_cfg/datatypes.h
	for t in $(ESP_TARGETS); do \
		rm -f fa_cfg/*.o fa_cfg/*.d conf/*.o conf/*.d; \
		$(MAKE) -C fa_cfg ESP_TARGET=$$t || exit 1; \
	done
	rm -f fa_cfg/*.o fa_cfg/*.d conf/*.o conf/*.d

float_accessories.vescpkg: espled_libs fa_cfg_libs
	$(VESC_TOOL) --buildPkg "float_accessories.vescpkg:float_accessories.lisp:ui.qml:0:README.md:Float Accessories"

clean:
	rm -f float_accessories.vescpkg
	for t in $(ESP_TARGETS); do \
		$(MAKE) -C fa_cfg ESP_TARGET=$$t clean; \
	done
	$(MAKE) -C ../lib_espled_strip clean

.PHONY: all clean espled_libs fa_cfg_libs

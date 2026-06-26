VESC_TOOL ?= vesc_tool

all: mt6701_config.vescpkg

mt6701_config.vescpkg:
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vbms32' --testPkgDesc 'vesc:test'

clean:
	rm -f mt6701_config.vescpkg

.PHONY: all clean

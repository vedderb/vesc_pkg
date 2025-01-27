VESC_TOOL ?= vesc_tool

all: vbms32_micro.vescpkg

vbms32_micro.vescpkg: pkgdesc.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vbms32' --testPkgDesc 'vesc:vbms32'

clean:
	rm -f vbms32_micro.vescpkg

.PHONY: all clean

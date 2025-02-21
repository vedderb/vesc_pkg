VESC_TOOL ?= vesc_tool

all: vbms32.vescpkg

vbms32.vescpkg: pkgdesc.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vbms32' --testPkgDesc 'vesc:vbms32' --testPkgDesc 'custom:vbms32:micro'

clean:
	rm -f vbms32.vescpkg

.PHONY: all clean

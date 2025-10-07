VESC_TOOL ?= vesc_tool

all: logui.vescpkg

logui.vescpkg:
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'custom:vbms32' --testPkgDesc 'vesc:test'

clean:
	rm -f logui.vescpkg

.PHONY: all clean

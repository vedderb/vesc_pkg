VESC_TOOL ?= vesc_tool

all: slcan_adapter.vescpkg

slcan_adapter.vescpkg: pkgdesc.qml slcan.lisp README.md
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

clean:
	rm -f slcan_adapter.vescpkg

.PHONY: all clean

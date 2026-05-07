VESC_TOOL ?= vesc_tool
VERSION := $(shell sed -n 's/.*Version \([0-9][0-9.]*\).*/\1/p' ui.qml | head -n 1)
DEV_PKG := UCLights-V$(VERSION).vescpkg

all: UCLights.vescpkg

UCLights.vescpkg: pkgdesc.qml README.md UCLights.lisp ui.qml
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml

dev:
	$(VESC_TOOL) --buildPkg "$(DEV_PKG):UCLights.lisp:ui.qml:0:README.md:UCLights"

clean:
	rm -f UCLights*.vescpkg

.PHONY: all dev clean
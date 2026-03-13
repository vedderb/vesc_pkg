VESC_TOOL ?= vesc_tool
VERSION := $(shell sed -n 's/.*Version \([0-9][0-9.]*\).*/\1/p' ui.qml | head -n 1)
PKG_NAME := UCLights-V$(VERSION).vescpkg

all: clean $(PKG_NAME)

$(PKG_NAME):
	$(VESC_TOOL) --buildPkg "$(PKG_NAME):UCLights.lisp:ui.qml:0:README.md:UCLights"

clean:
	rm -f UCLights*.vescpkg

.PHONY: all clean
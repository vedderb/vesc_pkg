# Requires a VESC Tool binary. Point VESC_TOOL at it if it is not on PATH, e.g.
#   make VESC_TOOL="/Applications/VESC Tool.app/Contents/MacOS/VESC Tool"
VESC_TOOL ?= vesc_tool

all: mqttcan4vesc.vescpkg

mqttcan4vesc.vescpkg: pkgdesc.qml mqttcan4vesc.lisp ui.qml README.md
	"$(VESC_TOOL)" --buildPkgFromDesc pkgdesc.qml

clean:
	rm -f mqttcan4vesc.vescpkg

.PHONY: all clean

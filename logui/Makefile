VESC_TOOL ?= vesc_tool

all: logui.vescpkg

logui.vescpkg:
	$(VESC_TOOL) --buildPkg "logui.vescpkg:logger.lisp:ui.qml:0:README.md:LogUI"

clean:
	rm -f logui.vescpkg

.PHONY: all clean

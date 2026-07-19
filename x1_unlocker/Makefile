VESC_TOOL ?= vesc_tool

all: x1_unlocker.vescpkg

x1_unlocker.vescpkg:
	$(VESC_TOOL) --buildPkg "x1_unlocker.vescpkg:script.lisp::0:README.md:X1-Unlocker"

clean:
	rm -f x1_unlocker.vescpkg

.PHONY: all clean

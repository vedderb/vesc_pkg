VESC_TOOL ?= vesc_tool

all: vbms32_micro.vescpkg

vbms32_micro.vescpkg:
	$(VESC_TOOL) --buildPkg "vbms32_micro.vescpkg:vbms32_micro.lisp::0:README.md:VBMS32 Micro"

clean:
	rm -f vbms32_micro.vescpkg

.PHONY: all clean

VESC_TOOL ?= vesc_tool

all: tca9535.vescpkg

tca9535.vescpkg:
	$(VESC_TOOL) --buildPkg "tca9535.vescpkg:tca9535.lisp::0:README.md:TCA9535 Driver"

clean:
	rm -f tca9535.vescpkg

.PHONY: all clean

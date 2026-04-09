VESC_TOOL ?= vesc_tool

all: tca9534.vescpkg

tca9534.vescpkg:
	$(VESC_TOOL) --buildPkg "tca9534.vescpkg:tca9534.lisp::0:README.md:TCA9534 Driver"

clean:
	rm -f tca9534.vescpkg

.PHONY: all clean

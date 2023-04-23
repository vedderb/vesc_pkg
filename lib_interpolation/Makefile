VESC_TOOL ?= vesc_tool

all: interpolation.vescpkg

interpolation.vescpkg: interpolation
	$(VESC_TOOL) --buildPkg "interpolation.vescpkg:interpolation.lisp::0:README.md:Interpolation"

interpolation:
	$(MAKE) -C $@

clean:
	rm -f interpolation.vescpkg
	$(MAKE) -C interpolation clean

.PHONY: all clean interpolation
